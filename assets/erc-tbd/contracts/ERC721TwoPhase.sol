// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.24;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IERC721TwoPhase } from "./IERC721TwoPhase.sol";

/// @title ERC721TwoPhase — abstract opt-in two-phase transfer extension over OZ ERC721.
/// @notice Adds `initiateTransfer` / `acceptTransfer` / `revokeTransfer` /
///         `reclaimExpired` keyed by `tokenId`. Plain `transferFrom` /
///         `safeTransferFrom` stay atomic, but are BLOCKED for a pending tokenId.
///
/// @dev Lock model (design decision): ownership is NOT moved to the contract while
///      pending — it stays with the sender, so `ownerOf`, metadata, and marketplace
///      approval queries keep returning sensible values. The token is instead LOCKED:
///      `_update` reverts for any locked tokenId. `acceptTransfer` (and only it) sets
///      a transient `_settling` flag to let the ownership-moving `_update` through.
abstract contract ERC721TwoPhase is ERC721, IERC721TwoPhase {
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

    /// @dev tokenId → pending id while locked; 0 when unlocked.
    mapping(uint256 tokenId => uint256 id) private _lockOf;

    uint256 private _nextId;

    /// @dev Transient bypass — set only inside `acceptTransfer` so the settlement
    ///      `_transfer` can move a still-locked token exactly once.
    bool private _settling;

    /*//////////////////////////////////////////////////////////////
                              INITIATE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC721TwoPhase
    function initiateTransfer(address to, uint256 tokenId, uint64 expiry)
        external
        virtual
        returns (uint256 id)
    {
        return _initiate(to, tokenId, expiry, address(0));
    }

    /// @inheritdoc IERC721TwoPhase
    function initiateTransferWithCommit(address to, uint256 tokenId, uint64 expiry, address commit)
        external
        virtual
        returns (uint256 id)
    {
        if (commit == address(0)) revert BadCommit();
        return _initiate(to, tokenId, expiry, commit);
    }

    /// @dev Shared initiate path. `commit == address(0)` means plain mode; non-zero
    ///      means committed mode (receiver key AND a signature by the secret key).
    function _initiate(address to, uint256 tokenId, uint64 expiry, address commit)
        private
        returns (uint256 id)
    {
        if (to == address(0) || to == msg.sender) revert BadReceiver();
        if (expiry < block.timestamp + MIN_EXPIRY) revert BadExpiry();
        if (expiry > block.timestamp + MAX_EXPIRY) revert BadExpiry();
        if (_lockOf[tokenId] != 0) revert AlreadyPending();

        // Authorization: caller must own or be approved for the token. Reverts with
        // ERC721NonexistentToken if the id was never minted.
        address owner = ownerOf(tokenId);
        if (!_isAuthorized(owner, msg.sender, tokenId)) revert NotOwner();

        id = ++_nextId;

        _pending[id] = PendingTransfer({
            from: owner,
            to: to,
            tokenId: tokenId,
            expiry: expiry,
            status: Status.Pending,
            commit: commit
        });
        _lockOf[tokenId] = id; // lock: any _update now reverts until settled

        emit TransferInitiated(id, owner, to, tokenId, expiry, commit);
    }

    /*//////////////////////////////////////////////////////////////
                               ACCEPT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC721TwoPhase
    function acceptTransfer(uint256 id) external virtual {
        PendingTransfer storage t = _pending[id];
        if (t.status != Status.Pending) revert NotPending();
        if (msg.sender != t.to) revert NotReceiver();
        if (t.commit != address(0)) revert SecretRequired();

        _settle(id, t);
    }

    /// @inheritdoc IERC721TwoPhase
    /// @dev The secret key never touches the chain: the receiver proves knowledge by
    ///      signing a digest binding chainid, this contract, the transfer id, AND the
    ///      caller. A mistaken submission from the wrong account leaks only a
    ///      signature over that wrong address — non-replayable by anyone. Receiver
    ///      check still runs BEFORE the signature check.
    function acceptTransfer(uint256 id, bytes calldata secretSig) external virtual {
        PendingTransfer storage t = _pending[id];
        if (t.status != Status.Pending) revert NotPending();
        if (msg.sender != t.to) revert NotReceiver();

        (address recovered,,) = ECDSA.tryRecover(_acceptDigest(id, msg.sender), secretSig);
        if (t.commit == address(0) || recovered != t.commit) revert BadSecret();

        _settle(id, t);
    }

    /// @dev Digest the secret key must sign for `caller` to accept transfer `id`.
    function _acceptDigest(uint256 id, address caller) internal view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, address(this), id, caller));
    }

    /// @notice Public helper for clients: the digest to sign with the secret key.
    function acceptDigest(uint256 id, address caller) external view returns (bytes32) {
        return _acceptDigest(id, caller);
    }

    /// @dev Shared settlement: unlock, then move ownership through the guarded _update.
    function _settle(uint256 id, PendingTransfer storage t) private {
        t.status = Status.Accepted;

        uint256 tokenId = t.tokenId;
        address from = t.from;
        address to = t.to;

        // Effects: clear the lock before the move so _update's guard passes cleanly,
        // and use the transient flag as belt-and-suspenders (order-independent).
        _lockOf[tokenId] = 0;

        _settling = true;
        _transfer(from, to, tokenId); // emits standard ERC-721 Transfer
        _settling = false;

        emit TransferAccepted(id);
    }

    /*//////////////////////////////////////////////////////////////
                          REVOKE / RECLAIM
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC721TwoPhase
    function revokeTransfer(uint256 id) external virtual {
        PendingTransfer storage t = _pending[id];
        if (t.status != Status.Pending) revert NotPending();
        if (msg.sender != t.from) revert NotSender();

        t.status = Status.Revoked;
        _lockOf[t.tokenId] = 0; // unlock; ownership was never moved

        emit TransferRevoked(id);
    }

    /// @inheritdoc IERC721TwoPhase
    function reclaimExpired(uint256 id) external virtual {
        PendingTransfer storage t = _pending[id];
        if (t.status != Status.Pending) revert NotPending();
        if (msg.sender != t.from) revert NotSender();
        if (block.timestamp <= t.expiry) revert NotExpired();

        t.status = Status.Reclaimed;
        _lockOf[t.tokenId] = 0;

        emit TransferReclaimed(id);
    }

    /*//////////////////////////////////////////////////////////////
                                VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC721TwoPhase
    function pendingTransfer(uint256 id) external view returns (PendingTransfer memory) {
        return _pending[id];
    }

    /// @inheritdoc IERC721TwoPhase
    function isLocked(uint256 tokenId) public view returns (bool) {
        return _lockOf[tokenId] != 0;
    }

    /*//////////////////////////////////////////////////////////////
                              OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @dev Lock enforcement. A pending tokenId cannot be transferred by any plain
    ///      ERC-721 path; only `acceptTransfer` (which sets `_settling`) may move it.
    ///      Mints and burns of unrelated tokens are unaffected.
    function _update(address to, uint256 tokenId, address auth)
        internal
        virtual
        override
        returns (address)
    {
        if (_lockOf[tokenId] != 0 && !_settling) revert TokenLocked();
        return super._update(to, tokenId, auth);
    }

    /// @notice ERC-165: advertise IERC721TwoPhase in addition to inherited ERC-721/165.
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC721TwoPhase).interfaceId || super.supportsInterface(interfaceId);
    }
}
