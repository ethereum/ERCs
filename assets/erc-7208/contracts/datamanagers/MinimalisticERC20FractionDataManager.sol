// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../interfaces/IDataIndex.sol";
import "../interfaces/IDataObject.sol";
import "../interfaces/IFungibleFractionsOperations.sol";
import "../interfaces/IFractionTransferEventEmitter.sol";

contract MinimalisticERC20FractionDataManager is IFractionTransferEventEmitter, IERC20, IERC20Errors, OwnableUpgradeable {
    uint8 private constant DECIMALS = 0;

    DataPoint internal datapoint;
    IDataObject public fungibleFractionsDO;
    IDataIndex public dataIndex;
    address public erc1155dm;
    uint256 public erc1155ID;

    string private _name;
    string private _symbol;

    mapping(address account => mapping(address spender => uint256)) private _allowances;

    modifier onlyTransferNotifier() {
        if (_msgSender() != erc1155dm) revert WrongTransferNotificationSource();
        _;
    }

    function initialize(
        bytes32 _datapoint,
        address _dataIndex,
        address _fungibleFractionsDO,
        address _erc1155dm,
        uint256 _erc1155ID,
        string memory name_,
        string memory symbol_
    ) external initializer {
        __Ownable_init_unchained(_msgSender());
        __MinimalisticERC20FractionDataManager_init_unchained(_datapoint, _dataIndex, _fungibleFractionsDO, _erc1155dm, _erc1155ID, name_, symbol_);
    }

    function __MinimalisticERC20FractionDataManager_init_unchained(
        bytes32 _datapoint,
        address _dataIndex,
        address _fungibleFractionsDO,
        address _erc1155dm,
        uint256 _erc1155ID,
        string memory name_,
        string memory symbol_
    ) internal onlyInitializing {
        datapoint = DataPoint.wrap(_datapoint);
        dataIndex = IDataIndex(_dataIndex);
        fungibleFractionsDO = IDataObject(_fungibleFractionsDO);
        erc1155dm = _erc1155dm;
        erc1155ID = _erc1155ID;
        _name = name_;
        _symbol = symbol_;
    }

    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function totalSupply() external view override returns (uint256) {
        return abi.decode(fungibleFractionsDO.read(datapoint, IFungibleFractionsOperations.totalSupply.selector, abi.encode(erc1155ID)), (uint256));
    }

    function balanceOf(address account) external view override returns (uint256) {
        return abi.decode(fungibleFractionsDO.read(datapoint, IFungibleFractionsOperations.balanceOf.selector, abi.encode(account, erc1155ID)), (uint256));
    }

    function fractionTransferredNotify(address from, address to, uint256 amount) external onlyTransferNotifier {
        emit Transfer(from, to, amount);
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 value) public returns (bool) {
        if (_msgSender() == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        _allowances[_msgSender()][spender] = value;
        emit Approval(_msgSender(), spender, value);
        return true;
    }

    function transfer(address to, uint256 amount) external virtual override returns (bool) {
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _beforeTokenTransfer(_msgSender(), to, amount);

        _writeTransfer(_msgSender(), to, amount);

        emit Transfer(_msgSender(), to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external virtual override returns (bool) {
        _spendAllowance(from, _msgSender(), amount);
        _beforeTokenTransfer(from, to, amount);

        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }

        _writeTransfer(from, to, amount);

        emit Transfer(from, to, amount);
        return true;
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, amount);
            }
            unchecked {
                _allowances[owner][spender] = currentAllowance - amount;
            }
        }
    }

    function _writeTransfer(address from, address to, uint256 amount) internal {
        if (from == address(0)) {
            dataIndex.write(address(fungibleFractionsDO), datapoint, IFungibleFractionsOperations.mint.selector, abi.encode(to, erc1155ID, amount));
        } else if (to == address(0)) {
            dataIndex.write(address(fungibleFractionsDO), datapoint, IFungibleFractionsOperations.burn.selector, abi.encode(from, erc1155ID, amount));
        } else {
            dataIndex.write(address(fungibleFractionsDO), datapoint, IFungibleFractionsOperations.transferFrom.selector, abi.encode(from, to, erc1155ID, amount));
        }
        IFractionTransferEventEmitter(erc1155dm).fractionTransferredNotify(from, to, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {}
}
