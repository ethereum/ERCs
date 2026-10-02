// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Base64} from "solady/utils/Base64.sol";
import {LibString} from "solady/utils/LibString.sol";
import {P256} from "solady/utils/P256.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

/// @notice ERC-8395 grant proof verification, NOT HTTP authorization.
/// @dev Callers must separately validate grant structure, parent/profile binding,
/// attenuation, validity, revocation, request signatures and service permissions.
/// No constructor arguments, storage or immutables: CREATE2 code is chain invariant.
contract DelegationVerifier {
    struct Delegation {
        string issuer;
        string delegate;
        string[] audiences;
        bytes32 id;
        uint64 epoch;
        uint64 validAfter;
        uint64 validUntil;
        uint32 maxRequestValiditySeconds;
        uint32 remainingDelegations;
        string delegateProfile;
        bool requireNonReplayable;
        string[] requiredComponents;
        string[] permissions;
        bytes32 parentGrantHash;
    }

    bytes32 public constant DELEGATION_TYPEHASH = keccak256(
        "Delegation(string issuer,string delegate,string[] audiences,bytes32 id,uint64 epoch,uint64 validAfter,uint64 validUntil,uint32 maxRequestValiditySeconds,uint32 remainingDelegations,string delegateProfile,bool requireNonReplayable,string[] requiredComponents,string[] permissions,bytes32 parentGrantHash)"
    );
    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant NAME_HASH = keccak256("ERC-8128 Delegation");
    bytes32 private constant VERSION_HASH = keccak256("1");
    uint256 private constant HALF_ORDER = 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;
    bytes32 private constant ERC6492_SUFFIX = 0x6492649264926492649264926492649264926492649264926492649264926492;

    error OnlySelf();
    error ProofResult(bool valid);

    function domainSeparator() public view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(this)));
    }

    function hashGrant(Delegation calldata grant) public view returns (bytes32) {
        return keccak256(proofMessage(grant));
    }

    /// @notice The 66-byte EIP-712 input B. Registered profiles sign B, not keccak256(B).
    function proofMessage(Delegation calldata grant) public view returns (bytes memory) {
        return abi.encodePacked(hex"1901", domainSeparator(), hashGrantStruct(grant));
    }

    function hashGrantStruct(Delegation calldata g) public pure returns (bytes32) {
        // Fixed-width words avoid stack pressure without changing EIP-712 encoding.
        bytes32[15] memory words;
        words[0] = DELEGATION_TYPEHASH;
        words[1] = keccak256(bytes(g.issuer));
        words[2] = keccak256(bytes(g.delegate));
        words[3] = _hashStrings(g.audiences);
        words[4] = g.id;
        words[5] = bytes32(uint256(g.epoch));
        words[6] = bytes32(uint256(g.validAfter));
        words[7] = bytes32(uint256(g.validUntil));
        words[8] = bytes32(uint256(g.maxRequestValiditySeconds));
        words[9] = bytes32(uint256(g.remainingDelegations));
        words[10] = keccak256(bytes(g.delegateProfile));
        words[11] = bytes32(uint256(g.requireNonReplayable ? 1 : 0));
        words[12] = _hashStrings(g.requiredComponents);
        words[13] = _hashStrings(g.permissions);
        words[14] = g.parentGrantHash;
        return keccak256(abi.encode(words));
    }

    /// @param eoaOnly True only when the PARENT selected erc8128-eoa; root uses false.
    /// @dev Non-view solely to simulate ERC-6492 deployment in an always-reverting
    /// self-call. Even a transaction cannot retain the simulated factory effects.
    function verifyEthereumGrant(Delegation calldata grant, address issuer, bytes calldata signature, bool eoaOnly)
        external
        returns (bool)
    {
        string memory accountId =
            string.concat("eip155:", LibString.toString(block.chainid), ":", LibString.toHexString(issuer));
        if (issuer == address(0) || keccak256(bytes(grant.issuer)) != keccak256(bytes(accountId))) return false;
        bytes32 digest = hashGrant(grant);
        if (eoaOnly) return _verifyEoa(issuer, digest, signature);
        bool wrapped = signature.length >= 32 && bytes32(signature[signature.length - 32:]) == ERC6492_SUFFIX;
        if (!wrapped) {
            return issuer.code.length == 0
                ? _verifyEoa(issuer, digest, signature)
                : SignatureCheckerLib.isValidERC1271SignatureNowCalldata(issuer, digest, signature);
        }
        try this.simulateCounterfactual(issuer, digest, signature) {
            return false;
        } catch (bytes memory result) {
            // Do not trust errors propagated by a factory/account. The helper
            // catches them itself and only this contract constructs ProofResult.
            return keccak256(result) == keccak256(abi.encodeWithSelector(ProofResult.selector, true));
        }
    }

    function simulateCounterfactual(address issuer, bytes32 digest, bytes calldata signature) external {
        if (msg.sender != address(this)) revert OnlySelf();
        bool valid;
        try this.checkCounterfactual(issuer, digest, signature) returns (bool result) {
            valid = result;
        } catch {}
        revert ProofResult(valid);
    }

    function checkCounterfactual(address issuer, bytes32 digest, bytes calldata signature) external returns (bool) {
        if (msg.sender != address(this)) revert OnlySelf();
        (address factory, bytes memory factoryData, bytes memory innerSignature) =
            abi.decode(signature[:signature.length - 32], (address, bytes, bytes));
        if (issuer.code.length != 0 && SignatureCheckerLib.isValidERC1271SignatureNow(issuer, digest, innerSignature)) {
            return true;
        }
        // This call is enclosed by simulateCounterfactual's unconditional revert.
        // Do not depend on a separately deployed universal-signature validator.
        (bool success,) = factory.call(factoryData);
        return success && issuer.code.length != 0
            && SignatureCheckerLib.isValidERC1271SignatureNow(issuer, digest, innerSignature);
    }

    /// @notice Verify an ecdsa-p256-sha256 issuer, binding its key to the issuer's
    /// RFC-9278 ID. The parent, not grant.delegateProfile, selects this algorithm.
    function verifyP256Grant(Delegation calldata grant, bytes32 x, bytes32 y, bytes calldata signature)
        external
        view
        returns (bool)
    {
        if (signature.length != 64) return false;
        bytes memory jwk = abi.encodePacked(
            '{"crv":"P-256","kty":"EC","x":"',
            Base64.encode(abi.encodePacked(x), true, true),
            '","y":"',
            Base64.encode(abi.encodePacked(y), true, true),
            '"}'
        );
        string memory issuerId = string.concat(
            "urn:ietf:params:oauth:jwk-thumbprint:sha-256:", Base64.encode(abi.encodePacked(sha256(jwk)), true, true)
        );
        if (keccak256(bytes(grant.issuer)) != keccak256(bytes(issuerId))) return false;
        return P256.verifySignatureAllowMalleability(
            sha256(proofMessage(grant)), bytes32(signature[:32]), bytes32(signature[32:]), x, y
        );
    }

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
        )
    {
        return (0x0f, "ERC-8128 Delegation", "1", block.chainid, address(this), bytes32(0), new uint256[](0));
    }

    function _hashStrings(string[] calldata values) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](values.length);
        for (uint256 i; i < values.length; ++i) {
            hashes[i] = keccak256(bytes(values[i]));
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function _verifyEoa(address issuer, bytes32 digest, bytes calldata signature) private pure returns (bool) {
        if (signature.length != 65) return false;
        bytes32 r = bytes32(signature[:32]);
        bytes32 s = bytes32(signature[32:64]);
        uint8 v = uint8(signature[64]);
        if ((v != 27 && v != 28) || uint256(s) > HALF_ORDER) return false;
        return ecrecover(digest, v, r, s) == issuer;
    }
}
