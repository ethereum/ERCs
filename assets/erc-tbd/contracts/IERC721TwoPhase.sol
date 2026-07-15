// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.24;

/// @title IERC721TwoPhase — opt-in two-phase ("2FA") transfer extension for ERC-721.
/// @notice A sender *initiates* a transfer of a `tokenId` bound to a receiver; the
///         token is LOCKED (non-transferable) but ownership stays with the sender
///         until the receiver *accepts*, at which point ownership moves. While pending
///         the sender may revoke; after expiry the sender may reclaim (unlock).
///
/// @dev Design decision — ownership stays with the sender while pending (not moved to
///      the contract). Marketplaces and `ownerOf` / metadata queries keep working; the
///      token is merely locked against transfer. `acceptTransfer` performs the real
///      ownership move. Plain `transferFrom` / `safeTransferFrom` stay atomic and are
///      simply blocked for a pending tokenId.
///
/// @dev ERC-165 interface id: `type(IERC721TwoPhase).interfaceId`.
interface IERC721TwoPhase {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    enum Status {
        None, // 0 — no pending transfer for this id
        Pending, // 1 — token locked, awaiting accept / revoke / reclaim
        Accepted, // 2 — receiver accepted; ownership moved
        Revoked, // 3 — sender revoked while pending
        Reclaimed // 4 — sender reclaimed after expiry
    }

    struct PendingTransfer {
        address from;
        address to;
        uint256 tokenId;
        uint64 expiry; // unix seconds
        Status status;
        address commit; // address of the secret key; address(0) => plain (no-secret) mode
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @dev `commit` is address(0) for plain-mode transfers; non-zero for committed ones.
    event TransferInitiated(
        uint256 indexed id,
        address indexed from,
        address indexed to,
        uint256 tokenId,
        uint64 expiry,
        address commit
    );

    /// @notice Emitted when the receiver accepts. A standard ERC-721 `Transfer`
    ///         event (from sender to receiver) is emitted alongside this.
    event TransferAccepted(uint256 indexed id);

    event TransferRevoked(uint256 indexed id);

    event TransferReclaimed(uint256 indexed id);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error BadExpiry(); // expiry outside [now+MIN_EXPIRY, now+MAX_EXPIRY]
    error BadReceiver(); // zero receiver, or receiver == sender
    error NotOwner(); // initiate by non-owner (and not approved)
    error NotReceiver(); // accept by non-receiver
    error NotSender(); // revoke / reclaim by non-sender
    error NotPending(); // transfer is not in Pending state
    error NotExpired(); // reclaim before expiry
    error AlreadyPending(); // tokenId already has a pending transfer
    error TokenLocked(); // plain transfer attempted on a pending tokenId
    error BadCommit(); // commit == address(0) on initiateTransferWithCommit (client bug)
    error SecretRequired(); // plain accept on a committed transfer
    error BadSecret(); // signature doesn't recover to the committed secret address

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Lock `tokenId` and create a pending transfer bound to `to`.
    /// @dev Caller must be the owner or approved. Ownership is unchanged; the token is
    ///      locked against plain transfers until settled.
    /// @return id Monotonic identifier for this pending transfer.
    function initiateTransfer(address to, uint256 tokenId, uint64 expiry)
        external
        returns (uint256 id);

    /// @notice Like `initiateTransfer`, but additionally binds a secret-key commitment.
    ///         The "secret" delivered out-of-band is a throwaway PRIVATE KEY; `commit`
    ///         is its address. Settlement then requires BOTH the receiver's account
    ///         key AND a signature by the secret key (see `acceptTransfer(id, sig)`).
    /// @dev The secret key itself NEVER appears on-chain — not in calldata, not on
    ///      revert. A mistaken submission from the wrong account leaks only a
    ///      signature bound to that account, unusable by anyone else. If `to` is
    ///      unowned or mistyped, the only correct actions are `revokeTransfer` or
    ///      `reclaimExpired`.
    /// @param commit Address derived from the secret key; MUST NOT be address(0).
    function initiateTransferWithCommit(address to, uint256 tokenId, uint64 expiry, address commit)
        external
        returns (uint256 id);

    /// @notice Bound receiver accepts a plain (no-commit) transfer. Receiver-only.
    /// @dev MUST revert with `SecretRequired` if the transfer carries a commit.
    function acceptTransfer(uint256 id) external;

    /// @notice Bound receiver accepts a committed transfer by proving knowledge of
    ///         the secret key: `secretSig` is that key's ECDSA signature over
    ///         `keccak256(abi.encode(block.chainid, address(this), id, msg.sender))`.
    /// @dev Receiver check MUST run before the signature check. The signed digest
    ///      includes chainid, token, id, and msg.sender, so an observed signature
    ///      cannot be replayed by any other caller, transfer, or chain.
    function acceptTransfer(uint256 id, bytes calldata secretSig) external;

    /// @notice Sender revokes a still-pending transfer, unlocking the token. Sender-only.
    function revokeTransfer(uint256 id) external;

    /// @notice Sender reclaims (unlocks) an unaccepted transfer after expiry. Sender-only.
    function reclaimExpired(uint256 id) external;

    /// @notice Read the full record for a pending-transfer id.
    function pendingTransfer(uint256 id) external view returns (PendingTransfer memory);

    /// @notice Whether `tokenId` currently has a pending (locked) transfer.
    function isLocked(uint256 tokenId) external view returns (bool);
}
