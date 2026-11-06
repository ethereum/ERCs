// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.24;

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IFrameConsentGuard } from "./IFrameConsentGuard.sol";
import { IFrameIntrospector } from "./IFrameIntrospector.sol";

/// @title FrameConsentGuard: receiver-attested transfers without escrow (EIP-8141).
/// @notice Runs as a DEFAULT frame flagged ATOMIC_BATCH, directly before the SENDER frame
///         that moves the asset. It reverts unless that next frame is exactly the transfer the
///         receiver signed. The atomic batch then skips the transfer, so nothing moves.
///
/// @dev Design decisions:
///      - No custody, no owner, no upgradability. The only state is the used stamp.
///      - Check order: atomic flag, next frame, tx sender, deadline, asset, frame match,
///        stamp, signature. `WrongSender` precedes any stamp access, so nobody but the
///        consented sender can consume a consent.
///      - The stamp is written in the same atomic batch as the transfer: if the transfer
///        frame fails, the stamp rolls back and the consent stays usable.
contract FrameConsentGuard is IFrameConsentGuard, EIP712, ERC165 {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev EIP-8141 frame mode SENDER (caller = tx.sender).
    uint256 internal constant MODE_SENDER = 2;

    /// @dev EIP-8141 ATOMIC_BATCH_FLAG (flags bit 2).
    uint256 internal constant ATOMIC_BATCH_FLAG = 0x4;

    bytes32 public constant CONSENT_TYPEHASH = keccak256(
        "TransferConsent(address sender,address receiver,uint8 kind,address token,"
        "uint256 tokenId,uint256 amount,bytes32 challenge,uint64 deadline)"
    );

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Read-only view of the current frame transaction.
    IFrameIntrospector public immutable frames;

    /// @dev Consent digest → paid out.
    mapping(bytes32 digest => bool) private _used;

    constructor(IFrameIntrospector frames_) EIP712("FrameConsentGuard", "1") {
        frames = frames_;
    }

    /*//////////////////////////////////////////////////////////////
                                 CHECK
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFrameConsentGuard
    function check(Consent calldata c, bytes calldata receiverSig) external {
        uint256 me = frames.currentFrameIndex();
        if (frames.frameFlags(me) & ATOMIC_BATCH_FLAG == 0) revert NotAtomic();

        uint256 t = me + 1; // ATOMIC_BATCH guarantees frame me+1 exists and is not VERIFY
        if (frames.frameMode(t) != MODE_SENDER) revert BadTransferFrame();
        if (frames.txSender() != c.sender) revert WrongSender();
        if (block.timestamp > c.deadline) revert ConsentExpired();

        _validateAsset(c);
        _matchTransferFrame(t, c);

        bytes32 digest = _consentDigest(c);
        if (_used[digest]) revert AlreadyUsed();
        if (!SignatureChecker.isValidSignatureNow(c.receiver, digest, receiverSig)) {
            revert BadConsent();
        }
        _used[digest] = true;

        emit ConsentUsed(digest, c.sender, c.receiver);
    }

    /// @dev Per-kind field consistency, mirroring the former escrow's Asset rules.
    function _validateAsset(Consent calldata c) private pure {
        if (c.receiver == address(0) || c.receiver == c.sender) revert BadAsset();
        if (c.kind == AssetKind.Native) {
            if (c.token != address(0) || c.tokenId != 0 || c.amount == 0) revert BadAsset();
        } else {
            if (c.token == address(0)) revert BadAsset();
            if (c.kind == AssetKind.ERC20) {
                if (c.tokenId != 0 || c.amount == 0) revert BadAsset();
            } else if (c.kind == AssetKind.ERC721) {
                if (c.amount != 1) revert BadAsset();
            } else if (c.amount == 0) {
                revert BadAsset(); // ERC1155
            }
        }
    }

    /// @dev The next frame must be exactly the consented transfer: same target, value and
    ///      calldata. Reading the frame itself (not a parameter) is what catches a typo'd `to`.
    function _matchTransferFrame(uint256 t, Consent calldata c) private view {
        address target = frames.frameTarget(t);
        uint256 value = frames.frameValue(t);
        bytes memory data = frames.frameData(t);

        bool ok;
        if (c.kind == AssetKind.Native) {
            // Plain value send straight to the receiver, no calldata.
            ok = target == c.receiver && value == c.amount && data.length == 0;
        } else if (c.kind == AssetKind.ERC20) {
            // SENDER mode: caller is tx.sender, so plain transfer(receiver, amount).
            ok = target == c.token && value == 0
                && keccak256(data) == keccak256(abi.encodeCall(IERC20.transfer, (c.receiver, c.amount)));
        } else {
            ok = target == c.token && value == 0 && _matchNftCall(data, c);
        }

        if (!ok) revert BadTransferFrame();
    }

    /// @dev ERC-721 / ERC-1155: does `data` (the SENDER frame's calldata, called on c.token)
    ///      move exactly c.tokenId (and c.amount for 1155) from c.sender to c.receiver?
    ///
    ///      Decide which call shapes count as "the consented transfer":
    ///        ERC-721:  transferFrom(from,to,id)
    ///                  safeTransferFrom(from,to,id)
    ///                  safeTransferFrom(from,to,id,bytes data)
    ///        ERC-1155: safeTransferFrom(from,to,id,amount,bytes data)
    ///      Exact-bytes comparison via abi.encodeCall (as the ERC-20 branch does) is the
    ///      simplest strict option, but the trailing `bytes data` argument is chosen by the
    ///      sender and isn't part of the consent, so exact matching forces it to "".
    ///      Returning false is always safe (the transfer is skipped).
    function _matchNftCall(bytes memory data, Consent calldata c) private pure returns (bool) {
        // TODO(user): implement the ERC-721 and ERC-1155 branches.
        data;
        c;
        return false;
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IFrameConsentGuard
    function consentDigest(Consent calldata c) external view returns (bytes32) {
        return _consentDigest(c);
    }

    /// @inheritdoc IFrameConsentGuard
    function isUsed(bytes32 digest) external view returns (bool) {
        return _used[digest];
    }

    function _consentDigest(Consent calldata c) private view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    CONSENT_TYPEHASH,
                    c.sender,
                    c.receiver,
                    c.kind,
                    c.token,
                    c.tokenId,
                    c.amount,
                    c.challenge,
                    c.deadline
                )
            )
        );
    }

    /// @notice ERC-165: advertise IFrameConsentGuard so wallets can detect the guard.
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IFrameConsentGuard).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
