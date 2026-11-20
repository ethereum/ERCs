// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

/// @notice How a published case declares the binding chain the enforcer should resolve against.
///
/// @dev The four shapes are distinct facts and the earlier harness collapsed all of them into
///      "register the genesis binding". That is why case 12 passed: the runner never presented the
///      unavailable chain, so the enforcer was never asked the question the case exists to ask.
enum ChainShape {
    Default, // the case declares no `bindings`; the file's top-level chain governs
    Unavailable, // `bindings: null` — the consumer could not fetch the chain at all
    Empty, // `bindings: []` — the chain was fetched and this agent has none
    Explicit // `bindings: [...]` — resolve against exactly these
}

struct VectorBinding {
    string name;
    bytes pqPubkey;
    bool anchored; // false when `binding_anchor_time` is null
    uint64 anchorTime;
    bool hasActivatedAt;
    uint64 activatedAt;
    bool hasRevokedAt;
    uint64 revokedAt;
}

/// @notice Reads the chain declaration for one published case, without flattening the four shapes.
library VectorChain {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @dev Foundry reports the shapes differently and all four are reachable:
    ///      absent -> keyExistsJson false; `null` -> 32 bytes; `[]` -> 64 bytes; a list -> more.
    function shapeOf(string memory json, uint256 i) internal view returns (ChainShape) {
        string memory p = path(i);
        if (!vm.keyExistsJson(json, p)) return ChainShape.Default;
        uint256 len = vm.parseJson(json, p).length;
        if (len <= 32) return ChainShape.Unavailable;
        if (len <= 64) return ChainShape.Empty;
        return ChainShape.Explicit;
    }

    function path(uint256 i) internal pure returns (string memory) {
        return string.concat(".cases[", vm.toString(i), "].bindings");
    }

    /// @dev `name` is the only member every binding carries; `binding_anchor_time` is nullable.
    function countOf(string memory json, uint256 i) internal view returns (uint256 n) {
        while (vm.keyExistsJson(json, string.concat(path(i), "[", vm.toString(n), "].name"))) {
            n++;
        }
    }

    function readAt(string memory json, string memory base) internal view returns (VectorBinding memory b) {
        b.name = vm.parseJsonString(json, string.concat(base, ".name"));
        b.pqPubkey = bytes(vm.parseJsonString(json, string.concat(base, ".pq_pubkey")));

        // A null `binding_anchor_time` is a real published state: a key with no immutable anchor.
        // Foundry decodes both a JSON number and a JSON null to a 32-byte word, so presence is not
        // the discriminator and the value is: null decodes to zero. No vector uses a real anchor
        // time of 0, and the enforcer already treats 0 as "not anchored", so the collision is
        // consistent rather than lossy.
        string memory at = string.concat(base, ".binding_anchor_time");
        if (vm.keyExistsJson(json, at)) {
            uint256 v = uint256(bytes32(vm.parseJson(json, at)));
            b.anchored = v != 0;
            b.anchorTime = uint64(v);
        }

        string memory act = string.concat(base, ".activated_at");
        if (vm.keyExistsJson(json, act)) {
            b.hasActivatedAt = true;
            b.activatedAt = uint64(vm.parseJsonUint(json, act));
        }

        string memory rev = string.concat(base, ".revoked_at");
        if (vm.keyExistsJson(json, rev)) {
            b.hasRevokedAt = true;
            b.revokedAt = uint64(vm.parseJsonUint(json, rev));
        }
    }
}
