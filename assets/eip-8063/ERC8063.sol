// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "./IERC8063.sol";

/// @title ERC8063 — Reference implementation of a membership token (Group)
/// @notice ERC-20 token with threshold-based membership semantics
/// @dev Implements ERC-20, ERC-5679, and IERC8063
contract ERC8063 is IERC8063, IERC5679Ext20 {
    string private _name;
    string private _symbol;
    uint8 private immutable _decimals;
    address private immutable _admin;
    uint256 private _totalSupply;
    uint256 private _memberCount; // Tracks accounts with balance > 0

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @param groupName Human-readable group name (ERC-20 name)
    /// @param groupSymbol Token symbol (ERC-20 symbol)
    /// @param tokenDecimals Number of decimals (typically 18)
    constructor(string memory groupName, string memory groupSymbol, uint8 tokenDecimals) {
        _name = groupName;
        _symbol = groupSymbol;
        _decimals = tokenDecimals;
        _admin = msg.sender;
        
        // Deployer becomes initial member with 1 token (in smallest unit)
        uint256 initialAmount = 1 * 10**tokenDecimals;
        _balances[msg.sender] = initialAmount;
        _totalSupply = initialAmount;
        _memberCount = 1;
        emit Transfer(address(0), msg.sender, initialAmount);
    }

    // ============ ERC-165 ============

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == type(IERC8063).interfaceId ||
            interfaceId == 0x36372b07 || // ERC-20
            interfaceId == 0xd0017968 || // ERC-5679 for ERC-20
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

        bool fromWasMember = _balances[from] > 0;
        bool toWasMember = _balances[to] > 0;

        unchecked {
            _balances[from] -= amount;
        }
        _balances[to] += amount;

        // Update member count
        bool fromIsMember = _balances[from] > 0;
        bool toIsMember = _balances[to] > 0;
        
        if (fromWasMember && !fromIsMember) {
            _memberCount--;
        }
        if (!toWasMember && toIsMember) {
            _memberCount++;
        }

        emit Transfer(from, to, amount);
    }

    // ============ ERC-5679 (Mint/Burn) ============

    function mint(address to, uint256 amount, bytes calldata) external override {
        require(canMint(msg.sender), "Not authorized to mint");
        require(to != address(0), "Mint to zero");

        bool wasMember = _balances[to] > 0;
        
        _balances[to] += amount;
        _totalSupply += amount;

        if (!wasMember && _balances[to] > 0) {
            _memberCount++;
        }

        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount, bytes calldata) external override {
        require(canBurn(msg.sender, from), "Not authorized to burn");
        require(_balances[from] >= amount, "Insufficient balance");

        bool wasMember = _balances[from] > 0;

        unchecked {
            _balances[from] -= amount;
            _totalSupply -= amount;
        }

        if (wasMember && _balances[from] == 0) {
            _memberCount--;
        }

        emit Transfer(from, address(0), amount);
    }

    // ============ IERC8063 ============

    /// @notice Returns the admin (implementation-specific, not part of IERC8063)
    function admin() public view returns (address) {
        return _admin;
    }

    /// @notice Returns true if account holds at least threshold tokens
    function isMember(address account, uint256 threshold) public view override returns (bool) {
        return _balances[account] >= threshold;
    }

    /// @notice Admin can mint new membership tokens
    function canMint(address operator) public view override returns (bool) {
        return operator == _admin;
    }

    /// @notice Admin can burn anyone's tokens; members can burn their own
    function canBurn(address operator, address from) public view override returns (bool) {
        // Admin can burn anyone except themselves
        if (operator == _admin) {
            return from != _admin;
        }
        // Members can burn their own tokens (voluntary exit)
        return operator == from;
    }

    // ============ Optional Aliases ============

    /// @notice Returns count of addresses with balance > 0
    function getMemberCount() public view returns (uint256) {
        return _memberCount;
    }

    /// @notice Convenience: mint tokens to add a member
    function addMember(address account, uint256 amount) external {
        this.mint(account, amount, "");
    }

    /// @notice Convenience: burn own tokens to reduce membership level
    function leaveGroup(uint256 amount) external {
        this.burn(msg.sender, amount, "");
    }

    /// @notice Convenience: burn all own tokens to fully exit
    function leaveGroupFully() external {
        this.burn(msg.sender, _balances[msg.sender], "");
    }
}
