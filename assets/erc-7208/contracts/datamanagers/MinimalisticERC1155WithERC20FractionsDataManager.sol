// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Arrays.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "../interfaces/IDataIndex.sol";
import "../interfaces/IDataObject.sol";
import "./MinimalisticERC20FractionDataManagerFactory.sol";
import "./MinimalisticERC20FractionDataManager.sol";

/**
 * Deployment process
 * 1. Allocate DataPoint via IDataPointRegistry.allocate()
 * 2. Deploy ERC1155WithERC20FractionsDataManager (or an extending contract)
 * 3. Grant Admin role on the DataPoint to the deployed contract
 */
contract MinimalisticERC1155WithERC20FractionsDataManager is IFractionTransferEventEmitter, IERC1155, IERC1155Errors, ERC165, Ownable {
    using Arrays for uint256[];

    error IncorrectId(uint256 id);
    event ERC20FractionDataManagerDeployed(uint256 id, address dm);

    string private _name;
    string private _symbol;
    string private _defaultURI = "";
    DataPoint internal immutable datapoint;
    IDataObject public immutable fungibleFractionsDO;
    IDataIndex public dataIndex;
    mapping(address account => mapping(address operator => bool)) private _operatorApprovals;
    mapping(uint256 id => address erc20dm) public fractionManagersById;
    mapping(address erc20dm => uint256 id) public fractionManagersByAddress;
    MinimalisticERC20FractionDataManagerFactory erc20FractionsDMFactory;

    modifier onlyMinter() {
        _checkMinter();
        _;
    }

    constructor(
        bytes32 _dp,
        address _dataIndex,
        address _fungibleFractionsDO,
        address _erc20FractionsDMFactory,
        string memory name_,
        string memory symbol_
    ) Ownable(msg.sender) {
        _name = name_;
        _symbol = symbol_;
        datapoint = DataPoint.wrap(_dp);
        dataIndex = IDataIndex(_dataIndex);
        fungibleFractionsDO = IDataObject(_fungibleFractionsDO);
        erc20FractionsDMFactory = MinimalisticERC20FractionDataManagerFactory(_erc20FractionsDMFactory);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC165) returns (bool) {
        return interfaceId == type(IERC1155).interfaceId || interfaceId == type(IERC1155MetadataURI).interfaceId || super.supportsInterface(interfaceId);
    }

    function setDefaultURI(string calldata defaultURI) external onlyOwner {
        _setDefaultURI(defaultURI);
    }

    function totalSupply() public view returns (uint256) {
        return abi.decode(fungibleFractionsDO.read(datapoint, IFungibleFractionsOperations.totalSupplyAll.selector, ""), (uint256));
    }

    function totalSupply(uint256 id) public view returns (uint256) {
        return abi.decode(fungibleFractionsDO.read(datapoint, IFungibleFractionsOperations.totalSupply.selector, abi.encode(id)), (uint256));
    }

    function balanceOf(address account, uint256 id) public view returns (uint256) {
        return abi.decode(fungibleFractionsDO.read(datapoint, IFungibleFractionsOperations.balanceOf.selector, abi.encode(account, id)), (uint256));
    }

    function balanceOfBatch(address[] memory accounts, uint256[] memory ids) public view returns (uint256[] memory) {
        return
            abi.decode(
                fungibleFractionsDO.read(datapoint, IFungibleFractionsOperations.balanceOfBatchAccounts.selector, abi.encode(accounts, ids)),
                (uint256[])
            );
    }

    function uri(uint256) public view virtual returns (string memory) {
        return _defaultURI;
    }

    function name() public view returns (string memory) {
        return _name;
    }
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev See {IERC1155-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) public virtual {
        _setApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @dev See {IERC1155-isApprovedForAll}.
     */
    function isApprovedForAll(address account, address operator) public view virtual returns (bool) {
        return _operatorApprovals[account][operator];
    }

    /**
     * @dev Approve `operator` to operate on all of `owner` tokens
     *
     * Emits an {ApprovalForAll} event.
     *
     * Requirements:
     *
     * - `operator` cannot be the zero address.
     */
    function _setApprovalForAll(address owner, address operator, bool approved) internal virtual {
        if (operator == address(0)) {
            revert ERC1155InvalidOperator(address(0));
        }
        _operatorApprovals[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }

    /**
     * @dev See {IERC1155-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes calldata data) public virtual {
        address sender = _msgSender();
        if (from != sender && !isApprovedForAll(from, sender)) {
            revert ERC1155MissingApprovalForAll(sender, from);
        }
        _safeTransferFrom(from, to, id, value, data);
    }

    /**
     * @dev See {IERC1155-safeBatchTransferFrom}.
     */
    function safeBatchTransferFrom(address from, address to, uint256[] calldata ids, uint256[] calldata values, bytes calldata data) external virtual {
        address sender = _msgSender();
        if (from != sender && !isApprovedForAll(from, sender)) {
            revert ERC1155MissingApprovalForAll(sender, from);
        }
        _safeBatchTransferFrom(from, to, ids, values, data);
    }

    /**
     * @dev Transfers a `value` tokens of token type `id` from `from` to `to`.
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `from` must have a balance of tokens of type `id` of at least `value` amount.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.
     */
    function _safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes memory data) internal {
        if (to == address(0)) {
            revert ERC1155InvalidReceiver(address(0));
        }
        if (from == address(0)) {
            revert ERC1155InvalidSender(address(0));
        }
        _updateWithAcceptanceCheck(from, to, id, value, data);
    }

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {_safeTransferFrom}.
     *
     * Emits a {TransferBatch} event.
     *
     * Requirements:
     *
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155BatchReceived} and return the
     * acceptance magic value.
     * - `ids` and `values` must have the same length.
     */
    function _safeBatchTransferFrom(address from, address to, uint256[] memory ids, uint256[] memory values, bytes memory data) internal {
        if (ids.length != values.length) {
            revert ERC1155InvalidArrayLength(ids.length, values.length);
            // DO NOT remove this check without refactoring ERC1155WithERC20FractionsDataManager._update() which relies on it!
        }

        if (to == address(0)) {
            revert ERC1155InvalidReceiver(address(0));
        }
        if (from == address(0)) {
            revert ERC1155InvalidSender(address(0));
        }
        if (ids.length == 1 && values.length == 1) {
            uint256 id = ids.unsafeMemoryAccess(0);
            uint256 value = values.unsafeMemoryAccess(0);
            _updateWithAcceptanceCheck(from, to, id, value, data);
        } else {
            _updateWithAcceptanceCheck(from, to, ids, values, data);
        }
    }

    /**
     * @dev Version of {_update} that performs the token acceptance check by calling
     * {IERC1155Receiver-onERC1155Received} or {IERC1155Receiver-onERC1155BatchReceived} on the receiver address if it
     * contains code (eg. is a smart contract at the moment of execution).
     *
     * IMPORTANT: Overriding this function is discouraged because it poses a reentrancy risk from the receiver. So any
     * update to the contract state after this function would break the check-effect-interaction pattern. Consider
     * overriding {_update} instead.
     */
    function _updateWithAcceptanceCheck(address from, address to, uint256 id, uint256 value, bytes memory data) internal virtual {
        _update(from, to, id, value);
        if (to != address(0)) {
            address operator = _msgSender();
            _doSafeTransferAcceptanceCheck(operator, from, to, id, value, data);
        }
    }

    /**
     * @dev Version of {_update} that performs the token acceptance check by calling
     * {IERC1155Receiver-onERC1155Received} or {IERC1155Receiver-onERC1155BatchReceived} on the receiver address if it
     * contains code (eg. is a smart contract at the moment of execution).
     *
     * IMPORTANT: Overriding this function is discouraged because it poses a reentrancy risk from the receiver. So any
     * update to the contract state after this function would break the check-effect-interaction pattern. Consider
     * overriding {_update} instead.
     */
    function _updateWithAcceptanceCheck(address from, address to, uint256[] memory ids, uint256[] memory values, bytes memory data) internal virtual {
        _update(from, to, ids, values);
        if (to != address(0)) {
            address operator = _msgSender();
            _doSafeBatchTransferAcceptanceCheck(operator, from, to, ids, values, data);
        }
    }

    /**
     * @dev Transfers a `value` amount of tokens of type `id` from `from` to `to`. Will mint (or burn) if `from`
     * (or `to`) is the zero address.
     *
     * Emits a {TransferSingle} event if the arrays contain one element, and {TransferBatch} otherwise.
     *
     * Requirements:
     *
     * - If `to` refers to a smart contract, it must implement either {IERC1155Receiver-onERC1155Received}
     *   or {IERC1155Receiver-onERC1155BatchReceived} and return the acceptance magic value.
     * - `ids` and `values` must have the same length.
     *
     * NOTE: The ERC-1155 acceptance check is not performed in this function. See {_updateWithAcceptanceCheck} instead.
     */
    function _updateInternal(address from, address to, uint256 id, uint256 value) internal virtual {
        address operator = _msgSender();

        _writeTransfer(from, to, id, value);

        emit TransferSingle(operator, from, to, id, value);
    }

    /**
     * @dev Transfers a `value` amount of tokens of type `id` from `from` to `to`. Will mint (or burn) if `from`
     * (or `to`) is the zero address.
     *
     * Emits a {TransferSingle} event if the arrays contain one element, and {TransferBatch} otherwise.
     *
     * Requirements:
     *
     * - If `to` refers to a smart contract, it must implement either {IERC1155Receiver-onERC1155Received}
     *   or {IERC1155Receiver-onERC1155BatchReceived} and return the acceptance magic value.
     * - `ids` and `values` must have the same length.
     *
     * NOTE: The ERC-1155 acceptance check is not performed in this function. See {_updateWithAcceptanceCheck} instead.
     * NOTE: Array length check is not performed in this function and must be performed in the caller
     */
    function _updateInternal(address from, address to, uint256[] memory ids, uint256[] memory values) internal virtual {
        address operator = _msgSender();

        _writeTransferBatch(from, to, ids, values);
        emit TransferBatch(operator, from, to, ids, values);
    }

    /**
     * @dev Performs an acceptance check by calling {IERC1155-onERC1155Received} on the `to` address
     * if it contains code at the moment of execution.
     */
    function _doSafeTransferAcceptanceCheck(address operator, address from, address to, uint256 id, uint256 value, bytes memory data) private {
        if (to.code.length > 0) {
            try IERC1155Receiver(to).onERC1155Received(operator, from, id, value, data) returns (bytes4 response) {
                if (response != IERC1155Receiver.onERC1155Received.selector) {
                    // Tokens rejected
                    revert ERC1155InvalidReceiver(to);
                }
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    // non-ERC1155Receiver implementer
                    revert ERC1155InvalidReceiver(to);
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        }
    }

    /**
     * @dev Performs a batch acceptance check by calling {IERC1155-onERC1155BatchReceived} on the `to` address
     * if it contains code at the moment of execution.
     */
    function _doSafeBatchTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) private {
        if (to.code.length > 0) {
            try IERC1155Receiver(to).onERC1155BatchReceived(operator, from, ids, values, data) returns (bytes4 response) {
                if (response != IERC1155Receiver.onERC1155BatchReceived.selector) {
                    // Tokens rejected
                    revert ERC1155InvalidReceiver(to);
                }
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    // non-ERC1155Receiver implementer
                    revert ERC1155InvalidReceiver(to);
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        }
    }

    function _setDefaultURI(string memory defaultURI) internal virtual {
        _defaultURI = defaultURI;
    }

    function _checkMinter() internal view {
        _checkOwner();
    }

    function _writeTransfer(address from, address to, uint256 id, uint256 value) internal virtual {
        if (from == address(0)) {
            dataIndex.write(address(fungibleFractionsDO), datapoint, IFungibleFractionsOperations.mint.selector, abi.encode(to, id, value));
        } else if (to == address(0)) {
            dataIndex.write(address(fungibleFractionsDO), datapoint, IFungibleFractionsOperations.burn.selector, abi.encode(from, id, value));
        } else {
            dataIndex.write(address(fungibleFractionsDO), datapoint, IFungibleFractionsOperations.transferFrom.selector, abi.encode(from, to, id, value));
        }
    }

    function _writeTransferBatch(address from, address to, uint256[] memory ids, uint256[] memory values) internal virtual {
        if (from == address(0)) {
            dataIndex.write(address(fungibleFractionsDO), datapoint, IFungibleFractionsOperations.batchMint.selector, abi.encode(to, ids, values));
        } else if (to == address(0)) {
            dataIndex.write(address(fungibleFractionsDO), datapoint, IFungibleFractionsOperations.batchBurn.selector, abi.encode(from, ids, values));
        } else {
            dataIndex.write(address(fungibleFractionsDO), datapoint, IFungibleFractionsOperations.batchTransferFrom.selector, abi.encode(from, to, ids, values));
        }
    }

    function mint(address to, uint256 id, uint256 value, bytes memory data) public virtual onlyMinter {
        _mint(to, id, value, data);
    }

    function batchMint(address, uint256[] memory, uint256[] memory, bytes memory) public pure {
        revert("Batch mint not supported"); // it will be very expensive anyway
    }

    function fractionTransferredNotify(address from, address to, uint256 value) external {
        uint256 id = fractionManagersByAddress[_msgSender()];
        if (id == 0) revert WrongTransferNotificationSource();
        emit TransferSingle(_msgSender(), from, to, id, value);
    }

    function _mint(address to, uint256 id, uint256 value, bytes memory data) internal virtual {
        if (id == 0) revert IncorrectId(id);
        _deployERC20DMIfNotDeployed(id, data);
        _updateWithAcceptanceCheck(address(0), to, id, value, data);
    }

    function _update(address from, address to, uint256 id, uint256 value) internal {
        _updateInternal(from, to, id, value);
        _erc20TransferNotify(id, from, to, value);
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal {
        _updateInternal(from, to, ids, values);
        for (uint256 i; i < ids.length; i++) {
            uint256 id = ids.unsafeMemoryAccess(i);
            uint256 value = ids.unsafeMemoryAccess(i); // We have an array length check in ERC1155Transfers._safeBatchTransferFrom()
            _erc20TransferNotify(id, from, to, value);
        }
    }

    function _deployERC20DMIfNotDeployed(uint256 id, bytes memory data) internal {
        if (fractionManagersById[id] != address(0)) return; // Already deployed
        (string memory name_, string memory symbol_) = _prepareNameAndSymbol(data, id);
        _deployERC20DM(id, name_, symbol_);
    }

    function _afterDeployERC20DM(address deployedDM) internal virtual {}

    function _prepareNameAndSymbol(bytes memory data, uint256 id) private view returns (string memory, string memory) {
        string memory name_;
        string memory symbol_;
        if (data.length != 0) {
            (name_, symbol_) = abi.decode(data, (string, string));
        } else {
            name_ = string.concat(name(), " ", Strings.toString(id));
            symbol_ = string.concat(symbol(), "-", Strings.toString(id));
        }
        return (name_, symbol_);
    }

    function _deployERC20DM(uint256 id, string memory name_, string memory symbol_) private {
        address erc20dm = erc20FractionsDMFactory.deploy(id);
        MinimalisticERC20FractionDataManager(erc20dm).initialize(
            DataPoint.unwrap(datapoint),
            address(dataIndex),
            address(fungibleFractionsDO),
            address(this),
            id,
            name_,
            symbol_
        );

        fractionManagersById[id] = erc20dm;
        fractionManagersByAddress[erc20dm] = id;

        dataIndex.allowDataManager(datapoint, erc20dm, true);

        _afterDeployERC20DM(erc20dm);

        emit ERC20FractionDataManagerDeployed(id, erc20dm);
    }

    function _erc20TransferNotify(uint256 id, address from, address to, uint256 value) private {
        IFractionTransferEventEmitter(fractionManagersById[id]).fractionTransferredNotify(from, to, value);
    }
}
