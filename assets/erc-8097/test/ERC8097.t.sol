// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC8097} from "../contracts/ERC8097.sol";
import {IERC8097, IRO, IGO, ICO, IEXO, IEO} from "../contracts/IERC8097.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract ERC8097Test is Test {

    ERC8097 public erc;

    // Test CP/QP key
    uint256 constant CP_PRIVATE_KEY = 0xA11CE;
    address cpAddress;

    bytes32 constant DEPOSIT_ID = keccak256(abi.encodePacked("Boddington Gold Mine", "AU:M70/1388"));

    IRO baseIRO;
    IGO baseIGO;

    function setUp() public {
        erc = new ERC8097();
        cpAddress = vm.addr(CP_PRIVATE_KEY);

        baseIRO = IRO({
            depositId:        DEPOSIT_ID,
            commodity:        "AU",
            reportingStandard: "JORC2012",
            totalInGround:    34_200_000_000, // 34,200 kg in grams
            resourceClass:    2,              // Measured
            anchorHash:       keccak256("mock_report_pdf_bytes"),
            anchoredAt:       0              // set by contract
        });

        baseIGO = _makeIGO(1);
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    bytes32 constant IGO_TYPEHASH = keccak256(
        "IGOAttestation(bytes32 depositId,string country,string depositStyle,"
        "string hostRock,address cpAddress,uint256 siteVisitDate,"
        "bytes32 reportHash,uint256 version)"
    );

    function _makeIGO(uint256 version) internal view returns (IGO memory igo) {
        igo.depositId    = DEPOSIT_ID;
        igo.country      = "AU";
        igo.depositStyle = "Orogenic Gold";
        igo.hostRock     = "granite";
        igo.cpAddress    = cpAddress;
        igo.siteVisitDate = 1_700_000_000;
        igo.reportHash   = keccak256("mock_report_pdf_bytes");
        igo.version      = version;
        igo.cpSignature  = _signIGO(igo);
    }

    function _signIGO(IGO memory igo) internal view returns (bytes memory) {
        // Reconstruct EIP-712 domain separator matching contract
        bytes32 domainSep = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("ERC8097"),
            keccak256("1"),
            block.chainid,
            address(erc)
        ));
        bytes32 structHash = keccak256(abi.encode(
            IGO_TYPEHASH,
            igo.depositId,
            keccak256(bytes(igo.country)),
            keccak256(bytes(igo.depositStyle)),
            keccak256(bytes(igo.hostRock)),
            igo.cpAddress,
            igo.siteVisitDate,
            igo.reportHash,
            igo.version
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(CP_PRIVATE_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    // ── anchorResource ────────────────────────────────────────────────────

    function test_anchorResource_emitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit IERC8097.ResourceAnchored(DEPOSIT_ID, "AU", baseIRO.totalInGround, baseIRO.anchorHash);
        erc.anchorResource(baseIRO);
    }

    function test_anchorResource_setsAnchoredAt() public {
        vm.warp(1_800_000_000);
        erc.anchorResource(baseIRO);
        IRO memory stored = erc.getIRO(DEPOSIT_ID);
        assertEq(stored.anchoredAt, 1_800_000_000);
    }

    function test_anchorResource_initializesIEXO() public {
        erc.anchorResource(baseIRO);
        assertEq(erc.remainingInGround(DEPOSIT_ID), baseIRO.totalInGround);
    }

    function test_anchorResource_revertsIfAlreadyAnchored() public {
        erc.anchorResource(baseIRO);
        vm.expectRevert(abi.encodeWithSelector(IERC8097.AlreadyAnchored.selector, DEPOSIT_ID));
        erc.anchorResource(baseIRO);
    }

    function test_anchorResource_revertsIfZeroQuantity() public {
        baseIRO.totalInGround = 0;
        vm.expectRevert(IERC8097.ZeroResourceQuantity.selector);
        erc.anchorResource(baseIRO);
    }

    // ── updateGeology ─────────────────────────────────────────────────────

    function test_updateGeology_setsVersion1() public {
        erc.anchorResource(baseIRO);
        erc.updateGeology(baseIGO);
        IGO memory stored = erc.getIGO(DEPOSIT_ID);
        assertEq(stored.version, 1);
    }

    function test_updateGeology_emitsCPAttestation() public {
        erc.anchorResource(baseIRO);
        vm.expectEmit(true, true, false, true);
        emit IERC8097.CPAttestation(DEPOSIT_ID, cpAddress, baseIGO.reportHash, baseIGO.siteVisitDate, 1);
        erc.updateGeology(baseIGO);
    }

    function test_updateGeology_invalidatesAttestation() public {
        erc.anchorResource(baseIRO);
        erc.updateGeology(baseIGO);
        erc.verifyAttestation(DEPOSIT_ID);
        assertTrue(erc.getICO(DEPOSIT_ID).attestationValid);
        // Update geology again — should invalidate
        IGO memory v2 = _makeIGO(2);
        erc.updateGeology(v2);
        assertFalse(erc.getICO(DEPOSIT_ID).attestationValid);
    }

    function test_updateGeology_revertsOnBadSignature() public {
        erc.anchorResource(baseIRO);
        IGO memory bad = baseIGO;
        bad.cpSignature = bytes("bad_signature");
        vm.expectRevert();
        erc.updateGeology(bad);
    }

    function test_updateGeology_revertsIfNotAnchored() public {
        vm.expectRevert(abi.encodeWithSelector(IERC8097.DepositNotFound.selector, DEPOSIT_ID));
        erc.updateGeology(baseIGO);
    }

    // ── verifyAttestation ─────────────────────────────────────────────────

    function test_verifyAttestation_setsValid() public {
        erc.anchorResource(baseIRO);
        erc.updateGeology(baseIGO);
        bool result = erc.verifyAttestation(DEPOSIT_ID);
        assertTrue(result);
        assertTrue(erc.getICO(DEPOSIT_ID).attestationValid);
    }

    // ── recordDepletion ───────────────────────────────────────────────────

    function test_recordDepletion_decreasesRemaining() public {
        erc.anchorResource(baseIRO);
        erc.updateGeology(baseIGO);
        erc.verifyAttestation(DEPOSIT_ID);
        uint256 before = erc.remainingInGround(DEPOSIT_ID);
        erc.recordDepletion(DEPOSIT_ID, 1_000_000);
        assertEq(erc.remainingInGround(DEPOSIT_ID), before - 1_000_000);
    }

    function test_recordDepletion_maintainsInvariant() public {
        erc.anchorResource(baseIRO);
        erc.updateGeology(baseIGO);
        erc.verifyAttestation(DEPOSIT_ID);
        erc.recordDepletion(DEPOSIT_ID, 5_000_000);
        IEXO memory e = erc.getIEXO(DEPOSIT_ID);
        IRO memory r  = erc.getIRO(DEPOSIT_ID);
        assertEq(e.totalDepleted + e.remainingInGround, r.totalInGround);
    }

    function test_recordDepletion_emitsEvent() public {
        erc.anchorResource(baseIRO);
        erc.updateGeology(baseIGO);
        erc.verifyAttestation(DEPOSIT_ID);
        vm.expectEmit(true, true, false, true);
        emit IERC8097.DepletionRecorded(
            DEPOSIT_ID, 1_000_000, baseIRO.totalInGround - 1_000_000, address(this)
        );
        erc.recordDepletion(DEPOSIT_ID, 1_000_000);
    }

    function test_recordDepletion_revertsIfExceedsRemaining() public {
        erc.anchorResource(baseIRO);
        erc.updateGeology(baseIGO);
        erc.verifyAttestation(DEPOSIT_ID);
        uint256 tooMuch = baseIRO.totalInGround + 1;
        vm.expectRevert(abi.encodeWithSelector(
            IERC8097.DepletionExceedsRemaining.selector,
            DEPOSIT_ID, tooMuch, baseIRO.totalInGround
        ));
        erc.recordDepletion(DEPOSIT_ID, tooMuch);
    }

    function test_recordDepletion_revertsIfAttestationInvalid() public {
        erc.anchorResource(baseIRO);
        // No verifyAttestation call
        vm.expectRevert(abi.encodeWithSelector(IERC8097.AttestationNotValid.selector, DEPOSIT_ID));
        erc.recordDepletion(DEPOSIT_ID, 1_000_000);
    }

    function test_recordDepletion_cannotIncrease() public {
        // This test verifies monotonic decrease by attempting two depletions
        erc.anchorResource(baseIRO);
        erc.updateGeology(baseIGO);
        erc.verifyAttestation(DEPOSIT_ID);
        erc.recordDepletion(DEPOSIT_ID, 1_000_000);
        erc.recordDepletion(DEPOSIT_ID, 1_000_000);
        IEXO memory e = erc.getIEXO(DEPOSIT_ID);
        assertEq(e.totalDepleted, 2_000_000);
        assertEq(e.remainingInGround, baseIRO.totalInGround - 2_000_000);
    }

    // ── updateEnvironmental ───────────────────────────────────────────────

    function test_updateEnvironmental_emitsEvent() public {
        erc.anchorResource(baseIRO);
        IEO memory ieo = IEO({
            depositId: DEPOSIT_ID, eiaSubmitted: true, waterRightsPresent: true,
            tailingsPlanPresent: true, ghgReportHash: keccak256("ghg_report"),
            rehabilitationBond: 1 ether, lastUpdated: 0
        });
        vm.expectEmit(true, false, false, true);
        emit IERC8097.ESGUpdated(DEPOSIT_ID, ieo.ghgReportHash, true, 1 ether);
        erc.updateEnvironmental(ieo);
    }

    // ── depositId computation ─────────────────────────────────────────────

    function test_depositId_deterministic() public pure {
        bytes32 id1 = keccak256(abi.encodePacked("Boddington Gold Mine", "AU:M70/1388"));
        bytes32 id2 = keccak256(abi.encodePacked("Boddington Gold Mine", "AU:M70/1388"));
        assertEq(id1, id2);
    }

    function test_depositId_differentForDifferentDeposits() public pure {
        bytes32 id1 = keccak256(abi.encodePacked("Boddington Gold Mine", "AU:M70/1388"));
        bytes32 id2 = keccak256(abi.encodePacked("Olympic Dam",          "AU:M6/2671"));
        assertTrue(id1 != id2);
    }
}
