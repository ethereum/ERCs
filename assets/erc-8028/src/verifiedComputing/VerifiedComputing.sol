// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/VerifiedComputingStorageV1.sol";

contract VerifiedComputing is
    UUPSUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC2771ContextUpgradeable,
    VerifiedComputingStorageV1
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    bytes32 public constant MAINTAINER_ROLE = keccak256("MAINTAINER_ROLE");

    event NodeAdded(address indexed nodeAddress);
    event NodeRemoved(address indexed nodeAddress);

    event JobSubmitted(uint256 indexed jobId, uint256 indexed fileId, address nodeAddress, uint256 bidAmount);
    event JobCanceled(uint256 indexed jobId);

    event JobComplete(address indexed attestator, uint256 indexed jobId, uint256 indexed fileId);
    event Claimed(address indexed nodeAddress, uint256 amount);

    error NodeAlreadyAdded();
    error NodeNotActive();
    error InvalidJobStatus();
    error InvalidJobNode();
    error NothingToClaim();
    error InsufficientFee();
    error NoActiveNode();
    error NotJobOwner();
    error TransferFailed();

    modifier onlyActiveNode() {
        if (!(_nodes[_msgSender()].status == NodeStatus.Active)) {
            revert NodeNotActive();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() ERC2771ContextUpgradeable(address(0)) {
        _disableInitializers();
    }

    function initialize(address ownerAddress) external initializer {
        __UUPSUpgradeable_init();
        __Pausable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();

        _setRoleAdmin(MAINTAINER_ROLE, DEFAULT_ADMIN_ROLE);
        _grantRole(DEFAULT_ADMIN_ROLE, ownerAddress);
        _grantRole(MAINTAINER_ROLE, ownerAddress);
    }

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

    function version() external pure virtual override returns (uint256) {
        return 1;
    }

    function pause() external override onlyRole(MAINTAINER_ROLE) {
        _pause();
    }

    function unpause() external override onlyRole(MAINTAINER_ROLE) {
        _unpause();
    }

    function getJob(uint256 jobId) external view override returns (Job memory) {
        return _jobs[jobId];
    }

    function getNode(address nodeAddress) public view override returns (NodeInfo memory) {
        return NodeInfo({
            nodeAddress: nodeAddress,
            url: _nodes[nodeAddress].url,
            status: _nodes[nodeAddress].status,
            amount: _nodes[nodeAddress].amount,
            jobsCount: _nodes[nodeAddress].jobIdsList.length(),
            publicKey: _nodes[nodeAddress].publicKey
        });
    }

    function nodesCount() external view override returns (uint256) {
        return _nodeList.length();
    }

    function nodeList() external view override returns (address[] memory) {
        return _nodeList.values();
    }

    function nodeListAt(uint256 index) external view override returns (NodeInfo memory) {
        return getNode(_nodeList.at(index));
    }

    function activeNodesCount() external view override returns (uint256) {
        return _activeNodeList.length();
    }

    function activeNodeList() external view override returns (address[] memory) {
        return _activeNodeList.values();
    }

    function activeNodeListAt(uint256 index) external view override returns (NodeInfo memory) {
        return getNode(_activeNodeList.at(index));
    }

    function isNode(address nodeAddress) external view override returns (bool) {
        return _nodes[nodeAddress].status == NodeStatus.Active;
    }

    function fileJobIds(uint256 fileId) external view override returns (uint256[] memory) {
        return _fileJobsIds[fileId].values();
    }

    function updateNodeFee(uint256 newNodeFee) external override onlyRole(MAINTAINER_ROLE) {
        nodeFee = newNodeFee;
    }

    function addNode(address nodeAddress, string calldata url, string calldata publicKey)
        external
        override
        onlyRole(MAINTAINER_ROLE)
    {
        if (_activeNodeList.contains(nodeAddress)) {
            revert NodeAlreadyAdded();
        }
        _nodeList.add(nodeAddress);
        _activeNodeList.add(nodeAddress);
        _nodes[nodeAddress].status = NodeStatus.Active;
        _nodes[nodeAddress].url = url;
        _nodes[nodeAddress].publicKey = publicKey;
        emit NodeAdded(nodeAddress);
    }

    function removeNode(address nodeAddress) external override onlyRole(MAINTAINER_ROLE) {
        if (!_activeNodeList.contains(nodeAddress)) {
            revert NodeNotActive();
        }
        _nodes[nodeAddress].status = NodeStatus.Removed;
        _activeNodeList.remove(nodeAddress);
        emit NodeRemoved(nodeAddress);
    }

    function requestProof(uint256 fileId) public payable override whenNotPaused {
        if (msg.value < nodeFee) {
            revert InsufficientFee();
        }
        if (_activeNodeList.length() == 0) {
            revert NoActiveNode();
        }
        uint256 jobsCountTemp = ++jobsCount;
        address nodeAddress = getNode(_activeNodeList.at(jobsCountTemp % _activeNodeList.length())).nodeAddress;
        _jobs[jobsCountTemp].fileId = fileId;
        _jobs[jobsCountTemp].bidAmount = msg.value;
        _jobs[jobsCountTemp].addedTimestamp = block.timestamp;
        _jobs[jobsCountTemp].ownerAddress = _msgSender();
        _jobs[jobsCountTemp].status = JobStatus.Submitted;
        _jobs[jobsCountTemp].nodeAddress = nodeAddress;
        _fileJobsIds[fileId].add(jobsCountTemp);
        _nodes[nodeAddress].jobIdsList.add(jobsCountTemp);
        emit JobSubmitted(jobsCountTemp, fileId, nodeAddress, msg.value);
    }

    function submitJob(uint256 fileId) external payable override whenNotPaused {
        requestProof(fileId);
    }

    function completeJob(uint256 jobId) external override onlyActiveNode whenNotPaused {
        Job storage job = _jobs[jobId];
        if (job.status != JobStatus.Submitted) {
            revert InvalidJobStatus();
        }
        if (job.nodeAddress != _msgSender()) {
            revert InvalidJobNode();
        }
        _nodes[_msgSender()].amount += job.bidAmount;
        _nodes[_msgSender()].jobIdsList.remove(jobId);
        job.status = JobStatus.Completed;
        emit JobComplete(_msgSender(), jobId, job.fileId);
    }

    function claim() external nonReentrant whenNotPaused {
        uint256 amount = _nodes[_msgSender()].amount - _nodes[_msgSender()].withdrawnAmount;
        if (amount == 0) {
            revert NothingToClaim();
        }
        _nodes[_msgSender()].withdrawnAmount = _nodes[_msgSender()].amount;
        (bool success,) = payable(_msgSender()).call{value: amount}("");
        if (!success) {
            revert TransferFailed();
        }
        emit Claimed(_msgSender(), amount);
    }
}
