// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../AgentCoordinationFramework.sol";

contract AgentCoordinationTest is Test {
    AgentCoordinationFramework core;
    address alice = address(0xA11CE);
    address bob   = address(0xB0B);

    function setUp() public {
        core = new AgentCoordinationFramework();
    }

    function testProposeAndExecute() public {
        IAgentCoordinationCore.AgentIntent memory intent;
        IAgentCoordinationCore.CoordinationPayload memory payload;

        intent.payloadHash = bytes32(0); // derived in contract
        intent.expiry = uint64(block.timestamp + 3600);
        intent.nonce = 1;
        intent.chainId = uint32(block.chainid);
        intent.agentId = alice;
        intent.coordinationType = keccak256("ARBITRAGE_COORD_V1");
        intent.maxGasCost = 0;
        intent.priority = 0;
        intent.dependencyHash = bytes32(0);
        intent.securityLevel = 0;
        address[] memory parts = new address[](2);
        parts[0] = alice;
        parts[1] = bob;
        intent.participants = parts;
        intent.coordinationValue = 0;

        payload.version = keccak256("v1");
        payload.coordinationType = intent.coordinationType;
        payload.coordinationData = bytes("hello");
        payload.conditionsHash = keccak256("c");
        payload.timestamp = block.timestamp;
        payload.metadata = "";

        bytes memory sig = ""; // skeleton ignores signature

        bytes32 h = core.proposeCoordination(intent, sig, payload);
        assertTrue(h != bytes32(0));

        vm.prank(bob);
        core.acceptCoordination(h, "");

        (bool success, bytes memory result) = core.executeCoordination(h, payload, "");
        assertTrue(success);
        assertEq(result, payload.coordinationData);
    }
}
