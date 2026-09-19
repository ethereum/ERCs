// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IKYAVerifier} from "../interfaces/IKYAVerifier.sol";

/// @dev snarkjs-style Groth16 verifier with 10 public signals.
interface IGroth16Verifier10 {
    function verifyProof(uint256[2] calldata a, uint256[2][2] calldata b, uint256[2] calldata c, uint256[10] calldata input)
        external
        view
        returns (bool);
}

/// @title Groth16KYAVerifierAdapter
/// @notice Adapts a snarkjs-style Groth16 verifier to IKYAVerifier using the canonical
///         "kya-public-v1" layout. 256-bit values are split into (hi128, lo128) field elements so
///         they fit under the BN254 scalar field without truncation.
///
///         publicInputs = abi.encode(bytes32 subjectKey, bytes32 nullifier, uint8 level,
///                                   bytes32 claimDigest, uint64 expiresAt, bytes32 issuerSetRoot)
///         proof        = abi.encode(uint256[2] a, uint256[2][2] b, uint256[2] c)
///
///         signals (10): [subjectKey.hi, subjectKey.lo, nullifier.hi, nullifier.lo, level,
///                        claimDigest.hi, claimDigest.lo, expiresAt, issuerSetRoot.hi, issuerSetRoot.lo]
///
///         `issuerSetRoot` is exposed so relying parties can pin the attestor set the circuit proved
///         membership in; the adapter optionally enforces a fixed root.
contract Groth16KYAVerifierAdapter is IKYAVerifier {
    IGroth16Verifier10 public immutable groth16;
    bytes32 public immutable requiredIssuerSetRoot; // 0x0 = any

    constructor(address groth16_, bytes32 requiredIssuerSetRoot_) {
        groth16 = IGroth16Verifier10(groth16_);
        requiredIssuerSetRoot = requiredIssuerSetRoot_;
    }

    function verify(bytes32, bytes calldata publicInputs, bytes calldata proof)
        external
        view
        returns (bool ok, bytes32 subjectKey, bytes32 nullifier, uint8 level, bytes32 claimDigest, uint64 expiresAt)
    {
        bytes32 issuerSetRoot;
        (subjectKey, nullifier, level, claimDigest, expiresAt, issuerSetRoot) =
            abi.decode(publicInputs, (bytes32, bytes32, uint8, bytes32, uint64, bytes32));

        if (requiredIssuerSetRoot != bytes32(0) && issuerSetRoot != requiredIssuerSetRoot) {
            return (false, bytes32(0), bytes32(0), 0, bytes32(0), 0);
        }

        (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c) =
            abi.decode(proof, (uint256[2], uint256[2][2], uint256[2]));

        uint256[10] memory input;
        (input[0], input[1]) = _split(subjectKey);
        (input[2], input[3]) = _split(nullifier);
        input[4] = level;
        (input[5], input[6]) = _split(claimDigest);
        input[7] = expiresAt;
        (input[8], input[9]) = _split(issuerSetRoot);

        ok = groth16.verifyProof(a, b, c, input);
        if (!ok) return (false, bytes32(0), bytes32(0), 0, bytes32(0), 0);
    }

    function _split(bytes32 v) internal pure returns (uint256 hi, uint256 lo) {
        hi = uint256(v) >> 128;
        lo = uint256(v) & ((uint256(1) << 128) - 1);
    }
}
