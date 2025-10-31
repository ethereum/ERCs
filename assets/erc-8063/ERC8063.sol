// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "./IERC8063.sol";

/// @title ERC8063 — minimal reference implementation of IERC8063
contract ERC8063 is IERC8063 {
    struct GroupData {
        address owner;
        string name;
        string metadataURI;
        uint256 memberCount;
        mapping(address => bool) isMember;
        mapping(address => bool) pendingInvite;
    }

    uint256 private _nextGroupId;
    mapping(uint256 => GroupData) private _groups;

    constructor() {
        _nextGroupId = 1;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC8063).interfaceId;
    }

    function createGroup(string calldata name, string calldata metadataURI) external override returns (uint256 groupId) {
        groupId = _nextGroupId++;
        GroupData storage g = _groups[groupId];
        g.owner = msg.sender;
        g.name = name;
        g.metadataURI = metadataURI;
        if (!g.isMember[msg.sender]) {
            g.isMember[msg.sender] = true;
            g.memberCount = 1;
        }
        emit GroupCreated(groupId, msg.sender, name, metadataURI);
    }

    function groupOwner(uint256 groupId) public view override returns (address) {
        return _groups[groupId].owner;
    }

    function groupName(uint256 groupId) public view override returns (string memory) {
        return _groups[groupId].name;
    }

    function isMember(uint256 groupId, address account) public view override returns (bool) {
        return _groups[groupId].isMember[account];
    }

    function getMemberCount(uint256 groupId) external view override returns (uint256) {
        return _groups[groupId].memberCount;
    }

    function inviteMember(uint256 groupId, address account) external override {
        GroupData storage g = _groups[groupId];
        require(msg.sender == g.owner, "Only owner can invite");
        require(account != address(0), "Zero address");
        require(!g.isMember[account], "Already member");
        require(!g.pendingInvite[account], "Already invited");
        g.pendingInvite[account] = true;
        emit MemberInvited(groupId, msg.sender, account);
    }

    function acceptInvite(uint256 groupId) external override {
        GroupData storage g = _groups[groupId];
        require(g.pendingInvite[msg.sender], "No invite");
        require(!g.isMember[msg.sender], "Already member");
        g.pendingInvite[msg.sender] = false;
        g.isMember[msg.sender] = true;
        unchecked { g.memberCount += 1; }
        emit MemberJoined(groupId, msg.sender);
    }

    function removeMember(uint256 groupId, address account) external override {
        GroupData storage g = _groups[groupId];
        require(msg.sender == g.owner, "Only owner can remove");
        require(account != g.owner, "Cannot remove owner");
        require(g.isMember[account], "Not a member");
        g.isMember[account] = false;
        unchecked { g.memberCount -= 1; }
        emit MemberRemoved(groupId, account, msg.sender);
    }
}


