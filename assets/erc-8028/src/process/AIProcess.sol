// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/metatx/ERC2771ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "../verifiedComputing/VerifiedComputing.sol";
import "./interfaces/AIProcessStorageV1.sol";

contract AIProcess is
    UUPSUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC2771ContextUpgradeable,
    AIProcessStorageV1
{
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    bytes32 public constant MAINTAINER_ROLE = keccak256("MAINTAINER_ROLE");

    event NodeAdded(address indexed nodeAddress);
    event NodeRemoved(address indexed nodeAddress);

    event SettlementUpdated(address newSettlement);
    event BalanceUpdated(address indexed user, address indexed node, uint256 amount, uint256 pendingRefund);

    error NodeAlreadyAdded();
    error NodeNotActive();
    error NoActiveNode();

    error AccountNotExists(address user, address node);
    error AccountAlreadyExists(address user, address node);
    error InsufficientBalance(address user, address node);
    error InvalidAttestator(bytes32 messageHash, bytes signature, address signer);
    error InvalidUserSignature(bytes32 messageHash, uint256 nonce, address user, address node);
    error NonceTooLow();

    modifier onlyActiveNode() {
        if (!(_nodes[_msgSender()].status == NodeStatus.Active)) {
            revert NodeNotActive();
        }
        _;
    }

    modifier onlySettlement() {
        require(msg.sender == address(settlement), "Caller is not the settelemt contract");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() ERC2771ContextUpgradeable(address(0)) {
        _disableInitializers();
    }

    function initialize(address ownerAddress, address settlementAddress, uint256 lockTime_) external initializer {
        __UUPSUpgradeable_init();
        __Pausable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();

        settlement = ISettlement(settlementAddress);
        lockTime = lockTime_;

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
        Node storage node = _nodes[nodeAddress];
        node.status = NodeStatus.Active;
        node.url = url;
        node.publicKey = publicKey;
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

    function updateSettlement(address newSettlement) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        settlement = ISettlement(newSettlement);
        emit SettlementUpdated(newSettlement);
    }

    function getAccount(address user, address node) external view override returns (Account memory) {
        return _getAccount(user, node);
    }

    function getAccountPendingRefund(address user, address node) external view override returns (uint256) {
        Account storage account = _getAccount(user, node);
        return account.pendingRefund;
    }

    function getAllAccounts() external view override returns (Account[] memory accounts) {
        uint256 len = _accountLength();
        accounts = new Account[](len);

        for (uint256 i = 0; i < len; i++) {
            accounts[i] = _accountAt(i);
        }
    }

    function accountExists(address user, address node) external view override returns (bool) {
        return _accountContains(_accountKey(user, node));
    }

    function addAccount(address user, address node) external payable override onlySettlement {
        bytes32 key = _accountKey(user, node);
        if (_accountContains(key)) {
            revert AccountAlreadyExists(user, node);
        }
        _setAccount(key, user, node, msg.value);
        emit BalanceUpdated(user, node, msg.value, 0);
    }

    function deleteAccount(address user, address node) external override onlySettlement {
        bytes32 key = _accountKey(user, node);
        if (!_accountContains(key)) {
            return;
        }
        accountMap._keys.remove(key);
        delete accountMap._values[key];
    }

    function deposit(address user, address node, uint256 cancelRetrievingAmount)
        external
        payable
        override
        onlySettlement
    {
        bytes32 key = _accountKey(user, node);
        if (!_accountContains(key)) {
            revert AccountNotExists(user, node);
        }
        Account storage account = _getAccount(user, node);
        for (uint256 i = 0; i < account.refunds.length; i++) {
            Refund storage refund = account.refunds[i];
            if (refund.processed) {
                continue;
            }
            account.pendingRefund -= refund.amount;
            if (cancelRetrievingAmount <= refund.amount) {
                delete account.refunds[i];
                break;
            }
            cancelRetrievingAmount -= refund.amount;
            delete account.refunds[i];
        }
        account.balance += msg.value;
        emit BalanceUpdated(user, node, account.balance, account.pendingRefund);
    }

    function request(address user, address node) external override onlySettlement {
        Account storage account = _getAccount(user, node);
        uint256 amount = account.balance - account.pendingRefund;
        if (amount == 0) {
            return;
        }
        account.refunds.push(Refund(account.refunds.length, amount, block.timestamp, false));
        account.pendingRefund += amount;
    }

    function process(address user, address node)
        external
        override
        onlySettlement
        returns (uint256 totalAmount, uint256 balance, uint256 pendingRefund)
    {
        Account storage account = _getAccount(user, node);
        totalAmount = 0;

        for (uint256 i = 0; i < account.refunds.length; i++) {
            Refund storage refund = account.refunds[i];
            if (refund.processed) {
                continue;
            }
            if (block.timestamp < refund.createdAt + lockTime) {
                continue;
            }
            account.balance -= refund.amount;
            account.pendingRefund -= refund.amount;
            totalAmount += refund.amount;
            refund.processed = true;
        }

        balance = account.balance;
        pendingRefund = account.pendingRefund;
    }

    function settlementFees(Settlement memory settlement) external override onlyActiveNode {
        bytes32 _userMessageHash = keccak256(abi.encode(settlement.data.nonce, settlement.data.user, _msgSender()));
        address user = _userMessageHash.toEthSignedMessageHash().recover(settlement.data.userSignature);
        if (user != settlement.data.user) {
            revert InvalidUserSignature(_userMessageHash, settlement.data.nonce, settlement.data.user, _msgSender());
        }
        Account storage account = _getAccount(settlement.data.user, msg.sender);
        if (account.balance < settlement.data.cost) {
            revert InsufficientBalance(account.user, account.node);
        }
        if (settlement.data.nonce < account.nonce) {
            revert NonceTooLow();
        }
        _settlementFees(account, settlement.data.cost);
        // Update the account nonce.
        account.nonce = settlement.data.nonce;
    }

    function _settlementFees(Account storage account, uint256 cost) private {
        if (cost > (account.balance - account.pendingRefund)) {
            uint256 remainingFee = cost - (account.balance - account.pendingRefund);
            if (account.pendingRefund < remainingFee) {
                revert InsufficientBalance(account.user, account.node);
            }

            account.pendingRefund -= remainingFee;
            for (int256 i = int256(account.refunds.length - 1); i >= 0; i--) {
                Refund storage refund = account.refunds[uint256(i)];
                if (refund.processed) {
                    continue;
                }
                if (refund.amount <= remainingFee) {
                    remainingFee -= refund.amount;
                } else {
                    refund.amount -= remainingFee;
                    remainingFee = 0;
                }
                if (remainingFee == 0) {
                    break;
                }
            }
        }
        account.balance -= cost;
        settlement.settlement(account.user, cost);
        emit BalanceUpdated(account.user, msg.sender, account.balance, account.pendingRefund);
        payable(msg.sender).transfer(cost);
    }

    function _accountAt(uint256 index) internal view returns (Account storage) {
        bytes32 key = accountMap._keys.at(index);
        return accountMap._values[key];
    }

    function _accountContains(bytes32 key) internal view returns (bool) {
        return accountMap._keys.contains(key);
    }

    function _accountLength() internal view returns (uint256) {
        return accountMap._keys.length();
    }

    function _getAccount(address user, address node) internal view returns (Account storage) {
        bytes32 key = _accountKey(user, node);
        Account storage value = accountMap._values[key];
        if (!_accountContains(key)) {
            revert AccountNotExists(user, node);
        }
        return value;
    }

    function _setAccount(bytes32 key, address user, address node, uint256 balance) internal {
        Account storage account = accountMap._values[key];
        account.balance = balance;
        account.user = user;
        account.node = node;
        accountMap._keys.add(key);
    }

    function _accountKey(address user, address node) internal pure returns (bytes32) {
        return keccak256(abi.encode(user, node));
    }
}
