// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IARDKindAdapter} from "../interfaces/IARDKindAdapter.sol";
import {IERC165} from "../interfaces/IERC165.sol";
import {ARDKinds} from "../libraries/ARDKinds.sol";
import {ISkillTokenKernel} from "./interfaces/ISkillTokenKernel.sol";
import {IERC721View} from "./interfaces/IERC721View.sol";

/// @title  Skill adapter — kind `skill` (offer, supply side) over token-bound executable skill tokens
/// @notice Anchor = (token contract, token id). The target MUST declare the skill kernel interface
///         through ERC-165. Controller = the current ERC-721 owner (the seller), not the update
///         authority (the publisher): a value record is an offer, and offers belong to holders.
///         Backed = the token exists with a nonzero package hash; anchorHint = that package hash,
///         which resolvers compare with `value:provenance.packageDigest`.
contract SkillAdapter is IARDKindAdapter {
    bytes32 public constant KIND = ARDKinds.SKILL;
    bytes4 public constant SKILL_INTERFACE_ID = type(ISkillTokenKernel).interfaceId;

    function kind() external pure override returns (bytes32) {
        return KIND;
    }

    function exists(address target, uint256 id) public view override returns (bool) {
        if (target.code.length == 0) return false;
        try IERC165(target).supportsInterface(SKILL_INTERFACE_ID) returns (bool ok) {
            if (!ok) return false;
        } catch {
            return false;
        }
        try IERC721View(target).ownerOf(id) returns (address o) {
            return o != address(0);
        } catch {
            return false;
        }
    }

    function controllerOf(address target, uint256 id) external view override returns (address) {
        if (!exists(target, id)) return address(0);
        return IERC721View(target).ownerOf(id);
    }

    function backed(address target, uint256 id) external view override returns (bool) {
        return anchorHint(target, id) != bytes32(0);
    }

    function anchorHint(address target, uint256 id) public view override returns (bytes32) {
        if (!exists(target, id)) return bytes32(0);
        try ISkillTokenKernel(target).skillOf(id) returns (ISkillTokenKernel.SkillBinding memory b) {
            return b.packageHash;
        } catch {
            return bytes32(0);
        }
    }
}
