// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.27;

/*
 * solhint: disable mixedCase function name rule for standard constants
 * Some ERC standards expose functions/variables in SCREAMING_SNAKE_CASE
 * (for example DOMAIN_SEPARATOR). We intentionally keep the standard
 * names to match token implementations, so disable the rule for this file.
 */
/* solhint-disable func-name-mixedcase */

/**
 * @title IERC20Permit
 * @dev Interface for the ERC20 Permit standard (EIP-2612).
 */
interface IERC20Permit {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function nonces(address owner) external view returns (uint256);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

/**
 * @title IDaiPermit
 * @dev Interface for the DAI-style permit.
 */
interface IDaiPermit {
    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

/**
 * @notice Struct to hold permit data for EIP-2612 tokens.
 * @param deadline The time at which the signature expires.
 * @param v The recovery id of the signature.
 * @param r The r-value of the signature.
 * @param s The s-value of the signature.
 */
struct PermitData {
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
}

/**
 * @notice Struct to hold permit data for DAI-style tokens.
 * @param nonce The nonce of the permit.
 * @param expiry The time at which the signature expires.
 * @param allowed Whether the spender is allowed to spend the tokens.
 * @param v The recovery id of the signature.
 * @param r The r-value of the signature.
 * @param s The s-value of the signature.
 */
struct DaiPermitData {
    uint256 nonce;
    uint256 expiry;
    bool allowed;
    uint8 v;
    bytes32 r;
    bytes32 s;
}
