// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IAIProcess} from "../../process/interfaces/IAIProcess.sol";

interface ISettlement {
    struct User {
        address addr;
        uint256 availableBalance;
        uint256 totalBalance;
        address[] queryNodes;
        address[] inferenceNodes;
        address[] trainingNodes;
    }

    struct UserMap {
        EnumerableSet.Bytes32Set _keys;
        mapping(bytes32 => User) _values;
    }

    function version() external pure returns (uint256);
    function query() external view returns (IAIProcess);
    function updateQuery(address newQuery) external;
    function training() external view returns (IAIProcess);
    function updateTraining(address newTraining) external;
    function inference() external view returns (IAIProcess);
    function updateInference(address newInference) external;

    function pause() external;
    function unpause() external;

    function getUser(address user) external view returns (User memory);
    function getAllUsers() external view returns (User[] memory users);
    function addUser() external payable;
    function deleteUser() external;
    function deposit() external payable;
    function withdraw(uint256 amount) external;

    function depositQuery(address node, uint256 amount) external;
    function depositInference(address node, uint256 amount) external;
    function depositTraining(address node, uint256 amount) external;

    function retrieveQuery(address[] memory nodes) external;
    function retrieveInference(address[] memory nodes) external;
    function retrieveTraining(address[] memory nodes) external;

    function settlement(address addr, uint256 cost) external;
}
