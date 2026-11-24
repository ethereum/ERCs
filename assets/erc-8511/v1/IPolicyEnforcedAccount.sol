// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/**
 * @title IPolicyEnforcedAccount (draft ERC: Policy-Enforced Agent Accounts)
 * @notice Read interface for an account whose transactions need an external policy signer.
 *         Served by the account itself or by a registry for existing accounts. All reads take the
 *         account address so one registry can serve many accounts.
 */
interface IPolicyEnforcedAccount {
    /// @param policySigner  the external co-signer that enforces the policy (0 = not enforced)
    /// @param publisher     the only address that may post commitments for the account
    /// @param receiptSigner the key that signs decision receipts (EOA, or ERC-1271 contract)
    /// @param since         block timestamp from which this set applies
    struct Signers {
        address policySigner;
        address publisher;
        address receiptSigner;
        uint64 since;
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

    event SignersDeclared(address indexed account, address policySigner, address publisher, address receiptSigner);
    event PolicyActivated(address indexed account, bytes32 indexed policyHash, uint64 version, uint64 effectiveAt, string policyURI, string schemaURI);
    event PolicyPending(address indexed account, bytes32 indexed policyHash, uint64 version, uint64 effectiveAt, string policyURI, string schemaURI);
    event PolicyCancelled(address indexed account, bytes32 indexed policyHash, uint64 version, string reason);
    event EmergencyStop(address indexed account, string reason);
    event EmergencyStopLifted(address indexed account);
    event MandateSet(address indexed account, string mandateURI, bytes32 configHash);

    /// @notice The account's current signers (all zero if it never declared).
    function policySigner(address account) external view returns (Signers memory);

    /// @notice The signers that applied at `timestamp` (to verify an older receipt).
    function signersAt(address account, uint64 timestamp) external view returns (Signers memory);

    /// @notice The policy deciding now. A pending change whose effectiveAt has passed is returned here.
    function policyOf(address account) external view returns (PolicyCommitment memory);

    /// @notice A pending change that is not yet effective, if any.
    function pendingPolicyOf(address account) external view returns (bool exists, PolicyCommitment memory);

    /// @notice An optional vote-governed mandate that changes this account's policy.
    function mandateOf(address account) external view returns (string memory mandateURI, bytes32 configHash);

    /// @notice True while the account's emergency stop is engaged (the signer allows nothing).
    function isStopped(address account) external view returns (bool);
}
