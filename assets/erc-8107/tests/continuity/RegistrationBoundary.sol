// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ITrustRegistry, TrustLevel} from "../../contracts/ITrustRegistry.sol";

interface IBaseRegistrarEvents {
    event NameRegistered(uint256 indexed id, address indexed owner, uint256 expires);
    event NameRenewed(uint256 indexed id, uint256 expires);
}

interface INameWrapperEvents {
    event NameWrapped(bytes32 indexed node, bytes name, address owner, uint32 fuses, uint64 expiry);
}

/// @title Registration-boundary continuity policy (coordinator side, non-normative)
/// @notice Reference for the coordinator check under ERC-8107 "Wrapped Name Lifecycle".
///         An attestation stays eligible only while no name it involves, as trustor or
///         trustee, has been registered again since the attestation's `TrustSet` event.
///         A `.eth` second-level name is registered again on a BaseRegistrar
///         `NameRegistered` for its label; `NameRenewed` never moves the boundary. A name
///         below one is registered again whenever its second-level ancestor is, and on a
///         NameWrapper `NameWrapped` for the name or for an ancestor of it below the
///         second-level name. Names outside `.eth` are not checked.
///
///         This checks REGISTRATION continuity, not CONTROLLER continuity: a transfer
///         within one registration, or a parent reassigning a subname that still has a
///         holder, emits neither event and leaves attestations eligible. It is applied in addition to `verifyPath`, whose verdict it never
///         widens, and it fails closed (`Unknown`) whenever the evidence it needs is
///         missing or inconsistent. It does not apply the liveness check for a wrapped
///         trustor under "Wrapped Name Lifecycle", which reads the trustor's controller at
///         the decision; a coordinator applies that check as well.
///
///         Inputs are what a coordinator holds off-chain: logs from `eth_getLogs` for the
///         registry, the BaseRegistrar and the NameWrapper, a block window the caller
///         asserts is complete for all three emitters, and the name behind each path node. The function is `view`
///         only because it reads the stored records to apply scope fallback.
library RegistrationBoundary {
    /// namehash("eth")
    bytes32 internal constant ETH_NODE = 0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae;

    struct Log {
        address emitter;
        bytes32[] topics;
        bytes data;
        uint64 blockNumber;
        uint32 txIndex;
        uint32 logIndex;
    }

    /// `logs` MUST hold every log the registry, the BaseRegistrar and the NameWrapper
    /// emitted in [fromBlock, toBlock], ordered by (blockNumber, txIndex, logIndex)
    struct History {
        uint64 fromBlock;
        uint64 toBlock;
        Log[] logs;
    }

    /// The name behind a node, label by label from the node up to the root, so that
    /// node == namehash(labels): "sub.alice.eth" is ["sub", "alice", "eth"]
    struct NameProof {
        bool known;
        string[] labels;
    }

    enum Verdict {
        Eligible,
        Ineligible,
        Unknown
    }

    enum Reason {
        None,
        HistoryBehindHead,
        HistoryUnordered,
        NoNameProof,
        NameProofMismatch,
        NotEndorsed,
        NoTrustSet,
        RecordMismatch,
        ReRegistered,
        ReWrapped
    }

    struct Result {
        Verdict verdict;
        Reason reason;
        uint256 edge; // index i of the edge nodes[i] -> nodes[i + 1]
        bytes32 node; // the node the reason concerns, where there is one
    }

    struct Query {
        ITrustRegistry registry;
        address baseRegistrar;
        address nameWrapper; // zero where the network has no NameWrapper
        bytes32[] nodes;
        bytes32 scope;
        NameProof[] proofs; // one per node
        uint64 head; // the block the coordinator decides at; the history must reach it
    }

    function evaluate(
        ITrustRegistry registry,
        address baseRegistrar,
        address nameWrapper,
        bytes32[] memory nodes,
        bytes32 scope,
        NameProof[] memory proofs,
        History memory h,
        uint64 head
    ) internal view returns (Result memory) {
        return evaluate(Query(registry, baseRegistrar, nameWrapper, nodes, scope, proofs, head), h);
    }

    function evaluate(Query memory q, History memory h) internal view returns (Result memory r) {
        if (h.toBlock < q.head) return _unknown(Reason.HistoryBehindHead, 0, bytes32(0));
        if (!_ordered(h)) return _unknown(Reason.HistoryUnordered, 0, bytes32(0));
        if (q.proofs.length != q.nodes.length) return _unknown(Reason.NoNameProof, 0, bytes32(0));

        // For each node under .eth: the BaseRegistrar token id of its 2LD (itself or an
        // ancestor), and the nodes from it up to, not including, the 2LD. A node whose
        // name cannot be verified fails closed: without it the coordinator cannot tell
        // whether the rule applies
        bool[] memory underEth = new bool[](q.nodes.length);
        uint256[] memory tokenId = new uint256[](q.nodes.length);
        bytes32[][] memory below2LD = new bytes32[][](q.nodes.length);
        for (uint256 i = 0; i < q.nodes.length; i++) {
            if (!q.proofs[i].known) return _unknown(Reason.NoNameProof, i, q.nodes[i]);
            bool ok;
            (ok, underEth[i], tokenId[i], below2LD[i]) = _name(q.proofs[i].labels, q.nodes[i]);
            if (!ok) return _unknown(Reason.NameProofMismatch, i, q.nodes[i]);
        }

        for (uint256 i = 0; i + 1 < q.nodes.length; i++) {
            uint256 at;
            (r, at) = _edgeRecord(q, h, i);
            if (r.verdict != Verdict.Eligible) return r;
            for (uint256 n = i; n <= i + 1; n++) {
                // trustor, then trustee
                if (!underEth[n]) continue;
                if (_registeredAfter(h, q.baseRegistrar, tokenId[n], at)) {
                    return Result(Verdict.Ineligible, Reason.ReRegistered, i, q.nodes[n]);
                }
                for (uint256 k = 0; k < below2LD[n].length; k++) {
                    if (_wrappedAfter(h, q.nameWrapper, below2LD[n][k], at)) {
                        return Result(Verdict.Ineligible, Reason.ReWrapped, i, q.nodes[n]);
                    }
                }
            }
        }
        return Result(Verdict.Eligible, Reason.None, 0, bytes32(0));
    }

    /// Locates the TrustSet that wrote the record carrying edge i, and checks that it is
    /// the stored record
    function _edgeRecord(Query memory q, History memory h, uint256 i) private view returns (Result memory, uint256) {
        bytes32 from = q.nodes[i];
        bytes32 to = q.nodes[i + 1];
        (bytes32 eff, TrustLevel level, uint64 expiry) = _effective(q.registry, from, to, q.scope);
        if (level != TrustLevel.Marginal && level != TrustLevel.Full) {
            return (Result(Verdict.Ineligible, Reason.NotEndorsed, i, to), 0);
        }
        (bool found, uint256 at, TrustLevel loggedLevel, uint64 loggedExpiry) =
            _lastTrustSet(h, address(q.registry), from, to, eff);
        if (!found) return (_unknown(Reason.NoTrustSet, i, to), 0);
        // In a complete history the newest TrustSet for the key is the stored record
        if (loggedLevel != level || loggedExpiry != expiry) return (_unknown(Reason.RecordMismatch, i, to), 0);
        return (Result(Verdict.Eligible, Reason.None, i, bytes32(0)), at);
    }

    /// Mirrors the scope fallback of ERC-8107 `_edgeTrust`, returning which stored
    /// record carries the edge
    function _effective(ITrustRegistry registry, bytes32 from, bytes32 to, bytes32 scope)
        private
        view
        returns (bytes32 eff, TrustLevel level, uint64 expiry)
    {
        (TrustLevel ul, uint64 ux) = registry.getTrust(from, to, bytes32(0));
        if (scope == bytes32(0) || ul == TrustLevel.None) return (bytes32(0), ul, ux);
        (TrustLevel sl, uint64 sx) = registry.getTrust(from, to, scope);
        if (sl != TrustLevel.Unknown) return (scope, sl, sx);
        return (bytes32(0), ul, ux);
    }

    function _lastTrustSet(History memory h, address registry, bytes32 from, bytes32 to, bytes32 scope)
        private
        pure
        returns (bool found, uint256 at, TrustLevel level, uint64 expiry)
    {
        for (uint256 k = h.logs.length; k > 0; k--) {
            Log memory l = h.logs[k - 1];
            if (
                l.emitter == registry && l.topics.length == 4 && l.topics[0] == ITrustRegistry.TrustSet.selector
                    && l.topics[1] == from && l.topics[2] == to && l.topics[3] == scope
            ) {
                (level, expiry,) = abi.decode(l.data, (TrustLevel, uint64, uint64));
                return (true, k - 1, level, expiry);
            }
        }
    }

    /// Only the BaseRegistrar's own event counts; a controller's NameRegistered has a
    /// different signature, and any other emitter is ignored
    function _registeredAfter(History memory h, address base, uint256 id, uint256 at) private pure returns (bool) {
        for (uint256 k = at + 1; k < h.logs.length; k++) {
            Log memory l = h.logs[k];
            if (
                l.emitter == base && l.topics.length == 3 && l.topics[0] == IBaseRegistrarEvents.NameRegistered.selector
                    && uint256(l.topics[1]) == id
            ) return true;
        }
        return false;
    }

    /// Every NameWrapped counts, whether the name is wrapped for the first time, wrapped
    /// again after an unwrap, or created again by its parent after its NameWrapper
    /// expiry. A live reassignment by the parent emits TransferSingle, not NameWrapped
    function _wrappedAfter(History memory h, address wrapper, bytes32 node, uint256 at) private pure returns (bool) {
        for (uint256 k = at + 1; k < h.logs.length; k++) {
            Log memory l = h.logs[k];
            if (
                l.emitter == wrapper && l.topics.length == 2 && l.topics[0] == INameWrapperEvents.NameWrapped.selector
                    && l.topics[1] == node
            ) return true;
        }
        return false;
    }

    /// Hashes `labels` from the root down and checks the result against `node`. For a
    /// name under .eth with at least two labels, also returns its 2LD's token id and the
    /// nodes below the 2LD on the way to `node`, `node` included
    function _name(string[] memory labels, bytes32 node)
        private
        pure
        returns (bool ok, bool underEth, uint256 tokenId, bytes32[] memory below)
    {
        uint256 len = labels.length;
        bytes32[] memory at = new bytes32[](len); // at[j]: the node named by labels[j..]
        bytes32 n = bytes32(0);
        for (uint256 j = len; j > 0; j--) {
            n = keccak256(abi.encodePacked(n, keccak256(bytes(labels[j - 1]))));
            at[j - 1] = n;
        }
        if (n != node) return (false, false, 0, below);
        if (len < 2 || at[len - 1] != ETH_NODE) {
            return (true, false, 0, below);
        }
        below = new bytes32[](len - 2);
        for (uint256 j = 0; j + 2 < len; j++) {
            below[j] = at[j];
        }
        return (true, true, uint256(keccak256(bytes(labels[len - 2]))), below);
    }

    function _ordered(History memory h) private pure returns (bool) {
        uint256 prev;
        for (uint256 k = 0; k < h.logs.length; k++) {
            Log memory l = h.logs[k];
            if (l.blockNumber < h.fromBlock || l.blockNumber > h.toBlock) return false;
            uint256 pos = (uint256(l.blockNumber) << 64) | (uint256(l.txIndex) << 32) | l.logIndex;
            if (k > 0 && pos <= prev) return false;
            prev = pos;
        }
        return true;
    }

    function _unknown(Reason reason, uint256 i, bytes32 node) private pure returns (Result memory) {
        return Result(Verdict.Unknown, reason, i, node);
    }
}
