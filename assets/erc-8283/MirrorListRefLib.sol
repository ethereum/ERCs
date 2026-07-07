// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./IClearSigningRegistry.sol";

/// @title  MirrorListRefLib — Resolution helpers for IClearSigningRegistry.MirrorListRef
/// @notice Attach via 'using MirrorListRefLib for MirrorListRef' inside a contract that
///         imports 'IClearSigningRegistry'.
library MirrorListRefLib {
    /// @dev The 'mirrorListId' 'ref' resolves to, without touching storage: the content
    ///      hash of 'ref.uris' in the inline flow, or 'ref.id' directly in the reference
    ///      flow. Does not validate that a referenced id was ever actually published —
    ///      callers that need that guarantee should go through 'resolve' instead.
    function resolvedId(IClearSigningRegistry.MirrorListRef calldata ref) internal pure returns (bytes32) {
        if (ref.uris.length > 0) {
            return keccak256(abi.encode(ref.uris));
        }
        return ref.id;
    }

    /// @dev Dispatches 'ref' to whichever single flow it carries: 'publishInline' when
    ///      'ref.uris' is supplied, 'referenceExisting' otherwise.
    function resolve(
        IClearSigningRegistry.MirrorListRef calldata ref,
        mapping(bytes32 mirrorListId => string[]) storage mirrorLists
    ) internal returns (bytes32) {
        if (ref.uris.length > 0) {
            return publishInline(ref, mirrorLists);
        }
        return referenceExisting(ref, mirrorLists);
    }

    /// @dev Inline flow: publishes 'ref.uris' and returns its id. Reverts
    ///      'RedundantMirrorListId' if 'ref.id' is also set.
    function publishInline(
        IClearSigningRegistry.MirrorListRef calldata ref,
        mapping(bytes32 mirrorListId => string[]) storage mirrorLists
    ) internal returns (bytes32) {
        if (ref.id != bytes32(0)) {
            revert IClearSigningRegistry.RedundantMirrorListId();
        }
        return publish(ref.uris, mirrorLists);
    }

    /// @dev Reference flow: validates that 'ref.id' was already published and returns
    ///      it. Reverts 'EmptyMirrorListRef' when the ref carries neither an id nor
    ///      inline uris, and 'UnknownMirrorList' when the referenced id is unpublished.
    function referenceExisting(
        IClearSigningRegistry.MirrorListRef calldata ref,
        mapping(bytes32 mirrorListId => string[]) storage mirrorLists
    ) internal view returns (bytes32) {
        if (ref.id == bytes32(0)) {
            revert IClearSigningRegistry.EmptyMirrorListRef();
        }
        if (mirrorLists[ref.id].length == 0) {
            revert IClearSigningRegistry.UnknownMirrorList(ref.id);
        }
        return ref.id;
    }

    /// @dev Stores 'uris' keyed by its content hash. Idempotent: a list with identical
    ///      content is stored exactly once and emits no event on repeated publication.
    function publish(
        string[] calldata uris,
        mapping(bytes32 mirrorListId => string[]) storage mirrorLists
    ) internal returns (bytes32 mirrorListId) {
        if (uris.length == 0) {
            revert IClearSigningRegistry.EmptyMirrorList();
        }
        mirrorListId = keccak256(abi.encode(uris));
        string[] storage storedUris = mirrorLists[mirrorListId];
        if (storedUris.length == 0) {
            // Element-by-element copy: a whole-array 'storedUris = uris' assignment of
            // nested calldata arrays is only supported by the IR pipeline ('via-ir').
            for (uint256 uriIndex = 0; uriIndex < uris.length; uriIndex++) {
                storedUris.push(uris[uriIndex]);
            }
            emit IClearSigningRegistry.MirrorListPublished(mirrorListId);
        }
    }
}
