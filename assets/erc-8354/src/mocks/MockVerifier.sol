// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IVerifier} from "../IVerifier.sol";

/// @notice Test double. Returns `result`; `shouldRevert` models a malformed proof.
contract MockVerifier is IVerifier {
    bool public result = true;
    bool public shouldRevert;

    function setResult(bool r) external { result = r; }
    function setRevert(bool r) external { shouldRevert = r; }

    function verifyProof(bytes32, bytes calldata, bytes calldata) external view returns (bool) {
        require(!shouldRevert, "malformed proof");
        return result;
    }
}
