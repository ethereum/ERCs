// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IERC8097, IRO, IGO, ICO, IEXO, IEO} from "./IERC8097.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title ERC8097
/// @notice Reference implementation of the In-Ground Asset Token standard (ERC-8097)
/// @dev This is a reference implementation. Production deployments should add
///      appropriate access controls for anchorResource, updateGeology, updateCompliance,
///      recordDepletion, and updateEnvironmental based on their operational model.
contract ERC8097 is IERC8097, EIP712, AccessControl {
    using ECDSA for bytes32;

    bytes32 public constant ANCHOR_ROLE     = keccak256("ANCHOR_ROLE");
    bytes32 public constant DEPLETION_ROLE  = keccak256("DEPLETION_ROLE");
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");
    bytes32 public constant ESG_ROLE        = keccak256("ESG_ROLE");

    bytes32 public constant IGO_TYPEHASH = keccak256(
        "IGOAttestation(bytes32 depositId,string country,string depositStyle,"
        "string hostRock,address cpAddress,uint256 siteVisitDate,"
        "bytes32 reportHash,uint256 version)"
    );

    mapping(bytes32 => IRO)  private _iros;
    mapping(bytes32 => IGO)  private _igos;
    mapping(bytes32 => ICO)  private _icos;
    mapping(bytes32 => IEXO) private _iexos;
    mapping(bytes32 => IEO)  private _ieos;
    mapping(bytes32 => bool) private _anchored;

    constructor() EIP712("ERC8097", "1") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ANCHOR_ROLE,        msg.sender);
        _grantRole(DEPLETION_ROLE,     msg.sender);
        _grantRole(COMPLIANCE_ROLE,    msg.sender);
        _grantRole(ESG_ROLE,           msg.sender);
    }

    function anchorResource(IRO calldata iro) external onlyRole(ANCHOR_ROLE) {
        if (_anchored[iro.depositId]) revert AlreadyAnchored(iro.depositId);
        if (iro.totalInGround == 0)  revert ZeroResourceQuantity();

        IRO storage s = _iros[iro.depositId];
        s.depositId        = iro.depositId;
        s.commodity        = iro.commodity;
        s.reportingStandard = iro.reportingStandard;
        s.totalInGround    = iro.totalInGround;
        s.resourceClass    = iro.resourceClass;
        s.anchorHash       = iro.anchorHash;
        s.anchoredAt       = block.timestamp;

        // Initialise IEXO to full quantity
        _iexos[iro.depositId] = IEXO({
            depositId:         iro.depositId,
            remainingInGround: iro.totalInGround,
            lastDepletionAt:   0,
            totalDepleted:     0
        });

        _anchored[iro.depositId] = true;
        emit ResourceAnchored(iro.depositId, iro.commodity, iro.totalInGround, iro.anchorHash);
    }

    function updateGeology(IGO calldata igo) external {
        if (!_anchored[igo.depositId]) revert DepositNotFound(igo.depositId);
        _verifyCPSignature(igo);

        uint256 newVersion = _igos[igo.depositId].version + 1;
        IGO storage s = _igos[igo.depositId];
        s.depositId    = igo.depositId;
        s.country      = igo.country;
        s.depositStyle = igo.depositStyle;
        s.hostRock     = igo.hostRock;
        s.cpAddress    = igo.cpAddress;
        s.cpSignature  = igo.cpSignature;
        s.siteVisitDate = igo.siteVisitDate;
        s.reportHash   = igo.reportHash;
        s.version      = newVersion;

        // Invalidate compliance attestation when geology changes
        _icos[igo.depositId].attestationValid = false;

        emit CPAttestation(igo.depositId, igo.cpAddress, igo.reportHash, igo.siteVisitDate, newVersion);
    }

    function verifyAttestation(bytes32 depositId) external returns (bool valid) {
        if (!_anchored[depositId]) revert DepositNotFound(depositId);
        IGO storage igo = _igos[depositId];
        if (igo.cpAddress == address(0)) revert DepositNotFound(depositId);
        _verifyCPSignature(igo);
        _icos[depositId].attestationValid = true;
        _icos[depositId].cpAddress = igo.cpAddress;
        return true;
    }

    function updateCompliance(ICO calldata ico) external onlyRole(COMPLIANCE_ROLE) {
        if (!_anchored[ico.depositId]) revert DepositNotFound(ico.depositId);
        ICO storage s = _icos[ico.depositId];
        s.jurisdictionId      = ico.jurisdictionId;
        s.licenceExpiresAt    = ico.licenceExpiresAt;
        s.indigenousConsentHash = ico.indigenousConsentHash;
        emit JurisdictionUpdated(ico.depositId, ico.jurisdictionId, ico.licenceExpiresAt);
    }

    function recordDepletion(bytes32 depositId, uint256 amount) external onlyRole(DEPLETION_ROLE) {
        if (!_anchored[depositId]) revert DepositNotFound(depositId);
        if (!_icos[depositId].attestationValid) revert AttestationNotValid(depositId);
        IEXO storage e = _iexos[depositId];
        if (amount > e.remainingInGround)
            revert DepletionExceedsRemaining(depositId, amount, e.remainingInGround);
        e.remainingInGround -= amount;
        e.totalDepleted     += amount;
        e.lastDepletionAt    = block.timestamp;
        // Invariant check: should always hold given the subtraction above
        assert(e.totalDepleted + e.remainingInGround == _iros[depositId].totalInGround);
        emit DepletionRecorded(depositId, amount, e.remainingInGround, msg.sender);
    }

    function updateEnvironmental(IEO calldata ieo) external onlyRole(ESG_ROLE) {
        if (!_anchored[ieo.depositId]) revert DepositNotFound(ieo.depositId);
        IEO storage s = _ieos[ieo.depositId];
        s.depositId          = ieo.depositId;
        s.eiaSubmitted       = ieo.eiaSubmitted;
        s.waterRightsPresent = ieo.waterRightsPresent;
        s.tailingsPlanPresent = ieo.tailingsPlanPresent;
        s.ghgReportHash      = ieo.ghgReportHash;
        s.rehabilitationBond = ieo.rehabilitationBond;
        s.lastUpdated        = block.timestamp;
        emit ESGUpdated(ieo.depositId, ieo.ghgReportHash, ieo.eiaSubmitted, ieo.rehabilitationBond);
    }

    function getIRO(bytes32 depositId) external view returns (IRO memory) {
        if (!_anchored[depositId]) revert DepositNotFound(depositId);
        return _iros[depositId];
    }
    function getIGO(bytes32 depositId) external view returns (IGO memory) {
        if (!_anchored[depositId]) revert DepositNotFound(depositId);
        return _igos[depositId];
    }
    function getICO(bytes32 depositId) external view returns (ICO memory) {
        if (!_anchored[depositId]) revert DepositNotFound(depositId);
        return _icos[depositId];
    }
    function getIEXO(bytes32 depositId) external view returns (IEXO memory) {
        if (!_anchored[depositId]) revert DepositNotFound(depositId);
        return _iexos[depositId];
    }
    function getIEO(bytes32 depositId) external view returns (IEO memory) {
        if (!_anchored[depositId]) revert DepositNotFound(depositId);
        return _ieos[depositId];
    }
    function remainingInGround(bytes32 depositId) external view returns (uint256) {
        if (!_anchored[depositId]) revert DepositNotFound(depositId);
        return _iexos[depositId].remainingInGround;
    }

    // ── Internal ─────────────────────────────────────────────────────
    function _verifyCPSignature(IGO storage igo) internal view {
        _verifyCPSignatureCalldata(igo.depositId, igo.country, igo.depositStyle,
            igo.hostRock, igo.cpAddress, igo.siteVisitDate,
            igo.reportHash, igo.version + 1, igo.cpSignature);
    }

    function _verifyCPSignature(IGO calldata igo) internal view {
        _verifyCPSignatureCalldata(igo.depositId, igo.country, igo.depositStyle,
            igo.hostRock, igo.cpAddress, igo.siteVisitDate,
            igo.reportHash, _igos[igo.depositId].version + 1, igo.cpSignature);
    }

    function _verifyCPSignatureCalldata(
        bytes32 depositId, string memory country, string memory depositStyle,
        string memory hostRock, address cpAddress, uint256 siteVisitDate,
        bytes32 reportHash, uint256 version, bytes memory signature
    ) internal view {
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
            IGO_TYPEHASH,
            depositId,
            keccak256(bytes(country)),
            keccak256(bytes(depositStyle)),
            keccak256(bytes(hostRock)),
            cpAddress,
            siteVisitDate,
            reportHash,
            version
        )));
        address recovered = ECDSA.recover(digest, signature);
        if (recovered != cpAddress) revert InvalidCPSignature(depositId, cpAddress);
    }
}
