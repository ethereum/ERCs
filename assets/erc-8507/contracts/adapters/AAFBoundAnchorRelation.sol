// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IAAFRelationSource} from "../interfaces/IAAFRelationSource.sol";
import {SubjectRef, KIND_ACCOUNT, KIND_ENTRY} from "../interfaces/AAFTypes.sol";

/// @dev The view of an address-anchored identity registry this adapter reads.
interface IAnchorRegistry {
    struct Binding {
        address registry;
        uint256 agentId;
        uint64 boundAt;
    }

    function bindingOf(address anchor) external view returns (Binding memory);
    function anchorOf(address registry, uint256 agentId) external view returns (address);
}

/// @dev The two views of an agent identity registry the binding predicate rests on.
interface IAgentIdentity {
    function ownerOf(uint256 agentId) external view returns (address);
    function getAgentWallet(uint256 agentId) external view returns (address);
}

/// @title Relation source: the anchor bound to an agent identity
/// @notice Example of a related-object extension. The relation runs from an agent identity (a
/// registry entry, which may be listed) to the account that is bound to it as its anchor.
///
/// The relation holds only on evidence both sides produced: the account bound itself to the
/// identity, and the identity names the account as its owner or as its wallet. A statement by one
/// side alone establishes nothing here. In particular, an anchor that retires and names another
/// account as its successor does not make that account related to anything: the named account is
/// related only once it has bound itself to the identity.
///
/// An account is bound to at most one identity, so the enumeration of origins is complete.
contract AAFBoundAnchorRelation is IAAFRelationSource {
    bytes32 public constant RELATION_BOUND_ANCHOR = keccak256("aaf.relation.bound-anchor");

    IAnchorRegistry public immutable anchors;

    constructor(address anchors_) {
        anchors = IAnchorRegistry(anchors_);
    }

    function configHash() external view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, anchors, RELATION_BOUND_ANCHOR));
    }

    function originOf(bytes32 relationType, SubjectRef calldata subject, bytes calldata, uint256 index)
        external
        view
        returns (uint8 status, SubjectRef memory origin, uint64 since)
    {
        // What this source does not know it does not answer.
        if (relationType != RELATION_BOUND_ANCHOR) return (0, origin, 0);
        if (subject.kind != KIND_ACCOUNT) return (2, origin, 0);
        if (subject.chainId != block.chainid || subject.namespace != address(0)) return (0, origin, 0);
        if (index != 0) return (2, origin, 0);

        address account = address(uint160(uint256(subject.id)));
        try anchors.bindingOf(account) returns (IAnchorRegistry.Binding memory b) {
            if (b.registry == address(0)) return (2, origin, 0);
            // The identity's side of the relation, read from the identity registry itself.
            try IAgentIdentity(b.registry).ownerOf(b.agentId) returns (address owner) {
                bool named = owner == account;
                if (!named) {
                    try IAgentIdentity(b.registry).getAgentWallet(b.agentId) returns (address wallet) {
                        named = wallet == account;
                    } catch {
                        return (0, origin, 0);
                    }
                }
                if (!named) return (2, origin, 0);
            } catch {
                return (0, origin, 0);
            }
            origin = SubjectRef({kind: KIND_ENTRY, chainId: block.chainid, namespace: b.registry, id: bytes32(b.agentId)});
            return (1, origin, b.boundAt);
        } catch {
            return (0, origin, 0);
        }
    }
}
