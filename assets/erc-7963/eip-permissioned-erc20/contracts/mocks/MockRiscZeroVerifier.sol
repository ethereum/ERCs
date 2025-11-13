// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title MockRiscZeroVerifier
 * @notice A mock verifier contract for RISC Zero proofs for testing purposes
 * @dev This mock implements the same interface as RiscZeroVerifier but allows
 *      configurable return values for testing different scenarios
 */
contract MockRiscZeroVerifier {
    
    // --- Configurable State ---
    bool private _verifyResult = true; // Default to true
    bool private _verifyWithMethodIdResult = true; // Default to true
    
    // --- Events ---
    event VerifyCalled(bytes proof, bytes32 journalHash, bytes32 sealHash);
    event VerifyWithMethodIdCalled(bytes proof, bytes32 journalHash, bytes32 sealHash, bytes32 methodId);
    
    /// @notice Verifies a RISC Zero proof
    /// @param proof The proof bytes
    /// @param journalHash The hash of the journal (public outputs)
    /// @param sealHash The hash of the seal
    /// @return True if the proof is valid
    function verify(
        bytes calldata proof,
        bytes32 journalHash,
        bytes32 sealHash
    ) external view returns (bool) {
        // In a real implementation, this would verify the actual proof
        // For testing, we return the configured result
        return _verifyResult;
    }
    
    /// @notice Verifies a RISC Zero proof with method ID
    /// @param proof The proof bytes
    /// @param journalHash The hash of the journal (public outputs)
    /// @param sealHash The hash of the seal
    /// @param methodId The method ID that generated this proof
    /// @return True if the proof is valid
    function verifyWithMethodId(
        bytes calldata proof,
        bytes32 journalHash,
        bytes32 sealHash,
        bytes32 methodId
    ) external view returns (bool) {
        // In a real implementation, this would verify the proof with method ID
        // For testing, we return the configured result
        return _verifyWithMethodIdResult;
    }
    
    // --- Mock Configuration Functions ---
    
    /// @notice Sets the return value for verify() calls
    /// @param result The boolean result to return
    function setVerifyResult(bool result) external {
        _verifyResult = result;
    }
    
    /// @notice Sets the return value for verifyWithMethodId() calls
    /// @param result The boolean result to return
    function setVerifyWithMethodIdResult(bool result) external {
        _verifyWithMethodIdResult = result;
    }
    
    /// @notice Sets both verify results to the same value
    /// @param result The boolean result to return for both functions
    function setVerifyProofResult(bool result) external {
        _verifyResult = result;
        _verifyWithMethodIdResult = result;
    }
    
    // --- View Functions for Testing ---
    
    /// @notice Gets the current verify result setting
    /// @return The current verify result
    function getVerifyResult() external view returns (bool) {
        return _verifyResult;
    }
    
    /// @notice Gets the current verifyWithMethodId result setting
    /// @return The current verifyWithMethodId result
    function getVerifyWithMethodIdResult() external view returns (bool) {
        return _verifyWithMethodIdResult;
    }
} 