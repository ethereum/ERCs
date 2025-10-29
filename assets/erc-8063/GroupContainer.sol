// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "./IERCGroup.sol";

/// @title GroupContainer — minimal reference implementation of IERCGroup
contract GroupContainer is IERCGroup {
    struct GroupData {
        address owner;
        string metadataURI;
        uint256 memberCount;
        mapping(address => bool) isMember;
        mapping(address => bool) pendingInvite;
        mapping(bytes32 => string) resources;
    }

    uint256 private _nextGroupId;
    mapping(uint256 => GroupData) private _groups;

    constructor() {
        _nextGroupId = 1;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERCGroup).interfaceId;
    }

    function createGroup(string calldata metadataURI) external override returns (uint256 groupId) {
        groupId = _nextGroupId++;
        GroupData storage g = _groups[groupId];
        g.owner = msg.sender;
        g.metadataURI = metadataURI;
        if (!g.isMember[msg.sender]) {
            g.isMember[msg.sender] = true;
            g.memberCount = 1;
        }
        emit GroupCreated(groupId, msg.sender, metadataURI);
    }

    function groupOwner(uint256 groupId) public view override returns (address) {
        return _groups[groupId].owner;
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

    function setResource(uint256 groupId, bytes32 key, string calldata value) external override {
        GroupData storage g = _groups[groupId];
        require(g.isMember[msg.sender] || msg.sender == g.owner, "Only member or owner");
        if (bytes(value).length == 0) {
            // delete by setting to empty string (idempotent)
            if (bytes(g.resources[key]).length != 0) {
                g.resources[key] = "";
            }
        } else {
            g.resources[key] = value;
        }
        emit ResourceUpdated(groupId, key, value, msg.sender);
    }

    function getResource(uint256 groupId, bytes32 key) external view override returns (string memory) {
        return _groups[groupId].resources[key];
    }
}


