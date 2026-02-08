// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IZRC20.sol";

/**
 * @title IDualModeToken
 * @notice Interface for dual-mode tokens (ERC-8085) combining ERC-20 and ERC-8086 (IZRC20)
 * @dev Implementations MUST inherit both IERC20 and IZRC20
 *      Privacy events and core functions are inherited from IZRC20 (ERC-8086)
 *      This interface only defines mode conversion logic - the core value of ERC-8085
 *
 * Architecture:
 *   - Public Mode: Standard ERC-20 (transparent balances and transfers)
 *   - Privacy Mode: ERC-8086 IZRC20 (ZK-SNARK protected balances and transfers)
 *   - Mode Conversion: toPrivate (public → private) and toPublic (private → public)
 */
interface IDualModeToken is IERC20, IZRC20 {

    // ═══════════════════════════════════════════════════════════════════════
    // Mode Conversion Functions (Core of ERC-8085)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Convert transparent balance to privacy mode
     * @dev Burns ERC-20 tokens and creates privacy commitment via IZRC20
     * @param amount Amount to convert (must match proof)
     * @param proofType Type of proof to support multiple proof strategies.
     * @param proof ZK-SNARK proof of valid commitment creation
     * @param encryptedNote Encrypted note data for recipient wallet
     */
    function toPrivate(
        uint256 amount,
        uint8 proofType,
        bytes calldata proof,
        bytes calldata encryptedNote
    ) external;

    /**
     * @notice Convert privacy balance to transparent mode
     * @dev Spends privacy notes and mints ERC-20 tokens to recipient
     * @param recipient Address to receive public tokens
     * @param proofType Type of proof to support multiple proof strategies.
     * @param proof ZK-SNARK proof of note ownership and spending
     * @param encryptedNotes Encrypted notes for change outputs (if any)
     */
    function toPublic(
        address recipient,
        uint8 proofType,
        bytes calldata proof,
        bytes[] calldata encryptedNotes
    ) external;

    // ═══════════════════════════════════════════════════════════════════════
    // Supply Tracking
    // ═══════════════════════════════════════════════════════════════════════

    // Note: Privacy transfers use IZRC20.transfer(uint8, bytes, bytes[])
    // which is inherited from IZRC20 (ERC-8086)

    /**
     * @notice Total supply across both modes (overrides IERC20 and IZRC20)
     * @return Total supply = publicSupply + privacySupply
     */
    function totalSupply() external view override(IERC20, IZRC20) returns (uint256);

    /**
     * @notice Get total supply in privacy mode
     * @dev Tracked by increments/decrements during mode conversions
     * @return Total privacy supply
     */
    function totalPrivacySupply() external view returns (uint256);

    /**
     * @notice Check if a nullifier has been spent
     * @dev Alias for IZRC20.nullifiers() with different naming convention
     * @param nullifier The nullifier hash to check
     * @return True if spent, false otherwise
     */
    function isNullifierSpent(bytes32 nullifier) external view returns (bool);
}
