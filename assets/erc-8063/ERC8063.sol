// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "./IERC8063.sol";

/// @title ERC8063 — minimal reference implementation of IERC8063
contract ERC8063 is IERC8063 {
    address private immutable _owner;
    string private _name;
    string private _metadataURI;
    uint256 private _memberCount;
    
    mapping(address => bool) private _isMember;

    /// @notice Create a new group; caller becomes owner and initial member
    /// @param groupName Human-readable group name
    /// @param metadataURI Optional offchain metadata (e.g., JSON document)
    constructor(string memory groupName, string memory metadataURI) {
        _owner = msg.sender;
        _name = groupName;
        _metadataURI = metadataURI;
        _isMember[msg.sender] = true;
        _memberCount = 1;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC8063).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    function owner() public view override returns (address) {
        return _owner;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function isMember(address account) public view override returns (bool) {
        return _isMember[account];
    }

    function getMemberCount() external view override returns (uint256) {
        return _memberCount;
    }

    function addMember(address account) external override {
        require(msg.sender == _owner, "Only owner can add");
        require(account != address(0), "Zero address");
        require(!_isMember[account], "Already member");
        _isMember[account] = true;
        unchecked { _memberCount += 1; }
        emit MemberAdded(account, msg.sender);
    }

    function leaveGroup() external override {
        require(_isMember[msg.sender], "Not a member");
        require(msg.sender != _owner, "Owner cannot leave");
        _isMember[msg.sender] = false;
        unchecked { _memberCount -= 1; }
        emit MemberLeft(msg.sender);
    }

    function transferMembership(address to) external override {
        require(_isMember[msg.sender], "Not a member");
        require(msg.sender != _owner, "Owner cannot transfer");
        require(to != address(0), "Zero address");
        require(!_isMember[to], "Already a member");
        
        _isMember[msg.sender] = false;
        _isMember[to] = true;
        emit MembershipTransferred(msg.sender, to);
    }
}
