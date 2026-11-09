// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IERC165} from "./interfaces/IERC165.sol";
import {IAIFPSubjectSet} from "./interfaces/IAIFPPredicateVerifier.sol";

/// @title AIFPSubjectSet
/// @notice A minimal owner-managed roster of subject references for ALLOWLIST leaves.
contract AIFPSubjectSet is IAIFPSubjectSet, IERC165 {
    address public owner;
    mapping(bytes32 => bool) private _members;
    uint256 public size;

    event MemberAdded(bytes32 indexed subject);
    event MemberRemoved(bytes32 indexed subject);
    event OwnerChanged(address indexed previousOwner, address indexed newOwner);

    error NotOwner();

    constructor(address owner_) {
        owner = owner_;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IAIFPSubjectSet).interfaceId;
    }

    function add(bytes32 subject) external onlyOwner {
        if (!_members[subject]) {
            _members[subject] = true;
            size++;
            emit MemberAdded(subject);
        }
    }

    function remove(bytes32 subject) external onlyOwner {
        if (_members[subject]) {
            _members[subject] = false;
            size--;
            emit MemberRemoved(subject);
        }
    }

    function transferOwnership(address newOwner) external onlyOwner {
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    function contains(bytes32 subject) external view returns (bool) {
        return _members[subject];
    }
}
