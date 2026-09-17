// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AssetLimit, SpendGrant} from "../src/MandateTypes.sol";
import {MandateHash} from "../src/MandateHash.sol";
import {HashHarness} from "./HashHarness.sol";

contract MandateHashTest is Test {
    HashHarness internal harness;

    function setUp() public {
        harness = new HashHarness();
    }

    function test_encodeType_matchesSpec() public pure {
        bytes32 expected = keccak256(
            "SpendGrant(address principal,address delegate,uint8 recipientMode,address recipient,uint8 assetCombine,uint64 windowSeconds,AssetLimit[] assets,uint64 validAfter,uint64 validUntil,uint256 salt,bytes32 renderingHash)AssetLimit(address asset,uint256 maxPerCall,uint256 maxPerWindow,uint256 maxTotal)"
        );
        SpendGrant memory m;
        m.assets = new AssetLimit[](1);
        m.assets[0] = AssetLimit(address(0), 1, 1, 1);
        // Touch library via hashStruct so the typehash is the one compiled in.
        bytes32 structHash = MandateHash.hashStruct(m);
        bytes32 rebuilt = keccak256(
            abi.encode(
                expected,
                m.principal,
                m.delegate,
                m.recipientMode,
                m.recipient,
                m.assetCombine,
                m.windowSeconds,
                MandateHash.hashAssets(m.assets),
                m.validAfter,
                m.validUntil,
                m.salt,
                m.renderingHash
            )
        );
        assertEq(structHash, rebuilt);
    }

    function test_arrayHash_isConcatOfElementHashes() public {
        AssetLimit[] memory assets = new AssetLimit[](2);
        assets[0] = AssetLimit(address(0), 1, 2, 3);
        assets[1] = AssetLimit(address(uint160(1)), 4, 5, 6);
        bytes32 h0 = keccak256(
            abi.encode(
                keccak256("AssetLimit(address asset,uint256 maxPerCall,uint256 maxPerWindow,uint256 maxTotal)"),
                assets[0].asset,
                assets[0].maxPerCall,
                assets[0].maxPerWindow,
                assets[0].maxTotal
            )
        );
        bytes32 h1 = keccak256(
            abi.encode(
                keccak256("AssetLimit(address asset,uint256 maxPerCall,uint256 maxPerWindow,uint256 maxTotal)"),
                assets[1].asset,
                assets[1].maxPerCall,
                assets[1].maxPerWindow,
                assets[1].maxTotal
            )
        );
        assertEq(MandateHash.hashAssets(assets), keccak256(abi.encodePacked(h0, h1)));
    }

    function test_goldenVectors() public {
        string memory json = vm.readFile("assets/erc-draft_spend_grants/vectors/v1.json");
        for (uint256 i = 0; i < 4; i++) {
            string memory p = string.concat(".vectors[", vm.toString(i), "]");
            uint256 chainId = vm.parseJsonUint(json, string.concat(p, ".chainId"));
            address registry = vm.parseJsonAddress(json, string.concat(p, ".revocationRegistry"));
            bytes32 domain = vm.parseJsonBytes32(json, string.concat(p, ".domainSeparator"));
            bytes32 structHash = vm.parseJsonBytes32(json, string.concat(p, ".structHash"));
            bytes32 digest_ = vm.parseJsonBytes32(json, string.concat(p, ".digest"));
            bytes32 renderingHash = vm.parseJsonBytes32(json, string.concat(p, ".grant.renderingHash"));
            string memory rendering = vm.parseJsonString(json, string.concat(p, ".rendering"));

            uint256 nAssets = (i == 0 || i == 3) ? 1 : 2;
            SpendGrant memory m = _mandateFromJson(json, p, nAssets);
            assertEq(keccak256(bytes(rendering)), renderingHash);
            assertEq(m.renderingHash, renderingHash);

            vm.chainId(chainId);
            assertEq(harness.domainSeparator(registry), domain);
            assertEq(harness.hashStruct(m), structHash);
            assertEq(harness.digest(chainId, registry, m), digest_);
            assertEq(MandateHash.digest(chainId, registry, m), digest_);

            if (i == 3) {
                bytes memory sig = vm.parseJsonBytes(json, string.concat(p, ".signature"));
                assertEq(sig.length, 65);
                bytes32 r;
                bytes32 s;
                uint8 v;
                assembly {
                    r := mload(add(sig, 32))
                    s := mload(add(sig, 64))
                    v := byte(0, mload(add(sig, 96)))
                }
                address recovered = ecrecover(digest_, v, r, s);
                assertEq(recovered, m.principal);
                assertTrue(v == 27 || v == 28);
            }
        }
    }

    function test_digest_dependsOnChainAndRegistry() public {
        SpendGrant memory m;
        m.principal = address(0x1);
        m.delegate = address(0x2);
        m.recipientMode = 1;
        m.windowSeconds = 1;
        m.validAfter = 1;
        m.validUntil = 2;
        m.assets = new AssetLimit[](1);
        m.assets[0] = AssetLimit(address(0), 1, 1, 1);

        bytes32 a = harness.digest(1, address(0x1111), m);
        bytes32 b = harness.digest(2, address(0x1111), m);
        bytes32 c = harness.digest(1, address(0x2222), m);
        assertTrue(a != b && a != c && b != c);
    }

    function _mandateFromJson(string memory json, string memory p, uint256 nAssets)
        internal
        view
        returns (SpendGrant memory m)
    {
        m.principal = vm.parseJsonAddress(json, string.concat(p, ".grant.principal"));
        m.delegate = vm.parseJsonAddress(json, string.concat(p, ".grant.delegate"));
        m.recipientMode = uint8(vm.parseJsonUint(json, string.concat(p, ".grant.recipientMode")));
        m.recipient = vm.parseJsonAddress(json, string.concat(p, ".grant.recipient"));
        m.assetCombine = uint8(vm.parseJsonUint(json, string.concat(p, ".grant.assetCombine")));
        m.windowSeconds = uint64(vm.parseJsonUint(json, string.concat(p, ".grant.windowSeconds")));
        m.validAfter = uint64(vm.parseJsonUint(json, string.concat(p, ".grant.validAfter")));
        m.validUntil = uint64(vm.parseJsonUint(json, string.concat(p, ".grant.validUntil")));
        m.salt = vm.parseJsonUint(json, string.concat(p, ".grant.salt"));
        m.renderingHash = vm.parseJsonBytes32(json, string.concat(p, ".grant.renderingHash"));
        m.assets = new AssetLimit[](nAssets);
        for (uint256 i = 0; i < nAssets; i++) {
            string memory a = string.concat(p, ".grant.assets[", vm.toString(i), "]");
            m.assets[i] = AssetLimit({
                asset: vm.parseJsonAddress(json, string.concat(a, ".asset")),
                maxPerCall: vm.parseJsonUint(json, string.concat(a, ".maxPerCall")),
                maxPerWindow: vm.parseJsonUint(json, string.concat(a, ".maxPerWindow")),
                maxTotal: vm.parseJsonUint(json, string.concat(a, ".maxTotal"))
            });
        }
    }
}
