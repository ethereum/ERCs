// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IARDKindAdapter} from "../interfaces/IARDKindAdapter.sol";
import {IERC165} from "../interfaces/IERC165.sol";
import {ARDKinds} from "../libraries/ARDKinds.sol";
import {ITaskTenderKernel} from "./interfaces/ITaskTenderKernel.sol";
import {ITaskBindingView} from "./interfaces/ITaskBindingView.sol";
import {IERC721View} from "./interfaces/IERC721View.sol";

/// @title  Task adapter — kind `task` (tender, demand side) over token-bound task tender tokens
/// @notice Anchor = (token contract, token id). The target MUST declare the tender kernel interface
///         through ERC-165. Controller = the current ERC-721 owner (the demander). Backed = the tender
///         is live: not cancelled, escrow balance above zero, and `settleBy` (when set) not passed.
///         anchorHint = the task hash, compared by resolvers with `value:provenance.packageDigest`.
contract TaskAdapter is IARDKindAdapter {
    bytes32 public constant KIND = ARDKinds.TASK;
    bytes4 public constant TENDER_INTERFACE_ID = type(ITaskTenderKernel).interfaceId;

    function kind() external pure override returns (bytes32) {
        return KIND;
    }

    function exists(address target, uint256 id) public view override returns (bool) {
        if (target.code.length == 0) return false;
        try IERC165(target).supportsInterface(TENDER_INTERFACE_ID) returns (bool ok) {
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
        if (!exists(target, id)) return false;
        ITaskTenderKernel t = ITaskTenderKernel(target);
        try t.isTenderCancelled(id) returns (bool cancelled) {
            if (cancelled) return false;
        } catch {
            return false;
        }
        try t.escrowBalanceOf(id) returns (uint256 bal) {
            if (bal == 0) return false;
        } catch {
            return false;
        }
        try t.tenderTermsOf(id) returns (ITaskTenderKernel.TenderTerms memory terms) {
            if (terms.settleBy != 0 && terms.settleBy <= block.timestamp) return false;
        } catch {
            return false;
        }
        return true;
    }

    function anchorHint(address target, uint256 id) external view override returns (bytes32) {
        if (!exists(target, id)) return bytes32(0);
        try ITaskBindingView(target).taskOf(id) returns (ITaskBindingView.TaskBinding memory b) {
            return b.taskHash;
        } catch {
            return bytes32(0);
        }
    }
}
