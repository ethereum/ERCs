// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IConfidentialPolicyVerdict, Verdict, PolicyKind} from "./IConfidentialPolicyVerdict.sol";
import {IPolicyDomainRegistry} from "./IPolicyDomainRegistry.sol";
import {IVerifier} from "./IVerifier.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @notice The Guard: consumes a confidential policy verdict and burns its nullifier.
/// The core normative contract of the standard.
contract ConfidentialPolicyVerdict is IConfidentialPolicyVerdict, EIP712, ERC165 {
    IPolicyDomainRegistry public immutable registry;

    bytes32 private constant VERDICT_TYPEHASH = keccak256(
        "Verdict(uint256 agentId,bytes32 domainId,bytes32 policyRoot,bytes32 actionCommitment,address executor,uint64 expiry,bytes32 nullifier,uint8 decision,uint8 policyKind)"
    );

    // domainId => nullifier => consumed
    mapping(bytes32 => mapping(bytes32 => bool)) private _consumed;

    constructor(IPolicyDomainRegistry _registry) EIP712("ConfidentialPolicyVerdict", "1") {
        registry = _registry;
    }

    function isConsumed(bytes32 domainId, bytes32 nullifier) public view returns (bool) {
        return _consumed[domainId][nullifier];
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IConfidentialPolicyVerdict).interfaceId || super.supportsInterface(interfaceId);
    }

    function verdictDigest(Verdict calldata v) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    VERDICT_TYPEHASH,
                    v.agentId,
                    v.domainId,
                    v.policyRoot,
                    v.actionCommitment,
                    v.executor,
                    v.expiry,
                    v.nullifier,
                    v.decision,
                    v.policyKind
                )
            )
        );
    }

    function verify(Verdict calldata v, bytes calldata proof) external view returns (bool) {
        IPolicyDomainRegistry.Domain memory d = registry.domain(v.domainId);
        if (!d.active) return false;
        if (!PolicyKind.agreesWithDecision(v.policyKind, v.decision)) return false;
        if (v.decision != 1) return false;
        if (block.timestamp >= v.expiry) return false;
        if (_consumed[v.domainId][v.nullifier]) return false;
        if (!registry.isRootAcceptable(v.domainId, v.policyRoot)) return false;
        // Malformed proof MUST return false, not revert.
        try IVerifier(d.verifier).verifyProof(d.programKey, abi.encode(v), proof) returns (bool ok) {
            return ok;
        } catch {
            return false;
        }
    }

    /// @notice Direct consume: v.executor must be msg.sender.
    function consume(Verdict calldata v, bytes calldata proof) external {
        _consume(v, proof, "");
    }

    /// @notice Relayed consume: msg.sender may be any address if executorAuth is a valid
    /// signature by v.executor over verdictDigest(v).
    function consume(Verdict calldata v, bytes calldata proof, bytes calldata executorAuth) external {
        _consume(v, proof, executorAuth);
    }

    /// @dev Checks run in the exact order the spec mandates; revert on the first failure.
    function _consume(Verdict calldata v, bytes calldata proof, bytes memory executorAuth) internal {
        if (!PolicyKind.agreesWithDecision(v.policyKind, v.decision)) {
            revert VerdictKindMismatch(v.decision, v.policyKind);                            // 1
        }
        IPolicyDomainRegistry.Domain memory d = registry.domain(v.domainId);
        if (!d.active) revert DomainInactive(v.domainId);                                    // 2
        if (v.decision != 1) revert VerdictDenied();                                         // 3
        _requireExecutorAuthorized(v, executorAuth);                                         // 4
        if (block.timestamp >= v.expiry) revert VerdictExpired(v.expiry);                    // 5
        if (_consumed[v.domainId][v.nullifier]) revert VerdictReplayed(v.nullifier);         // 6
        if (!registry.isRootAcceptable(v.domainId, v.policyRoot)) revert PolicyRootRejected(v.policyRoot); // 7
        // Mirrors `verify`: a malformed proof must surface as InvalidProof rather than
        // propagating the verifier's own error, which check 8 names.
        try IVerifier(d.verifier).verifyProof(d.programKey, abi.encode(v), proof) returns (bool ok) {
            if (!ok) revert InvalidProof();                                                  // 8
        } catch {
            revert InvalidProof();                                                           // 8
        }

        _consumed[v.domainId][v.nullifier] = true;
        emit VerdictConsumed(v.nullifier, v.agentId, v.domainId, v.policyRoot, v.actionCommitment);
    }

    /// @dev Executor is bound cryptographically, not positionally. Direct submission
    /// (msg.sender == executor) needs no signature; a relayer must present the executor's
    /// EIP-712 signature (ECDSA or ERC-1271) over this verdict's digest.
    function _requireExecutorAuthorized(Verdict calldata v, bytes memory executorAuth) internal view {
        if (msg.sender == v.executor) return;
        if (executorAuth.length == 0) revert ExecutorMismatch(v.executor, msg.sender);
        if (!SignatureChecker.isValidSignatureNow(v.executor, verdictDigest(v), executorAuth)) {
            revert ExecutorAuthInvalid();
        }
    }
}
