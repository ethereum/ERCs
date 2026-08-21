// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "./IERC8063.sol";

/// @title ERC8063 — Reference implementation of a membership token (Group)
/// @notice A standard ERC-20 token with optional membership introspection
/// @dev Any ERC-20 can be a Group; this reference adds the IERC8063 interface
contract ERC8063 is IERC8063 {
    string private _name;
    string private _symbol;
    uint8 private immutable _decimals;
    address private _owner;
    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    modifier onlyOwner() {
        require(msg.sender == _owner, "Not owner");
        _;
    }

    /// @param groupName Human-readable group name (ERC-20 name)
    /// @param groupSymbol Token symbol (ERC-20 symbol)
    /// @param tokenDecimals Number of decimals (typically 18)
    /// @param initialSupply Initial token supply (in smallest unit)
    constructor(
        string memory groupName, 
        string memory groupSymbol, 
        uint8 tokenDecimals,
        uint256 initialSupply
    ) {
        _name = groupName;
        _symbol = groupSymbol;
        _decimals = tokenDecimals;
        _owner = msg.sender;
        
        if (initialSupply > 0) {
            _balances[msg.sender] = initialSupply;
            _totalSupply = initialSupply;
            emit Transfer(address(0), msg.sender, initialSupply);
        }
    }

    // ============ ERC-165 ============

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == type(IERC8063).interfaceId ||
            interfaceId == 0x36372b07 || // ERC-20
            interfaceId == 0x01ffc9a7;   // ERC-165
    }

    // ============ ERC-20 ============

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        require(spender != address(0), "Zero address");
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "Insufficient allowance");
        unchecked {
            _allowances[from][msg.sender] = currentAllowance - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "Transfer from zero");
        require(to != address(0), "Transfer to zero");
        require(_balances[from] >= amount, "Insufficient balance");

        unchecked {
            _balances[from] -= amount;
        }
        _balances[to] += amount;

        emit Transfer(from, to, amount);
    }

    // ============ Minting/Burning (implementation-defined) ============

    /// @notice Mint new tokens (owner only in this reference implementation)
    function mint(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Mint to zero");
        _balances[to] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    /// @notice Burn tokens (owner can burn anyone's, users can burn their own)
    function burn(address from, uint256 amount) external {
        require(msg.sender == _owner || msg.sender == from, "Not authorized");
        require(_balances[from] >= amount, "Insufficient balance");
        
        unchecked {
            _balances[from] -= amount;
            _totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }

    // ============ IERC8063 ============

    /// @notice Returns true if account holds at least threshold tokens
    function isMember(address account, uint256 threshold) public view override returns (bool) {
        return _balances[account] >= threshold;
    }

    // ============ Ownership (optional helper) ============

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        _owner = newOwner;
    }
}
