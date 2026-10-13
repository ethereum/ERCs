// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

/// @dev ERC-7528 sentinel for the native currency.
address constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

struct AssetLimit {
    address asset;
    uint256 maxPerCall;
    uint256 maxPerWindow;
    uint256 maxTotal;
}

struct SpendGrant {
    address principal;
    address delegate;
    uint8 recipientMode;
    address recipient;
    uint8 assetCombine;
    uint64 windowSeconds;
    AssetLimit[] assets;
    uint64 validAfter;
    uint64 validUntil;
    uint256 salt;
}

/// @dev Align names with ERC-8226 where they match. Extra codes are this ERC's. The numbers are normative
/// (`SpendGrantError(uint8)` carries them) and never change meaning; later versions only append.
/// `BAD_SIGNATURE` (2) is reserved: this version never returns it.
enum Reason {
    OK,
    INVALID_GRANT,
    BAD_SIGNATURE,
    NOT_YET_VALID,
    EXPIRED,
    REVOKED,
    WRONG_ASSET,
    WRONG_RECIPIENT,
    OVER_TX_CAP,
    OVER_WINDOW_CAP,
    OVER_CUMULATIVE_CAP,
    WINDOW_FULL,
    UNAUTHORIZED_EXECUTOR,
    UNAUTHORIZED_DELEGATE,
    NONEXISTENT
}

/// @dev ABI signature `SpendGrantError(uint8)`.
error SpendGrantError(Reason reason);
error NotPrincipal();
error GrantExists(bytes32 grantId);
error UnknownGrant(bytes32 grantId);
error GrantIsRevoked(bytes32 grantId);
error StaleVersion(uint256 current);
error FixedField();
/// @notice `grantState` had too little gas left to give a balance or allowance read its full stipend.
error InsufficientGas();

bytes32 constant REASON_OK = "OK";
bytes32 constant REASON_INVALID_GRANT = "INVALID_GRANT";
/// @dev Reserved; never returned by this version.
bytes32 constant REASON_BAD_SIGNATURE = "BAD_SIGNATURE";
bytes32 constant REASON_NOT_YET_VALID = "NOT_YET_VALID";
bytes32 constant REASON_EXPIRED = "EXPIRED";
bytes32 constant REASON_REVOKED = "REVOKED";
bytes32 constant REASON_WRONG_ASSET = "WRONG_ASSET";
bytes32 constant REASON_WRONG_RECIPIENT = "WRONG_RECIPIENT";
bytes32 constant REASON_OVER_TX_CAP = "OVER_TX_CAP";
bytes32 constant REASON_OVER_WINDOW_CAP = "OVER_WINDOW_CAP";
bytes32 constant REASON_OVER_CUMULATIVE_CAP = "OVER_CUMULATIVE_CAP";
bytes32 constant REASON_WINDOW_FULL = "WINDOW_FULL";
bytes32 constant REASON_UNAUTHORIZED_EXECUTOR = "UNAUTHORIZED_EXECUTOR";
bytes32 constant REASON_UNAUTHORIZED_DELEGATE = "UNAUTHORIZED_DELEGATE";
bytes32 constant REASON_NONEXISTENT = "NONEXISTENT";

uint256 constant MAX_ASSETS = 16;
uint256 constant MAX_LIVE_DEBITS = 1024;

interface IERC1271 {
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4);
}

/// @notice What `grantState` reports for one asset of one grant.
struct GrantState {
    // The first failing condition among NONEXISTENT, NOT_YET_VALID, EXPIRED, REVOKED, WRONG_ASSET and
    // INVALID_GRANT, else OK.
    Reason status;
    // The asset's caps in the current terms; 0 when the grant does not exist or does not list the asset.
    uint256 maxPerCall;
    uint256 maxPerWindow;
    uint256 maxTotal;
    // Lifetime spend (as `usage`).
    uint256 spent;
    // Unexpired spend (as `rollingUsage`).
    uint256 windowSpent;
    // Unexpired debit count (as `rollingUsage`).
    uint256 liveDebits;
    // When the oldest unexpired debit expires; 0 if none.
    uint256 nextExpiry;
    // The principal's balance of the asset; 0 when not read or the read failed.
    uint256 balance;
    // The principal's ERC-20 allowance to the executor; 0 when not read or the read failed;
    // `type(uint256).max` for NATIVE.
    uint256 allowance;
    bool balanceKnown;
    bool allowanceKnown;
    // 0 unless `status` is OK; otherwise the least of the window and lifetime room, the room left in
    // the live-debit bound, `balance` and `allowance`.
    uint256 spendableNow;
}

interface ISpendGrantRegistry {
    event GrantRegistered(
        bytes32 indexed grantId, address indexed principal, address indexed delegate, SpendGrant terms
    );
    event GrantUpdated(
        bytes32 indexed grantId, address indexed principal, address indexed delegate, uint256 version, SpendGrant terms
    );
    event GrantRevoked(bytes32 indexed grantId, address indexed principal, address indexed delegate);
    event GrantConsumed(
        bytes32 indexed grantId, address indexed principal, address asset, uint256 amount, address indexed recipient
    );

    function executor() external view returns (address);
    /// @notice The id `register(terms)` would assign. Validates nothing.
    function hashGrant(SpendGrant calldata terms) external view returns (bytes32);
    function register(SpendGrant calldata terms) external returns (bytes32 grantId);
    function update(bytes32 grantId, uint256 expectedVersion, SpendGrant calldata terms) external;
    function revoke(bytes32 grantId) external;
    function revoked(bytes32 grantId) external view returns (bool);
    function getGrant(bytes32 grantId)
        external
        view
        returns (SpendGrant memory terms, uint256 version, uint256 createdAt, uint256 updatedAt, bool isRevoked);
    function parties(bytes32 grantId) external view returns (address principal, address delegate);
    function grantsOf(address principal, uint256 offset, uint256 limit)
        external
        view
        returns (bytes32[] memory grantIds, uint256 total);
    function grantsTo(address delegate, uint256 offset, uint256 limit)
        external
        view
        returns (bytes32[] memory grantIds, uint256 total);
    function usage(bytes32 grantId, address asset) external view returns (uint256 spent, uint256 calls);
    function rollingUsage(bytes32 grantId, address asset) external view returns (uint256 spent, uint256 calls);
    function liveDebits(bytes32 grantId, address asset, uint256 maxCount)
        external
        view
        returns (uint256[] memory expiresAt, uint256[] memory amounts);
    function evict(bytes32 grantId, address asset, uint256 maxCount) external;
    function grantState(bytes32 grantId, address asset) external view returns (GrantState memory);
    function check(bytes32 grantId, address authorizer, address asset, uint256 amount, address recipient)
        external
        view
        returns (bool ok, Reason reason);
    function consume(bytes32 grantId, address authorizer, address asset, uint256 amount, address recipient) external;
}
