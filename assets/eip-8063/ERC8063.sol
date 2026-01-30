// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "./IERC8063.sol";

/// @title ERC8063 — Reference implementation of a membership token (Group)
/// @notice ERC-20 token with balance capped at 1, representing group membership
/// @dev Implements ERC-20, ERC-5679, and IERC8063 with optional aliases
contract ERC8063 is IERC20, IERC5679Ext20, IERC8063, IERC8063Aliases {
    string private _name;
    string private _symbol;
    address private immutable _admin;
    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    /// @notice Emitted on membership changes (standard ERC-20 Transfer)
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @param groupName Human-readable group name (ERC-20 name)
    /// @param groupSymbol Token symbol (ERC-20 symbol)
    constructor(string memory groupName, string memory groupSymbol) {
        _name = groupName;
        _symbol = groupSymbol;
        _admin = msg.sender;
        
        // Deployer becomes initial member
        _balances[msg.sender] = 1;
        _totalSupply = 1;
        emit Transfer(address(0), msg.sender, 1);
    }

    // ============ ERC-165 ============

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IERC8063).interfaceId ||
            interfaceId == 0x36372b07 || // ERC-20
            interfaceId == 0xd0017968;   // ERC-5679 for ERC-20
    }

    // ============ ERC-20 ============

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return 0;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        require(amount == 1, "Amount must be 1");
        require(_balances[msg.sender] == 1, "Not a member");
        require(_balances[to] == 0, "Recipient already a member");
        require(to != address(0), "Zero address");

        _balances[msg.sender] = 0;
        _balances[to] = 1;
        emit Transfer(msg.sender, to, 1);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        require(spender != address(0), "Zero address");
        _allowances[msg.sender][spender] = amount > 0 ? 1 : 0;
        emit Approval(msg.sender, spender, _allowances[msg.sender][spender]);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        require(amount == 1, "Amount must be 1");
        require(_balances[from] == 1, "From not a member");
        require(_balances[to] == 0, "To already a member");
        require(to != address(0), "Zero address");
        require(_allowances[from][msg.sender] >= 1, "Insufficient allowance");

        _allowances[from][msg.sender] = 0;
        _balances[from] = 0;
        _balances[to] = 1;
        emit Transfer(from, to, 1);
        return true;
    }

    // ============ ERC-5679 (Mint/Burn) ============

    function mint(address to, uint256 amount, bytes calldata) external override {
        require(amount == 1, "Amount must be 1");
        require(canMint(msg.sender), "Not authorized to mint");
        require(to != address(0), "Zero address");
        require(_balances[to] == 0, "Already a member");

        _balances[to] = 1;
        unchecked { _totalSupply += 1; }
        emit Transfer(address(0), to, 1);
    }

    function burn(address from, uint256 amount, bytes calldata) external override {
        require(amount == 1, "Amount must be 1");
        require(canBurn(msg.sender, from), "Not authorized to burn");
        require(_balances[from] == 1, "Not a member");

        _balances[from] = 0;
        unchecked { _totalSupply -= 1; }
        emit Transfer(from, address(0), 1);
    }

    // ============ IERC8063 (Access Control Introspection) ============

    /// @notice Admin can mint new memberships
    function canMint(address operator) public view override returns (bool) {
        return operator == _admin;
    }

    /// @notice Admin can burn anyone (except themselves); members can burn themselves
    function canBurn(address operator, address from) public view override returns (bool) {
        // Admin can remove anyone except themselves
        if (operator == _admin) {
            return from != _admin;
        }
        // Members can remove themselves (voluntary exit)
        return operator == from && _balances[from] == 1;
    }

    // ============ IERC8063Aliases (Convenience Functions) ============

    /// @notice Returns the admin (not part of IERC8063, implementation-specific)
    function admin() public view returns (address) {
        return _admin;
    }

    function isMember(address account) public view override returns (bool) {
        return _balances[account] >= 1;
    }

    function getMemberCount() public view override returns (uint256) {
        return _totalSupply;
    }

    function addMember(address account) external override {
        this.mint(account, 1, "");
    }

    function removeMember(address account) external override {
        this.burn(account, 1, "");
    }

    function leaveGroup() external override {
        this.burn(msg.sender, 1, "");
    }

    function transferMembership(address to) external override {
        transfer(to, 1);
    }
}
