// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "./IERC-8097.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title ERC8097
/// @notice Reference implementation of ERC-8097: In-Ground Asset Token.
contract ERC8097 is IERC8097, ERC165, EIP712, Ownable {
    using ECDSA for bytes32;

    bytes32 private constant CP_ATTESTATION_TYPEHASH = keccak256(
        "CPAttestation(bytes32 assetId,bytes32 objectHash,string cpName,string cpBody,string cpMembershipNumber,uint256 attestationTimestamp)"
    );

    mapping(bytes32 => AssetRecord) private _assets;
    mapping(string => bytes32) private _slugToAsset;
    mapping(bytes32 => uint256) private _depletionMt;
    mapping(bytes32 => ProductionStatus) private _productionStatus;
    mapping(bytes32 => CPAttestation[]) private _attestations;
    mapping(bytes32 => SML) private _sml;
    mapping(address => bool) private _authorisedRelayers;
    mapping(bytes32 => bool) private _digestUsed;
    mapping(uint8 => mapping(uint8 => bool)) private _productionTransition;

    modifier onlyRelayer() {
        require(_authorisedRelayers[msg.sender] || owner() == msg.sender, "ERC8097: not an authorised relayer");
        _;
    }

    modifier exists(bytes32 assetId) {
        require(bytes(_assets[assetId].mineSlug).length > 0, "ERC8097: asset not registered");
        _;
    }

    constructor(address initialOwner)
        EIP712("ERC-8097 In-Ground Asset Token", "1")
        Ownable(initialOwner)
    {
        _initProductionTransitions();
    }

    function _initProductionTransitions() private {
        uint8 preExploration = uint8(ProductionStatus.PRE_EXPLORATION);
        uint8 exploration = uint8(ProductionStatus.EXPLORATION);
        uint8 preFeasibility = uint8(ProductionStatus.PRE_FEASIBILITY);
        uint8 feasibility = uint8(ProductionStatus.FEASIBILITY);
        uint8 development = uint8(ProductionStatus.DEVELOPMENT);
        uint8 production = uint8(ProductionStatus.PRODUCTION);
        uint8 care = uint8(ProductionStatus.CARE_AND_MAINTENANCE);
        uint8 closed = uint8(ProductionStatus.CLOSED);

        _productionTransition[preExploration][exploration] = true;
        _productionTransition[exploration][preFeasibility] = true;
        _productionTransition[preFeasibility][feasibility] = true;
        _productionTransition[feasibility][development] = true;
        _productionTransition[development][production] = true;
        _productionTransition[production][care] = true;
        _productionTransition[care][production] = true;
        _productionTransition[production][closed] = true;
        _productionTransition[care][closed] = true;
    }

    function setRelayer(address relayer, bool authorised) external onlyOwner {
        _authorisedRelayers[relayer] = authorised;
    }

    function register(
        string calldata mineSlug,
        string calldata mineName,
        string calldata schemaVersion
    ) external onlyRelayer returns (bytes32 assetId) {
        require(bytes(mineSlug).length > 0, "ERC8097: mineSlug required");
        require(bytes(mineName).length > 0, "ERC8097: mineName required");
        require(_slugToAsset[mineSlug] == bytes32(0), "ERC8097: slug already registered");

        assetId = keccak256(abi.encode(block.chainid, mineSlug));

        _assets[assetId] = AssetRecord({
            assetId: assetId,
            mineName: mineName,
            mineSlug: mineSlug,
            lifecycleState: LifecycleState.INDEXED,
            schemaVersion: schemaVersion,
            rulebookVersion: "",
            iroHash: bytes32(0),
            igoHash: bytes32(0),
            icoHash: bytes32(0),
            iexoHash: bytes32(0),
            ieoHash: bytes32(0),
            smlHash: bytes32(0),
            reportPdfHash: bytes32(0),
            reportIpfsUri: "",
            anchoredAt: 0,
            anchoredBy: address(0),
            active: true
        });
        _slugToAsset[mineSlug] = assetId;

        emit AssetRegistered(assetId, mineSlug, msg.sender, block.timestamp);
    }

    function anchor(
        bytes32 assetId,
        bytes32 iroHash,
        bytes32 igoHash,
        bytes32 icoHash,
        bytes32 iexoHash,
        bytes32 ieoHash,
        bytes32 smlHash,
        uint256 currentScore,
        bytes32 reportPdfHash,
        string calldata reportIpfsUri,
        string calldata rulebookVersion,
        string calldata schemaVersion
    ) external onlyRelayer exists(assetId) {
        require(
            uint8(_assets[assetId].lifecycleState) >= uint8(LifecycleState.VERIFIED),
            "ERC8097: lifecycle must reach VERIFIED before anchoring"
        );
        require(reportPdfHash != bytes32(0), "ERC8097: reportPdfHash required");
        require(bytes(reportIpfsUri).length > 0, "ERC8097: reportIpfsUri required");
        require(iroHash != bytes32(0), "ERC8097: iroHash required");
        require(igoHash != bytes32(0), "ERC8097: igoHash required");
        require(icoHash != bytes32(0), "ERC8097: icoHash required");
        require(iexoHash != bytes32(0), "ERC8097: iexoHash required");
        require(ieoHash != bytes32(0), "ERC8097: ieoHash required");
        require(smlHash != bytes32(0), "ERC8097: smlHash required");
        require(currentScore <= 1000, "ERC8097: score must be 0-1000");

        bool isReAnchor = _assets[assetId].anchoredAt > 0;
        bytes32 previousIroHash = _assets[assetId].iroHash;

        _assets[assetId].iroHash = iroHash;
        _assets[assetId].igoHash = igoHash;
        _assets[assetId].icoHash = icoHash;
        _assets[assetId].iexoHash = iexoHash;
        _assets[assetId].ieoHash = ieoHash;
        _assets[assetId].smlHash = smlHash;
        _assets[assetId].reportPdfHash = reportPdfHash;
        _assets[assetId].reportIpfsUri = reportIpfsUri;
        _assets[assetId].rulebookVersion = rulebookVersion;
        _assets[assetId].schemaVersion = schemaVersion;
        _assets[assetId].anchoredAt = block.timestamp;
        _assets[assetId].anchoredBy = msg.sender;
        _assets[assetId].lifecycleState = LifecycleState.ANCHORED;

        _sml[assetId] = SML({
            assetId: assetId,
            currentScore: currentScore,
            scoreVersion: "v3.0",
            rulebookVersion: rulebookVersion,
            smlHash: smlHash,
            anchoredAt: block.timestamp
        });

        emit AssetAnchored(
            assetId,
            _assets[assetId].mineSlug,
            iroHash,
            igoHash,
            icoHash,
            iexoHash,
            ieoHash,
            smlHash,
            reportPdfHash,
            block.timestamp
        );

        if (isReAnchor) {
            emit AssetReAnchored(assetId, previousIroHash, iroHash, block.timestamp);
        }
    }

    function advanceLifecycle(bytes32 assetId, LifecycleState newState)
        external
        onlyRelayer
        exists(assetId)
    {
        LifecycleState current = _assets[assetId].lifecycleState;
        require(newState != LifecycleState.ANCHORED, "ERC8097: use anchor() to reach ANCHORED state");
        require(uint8(newState) == uint8(current) + 1, "ERC8097: lifecycle must advance exactly one step");

        _assets[assetId].lifecycleState = newState;
        emit LifecycleAdvanced(assetId, current, newState, block.timestamp);
    }

    function recordCPAttestation(
        bytes32 assetId,
        bytes32 objectHash,
        string calldata cpName,
        string calldata cpBody,
        string calldata cpMembershipNumber,
        address expectedSigner,
        uint256 attestationTimestamp,
        bytes calldata signature
    ) external exists(assetId) {
        require(expectedSigner != address(0), "ERC8097: expectedSigner required");
        require(_isAssetHash(assetId, objectHash), "ERC8097: objectHash not a current hash of this asset");

        bytes32 structHash = keccak256(abi.encode(
            CP_ATTESTATION_TYPEHASH,
            assetId,
            objectHash,
            keccak256(bytes(cpName)),
            keccak256(bytes(cpBody)),
            keccak256(bytes(cpMembershipNumber)),
            attestationTimestamp
        ));
        bytes32 digest = _hashTypedDataV4(structHash);

        require(!_digestUsed[digest], "ERC8097: attestation digest already used");

        address recovered = digest.recover(signature);
        require(recovered == expectedSigner, "ERC8097: signer does not match expectedSigner");

        _digestUsed[digest] = true;
        _attestations[objectHash].push(CPAttestation({
            assetId: assetId,
            objectHash: objectHash,
            cpName: cpName,
            cpBody: cpBody,
            cpMembershipNumber: cpMembershipNumber,
            attestationTimestamp: attestationTimestamp,
            signerAddress: recovered,
            signature: signature
        }));

        emit CPAttestationRecorded(assetId, objectHash, cpName, cpBody, recovered, attestationTimestamp);
    }

    function advanceProductionStatus(bytes32 assetId, ProductionStatus newStatus)
        external
        onlyRelayer
        exists(assetId)
    {
        ProductionStatus current = _productionStatus[assetId];
        require(
            _productionTransition[uint8(current)][uint8(newStatus)],
            "ERC8097: production status transition not permitted"
        );

        _productionStatus[assetId] = newStatus;
        emit ProductionStatusAdvanced(assetId, current, newStatus, block.timestamp);
    }

    function updateDepletion(bytes32 assetId, uint256 newDepletionMt)
        external
        onlyRelayer
        exists(assetId)
    {
        require(_productionStatus[assetId] == ProductionStatus.PRODUCTION, "ERC8097: production status must be PRODUCTION");
        uint256 current = _depletionMt[assetId];
        require(newDepletionMt > current, "ERC8097: depletion can only increase");

        _depletionMt[assetId] = newDepletionMt;
        emit DepletionUpdated(assetId, current, newDepletionMt, block.timestamp);
    }

    function updateSML(bytes32 assetId, bytes32 newSmlHash, uint256 currentScore)
        external
        onlyRelayer
        exists(assetId)
    {
        require(newSmlHash != bytes32(0), "ERC8097: smlHash required");
        require(currentScore <= 1000, "ERC8097: score must be 0-1000");

        _assets[assetId].smlHash = newSmlHash;
        _sml[assetId].smlHash = newSmlHash;
        _sml[assetId].currentScore = currentScore;
        _sml[assetId].anchoredAt = block.timestamp;

        emit SMLUpdated(assetId, newSmlHash, currentScore, block.timestamp);
    }

    function _isAssetHash(bytes32 assetId, bytes32 objectHash) private view returns (bool) {
        AssetRecord storage asset = _assets[assetId];
        return objectHash == asset.iroHash
            || objectHash == asset.igoHash
            || objectHash == asset.icoHash
            || objectHash == asset.iexoHash
            || objectHash == asset.ieoHash
            || objectHash == asset.smlHash;
    }

    function getAsset(bytes32 assetId) external view returns (AssetRecord memory) {
        return _assets[assetId];
    }

    function getAssetBySlug(string calldata mineSlug) external view returns (bytes32) {
        return _slugToAsset[mineSlug];
    }

    function getLifecycleState(bytes32 assetId) external view returns (LifecycleState) {
        return _assets[assetId].lifecycleState;
    }

    function getCPAttestations(bytes32 objectHash) external view returns (CPAttestation[] memory) {
        return _attestations[objectHash];
    }

    function isAnchored(bytes32 assetId) external view returns (bool) {
        return _assets[assetId].lifecycleState == LifecycleState.ANCHORED;
    }

    function getCurrentScore(bytes32 assetId) external view returns (uint256) {
        return _sml[assetId].currentScore;
    }

    function getDepletion(bytes32 assetId) external view returns (uint256) {
        return _depletionMt[assetId];
    }

    function getProductionStatus(bytes32 assetId) external view returns (ProductionStatus) {
        return _productionStatus[assetId];
    }

    function getSML(bytes32 assetId) external view returns (SML memory) {
        return _sml[assetId];
    }

    function getDomainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function isProductionTransitionAllowed(ProductionStatus from, ProductionStatus to)
        external
        view
        returns (bool)
    {
        return _productionTransition[uint8(from)][uint8(to)];
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC165, IERC165)
        returns (bool)
    {
        return interfaceId == type(IERC8097).interfaceId || super.supportsInterface(interfaceId);
    }
}
