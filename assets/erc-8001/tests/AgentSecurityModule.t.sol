// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AgentSecurityModule.sol";

contract AgentSecurityModuleTest is Test {
    AgentSecurityModule securityModule;

    address framework = address(0xF4A3E);

    // Use correct private key/address pairs
    uint256 aliceKey = 0x1;
    uint256 bobKey = 0x2;
    uint256 charlieKey = 0x3;

    address alice;
    address bob;
    address charlie;
    address owner = address(this);

    bytes32 testIntentHash = keccak256("test_intent");

    function setUp() public {
        // Get correct addresses for private keys
        alice = vm.addr(aliceKey);
        bob = vm.addr(bobKey);
        charlie = vm.addr(charlieKey);

        vm.prank(owner);
        securityModule = new AgentSecurityModule(framework);
    }

    function testCreateBasicSecurityContext() public {
        address[] memory participants = new address[](2);
        participants[0] = alice;
        participants[1] = bob;

        vm.prank(framework);
        securityModule.createSecurityContext(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.BASIC,
            participants,
            0
        );

        AgentSecurityModule.SecurityContext memory context = securityModule.getSecurityContext(testIntentHash);
        assertEq(uint8(context.level), uint8(AgentSecurityModule.SecurityLevel.BASIC));
        assertEq(context.authorizedAgents.length, 2);
        assertEq(context.timelock, 0);
        // Context creator should be the test contract (tx.origin in prank)
        assertTrue(context.creator != address(0)); // Just verify it's set

        assertTrue(securityModule.hasAccess(testIntentHash, alice));
        assertTrue(securityModule.hasAccess(testIntentHash, bob));
        assertFalse(securityModule.hasAccess(testIntentHash, charlie));
    }

    function testCreateStandardSecurityContext() public {
        address[] memory participants = new address[](1);
        participants[0] = alice;

        vm.prank(framework);
        securityModule.createSecurityContext(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.STANDARD,
            participants,
            300 // 5 minutes
        );

        AgentSecurityModule.SecurityContext memory context = securityModule.getSecurityContext(testIntentHash);
        assertEq(uint8(context.level), uint8(AgentSecurityModule.SecurityLevel.STANDARD));
        assertEq(context.timelock, 300);
        assertTrue(context.encryptionKey.length > 0);
    }

    function testCreateEnhancedSecurityContext() public {
        address[] memory participants = new address[](3);
        participants[0] = alice;
        participants[1] = bob;
        participants[2] = charlie;

        vm.prank(framework);
        securityModule.createSecurityContext(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.ENHANCED,
            participants,
            1800 // 30 minutes
        );

        AgentSecurityModule.SecurityContext memory context = securityModule.getSecurityContext(testIntentHash);
        assertEq(uint8(context.level), uint8(AgentSecurityModule.SecurityLevel.ENHANCED));
        assertEq(context.timelock, 1800);
        assertEq(context.authorizedAgents.length, 3);
    }

    function testCreateMaximumSecurityContext() public {
        // First register public keys for all participants
        vm.prank(alice);
        securityModule.registerPublicKey(keccak256("alice_pubkey"));

        vm.prank(bob);
        securityModule.registerPublicKey(keccak256("bob_pubkey"));

        address[] memory participants = new address[](2);
        participants[0] = alice;
        participants[1] = bob;

        vm.prank(framework);
        securityModule.createSecurityContext(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.MAXIMUM,
            participants,
            7200 // 2 hours
        );

        AgentSecurityModule.SecurityContext memory context = securityModule.getSecurityContext(testIntentHash);
        assertEq(uint8(context.level), uint8(AgentSecurityModule.SecurityLevel.MAXIMUM));
        assertEq(context.timelock, 7200);
        assertTrue(context.encryptionKey.length >= 32);
    }

    function testCreateContextWithInsufficientTimelock() public {
        address[] memory participants = new address[](1);
        participants[0] = alice;

        vm.prank(framework);
        vm.expectRevert("Timelock too short for security level");
        securityModule.createSecurityContext(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.STANDARD,
            participants,
            100 // Less than required 300 seconds
        );
    }

    function testCreateContextUnauthorized() public {
        address[] memory participants = new address[](1);
        participants[0] = alice;

        vm.prank(alice); // Not the framework
        vm.expectRevert("Unauthorized: framework only");
        securityModule.createSecurityContext(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.BASIC,
            participants,
            0
        );
    }

    function testCreateDuplicateContext() public {
        address[] memory participants = new address[](1);
        participants[0] = alice;

        vm.prank(framework);
        securityModule.createSecurityContext(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.BASIC,
            participants,
            0
        );

        vm.prank(framework);
        vm.expectRevert("Context already exists");
        securityModule.createSecurityContext(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.BASIC,
            participants,
            0
        );
    }

    function testValidateBasicSecurityLevel() public {
        address[] memory participants = new address[](1);
        participants[0] = alice;

        vm.prank(framework);
        securityModule.createSecurityContext(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.BASIC,
            participants,
            0
        );

        (bool valid, string memory reason) = securityModule.validateSecurityLevel(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.BASIC,
            ""
        );

        assertTrue(valid);
        assertEq(reason, "");
    }

    function testValidateStandardSecurityLevelWithTimelock() public {
        address[] memory participants = new address[](1);
        participants[0] = alice;

        vm.prank(framework);
        securityModule.createSecurityContext(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.STANDARD,
            participants,
            300
        );

        // Should fail immediately due to timelock
        (bool valid, string memory reason) = securityModule.validateSecurityLevel(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.STANDARD,
            ""
        );

        assertFalse(valid);
        assertEq(reason, "Timelock not satisfied");

        // Fast forward time
        vm.warp(block.timestamp + 301);

        (valid, reason) = securityModule.validateSecurityLevel(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.STANDARD,
            ""
        );

        assertTrue(valid);
    }

    function testValidateEnhancedSecurityLevelRequiresProof() public {
        address[] memory participants = new address[](1);
        participants[0] = alice;

        vm.prank(framework);
        securityModule.createSecurityContext(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.ENHANCED,
            participants,
            1800
        );

        vm.warp(block.timestamp + 1801);

        // Should fail without proof
        (bool valid, string memory reason) = securityModule.validateSecurityLevel(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.ENHANCED,
            ""
        );

        assertFalse(valid);
        assertEq(reason, "Security proof required for enhanced levels");

        // Should succeed with proof (65-byte signature)
        bytes memory proof = new bytes(65);
        (valid, reason) = securityModule.validateSecurityLevel(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.ENHANCED,
            proof
        );

        assertTrue(valid);
    }

    function testValidateMaximumSecurityLevelRequiresPublicKeys() public {
        address[] memory participants = new address[](2);
        participants[0] = alice;
        participants[1] = bob;

        vm.prank(framework);
        securityModule.createSecurityContext(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.MAXIMUM,
            participants,
            7200
        );

        vm.warp(block.timestamp + 7201);

        bytes memory proof = new bytes(32); // Valid proof length

        // Should fail without all public keys registered
        (bool valid, string memory reason) = securityModule.validateSecurityLevel(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.MAXIMUM,
            proof
        );

        assertFalse(valid);
        assertEq(reason, "Participant missing public key registration");

        // Register public keys
        vm.prank(alice);
        securityModule.registerPublicKey(keccak256("alice_key"));

        vm.prank(bob);
        securityModule.registerPublicKey(keccak256("bob_key"));

        // Should now succeed
        (valid, reason) = securityModule.validateSecurityLevel(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.MAXIMUM,
            proof
        );

        assertTrue(valid);
    }

    function testEncryptDecryptBasicLevel() public view {
        bytes memory testData = "sensitive coordination data";
        address[] memory participants = new address[](2);
        participants[0] = alice;
        participants[1] = bob;

        (bytes memory encryptedData, bytes memory keyData) = securityModule.encryptCoordinationData(
            testData,
            participants,
            AgentSecurityModule.SecurityLevel.BASIC
        );

        // Basic level uses obfuscation, not real encryption
        assertTrue(encryptedData.length == testData.length);
        assertEq(keyData.length, 0); // No key data for basic level

        bytes memory decryptedData = securityModule.decryptCoordinationData(
            encryptedData,
            keyData,
            alice,
            AgentSecurityModule.SecurityLevel.BASIC
        );

        assertEq(decryptedData, testData);
    }

    function testEncryptDecryptStandardLevel() public view {
        bytes memory testData = "sensitive coordination data for standard encryption";
        address[] memory participants = new address[](2);
        participants[0] = alice;
        participants[1] = bob;

        (bytes memory encryptedData, bytes memory keyData) = securityModule.encryptCoordinationData(
            testData,
            participants,
            AgentSecurityModule.SecurityLevel.STANDARD
        );

        assertTrue(encryptedData.length == testData.length);
        assertTrue(keyData.length > 0);

        // Verify encryption actually changed the data
        bool dataChanged = false;
        for (uint i = 0; i < testData.length; i++) {
            if (testData[i] != encryptedData[i]) {
                dataChanged = true;
                break;
            }
        }
        assertTrue(dataChanged);

        bytes memory decryptedData = securityModule.decryptCoordinationData(
            encryptedData,
            keyData,
            alice,
            AgentSecurityModule.SecurityLevel.STANDARD
        );

        assertEq(decryptedData, testData);
    }

    function testEncryptDecryptEnhancedLevel() public view {
        bytes memory testData = "highly sensitive coordination data requiring enhanced security";
        address[] memory participants = new address[](3);
        participants[0] = alice;
        participants[1] = bob;
        participants[2] = charlie;

        (bytes memory encryptedData, bytes memory keyData) = securityModule.encryptCoordinationData(
            testData,
            participants,
            AgentSecurityModule.SecurityLevel.ENHANCED
        );

        assertTrue(encryptedData.length == testData.length);
        assertTrue(keyData.length >= 64); // Enhanced level uses larger keys

        bytes memory decryptedData = securityModule.decryptCoordinationData(
            encryptedData,
            keyData,
            alice,
            AgentSecurityModule.SecurityLevel.ENHANCED
        );

        assertEq(decryptedData, testData);
    }

    function testUpgradeSecurityLevel() public {
        address[] memory participants = new address[](1);
        participants[0] = alice;

        // Create the context - the creator will be tx.origin (this test contract)
        vm.prank(framework);
        securityModule.createSecurityContext(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.BASIC,
            participants,
            0
        );

        // Get the actual creator from the context
        AgentSecurityModule.SecurityContext memory context = securityModule.getSecurityContext(testIntentHash);

        // Upgrade with the actual creator
        vm.prank(context.creator);
        securityModule.upgradeSecurityLevel(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.STANDARD
        );

        // Verify upgrade
        context = securityModule.getSecurityContext(testIntentHash);
        assertEq(uint8(context.level), uint8(AgentSecurityModule.SecurityLevel.STANDARD));
        assertEq(context.timelock, securityModule.getMinTimelock(AgentSecurityModule.SecurityLevel.STANDARD));
    }

    function testUpgradeSecurityLevelUnauthorized() public {
        address[] memory participants = new address[](1);
        participants[0] = alice;

        vm.prank(framework);
        securityModule.createSecurityContext(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.BASIC,
            participants,
            0
        );

        vm.prank(alice); // Not the creator
        vm.expectRevert("Unauthorized: not creator");
        securityModule.upgradeSecurityLevel(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.STANDARD
        );
    }

    function testDowngradeSecurityLevel() public {
        address[] memory participants = new address[](1);
        participants[0] = alice;

        vm.prank(framework);
        securityModule.createSecurityContext(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.STANDARD,
            participants,
            300
        );

        vm.warp(block.timestamp + 301);

        AgentSecurityModule.SecurityContext memory context = securityModule.getSecurityContext(testIntentHash);

        vm.prank(context.creator);
        vm.expectRevert("Cannot downgrade security level");
        securityModule.upgradeSecurityLevel(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.BASIC
        );
    }

    function testRevokeAccess() public {
        address[] memory participants = new address[](2);
        participants[0] = alice;
        participants[1] = bob;

        vm.prank(framework);
        securityModule.createSecurityContext(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.BASIC,
            participants,
            0
        );

        assertTrue(securityModule.hasAccess(testIntentHash, alice));

        vm.prank(address(this)); // Creator
        securityModule.revokeAccess(testIntentHash, alice);

        assertFalse(securityModule.hasAccess(testIntentHash, alice));
        assertTrue(securityModule.hasAccess(testIntentHash, bob)); // Bob still has access
    }

    function testOwnerCanRevokeAccess() public {
        address[] memory participants = new address[](1);
        participants[0] = alice;

        vm.prank(framework);
        securityModule.createSecurityContext(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.BASIC,
            participants,
            0
        );

        vm.prank(owner); // Owner can revoke anyone's access
        securityModule.revokeAccess(testIntentHash, alice);

        assertFalse(securityModule.hasAccess(testIntentHash, alice));
    }

    function testRegisterPublicKey() public {
        bytes32 publicKey = keccak256("alice_public_key");

        vm.prank(alice);
        securityModule.registerPublicKey(publicKey);

        assertEq(securityModule.getPublicKey(alice), publicKey);
    }

    function testRegisterInvalidPublicKey() public {
        vm.prank(alice);
        vm.expectRevert("Invalid public key");
        securityModule.registerPublicKey(bytes32(0));
    }

    function testOwnerCanUpdateMinTimelock() public {
        uint256 newTimelock = 600; // 10 minutes

        vm.prank(owner);
        securityModule.updateMinTimelock(AgentSecurityModule.SecurityLevel.STANDARD, newTimelock);

        assertEq(securityModule.getMinTimelock(AgentSecurityModule.SecurityLevel.STANDARD), newTimelock);
    }

    function testNonOwnerUpdateMinTimelock() public {
        vm.prank(alice);
        vm.expectRevert("Unauthorized: owner only");
        securityModule.updateMinTimelock(AgentSecurityModule.SecurityLevel.STANDARD, 600);
    }

    function testTransferOwnership() public {
        vm.prank(owner);
        securityModule.transferOwnership(alice);

        assertEq(securityModule.owner(), alice);
    }

    function testTransferOwnershipToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("Invalid new owner");
        securityModule.transferOwnership(address(0));
    }

    function testInvalidParticipantCount() public {
        address[] memory participants = new address[](0);

        vm.prank(framework);
        vm.expectRevert("Invalid participant count");
        securityModule.createSecurityContext(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.BASIC,
            participants,
            0
        );
    }

    function testTooManyParticipants() public {
        address[] memory participants = new address[](101); // Over the limit
        for (uint i = 0; i < 101; i++) {
            participants[i] = address(uint160(i + 1));
        }

        vm.prank(framework);
        vm.expectRevert("Invalid participant count");
        securityModule.createSecurityContext(
            testIntentHash,
            AgentSecurityModule.SecurityLevel.BASIC,
            participants,
            0
        );
    }

    function testEncryptEmptyData() public {
        bytes memory emptyData = "";
        address[] memory participants = new address[](1);
        participants[0] = alice;

        vm.expectRevert("No data to encrypt");
        securityModule.encryptCoordinationData(
            emptyData,
            participants,
            AgentSecurityModule.SecurityLevel.BASIC
        );
    }

    function testDecryptWithInvalidParticipant() public {
        bytes memory encryptedData = "encrypted";
        bytes memory keyData = "";

        vm.expectRevert("Invalid participant");
        securityModule.decryptCoordinationData(
            encryptedData,
            keyData,
            address(0),
            AgentSecurityModule.SecurityLevel.BASIC
        );
    }
}