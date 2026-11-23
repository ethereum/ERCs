// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/**
 * @title PolicyDecisionReceipt (draft ERC: Policy-Enforced Agent Accounts)
 * @notice Pure helpers to verify a signed decision receipt on chain, e.g. a lender or marketplace that
 *         accepts an agent's transaction only with an ALLOW receipt from the account's receipt signer.
 *         Version 2 of the EIP-712 domain: the intent includes the operation (call or delegatecall).
 *         A verifier that acts on an ALLOW must also check, at use time, that the receipt's policy is
 *         the registry's current one, that the account is not stopped, and that the decisionId is unused.
 */
library PolicyDecisionReceipt {
    bytes32 internal constant INTENT_TYPEHASH = keccak256("Intent(uint256 chainId,address account,address target,uint256 value,bytes32 dataHash,uint8 operation)");
    bytes32 internal constant DECISION_TYPEHASH = keccak256(
        "Decision(address account,bytes32 intentHash,uint8 decision,bytes32 reasonCode,bytes32 detailCode,bytes32 policyHash,uint64 policyVersion,uint64 issuedAt,uint64 expiresAt,bytes32 decisionId)"
    );
    bytes32 internal constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    uint8 internal constant ALLOW = 0;
    uint8 internal constant DENY = 1;
    uint8 internal constant REVIEW = 2;

    uint8 internal constant CALL = 0;
    uint8 internal constant DELEGATECALL = 1;

    struct Decision {
        address account;
        bytes32 intentHash;
        uint8 decision;
        bytes32 reasonCode;
        bytes32 detailCode;
        bytes32 policyHash;
        uint64 policyVersion;
        uint64 issuedAt;
        uint64 expiresAt;
        bytes32 decisionId;
    }

    /// @param operation 0 for a call, 1 for a delegatecall (for ERC-7579 accounts: the call type byte of the execution mode)
    function intentHash(uint256 chainId, address account, address target, uint256 value, bytes memory data, uint8 operation)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(INTENT_TYPEHASH, chainId, account, target, value, keccak256(data), operation));
    }

    function domainSeparator(uint256 chainId, address registry) internal pure returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("PolicyDecisionReceipt"), keccak256("2"), chainId, registry));
    }

    function digest(Decision memory d, uint256 chainId, address registry) internal pure returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                DECISION_TYPEHASH, d.account, d.intentHash, d.decision, d.reasonCode, d.detailCode, d.policyHash, d.policyVersion, d.issuedAt, d.expiresAt, d.decisionId
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator(chainId, registry), structHash));
    }

    /// @return signer the EOA that signed, or address(0) for a malformed or high-s signature
    function recover(bytes32 hash, bytes memory signature) internal pure returns (address signer) {
        if (signature.length != 65) return address(0);
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) return address(0);
        if (v < 27) v += 27;
        return ecrecover(hash, v, r, s);
    }
}
