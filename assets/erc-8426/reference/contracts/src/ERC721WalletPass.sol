// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IERC721WalletPass} from "./IERC721WalletPass.sol";

/// @title ERC721WalletPass
/// @notice Minimal reference implementation of the ERC-721 Wallet Pass
///  Extension. It is written to teach the standard, not to ship a product:
///  everything here is the smallest surface that exercises the interface.
/// @dev The on-chain half of the standard is only discovery and freshness
///  signalling: `passURI` points at an off-chain manifest, and the pass
///  events tell distributors that pass content is stale. Pass generation,
///  signing, and delivery all live off chain and are demonstrated in the
///  companion server.
contract ERC721WalletPass is ERC721, Ownable, IERC721WalletPass {
    using Strings for uint256;

    /// @dev Base endpoint the per-token manifest lives under. `passURI`
    ///  appends the decimal token id, mirroring how `tokenURI` composes a
    ///  metadata URL from a base. In a real deployment this base encodes the
    ///  chain and contract so the endpoint can resolve a manifest without
    ///  further context, for example
    ///  "https://passes.example/eip155/8453/0xCollection/".
    string private _passBaseURI;

    /// @dev Base endpoint for ERC-721 metadata, consumed by `tokenURI`.
    string private _metadataBaseURI;

    /// @dev One tiny piece of mutable, pass-rendered state per token. A real
    ///  collection might render a countdown, a balance, or a standing here;
    ///  a level is enough to show that a change to on-chain state emits
    ///  `PassUpdate` so distributors know to regenerate the pass.
    mapping(uint256 tokenId => uint256) private _levels;

    uint256 private _nextTokenId;

    /// @dev Raised by `refreshPasses` when the range is inverted.
    error InvalidTokenRange(uint256 fromTokenId, uint256 toTokenId);

    constructor(
        string memory name_,
        string memory symbol_,
        string memory metadataBaseURI_,
        string memory passBaseURI_,
        address initialOwner
    ) ERC721(name_, symbol_) Ownable(initialOwner) {
        _metadataBaseURI = metadataBaseURI_;
        _passBaseURI = passBaseURI_;
    }

    /// @notice Mint the next token to `to`.
    /// @dev Minting is owner-gated purely to keep the demo self-contained.
    function mint(address to) external onlyOwner returns (uint256 tokenId) {
        _nextTokenId += 1;
        tokenId = _nextTokenId;
        _safeMint(to, tokenId);
    }

    /// @inheritdoc IERC721WalletPass
    function passURI(uint256 tokenId) external view returns (string memory) {
        _requireOwned(tokenId);
        return string.concat(_passBaseURI, tokenId.toString());
    }

    /// @notice The current pass-rendered level of a token.
    function level(uint256 tokenId) external view returns (uint256) {
        _requireOwned(tokenId);
        return _levels[tokenId];
    }

    /// @notice Increment a token's on-chain level and signal that its pass
    ///  content is now stale.
    /// @dev This mutation is authorized on chain (owner or approved operator).
    ///  That is a separate concern from authorizing an action reached through
    ///  an installed pass, which is off chain and defined by the standard's
    ///  two-check model (control proof plus a fresh ownership read); see the
    ///  companion server. Emitting `PassUpdate` is the whole point of the
    ///  method: pass distributors listen for it and regenerate the pass.
    function levelUp(uint256 tokenId) external {
        address owner = ownerOf(tokenId);
        _checkAuthorized(owner, msg.sender, tokenId);
        _levels[tokenId] += 1;
        emit PassUpdate(tokenId);
    }

    /// @notice Signal that pass content for a consecutive range of tokens has
    ///  changed, for example after an issuer-side art or template refresh that
    ///  touches every pass without changing per-token on-chain state.
    /// @dev Demonstrates `BatchPassUpdate`. The bound is inclusive on both ends.
    function refreshPasses(uint256 fromTokenId, uint256 toTokenId) external onlyOwner {
        if (fromTokenId > toTokenId) {
            revert InvalidTokenRange(fromTokenId, toTokenId);
        }
        emit BatchPassUpdate(fromTokenId, toTokenId);
    }

    /// @inheritdoc ERC721
    function supportsInterface(bytes4 interfaceId) public view override(ERC721) returns (bool) {
        return interfaceId == type(IERC721WalletPass).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @dev Base for `tokenURI`. Kept distinct from the pass base so metadata
    ///  and pass endpoints can be operated independently.
    function _baseURI() internal view override returns (string memory) {
        return _metadataBaseURI;
    }
}
