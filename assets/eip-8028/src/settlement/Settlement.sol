// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/SettlementStorageV1.sol";

contract Settlement is
    UUPSUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC2771ContextUpgradeable,
    SettlementStorageV1
{
    using EnumerableSet for EnumerableSet.Bytes32Set;

    bytes32 public constant MAINTAINER_ROLE = keccak256("MAINTAINER_ROLE");

    event QueryUpdated(address newQuery);
    event InferenceUpdated(address newInference);
    event TrainingUpdated(address newTraining);

    event UserAdded(address indexed addr);
    event UserDeleted(address indexed addr);

    error UserNotExists(address user);
    error UserAlreadyExists(address user);
    error InsufficientBalance(address user);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() ERC2771ContextUpgradeable(address(0)) {
        _disableInitializers();
    }

    function initialize(
        address ownerAddress_,
        address queryAddress_,
        address inferenceAddress_,
        address trainingAddress_
    ) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __Pausable_init();

        queryAddress = payable(queryAddress_);
        inferenceAddress = payable(inferenceAddress_);
        trainingAddress = payable(trainingAddress_);
        query = IAIProcess(queryAddress_);
        inference = IAIProcess(inferenceAddress_);
        training = IAIProcess(trainingAddress_);

        _setRoleAdmin(MAINTAINER_ROLE, DEFAULT_ADMIN_ROLE);
        _grantRole(DEFAULT_ADMIN_ROLE, ownerAddress_);
        _grantRole(MAINTAINER_ROLE, ownerAddress_);
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

    function updateQuery(address newQuery) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        queryAddress = payable(newQuery);
        query = IAIProcess(newQuery);
        emit QueryUpdated(newQuery);
    }

    function updateInference(address newInference) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        inferenceAddress = payable(newInference);
        inference = IAIProcess(newInference);
        emit InferenceUpdated(newInference);
    }

    function updateTraining(address newTraining) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        trainingAddress = payable(newTraining);
        training = IAIProcess(newTraining);
        emit TrainingUpdated(newTraining);
    }

    modifier onlyAIProcess() {
        require(
            msg.sender == queryAddress || msg.sender == trainingAddress || msg.sender == inferenceAddress,
            "Caller is not the query, inference or training contract"
        );
        _;
    }

    function getUser(address user) external view override returns (User memory) {
        return _getUser(user);
    }

    function getAllUsers() external view override returns (User[] memory users) {
        uint256 len = _userLength();
        users = new User[](len);
        for (uint256 i = 0; i < len; i++) {
            users[i] = _userAt(i);
        }
    }

    function addUser() external payable override {
        bytes32 key = _userKey(msg.sender);
        if (_userContains(key)) {
            revert UserAlreadyExists(msg.sender);
        }
        _setUser(key, msg.sender, msg.value);
        emit UserAdded(msg.sender);
    }

    function deleteUser() external override {
        bytes32 key = _userKey(msg.sender);
        if (!_userContains(key)) {
            revert UserNotExists(msg.sender);
        }
        User storage user = _getUser(msg.sender);
        for (uint256 i = 0; i < user.queryNodes.length; i++) {
            query.deleteAccount(msg.sender, user.queryNodes[i]);
        }
        for (uint256 i = 0; i < user.inferenceNodes.length; i++) {
            inference.deleteAccount(msg.sender, user.inferenceNodes[i]);
        }
        for (uint256 i = 0; i < user.trainingNodes.length; i++) {
            training.deleteAccount(msg.sender, user.trainingNodes[i]);
        }

        userMap._keys.remove(key);
        delete userMap._values[key];
    }

    function deposit() external payable override {
        bytes32 key = _userKey(msg.sender);
        if (!_userContains(key)) {
            revert UserNotExists(msg.sender);
        }
        User memory user = _getUser(msg.sender);
        user.availableBalance += msg.value;
        user.totalBalance += msg.value;
    }

    function withdraw(uint256 amount) external override {
        User memory user = _getUser(msg.sender);
        if (user.availableBalance < amount) {
            revert InsufficientBalance(msg.sender);
        }
        user.availableBalance -= amount;
        user.totalBalance -= amount;
        payable(msg.sender).transfer(amount);
    }

    function depositQuery(address node, uint256 amount) external override {
        User storage user = _getUser(msg.sender);
        uint256 transferAmount = amount;
        if (query.accountExists(msg.sender, node)) {
            uint256 retrievingAmount = query.getAccountPendingRefund(msg.sender, node);
            uint256 cancelRetrievingAmount = Math.min(amount, retrievingAmount);
            transferAmount -= cancelRetrievingAmount;
            query.deposit{value: transferAmount}(msg.sender, node, cancelRetrievingAmount);
        } else {
            query.addAccount{value: transferAmount}(msg.sender, node);
            user.queryNodes.push(node);
        }
        // Note: we have the overflow check here.
        user.availableBalance -= transferAmount;
    }

    function depositInference(address node, uint256 amount) external override {
        User storage user = _getUser(msg.sender);
        uint256 transferAmount = amount;
        if (inference.accountExists(msg.sender, node)) {
            uint256 retrievingAmount = inference.getAccountPendingRefund(msg.sender, node);
            uint256 cancelRetrievingAmount = Math.min(amount, retrievingAmount);
            transferAmount -= cancelRetrievingAmount;
            inference.deposit{value: transferAmount}(msg.sender, node, cancelRetrievingAmount);
        } else {
            inference.addAccount{value: transferAmount}(msg.sender, node);
            user.inferenceNodes.push(node);
        }
        // Note: we have the overflow check here.
        user.availableBalance -= transferAmount;
    }

    function depositTraining(address node, uint256 amount) external override {
        User storage user = _getUser(msg.sender);
        uint256 transferAmount = amount;
        if (training.accountExists(msg.sender, node)) {
            uint256 retrievingAmount = training.getAccountPendingRefund(msg.sender, node);
            uint256 cancelRetrievingAmount = Math.min(amount, retrievingAmount);
            transferAmount -= cancelRetrievingAmount;
            training.deposit{value: transferAmount}(msg.sender, node, cancelRetrievingAmount);
        } else {
            training.addAccount{value: transferAmount}(msg.sender, node);
            user.trainingNodes.push(node);
        }
        // Note: we have the overflow check here.
        user.availableBalance -= transferAmount;
    }

    function retrieveQuery(address[] memory nodes) external override {
        _retrieve(nodes, query);
    }

    function retrieveTraining(address[] memory nodes) external override {
        _retrieve(nodes, training);
    }

    function retrieveInference(address[] memory nodes) external override {
        _retrieve(nodes, inference);
    }

    function settlement(address addr, uint256 cost) external override onlyAIProcess {
        User storage user = _getUser(addr);
        require((user.totalBalance - user.availableBalance) >= cost, "Insufficient balance");
        user.totalBalance -= cost;
    }

    function _retrieve(address[] memory nodes, IAIProcess process) internal {
        User storage user = _getUser(msg.sender);
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < nodes.length; i++) {
            (uint256 amount,,) = process.process(msg.sender, nodes[i]);
            totalAmount += amount;
            process.request(msg.sender, nodes[i]);
        }
        user.availableBalance += totalAmount;
    }

    /* User functions */

    function _userKey(address addr) internal pure returns (bytes32) {
        return keccak256(abi.encode(addr));
    }

    function _userAt(uint256 index) internal view returns (User storage) {
        bytes32 key = userMap._keys.at(index);
        return userMap._values[key];
    }

    function _userContains(bytes32 key) internal view returns (bool) {
        return userMap._keys.contains(key);
    }

    function _userLength() internal view returns (uint256) {
        return userMap._keys.length();
    }

    function _getUser(address user) internal view returns (User storage) {
        bytes32 key = _userKey(user);
        User storage value = userMap._values[key];
        if (!_userContains(key)) {
            revert UserNotExists(user);
        }
        return value;
    }

    function _setUser(bytes32 key, address addr, uint256 balance) internal {
        User storage user = userMap._values[key];
        user.availableBalance = balance;
        user.totalBalance = balance;
        user.addr = addr;
        userMap._keys.add(key);
    }
}
