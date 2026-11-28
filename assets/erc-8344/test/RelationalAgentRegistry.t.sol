// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RelationalAgentRegistry} from "../contracts/RelationalAgentRegistry.sol";
import {IRelationalAgentRegistry as I} from "../contracts/IRelationalAgentRegistry.sol";

contract RelationalAgentRegistryTest is Test {
    RelationalAgentRegistry reg;

    address constant A = address(0xAA);
    address constant B = address(0xBB);
    address constant C = address(0xCC);
    address constant OP = address(0x0F);

    function setUp() public {
        reg = new RelationalAgentRegistry();
    }

    function _members3() internal pure returns (address[] memory m) {
        m = new address[](3);
        m[0] = A; m[1] = B; m[2] = C;
    }

    function _pair(address x, address y) internal pure returns (address[] memory m) {
        m = new address[](2);
        m[0] = x; m[1] = y;
    }

    function _activate3() internal returns (uint256 agentId) {
        vm.prank(A);
        agentId = reg.proposeAgent(_members3(), false, "ipfs://card", 30 days);
        vm.prank(B);
        reg.acceptAgent(agentId);
        vm.prank(C);
        reg.acceptAgent(agentId);
    }

    // ------------------------------------------------------------------
    // Identity: test vectors from the ERC's Test Cases section
    // ------------------------------------------------------------------

    function test_RelationshipIdVectors() public view {
        assertEq(
            reg.relationshipIdOf(_pair(A, B), false),
            0x9d086835e9dba64a081aa4c50f23e76a017a27fa4eb3822eaaf4c7a3eddf68fa
        );
        assertEq(
            reg.relationshipIdOf(_members3(), false),
            0x03e5f8c327af463723625c22b020d3f8200909584b36516f22e11dfbbb6674bf
        );
        assertEq(
            reg.relationshipIdOf(_pair(A, B), true),
            0x60093d0882bca3aaeddfab88c72617475aee555b86f39cd70b8de2388efc9fae
        );
        assertEq(
            reg.relationshipIdOf(_pair(B, A), true),
            0x538cfc3380d8b6e3602dd2e490fdb3b8fdc03a29b3d688782d11377376700797
        );
    }

    function test_AgentIdVectors() public view {
        uint256 ridPair = reg.relationshipIdOf(_pair(A, B), false);
        uint256 ridGroup = reg.relationshipIdOf(_members3(), false);
        assertEq(
            reg.agentIdOf(ridPair, 0),
            0x5b0996fdc03d50be11906b0792833a211aea5ab2f7d2f50307cc409054b55622
        );
        assertEq(
            reg.agentIdOf(ridPair, 1),
            0x7faf3d8cdb080e768e82ec034b1e1d6cbc303f6c79b815a8f316670191afd247
        );
        assertEq(
            reg.agentIdOf(ridGroup, 0),
            0xb30bfcca270c106a5448c86b258f259226e80e0303c9d27dcf78b02ad712b595
        );
    }

    function test_RevertIdentity() public {
        vm.expectRevert(bytes("not strictly ascending"));
        reg.relationshipIdOf(_pair(B, A), false);

        vm.expectRevert(bytes("not strictly ascending"));
        reg.relationshipIdOf(_pair(A, A), false);

        address[] memory one = new address[](1);
        one[0] = A;
        vm.expectRevert(bytes("min two members"));
        reg.relationshipIdOf(one, false);

        vm.expectRevert(bytes("directed is pairs-only"));
        reg.relationshipIdOf(_members3(), true);

        vm.expectRevert(bytes("zero address"));
        reg.relationshipIdOf(_pair(address(0), A), false);
    }

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    function test_ProposeAcceptActivate() public {
        vm.prank(A);
        uint256 agentId = reg.proposeAgent(_members3(), false, "ipfs://card", 30 days);
        assertEq(uint8(reg.getAgent(agentId).status), uint8(I.Status.Proposed));

        vm.prank(B);
        reg.acceptAgent(agentId);
        assertEq(uint8(reg.getAgent(agentId).status), uint8(I.Status.Proposed));

        vm.prank(C);
        reg.acceptAgent(agentId);
        assertEq(uint8(reg.getAgent(agentId).status), uint8(I.Status.Active));
        assertEq(reg.memberCount(agentId), 3);
        assertTrue(reg.isMember(agentId, B));
    }

    function test_RevertProposeByNonMember() public {
        vm.prank(OP);
        vm.expectRevert(bytes("proposer not in member set"));
        reg.proposeAgent(_members3(), false, "", 0);
    }

    function test_RevertDoubleAcceptAndNonMemberAccept() public {
        vm.prank(A);
        uint256 agentId = reg.proposeAgent(_members3(), false, "", 0);
        vm.prank(A);
        vm.expectRevert(bytes("already accepted"));
        reg.acceptAgent(agentId);
        vm.prank(OP);
        vm.expectRevert(bytes("not a member"));
        reg.acceptAgent(agentId);
    }

    function test_RevertSecondAgentSameRelationship() public {
        _activate3();
        vm.prank(A);
        vm.expectRevert(bytes("current agent not dissolved"));
        reg.proposeAgent(_members3(), false, "", 0);
    }

    function test_LeaveDissolvesAndNextGenerationLinksPredecessor() public {
        uint256 gen0 = _activate3();
        vm.prank(C);
        reg.leaveAgent(gen0);
        assertEq(uint8(reg.getAgent(gen0).status), uint8(I.Status.Dissolved));

        // same member set can recreate; generation increments, predecessor auto-links
        vm.prank(A);
        uint256 gen1 = reg.proposeAgent(_members3(), false, "", 0);
        assertTrue(gen1 != gen0);
        assertEq(reg.getAgent(gen1).predecessorAgentId, gen0);
        uint256 rid = reg.relationshipIdOf(_members3(), false);
        assertEq(reg.generationOf(rid), 2);
        assertEq(reg.currentAgentOf(rid), gen1);
    }

    function test_PauseResume_ShortPause() public {
        uint256 agentId = _activate3();
        vm.prank(B);
        reg.pauseAgent(agentId);
        assertEq(uint8(reg.getAgent(agentId).status), uint8(I.Status.Paused));
        vm.warp(block.timestamp + 1 days); // within 30-day reconsentPeriod
        vm.prank(B);
        reg.resumeAgent(agentId);
        assertEq(uint8(reg.getAgent(agentId).status), uint8(I.Status.Active));
    }

    function test_PauseResume_LongPauseNeedsReconsent() public {
        uint256 agentId = _activate3();
        vm.prank(B);
        reg.pauseAgent(agentId);
        vm.warp(block.timestamp + 31 days); // beyond reconsentPeriod

        vm.prank(B);
        vm.expectRevert(bytes("pauser cannot re-consent"));
        reg.resumeAgent(agentId);

        vm.prank(A);
        reg.resumeAgent(agentId);
        assertEq(uint8(reg.getAgent(agentId).status), uint8(I.Status.Paused));
        vm.prank(C);
        reg.resumeAgent(agentId);
        assertEq(uint8(reg.getAgent(agentId).status), uint8(I.Status.Active));
    }

    // ------------------------------------------------------------------
    // Shared Record Corpus
    // ------------------------------------------------------------------

    function test_AppendAndFullyCoSign() public {
        uint256 agentId = _activate3();
        vm.prank(A);
        uint256 idx = reg.appendRecord(agentId, I.RecordType.MeetingNote, keccak256("note"), "ipfs://note");
        assertEq(reg.recordCount(agentId), 1);
        assertEq(reg.getRecord(agentId, idx).coSignCount, 0);

        vm.prank(B);
        reg.coSignRecord(agentId, idx);
        vm.prank(C);
        reg.coSignRecord(agentId, idx);
        assertEq(reg.getRecord(agentId, idx).coSignCount, 2); // memberCount - 1: fully co-signed
        assertTrue(reg.hasCoSigned(agentId, idx, B));
        assertFalse(reg.hasCoSigned(agentId, idx, A));
    }

    function test_RevertRecordRules() public {
        uint256 agentId = _activate3();
        vm.prank(A);
        uint256 idx = reg.appendRecord(agentId, I.RecordType.Photo, keccak256("p"), "");

        vm.prank(A);
        vm.expectRevert(bytes("contributor cannot co-sign"));
        reg.coSignRecord(agentId, idx);

        vm.prank(B);
        reg.coSignRecord(agentId, idx);
        vm.prank(B);
        vm.expectRevert(bytes("already co-signed"));
        reg.coSignRecord(agentId, idx);

        vm.prank(OP);
        vm.expectRevert(bytes("not member or SRC_APPEND operator"));
        reg.appendRecord(agentId, I.RecordType.Letter, keccak256("l"), "");
    }

    function test_RevertAppendBeforeActiveAndAfterDissolved() public {
        vm.prank(A);
        uint256 agentId = reg.proposeAgent(_members3(), false, "", 0);
        vm.prank(A);
        vm.expectRevert(bytes("not active"));
        reg.appendRecord(agentId, I.RecordType.Letter, keccak256("x"), "");

        vm.prank(B);
        reg.acceptAgent(agentId);
        vm.prank(C);
        reg.acceptAgent(agentId);
        vm.prank(A);
        reg.appendRecord(agentId, I.RecordType.Letter, keccak256("x"), "");

        vm.prank(B);
        reg.dissolveAgent(agentId);
        vm.prank(A);
        vm.expectRevert(bytes("not active"));
        reg.appendRecord(agentId, I.RecordType.Letter, keccak256("y"), "");
        // sealed SRC stays readable
        assertEq(reg.recordCount(agentId), 1);
        assertEq(reg.getRecord(agentId, 0).contributor, A);
    }

    // ------------------------------------------------------------------
    // Delegation
    // ------------------------------------------------------------------

    function test_DelegateAllKeysGrantSingleKeyRevoke() public {
        uint256 agentId = _activate3();
        bytes32 scope = keccak256("SEND_MESSAGE");
        uint64 expiry = uint64(block.timestamp + 7 days);

        vm.prank(A);
        reg.delegate(agentId, OP, scope, expiry);
        assertFalse(reg.isAuthorized(agentId, OP, scope));
        vm.prank(B);
        reg.delegate(agentId, OP, scope, expiry);
        assertFalse(reg.isAuthorized(agentId, OP, scope));
        vm.prank(C);
        reg.delegate(agentId, OP, scope, expiry);
        assertTrue(reg.isAuthorized(agentId, OP, scope));

        vm.prank(B); // any single member revokes
        reg.revokeDelegation(agentId, OP, scope);
        assertFalse(reg.isAuthorized(agentId, OP, scope));
    }

    function test_DelegationDeadOnPauseAndDissolve() public {
        uint256 agentId = _activate3();
        bytes32 scope = reg.SRC_APPEND();
        uint64 expiry = uint64(block.timestamp + 7 days);
        vm.prank(A); reg.delegate(agentId, OP, scope, expiry);
        vm.prank(B); reg.delegate(agentId, OP, scope, expiry);
        vm.prank(C); reg.delegate(agentId, OP, scope, expiry);

        vm.prank(OP);
        reg.appendRecord(agentId, I.RecordType.ChatHistory, keccak256("m"), "");

        vm.prank(A);
        reg.pauseAgent(agentId);
        assertFalse(reg.isAuthorized(agentId, OP, scope));

        vm.prank(A);
        reg.resumeAgent(agentId);
        assertTrue(reg.isAuthorized(agentId, OP, scope));

        vm.prank(C);
        reg.dissolveAgent(agentId);
        assertFalse(reg.isAuthorized(agentId, OP, scope));
    }

    function test_DelegationExpiry() public {
        uint256 agentId = _activate3();
        bytes32 scope = keccak256("S");
        uint64 expiry = uint64(block.timestamp + 1 days);
        vm.prank(A); reg.delegate(agentId, OP, scope, expiry);
        vm.prank(B); reg.delegate(agentId, OP, scope, expiry);
        vm.prank(C); reg.delegate(agentId, OP, scope, expiry);
        assertTrue(reg.isAuthorized(agentId, OP, scope));
        vm.warp(block.timestamp + 2 days);
        assertFalse(reg.isAuthorized(agentId, OP, scope));
    }

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------

    function test_AgentsOf() public {
        uint256 g = _activate3();
        vm.prank(A);
        uint256 p = reg.proposeAgent(_pair(A, B), false, "", 0);
        uint256[] memory ofA = reg.agentsOf(A);
        assertEq(ofA.length, 2);
        assertEq(ofA[0], g);
        assertEq(ofA[1], p);
        assertEq(reg.agentsOf(C).length, 1);
    }
}
