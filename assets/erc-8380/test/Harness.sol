// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IVerifier} from "../IVerifier.sol";

/// @title BindingVerifier
/// @notice A stand-in for the real circuit that is deliberately NOT a rubber stamp.
/// @dev A verifier that always returns true makes every binding test in this suite pass for
///      free: swap the executor, swap the expiry, substitute the nullifier, and a permissive
///      mock still says yes. This one issues a proof against one exact public-input vector and
///      accepts it only against that vector, which is the property a real circuit has and the
///      only property these tests are actually about.
contract BindingVerifier is IVerifier {
    mapping(bytes32 => bytes32) private _boundTo;

    function issueProof(bytes memory proof, bytes32[] memory publicInputs) external {
        _boundTo[keccak256(proof)] = keccak256(abi.encode(publicInputs));
    }

    function verify(bytes calldata proof, bytes32[] calldata publicInputs)
        external view returns (bool)
    {
        bytes32 bound = _boundTo[keccak256(proof)];
        return bound != bytes32(0) && bound == keccak256(abi.encode(publicInputs));
    }
}

/// @notice Records that it ran, so "burn implies execution" is observable rather than assumed.
contract ActionTarget {
    uint256 public runs;
    function act() external { runs += 1; }
    function boom() external pure { revert("action failed"); }
}
