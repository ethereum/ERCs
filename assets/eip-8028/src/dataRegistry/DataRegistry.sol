// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "./interfaces/DataRegistryStorageV1.sol";

contract DataRegistry is
    UUPSUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC2771ContextUpgradeable,
    DataRegistryStorageV1
{
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    bytes32 public constant MAINTAINER_ROLE = keccak256("MAINTAINER_ROLE");

    event FileAdded(uint256 indexed fileId, address indexed ownerAddress, string url);
    event ProofAdded(uint256 indexed fileId, address indexed ownerAddress, uint256 proofIndex, string proofUrl);
    event PermissionGranted(uint256 indexed fileId, address indexed account);

    event RewardRequested(
        address indexed contributorAddress, uint256 indexed fileId, uint256 indexed proofIndex, uint256 rewardAmount
    );

    event PublicKeyUpdated(string newPublicKey);

    event TokenUpdated(address newToken);
    event VerifiedComputingUpdated(address newVerifiedComputing);

    error NotFileOwner();
    error FileUrlAlreadyUsed();
    error FileNotFound();
    error FileAlreadyRewarded();
    error NoPermission();
    error InvalidUrl();
    error InvalidAttestator(bytes32 messageHash, bytes signature, address signer);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() ERC2771ContextUpgradeable(address(0)) {
        _disableInitializers();
    }

    struct InitParams {
        address ownerAddress;
        address tokenAddress;
        address verifiedComputingAddress;
        string name;
        string publicKey;
    }

    function initialize(InitParams memory params) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __Pausable_init();

        name = params.name;
        token = DataAnchoringToken(params.tokenAddress);
        verifiedComputing = IVerifiedComputing(params.verifiedComputingAddress);
        publicKey = params.publicKey;

        _setRoleAdmin(MAINTAINER_ROLE, DEFAULT_ADMIN_ROLE);
        _grantRole(DEFAULT_ADMIN_ROLE, params.ownerAddress);
        _grantRole(MAINTAINER_ROLE, params.ownerAddress);
    }

    /**
     * @notice Upgrade the contract
     * This function is required by OpenZeppelin's UUPSUpgradeable
     *
     * @param newImplementation                  new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function _msgSender()
        internal
        view
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (address sender)
    {
        return ERC2771ContextUpgradeable._msgSender();
    }

    function _msgData()
        internal
        view
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (bytes calldata)
    {
        return ERC2771ContextUpgradeable._msgData();
    }

    function _contextSuffixLength()
        internal
        view
        override(ContextUpgradeable, ERC2771ContextUpgradeable)
        returns (uint256)
    {
        return ERC2771ContextUpgradeable._contextSuffixLength();
    }

    function _checkRole(bytes32 role) internal view override {
        _checkRole(role, msg.sender);
    }

    function setRoleAdmin(bytes32 role, bytes32 adminRole) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setRoleAdmin(role, adminRole);
    }

    /**
     * @notice Returns the version of the contract
     */
    function version() external pure virtual returns (uint256) {
        return 1;
    }

    /**
     * @dev Pauses the contract
     */
    function pause() external override onlyRole(MAINTAINER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses the contract
     */
    function unpause() external override onlyRole(MAINTAINER_ROLE) {
        _unpause();
    }

    function getFile(uint256 fileId) external view returns (FileResponse memory) {
        File storage file = _files[fileId];
        return FileResponse({
            id: fileId,
            url: file.url,
            hash: file.hash,
            ownerAddress: file.ownerAddress,
            proofIndex: file.proofIndex,
            rewardAmount: file.rewardAmount
        });
    }

    function getFileIdByUrl(string memory url) external view override returns (uint256) {
        return _urlHashToFileId[keccak256(abi.encodePacked(url))];
    }

    function getFileProof(uint256 fileId, uint256 index) external view override returns (Proof memory) {
        return _files[fileId].proofs[index];
    }

    function getFilePermission(uint256 fileId, address account) external view override returns (string memory) {
        return _files[fileId].permissions[account];
    }

    function addFile(string memory url, string memory hash) external override whenNotPaused returns (uint256) {
        return _addFile(url, hash, _msgSender());
    }

    function addFileWithPermissions(
        string memory url,
        string memory hash,
        address ownerAddress,
        Permission[] memory permissions
    ) external override whenNotPaused returns (uint256) {
        uint256 fileId = _addFile(url, hash, ownerAddress);
        for (uint256 i = 0; i < permissions.length; i++) {
            _files[fileId].permissions[permissions[i].account] = permissions[i].key;
            emit PermissionGranted(fileId, permissions[i].account);
        }
        return fileId;
    }

    function addPermissionForFile(uint256 fileId, address account, string memory key) external override whenNotPaused {
        if (_msgSender() != _files[fileId].ownerAddress) {
            revert NotFileOwner();
        }
        _files[fileId].permissions[account] = key;
        emit PermissionGranted(fileId, account);
    }

    function addFileAndRequestProof(
        string memory url,
        string memory hash,
        address ownerAddress,
        Permission[] memory permissions
    ) external payable override whenNotPaused returns (uint256) {
        uint256 fileId = this.addFileWithPermissions(url, hash, ownerAddress, permissions);
        verifiedComputing.requestProof{value: msg.value}(fileId);
        return fileId;
    }

    function addProof(uint256 fileId, Proof memory proof) external override whenNotPaused {
        uint256 cachedProofCount = ++_files[fileId].proofsCount;
        _files[fileId].proofs[cachedProofCount] = proof;
        emit ProofAdded(fileId, _files[fileId].ownerAddress, cachedProofCount, proof.data.proofUrl);
    }

    function _addFile(string memory url, string memory hash, address ownerAddress) internal returns (uint256) {
        uint256 count = ++filesCount;
        bytes32 urlHash = keccak256(abi.encodePacked(url));
        if (_urlHashToFileId[urlHash] != 0) {
            revert FileUrlAlreadyUsed();
        }
        File storage file = _files[count];
        file.ownerAddress = ownerAddress;
        file.url = url;
        file.hash = hash;
        _urlHashToFileId[urlHash] = count;
        emit FileAdded(count, ownerAddress, url);
        return count;
    }

    function updatePublicKey(string calldata newPublicKey) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        publicKey = newPublicKey;
        emit PublicKeyUpdated(newPublicKey);
    }

    function updateToken(address newToken) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        token = DataAnchoringToken(newToken);
        emit TokenUpdated(newToken);
    }

    function updateVerifiedComputing(address newVerifiedComputing) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        verifiedComputing = IVerifiedComputing(newVerifiedComputing);
        emit VerifiedComputingUpdated(newVerifiedComputing);
    }

    function requestReward(uint256 fileId, uint256 proofIndex) external override whenNotPaused nonReentrant {
        Proof memory fileProof = this.getFileProof(fileId, proofIndex);
        File storage file = _files[fileId];
        // Has been rewarded? Revert here.
        if (file.rewardAmount != 0) {
            revert FileAlreadyRewarded();
        }
        // Validate the signature using the verified computing node.
        bytes32 _messageHash = keccak256(abi.encode(fileProof.data));
        address signer = _messageHash.toEthSignedMessageHash().recover(fileProof.signature);
        if (!verifiedComputing.isNode(signer)) {
            revert InvalidAttestator(_messageHash, fileProof.signature, signer);
        }
        // When the file has the timestamp and proof index field,
        // which denotes the file has been verfied
        file.timestamp = block.timestamp;
        file.proofIndex = proofIndex;
        file.rewardAmount = fileProof.data.score;
        // Mint the DAT.
        token.mint(file.ownerAddress, file.rewardAmount, file.url, true);

        emit RewardRequested(file.ownerAddress, fileId, proofIndex, file.rewardAmount);
    }
}
