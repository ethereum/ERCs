// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/**
 * @title IPuller
 * @notice Interface for the ERC-8187 Token Puller standard.
 *
 * @dev A Puller contract acts as an intermediary that manages pull allowances
 * granted by owners to spenders, executes custom sourcing logic to obtain tokens,
 * and transfers them to a requested destination.
 *
 * The interface supports:
 * - On-chain approvals with limits
 * - Off-chain EIP-712 signed permits
 * - Allowance delegation/transfer between spenders
 * - Infinite approval handling
 * - Renunciation of allowances
 * - Atomic permit + pull operations
 *
 * @custom:specification https://eips.ethereum.org/ERCS/erc-8187
 */
interface IPuller {
    // =============================================================
    // Events
    // =============================================================

    /**
     * @notice Emitted when an owner approves or updates a spender's pull allowance.
     * @param token The token address
     * @param owner The owner granting the allowance
     * @param spender The spender receiving the allowance
     * @param limit The new allowance limit (0 means revoked)
     */
    event PullApproval(address indexed token, address indexed owner, address indexed spender, uint256 limit);

    /**
     * @notice Emitted when tokens are successfully pulled.
     * @param token The token address
     * @param owner The owner from whom tokens were sourced
     * @param spender The spender who initiated the pull
     * @param to The destination address receiving the tokens
     * @param amount The amount of tokens transferred
     */
    event TokensPulled(address indexed token, address indexed owner, address indexed spender, address to, uint256 amount);

    /**
     * @notice Emitted when a spender transfers part or all of their pull allowance.
     * @param token The token address
     * @param owner The owner
     * @param fromSpender The spender transferring away allowance
     * @param toSpender The recipient spender (address(0) for renunciation)
     * @param amount The amount transferred
     */
    event TransferPullAllowance(
        address indexed token, address indexed owner, address indexed fromSpender, address toSpender, uint256 amount
    );

    // =============================================================
    // Core functions
    // =============================================================

    /**
     * @notice Sets or updates the pull allowance for a spender.
     * @dev Must revert if called by any address other than the owner.
     * Setting `limit` to 0 revokes the spender's permission.
     * Must overwrite any previous allowance for `(token, owner, spender)`.
     * Must emit `PullApproval`.
     * @param token The token address
     * @param spender The spender being authorized
     * @param limit The maximum amount the spender may pull
     */
    function approvePull(address token, address spender, uint256 limit) external;

    /**
     * @notice Pulls tokens from an owner and transfers them to a destination.
     * @dev Must revert unless msg.sender has sufficient allowance.
     * When msg.sender == owner, may bypass allowance check.
     * Must decrease allowance by amount (unless infinite).
     * Must execute sourcing logic and transfer exactly `amount` tokens to `to`.
     * Must emit `TokensPulled`.
     * @param token The token address
     * @param owner The owner to pull from
     * @param to The destination for the pulled tokens
     * @param amount The amount to pull
     */
    function pullFrom(address token, address owner, address to, uint256 amount) external;

    /**
     * @notice Returns the remaining pull allowance for a spender.
     * @param token The token address
     * @param owner The owner
     * @param spender The spender
     * @return The remaining allowance
     */
    function pullAllowance(address token, address owner, address spender) external view returns (uint256);

    /**
     * @notice Returns the maximum amount that could be pulled from an owner,
     * considering sourcing constraints, capped by `upTo`.
     * @dev The spender-specific maximum is computed as:
     * `maxPullable(token, owner, pullAllowance(token, owner, spender))`.
     * The `upTo` parameter allows early termination.
     * @param token The token address
     * @param owner The owner
     * @param upTo The cap for the returned value
     * @return The maximum pullable amount, between 0 and upTo
     */
    function maxPullable(address token, address owner, uint256 upTo) external view returns (uint256);

    // =============================================================
    // Allowance delegation
    // =============================================================

    /**
     * @notice Transfers pull allowance from msg.sender to another spender.
     * @dev Must revert if msg.sender has insufficient allowance.
     * Special case: if amount == type(uint256).max and current allowance is infinite,
     * set msg.sender's to 0 and toSpender's to type(uint256).max.
     * Otherwise, decrease msg.sender's and increase toSpender's.
     * toSpender == address(0) means renunciation (no increase).
     * Must revert if toSpender == msg.sender.
     * Must emit `TransferPullAllowance`.
     * @param token The token address
     * @param owner The owner
     * @param toSpender The spender receiving allowance
     * @param amount The amount to transfer
     */
    function transferPullAllowance(address token, address owner, address toSpender, uint256 amount) external;

    // =============================================================
    // Permits (off-chain approvals)
    // =============================================================

    /**
     * @notice Approves or updates a pull allowance using an off-chain EIP-712 signature.
     * @dev The signature must be over the `PullPermit` struct.
     * Must revert if deadline has passed, the signature is invalid, or nonce mismatches.
     * On success, increments the owner's nonce, sets the allowance, and emits `PullApproval`.
     * May be called by anyone (spender, relayer, etc.).
     *
     * Struct: PullPermit(address token, address owner, address spender, uint256 limit, uint256 nonce, uint256 deadline)
     * Typehash: keccak256("PullPermit(address token,address owner,address spender,uint256 limit,uint256 nonce,uint256 deadline)")
     *
     * @param token The token address
     * @param owner The owner granting the allowance
     * @param spender The spender being authorized
     * @param limit The allowance limit
     * @param deadline The timestamp after which the permit is invalid
     * @param signature The EIP-712 signature (r,s,v for EOA; TODO: ERC-6492/ERC-1271 support)
     */
    function permitPull(
        address token,
        address owner,
        address spender,
        uint256 limit,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /**
     * @notice Atomically applies a permit (with limit == amount) and executes a pull.
     * @dev The signature must correspond to a PullPermit where limit == amount and spender == msg.sender.
     * Should call permitPull but not revert if it fails (front-run DOS protection).
     * Must revert only if the pull itself fails.
     * Must emit `PullApproval` followed by `TokensPulled`.
     * @param token The token address
     * @param owner The owner
     * @param to The destination address
     * @param amount The amount to pull
     * @param deadline The permit deadline
     * @param signature The EIP-712 signature
     */
    function pullFromWithPermit(
        address token,
        address owner,
        address to,
        uint256 amount,
        uint256 deadline,
        bytes calldata signature
    ) external;

    // =============================================================
    // EIP-5267 / EIP-2612 helpers
    // =============================================================

    /**
     * @notice Returns the EIP-712 domain data per ERC-5267.
     * @return fields A bit string specifying which fields are present
     * @return name The domain name
     * @return version The domain version
     * @return chainId The chain ID
     * @return verifyingContract The verifying contract address
     * @return salt The domain salt
     * @return extensions Additional fields
     */
    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        );

    /**
     * @notice Returns the current nonce for an owner.
     * @dev Used for permit replay protection.
     * @param owner The owner address
     * @return The current nonce
     */
    function nonces(address owner) external view returns (uint256);
}
