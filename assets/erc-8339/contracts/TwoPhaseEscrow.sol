// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.24;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { ERC1155Holder } from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { ITwoPhaseEscrow } from "./ITwoPhaseEscrow.sol";

/// @title TwoPhaseEscrow: asset-agnostic two-phase transfer escrow.
/// @notice Retrofits the two-phase (initiate -> accept) lifecycle onto assets that
///         cannot be modified: native ETH and any already-deployed ERC-20, ERC-721,
///         or ERC-1155. Custody model: the escrow holds the asset while pending;
///         `acceptTransfer` / `revokeTransfer` / `reclaimExpired` are the only paths
///         that move it out.
///
/// @dev Design decisions:
///      - ERC-721 payouts use plain `transferFrom` (not safe*) so a receiver who
///        actively chose to accept cannot be griefed by their own missing
///        onERC721Received; ERC-1155 has no unsafe variant, but there the recipient
///        initiated the call themselves, and `nonReentrant` guards the callback.
///      - Every transfer commits to an out-of-band secret: a throwaway private key,
///        proven at accept time by signature over a caller-bound digest, never
///        revealed on-chain.
contract TwoPhaseEscrow is ITwoPhaseEscrow, ERC1155Holder, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Minimum receiver window, relative to now (see PendingTransfers rationale).
    uint64 public constant MIN_EXPIRY = 10 minutes;

    /// @notice Maximum receiver window, relative to now.
    uint64 public constant MAX_EXPIRY = 7 days;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Monotonic id → pending transfer. First id is 1 (0 is a sentinel).
    mapping(uint256 id => PendingTransfer) private _pending;

    uint256 private _nextId;

    /*//////////////////////////////////////////////////////////////
                              INITIATE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ITwoPhaseEscrow
    function initiateTransfer(Asset calldata asset, address to, uint64 expiry, address commit)
        external
        payable
        nonReentrant
        returns (uint256 id)
    {
        if (commit == address(0)) revert BadCommit();
        return _initiate(asset, to, expiry, commit);
    }

    /// @dev Shared initiate path: validate, record, then pull custody (CEI: the
    ///      pull is the interaction; state is final before any external call).
    function _initiate(Asset calldata asset, address to, uint64 expiry, address commit)
        private
        returns (uint256 id)
    {
        if (to == address(0) || to == msg.sender) revert BadReceiver();
        if (expiry < block.timestamp + MIN_EXPIRY) revert BadExpiry();
        if (expiry > block.timestamp + MAX_EXPIRY) revert BadExpiry();
        _validateAsset(asset);

        id = ++_nextId;

        _pending[id] = PendingTransfer({
            from: msg.sender,
            to: to,
            asset: asset,
            expiry: expiry,
            status: Status.Pending,
            commit: commit
        });

        _pullCustody(asset);

        emit TransferInitiated(id, msg.sender, to, asset, expiry, commit);
    }

    /// @dev Per-kind field consistency. Native carries value in msg.value; every
    ///      token kind must send zero value so ETH can never be stranded here.
    function _validateAsset(Asset calldata asset) private view {
        if (asset.kind == AssetType.Native) {
            if (asset.token != address(0) || asset.tokenId != 0) revert BadAsset();
            if (asset.amount == 0 || msg.value != asset.amount) revert BadAmount();
        } else {
            if (asset.token == address(0)) revert BadAsset();
            if (msg.value != 0) revert BadAmount();
            if (asset.kind == AssetType.ERC20) {
                if (asset.tokenId != 0) revert BadAsset();
                if (asset.amount == 0) revert BadAmount();
            } else if (asset.kind == AssetType.ERC721) {
                if (asset.amount != 1) revert BadAmount();
            } else {
                // ERC1155
                if (asset.amount == 0) revert BadAmount();
            }
        }
    }

    /// @dev Move the asset from the sender into escrow custody.
    function _pullCustody(Asset calldata asset) private {
        if (asset.kind == AssetType.Native) {
            return; // msg.value already sits on this contract
        }
        if (asset.kind == AssetType.ERC20) {
            IERC20(asset.token).safeTransferFrom(msg.sender, address(this), asset.amount);
        } else if (asset.kind == AssetType.ERC721) {
            IERC721(asset.token).transferFrom(msg.sender, address(this), asset.tokenId);
        } else {
            IERC1155(asset.token)
                .safeTransferFrom(msg.sender, address(this), asset.tokenId, asset.amount, "");
        }
    }

    /*//////////////////////////////////////////////////////////////
                               ACCEPT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ITwoPhaseEscrow
    /// @dev Receiver check BEFORE signature verification; the digest binds
    ///      msg.sender, so leaked/observed signatures are worthless to anyone else.
    function acceptTransfer(uint256 id, bytes calldata secretSig) external nonReentrant {
        PendingTransfer storage t = _pending[id];
        if (t.status != Status.Pending) revert NotPending();
        if (msg.sender != t.to) revert NotReceiver();

        (address recovered,,) = ECDSA.tryRecover(_acceptDigest(id, msg.sender), secretSig);
        if (recovered != t.commit) revert BadSecret();

        _settle(id, t, Status.Accepted, t.to);
        emit TransferAccepted(id);
    }

    /*//////////////////////////////////////////////////////////////
                          REVOKE / RECLAIM
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ITwoPhaseEscrow
    function revokeTransfer(uint256 id) external nonReentrant {
        PendingTransfer storage t = _pending[id];
        if (t.status != Status.Pending) revert NotPending();
        if (msg.sender != t.from) revert NotSender();

        _settle(id, t, Status.Revoked, t.from);
        emit TransferRevoked(id);
    }

    /// @inheritdoc ITwoPhaseEscrow
    function reclaimExpired(uint256 id) external nonReentrant {
        PendingTransfer storage t = _pending[id];
        if (t.status != Status.Pending) revert NotPending();
        if (msg.sender != t.from) revert NotSender();
        if (block.timestamp <= t.expiry) revert NotExpired();

        _settle(id, t, Status.Reclaimed, t.from);
        emit TransferReclaimed(id);
    }

    /// @dev Shared settlement: finalize status (effects), then deliver (interaction).
    function _settle(uint256, PendingTransfer storage t, Status newStatus, address recipient)
        private
    {
        t.status = newStatus;

        Asset memory asset = t.asset;
        if (asset.kind == AssetType.Native) {
            (bool ok,) = recipient.call{ value: asset.amount }("");
            if (!ok) revert NativeTransferFailed();
        } else if (asset.kind == AssetType.ERC20) {
            IERC20(asset.token).safeTransfer(recipient, asset.amount);
        } else if (asset.kind == AssetType.ERC721) {
            IERC721(asset.token).transferFrom(address(this), recipient, asset.tokenId);
        } else {
            IERC1155(asset.token)
                .safeTransferFrom(address(this), recipient, asset.tokenId, asset.amount, "");
        }
    }

    /*//////////////////////////////////////////////////////////////
                                VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ITwoPhaseEscrow
    function pendingTransfer(uint256 id) external view returns (PendingTransfer memory) {
        return _pending[id];
    }

    /// @inheritdoc ITwoPhaseEscrow
    function acceptDigest(uint256 id, address caller) external view returns (bytes32) {
        return _acceptDigest(id, caller);
    }

    /// @dev Layout mirrors the token-native extensions: chainid + verifying contract
    ///      + transfer id + caller.
    function _acceptDigest(uint256 id, address caller) private view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, address(this), id, caller));
    }

    /// @notice ERC-165: advertise ITwoPhaseEscrow alongside the inherited
    ///         ERC1155Receiver/ERC165 support, so wallets can detect the escrow.
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return
            interfaceId == type(ITwoPhaseEscrow).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @dev No receive()/fallback: ETH enters only via initiate (msg.value == amount),
    ///      so the escrow can never hold funds that no transfer record owns.
}
