// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IDataIndex.sol";
import "./interfaces/IDataObject.sol";
import "./interfaces/IIDManager.sol";
import "./interfaces/IDataPointRegistry.sol";

/**
 * @title Data Index contract
 * @notice Minimalistic implementation of a Data Index contract
 */
contract DataIndex is IDataIndex, IIDManager, AccessControl {
    /// @dev Error thrown when the sender is not an admin of the DataPoint
    error InvalidDataPointAdmin(DataPoint dp, address sender);

    /// @dev Error thrown when the DataManager is not approved to interact with the DataPoint
    error DataManagerNotApproved(DataPoint dp, address dm);

    /// @dev Error thrown when the dataIndex identifier is incorrect
    error IncorrectIdentifier(bytes32 diid);

    /**
     * @notice Event emitted when DataManager is approved for DataPoint
     * @param dp Identifier of the DataPoint
     * @param dm Address of DataManager
     * @param approved if DataManager is approved
     */
    event DataPointDMApprovalChanged(DataPoint dp, address dm, bool approved);

    /// @dev Mapping of DataPoint to DataManagers allowed to write to this DP (in any DataObject)
    mapping(DataPoint => mapping(address dm => bool allowed)) dmApprovals;

    /**
     * @notice Restricts access to the function, allowing only DataPoint admins
     * @param dp DataPoint to check ownership of
     */
    modifier onlyDPOwner(DataPoint dp) {
        (uint32 chainId, address registry, ) = DataPoints.decode(dp);
        ChainidTools.requireCurrentChain(chainId);
        bool isAdmin = IDataPointRegistry(registry).isAdmin(dp, msg.sender);
        if (!isAdmin) revert InvalidDataPointAdmin(dp, msg.sender);
        _;
    }

    /**
     * @notice Allows access only to DataManagers which was previously approved
     * @param dp DataPoint to check DataManager approval for
     */
    modifier onlyApprovedDM(DataPoint dp) {
        bool approved = dmApprovals[dp][msg.sender];
        if (!approved) revert DataManagerNotApproved(dp, msg.sender);
        _;
    }

    /// @dev Sets the default admin role
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    ///@inheritdoc IDataIndex
    function isApprovedDataManager(DataPoint dp, address dm) external view returns (bool) {
        return dmApprovals[dp][dm];
    }

    ///@inheritdoc IDataIndex
    function allowDataManager(DataPoint dp, address dm, bool approved) external onlyDPOwner(dp) {
        dmApprovals[dp][dm] = approved;
        emit DataPointDMApprovalChanged(dp, dm, approved);
    }

    ///@inheritdoc IDataIndex
    function read(address dobj, DataPoint dp, bytes4 operation, bytes calldata data) external view returns (bytes memory) {
        return IDataObject(dobj).read(dp, operation, data);
    }

    ///@inheritdoc IDataIndex
    function write(address dobj, DataPoint dp, bytes4 operation, bytes calldata data) external onlyApprovedDM(dp) returns (bytes memory) {
        return IDataObject(dobj).write(dp, operation, data);
    }

    ///@inheritdoc IIDManager
    function diid(address account, DataPoint) external pure returns (bytes32) {
        return bytes32(uint256(uint160(account)));
    }

    ///@inheritdoc IIDManager
    function ownerOf(bytes32 _diid) external view returns (uint32, address) {
        if (_diid & 0xFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000000000000000 != 0) revert IncorrectIdentifier(_diid); // Require first 12 bytes empty, leaving only 20 bytes of address non-empty
        address account = address(uint160(uint256(_diid)));
        if (account == address(0)) revert IncorrectIdentifier(_diid);
        return (ChainidTools.chainid(), account);
    }
}
