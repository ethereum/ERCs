// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ISettlement} from "../../settlement/interfaces/ISettlement.sol";

interface IAIProcess {
    struct Account {
        address user;
        address node;
        uint256 nonce;
        uint256 balance;
        uint256 pendingRefund;
        Refund[] refunds;
    }

    struct Refund {
        uint256 index;
        uint256 amount;
        uint256 createdAt;
        bool processed;
    }

    struct AccountMap {
        EnumerableSet.Bytes32Set _keys;
        mapping(bytes32 => Account) _values;
    }

    struct SettlementData {
        // Use string here and sync with the chat/training id.
        string id;
        address user;
        uint256 cost;
        uint256 nonce;
        bytes userSignature;
    }

    struct Settlement {
        bytes signature;
        SettlementData data;
    }

    enum NodeStatus {
        None,
        Active,
        Removed
    }

    struct Node {
        NodeStatus status;
        string url;
        uint256 amount;
        uint256 withdrawnAmount;
        EnumerableSet.UintSet jobIdsList;
        string publicKey;
    }

    struct NodeInfo {
        address nodeAddress;
        string url;
        NodeStatus status;
        uint256 amount;
        uint256 jobsCount;
        string publicKey;
    }

    function version() external pure returns (uint256);

    function pause() external;
    function unpause() external;

    // Node operations

    function nodeList() external view returns (address[] memory);
    function nodeListAt(uint256 index) external view returns (NodeInfo memory);
    function nodesCount() external view returns (uint256);

    function activeNodesCount() external view returns (uint256);
    function activeNodeList() external view returns (address[] memory);
    function activeNodeListAt(uint256 index) external view returns (NodeInfo memory);

    function getNode(address nodeAddress) external view returns (NodeInfo memory);
    function addNode(address nodeAddress, string memory url, string memory publicKey) external;
    function removeNode(address nodeAddress) external;
    function isNode(address nodeAddress) external view returns (bool);

    // Settlement account and operations

    function settlement() external view returns (ISettlement);
    function updateSettlement(address newSettlement) external;

    function getAccount(address user, address node) external view returns (Account memory);
    function getAccountPendingRefund(address user, address node) external view returns (uint256);
    function getAllAccounts() external view returns (Account[] memory accounts);
    function accountExists(address user, address node) external view returns (bool);
    function addAccount(address user, address node) external payable;
    function deleteAccount(address user, address node) external;

    function deposit(address user, address node, uint256 cancelRetrievingAmount) external payable;
    function request(address user, address node) external;
    function process(address user, address node)
        external
        returns (uint256 totalAmount, uint256 balance, uint256 pendingRefund);

    function settlementFees(Settlement memory settlement) external;
}
