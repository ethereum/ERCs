// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.17;

interface IDLT {
    event Transfer(address indexed sender, address indexed recipient, uint256 indexed mainId, uint256 subId, uint256 amount);
    event TransferBatch(address indexed sender, address indexed recipient, uint256[] mainIds, uint256[] subIds, uint256[] amounts);
    event Approval(address indexed owner, address indexed operator, uint256 mainId, uint256 subId, uint256 amount);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function setApprovalForAll(address operator, bool approved) external;
    function safeTransferFrom(address sender, address recipient, uint256 mainId, uint256 subId, uint256 amount, bytes calldata data) external returns (bool);
    function approve(address operator, uint256 mainId, uint256 subId, uint256 amount) external returns (bool);
    function subBalanceOf(address account, uint256 mainId, uint256 subId) external view returns (uint256);
    function balanceOfBatch(address[] calldata accounts, uint256[] calldata mainIds, uint256[] calldata subIds) external view returns (uint256[] calldata);
    function allowance(address owner, address operator, uint256 mainId, uint256 subId) external view returns (uint256);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

interface IDLTReceiver {
    function onDLTReceived(address operator, address from, uint256 mainId, uint256 subId, uint256 amount, bytes calldata data) external returns (bytes4);
    function onDLTBatchReceived(address operator, address from, uint256[] calldata mainIds, uint256[] calldata subIds, uint256[] calldata amounts, bytes calldata data) external returns (bytes4);
}

contract DLT is IDLT {
    mapping(uint256 => mapping(address => mapping(uint256 => uint256))) internal _balances;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => uint256)))) private _allowances;

    function approve(address spender, uint256 mainId, uint256 subId, uint256 amount) public virtual override returns (bool) {
        require(spender != msg.sender, "DLT: approval to current owner");
        _approve(msg.sender, spender, mainId, subId, amount);
        return true;
    }

    function setApprovalForAll(address operator, bool approved) public virtual override {
        require(msg.sender != operator, "DLT: approve to caller");
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function safeTransferFrom(address sender, address recipient, uint256 mainId, uint256 subId, uint256 amount, bytes calldata data) public virtual override returns (bool) {
        if (sender != msg.sender && !isApprovedForAll(sender, msg.sender)) {
            _spendAllowance(sender, msg.sender, mainId, subId, amount);
        }
        _transfer(sender, recipient, mainId, subId, amount);
        require(_checkOnDLTReceived(sender, recipient, mainId, subId, amount, data), "DLT: transfer to non DLTReceiver implementer");
        return true;
    }

    function subBalanceOf(address account, uint256 mainId, uint256 subId) public view virtual override returns (uint256) {
        return _balances[mainId][account][subId];
    }

    function balanceOfBatch(address[] calldata accounts, uint256[] calldata mainIds, uint256[] calldata subIds) public view returns (uint256[] memory) {
        require(accounts.length == mainIds.length && accounts.length == subIds.length, "DLT: length mismatch");
        uint256[] memory batchBalances = new uint256[](accounts.length);
        for (uint256 i = 0; i < accounts.length; ++i) {
            batchBalances[i] = subBalanceOf(accounts[i], mainIds[i], subIds[i]);
        }
        return batchBalances;
    }

    function allowance(address owner, address spender, uint256 mainId, uint256 subId) public view virtual override returns (uint256) {
        return _allowances[owner][spender][mainId][subId];
    }

    function isApprovedForAll(address owner, address operator) public view virtual override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function _transfer(address sender, address recipient, uint256 mainId, uint256 subId, uint256 amount) internal virtual {
        require(sender != address(0), "DLT: transfer from the zero address");
        require(recipient != address(0), "DLT: transfer to the zero address");
        require(_balances[mainId][sender][subId] >= amount, "DLT: insufficient balance for transfer");
        unchecked {
            _balances[mainId][sender][subId] -= amount;
        }
        _balances[mainId][recipient][subId] += amount;
        emit Transfer(sender, recipient, mainId, subId, amount);
    }

    function _mint(address account, uint256 mainId, uint256 subId, uint256 amount) internal virtual {
        require(account != address(0), "DLT: mint to the zero address");
        require(amount != 0, "DLT: mint zero amount");
        _balances[mainId][account][subId] += amount;
        emit Transfer(address(0), account, mainId, subId, amount);
    }

    function _burn(address account, uint256 mainId, uint256 subId, uint256 amount) internal virtual {
        require(account != address(0), "DLT: burn from the zero address");
        require(_balances[mainId][account][subId] >= amount, "DLT: insufficient balance");
        unchecked {
            _balances[mainId][account][subId] -= amount;
        }
        emit Transfer(account, address(0), mainId, subId, amount);
    }

    function _approve(address owner, address spender, uint256 mainId, uint256 subId, uint256 amount) internal virtual {
        require(owner != address(0), "DLT: approve from the zero address");
        require(spender != address(0), "DLT: approve to the zero address");
        _allowances[owner][spender][mainId][subId] = amount;
        emit Approval(owner, spender, mainId, subId, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 mainId, uint256 subId, uint256 amount) internal virtual {
        uint256 currentAllowance = _allowances[owner][spender][mainId][subId];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "DLT: insufficient allowance");
            unchecked {
                _approve(owner, spender, mainId, subId, currentAllowance - amount);
            }
        }
    }

    function _checkOnDLTReceived(address sender, address recipient, uint256 mainId, uint256 subId, uint256 amount, bytes memory data) private returns (bool) {
        if (recipient.code.length > 0) {
            try IDLTReceiver(recipient).onDLTReceived(msg.sender, sender, mainId, subId, amount, data) returns (bytes4 retval) {
                return retval == IDLTReceiver.onDLTReceived.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("DLT: transfer to non DLTReceiver implementer");
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }
}
