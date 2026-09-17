// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

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
    bytes32 renderingHash;
}

/// @dev Align names with ERC-8226 where they match. Extra codes are this ERC's.
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
    UNAUTHORIZED_EXECUTOR
}

error SpendGrantError(Reason reason);

bytes32 constant REASON_OK = "OK";
bytes32 constant REASON_INVALID_GRANT = "INVALID_GRANT";
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

uint256 constant WAD = 1e18;
uint256 constant MAX_ASSETS = 16;
uint256 constant MAX_LIVE_DEBITS = 256;

interface IERC1271 {
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4);
}

interface ISpendGrantRegistry {
    event GrantRevoked(address indexed principal, bytes32 indexed grantHash);
    event GrantConsumed(
        bytes32 indexed grantHash,
        address indexed asset,
        uint256 amount,
        address indexed recipient
    );

    function executor() external view returns (address);
    function revoke(bytes32 grantHash) external;
    function revoked(address principal, bytes32 grantHash) external view returns (bool);
    function usage(bytes32 grantHash, address asset) external view returns (uint256 spent, uint256 calls);
    function rollingUsage(bytes32 grantHash, address asset) external view returns (uint256 spent, uint256 calls);
    function pieUsed(bytes32 grantHash) external view returns (uint256 lifetimeWad, uint256 windowWad);

    function consume(
        SpendGrant calldata grant,
        bytes calldata grantSignature,
        address asset,
        uint256 amount,
        address recipient
    ) external;
}
