// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.24;

/// @title ITwoPhaseEscrow — asset-agnostic two-phase ("2FA") transfer escrow.
/// @notice The standalone-escrow embodiment of the two-phase transfer ERC: retrofits
///         the initiate → accept lifecycle onto assets that cannot be modified —
///         native ETH and ANY already-deployed ERC-20, ERC-721, or ERC-1155. The
///         escrow takes custody while pending; the bound receiver accepts (optionally
///         proving an out-of-band secret key by signature); the sender may revoke
///         anytime while pending and reclaim after expiry.
///
/// @dev Same lifecycle, commit model, and assumptions as the token-native
///      IERC20TwoPhase / IERC721TwoPhase extensions; only custody differs (escrow
///      balance instead of internal token state).
interface ITwoPhaseEscrow {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    enum Status {
        None, // 0 — slot never used
        Pending, // 1 — asset escrowed, awaiting accept / revoke / reclaim
        Accepted, // 2 — receiver accepted; asset delivered
        Revoked, // 3 — sender revoked while pending
        Reclaimed // 4 — sender reclaimed after expiry
    }

    enum AssetType {
        Native, // ETH (or the chain's native currency)
        ERC20,
        ERC721,
        ERC1155
    }

    struct Asset {
        AssetType kind;
        address token; // asset contract; MUST be address(0) for Native
        uint256 tokenId; // ERC-721 / ERC-1155 id; MUST be 0 otherwise
        uint256 amount; // wei / token units / ERC-1155 units; MUST be 1 for ERC-721
    }

    struct PendingTransfer {
        address from;
        address to;
        Asset asset;
        uint64 expiry; // unix seconds
        Status status;
        address commit; // address of the secret key; address(0) => plain mode
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a sender escrows an asset into pending state.
    /// @dev `commit` is address(0) for plain-mode transfers; non-zero for committed ones.
    event TransferInitiated(
        uint256 indexed id,
        address indexed from,
        address indexed to,
        Asset asset,
        uint64 expiry,
        address commit
    );

    /// @notice Emitted when the bound receiver accepts and the asset is delivered.
    event TransferAccepted(uint256 indexed id);

    /// @notice Emitted when the sender revokes a still-pending transfer.
    event TransferRevoked(uint256 indexed id);

    /// @notice Emitted when the sender reclaims an expired, unaccepted transfer.
    event TransferReclaimed(uint256 indexed id);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error BadExpiry(); // expiry outside [now+MIN_EXPIRY, now+MAX_EXPIRY]
    error BadAmount(); // zero amount, ERC-721 amount != 1, or msg.value mismatch
    error BadReceiver(); // zero receiver, or receiver == sender
    error BadAsset(); // asset fields inconsistent with kind (token / tokenId rules)
    error NotReceiver(); // accept by non-receiver
    error NotSender(); // revoke / reclaim by non-sender
    error NotPending(); // transfer is not in Pending state
    error NotExpired(); // reclaim before expiry
    error BadCommit(); // commit == address(0) on initiateTransferWithCommit (client bug)
    error SecretRequired(); // plain accept on a committed transfer
    error BadSecret(); // signature doesn't recover to the committed secret address
    error NativeTransferFailed(); // ETH payout call failed

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Escrow `asset` from the caller into a pending transfer bound to `to`.
    /// @dev Native: send the amount as msg.value (asset.token/tokenId zero). Tokens:
    ///      approve the escrow first; msg.value MUST be zero.
    /// @return id Monotonic identifier for this pending transfer.
    function initiateTransfer(Asset calldata asset, address to, uint64 expiry)
        external
        payable
        returns (uint256 id);

    /// @notice Like `initiateTransfer`, but additionally commits to a throwaway
    ///         secret key (commit = its address). Settlement then requires the
    ///         receiver's account key AND a signature by the secret key.
    /// @dev The secret key itself NEVER appears on-chain (see the ERC draft's
    ///      Assumptions). If `to` is unowned or mistyped, revoke or reclaim.
    /// @param commit Address derived from the secret key; MUST NOT be address(0).
    function initiateTransferWithCommit(
        Asset calldata asset,
        address to,
        uint64 expiry,
        address commit
    ) external payable returns (uint256 id);

    /// @notice Bound receiver accepts a plain (no-commit) transfer. Receiver-only.
    /// @dev MUST revert with `SecretRequired` if the transfer carries a commit.
    function acceptTransfer(uint256 id) external;

    /// @notice Bound receiver accepts a committed transfer by proving knowledge of
    ///         the secret key: `secretSig` is that key's ECDSA signature over
    ///         `keccak256(abi.encode(block.chainid, address(this), id, msg.sender))`.
    /// @dev Receiver check MUST run before the signature check; the digest binds
    ///      msg.sender, so an observed signature is non-replayable by anyone else.
    function acceptTransfer(uint256 id, bytes calldata secretSig) external;

    /// @notice Sender revokes a still-pending transfer, refunding themselves. Sender-only.
    function revokeTransfer(uint256 id) external;

    /// @notice Sender reclaims an unaccepted transfer after expiry. Sender-only.
    function reclaimExpired(uint256 id) external;

    /// @notice Read the full record for a pending-transfer id.
    function pendingTransfer(uint256 id) external view returns (PendingTransfer memory);

    /// @notice The digest the secret key must sign for `caller` to accept transfer `id`.
    function acceptDigest(uint256 id, address caller) external view returns (bytes32);
}
