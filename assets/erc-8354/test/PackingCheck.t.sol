// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {PolicyAction, PolicyActionLib} from "../src/PolicyAction.sol";

/// @notice Cross-checks that Solidity `PolicyAction.commit` produces the exact same commitment
/// as the Noir circuit's `abi_encode_policy_action` + keccak, for identical inputs. If this passes,
/// the on-chain guarded contract and the proving circuit bind to the same action bytes.
contract PackingCheck is Test {
    function test_commit_matches_noir() public pure {
        PolicyAction memory a = PolicyAction({
            chainId: 1,
            domainId: bytes32(uint256(42)),
            agentId: 7,
            target: address(uint160(0x1234)),
            value: 0,
            callDataHash: bytes32(0),
            actionNonce: 3
        });
        bytes32 c = PolicyActionLib.commit(a);
        // Value printed by the Noir circuit test `test_print_commit` for the same inputs.
        bytes32 fromNoir = 0x7ccb7a4e9d51128b951cbeddefaec1140180a3d13f6eae6f06596dc432057cfa;
        assertEq(c, fromNoir, "Noir/Solidity action-commitment packing mismatch");
    }
}
