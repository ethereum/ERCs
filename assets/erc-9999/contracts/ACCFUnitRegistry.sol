// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ACCFTypes as T} from "./interfaces/ACCFTypes.sol";
import {IACCFUnits} from "./interfaces/IACCFUnits.sol";
import {ACCFErrors} from "./ACCFErrors.sol";

/// @title ACCFUnitRegistry
/// @notice Reference registry of Cell Records, manifest commitments and Transition Records.
/// @dev    No owner, no upgrade path, no privileged account. Documents stay off chain; the registry holds
///         their commitments and the facts it enforces.
contract ACCFUnitRegistry is IACCFUnits, ACCFErrors {
    struct Grant {
        uint256 scopes;
        uint48 validUntil;
        uint32 controlVersion;
    }

    struct PendingControl {
        address newController;
        address proposer;
        uint48 expiry;
        bytes32 detailsHash;
    }

    struct Proposal {
        uint8 kind; // KIND_SUCCESSION or KIND_COMPOSITION; 0 when absent
        bool byGroup;
        bool memberAffected;
        uint48 expiry;
        uint32 controlVersion; // control version of the proposing side
        bytes32 a; // predecessor or group
        bytes32 b; // successor or member
        bytes32 termsHash;
    }

    mapping(bytes32 => T.Unit) private _units;
    mapping(bytes32 => mapping(uint8 => bytes32)) private _entries;
    mapping(bytes32 => mapping(address => Grant)) private _operators;
    mapping(bytes32 => PendingControl) private _pendingControl;
    mapping(bytes32 => T.Derivation) private _derivations;
    mapping(bytes32 => Proposal) private _proposals;
    mapping(bytes32 => mapping(bytes32 => bool)) private _members;
    mapping(bytes32 => bytes32) private _claims;
    mapping(bytes32 => mapping(address => bool)) private _approvedAccounts;
    mapping(bytes32 => T.Transition) private _transitions;
    mapping(bytes32 => bytes32[]) private _history;
    uint256 private _unitNonce;
    uint256 private _transitionNonce;
    uint256 private _proposalNonce;

    // ---------------------------------------------------------------------
    // Clock and introspection
    // ---------------------------------------------------------------------

    function clock() public view returns (uint48) {
        return uint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=timestamp";
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IACCFUnits).interfaceId || interfaceId == 0x01ffc9a7 // ERC-165
            || interfaceId == 0xda287a1d; // ERC-6372
    }

    // ---------------------------------------------------------------------
    // Registration and single-unit transitions
    // ---------------------------------------------------------------------

    function register(T.UnitInput calldata input) external returns (bytes32 unitId) {
        unitId = _create(input, bytes32(0), 0);
        _record(
            unitId,
            T.KIND_REGISTRATION,
            bytes32(0),
            _units[unitId].entries | T.DEP_BOUNDARY | T.DEP_CONTROL,
            input.detailsHash,
            input.detailsURI
        );
    }

    function transition(bytes32 unitId, T.TransitionInput calldata input) external returns (bytes32 transitionId) {
        T.Unit storage u = _live(unitId);
        uint8 kind = input.kind;
        if (input.detailsHash == bytes32(0)) revert DetailsRequired();

        uint256 scope;
        if (kind == T.KIND_MIGRATION || kind == T.KIND_REPAIR || kind == T.KIND_UPGRADE) {
            scope = T.SCOPE_MANIFEST;
        } else if (kind == T.KIND_SUSPENSION || kind == T.KIND_RESUMPTION) {
            scope = T.SCOPE_STATE;
        } else if (kind == T.KIND_BOUNDARY_CHANGE) {
            scope = T.SCOPE_BOUNDARY;
        } else if (kind != T.KIND_RETIREMENT && kind < T.FIRST_EXTENSION_KIND) {
            revert InvalidKind(kind);
        }
        _authorize(unitId, u, scope);

        uint256 changed = _setEntries(unitId, u, input.entries, input.entryHashes);
        bool boundary = input.descriptorHash != bytes32(0);
        T.OperatingState target = input.state;

        if (kind == T.KIND_UPGRADE) {
            if (changed == 0) revert NothingChanged();
        } else if (kind == T.KIND_MIGRATION) {
            if (changed & (uint256(1) << T.SEC_EXECUTION) == 0) revert NothingChanged();
        } else if (kind == T.KIND_BOUNDARY_CHANGE) {
            if (!boundary) revert DescriptorRequired();
            if (changed != 0) revert UnexpectedChange();
        } else if (kind < T.FIRST_EXTENSION_KIND) {
            // repair, suspension, resumption and retirement leave manifest and boundary as they are
            if (changed != 0 || boundary) revert UnexpectedChange();
            if (kind == T.KIND_SUSPENSION) {
                if (
                    target != T.OperatingState.Degraded && target != T.OperatingState.Suspended
                        && target != T.OperatingState.Maintenance
                ) revert InvalidState();
            } else if (kind == T.KIND_RESUMPTION) {
                if (target != T.OperatingState.Active && target != T.OperatingState.Degraded) revert InvalidState();
                if (u.state == T.OperatingState.Active) revert InvalidState();
            } else if (kind == T.KIND_RETIREMENT) {
                if (target != T.OperatingState.Retired) revert InvalidState();
                if (u.memberCount != 0 || u.groupCount != 0 || u.claimCount != 0) revert OutstandingRelations(unitId);
            }
        }

        if (target != T.OperatingState.None) {
            if (target == T.OperatingState.Retired && kind != T.KIND_RETIREMENT) revert InvalidState();
            u.state = target;
        }
        if (changed != 0) {
            u.manifestVersion += 1;
            u.manifestRoot = _root(unitId, u.entries);
            emit ManifestSet(unitId, u.manifestVersion, u.manifestRoot, input.manifestURI);
        }
        if (boundary) {
            _setDescriptor(unitId, u, input.descriptorHash, input.descriptorURI);
            changed |= T.DEP_BOUNDARY;
        }
        transitionId = _record(unitId, kind, bytes32(0), changed, input.detailsHash, input.detailsURI);
    }

    // ---------------------------------------------------------------------
    // Control relation
    // ---------------------------------------------------------------------

    function setRecovery(bytes32 unitId, address recovery) external {
        T.Unit storage u = _live(unitId);
        _authorize(unitId, u, 0);
        u.recovery = recovery;
        PendingControl storage p = _pendingControl[unitId];
        if (p.newController != address(0) && p.proposer != u.controller) {
            delete _pendingControl[unitId];
            emit ControlProposalCancelled(unitId);
        }
        emit RecoverySet(unitId, recovery);
    }

    function setOperator(bytes32 unitId, address operator, uint256 scopes, uint48 validUntil) external {
        T.Unit storage u = _live(unitId);
        _authorize(unitId, u, 0);
        if (operator == address(0)) revert InvalidAddress();
        _operators[unitId][operator] = Grant({scopes: scopes, validUntil: validUntil, controlVersion: u.controlVersion});
        emit OperatorSet(unitId, operator, scopes, validUntil);
    }

    function proposeControl(
        bytes32 unitId,
        address newController,
        bytes32 detailsHash,
        string calldata detailsURI,
        uint48 expiry
    ) external {
        T.Unit storage u = _live(unitId);
        _controlAuthority(unitId, u);
        if (newController == address(0)) revert InvalidAddress();
        if (detailsHash == bytes32(0)) revert DetailsRequired();
        if (expiry <= clock()) revert InvalidExpiry();
        _pendingControl[unitId] =
            PendingControl({newController: newController, proposer: msg.sender, expiry: expiry, detailsHash: detailsHash});
        emit ControlProposed(unitId, newController, msg.sender, detailsHash, detailsURI, expiry);
    }

    function cancelControl(bytes32 unitId) external {
        T.Unit storage u = _live(unitId);
        _controlAuthority(unitId, u);
        delete _pendingControl[unitId];
        emit ControlProposalCancelled(unitId);
    }

    function acceptControl(bytes32 unitId, bytes32 descriptorHash, string calldata descriptorURI)
        external
        returns (bytes32 transitionId)
    {
        T.Unit storage u = _live(unitId);
        PendingControl memory p = _pendingControl[unitId];
        if (p.newController != msg.sender || p.expiry < clock()) revert NotAuthorized(unitId, msg.sender);
        delete _pendingControl[unitId];
        u.controller = msg.sender;
        u.controlVersion += 1;
        uint256 changed = T.DEP_CONTROL;
        if (descriptorHash != bytes32(0)) {
            _setDescriptor(unitId, u, descriptorHash, descriptorURI);
            changed |= T.DEP_BOUNDARY;
        }
        transitionId = _record(unitId, T.KIND_CONTROL_CHANGE, bytes32(0), changed, p.detailsHash, "");
    }

    // ---------------------------------------------------------------------
    // Derivation
    // ---------------------------------------------------------------------

    function setDerivationAllowance(bytes32 unitId, T.DerivationAllowance calldata a) external {
        T.Unit storage u = _live(unitId);
        _authorize(unitId, u, 0);
        T.Derivation storage d = _derivations[unitId];
        if (a.limits > (T.LIMIT_COUNT | T.LIMIT_GENERATION | T.LIMIT_BUDGET)) revert DerivationLimit(unitId, a.limits);
        if (d.inherited & T.LIMIT_GENERATION != 0) {
            if (a.limits & T.LIMIT_GENERATION == 0 || a.maxGeneration > d.inheritedMaxGeneration) {
                revert AllowanceWidened(T.LIMIT_GENERATION);
            }
        }
        if (d.inherited & T.LIMIT_BUDGET != 0) {
            if (a.limits & T.LIMIT_BUDGET == 0 || a.budget > d.inheritedBudget) revert AllowanceWidened(T.LIMIT_BUDGET);
        }
        if (a.limits & T.LIMIT_BUDGET != 0 && a.budget < d.granted) revert DerivationLimit(unitId, T.LIMIT_BUDGET);
        if (a.limits & T.LIMIT_COUNT != 0 && a.maxChildren < d.children) revert DerivationLimit(unitId, T.LIMIT_COUNT);
        d.allowance = a;
        emit DerivationAllowanceSet(unitId, a);
    }

    function derive(bytes32 parentId, T.UnitInput calldata child, T.DerivationTerms calldata terms)
        external
        returns (bytes32 childId, bytes32 transitionId)
    {
        T.Unit storage p = _live(parentId);
        _authorize(parentId, p, T.SCOPE_DERIVE);
        if (p.state != T.OperatingState.Active && p.state != T.OperatingState.Degraded) revert InvalidState();

        T.Derivation storage d = _derivations[parentId];
        T.DerivationAllowance memory a = d.allowance;
        uint32 generation = p.generation + 1;
        if (!a.enabled) revert DerivationNotPermitted(parentId);
        if (a.limits & T.LIMIT_COUNT != 0 && d.children >= a.maxChildren) revert DerivationLimit(parentId, T.LIMIT_COUNT);
        if (a.limits & T.LIMIT_GENERATION != 0 && generation > a.maxGeneration) {
            revert DerivationLimit(parentId, T.LIMIT_GENERATION);
        }
        if (a.limits & T.LIMIT_BUDGET != 0) {
            // the limit is on the sum of what all children were granted, not on each grant
            if (d.granted + terms.budget > a.budget) revert DerivationLimit(parentId, T.LIMIT_BUDGET);
            d.granted += terms.budget;
        } else if (terms.budget != 0) {
            revert DerivationLimit(parentId, T.LIMIT_BUDGET);
        }
        d.children += 1;

        childId = _create(child, parentId, generation);
        T.Unit storage c = _units[childId];
        T.Derivation storage cd = _derivations[childId];
        cd.inherited = a.limits & (T.LIMIT_GENERATION | T.LIMIT_BUDGET);
        cd.inheritedMaxGeneration = a.maxGeneration;
        cd.inheritedBudget = terms.budget;

        uint256 parentChanged;
        for (uint256 i = 0; i < terms.claims.length; ++i) {
            _moveClaim(parentId, p, childId, c, terms.claims[i]);
        }
        if (terms.claims.length != 0 || terms.budget != 0) {
            // what the parent gave away is no longer inside its boundary
            _bumpBoundary(parentId, p);
            parentChanged = T.DEP_BOUNDARY;
        }
        emit DerivationGranted(parentId, childId, terms.budget, terms.claims);

        _record(
            childId,
            T.KIND_DERIVATION,
            parentId,
            c.entries | T.DEP_BOUNDARY | T.DEP_CONTROL,
            child.detailsHash,
            child.detailsURI
        );
        transitionId = _record(parentId, T.KIND_DERIVATION, childId, parentChanged, child.detailsHash, child.detailsURI);
    }

    // ---------------------------------------------------------------------
    // Succession
    // ---------------------------------------------------------------------

    function proposeSuccession(bytes32 predecessorId, bytes32 successorId, T.SuccessionTerms calldata terms)
        external
        returns (bytes32 proposalId)
    {
        T.Unit storage p = _live(predecessorId);
        _authorize(predecessorId, p, T.SCOPE_SUCCEED);
        _live(successorId);
        if (predecessorId == successorId) revert SameUnit();
        if (terms.detailsHash == bytes32(0)) revert DetailsRequired();
        if (terms.expiry <= clock()) revert InvalidExpiry();
        if (!terms.retirePredecessor && terms.predecessorDescriptorHash == bytes32(0)) revert DescriptorRequired();
        proposalId = keccak256(abi.encode(block.chainid, address(this), "proposal", ++_proposalNonce));
        _proposals[proposalId] = Proposal({
            kind: T.KIND_SUCCESSION,
            byGroup: false,
            memberAffected: false,
            expiry: terms.expiry,
            controlVersion: p.controlVersion,
            a: predecessorId,
            b: successorId,
            termsHash: keccak256(abi.encode(terms))
        });
        emit SuccessionProposed(proposalId, predecessorId, successorId, terms);
    }

    function acceptSuccession(
        bytes32 proposalId,
        T.SuccessionTerms calldata terms,
        bytes32 successorDescriptorHash,
        string calldata successorDescriptorURI
    ) external returns (bytes32 transitionId) {
        Proposal memory pr = _open(proposalId, T.KIND_SUCCESSION);
        if (keccak256(abi.encode(terms)) != pr.termsHash) revert TermsMismatch();
        T.Unit storage p = _live(pr.a);
        T.Unit storage s = _live(pr.b);
        if (p.controlVersion != pr.controlVersion) revert ProposalNotOpen(proposalId);
        _authorize(pr.b, s, T.SCOPE_SUCCEED);
        if (successorDescriptorHash == bytes32(0)) revert DescriptorRequired();
        delete _proposals[proposalId];

        for (uint256 i = 0; i < terms.claims.length; ++i) {
            _moveClaim(pr.a, p, pr.b, s, terms.claims[i]);
        }
        _setDescriptor(pr.b, s, successorDescriptorHash, successorDescriptorURI);
        if (terms.retirePredecessor) {
            // nothing the predecessor held or owed may be left without a bearer
            if (p.memberCount != 0 || p.groupCount != 0 || p.claimCount != 0) revert OutstandingRelations(pr.a);
            p.state = T.OperatingState.Retired;
        } else {
            _setDescriptor(pr.a, p, terms.predecessorDescriptorHash, terms.predecessorDescriptorURI);
        }
        _record(pr.a, T.KIND_SUCCESSION, pr.b, T.DEP_BOUNDARY, terms.detailsHash, terms.detailsURI);
        transitionId = _record(pr.b, T.KIND_SUCCESSION, pr.a, T.DEP_BOUNDARY, terms.detailsHash, terms.detailsURI);
    }

    // ---------------------------------------------------------------------
    // Composition
    // ---------------------------------------------------------------------

    function proposeMembership(
        bytes32 groupId,
        bytes32 memberId,
        bool byGroup,
        bool memberAffected,
        bytes32 termsHash,
        string calldata termsURI,
        uint48 expiry
    ) external returns (bytes32 proposalId) {
        T.Unit storage g = _live(groupId);
        T.Unit storage m = _live(memberId);
        if (m.rank >= g.rank) revert InvalidRank();
        if (_members[groupId][memberId]) revert AlreadyMember(groupId, memberId);
        if (termsHash == bytes32(0)) revert DetailsRequired();
        if (expiry <= clock()) revert InvalidExpiry();
        uint32 version;
        if (byGroup) {
            _authorize(groupId, g, T.SCOPE_COMPOSE);
            version = g.controlVersion;
        } else {
            _authorize(memberId, m, T.SCOPE_COMPOSE);
            version = m.controlVersion;
        }
        proposalId = keccak256(abi.encode(block.chainid, address(this), "proposal", ++_proposalNonce));
        _proposals[proposalId] = Proposal({
            kind: T.KIND_COMPOSITION,
            byGroup: byGroup,
            memberAffected: !byGroup && memberAffected,
            expiry: expiry,
            controlVersion: version,
            a: groupId,
            b: memberId,
            termsHash: termsHash
        });
        emit MembershipProposed(proposalId, groupId, memberId, byGroup, termsHash, termsURI, expiry);
    }

    function acceptMembership(bytes32 proposalId, bool memberAffected) external returns (bytes32 transitionId) {
        Proposal memory pr = _open(proposalId, T.KIND_COMPOSITION);
        T.Unit storage g = _live(pr.a);
        T.Unit storage m = _live(pr.b);
        if ((pr.byGroup ? g.controlVersion : m.controlVersion) != pr.controlVersion) revert ProposalNotOpen(proposalId);
        if (_members[pr.a][pr.b]) revert AlreadyMember(pr.a, pr.b);
        bool affected;
        if (pr.byGroup) {
            _authorize(pr.b, m, T.SCOPE_COMPOSE);
            affected = memberAffected;
        } else {
            _authorize(pr.a, g, T.SCOPE_COMPOSE);
            affected = pr.memberAffected;
        }
        delete _proposals[proposalId];
        _members[pr.a][pr.b] = true;
        g.memberCount += 1;
        m.groupCount += 1;
        emit MembershipChanged(pr.a, pr.b, true);
        transitionId = _recordMembership(pr.a, g, pr.b, m, T.KIND_COMPOSITION, affected, pr.termsHash, "");
    }

    function endMembership(
        bytes32 groupId,
        bytes32 memberId,
        bool byGroup,
        bool memberAffected,
        bytes32 detailsHash,
        string calldata detailsURI
    ) external returns (bytes32 transitionId) {
        T.Unit storage g = _live(groupId);
        T.Unit storage m = _live(memberId);
        if (!_members[groupId][memberId]) revert NotMember(groupId, memberId);
        if (detailsHash == bytes32(0)) revert DetailsRequired();
        if (byGroup) _authorize(groupId, g, T.SCOPE_COMPOSE);
        else _authorize(memberId, m, T.SCOPE_COMPOSE);
        _members[groupId][memberId] = false;
        g.memberCount -= 1;
        m.groupCount -= 1;
        emit MembershipChanged(groupId, memberId, false);
        transitionId = _recordMembership(
            groupId, g, memberId, m, T.KIND_DECOMPOSITION, !byGroup && memberAffected, detailsHash, detailsURI
        );
    }

    function cancelProposal(bytes32 proposalId) external {
        Proposal memory pr = _proposals[proposalId];
        if (pr.kind == 0) revert ProposalNotOpen(proposalId);
        bytes32 side = (pr.kind == T.KIND_SUCCESSION || pr.byGroup) ? pr.a : pr.b;
        _authorize(side, _live(side), pr.kind == T.KIND_SUCCESSION ? T.SCOPE_SUCCEED : T.SCOPE_COMPOSE);
        delete _proposals[proposalId];
        emit ProposalCancelled(proposalId);
    }

    // ---------------------------------------------------------------------
    // Exclusive claims
    // ---------------------------------------------------------------------

    function approveAccount(bytes32 unitId, address account, bool approved) external {
        _authorize(unitId, _live(unitId), T.SCOPE_CLAIM);
        _approvedAccounts[unitId][account] = approved;
        emit AccountApproved(unitId, account, approved);
    }

    function claimAccount(bytes32 unitId) external {
        T.Unit storage u = _live(unitId);
        if (msg.sender != u.controller && !_approvedAccounts[unitId][msg.sender]) {
            revert AccountNotApproved(unitId, msg.sender);
        }
        _claim(unitId, u, accountKey(msg.sender));
    }

    function claimResource(bytes32 unitId, bytes32 key) external {
        T.Unit storage u = _live(unitId);
        _authorize(unitId, u, T.SCOPE_CLAIM);
        // keys that fit in 160 bits are account keys and need the account's own call
        if (uint256(key) >> 160 == 0) revert InvalidClaimKey(key);
        _claim(unitId, u, key);
    }

    function release(bytes32 unitId, bytes32 key) external {
        T.Unit storage u = _live(unitId);
        if (key != accountKey(msg.sender)) _authorize(unitId, u, T.SCOPE_CLAIM);
        if (_claims[key] != unitId) revert NotClaimed(key, unitId);
        delete _claims[key];
        u.claimCount -= 1;
        _bumpBoundary(unitId, u);
        emit Released(unitId, key);
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function exists(bytes32 unitId) external view returns (bool) {
        return _units[unitId].registeredAt != 0;
    }

    function unitOf(bytes32 unitId) external view returns (T.Unit memory) {
        if (_units[unitId].registeredAt == 0) revert UnknownUnit(unitId);
        return _units[unitId];
    }

    function entryOf(bytes32 unitId, uint8 entry) external view returns (bytes32) {
        return _entries[unitId][entry];
    }

    function entriesOf(bytes32 unitId) external view returns (uint8[] memory entries, bytes32[] memory entryHashes) {
        if (_units[unitId].registeredAt == 0) revert UnknownUnit(unitId);
        return _collect(unitId, _units[unitId].entries);
    }

    function dependencyDigest(bytes32 unitId, uint256 mask) external view returns (bytes32) {
        T.Unit storage u = _units[unitId];
        if (u.registeredAt == 0) revert UnknownUnit(unitId);
        if (mask & ~T.DEPENDENCY_MASK != 0) revert InvalidEntries();
        // an absent entry contributes zero, so a digest taken over it changes when the entry is committed
        (, bytes32[] memory values) = _collect(unitId, mask & T.ENTRY_MASK);
        bytes32 boundary =
            mask & T.DEP_BOUNDARY != 0 ? keccak256(abi.encode(u.descriptorHash, u.boundaryVersion)) : bytes32(0);
        bytes32 control = mask & T.DEP_CONTROL != 0 ? keccak256(abi.encode(u.controller, u.controlVersion)) : bytes32(0);
        return keccak256(abi.encode(mask, values, boundary, control));
    }

    function isAuthorized(bytes32 unitId, address account, uint256 scope) public view returns (bool) {
        T.Unit storage u = _units[unitId];
        if (u.registeredAt == 0 || u.state == T.OperatingState.Retired) return false;
        if (account == u.controller) return true;
        if (scope == 0) return false;
        Grant storage g = _operators[unitId][account];
        return g.controlVersion == u.controlVersion && g.validUntil >= clock() && g.scopes & scope == scope;
    }

    function operatorOf(bytes32 unitId, address operator) external view returns (uint256 scopes, uint48 validUntil) {
        Grant storage g = _operators[unitId][operator];
        if (g.controlVersion != _units[unitId].controlVersion) return (0, 0);
        return (g.scopes, g.validUntil);
    }

    function pendingControlOf(bytes32 unitId) external view returns (address newController, uint48 expiry) {
        PendingControl storage p = _pendingControl[unitId];
        return (p.newController, p.expiry);
    }

    function derivationOf(bytes32 unitId) external view returns (T.Derivation memory) {
        return _derivations[unitId];
    }

    function derivationPermitted(bytes32 unitId, uint256 budget) external view returns (bool) {
        T.Unit storage u = _units[unitId];
        if (u.registeredAt == 0) return false;
        if (u.state != T.OperatingState.Active && u.state != T.OperatingState.Degraded) return false;
        T.Derivation storage d = _derivations[unitId];
        T.DerivationAllowance memory a = d.allowance;
        if (!a.enabled) return false;
        if (a.limits & T.LIMIT_COUNT != 0 && d.children >= a.maxChildren) return false;
        if (a.limits & T.LIMIT_GENERATION != 0 && u.generation + 1 > a.maxGeneration) return false;
        if (a.limits & T.LIMIT_BUDGET != 0) return d.granted + budget <= a.budget;
        return budget == 0;
    }

    function isMember(bytes32 groupId, bytes32 memberId) external view returns (bool) {
        return _members[groupId][memberId];
    }

    function claimantOf(bytes32 key) external view returns (bytes32) {
        return _claims[key];
    }

    function isAccountOf(bytes32 unitId, address account) external view returns (bool) {
        return unitId != bytes32(0) && _claims[accountKey(account)] == unitId;
    }

    function accountKey(address account) public pure returns (bytes32) {
        return bytes32(uint256(uint160(account)));
    }

    function transitionOf(bytes32 transitionId) external view returns (T.Transition memory) {
        return _transitions[transitionId];
    }

    function transitionCount(bytes32 unitId) external view returns (uint256) {
        return _history[unitId].length;
    }

    function transitionAt(bytes32 unitId, uint256 index) external view returns (bytes32) {
        return _history[unitId][index];
    }

    function computeRoot(uint8[] calldata entries, bytes32[] calldata entryHashes) external pure returns (bytes32) {
        if (entries.length != entryHashes.length) revert InvalidEntries();
        for (uint256 i = 0; i < entries.length; ++i) {
            if (entries[i] > T.LAST_ENTRY || (i != 0 && entries[i] <= entries[i - 1]) || entryHashes[i] == bytes32(0)) {
                revert InvalidEntries();
            }
        }
        return keccak256(abi.encode(T.MANIFEST_DOMAIN, entries, entryHashes));
    }

    function subjectKeyOf(bytes32 subjectType, bytes calldata subjectData) external pure returns (bytes32) {
        return keccak256(abi.encode(subjectType, subjectData));
    }

    // ---------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------

    function _live(bytes32 unitId) private view returns (T.Unit storage u) {
        u = _units[unitId];
        if (u.registeredAt == 0) revert UnknownUnit(unitId);
        if (u.state == T.OperatingState.Retired) revert Retired(unitId);
    }

    function _authorize(bytes32 unitId, T.Unit storage u, uint256 scope) private view {
        if (msg.sender == u.controller) return;
        if (scope != 0) {
            Grant storage g = _operators[unitId][msg.sender];
            if (g.controlVersion == u.controlVersion && g.validUntil >= clock() && g.scopes & scope == scope) return;
        }
        revert NotAuthorized(unitId, msg.sender);
    }

    function _controlAuthority(bytes32 unitId, T.Unit storage u) private view {
        if (msg.sender != u.controller && (u.recovery == address(0) || msg.sender != u.recovery)) {
            revert NotAuthorized(unitId, msg.sender);
        }
    }

    function _open(bytes32 proposalId, uint8 kind) private view returns (Proposal memory pr) {
        pr = _proposals[proposalId];
        if (pr.kind != kind || pr.expiry < clock()) revert ProposalNotOpen(proposalId);
    }

    function _create(T.UnitInput calldata input, bytes32 parent, uint32 generation) private returns (bytes32 unitId) {
        if (input.descriptorHash == bytes32(0)) revert DescriptorRequired();
        if (input.detailsHash == bytes32(0)) revert DetailsRequired();
        if (input.state == T.OperatingState.None || input.state == T.OperatingState.Retired) revert InvalidState();
        unitId = keccak256(abi.encode(block.chainid, address(this), ++_unitNonce));
        T.Unit storage u = _units[unitId];
        u.subjectKey = keccak256(abi.encode(input.subjectType, input.subjectData));
        u.controller = msg.sender;
        u.recovery = input.recovery;
        u.kind = input.kind;
        u.rank = input.rank;
        u.state = input.state;
        u.boundaryVersion = 1;
        u.controlVersion = 1;
        u.manifestVersion = 1;
        u.generation = generation;
        u.registeredAt = clock();
        u.bornAt = parent == bytes32(0) ? 0 : clock();
        u.descriptorHash = input.descriptorHash;
        u.parent = parent;
        u.lineageCommitment = input.lineageCommitment;
        emit UnitRegistered(
            unitId,
            u.subjectKey,
            msg.sender,
            input.subjectType,
            input.subjectData,
            input.kind,
            input.rank,
            parent,
            input.lineageCommitment
        );
        emit DescriptorSet(unitId, 1, input.descriptorHash, input.descriptorURI);
        _setEntries(unitId, u, input.entries, input.entryHashes);
        u.manifestRoot = _root(unitId, u.entries);
        emit ManifestSet(unitId, 1, u.manifestRoot, input.manifestURI);
    }

    /// @dev Applies entry commitments and returns the mask of entries whose value changed.
    function _setEntries(bytes32 unitId, T.Unit storage u, uint8[] calldata entries, bytes32[] calldata hashes)
        private
        returns (uint256 changed)
    {
        if (entries.length != hashes.length) revert InvalidEntries();
        uint256 bitmap = u.entries;
        for (uint256 i = 0; i < entries.length; ++i) {
            uint8 e = entries[i];
            if (e > T.LAST_ENTRY || (i != 0 && e <= entries[i - 1])) revert InvalidEntries();
            if (_entries[unitId][e] == hashes[i]) continue;
            _entries[unitId][e] = hashes[i];
            uint256 bit = uint256(1) << e;
            if (hashes[i] == bytes32(0)) bitmap &= ~bit;
            else bitmap |= bit;
            changed |= bit;
            emit EntrySet(unitId, e, hashes[i]);
        }
        u.entries = bitmap;
    }

    /// @dev The entries named by `bitmap` in ascending order with their current commitments.
    function _collect(bytes32 unitId, uint256 bitmap)
        private
        view
        returns (uint8[] memory entries, bytes32[] memory hashes)
    {
        uint256 count;
        for (uint256 m = bitmap; m != 0; m >>= 1) {
            count += m & 1;
        }
        entries = new uint8[](count);
        hashes = new bytes32[](count);
        uint256 k;
        for (uint256 i = 0; bitmap >> i != 0; ++i) {
            if ((bitmap >> i) & 1 == 1) {
                entries[k] = uint8(i);
                hashes[k] = _entries[unitId][uint8(i)];
                ++k;
            }
        }
    }

    function _root(bytes32 unitId, uint256 bitmap) private view returns (bytes32) {
        (uint8[] memory entries, bytes32[] memory hashes) = _collect(unitId, bitmap);
        return keccak256(abi.encode(T.MANIFEST_DOMAIN, entries, hashes));
    }

    function _setDescriptor(bytes32 unitId, T.Unit storage u, bytes32 descriptorHash, string memory uri) private {
        u.descriptorHash = descriptorHash;
        u.boundaryVersion += 1;
        emit DescriptorSet(unitId, u.boundaryVersion, descriptorHash, uri);
    }

    /// @dev Advances the boundary version without a new descriptor: what the boundary holds changed.
    function _bumpBoundary(bytes32 unitId, T.Unit storage u) private {
        u.boundaryVersion += 1;
        emit DescriptorSet(unitId, u.boundaryVersion, u.descriptorHash, "");
    }

    function _claim(bytes32 unitId, T.Unit storage u, bytes32 key) private {
        bytes32 holder = _claims[key];
        if (holder != bytes32(0)) revert AlreadyClaimed(key, holder);
        _claims[key] = unitId;
        u.claimCount += 1;
        _bumpBoundary(unitId, u);
        emit Claimed(unitId, key);
    }

    function _moveClaim(bytes32 fromId, T.Unit storage from, bytes32 toId, T.Unit storage to, bytes32 key) private {
        if (_claims[key] != fromId) revert NotClaimed(key, fromId);
        _claims[key] = toId;
        from.claimCount -= 1;
        to.claimCount += 1;
        emit ClaimMoved(fromId, toId, key);
    }

    function _recordMembership(
        bytes32 groupId,
        T.Unit storage g,
        bytes32 memberId,
        T.Unit storage m,
        uint8 kind,
        bool memberAffected,
        bytes32 detailsHash,
        string memory detailsURI
    ) private returns (bytes32 transitionId) {
        // membership is part of the group's boundary
        _bumpBoundary(groupId, g);
        if (memberAffected) _bumpBoundary(memberId, m);
        _record(memberId, kind, groupId, memberAffected ? T.DEP_BOUNDARY : 0, detailsHash, detailsURI);
        transitionId = _record(groupId, kind, memberId, T.DEP_BOUNDARY, detailsHash, detailsURI);
    }

    function _record(
        bytes32 unitId,
        uint8 kind,
        bytes32 counterpart,
        uint256 changed,
        bytes32 detailsHash,
        string memory detailsURI
    ) private returns (bytes32 transitionId) {
        T.Unit storage u = _units[unitId];
        transitionId = keccak256(abi.encode(block.chainid, address(this), "transition", ++_transitionNonce));
        _transitions[transitionId] = T.Transition({
            unitId: unitId,
            counterpart: counterpart,
            actor: msg.sender,
            kind: kind,
            state: u.state,
            at: clock(),
            boundaryVersion: u.boundaryVersion,
            controlVersion: u.controlVersion,
            manifestVersion: u.manifestVersion,
            changed: changed,
            manifestRoot: u.manifestRoot,
            detailsHash: detailsHash
        });
        _history[unitId].push(transitionId);
        emit Transitioned(transitionId, unitId, kind, counterpart, msg.sender, changed, u.state, detailsHash, detailsURI);
    }
}
