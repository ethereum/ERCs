// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import "./IERC20.sol";

contract ERC20 is IERC20 {
    struct IRS {
        address payer;
        address receiver;
        address oracleContractForBenchmark;
        uint256 spread;
        uint256 swapRate;
        uint8 ratesDecimals;
        uint256 benchmark;
        uint256 notionalAmount;
        address assetContract;
        uint256 paymentFrequency;
        uint256 startingDate;
        uint256 maturityDate;
        uint256[] paymentDates;
    }

    mapping(address => bool) _hasAgreed;
    mapping(address => uint256) internal _balanceOf;
    mapping(address => mapping(address => uint256)) internal _allowances;

    IRS irs;

    string private _name;
    string private _symbol;
    string irsSymbol;
    bool _isActive;
    uint256 paymentCount;

    uint256 internal _totalSupply;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balanceOf[account];
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = msg.sender;
        _transfer(owner, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = msg.sender;
        _approve(owner, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = msg.sender;
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        address owner = msg.sender;
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        address owner = msg.sender;
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= subtractedValue, "ERC20: INSUFFICIENT_BALANCE");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(from != address(0), "ERC20: ZERO_ADDRESS_FROM");
        require(to != address(0), "ERC20: ZERO_ADDRESS_TO");

        _beforeTokenTransfer(from, to, amount);

        uint256 balance = _balanceOf[from];
        require(balance > 0 && balance == amount, "ERC20: INVALID_BALANCE");
        unchecked {
            _balanceOf[from] = balance - amount;
            _balanceOf[to] += amount;
        }

        if(from == irs.payer) {
            irs.payer = to;
            _hasAgreed[to] = true;
        }

        if(from == irs.receiver) {
            irs.receiver = to;
            _hasAgreed[to] = true;
        }

        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
    }

    function mint(address account, uint256 amount) public virtual returns (bool) {
        require(account != address(0), "ERC20: ZERO_ADDRESS_TO");
        require(amount != 0, "ERC20: INVALID_AMOUNT");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        unchecked {
            _balanceOf[account] += amount;
        }
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);

        return true;
    }

    function burn(address account, uint256 amount) public virtual returns (bool) {
        require(account != address(0), "ERC20: BURN_FROM_ZERO_ADDRESS");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balanceOf[account];
        require(accountBalance >= amount, "ERC20: AMOUNT_EXCEED_BALANCE");
        unchecked {
            _balanceOf[account] = accountBalance - amount;
            _totalSupply -= amount;
        }

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);

        return true;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: ZERO_ADDRESS_OWNER");
        require(spender != address(0), "ERC20: ZERO_ADDRESS_SPENDER");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: INSUFFICIENT_ALLOWANCE");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}
