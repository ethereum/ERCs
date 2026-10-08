// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {RegulatedAssetClaimRegistry} from "../contracts/RegulatedAssetClaimRegistry.sol";
import {
    IRegulatedAssetClaimRegistry,
    RegulatedAssetClaim,
    ClaimType,
    ClaimState,
    RoleKind
} from "../contracts/interfaces/IRegulatedAssetClaimRegistry.sol";

contract RegulatedAssetClaimRegistryTest is Test {
    bytes32 constant PROPOSE_TYPEHASH = keccak256(
        "Propose(bytes32 assetId,uint8 claimType,bytes32 schemaId,bytes32 schemaHash,uint64 version,"
        "uint64 validFrom,uint64 validUntil,uint8 claimState,bytes32[] tags,bytes32 contentHash,"
        "address author,string uri,uint256 nonce,uint64 deadline)"
    );
    bytes32 constant VALIDATE_TYPEHASH = keccak256(
        "Validate(bytes32 assetId,uint8 claimType,uint64 version,uint8 targetState,uint256 nonce,uint64 deadline)"
    );
    bytes32 constant ACTIVATE_TYPEHASH = keccak256(
        "Activate(bytes32 assetId,uint8 claimType,uint64 version,uint8 targetState,uint256 nonce,uint64 deadline)"
    );
    bytes32 constant SUSPEND_TYPEHASH = keccak256(
        "Suspend(bytes32 assetId,uint8 claimType,uint64 version,uint8 targetState,uint256 nonce,uint64 deadline)"
    );
    bytes32 constant REVOKE_TYPEHASH = keccak256(
        "Revoke(bytes32 assetId,uint8 claimType,uint64 version,uint8 targetState,uint256 nonce,uint64 deadline)"
    );

    RegulatedAssetClaimRegistry registry;

    address admin = makeAddr("admin");
    address assetContract = makeAddr("assetContract");
    address relayer = makeAddr("relayer");
    address stranger = makeAddr("stranger");

    address author;
    uint256 authorPk;
    address validator;
    uint256 validatorPk;
    address activator;
    uint256 activatorPk;

    ClaimType constant CLAIM_TYPE = ClaimType.VALUATION;
    bytes32 assetId;

    function setUp() public {
        (author, authorPk) = makeAddrAndKey("author");
        (validator, validatorPk) = makeAddrAndKey("validator");
        (activator, activatorPk) = makeAddrAndKey("activator");

        registry = new RegulatedAssetClaimRegistry(admin);

        vm.startPrank(admin);
        assetId = registry.registerAsset(assetContract, 0, block.chainid);
        registry.grantRoleToClaimType(assetId, CLAIM_TYPE, RoleKind.AUTHOR, author);
        registry.grantRoleToClaimType(assetId, CLAIM_TYPE, RoleKind.VALIDATOR, validator);
        registry.grantRoleToClaimType(assetId, CLAIM_TYPE, RoleKind.ACTIVATOR, activator);
        vm.stopPrank();
    }

    // ---------- lifecycle happy path ----------

    function test_ProposeValidateActivate() public {
        _propose(1);
        assertEq(uint256(registry.getClaim(assetId, CLAIM_TYPE, 1).claimState), uint256(ClaimState.PROPOSED));
        assertEq(registry.nonces(author), 1);

        _validate(1);
        assertEq(uint256(registry.getClaim(assetId, CLAIM_TYPE, 1).claimState), uint256(ClaimState.VALID));

        _activate(1);
        assertEq(uint256(registry.getClaim(assetId, CLAIM_TYPE, 1).claimState), uint256(ClaimState.ACTIVE));

        RegulatedAssetClaim[] memory active = registry.getActiveClaims(assetId, CLAIM_TYPE);
        assertEq(active.length, 1);
        assertEq(active[0].version, 1);
    }

    function test_SuspendReturnsToValid() public {
        _propose(1);
        _validate(1);
        _activate(1);

        uint256 nonce = registry.nonces(activator);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(activatorPk, _lifecycleHash(SUSPEND_TYPEHASH, 1, ClaimState.VALID, nonce, deadline));
        vm.prank(relayer);
        registry.suspendClaim(assetId, CLAIM_TYPE, 1, activator, nonce, deadline, sig);

        assertEq(uint256(registry.getClaim(assetId, CLAIM_TYPE, 1).claimState), uint256(ClaimState.VALID));
        assertEq(registry.getActiveClaims(assetId, CLAIM_TYPE).length, 0);
    }

    function test_RevokeFromActive() public {
        _propose(1);
        _validate(1);
        _activate(1);

        uint256 nonce = registry.nonces(validator);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(validatorPk, _lifecycleHash(REVOKE_TYPEHASH, 1, ClaimState.REVOKED, nonce, deadline));
        vm.prank(relayer);
        registry.revokeClaim(assetId, CLAIM_TYPE, 1, validator, nonce, deadline, sig);

        assertEq(uint256(registry.getClaim(assetId, CLAIM_TYPE, 1).claimState), uint256(ClaimState.REVOKED));
    }

    // ---------- propose reverts ----------

    function test_ProposeRevertsNotAuthor() public {
        RegulatedAssetClaim memory claim = _claim(1);
        claim.author = stranger;
        uint256 nonce = registry.nonces(stranger);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        (, uint256 strangerPk) = makeAddrAndKey("stranger");
        bytes memory sig = _sign(strangerPk, _proposeHash(claim, nonce, deadline));
        vm.prank(relayer);
        vm.expectRevert(RegulatedAssetClaimRegistry.NotAuthorized.selector);
        registry.proposeClaim(claim, nonce, deadline, sig);
    }

    function test_ProposeRevertsWrongInitialState() public {
        RegulatedAssetClaim memory claim = _claim(1);
        claim.claimState = ClaimState.VALID;
        uint256 nonce = registry.nonces(author);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(authorPk, _proposeHash(claim, nonce, deadline));
        vm.prank(relayer);
        vm.expectRevert(RegulatedAssetClaimRegistry.InvalidClaimState.selector);
        registry.proposeClaim(claim, nonce, deadline, sig);
    }

    function test_ProposeRevertsVersionNotIncreasing() public {
        _propose(5);
        RegulatedAssetClaim memory claim = _claim(5);
        uint256 nonce = registry.nonces(author);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(authorPk, _proposeHash(claim, nonce, deadline));
        vm.prank(relayer);
        vm.expectRevert(RegulatedAssetClaimRegistry.VersionNotIncreasing.selector);
        registry.proposeClaim(claim, nonce, deadline, sig);
    }

    function test_ProposeRevertsAssetInactive() public {
        vm.prank(admin);
        registry.removeAsset(assetId);

        RegulatedAssetClaim memory claim = _claim(1);
        uint256 nonce = registry.nonces(author);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(authorPk, _proposeHash(claim, nonce, deadline));
        vm.prank(relayer);
        vm.expectRevert(RegulatedAssetClaimRegistry.AssetNotActive.selector);
        registry.proposeClaim(claim, nonce, deadline, sig);
    }

    function test_ProposeRevertsExpiredDeadline() public {
        RegulatedAssetClaim memory claim = _claim(1);
        uint256 nonce = registry.nonces(author);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(authorPk, _proposeHash(claim, nonce, deadline));
        vm.warp(block.timestamp + 2 hours);
        vm.prank(relayer);
        vm.expectRevert(RegulatedAssetClaimRegistry.SignatureExpired.selector);
        registry.proposeClaim(claim, nonce, deadline, sig);
    }

    function test_ProposeRevertsReplay() public {
        _propose(1);
        // reuse nonce 0 for a new version
        RegulatedAssetClaim memory claim = _claim(2);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(authorPk, _proposeHash(claim, 0, deadline));
        vm.prank(relayer);
        vm.expectRevert(RegulatedAssetClaimRegistry.InvalidNonce.selector);
        registry.proposeClaim(claim, 0, deadline, sig);
    }

    // ---------- lifecycle reverts ----------

    function test_ValidateRevertsAuthorCannotValidate() public {
        // grant the author the VALIDATOR role too, then have the author try to validate own claim
        vm.prank(admin);
        registry.grantRoleToClaimType(assetId, CLAIM_TYPE, RoleKind.VALIDATOR, author);
        _propose(1);

        uint256 nonce = registry.nonces(author);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(authorPk, _lifecycleHash(VALIDATE_TYPEHASH, 1, ClaimState.VALID, nonce, deadline));
        vm.prank(relayer);
        vm.expectRevert(RegulatedAssetClaimRegistry.AuthorCannotValidate.selector);
        registry.validateClaim(assetId, CLAIM_TYPE, 1, author, nonce, deadline, sig);
    }

    function test_ValidateRevertsNotValidator() public {
        _propose(1);
        uint256 nonce = registry.nonces(activator);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(activatorPk, _lifecycleHash(VALIDATE_TYPEHASH, 1, ClaimState.VALID, nonce, deadline));
        vm.prank(relayer);
        vm.expectRevert(RegulatedAssetClaimRegistry.NotAuthorized.selector);
        registry.validateClaim(assetId, CLAIM_TYPE, 1, activator, nonce, deadline, sig);
    }

    function test_ActivateRevertsWrongState() public {
        _propose(1); // still PROPOSED, not VALID
        uint256 nonce = registry.nonces(activator);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(activatorPk, _lifecycleHash(ACTIVATE_TYPEHASH, 1, ClaimState.ACTIVE, nonce, deadline));
        vm.prank(relayer);
        vm.expectRevert(RegulatedAssetClaimRegistry.InvalidClaimState.selector);
        registry.activateClaim(assetId, CLAIM_TYPE, 1, activator, nonce, deadline, sig);
    }

    function test_ValidateRevertsUnknownClaim() public {
        uint256 nonce = registry.nonces(validator);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(validatorPk, _lifecycleHash(VALIDATE_TYPEHASH, 99, ClaimState.VALID, nonce, deadline));
        vm.prank(relayer);
        vm.expectRevert(RegulatedAssetClaimRegistry.ClaimNotFound.selector);
        registry.validateClaim(assetId, CLAIM_TYPE, 99, validator, nonce, deadline, sig);
    }

    // ---------- suspend/revoke work on inactive asset ----------

    function test_RevokeAllowedOnInactiveAsset() public {
        _propose(1);
        _validate(1);
        _activate(1);
        vm.prank(admin);
        registry.removeAsset(assetId);

        uint256 nonce = registry.nonces(validator);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(validatorPk, _lifecycleHash(REVOKE_TYPEHASH, 1, ClaimState.REVOKED, nonce, deadline));
        vm.prank(relayer);
        registry.revokeClaim(assetId, CLAIM_TYPE, 1, validator, nonce, deadline, sig);
        assertEq(uint256(registry.getClaim(assetId, CLAIM_TYPE, 1).claimState), uint256(ClaimState.REVOKED));
    }

    // ---------- expiry ----------

    function test_ExpiryReportedAndExcluded() public {
        RegulatedAssetClaim memory claim = _claim(1);
        claim.validUntil = uint64(block.timestamp + 1 days);
        uint256 nonce = registry.nonces(author);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(authorPk, _proposeHash(claim, nonce, deadline));
        vm.prank(relayer);
        registry.proposeClaim(claim, nonce, deadline, sig);
        _validate(1);
        _activate(1);

        assertEq(registry.getActiveClaims(assetId, CLAIM_TYPE).length, 1);

        vm.warp(block.timestamp + 2 days);
        assertEq(uint256(registry.getClaim(assetId, CLAIM_TYPE, 1).claimState), uint256(ClaimState.EXPIRED));
        assertEq(registry.getActiveClaims(assetId, CLAIM_TYPE).length, 0);
    }

    function test_NotYetValidFromExcludedFromActive() public {
        RegulatedAssetClaim memory claim = _claim(1);
        claim.validFrom = uint64(block.timestamp + 1 days);
        uint256 nonce = registry.nonces(author);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(authorPk, _proposeHash(claim, nonce, deadline));
        vm.prank(relayer);
        registry.proposeClaim(claim, nonce, deadline, sig);
        _validate(1);
        _activate(1);

        // ACTIVE but not yet live
        assertEq(registry.getActiveClaims(assetId, CLAIM_TYPE).length, 0);
        vm.warp(block.timestamp + 2 days);
        assertEq(registry.getActiveClaims(assetId, CLAIM_TYPE).length, 1);
    }

    // ---------- asset registration ----------

    function test_RegisterRevertsNotAdmin() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, bytes32(0))
        );
        registry.registerAsset(makeAddr("x"), 0, block.chainid);
    }

    function test_RegisterRevertsAlreadyRegistered() public {
        vm.prank(admin);
        vm.expectRevert(RegulatedAssetClaimRegistry.AssetAlreadyRegistered.selector);
        registry.registerAsset(assetContract, 0, block.chainid);
    }

    function test_RemoveRevertsNotFound() public {
        vm.prank(admin);
        vm.expectRevert(RegulatedAssetClaimRegistry.AssetNotFound.selector);
        registry.removeAsset(keccak256("nope"));
    }

    function test_GetAssetReferenceRevertsUnknown() public {
        vm.expectRevert(RegulatedAssetClaimRegistry.AssetNotFound.selector);
        registry.getAssetReference(keccak256("nope"));
    }

    function test_GetClaimRevertsUnknown() public {
        vm.expectRevert(RegulatedAssetClaimRegistry.ClaimNotFound.selector);
        registry.getClaim(assetId, CLAIM_TYPE, 1);
    }

    // ---------- roles & asset views ----------

    function test_GrantAndRevokeRole() public {
        assertTrue(registry.isAuthorized(assetId, CLAIM_TYPE, RoleKind.AUTHOR, author));
        vm.prank(admin);
        registry.revokeRoleToClaimType(assetId, CLAIM_TYPE, RoleKind.AUTHOR, author);
        assertFalse(registry.isAuthorized(assetId, CLAIM_TYPE, RoleKind.AUTHOR, author));
    }

    function test_GetAssetId() public view {
        assertEq(registry.getAssetId(assetContract, 0, block.chainid), assetId);
    }

    function test_GetAssetReference() public view {
        (address contractAddr, uint256 subAssetId, uint256 chainId) = registry.getAssetReference(assetId);
        assertEq(contractAddr, assetContract);
        assertEq(subAssetId, 0);
        assertEq(chainId, block.chainid);
    }

    // ---------- extra lifecycle revert branches ----------

    function test_ActivateRevertsNotActivator() public {
        _propose(1);
        _validate(1);
        uint256 nonce = registry.nonces(validator);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(validatorPk, _lifecycleHash(ACTIVATE_TYPEHASH, 1, ClaimState.ACTIVE, nonce, deadline));
        vm.prank(relayer);
        vm.expectRevert(RegulatedAssetClaimRegistry.NotAuthorized.selector);
        registry.activateClaim(assetId, CLAIM_TYPE, 1, validator, nonce, deadline, sig);
    }

    function test_SuspendRevertsNotActivator() public {
        _propose(1);
        _validate(1);
        _activate(1);
        uint256 nonce = registry.nonces(validator);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(validatorPk, _lifecycleHash(SUSPEND_TYPEHASH, 1, ClaimState.VALID, nonce, deadline));
        vm.prank(relayer);
        vm.expectRevert(RegulatedAssetClaimRegistry.NotAuthorized.selector);
        registry.suspendClaim(assetId, CLAIM_TYPE, 1, validator, nonce, deadline, sig);
    }

    function test_ValidateRevertsAssetInactive() public {
        _propose(1);
        vm.prank(admin);
        registry.removeAsset(assetId);
        uint256 nonce = registry.nonces(validator);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(validatorPk, _lifecycleHash(VALIDATE_TYPEHASH, 1, ClaimState.VALID, nonce, deadline));
        vm.prank(relayer);
        vm.expectRevert(RegulatedAssetClaimRegistry.AssetNotActive.selector);
        registry.validateClaim(assetId, CLAIM_TYPE, 1, validator, nonce, deadline, sig);
    }

    function test_ValidateRevertsWrongState() public {
        _propose(1);
        _validate(1); // now VALID, re-validating must fail
        uint256 nonce = registry.nonces(validator);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(validatorPk, _lifecycleHash(VALIDATE_TYPEHASH, 1, ClaimState.VALID, nonce, deadline));
        vm.prank(relayer);
        vm.expectRevert(RegulatedAssetClaimRegistry.InvalidClaimState.selector);
        registry.validateClaim(assetId, CLAIM_TYPE, 1, validator, nonce, deadline, sig);
    }

    function test_ActivateRevertsAssetInactive() public {
        _propose(1);
        _validate(1);
        vm.prank(admin);
        registry.removeAsset(assetId);
        uint256 nonce = registry.nonces(activator);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(activatorPk, _lifecycleHash(ACTIVATE_TYPEHASH, 1, ClaimState.ACTIVE, nonce, deadline));
        vm.prank(relayer);
        vm.expectRevert(RegulatedAssetClaimRegistry.AssetNotActive.selector);
        registry.activateClaim(assetId, CLAIM_TYPE, 1, activator, nonce, deadline, sig);
    }

    function test_SuspendRevertsWrongState() public {
        _propose(1);
        _validate(1); // VALID, not ACTIVE -> cannot suspend
        uint256 nonce = registry.nonces(activator);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(activatorPk, _lifecycleHash(SUSPEND_TYPEHASH, 1, ClaimState.VALID, nonce, deadline));
        vm.prank(relayer);
        vm.expectRevert(RegulatedAssetClaimRegistry.InvalidClaimState.selector);
        registry.suspendClaim(assetId, CLAIM_TYPE, 1, activator, nonce, deadline, sig);
    }

    function test_RevokeRevertsNotValidator() public {
        _propose(1);
        uint256 nonce = registry.nonces(activator);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(activatorPk, _lifecycleHash(REVOKE_TYPEHASH, 1, ClaimState.REVOKED, nonce, deadline));
        vm.prank(relayer);
        vm.expectRevert(RegulatedAssetClaimRegistry.NotAuthorized.selector);
        registry.revokeClaim(assetId, CLAIM_TYPE, 1, activator, nonce, deadline, sig);
    }

    function test_ProposeRevertsBadSignature() public {
        (, uint256 wrongPk) = makeAddrAndKey("wrong");
        RegulatedAssetClaim memory claim = _claim(1);
        uint256 nonce = registry.nonces(author);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(wrongPk, _proposeHash(claim, nonce, deadline)); // signed by the wrong key
        vm.prank(relayer);
        vm.expectRevert(RegulatedAssetClaimRegistry.InvalidSignature.selector);
        registry.proposeClaim(claim, nonce, deadline, sig);
    }

    function test_RevokeRevertsWrongState() public {
        // propose an expiring claim, activate it, warp past expiry -> effective EXPIRED -> not revocable
        RegulatedAssetClaim memory claim = _claim(1);
        claim.validUntil = uint64(block.timestamp + 1 days);
        uint256 nonce = registry.nonces(author);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(authorPk, _proposeHash(claim, nonce, deadline));
        vm.prank(relayer);
        registry.proposeClaim(claim, nonce, deadline, sig);
        _validate(1);
        _activate(1);

        vm.warp(block.timestamp + 2 days);

        uint256 rnonce = registry.nonces(validator);
        uint64 rdeadline = uint64(block.timestamp + 1 hours);
        bytes memory rsig =
            _sign(validatorPk, _lifecycleHash(REVOKE_TYPEHASH, 1, ClaimState.REVOKED, rnonce, rdeadline));
        vm.prank(relayer);
        vm.expectRevert(RegulatedAssetClaimRegistry.InvalidClaimState.selector);
        registry.revokeClaim(assetId, CLAIM_TYPE, 1, validator, rnonce, rdeadline, rsig);
    }

    // ---------- multiple active versions ----------

    function test_MultipleActiveVersions() public {
        _propose(1);
        _validate(1);
        _activate(1);
        _propose(2);
        _validate(2);
        _activate(2);

        RegulatedAssetClaim[] memory active = registry.getActiveClaims(assetId, CLAIM_TYPE);
        assertEq(active.length, 2);
    }

    // ---------- ERC-165 ----------

    function test_SupportsInterface() public view {
        assertTrue(registry.supportsInterface(type(IRegulatedAssetClaimRegistry).interfaceId));
        assertTrue(registry.supportsInterface(type(IERC165).interfaceId));
        assertFalse(registry.supportsInterface(0xffffffff));
    }

    // ---------- helpers ----------

    function _claim(uint64 version) internal view returns (RegulatedAssetClaim memory claim) {
        claim = RegulatedAssetClaim({
            assetId: assetId,
            claimType: CLAIM_TYPE,
            schemaId: keccak256("schema"),
            schemaHash: keccak256("schemaHash"),
            version: version,
            validFrom: uint64(block.timestamp),
            validUntil: 0,
            claimState: ClaimState.PROPOSED,
            tags: new bytes32[](0),
            contentHash: keccak256("content"),
            author: author,
            uri: "ipfs://claim"
        });
    }

    function _digest(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(hex"1901", registry.DOMAIN_SEPARATOR(), structHash));
    }

    function _sign(uint256 pk, bytes32 structHash) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _digest(structHash));
        return abi.encodePacked(r, s, v);
    }

    function _proposeHash(RegulatedAssetClaim memory claim, uint256 nonce, uint64 deadline)
        internal
        pure
        returns (bytes32)
    {
        bytes memory head = abi.encode(
            PROPOSE_TYPEHASH,
            claim.assetId,
            uint8(claim.claimType),
            claim.schemaId,
            claim.schemaHash,
            claim.version,
            claim.validFrom
        );
        bytes memory tail = abi.encode(
            claim.validUntil,
            uint8(claim.claimState),
            keccak256(abi.encodePacked(claim.tags)),
            claim.contentHash,
            claim.author,
            keccak256(bytes(claim.uri)),
            nonce,
            deadline
        );
        return keccak256(bytes.concat(head, tail));
    }

    function _lifecycleHash(bytes32 typehash, uint64 version, ClaimState targetState, uint256 nonce, uint64 deadline)
        internal
        view
        returns (bytes32)
    {
        return keccak256(abi.encode(typehash, assetId, uint8(CLAIM_TYPE), version, uint8(targetState), nonce, deadline));
    }

    /// @dev Proposes version `v` (author), returns nothing; reverts bubble up.
    function _propose(uint64 v) internal {
        RegulatedAssetClaim memory claim = _claim(v);
        uint256 nonce = registry.nonces(author);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(authorPk, _proposeHash(claim, nonce, deadline));
        vm.prank(relayer);
        registry.proposeClaim(claim, nonce, deadline, sig);
    }

    function _validate(uint64 v) internal {
        uint256 nonce = registry.nonces(validator);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(validatorPk, _lifecycleHash(VALIDATE_TYPEHASH, v, ClaimState.VALID, nonce, deadline));
        vm.prank(relayer);
        registry.validateClaim(assetId, CLAIM_TYPE, v, validator, nonce, deadline, sig);
    }

    function _activate(uint64 v) internal {
        uint256 nonce = registry.nonces(activator);
        uint64 deadline = uint64(block.timestamp + 1 hours);
        bytes memory sig = _sign(activatorPk, _lifecycleHash(ACTIVATE_TYPEHASH, v, ClaimState.ACTIVE, nonce, deadline));
        vm.prank(relayer);
        registry.activateClaim(assetId, CLAIM_TYPE, v, activator, nonce, deadline, sig);
    }
}
