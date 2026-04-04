// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IVerifier} from "./IVerifier.sol";

/// @title OracleVerifier — Reference Implementation
/// @notice Example verifier using EIP-712 typed data signatures.
///         A trusted backend signs (id, claimant, expiry) after confirming
///         off-chain ownership (e.g. GitHub OAuth, DNS TXT record).
contract OracleVerifier is IVerifier {
    address public admin;
    address public trustedSigner;
    address public immutable registry;

    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant NAME_HASH = keccak256("CanonicalRegistry");
    bytes32 private constant VERSION_HASH = keccak256("1");
    bytes32 public constant PROOF_TYPEHASH =
        keccak256("OwnershipProof(bytes32 id,address claimant,uint256 expiry)");

    event TrustedSignerUpdated(address indexed previous, address indexed next);

    constructor(address registry_, address trustedSigner_, address admin_) {
        registry = registry_;
        trustedSigner = trustedSigner_;
        admin = admin_;
    }

    function verify(bytes32 id, address claimant, bytes calldata proof) external view returns (bool) {
        (bytes memory signature, uint256 expiry) = abi.decode(proof, (bytes, uint256));
        require(block.timestamp < expiry, "expired");

        bytes32 domainSeparator = keccak256(abi.encode(
            DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, registry
        ));
        bytes32 structHash = keccak256(abi.encode(PROOF_TYPEHASH, id, claimant, expiry));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(signature);
        return ecrecover(digest, v, r, s) == trustedSigner;
    }

    function setTrustedSigner(address signer) external {
        require(msg.sender == admin, "not admin");
        emit TrustedSignerUpdated(trustedSigner, signer);
        trustedSigner = signer;
    }

    function _splitSignature(bytes memory sig) private pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "bad sig length");
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }
}
