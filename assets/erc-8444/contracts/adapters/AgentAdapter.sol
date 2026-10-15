// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IARDKindAdapter} from "../interfaces/IARDKindAdapter.sol";
import {ARDKinds} from "../libraries/ARDKinds.sol";
import {IAgentIdentityRegistry} from "./interfaces/IAgentIdentityRegistry.sol";

/// @title  Agent adapter — kind `agent` (subject) over address-anchored agent identities
/// @notice Anchor = (address, 0). Any address is a dormant identity, so `exists` is true for every
///         nonzero address with id 0, and the controller is the address itself: only an account can
///         register a record about itself. Backed = the identity registry reports ACTIVE. anchorHint =
///         the digest of the identity's self-declared document, if any.
contract AgentAdapter is IARDKindAdapter {
    bytes32 public constant KIND = ARDKinds.AGENT;

    /// @notice The agent identity registry consulted for liveness; address(0) = none on this chain.
    IAgentIdentityRegistry public immutable identityRegistry;

    constructor(address identityRegistry_) {
        identityRegistry = IAgentIdentityRegistry(identityRegistry_);
    }

    function kind() external pure override returns (bytes32) {
        return KIND;
    }

    function exists(address target, uint256 id) public pure override returns (bool) {
        return target != address(0) && id == 0;
    }

    function controllerOf(address target, uint256 id) external pure override returns (address) {
        return exists(target, id) ? target : address(0);
    }

    function backed(address target, uint256 id) external view override returns (bool) {
        if (!exists(target, id) || address(identityRegistry) == address(0)) return false;
        try identityRegistry.state(target) returns (IAgentIdentityRegistry.State s) {
            return s == IAgentIdentityRegistry.State.ACTIVE;
        } catch {
            return false;
        }
    }

    function anchorHint(address target, uint256 id) external view override returns (bytes32) {
        if (!exists(target, id) || address(identityRegistry) == address(0)) return bytes32(0);
        try identityRegistry.documentURI(target) returns (string memory, bytes32 digest) {
            return digest;
        } catch {
            return bytes32(0);
        }
    }
}
