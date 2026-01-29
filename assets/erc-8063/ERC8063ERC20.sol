// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "./IERC8063.sol";

interface IERC20Minimal {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title ERC8063ERC20 — ERC-8063 group with optional ERC-20 compatibility (decimals=0)
/// @notice Balances are constrained to 0 or 1. Transfers MUST be exactly 1.
contract ERC8063ERC20 is IERC8063, IERC20Minimal {
    address private immutable _owner;
    string private _name;
    string private _symbol;
    string private _metadataURI;
    uint256 private _memberCount;

    mapping(address => bool) private _isMember;
    mapping(address => mapping(address => uint256)) private _allowances; // only 0 or 1 is valid

    constructor(string memory groupName, string memory symbol_, string memory metadataURI) {
        _owner = msg.sender;
        _name = groupName;
        _symbol = symbol_;
        _metadataURI = metadataURI;
        _isMember[msg.sender] = true;
        _memberCount = 1;
        emit Transfer(address(0), msg.sender, 1);
        emit MemberAdded(msg.sender, msg.sender);
    }

    // IERC165
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC8063).interfaceId;
    }

    // IERC8063
    function owner() public view override returns (address) { return _owner; }
    function isMember(address account) public view override returns (bool) { return _isMember[account]; }
    function getMemberCount() public view override returns (uint256) { return _memberCount; }

    function addMember(address account) external override {
        require(msg.sender == _owner, "Only owner");
        require(account != address(0), "Zero address");
        require(!_isMember[account], "Already member");
        _isMember[account] = true;
        unchecked { _memberCount += 1; }
        emit MemberAdded(account, msg.sender);
        emit Transfer(address(0), account, 1);
    }

    function leaveGroup() external override {
        require(_isMember[msg.sender], "Not member");
        require(msg.sender != _owner, "Owner cannot leave");
        _isMember[msg.sender] = false;
        unchecked { _memberCount -= 1; }
        emit MemberLeft(msg.sender);
        emit Transfer(msg.sender, address(0), 1);
    }

    function transferMembership(address to) external override {
        require(_isMember[msg.sender], "Not member");
        require(msg.sender != _owner, "Owner cannot transfer");
        require(to != address(0), "Zero address");
        require(!_isMember[to], "Already member");
        _isMember[msg.sender] = false;
        _isMember[to] = true;
        emit MembershipTransferred(msg.sender, to);
        emit Transfer(msg.sender, to, 1);
    }

    function name() public view override(IERC20Minimal, IERC8063) returns (string memory) { return _name; }
    function symbol() public view override returns (string memory) { return _symbol; }
    function decimals() public pure override returns (uint8) { return 0; }

    // ERC-20 views
    function totalSupply() public view override returns (uint256) { return _memberCount; }
    function balanceOf(address account) public view override returns (uint256) { return _isMember[account] ? 1 : 0; }

    // ERC-20 actions (amount MUST be exactly 1)
    function transfer(address to, uint256 amount) external override returns (bool) {
        require(amount == 1, "amount must be 1");
        transferMembership(to);
        return true;
    }

    function allowance(address owner_, address spender) public view override returns (uint256) {
        uint256 a = _allowances[owner_][spender];
        return a > 0 ? 1 : 0;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        require(spender != address(0), "Zero spender");
        // Only 0 or 1 are meaningful; clamp to {0,1}
        _allowances[msg.sender][spender] = amount > 0 ? 1 : 0;
        emit Approval(msg.sender, spender, _allowances[msg.sender][spender]);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(amount == 1, "amount must be 1");
        require(_allowances[from][msg.sender] >= 1, "insufficient allowance");
        require(_isMember[from], "from not member");
        require(from != _owner, "Owner cannot transfer");
        require(to != address(0), "Zero address");
        require(!_isMember[to], "to already member");
        _allowances[from][msg.sender] = 0;
        _isMember[from] = false;
        _isMember[to] = true;
        emit Transfer(from, to, 1);
        emit MembershipTransferred(from, to);
        return true;
    }
}


