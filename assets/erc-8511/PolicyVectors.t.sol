// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {PolicyDecisionReceipt as R} from "../src/peaa/PolicyDecisionReceipt.sol";
import {IPolicyEnforcedAccount} from "../src/peaa/IPolicyEnforcedAccount.sol";

/// The published v2 test vectors (operation in the intent, EIP-712 domain version "2"), checked by an
/// independent Solidity implementation.
contract PolicyVectorsTest is Test {
    using stdJson for string;

    string json;

    function setUp() public {
        json = vm.readFile("../packages/policy-enforced-accounts/vectors/vectors.json");
    }

    function test_interfaceId() public view {
        assertEq(bytes4(json.readBytes("$.interfaceId")), type(IPolicyEnforcedAccount).interfaceId);
    }

    function test_policyHashes() public view {
        for (uint256 i = 0; i < 5; i++) {
            string memory p = string.concat("$.policies[", vm.toString(i), "]");
            assertEq(keccak256(bytes(json.readString(string.concat(p, ".jcs")))), json.readBytes32(string.concat(p, ".policyHash")));
        }
    }

    function test_intents() public view {
        for (uint256 i = 0; i < 3; i++) {
            string memory p = string.concat("$.intents[", vm.toString(i), "]");
            bytes32 h = R.intentHash(
                json.readUint(string.concat(p, ".intent.chainId")),
                json.readAddress(string.concat(p, ".intent.account")),
                json.readAddress(string.concat(p, ".intent.target")),
                vm.parseUint(json.readString(string.concat(p, ".intent.value"))),
                json.readBytes(string.concat(p, ".intent.data")),
                uint8(json.readUint(string.concat(p, ".intent.operation")))
            );
            assertEq(h, json.readBytes32(string.concat(p, ".intentHash")));
        }
    }

    function _decision(string memory p) internal view returns (R.Decision memory d) {
        string memory dec = json.readString(string.concat(p, ".receipt.decision"));
        d.account = json.readAddress(string.concat(p, ".receipt.account"));
        d.intentHash = json.readBytes32(string.concat(p, ".receipt.intentHash"));
        d.decision = keccak256(bytes(dec)) == keccak256("ALLOW") ? R.ALLOW : keccak256(bytes(dec)) == keccak256("DENY") ? R.DENY : R.REVIEW;
        d.reasonCode = json.readBytes32(string.concat(p, ".encodedReason"));
        d.detailCode = json.readBytes32(string.concat(p, ".encodedDetail"));
        d.policyHash = json.readBytes32(string.concat(p, ".receipt.policyHash"));
        d.policyVersion = uint64(vm.parseUint(json.readString(string.concat(p, ".receipt.policyVersion"))));
        d.issuedAt = uint64(vm.parseUint(json.readString(string.concat(p, ".receipt.issuedAt"))));
        d.expiresAt = uint64(vm.parseUint(json.readString(string.concat(p, ".receipt.expiresAt"))));
        d.decisionId = json.readBytes32(string.concat(p, ".receipt.decisionId"));
    }

    function test_receipts() public view {
        address expected = json.readAddress("$.testKeys.receiptSigner.address");
        for (uint256 i = 0; i < 4; i++) {
            string memory p = string.concat("$.receipts[", vm.toString(i), "]");
            uint256 chainId = vm.parseUint(json.readString(string.concat(p, ".receipt.chainId")));
            address registry = json.readAddress(string.concat(p, ".receipt.registry"));
            bytes32 digest = R.digest(_decision(p), chainId, registry);
            assertEq(digest, json.readBytes32(string.concat(p, ".digest")));
            assertEq(R.recover(digest, json.readBytes(string.concat(p, ".receipt.signature"))), expected);
        }
    }

    function test_tamperedReceiptFails() public view {
        string memory p = "$.receipts[1]";
        R.Decision memory d = _decision(p);
        d.decision = R.ALLOW;
        bytes32 digest = R.digest(d, 4663, json.readAddress(string.concat(p, ".receipt.registry")));
        assertTrue(R.recover(digest, json.readBytes(string.concat(p, ".receipt.signature"))) != json.readAddress("$.testKeys.receiptSigner.address"));
    }

    function test_callAndDelegatecallDiffer() public view {
        assertTrue(json.readBytes32("$.intents[1].intentHash") != json.readBytes32("$.intents[2].intentHash"));
    }
}
