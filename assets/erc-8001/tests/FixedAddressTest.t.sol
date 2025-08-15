// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AgentCoordinationFramework.sol";

contract FixedAddressTest is Test {
    AgentCoordinationFramework coordination;

    // Use proper private key/address pairs
    uint256 aliceKey = 0x1;
    uint256 bobKey = 0x2;
    uint256 charlieKey = 0x3;

    address alice;
    address bob;
    address charlie;

    function setUp() public {
        coordination = new AgentCoordinationFramework();

        // Get correct addresses for the private keys
        alice = vm.addr(aliceKey);
        bob = vm.addr(bobKey);
        charlie = vm.addr(charlieKey);

        console.log("Alice address:", alice);
        console.log("Bob address:", bob);
        console.log("Charlie address:", charlie);

        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(charlie, 10 ether);
    }

    function testSignatureWorks() public {
        console.log("=== TESTING CORRECT SIGNATURE ===");

        address[] memory participants = new address[](1);
        participants[0] = alice;

        IAgentCoordinationCore.CoordinationPayload memory payload = IAgentCoordinationCore.CoordinationPayload({
            version: keccak256("v1"),
            coordinationType: keccak256("TEST_V1"),
            coordinationData: abi.encode("test", "data"),
            conditionsHash: keccak256("test conditions"),
            timestamp: block.timestamp,
            metadata: ""
        });

        IAgentCoordinationCore.AgentIntent memory intent = IAgentCoordinationCore.AgentIntent({
            payloadHash: coordination.getPayloadHash(payload),
            expiry: uint64(block.timestamp + 3600),
            nonce: 1,
            chainId: uint32(block.chainid),
            agentId: alice,
            coordinationType: keccak256("TEST_V1"),
            maxGasCost: 100000,
            priority: 128,
            dependencyHash: bytes32(0),
            securityLevel: 0,
            participants: participants,
            coordinationValue: 1 ether
        });

        // Create signature with matching private key
        bytes32 intentHash = coordination.getIntentHash(intent);
        bytes32 domainSeparator = coordination.getDomainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, intentHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Verify signature recovery
        address recovered = ecrecover(digest, v, r, s);
        console.log("Expected:", alice);
        console.log("Recovered:", recovered);
        assertEq(recovered, alice, "Signature should recover to alice's address");

        // Test contract verification
        bool isValid = coordination.verifyIntentSignature(intentHash, signature, alice);
        assertTrue(isValid, "Contract should verify signature");

        // Test coordination proposal
        vm.prank(alice);
        bytes32 resultHash = coordination.proposeCoordination(intent, signature, payload);

        console.log("SUCCESS! Coordination proposed with hash:");
        console.logBytes32(resultHash);

        // Verify proposal worked
        (uint8 status, address proposer,,,) = coordination.getCoordinationStatus(resultHash);
        assertEq(status, 0); // PROPOSED
        assertEq(proposer, alice);

        assertTrue(true, "All signature tests passed!");
    }

    function testBasicCoordination() public {
        bytes32 intentHash = _createAndProposeCoordination();

        // Verify proposal worked
        (uint8 status, address proposer,,,) = coordination.getCoordinationStatus(intentHash);
        assertEq(status, 0); // PROPOSED
        assertEq(proposer, alice);

        // Alice accepts (she's a participant)
        _acceptCoordination(intentHash, alice, aliceKey);

        // Check acceptance
        (,,,address[] memory acceptedBy,) = coordination.getCoordinationStatus(intentHash);
        assertEq(acceptedBy.length, 1);
        assertEq(acceptedBy[0], alice);
    }

    function testInvalidSignature() public {
        address[] memory participants = new address[](1);
        participants[0] = alice;

        IAgentCoordinationCore.AgentIntent memory intent = _createIntent(participants, 1);
        IAgentCoordinationCore.CoordinationPayload memory payload = _createPayload();
        intent.payloadHash = coordination.getPayloadHash(payload);

        // Sign with wrong key (bob instead of alice)
        bytes memory signature = _signIntent(intent, bobKey);

        vm.prank(alice);
        vm.expectRevert("Invalid signature");
        coordination.proposeCoordination(intent, signature, payload);
    }

    function testExpiredIntent() public {
        address[] memory participants = new address[](1);
        participants[0] = alice;

        IAgentCoordinationCore.AgentIntent memory intent = _createIntent(participants, 1);
        intent.expiry = uint64(block.timestamp - 1); // Already expired

        IAgentCoordinationCore.CoordinationPayload memory payload = _createPayload();
        intent.payloadHash = coordination.getPayloadHash(payload);

        bytes memory signature = _signIntent(intent, aliceKey);

        vm.prank(alice);
        vm.expectRevert("Intent expired");
        coordination.proposeCoordination(intent, signature, payload);
    }

    function testReplayProtection() public {
        _createAndProposeCoordination(); // Uses nonce 1

        // Try to create another coordination with same nonce
        address[] memory participants = new address[](1);
        participants[0] = alice;

        IAgentCoordinationCore.AgentIntent memory intent = _createIntent(participants, 1); // Same nonce
        IAgentCoordinationCore.CoordinationPayload memory payload = _createPayload();
        intent.payloadHash = coordination.getPayloadHash(payload);

        bytes memory signature = _signIntent(intent, aliceKey);

        vm.prank(alice);
        vm.expectRevert("Invalid nonce");
        coordination.proposeCoordination(intent, signature, payload);
    }

    function testGetAgentNonce() public {
        assertEq(coordination.getAgentNonce(alice), 0);
        _createAndProposeCoordination();
        assertEq(coordination.getAgentNonce(alice), 1);
    }

    function testValidateIntent() public view {
        address[] memory participants = new address[](1);
        participants[0] = alice;

        IAgentCoordinationCore.AgentIntent memory intent = _createIntent(participants, 1);
        bytes memory signature = _signIntent(intent, aliceKey);

        (bool valid, string memory reason) = coordination.validateIntent(intent, signature);
        assertTrue(valid);
        assertEq(reason, "");
    }

    // Helper functions
    function _createAndProposeCoordination() internal returns (bytes32) {
        address[] memory participants = new address[](1);
        participants[0] = alice;

        IAgentCoordinationCore.AgentIntent memory intent = _createIntent(participants, 1);
        IAgentCoordinationCore.CoordinationPayload memory payload = _createPayload();
        intent.payloadHash = coordination.getPayloadHash(payload);

        bytes memory signature = _signIntent(intent, aliceKey);

        vm.prank(alice);
        return coordination.proposeCoordination(intent, signature, payload);
    }

    function _createIntent(address[] memory participants, uint64 nonce) internal view returns (IAgentCoordinationCore.AgentIntent memory) {
        return IAgentCoordinationCore.AgentIntent({
            payloadHash: bytes32(0), // Will be set later
            expiry: uint64(block.timestamp + 3600),
            nonce: nonce,
            chainId: uint32(block.chainid),
            agentId: alice,
            coordinationType: keccak256("TEST_V1"),
            maxGasCost: 100000,
            priority: 128,
            dependencyHash: bytes32(0),
            securityLevel: 0,
            participants: participants,
            coordinationValue: 1 ether
        });
    }

    function _createPayload() internal view returns (IAgentCoordinationCore.CoordinationPayload memory) {
        return IAgentCoordinationCore.CoordinationPayload({
            version: keccak256("v1"),
            coordinationType: keccak256("TEST_V1"),
            coordinationData: abi.encode("test", "data"),
            conditionsHash: keccak256("test conditions"),
            timestamp: block.timestamp,
            metadata: ""
        });
    }

    function _signIntent(IAgentCoordinationCore.AgentIntent memory intent, uint256 privateKey) internal view returns (bytes memory) {
        bytes32 intentHash = coordination.getIntentHash(intent);
        bytes32 domainSeparator = coordination.getDomainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, intentHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _acceptCoordination(bytes32 intentHash, address participant, uint256 privateKey) internal {
        IAgentCoordinationCore.AcceptanceAttestation memory attestation = IAgentCoordinationCore.AcceptanceAttestation({
            intentHash: intentHash,
            participant: participant,
            nonce: 1,
            expiry: uint64(block.timestamp + 1800),
            conditionsHash: keccak256("agreed"),
            signature: ""
        });

        bytes32 acceptanceHash = coordination.getAcceptanceHash(attestation);
        bytes32 domainSeparator = coordination.getDomainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, acceptanceHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        attestation.signature = abi.encodePacked(r, s, v);

        coordination.acceptCoordination(intentHash, attestation);
    }
}