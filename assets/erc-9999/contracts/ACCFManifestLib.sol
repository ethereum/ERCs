// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ACCFTypes as T} from "./interfaces/ACCFTypes.sol";

/// @title ACCFManifestLib
/// @notice Manifest root, dependency closure and dependency digest of the reference unit registry, kept in a
///         linked library so that the registry stays within the contract size limit.
library ACCFManifestLib {
    /// @notice Root over the entries named by `bitmap`, in ascending order, with their commitments.
    function root(mapping(uint8 => bytes32) storage entries, uint256 bitmap) external view returns (bytes32) {
        (uint8[] memory names, bytes32[] memory hashes) = _collect(entries, bitmap);
        return keccak256(abi.encode(T.MANIFEST_DOMAIN, names, hashes));
    }

    /// @notice `mask` closed under the declared relations.
    function closure(mapping(uint8 => uint256) storage relations, uint256 mask) public view returns (uint256 closed) {
        closed = mask;
        uint256 frontier = mask & T.ENTRY_MASK;
        while (frontier != 0) {
            uint256 added;
            for (uint256 i = 0; frontier >> i != 0; ++i) {
                if ((frontier >> i) & 1 == 1) added |= relations[uint8(i)];
            }
            frontier = added & ~closed & T.ENTRY_MASK;
            closed |= added;
        }
    }

    /// @notice Digest of the current values of everything the closure of `mask` names. An absent entry
    ///         contributes zero, so a digest taken over it changes when the entry is committed; revisions make a
    ///         restored commitment a different state from the one it restores.
    function digest(
        mapping(uint8 => bytes32) storage entries,
        mapping(uint8 => uint32) storage revisions,
        mapping(uint8 => uint256) storage relations,
        T.Unit storage u,
        uint256 mask
    ) external view returns (bytes32) {
        uint256 closed = closure(relations, mask);
        (uint8[] memory names, bytes32[] memory values) = _collect(entries, closed & T.ENTRY_MASK);
        uint32[] memory revs = new uint32[](names.length);
        for (uint256 i = 0; i < names.length; ++i) {
            revs[i] = revisions[names[i]];
        }
        bytes32 boundary =
            closed & T.DEP_BOUNDARY != 0 ? keccak256(abi.encode(u.descriptorHash, u.boundaryVersion)) : bytes32(0);
        bytes32 control =
            closed & T.DEP_CONTROL != 0 ? keccak256(abi.encode(u.controller, u.controlVersion)) : bytes32(0);
        bytes32 authorization = closed & T.DEP_AUTHORIZATION != 0
            ? keccak256(abi.encode(u.controller, u.controlVersion, u.authorizationRevision))
            : bytes32(0);
        return keccak256(abi.encode(closed, values, revs, boundary, control, authorization));
    }

    function _collect(mapping(uint8 => bytes32) storage entries, uint256 bitmap)
        private
        view
        returns (uint8[] memory names, bytes32[] memory hashes)
    {
        uint256 count;
        for (uint256 m = bitmap; m != 0; m >>= 1) {
            count += m & 1;
        }
        names = new uint8[](count);
        hashes = new bytes32[](count);
        uint256 k;
        for (uint256 i = 0; bitmap >> i != 0; ++i) {
            if ((bitmap >> i) & 1 == 1) {
                names[k] = uint8(i);
                hashes[k] = entries[uint8(i)];
                ++k;
            }
        }
    }
}
