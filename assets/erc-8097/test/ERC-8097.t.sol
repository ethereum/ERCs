// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC8097} from "../contracts/ERC-8097.sol";
import {
    IERC8097,
    AssetRecord,
    CPAttestation,
    LifecycleState,
    ProductionStatus
} from "../contracts/IERC-8097.sol";

contract ERC8097Test is Test {
    ERC8097 registry;

    address owner = makeAddr("owner");
    address relayer = makeAddr("relayer");
    address stranger = makeAddr("stranger");

    uint256 cpPrivateKey = 0xA11CE;
    address cpAddress;

    string constant SLUG = "bellevue-gold-project";
    string constant MINE_NAME = "Bellevue Gold Project";
    string constant SCHEMA = "erc8097-v0.2";
    string constant RULEBOOK = "v1.1";
    string constant IPFS_URI = "ipfs://QmBellevueGoldReport";

    // Test-only stand-ins for SHA-256 object/report hashes. Production anchors
    // SHA-256 hashes of canonical off-chain JSON objects and report PDFs.
    bytes32 constant IRO_HASH = bytes32(uint256(1));
    bytes32 constant IGO_HASH = bytes32(uint256(2));
    bytes32 constant ICO_HASH = bytes32(uint256(3));
    bytes32 constant IEXO_HASH = bytes32(uint256(4));
    bytes32 constant IEO_HASH = bytes32(uint256(5));
    bytes32 constant SML_HASH = bytes32(uint256(6));
    bytes32 constant PDF_HASH = bytes32(uint256(7));

    bytes32 constant CP_ATTESTATION_TYPEHASH = keccak256(
        "CPAttestation(bytes32 assetId,bytes32 objectHash,string cpName,string cpBody,string cpMembershipNumber,uint256 attestationTimestamp)"
    );

    function setUp() public {
        cpAddress = vm.addr(cpPrivateKey);
        vm.startPrank(owner);
        registry = new ERC8097(owner);
        registry.setRelayer(relayer, true);
        vm.stopPrank();
    }

    function _register(string memory slug) internal returns (bytes32 assetId) {
        vm.prank(relayer);
        assetId = registry.register(slug, MINE_NAME, SCHEMA);
    }

    function _verifiedAsset(string memory slug) internal returns (bytes32 assetId) {
        assetId = _register(slug);
        vm.startPrank(relayer);
        registry.advanceLifecycle(assetId, LifecycleState.CLAIMED);
        registry.advanceLifecycle(assetId, LifecycleState.VERIFIED);
        vm.stopPrank();
    }

    function _anchor(string memory slug) internal returns (bytes32 assetId) {
        assetId = _verifiedAsset(slug);
        vm.prank(relayer);
        registry.anchor(
            assetId,
            IRO_HASH,
            IGO_HASH,
            ICO_HASH,
            IEXO_HASH,
            IEO_HASH,
            SML_HASH,
            762,
            PDF_HASH,
            IPFS_URI,
            RULEBOOK,
            SCHEMA
        );
    }

    function _signAttestation(
        bytes32 assetId,
        bytes32 objectHash,
        string memory cpName,
        string memory cpBody,
        string memory cpMembershipNumber,
        uint256 attestationTimestamp,
        uint256 privateKey
    ) internal view returns (bytes memory signature) {
        bytes32 structHash = keccak256(abi.encode(
            CP_ATTESTATION_TYPEHASH,
            assetId,
            objectHash,
            keccak256(bytes(cpName)),
            keccak256(bytes(cpBody)),
            keccak256(bytes(cpMembershipNumber)),
            attestationTimestamp
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", registry.getDomainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function test_registerCreatesIndexedAsset() public {
        bytes32 assetId = _register(SLUG);
        AssetRecord memory asset = registry.getAsset(assetId);
        assertEq(asset.mineSlug, SLUG);
        assertEq(asset.mineName, MINE_NAME);
        assertEq(uint8(asset.lifecycleState), uint8(LifecycleState.INDEXED));
        assertEq(registry.getAssetBySlug(SLUG), assetId);
    }

    function test_registerRejectsDuplicateSlug() public {
        _register(SLUG);
        vm.prank(relayer);
        vm.expectRevert("ERC8097: slug already registered");
        registry.register(SLUG, MINE_NAME, SCHEMA);
    }

    function test_registerRequiresRelayer() public {
        vm.prank(stranger);
        vm.expectRevert("ERC8097: not an authorised relayer");
        registry.register(SLUG, MINE_NAME, SCHEMA);
    }

    function test_lifecycleAdvancesOneStepOnly() public {
        bytes32 assetId = _register(SLUG);
        vm.prank(relayer);
        registry.advanceLifecycle(assetId, LifecycleState.CLAIMED);
        assertEq(uint8(registry.getLifecycleState(assetId)), uint8(LifecycleState.CLAIMED));
    }

    function test_lifecycleRejectsSkip() public {
        bytes32 assetId = _register(SLUG);
        vm.prank(relayer);
        vm.expectRevert("ERC8097: lifecycle must advance exactly one step");
        registry.advanceLifecycle(assetId, LifecycleState.VERIFIED);
    }

    function test_lifecycleRejectsAnchoredViaAdvance() public {
        bytes32 assetId = _verifiedAsset(SLUG);
        vm.prank(relayer);
        vm.expectRevert("ERC8097: use anchor() to reach ANCHORED state");
        registry.advanceLifecycle(assetId, LifecycleState.ANCHORED);
    }

    function test_anchorRequiresVerified() public {
        bytes32 assetId = _register(SLUG);
        vm.prank(relayer);
        vm.expectRevert("ERC8097: lifecycle must reach VERIFIED before anchoring");
        registry.anchor(assetId, IRO_HASH, IGO_HASH, ICO_HASH, IEXO_HASH, IEO_HASH, SML_HASH, 762, PDF_HASH, IPFS_URI, RULEBOOK, SCHEMA);
    }

    function test_anchorStoresHashesAndScore() public {
        bytes32 assetId = _anchor(SLUG);
        AssetRecord memory asset = registry.getAsset(assetId);
        assertEq(asset.iroHash, IRO_HASH);
        assertEq(asset.reportPdfHash, PDF_HASH);
        assertEq(asset.reportIpfsUri, IPFS_URI);
        assertEq(uint8(asset.lifecycleState), uint8(LifecycleState.ANCHORED));
        assertEq(registry.getCurrentScore(assetId), 762);
        assertTrue(registry.isAnchored(assetId));
    }

    function test_anchorRejectsMissingReport() public {
        bytes32 assetId = _verifiedAsset(SLUG);
        vm.prank(relayer);
        vm.expectRevert("ERC8097: reportPdfHash required");
        registry.anchor(assetId, IRO_HASH, IGO_HASH, ICO_HASH, IEXO_HASH, IEO_HASH, SML_HASH, 762, bytes32(0), IPFS_URI, RULEBOOK, SCHEMA);
    }

    function test_anchorRejectsScoreAbove1000() public {
        bytes32 assetId = _verifiedAsset(SLUG);
        vm.prank(relayer);
        vm.expectRevert("ERC8097: score must be 0-1000");
        registry.anchor(assetId, IRO_HASH, IGO_HASH, ICO_HASH, IEXO_HASH, IEO_HASH, SML_HASH, 1001, PDF_HASH, IPFS_URI, RULEBOOK, SCHEMA);
    }

    function test_reanchorEmitsAndUpdatesLatestHash() public {
        bytes32 assetId = _anchor(SLUG);
        bytes32 newIroHash = bytes32(uint256(111));

        vm.expectEmit(true, false, false, true);
        emit IERC8097.AssetAnchored(
            assetId,
            SLUG,
            newIroHash,
            IGO_HASH,
            ICO_HASH,
            IEXO_HASH,
            IEO_HASH,
            SML_HASH,
            PDF_HASH,
            block.timestamp
        );
        vm.expectEmit(true, false, false, true);
        emit IERC8097.AssetReAnchored(assetId, IRO_HASH, newIroHash, block.timestamp);
        vm.prank(relayer);
        registry.anchor(assetId, newIroHash, IGO_HASH, ICO_HASH, IEXO_HASH, IEO_HASH, SML_HASH, 800, PDF_HASH, IPFS_URI, RULEBOOK, SCHEMA);

        assertEq(registry.getAsset(assetId).iroHash, newIroHash);
        assertEq(registry.getCurrentScore(assetId), 800);
    }

    function test_cpAttestationStoresSignerAndTimestamp() public {
        bytes32 assetId = _anchor(SLUG);
        uint256 ts = 1_800_000_000;
        bytes memory sig = _signAttestation(assetId, IRO_HASH, "Peter Burge", "MAusIMM", "12345", ts, cpPrivateKey);

        registry.recordCPAttestation(assetId, IRO_HASH, "Peter Burge", "MAusIMM", "12345", cpAddress, ts, sig);
        CPAttestation[] memory attestations = registry.getCPAttestations(IRO_HASH);
        assertEq(attestations.length, 1);
        assertEq(attestations[0].signerAddress, cpAddress);
        assertEq(attestations[0].attestationTimestamp, ts);
    }

    function test_cpAttestationRejectsUnrelatedHash() public {
        bytes32 assetId = _anchor(SLUG);
        bytes32 unrelatedHash = keccak256("unrelated");
        bytes memory sig = _signAttestation(assetId, unrelatedHash, "Peter Burge", "MAusIMM", "12345", 1, cpPrivateKey);

        vm.expectRevert("ERC8097: objectHash not a current hash of this asset");
        registry.recordCPAttestation(assetId, unrelatedHash, "Peter Burge", "MAusIMM", "12345", cpAddress, 1, sig);
    }

    function test_cpAttestationRejectsReplay() public {
        bytes32 assetId = _anchor(SLUG);
        bytes memory sig = _signAttestation(assetId, IGO_HASH, "Peter Burge", "MAusIMM", "12345", 2, cpPrivateKey);

        registry.recordCPAttestation(assetId, IGO_HASH, "Peter Burge", "MAusIMM", "12345", cpAddress, 2, sig);
        vm.expectRevert("ERC8097: attestation digest already used");
        registry.recordCPAttestation(assetId, IGO_HASH, "Peter Burge", "MAusIMM", "12345", cpAddress, 2, sig);
    }

    function test_cpAttestationRejectsSignerMismatch() public {
        bytes32 assetId = _anchor(SLUG);
        bytes memory sig = _signAttestation(assetId, IGO_HASH, "Peter Burge", "MAusIMM", "12345", 3, cpPrivateKey);

        vm.expectRevert("ERC8097: signer does not match expectedSigner");
        registry.recordCPAttestation(assetId, IGO_HASH, "Peter Burge", "MAusIMM", "12345", makeAddr("wrong"), 3, sig);
    }

    function test_productionTransitionTable() public {
        assertTrue(registry.isProductionTransitionAllowed(ProductionStatus.PRODUCTION, ProductionStatus.CARE_AND_MAINTENANCE));
        assertTrue(registry.isProductionTransitionAllowed(ProductionStatus.CARE_AND_MAINTENANCE, ProductionStatus.PRODUCTION));
        assertFalse(registry.isProductionTransitionAllowed(ProductionStatus.EXPLORATION, ProductionStatus.PRODUCTION));
        assertFalse(registry.isProductionTransitionAllowed(ProductionStatus.CLOSED, ProductionStatus.PRODUCTION));
    }

    function test_advanceProductionStatusUsesTable() public {
        bytes32 assetId = _anchor(SLUG);
        vm.startPrank(relayer);
        registry.advanceProductionStatus(assetId, ProductionStatus.EXPLORATION);
        registry.advanceProductionStatus(assetId, ProductionStatus.PRE_FEASIBILITY);
        registry.advanceProductionStatus(assetId, ProductionStatus.FEASIBILITY);
        registry.advanceProductionStatus(assetId, ProductionStatus.DEVELOPMENT);
        registry.advanceProductionStatus(assetId, ProductionStatus.PRODUCTION);
        registry.advanceProductionStatus(assetId, ProductionStatus.CARE_AND_MAINTENANCE);
        registry.advanceProductionStatus(assetId, ProductionStatus.PRODUCTION);
        vm.stopPrank();
        assertEq(uint8(registry.getProductionStatus(assetId)), uint8(ProductionStatus.PRODUCTION));
    }

    function test_advanceProductionStatusRejectsSkippedTransition() public {
        bytes32 assetId = _anchor(SLUG);
        vm.prank(relayer);
        vm.expectRevert("ERC8097: production status transition not permitted");
        registry.advanceProductionStatus(assetId, ProductionStatus.PRODUCTION);
    }

    function test_updateDepletionRequiresProduction() public {
        bytes32 assetId = _anchor(SLUG);
        vm.prank(relayer);
        vm.expectRevert("ERC8097: production status must be PRODUCTION");
        registry.updateDepletion(assetId, 10);
    }

    function test_updateDepletionIncreasesOnly() public {
        bytes32 assetId = _anchor(SLUG);
        vm.startPrank(relayer);
        registry.advanceProductionStatus(assetId, ProductionStatus.EXPLORATION);
        registry.advanceProductionStatus(assetId, ProductionStatus.PRE_FEASIBILITY);
        registry.advanceProductionStatus(assetId, ProductionStatus.FEASIBILITY);
        registry.advanceProductionStatus(assetId, ProductionStatus.DEVELOPMENT);
        registry.advanceProductionStatus(assetId, ProductionStatus.PRODUCTION);
        registry.updateDepletion(assetId, 10);
        vm.expectRevert("ERC8097: depletion can only increase");
        registry.updateDepletion(assetId, 10);
        vm.stopPrank();
    }

    function test_updateSMLRejectsScoreAbove1000() public {
        bytes32 assetId = _anchor(SLUG);
        vm.prank(relayer);
        vm.expectRevert("ERC8097: score must be 0-1000");
        registry.updateSML(assetId, keccak256("new-sml"), 1001);
    }
}
