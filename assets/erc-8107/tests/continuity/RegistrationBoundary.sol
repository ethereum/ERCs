// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ITrustRegistry, TrustLevel} from "../../contracts/ITrustRegistry.sol";

interface IBaseRegistrarEvents {
    event NameRegistered(uint256 indexed id, address indexed owner, uint256 expires);
    event NameRenewed(uint256 indexed id, uint256 expires);
}

/// @title Registration-boundary continuity policy (coordinator side, non-normative)
/// @notice Reference for the coordinator check under ERC-8107 "Wrapped Name Lifecycle".
///         An attestation stays eligible only while no `.eth` second-level name it
///         involves, as trustor or trustee, has been registered again since the
///         attestation's `TrustSet` event. `NameRenewed` never moves the boundary.
///
///         This checks REGISTRATION continuity, not CONTROLLER continuity: a transfer
///         within one registration emits no `NameRegistered` and leaves attestations
///         eligible. It is applied in addition to `verifyPath`, whose verdict it never
///         widens, and it fails closed (`Unknown`) whenever the evidence it needs is
///         missing or inconsistent.
///
///         Inputs are what a coordinator holds off-chain: logs from `eth_getLogs` for the
///         registry and the BaseRegistrar, a block window the caller asserts is complete
///         for both emitters, and the name behind each path node. The function is `view`
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

    /// `logs` MUST hold every log the registry and the BaseRegistrar emitted in
    /// [fromBlock, toBlock], ordered by (blockNumber, txIndex, logIndex)
    struct History {
        uint64 fromBlock;
        uint64 toBlock;
        Log[] logs;
    }

    /// A node's preimage one level up: node == keccak256(parent, keccak256(label))
    struct NameProof {
        bool known;
        bytes32 parent;
        string label;
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
        ReRegistered
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
        bytes32[] nodes;
        bytes32 scope;
        NameProof[] proofs; // one per node
        uint64 head; // the block the coordinator decides at; the history must reach it
    }

    function evaluate(
        ITrustRegistry registry,
        address baseRegistrar,
        bytes32[] memory nodes,
        bytes32 scope,
        NameProof[] memory proofs,
        History memory h,
        uint64 head
    ) internal view returns (Result memory) {
        return evaluate(Query(registry, baseRegistrar, nodes, scope, proofs, head), h);
    }

    function evaluate(Query memory q, History memory h) internal view returns (Result memory r) {
        if (h.toBlock < q.head) return _unknown(Reason.HistoryBehindHead, 0, bytes32(0));
        if (!_ordered(h)) return _unknown(Reason.HistoryUnordered, 0, bytes32(0));
        if (q.proofs.length != q.nodes.length) return _unknown(Reason.NoNameProof, 0, bytes32(0));

        // Which nodes are .eth 2LDs, and their BaseRegistrar token ids. A node whose
        // name cannot be verified fails closed: without it the coordinator cannot tell
        // whether the rule applies
        bool[] memory is2LD = new bool[](q.nodes.length);
        uint256[] memory tokenId = new uint256[](q.nodes.length);
        for (uint256 i = 0; i < q.nodes.length; i++) {
            NameProof memory p = q.proofs[i];
            if (!p.known) return _unknown(Reason.NoNameProof, i, q.nodes[i]);
            bytes32 labelhash = keccak256(bytes(p.label));
            if (keccak256(abi.encodePacked(p.parent, labelhash)) != q.nodes[i]) {
                return _unknown(Reason.NameProofMismatch, i, q.nodes[i]);
            }
            is2LD[i] = p.parent == ETH_NODE;
            tokenId[i] = uint256(labelhash);
        }

        for (uint256 i = 0; i + 1 < q.nodes.length; i++) {
            uint256 at;
            (r, at) = _edgeRecord(q, h, i);
            if (r.verdict != Verdict.Eligible) return r;
            for (uint256 n = i; n <= i + 1; n++) {
                // trustor, then trustee
                if (is2LD[n] && _registeredAfter(h, q.baseRegistrar, tokenId[n], at)) {
                    return Result(Verdict.Ineligible, Reason.ReRegistered, i, q.nodes[n]);
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
