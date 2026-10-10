// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ACDFTypes as T} from "./ACDFTypes.sol";
import {IACDFPolicyRegistry} from "./interfaces/IACDFPolicyRegistry.sol";

/// @title  ACDFPolicyRegistry — Decision Policy registry, reference kernel v0.2
/// @notice Non-upgradeable. Every parameter that drives eligibility, thresholds, composition,
///         timing and finality is part of the hashed `PolicySpec`, so the registered rule and
///         the executed rule are the same object. Validation here is what makes "any
///         implementer gets the same legal state from the same input" possible: no cyclic or
///         duplicated body graph, no k outside [1, N], no roster duplicates, and a hard cap
///         that covers every round and appeal window.
contract ACDFPolicyRegistry is IACDFPolicyRegistry {
    uint256 private constant MAX_BODIES = 32;
    uint256 private constant MAX_NODES = 64;

    mapping(bytes32 => T.PolicySpec) private _policies;
    mapping(bytes32 => bool) private _exists;
    mapping(bytes32 => uint64) private _roundDuration;
    mapping(bytes32 => address) private _familyAuthority;
    mapping(bytes32 => bytes32) private _familyLatestId;
    mapping(bytes32 => uint32) private _familyLatestVersion;

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == type(IACDFPolicyRegistry).interfaceId;
    }

    function policyIdOf(T.PolicySpec calldata spec) public pure returns (bytes32) {
        return keccak256(abi.encode(spec));
    }

    function registerPolicy(T.PolicySpec calldata spec) external returns (bytes32 policyId) {
        policyId = policyIdOf(spec);
        require(!_exists[policyId], "ACDF: policy exists");
        uint64 duration = _validate(spec);

        require(spec.family != bytes32(0), "ACDF: zero family");
        require(spec.version >= 1, "ACDF: zero version");
        require(spec.updateAuthority != address(0), "ACDF: zero update authority");
        if (_familyAuthority[spec.family] == address(0)) {
            require(spec.previous == bytes32(0), "ACDF: first version has no previous");
        } else {
            require(msg.sender == _familyAuthority[spec.family], "ACDF: not family authority");
            require(spec.previous == _familyLatestId[spec.family], "ACDF: previous != latest");
            require(spec.version > _familyLatestVersion[spec.family], "ACDF: version not increasing");
        }
        _familyAuthority[spec.family] = spec.updateAuthority;
        _familyLatestId[spec.family] = policyId;
        _familyLatestVersion[spec.family] = spec.version;

        _store(policyId, spec);
        _exists[policyId] = true;
        _roundDuration[policyId] = duration;
        emit PolicyRegistered(policyId, spec.family, spec.version, msg.sender);
    }

    /// Validates every structural rule of a policy and returns the round duration
    /// (the longest body window; all bodies of a round start together).
    function _validate(T.PolicySpec calldata spec) private pure returns (uint64 duration) {
        uint256 nb = spec.bodies.length;
        uint256 nn = spec.nodes.length;
        require(nb >= 1 && nb <= MAX_BODIES, "ACDF: bodies out of range");
        require(nn >= 1 && nn <= MAX_NODES, "ACDF: nodes out of range");

        for (uint256 i = 0; i < nb; i++) {
            T.BodySpec calldata b = spec.bodies[i];
            require(b.window > 0, "ACDF: zero window");
            if (b.window > duration) duration = b.window;
            uint256 n = b.members.length;
            if (b.kind == T.BodyKind.ROSTER_KOFN) {
                require(n >= 1, "ACDF: empty roster");
                require(b.k >= 1 && b.k <= n, "ACDF: bad k");
                require(b.acceptance != T.Acceptance.AUTHORIZED_SUBMITTER, "ACDF: roster acceptance");
                for (uint256 a = 0; a < n; a++) {
                    require(b.members[a] != address(0), "ACDF: zero member");
                    for (uint256 c = a + 1; c < n; c++) {
                        require(b.members[a] != b.members[c], "ACDF: duplicate member");
                    }
                }
            } else {
                require(n == 1 && b.members[0] != address(0), "ACDF: submitter required");
                require(b.acceptance == T.Acceptance.AUTHORIZED_SUBMITTER, "ACDF: submitter acceptance");
            }
        }

        // nodes form a tree rooted at 0: every edge points to a strictly larger index
        // (acyclic by construction) and every non-root node is referenced exactly once.
        uint256[] memory refs = new uint256[](nn);
        for (uint256 i = 0; i < nn; i++) {
            T.Node calldata nd = spec.nodes[i];
            uint256 nc = nd.children.length;
            if (nd.op == T.Combinator.BODY) {
                require(nd.body < nb, "ACDF: body index");
                require(nc == 0, "ACDF: body node has children");
            } else if (nd.op == T.Combinator.VETO) {
                require(nc == 0, "ACDF: veto node has children");
                require(nd.target > i && nd.target < nn, "ACDF: veto target");
                require(nd.vetoBody < nb, "ACDF: veto body index");
                refs[nd.target] += 1;
            } else {
                require(nc >= 1, "ACDF: no children");
                if (nd.op == T.Combinator.KOFM) {
                    require(nd.k >= 1 && nd.k <= nc, "ACDF: bad node k");
                }
                for (uint256 a = 0; a < nc; a++) {
                    uint256 ch = nd.children[a];
                    require(ch > i && ch < nn, "ACDF: child index");
                    for (uint256 c = a + 1; c < nc; c++) {
                        require(ch != nd.children[c], "ACDF: duplicate child");
                    }
                    refs[ch] += 1;
                }
            }
        }
        require(refs[0] == 0, "ACDF: root referenced");
        for (uint256 i = 1; i < nn; i++) require(refs[i] == 1, "ACDF: node not in tree");

        if (spec.maxAppeals > 0) {
            require(spec.appealWindow > 0, "ACDF: zero appeal window");
            require(spec.appealable != 0 && spec.appealable <= 3, "ACDF: appealable mask");
        }
        uint256 worst = uint256(duration) * (uint256(spec.maxAppeals) + 1)
            + uint256(spec.appealWindow) * uint256(spec.maxAppeals);
        require(spec.maxTotalDuration >= worst, "ACDF: maxTotalDuration too short");
        require(spec.maxTotalDuration <= type(uint64).max / 2, "ACDF: maxTotalDuration too long");
    }

    function _store(bytes32 id, T.PolicySpec calldata spec) private {
        T.PolicySpec storage p = _policies[id];
        p.family = spec.family;
        p.version = spec.version;
        p.previous = spec.previous;
        p.updateAuthority = spec.updateAuthority;
        p.maxAppeals = spec.maxAppeals;
        p.appealWindow = spec.appealWindow;
        p.appealable = spec.appealable;
        p.appealStanding = spec.appealStanding;
        p.appealMode = spec.appealMode;
        p.maxTotalDuration = spec.maxTotalDuration;
        p.ackWindow = spec.ackWindow;
        p.allowAdvisory = spec.allowAdvisory;
        p.descriptorHash = spec.descriptorHash;
        for (uint256 i = 0; i < spec.bodies.length; i++) {
            p.bodies.push();
            T.BodySpec storage b = p.bodies[i];
            b.kind = spec.bodies[i].kind;
            b.acceptance = spec.bodies[i].acceptance;
            b.k = spec.bodies[i].k;
            b.window = spec.bodies[i].window;
            for (uint256 m = 0; m < spec.bodies[i].members.length; m++) {
                b.members.push(spec.bodies[i].members[m]);
            }
        }
        for (uint256 i = 0; i < spec.nodes.length; i++) {
            p.nodes.push();
            T.Node storage n = p.nodes[i];
            n.op = spec.nodes[i].op;
            n.body = spec.nodes[i].body;
            n.k = spec.nodes[i].k;
            n.target = spec.nodes[i].target;
            n.vetoBody = spec.nodes[i].vetoBody;
            n.silence = spec.nodes[i].silence;
            for (uint256 c = 0; c < spec.nodes[i].children.length; c++) {
                n.children.push(spec.nodes[i].children[c]);
            }
        }
    }

    // ------------------------------------------------------------------ reads

    function policyExists(bytes32 policyId) external view returns (bool) { return _exists[policyId]; }
    function familyAuthority(bytes32 family) external view returns (address) { return _familyAuthority[family]; }
    function familyLatest(bytes32 family) external view returns (bytes32, uint32) {
        return (_familyLatestId[family], _familyLatestVersion[family]);
    }
    function roundDurationOf(bytes32 policyId) external view returns (uint64) { return _roundDuration[policyId]; }

    function timingOf(bytes32 policyId) external view returns (Timing memory t) {
        require(_exists[policyId], "ACDF: unknown policy");
        T.PolicySpec storage p = _policies[policyId];
        t.maxAppeals = p.maxAppeals;
        t.appealWindow = p.appealWindow;
        t.appealable = p.appealable;
        t.appealStanding = p.appealStanding;
        t.appealMode = p.appealMode;
        t.maxTotalDuration = p.maxTotalDuration;
        t.ackWindow = p.ackWindow;
        t.allowAdvisory = p.allowAdvisory;
        t.roundDuration = _roundDuration[policyId];
    }

    function policyHeader(bytes32 policyId) external view returns (
        bytes32 family, uint32 version, bytes32 previous, address updateAuthority, bytes32 descriptorHash
    ) {
        require(_exists[policyId], "ACDF: unknown policy");
        T.PolicySpec storage p = _policies[policyId];
        return (p.family, p.version, p.previous, p.updateAuthority, p.descriptorHash);
    }

    function bodyCount(bytes32 policyId) external view returns (uint256) { return _policies[policyId].bodies.length; }

    function bodyOf(bytes32 policyId, uint32 body) external view returns (T.BodySpec memory) {
        require(body < _policies[policyId].bodies.length, "ACDF: body index");
        return _policies[policyId].bodies[body];
    }

    function nodeCount(bytes32 policyId) external view returns (uint256) { return _policies[policyId].nodes.length; }

    function nodeOf(bytes32 policyId, uint32 node) external view returns (T.Node memory) {
        require(node < _policies[policyId].nodes.length, "ACDF: node index");
        return _policies[policyId].nodes[node];
    }
}
