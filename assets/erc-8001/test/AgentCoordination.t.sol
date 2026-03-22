// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/AgentCoordination.sol";
import "../src/IAgentCoordination.sol";

contract AgentCoordinationCoreTest is Test {
    AgentCoordination core;

    address alice;
    address bob;
    address charlie;

    uint256 aliceKey = 0xa11ce;
    uint256 bobKey = 0xb0b;
    uint256 charlieKey = 0xc0de;

    function setUp() public {
        core = new AgentCoordination();
        alice = vm.addr(aliceKey);
        bob = vm.addr(bobKey);
        charlie = vm.addr(charlieKey);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(charlie, 10 ether);
    }

    function _participants(address a, address b) internal pure returns (address[] memory p) {
        p = new address[](2);
        if (a < b) {
            p[0] = a;
            p[1] = b;
        } else {
            p[0] = b;
            p[1] = a;
        }
    }

    function _intent(address[] memory parts, address agent, bytes32 ctype, uint64 nonce)
    internal
    view
    returns (IAgentCoordination.AgentIntent memory it)
    {
        it = IAgentCoordination.AgentIntent({
            payloadHash: bytes32(0),
            expiry: uint64(block.timestamp + 3600),
            nonce: nonce,
            agentId: agent,
            coordinationType: ctype,
            coordinationValue: 1 ether,
            participants: parts
        });
    }

    function _payload(bytes32 ctype) internal view returns (IAgentCoordination.CoordinationPayload memory p) {
        p = IAgentCoordination.CoordinationPayload({
            version: keccak256("v1"),
            coordinationType: ctype,
            coordinationData: abi.encode("data"),
            conditionsHash: keccak256("ok"),
            timestamp: block.timestamp,
            metadata: ""
        });
    }

    function _signIntent(IAgentCoordination.AgentIntent memory intent, uint256 key)
    internal
    view
    returns (bytes memory sig, bytes32 ih)
    {
        ih = core.getIntentHash(intent);
        bytes32 digest = core.getTypedDataDigest(ih);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function _signAcceptance(IAgentCoordination.AcceptanceAttestation memory att, uint256 key)
    internal
    view
    returns (bytes memory sig, bytes32 ah)
    {
        ah = core.getAcceptanceHash(att);
        bytes32 digest = core.getTypedDataDigest(ah);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        sig = abi.encodePacked(r, s, v);
    }

    function testProposeAcceptExecute() public {
        address[] memory parts = _participants(alice, bob);
        bytes32 ctype = keccak256("TEST_V1");

        IAgentCoordination.AgentIntent memory it = _intent(parts, alice, ctype, 1);
        IAgentCoordination.CoordinationPayload memory pl = _payload(ctype);
        it.payloadHash = core.getPayloadHash(pl);

        (bytes memory sig, bytes32 ih) = _signIntent(it, aliceKey);

        vm.prank(alice);
        bytes32 rh = core.proposeCoordination(it, sig, pl);
        assertEq(rh, ih);

        // bob accepts first
        IAgentCoordination.AcceptanceAttestation memory att = IAgentCoordination.AcceptanceAttestation({
            intentHash: ih,
            participant: bob,
            nonce: 1,
            expiry: uint64(block.timestamp + 1200),
            conditionsHash: keccak256("ok"),
            signature: ""
        });
        (bytes memory asig,) = _signAcceptance(att, bobKey);
        att.signature = asig;
        vm.prank(bob);
        bool all = core.acceptCoordination(ih, att);
        assertFalse(all);

        // alice accepts
        IAgentCoordination.AcceptanceAttestation memory att2 = IAgentCoordination.AcceptanceAttestation({
            intentHash: ih,
            participant: alice,
            nonce: 1,
            expiry: uint64(block.timestamp + 3600),
            conditionsHash: keccak256("ok"),
            signature: ""
        });
        (bytes memory asig2,) = _signAcceptance(att2, aliceKey);
        att2.signature = asig2;
        vm.prank(alice);
        bool all2 = core.acceptCoordination(ih, att2);
        assertTrue(all2);

        // execute
        vm.prank(alice);
        (bool success, bytes memory res) = core.executeCoordination(ih, pl, "");
        assertTrue(success);
        assertEq(res, pl.coordinationData);
    }

    function testAcceptanceMustBeFreshAtExecute() public {
        address[] memory parts = _participants(alice, bob);
        bytes32 ctype = keccak256("TEST_V1");

        IAgentCoordination.AgentIntent memory it = _intent(parts, alice, ctype, 2);
        IAgentCoordination.CoordinationPayload memory pl = _payload(ctype);
        it.payloadHash = core.getPayloadHash(pl);

        (bytes memory sig, bytes32 ih) = _signIntent(it, aliceKey);
        vm.prank(alice);
        core.proposeCoordination(it, sig, pl);

        // bob accepts but with short expiry
        IAgentCoordination.AcceptanceAttestation memory att = IAgentCoordination.AcceptanceAttestation({
            intentHash: ih,
            participant: bob,
            nonce: 1,
            expiry: uint64(block.timestamp + 1),
            conditionsHash: keccak256("ok"),
            signature: ""
        });
        (bytes memory asig,) = _signAcceptance(att, bobKey);
        att.signature = asig;
        vm.prank(bob);
        core.acceptCoordination(ih, att);

        // alice accepts with a long expiry so status becomes READY
        IAgentCoordination.AcceptanceAttestation memory att2 = IAgentCoordination.AcceptanceAttestation({
            intentHash: ih,
            participant: alice,
            nonce: 1,
            expiry: uint64(block.timestamp + 3600),
            conditionsHash: keccak256("ok"),
            signature: ""
        });
        (bytes memory asig2,) = _signAcceptance(att2, aliceKey);
        att2.signature = asig2;
        vm.prank(alice);
        bool allNow = core.acceptCoordination(ih, att2);
        assertTrue(allNow);

        // wait until bob's acceptance expires
        vm.warp(block.timestamp + 2);

        vm.prank(alice);
        vm.expectRevert("Acceptance expired");
        core.executeCoordination(ih, pl, "");
    }

    function testRejectUnsortedParticipants() public {
        // Build intentionally unsorted participants
        address[] memory parts = new address[](2);
        if (alice < bob) {
            parts[0] = alice;
            parts[1] = bob;
        } else {
            parts[0] = bob;
            parts[1] = alice;
        } // ascending
        // Flip them to force unsorted
        address tmp = parts[0];
        parts[0] = parts[1];
        parts[1] = tmp;

        bytes32 ctype = keccak256("TEST_V1");
        IAgentCoordination.AgentIntent memory it = _intent(parts, alice, ctype, 1);
        IAgentCoordination.CoordinationPayload memory pl = _payload(ctype);
        it.payloadHash = core.getPayloadHash(pl);

        (bytes memory sig,) = _signIntent(it, aliceKey);
        vm.prank(alice);
        vm.expectRevert("Participants not canonical");
        core.proposeCoordination(it, sig, pl);
    }

    function testReplayByNonceFails() public {
        address[] memory parts = _participants(alice, bob);
        bytes32 ctype = keccak256("TEST_V1");

        IAgentCoordination.AgentIntent memory it = _intent(parts, alice, ctype, 10);
        IAgentCoordination.CoordinationPayload memory pl = _payload(ctype);
        it.payloadHash = core.getPayloadHash(pl);

        (bytes memory sig,) = _signIntent(it, aliceKey);
        vm.prank(alice);
        core.proposeCoordination(it, sig, pl);

        // reuse same nonce
        vm.prank(alice);
        vm.expectRevert("Nonce not strictly increasing");
        core.proposeCoordination(it, sig, pl);
    }
}
