// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.30;

import {IERC8167} from "./IERC8167.sol";
import {ProxyStorageBase} from "./ProxyStorageBase.sol";

address constant FUNCTION_NOT_FOUND = address(0);

contract Setup is ProxyStorageBase {
    error Unauthorized(address);
    address public immutable OWNER;

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function _checkOwner() internal view {
        require(msg.sender == OWNER, Unauthorized(msg.sender));
    }

    constructor(address owner) {
        OWNER = owner;
    }

    function install(bytes4 selector, address delegate) public onlyOwner {
        ProxyAdminStorage storage sudo = adminStorage();
        require(delegate != FUNCTION_NOT_FOUND);
        require(delegate.code.length > 0);
        require(sudo.selectorInfo[selector].delegate == FUNCTION_NOT_FOUND);
        sudo.selectorInfo[selector] = SelectorInfo({delegate: delegate, index: uint96(sudo.selectors.length)});
        sudo.selectors.push(selector);
        emit IERC8167.SetDelegate(selector, delegate);
    }
}

contract FullAdmin is Setup {
    constructor(address owner) Setup(owner) {}

    function uninstall(bytes4 selector) public onlyOwner {
        ProxyAdminStorage storage sudo = adminStorage();
        require(sudo.selectorInfo[selector].delegate != FUNCTION_NOT_FOUND);
        uint256 index = sudo.selectorInfo[selector].index;
        delete sudo.selectorInfo[selector];
        bytes4 last = sudo.selectors[sudo.selectors.length - 1];
        sudo.selectors[index] = last;
        sudo.selectors.pop();
        emit IERC8167.SetDelegate(selector, FUNCTION_NOT_FOUND);
    }

    function upgrade(bytes4 selector, address delegate) public onlyOwner {
        ProxyAdminStorage storage sudo = adminStorage();
        require(delegate != FUNCTION_NOT_FOUND);
        require(delegate.code.length > 0);
        require(sudo.selectorInfo[selector].delegate != FUNCTION_NOT_FOUND);
        sudo.selectorInfo[selector].delegate = delegate;
        emit IERC8167.SetDelegate(selector, delegate);
    }
}

contract ProxyStorageView is IERC8167, ProxyStorageBase {
    function selectors() external view override returns (bytes4[] memory allSelectors) {
        ProxyAdminStorage storage admin = adminStorage();
        allSelectors = new bytes4[](admin.selectors.length);
        for (uint256 i = 0; i < admin.selectors.length; i++) {
            allSelectors[i] = admin.selectors[i];
        }
    }

    function implementation(bytes4 selector) external view override returns (address) {
        ProxyAdminStorage storage admin = adminStorage();
        return admin.selectorInfo[selector].delegate;
    }
}

contract Proxy is ProxyStorageBase {
    constructor() {
        address installDelegate = address(new Setup(msg.sender));
        (bool success,) = installDelegate.delegatecall(
            abi.encodeWithSelector(Setup.install.selector, Setup.install.selector, installDelegate)
        );
        require(success);
    }

    fallback() external payable {
        address delegate = adminStorage().selectorInfo[msg.sig].delegate;
        require(delegate != FUNCTION_NOT_FOUND, IERC8167.FunctionNotFound(msg.sig));
        assembly ("memory-safe") {
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), delegate, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if success {
                return(0, returndatasize())
            }
            revert(0, returndatasize())
        }
    }
}
