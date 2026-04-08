// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {TrustRegistry, IENS} from "src/TrustRegistry.sol";
import {ITrustRegistry, TrustLevel, TrustAttestation, ValidationParams} from "src/ITrustRegistry.sol";

/// @notice Mock ENS Registry for testing
contract MockENS is IENS {
    mapping(bytes32 => address) private _owners;
    mapping(address => mapping(address => bool)) private _operators;

    function setOwner(bytes32 node, address _owner) external {
        _owners[node] = _owner;
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operators[msg.sender][operator] = approved;
    }

    function owner(bytes32 node) external view override returns (address) {
        return _owners[node];
    }

    function isApprovedForAll(address owner_, address operator) external view override returns (bool) {
        return _operators[owner_][operator];
    }
}

contract TrustRegistryTest is Test {
    TrustRegistry public registry;
    MockENS public ens;

    // Test accounts
    uint256 aliceKey = 0xA11CE;
    uint256 bobKey = 0xB0B;
    uint256 carolKey = 0xCA201;
    uint256 daveKey = 0xDA7E;
    uint256 eveKey = 0xE7E;

    address alice;
    address bob;
    address carol;
    address dave;
    address eve;

    // ENS namehashes (simplified for testing)
    bytes32 aliceNode = keccak256("alice.eth");
    bytes32 bobNode = keccak256("bob.eth");
    bytes32 carolNode = keccak256("carol.eth");
    bytes32 daveNode = keccak256("dave.eth");
    bytes32 eveNode = keccak256("eve.eth");

    function setUp() public {
        // Derive addresses from keys
        alice = vm.addr(aliceKey);
        bob = vm.addr(bobKey);
        carol = vm.addr(carolKey);
        dave = vm.addr(daveKey);
        eve = vm.addr(eveKey);

        // Deploy mock ENS
        ens = new MockENS();

        // Set up ENS ownership
        ens.setOwner(aliceNode, alice);
        ens.setOwner(bobNode, bob);
        ens.setOwner(carolNode, carol);
        ens.setOwner(daveNode, dave);
        ens.setOwner(eveNode, eve);

        // Deploy registry
        registry = new TrustRegistry(address(ens));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BASIC TRUST TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SetTrust_Basic() public {
        TrustAttestation memory att = TrustAttestation({
            trustorNode: aliceNode, trusteeNode: bobNode, level: TrustLevel.Full, scope: bytes32(0), expiry: 0, nonce: 1
        });

        bytes memory sig = _signAttestation(att, aliceKey);

        vm.expectEmit(true, true, true, true);
        emit ITrustRegistry.TrustSet(aliceNode, bobNode, TrustLevel.Full, bytes32(0), 0);

        registry.setTrust(att, sig);

        (TrustLevel level, bytes32 scope, uint64 expiry) = registry.getTrust(aliceNode, bobNode);
        assertEq(uint8(level), uint8(TrustLevel.Full));
        assertEq(scope, bytes32(0));
        assertEq(expiry, 0);
    }

    function test_SetTrust_WithExpiry() public {
        uint64 futureExpiry = uint64(block.timestamp + 365 days);

        TrustAttestation memory att = TrustAttestation({
            trustorNode: aliceNode,
            trusteeNode: bobNode,
            level: TrustLevel.Marginal,
            scope: bytes32(0),
            expiry: futureExpiry,
            nonce: 1
        });

        bytes memory sig = _signAttestation(att, aliceKey);
        registry.setTrust(att, sig);

        (TrustLevel level,, uint64 expiry) = registry.getTrust(aliceNode, bobNode);
        assertEq(uint8(level), uint8(TrustLevel.Marginal));
        assertEq(expiry, futureExpiry);
    }

    function test_SetTrust_WithScope() public {
        bytes32 defiScope = keccak256("DEFI");

        TrustAttestation memory att = TrustAttestation({
            trustorNode: aliceNode, trusteeNode: bobNode, level: TrustLevel.Full, scope: defiScope, expiry: 0, nonce: 1
        });

        bytes memory sig = _signAttestation(att, aliceKey);
        registry.setTrust(att, sig);

        (, bytes32 scope,) = registry.getTrust(aliceNode, bobNode);
        assertEq(scope, defiScope);
    }

    function test_RevertWhen_SelfTrust() public {
        TrustAttestation memory att = TrustAttestation({
            trustorNode: aliceNode,
            trusteeNode: aliceNode, // Same as trustor
            level: TrustLevel.Full,
            scope: bytes32(0),
            expiry: 0,
            nonce: 1
        });

        bytes memory sig = _signAttestation(att, aliceKey);

        vm.expectRevert(ITrustRegistry.SelfTrustProhibited.selector);
        registry.setTrust(att, sig);
    }

    function test_RevertWhen_NonceTooLow() public {
        // First attestation
        TrustAttestation memory att1 = TrustAttestation({
            trustorNode: aliceNode, trusteeNode: bobNode, level: TrustLevel.Full, scope: bytes32(0), expiry: 0, nonce: 5
        });
        registry.setTrust(att1, _signAttestation(att1, aliceKey));
        
        // Verify first call succeeded
        assertEq(registry.getNonce(aliceNode), 5, "Nonce should be 5 after first call");

        // Try with lower nonce
        TrustAttestation memory att2 = TrustAttestation({
            trustorNode: aliceNode,
            trusteeNode: carolNode,
            level: TrustLevel.Full,
            scope: bytes32(0),
            expiry: 0,
            nonce: 3 // Lower than 5
        });

        // Sign BEFORE expectRevert (since _signAttestation makes an external call)
        bytes memory sig2 = _signAttestation(att2, aliceKey);
        
        vm.expectRevert(abi.encodeWithSelector(ITrustRegistry.NonceTooLow.selector, 3, 6));
        registry.setTrust(att2, sig2);
    }

    function test_RevertWhen_ExpiredAttestation() public {
        // Warp to a reasonable timestamp so block.timestamp - 1 isn't 0
        vm.warp(1000);
        
        uint64 expiredTime = uint64(block.timestamp - 1);
        
        TrustAttestation memory att = TrustAttestation({
            trustorNode: aliceNode,
            trusteeNode: bobNode,
            level: TrustLevel.Full,
            scope: bytes32(0),
            expiry: expiredTime,
            nonce: 1
        });

        // Sign BEFORE expectRevert (since _signAttestation makes an external call)
        bytes memory sig = _signAttestation(att, aliceKey);

        vm.expectRevert(
            abi.encodeWithSelector(
                ITrustRegistry.AttestationExpired.selector, expiredTime, uint64(block.timestamp)
            )
        );
        registry.setTrust(att, sig);
    }

    function test_RevertWhen_InvalidSignature() public {
        TrustAttestation memory att = TrustAttestation({
            trustorNode: aliceNode, trusteeNode: bobNode, level: TrustLevel.Full, scope: bytes32(0), expiry: 0, nonce: 1
        });

        // Sign with Bob's key instead of Alice's
        bytes memory sig = _signAttestation(att, bobKey);

        vm.expectRevert(ITrustRegistry.InvalidSignature.selector);
        registry.setTrust(att, sig);
    }

    function test_RevertWhen_ENSNameNotFound() public {
        bytes32 unknownNode = keccak256("unknown.eth");

        TrustAttestation memory att = TrustAttestation({
            trustorNode: unknownNode,
            trusteeNode: bobNode,
            level: TrustLevel.Full,
            scope: bytes32(0),
            expiry: 0,
            nonce: 1
        });

        bytes memory sig = _signAttestation(att, aliceKey);

        vm.expectRevert(abi.encodeWithSelector(ITrustRegistry.ENSNameNotFound.selector, unknownNode));
        registry.setTrust(att, sig);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TRUST REVOCATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_RevokeTrust() public {
        // Set up trust first
        TrustAttestation memory att = TrustAttestation({
            trustorNode: aliceNode, trusteeNode: bobNode, level: TrustLevel.Full, scope: bytes32(0), expiry: 0, nonce: 1
        });
        registry.setTrust(att, _signAttestation(att, aliceKey));

        // Revoke
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit ITrustRegistry.TrustRevoked(aliceNode, bobNode, "Bad behavior");
        registry.revokeTrustFor(aliceNode, bobNode, "Bad behavior");

        // Verify level is now None
        (TrustLevel level,,) = registry.getTrust(aliceNode, bobNode);
        assertEq(uint8(level), uint8(TrustLevel.None));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // WEB OF TRUST VALIDATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ValidateAgent_SelfValidation() public {
        ValidationParams memory params = _defaultParams();

        (bool isValid, uint8 pathLength,,) = registry.validateAgent(aliceNode, aliceNode, params);

        assertTrue(isValid);
        assertEq(pathLength, 0);
    }

    function test_ValidateAgent_DirectTrust() public {
        // Alice trusts Bob fully
        _setTrust(aliceNode, bobNode, TrustLevel.Full, aliceKey, 1);

        ValidationParams memory params = _defaultParams();

        (bool isValid, uint8 pathLength,, uint8 fullCount) = registry.validateAgent(aliceNode, bobNode, params);

        assertTrue(isValid);
        assertEq(pathLength, 0);
        assertEq(fullCount, 1);
    }

    function test_ValidateAgent_FullTrustDelegation() public {
        // Alice trusts Bob fully, Bob trusts Carol marginally
        _setTrust(aliceNode, bobNode, TrustLevel.Full, aliceKey, 1);
        _setTrust(bobNode, carolNode, TrustLevel.Marginal, bobKey, 1);

        ValidationParams memory params = _defaultParams();

        (bool isValid, uint8 pathLength,, uint8 fullCount) = registry.validateAgent(aliceNode, carolNode, params);

        assertTrue(isValid);
        assertEq(pathLength, 1);
        assertEq(fullCount, 1);
    }

    function test_ValidateAgent_MarginalAccumulation() public {
        // Alice trusts Bob, Carol, Dave marginally
        // All three trust Eve
        _setTrust(aliceNode, bobNode, TrustLevel.Marginal, aliceKey, 1);
        _setTrust(aliceNode, carolNode, TrustLevel.Marginal, aliceKey, 2);
        _setTrust(aliceNode, daveNode, TrustLevel.Marginal, aliceKey, 3);

        _setTrust(bobNode, eveNode, TrustLevel.Marginal, bobKey, 1);
        _setTrust(carolNode, eveNode, TrustLevel.Marginal, carolKey, 1);
        _setTrust(daveNode, eveNode, TrustLevel.Marginal, daveKey, 1);

        ValidationParams memory params = ValidationParams({
            maxPathLength: 5, marginalThreshold: 3, fullThreshold: 1, scope: bytes32(0), enforceExpiry: true
        });

        (bool isValid,, uint8 marginalCount,) = registry.validateAgent(aliceNode, eveNode, params);

        assertTrue(isValid);
        assertEq(marginalCount, 3);
    }

    function test_ValidateAgent_FailsWithInsufficientMarginal() public {
        // Alice trusts Bob and Carol marginally (only 2)
        // Both trust Eve
        _setTrust(aliceNode, bobNode, TrustLevel.Marginal, aliceKey, 1);
        _setTrust(aliceNode, carolNode, TrustLevel.Marginal, aliceKey, 2);

        _setTrust(bobNode, eveNode, TrustLevel.Marginal, bobKey, 1);
        _setTrust(carolNode, eveNode, TrustLevel.Marginal, carolKey, 1);

        ValidationParams memory params = ValidationParams({
            maxPathLength: 5,
            marginalThreshold: 3, // Requires 3
            fullThreshold: 1,
            scope: bytes32(0),
            enforceExpiry: true
        });

        (bool isValid,, uint8 marginalCount,) = registry.validateAgent(aliceNode, eveNode, params);

        assertFalse(isValid);
        assertEq(marginalCount, 2);
    }

    function test_ValidateAgent_RespectsExpiry() public {
        // Alice trusts Bob with expiry in the past
        uint64 pastExpiry = uint64(block.timestamp - 1);

        TrustAttestation memory att = TrustAttestation({
            trustorNode: aliceNode,
            trusteeNode: bobNode,
            level: TrustLevel.Full,
            scope: bytes32(0),
            expiry: uint64(block.timestamp + 1 days), // Valid when set
            nonce: 1
        });
        registry.setTrust(att, _signAttestation(att, aliceKey));

        // Fast forward past expiry
        vm.warp(block.timestamp + 2 days);

        ValidationParams memory params = ValidationParams({
            maxPathLength: 5, marginalThreshold: 3, fullThreshold: 1, scope: bytes32(0), enforceExpiry: true
        });

        (bool isValid,,,) = registry.validateAgent(aliceNode, bobNode, params);

        assertFalse(isValid);
    }

    function test_ValidateAgent_RespectsScope() public {
        bytes32 defiScope = keccak256("DEFI");
        bytes32 gamingScope = keccak256("GAMING");

        // Alice trusts Bob for DEFI only
        TrustAttestation memory att = TrustAttestation({
            trustorNode: aliceNode, trusteeNode: bobNode, level: TrustLevel.Full, scope: defiScope, expiry: 0, nonce: 1
        });
        registry.setTrust(att, _signAttestation(att, aliceKey));

        // Validate with DEFI scope - should pass
        ValidationParams memory defiParams = ValidationParams({
            maxPathLength: 5, marginalThreshold: 3, fullThreshold: 1, scope: defiScope, enforceExpiry: true
        });
        (bool isValidDefi,,,) = registry.validateAgent(aliceNode, bobNode, defiParams);
        assertTrue(isValidDefi);

        // Validate with GAMING scope - should fail
        ValidationParams memory gamingParams = ValidationParams({
            maxPathLength: 5, marginalThreshold: 3, fullThreshold: 1, scope: gamingScope, enforceExpiry: true
        });
        (bool isValidGaming,,,) = registry.validateAgent(aliceNode, bobNode, gamingParams);
        assertFalse(isValidGaming);
    }

    function test_ValidateAgent_PathLengthLimit() public {
        // Create a long chain: Alice -> Bob -> Carol -> Dave -> Eve
        _setTrust(aliceNode, bobNode, TrustLevel.Full, aliceKey, 1);
        _setTrust(bobNode, carolNode, TrustLevel.Full, bobKey, 1);
        _setTrust(carolNode, daveNode, TrustLevel.Full, carolKey, 1);
        _setTrust(daveNode, eveNode, TrustLevel.Full, daveKey, 1);

        // Should fail with maxPathLength of 2
        ValidationParams memory shortParams = ValidationParams({
            maxPathLength: 2, marginalThreshold: 3, fullThreshold: 1, scope: bytes32(0), enforceExpiry: true
        });
        (bool isValidShort,,,) = registry.validateAgent(aliceNode, eveNode, shortParams);
        assertFalse(isValidShort);

        // Should pass with maxPathLength of 5
        ValidationParams memory longParams = ValidationParams({
            maxPathLength: 5, marginalThreshold: 3, fullThreshold: 1, scope: bytes32(0), enforceExpiry: true
        });
        (bool isValidLong,,,) = registry.validateAgent(aliceNode, eveNode, longParams);
        assertTrue(isValidLong);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // IDENTITY GATE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SetIdentityGate() public {
        bytes32 coordType = keccak256("MEV_COORDINATION");
        ValidationParams memory params = _defaultParams();

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit ITrustRegistry.IdentityGateSet(coordType, aliceNode, params.maxPathLength, params.marginalThreshold);
        registry.setIdentityGate(coordType, aliceNode, params);

        (bytes32 gatekeeper, ValidationParams memory storedParams, bool enabled) = registry.getIdentityGate(coordType);
        assertEq(gatekeeper, aliceNode);
        assertTrue(enabled);
        assertEq(storedParams.maxPathLength, params.maxPathLength);
    }

    function test_ValidateParticipant_NoGate() public {
        bytes32 coordType = keccak256("OPEN_COORDINATION");

        // No gate set - should return true
        bool isValid = registry.validateParticipant(coordType, bobNode);
        assertTrue(isValid);
    }

    function test_ValidateParticipant_WithGate() public {
        bytes32 coordType = keccak256("MEV_COORDINATION");

        // Alice sets up a gate
        vm.prank(alice);
        registry.setIdentityGate(coordType, aliceNode, _defaultParams());

        // Bob is not trusted - should fail
        bool bobValid = registry.validateParticipant(coordType, bobNode);
        assertFalse(bobValid);

        // Alice trusts Carol - she should pass
        _setTrust(aliceNode, carolNode, TrustLevel.Full, aliceKey, 1);
        bool carolValid = registry.validateParticipant(coordType, carolNode);
        assertTrue(carolValid);
    }

    function test_RemoveIdentityGate() public {
        bytes32 coordType = keccak256("MEV_COORDINATION");

        // Set gate
        vm.prank(alice);
        registry.setIdentityGate(coordType, aliceNode, _defaultParams());

        // Remove gate
        vm.prank(alice);
        registry.removeIdentityGate(coordType);

        // Gate should be disabled
        (,, bool enabled) = registry.getIdentityGate(coordType);
        assertFalse(enabled);

        // Validation should now pass for anyone
        bool bobValid = registry.validateParticipant(coordType, bobNode);
        assertTrue(bobValid);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BATCH OPERATIONS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_SetTrustBatch() public {
        TrustAttestation[] memory atts = new TrustAttestation[](3);
        bytes[] memory sigs = new bytes[](3);

        atts[0] = TrustAttestation({
            trustorNode: aliceNode, trusteeNode: bobNode, level: TrustLevel.Full, scope: bytes32(0), expiry: 0, nonce: 1
        });
        atts[1] = TrustAttestation({
            trustorNode: aliceNode,
            trusteeNode: carolNode,
            level: TrustLevel.Marginal,
            scope: bytes32(0),
            expiry: 0,
            nonce: 2
        });
        atts[2] = TrustAttestation({
            trustorNode: aliceNode,
            trusteeNode: daveNode,
            level: TrustLevel.Marginal,
            scope: bytes32(0),
            expiry: 0,
            nonce: 3
        });

        sigs[0] = _signAttestation(atts[0], aliceKey);
        sigs[1] = _signAttestation(atts[1], aliceKey);
        sigs[2] = _signAttestation(atts[2], aliceKey);

        registry.setTrustBatch(atts, sigs);

        (TrustLevel bobLevel,,) = registry.getTrust(aliceNode, bobNode);
        (TrustLevel carolLevel,,) = registry.getTrust(aliceNode, carolNode);
        (TrustLevel daveLevel,,) = registry.getTrust(aliceNode, daveNode);

        assertEq(uint8(bobLevel), uint8(TrustLevel.Full));
        assertEq(uint8(carolLevel), uint8(TrustLevel.Marginal));
        assertEq(uint8(daveLevel), uint8(TrustLevel.Marginal));
    }

    function test_ValidateAgentBatch() public {
        // Alice trusts Bob and Carol, but not Dave
        _setTrust(aliceNode, bobNode, TrustLevel.Full, aliceKey, 1);
        _setTrust(aliceNode, carolNode, TrustLevel.Full, aliceKey, 2);

        bytes32[] memory targets = new bytes32[](3);
        targets[0] = bobNode;
        targets[1] = carolNode;
        targets[2] = daveNode;

        bool[] memory results = registry.validateAgentBatch(aliceNode, targets, _defaultParams());

        assertTrue(results[0]); // Bob is trusted
        assertTrue(results[1]); // Carol is trusted
        assertFalse(results[2]); // Dave is not trusted
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // QUERY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetTrustees() public {
        _setTrust(aliceNode, bobNode, TrustLevel.Full, aliceKey, 1);
        _setTrust(aliceNode, carolNode, TrustLevel.Marginal, aliceKey, 2);
        _setTrust(aliceNode, daveNode, TrustLevel.None, aliceKey, 3);

        // Get all (including None)
        bytes32[] memory allTrustees = registry.getTrustees(aliceNode, TrustLevel.None);
        assertEq(allTrustees.length, 3);

        // Get Marginal and above
        bytes32[] memory marginalTrustees = registry.getTrustees(aliceNode, TrustLevel.Marginal);
        assertEq(marginalTrustees.length, 2);

        // Get Full only
        bytes32[] memory fullTrustees = registry.getTrustees(aliceNode, TrustLevel.Full);
        assertEq(fullTrustees.length, 1);
        assertEq(fullTrustees[0], bobNode);
    }

    function test_GetTrustors() public {
        _setTrust(aliceNode, daveNode, TrustLevel.Full, aliceKey, 1);
        _setTrust(bobNode, daveNode, TrustLevel.Marginal, bobKey, 1);
        _setTrust(carolNode, daveNode, TrustLevel.Full, carolKey, 1);

        bytes32[] memory trustors = registry.getTrustors(daveNode, TrustLevel.Marginal);
        assertEq(trustors.length, 3);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _defaultParams() internal pure returns (ValidationParams memory) {
        return ValidationParams({
            maxPathLength: 5, marginalThreshold: 3, fullThreshold: 1, scope: bytes32(0), enforceExpiry: true
        });
    }

    function _setTrust(bytes32 trustorNode, bytes32 trusteeNode, TrustLevel level, uint256 signerKey, uint64 nonce)
        internal
    {
        TrustAttestation memory att = TrustAttestation({
            trustorNode: trustorNode, trusteeNode: trusteeNode, level: level, scope: bytes32(0), expiry: 0, nonce: nonce
        });
        registry.setTrust(att, _signAttestation(att, signerKey));
    }

    function _signAttestation(TrustAttestation memory att, uint256 privateKey) internal view returns (bytes memory) {
        bytes32 digest = registry.hashAttestation(att);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        return abi.encodePacked(r, s, v);
    }
}
