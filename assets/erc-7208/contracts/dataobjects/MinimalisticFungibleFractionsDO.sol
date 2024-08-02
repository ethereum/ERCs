// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Arrays.sol";
import "../interfaces/IIDManager.sol";
import "../interfaces/IFungibleFractionsOperations.sol";
import "../interfaces/IDataPointRegistry.sol";
import "../interfaces/IDataIndex.sol";
import "../interfaces/IDataObject.sol";
import "../utils/OmnichainAddresses.sol";

/**
 * @title Minimalistic Fungible Fractions Data Object
 * @notice DataObject with base funtionality of Fungible Fractions (Can be used for ERC1155-Compatible DataManagers)
 * @dev This contract exposes base functionality of Fungible Fraction tokens, including
 *      balanceOf, totalSupply, exists, transferFrom, mint, burn and their batch variants.
 *
 *      NOTE: This contract is expected to be used by a DataManager contract, which could
 *      implement a fungible token interface and provide more advanced features like approvals,
 *      access control, metadata management, etc. As may be an ERC1155 token.
 *
 *      This contract only emit basic events, it is expected that the DataManager contract will
 *      emit the events for the token operations
 */
contract MinimalisticFungibleFractionsDO is IDataObject {
    using Arrays for uint256[];
    using Arrays for address[];
    using EnumerableSet for EnumerableSet.UintSet;

    /**
     * @notice Error thrown when the msg.sender is not the expected caller
     * @param dp The DataPoint identifier
     * @param sender The msg.sender address
     */
    error InvalidCaller(DataPoint dp, address sender);

    /**
     * @notice Error thrown when the DataPoint is not initialized with a DataIndex implementation
     * @param dp The DataPoint identifier
     */
    error UninitializedDataPoint(DataPoint dp);
    
    /// @dev Error thrown when the operation arguments are wrong
    error WrongOperationArguments();

    /**
     * @notice Error thrown when the read operation is unknown
     * @param selector The operation selector
     */
    error UnknownReadOperation(bytes4 selector);

    /**
     * @notice Error thrown when the write operation is unknown
     * @param selector The operation selector
     */
    error UnknownWriteOperation(bytes4 selector);
    
    /**
     * @notice Error thrown when the balance is insufficient
     * @param diid The DataIndex identifier
     * @param id The id of the token
     * @param balance The current balance
     * @param value The requested amount
     */
    error InsufficientBalance(bytes32 diid, uint256 id, uint256 balance, uint256 value);

    /**
     * @notice Error thrown when the total supply is insufficient
     * @param id The id of the token
     * @param totalSupply The current total supply
     * @param value The requested amount
     * @dev This should never happen because we've already checked "from" balance
     */
    error InsufficientTotalSupply(uint256 id, uint256 totalSupply, uint256 value);

    /// @dev Error thrown when the params length mismatch
    error ArrayLengthMismatch();

    /**
     * @notice Event emitted when the DataIndex implementation is set
     * @param dp The DataPoint identifier
     * @param dataIndexImplementation The DataIndex implementation address
     */
    event DataIndexImplementationSet(DataPoint dp, address dataIndexImplementation);

    /**
     * @notice Data structure for storing Fungible Fractions data
     * @param totalSupplyAll Total supply of all tokens
     * @param totalSupply Mapping of token id to total supply
     * @dev Data related to the DataPoint as a whole
     */
    struct DpData {
        uint256 totalSupplyAll;
        mapping(uint256 id => uint256 totalSupplyOfId) totalSupply;
    }

    /**
     * @notice Data structure for storing Fungible Fractions data of a user
     * @param ids Enumerable set of object (ERC1155 token) ids
     * @param balances Mapping of object (ERC1155 token) id to balance of the user owning diid
     * @dev Data related to a specific user of a DataPoint (user identified by his DataIndex id)
     */
    struct DiidData {
        EnumerableSet.UintSet ids;
        mapping(uint256 id => uint256 value) balances;
    }

    /**
     * @notice Data structure to store DataPoint data
     * @param dataIndexImplementation The DataIndex implementation set for the DataPoint
     * @param dpData The DataPoint data
     * @param dataIndexData Mapping of diid to user data
     */
    struct DataPointStorage {
        IDataIndex dataIndexImplementation;
        DpData dpData;
        mapping(bytes32 diid => DiidData) diidData;
    }

    /// @dev Mapping of DataPoint to DataPointStorage
    mapping(DataPoint => DataPointStorage) private dpStorages;

    /**
     * @notice Modifier to check if the caller is the DataIndex implementation set for the DataPoint
     * @param dp The DataPoint identifier
     */
    modifier onlyDataIndex(DataPoint dp) {
        DataPointStorage storage dps = _dataPointStorage(dp);
        if (address(dps.dataIndexImplementation) != msg.sender) revert InvalidCaller(dp, msg.sender);
        _;
    }

    /// @inheritdoc IDataObject
    function setDIImplementation(DataPoint dp, IDataIndex newImpl) external {
        DataPointStorage storage dps = dpStorages[dp];
        if (address(dps.dataIndexImplementation) == address(0)) {
            // Registering new DataPoint
            // Should be called by DataPoint Admin
            if (!_isDataPointAdmin(dp, msg.sender)) revert InvalidCaller(dp, msg.sender);
        } else {
            // Updating the DataPoint
            // Should be called by current DataIndex or DataPoint Admin
            if ((address(dps.dataIndexImplementation) != msg.sender) && !_isDataPointAdmin(dp, msg.sender)) revert InvalidCaller(dp, msg.sender);
        }
        dps.dataIndexImplementation = newImpl;
        emit DataIndexImplementationSet(dp, address(newImpl));
    }

    // =========== Dispatch functions ============
    /// @inheritdoc IDataObject
    function read(DataPoint dp, bytes4 operation, bytes calldata data) external view returns (bytes memory) {
        return _dispatchRead(dp, operation, data);
    }

    /// @inheritdoc IDataObject
    function write(DataPoint dp, bytes4 operation, bytes calldata data) external onlyDataIndex(dp) returns (bytes memory) {
        return _dispatchWrite(dp, operation, data);
    }

    function _dispatchRead(DataPoint dp, bytes4 operation, bytes calldata data) internal view virtual returns (bytes memory) {
        if (operation == IFungibleFractionsOperations.balanceOf.selector) {
            (address account, uint256 id) = abi.decode(data, (address, uint256));
            return abi.encode(_balanceOf(dp, account, id));
        } else if (operation == IFungibleFractionsOperations.balanceOfBatchAccounts.selector) {
            (address[] memory accounts, uint256[] memory ids) = abi.decode(data, (address[], uint256[]));
            return abi.encode(_balanceOfBatchAccounts(dp, accounts, ids));
        } else if (operation == IFungibleFractionsOperations.totalSupply.selector) {
            return abi.encode(_totalSupply(dp, abi.decode(data, (uint256))));
        } else if (operation == IFungibleFractionsOperations.totalSupplyAll.selector) {
            if (data.length != 0) revert WrongOperationArguments();
            return abi.encode(_totalSupplyAll(dp));
        } else if (operation == IFungibleFractionsOperations.exists.selector) {
            return abi.encode(_exists(dp, abi.decode(data, (uint256))));
        } else {
            revert UnknownReadOperation(operation);
        }
    }

    function _dispatchWrite(DataPoint dp, bytes4 operation, bytes calldata data) internal virtual returns (bytes memory) {
        if (operation == IFungibleFractionsOperations.transferFrom.selector) {
            (address from, address to, uint256 id, uint256 value) = abi.decode(data, (address, address, uint256, uint256));
            _transferFrom(dp, from, to, id, value);
            return "";
        } else if (operation == IFungibleFractionsOperations.mint.selector) {
            (address to, uint256 id, uint256 value) = abi.decode(data, (address, uint256, uint256));
            _mint(dp, to, id, value);
            return "";
        } else if (operation == IFungibleFractionsOperations.burn.selector) {
            (address from, uint256 id, uint256 value) = abi.decode(data, (address, uint256, uint256));
            _burn(dp, from, id, value);
            return "";
        } else if (operation == IFungibleFractionsOperations.batchTransferFrom.selector) {
            (address from, address to, uint256[] memory ids, uint256[] memory values) = abi.decode(data, (address, address, uint256[], uint256[]));
            _batchTransferFrom(dp, from, to, ids, values);
            return "";
        } else {
            revert UnknownWriteOperation(operation);
        }
    }

    // =========== Logic implementation ============

    function _balanceOf(DataPoint dp, address account, uint256 id) internal view returns (uint256) {
        bytes32 diid = _tryDiid(dp, account);
        if (diid == 0) return 0;
        (bool success, DiidData storage od) = _tryDiidData(dp, diid);
        return success ? od.balances[id] : 0;
    }

    function _balanceOfBatchAccounts(DataPoint dp, address[] memory accounts, uint256[] memory ids) internal view returns (uint256[] memory balances) {
        if (accounts.length != ids.length) revert ArrayLengthMismatch();
        balances = new uint256[](accounts.length);
        for (uint256 i; i < accounts.length; i++) {
            uint256 id = ids.unsafeMemoryAccess(i);
            address account = accounts.unsafeMemoryAccess(i);
            bytes32 diid = _tryDiid(dp, account);
            if (diid == 0) {
                balances[i] = 0;
            } else {
                (bool success, DiidData storage od) = _tryDiidData(dp, diid);
                balances[i] = success ? od.balances[id] : 0;
            }
        }
    }

    function _totalSupply(DataPoint dp, uint256 id) internal view returns (uint256) {
        (bool success, DpData storage dd) = _tryDpData(dp);
        return success ? dd.totalSupply[id] : 0;
    }

    function _totalSupplyAll(DataPoint dp) internal view returns (uint256) {
        (bool success, DpData storage dd) = _tryDpData(dp);
        return success ? dd.totalSupplyAll : 0;
    }

    function _exists(DataPoint dp, uint256 id) internal view returns (bool) {
        (bool success, DpData storage dd) = _tryDpData(dp);
        return success ? (dd.totalSupply[id] > 0) : false;
    }

    function _transferFrom(DataPoint dp, address from, address to, uint256 id, uint256 value) internal virtual {
        bytes32 diidFrom = _diid(dp, from);
        bytes32 diidTo = _diid(dp, to);
        DiidData storage diiddFrom = _diidData(dp, diidFrom);
        DiidData storage diiddTo = _diidData(dp, diidTo);
        _decreaseBalance(diiddFrom, id, value, dp, diidFrom);
        _increaseBalance(diiddTo, id, value, dp, diidTo);
    }

    function _mint(DataPoint dp, address to, uint256 id, uint256 value) internal virtual {
        bytes32 diidTo = _diid(dp, to);
        DiidData storage diiddTo = _diidData(dp, diidTo);
        _increaseBalance(diiddTo, id, value, dp, diidTo);

        DpData storage dpd = _dpData(dp);
        dpd.totalSupply[id] += value;
        dpd.totalSupplyAll += value;
    }

    function _burn(DataPoint dp, address from, uint256 id, uint256 value) internal virtual {
        bytes32 diidFrom = _diid(dp, from);
        DiidData storage diiddFrom = _diidData(dp, diidFrom);
        _decreaseBalance(diiddFrom, id, value, dp, diidFrom);
        DpData storage dpd = _dpData(dp);
        uint256 totalSupply = dpd.totalSupply[id];
        if (totalSupply < value) revert InsufficientTotalSupply(id, totalSupply, value);
        unchecked {
            totalSupply -= value;
        }
        dpd.totalSupply[id] = totalSupply;
        uint256 totalSupplyAll = dpd.totalSupplyAll;
        if (totalSupplyAll < value) revert InsufficientTotalSupply(id, totalSupplyAll, value);
        unchecked {
            totalSupplyAll -= value;
        }
        dpd.totalSupplyAll = totalSupplyAll;
    }

    function _batchTransferFrom(DataPoint dp, address from, address to, uint256[] memory ids, uint256[] memory values) internal virtual {
        if (ids.length != values.length) revert ArrayLengthMismatch();
        bytes32 diidFrom = _diid(dp, from);
        bytes32 diidTo = _diid(dp, to);
        DiidData storage diiddFrom = _diidData(dp, diidFrom);
        DiidData storage diiddTo = _diidData(dp, diidTo);
        for (uint256 i; i < ids.length; i++) {
            uint256 id = ids.unsafeMemoryAccess(i);
            uint256 value = values.unsafeMemoryAccess(i);
            _decreaseBalance(diiddFrom, id, value, dp, diidFrom);
            _increaseBalance(diiddTo, id, value, dp, diidTo);
        }
    }

    function _increaseBalance(DiidData storage diidd, uint256 id, uint256 value, DataPoint, bytes32) private {
        diidd.balances[id] += value;
        diidd.ids.add(id); // if id is already in the set, this call will return false, but we don't care
    }

    function _decreaseBalance(DiidData storage diidd, uint256 id, uint256 value, DataPoint, bytes32 diidFrom) private {
        uint256 diidBalance = diidd.balances[id];
        if (diidBalance < value) {
            revert InsufficientBalance(diidFrom, id, diidBalance, value);
        } else {
            unchecked {
                diidBalance -= value;
            }
            diidd.balances[id] = diidBalance;
            if (diidBalance == 0) {
                diidd.ids.remove(id);
            }
        }
    }

    // =========== Helper functions ============

    function _isDataPointAdmin(DataPoint dp, address account) internal view returns (bool) {
        (uint32 chainId, address registry, ) = DataPoints.decode(dp);
        ChainidTools.requireCurrentChain(chainId);
        return IDataPointRegistry(registry).isAdmin(dp, account);
    }

    function _diid(DataPoint dp, address account) internal view returns (bytes32) {
        return IIDManager(msg.sender).diid(account, dp);
    }

    function _tryDiid(DataPoint dp, address account) internal view returns (bytes32) {
        try IIDManager(msg.sender).diid(account, dp) returns (bytes32 diid) {
            return diid;
        } catch {
            return 0;
        }
    }

    function _dpData(DataPoint dp) internal view returns (DpData storage) {
        DataPointStorage storage dps = _dataPointStorage(dp);
        return dps.dpData;
    }

    function _diidData(DataPoint dp, bytes32 diid) internal view returns (DiidData storage) {
        DataPointStorage storage dps = _dataPointStorage(dp);
        return dps.diidData[diid];
    }

    function _tryDpData(DataPoint dp) internal view returns (bool success, DpData storage) {
        (bool found, DataPointStorage storage dps) = _tryDataPointStorage(dp);
        if (!found) {
            return (false, dps.dpData);
        }
        return (true, dps.dpData);
    }

    function _tryDiidData(DataPoint dp, bytes32 diid) internal view returns (bool success, DiidData storage) {
        (bool found, DataPointStorage storage dps) = _tryDataPointStorage(dp);
        if (!found) {
            return (false, dps.diidData[bytes32(0)]);
        }
        DiidData storage diidd = dps.diidData[diid];
        if (diidd.ids.length() == 0) {
            // Here we use length of ids array as a flag that there is no data for the diid
            return (false, diidd);
        }
        return (true, diidd);
    }

    function _dataPointStorage(DataPoint dp) private view returns (DataPointStorage storage) {
        DataPointStorage storage dps = dpStorages[dp];
        if (address(dps.dataIndexImplementation) == address(0)) {
            revert UninitializedDataPoint(dp);
        }
        return dpStorages[dp];
    }

    function _tryDataPointStorage(DataPoint dp) private view returns (bool success, DataPointStorage storage) {
        DataPointStorage storage dps = dpStorages[dp];
        if (address(dps.dataIndexImplementation) == address(0)) {
            return (false, dps);
        }
        return (true, dps);
    }
}
