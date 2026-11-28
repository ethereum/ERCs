// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/**
 * @title IPolicyEnforcedAccount (draft ERC: Policy-Enforced Agent Accounts)
 * @notice Read interface for an account whose transactions need an external policy signer.
 *         Served by the account itself or by a registry for existing accounts. All reads take the
 *         account address so one registry can serve many accounts. Reads follow time: a pending
 *         signer set or policy is returned once its effective time has passed.
 */
interface IPolicyEnforcedAccount {
    /// @param policySigner  the external co-signer that enforces the policy (0 = not enforced)
    /// @param publisher     the only address that may post commitments for the account
    /// @param receiptSigner the key that signs decision receipts (EOA, or ERC-1271 contract)
    /// @param since         block timestamp from which this set applies
    /// @param minDelay      seconds every publisher change and every later signer change must wait
    /// @param signerType    how the policy signer is wired in: 1 co-signer in the signature path,
    ///                      2 validator module, 3 guard or hook, 4 other (0 only when not enforced)
    struct Signers {
        address policySigner;
        address publisher;
        address receiptSigner;
        uint64 since;
        uint32 minDelay;
        uint8 signerType;
    }

    /// @param policyHash  keccak256 of the policy document's RFC 8785 (JCS) canonical JSON
    /// @param version     the policy's version, strictly increasing per account
    /// @param effectiveAt block timestamp from which the policy decides
    /// @param policyURI   where the document can be fetched (may be empty: hash only)
    /// @param schemaURI   the document's format
    struct PolicyCommitment {
        bytes32 policyHash;
        uint64 version;
        uint64 effectiveAt;
        string policyURI;
        string schemaURI;
    }

    event SignersDeclared(address indexed account, address policySigner, address publisher, address receiptSigner, uint32 minDelay, uint8 signerType);
    event SignersPending(
        address indexed account, address policySigner, address publisher, address receiptSigner, uint32 minDelay, uint8 signerType, uint64 effectiveAt
    );
    event SignersCancelled(address indexed account, address policySigner, address publisher, address receiptSigner, uint64 effectiveAt);
    event PolicyActivated(address indexed account, bytes32 indexed policyHash, uint64 version, uint64 effectiveAt, string policyURI, string schemaURI);
    event PolicyPending(address indexed account, bytes32 indexed policyHash, uint64 version, uint64 effectiveAt, string policyURI, string schemaURI);
    event PolicyCancelled(address indexed account, bytes32 indexed policyHash, uint64 version, string reason);
    event EmergencyStop(address indexed account, string reason);
    event EmergencyStopLifted(address indexed account);
    event MandateSet(address indexed account, string mandateURI, bytes32 configHash);

    /// @notice The account's signers in effect now (all zero if it never declared, or cleared them).
    function policySigner(address account) external view returns (Signers memory);

    /// @notice The signers that applied at `timestamp` (to verify an older receipt).
    function signersAt(address account, uint64 timestamp) external view returns (Signers memory);

    /// @notice A signer change that is not yet effective, if any.
    function pendingSignersOf(address account) external view returns (bool exists, Signers memory);

    /// @notice The policy deciding now. A pending change whose effectiveAt has passed is returned here.
    function policyOf(address account) external view returns (PolicyCommitment memory);

    /// @notice A pending change that is not yet effective, if any.
    function pendingPolicyOf(address account) external view returns (bool exists, PolicyCommitment memory);

    /// @notice An optional vote-governed mandate that changes this account's policy.
    function mandateOf(address account) external view returns (string memory mandateURI, bytes32 configHash);

    /// @notice True while the account's emergency stop is engaged (the signer allows nothing).
    function isStopped(address account) external view returns (bool);
}
