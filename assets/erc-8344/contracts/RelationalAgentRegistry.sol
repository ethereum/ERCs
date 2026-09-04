// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IRelationalAgentRegistry} from "./IRelationalAgentRegistry.sol";

/// @title Relational Agent Registry — reference implementation
/// @notice An agent is a relationship: one agent per member set (pair or group),
///         anchored to the append-only Shared Record Corpus of that relationship.
///         The relationship is eternal (relationshipId); agent instances have a
///         lifecycle and are scoped by generation (agentId).
contract RelationalAgentRegistry is IRelationalAgentRegistry {
    uint256 public constant MAX_MEMBERS = 128;
    bytes32 public constant SRC_APPEND = keccak256("SRC_APPEND");

    struct Delegation {
        uint64 expiry;          // 0 = not active
        uint16 confirmations;   // members confirmed for the pending grant
        uint64 pendingExpiry;   // expiry parameter being confirmed
    }

    mapping(uint256 => Agent) internal _agents;                    // agentId => Agent
    mapping(uint256 => uint64) internal _generations;              // relationshipId => next generation
    mapping(uint256 => uint256) internal _currentAgent;            // relationshipId => latest agentId
    mapping(uint256 => mapping(address => bool)) internal _member; // agentId => member => bool
    mapping(uint256 => mapping(address => bool)) internal _accepted;
    mapping(uint256 => uint16) internal _acceptCount;

    mapping(uint256 => Record[]) internal _records;
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) internal _coSigned;

    mapping(uint256 => mapping(address => mapping(bytes32 => Delegation))) internal _delegations;
    mapping(uint256 => mapping(address => mapping(bytes32 => mapping(address => bool)))) internal _delegationConfirmed;

    mapping(uint256 => uint64) internal _pausedAt;
    mapping(uint256 => address) internal _pausedBy;
    mapping(uint256 => mapping(address => bool)) internal _resumeAcked;
    mapping(uint256 => uint16) internal _resumeAckCount;

    mapping(address => uint256[]) internal _agentsOf;

    modifier onlyMember(uint256 agentId) {
        require(_member[agentId][msg.sender], "not a member");
        _;
    }

    // ------------------------------------------------------------------
    // Identity
    // ------------------------------------------------------------------

    function relationshipIdOf(address[] calldata members, bool directed) public pure returns (uint256) {
        uint256 n = members.length;
        require(n >= 2, "min two members");
        if (directed) {
            require(n == 2, "directed is pairs-only");
            require(members[0] != address(0) && members[1] != address(0), "zero address");
            require(members[0] != members[1], "distinct members");
            return uint256(keccak256(abi.encode(uint8(1), members[0], members[1])));
        }
        require(n <= MAX_MEMBERS, "too many members");
        require(members[0] != address(0), "zero address");
        for (uint256 i = 1; i < n; i++) {
            require(members[i] > members[i - 1], "not strictly ascending");
        }
        return uint256(keccak256(abi.encode(uint8(0), members)));
    }

    function agentIdOf(uint256 relationshipId, uint64 generation) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(relationshipId, uint256(generation))));
    }

    function currentAgentOf(uint256 relationshipId) external view returns (uint256) {
        return _currentAgent[relationshipId];
    }

    function generationOf(uint256 relationshipId) external view returns (uint64) {
        return _generations[relationshipId];
    }

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    function proposeAgent(
        address[] calldata members,
        bool directed,
        string calldata metadataURI,
        uint64 reconsentPeriod
    ) external returns (uint256 agentId) {
        uint256 relationshipId = relationshipIdOf(members, directed);
        uint256 predecessorAgentId = _currentAgent[relationshipId];
        if (predecessorAgentId != 0) {
            require(_agents[predecessorAgentId].status == Status.Dissolved, "current agent not dissolved");
        }
        uint64 generation = _generations[relationshipId];
        _generations[relationshipId] = generation + 1;
        agentId = agentIdOf(relationshipId, generation);
        _currentAgent[relationshipId] = agentId;

        bool senderIsMember;
        for (uint256 i = 0; i < members.length; i++) {
            _member[agentId][members[i]] = true;
            _agentsOf[members[i]].push(agentId);
            if (members[i] == msg.sender) senderIsMember = true;
        }
        require(senderIsMember, "proposer not in member set");

        Agent storage a = _agents[agentId];
        a.members = members;
        a.directed = directed;
        a.status = Status.Proposed;
        a.metadataURI = metadataURI;
        a.createdAt = uint64(block.timestamp);
        a.reconsentPeriod = reconsentPeriod;
        a.predecessorAgentId = predecessorAgentId;

        _accepted[agentId][msg.sender] = true;
        _acceptCount[agentId] = 1;

        emit AgentProposed(agentId, msg.sender, members, directed);
    }

    function acceptAgent(uint256 agentId) external onlyMember(agentId) {
        Agent storage a = _agents[agentId];
        require(a.status == Status.Proposed, "not proposed");
        require(!_accepted[agentId][msg.sender], "already accepted");
        _accepted[agentId][msg.sender] = true;
        _acceptCount[agentId] += 1;
        emit AgentAccepted(agentId, msg.sender);
        if (_acceptCount[agentId] == a.members.length) {
            a.status = Status.Active;
            emit AgentActivated(agentId);
        }
    }

    function pauseAgent(uint256 agentId) external onlyMember(agentId) {
        Agent storage a = _agents[agentId];
        require(a.status == Status.Active, "not active");
        a.status = Status.Paused;
        _pausedAt[agentId] = uint64(block.timestamp);
        _pausedBy[agentId] = msg.sender;
        _resumeAckCount[agentId] = 0;
        for (uint256 i = 0; i < a.members.length; i++) {
            _resumeAcked[agentId][a.members[i]] = false;
        }
        emit AgentPaused(agentId, msg.sender);
    }

    function resumeAgent(uint256 agentId) external onlyMember(agentId) {
        Agent storage a = _agents[agentId];
        require(a.status == Status.Paused, "not paused");
        bool longPause = uint64(block.timestamp) - _pausedAt[agentId] > a.reconsentPeriod;
        if (!longPause) {
            a.status = Status.Active;
            emit AgentResumed(agentId);
            return;
        }
        // long pause: every member other than the pauser must re-acknowledge
        require(msg.sender != _pausedBy[agentId], "pauser cannot re-consent");
        require(!_resumeAcked[agentId][msg.sender], "already acked");
        _resumeAcked[agentId][msg.sender] = true;
        _resumeAckCount[agentId] += 1;
        if (_resumeAckCount[agentId] == a.members.length - 1) {
            a.status = Status.Active;
            emit AgentResumed(agentId);
        }
    }

    function leaveAgent(uint256 agentId) external onlyMember(agentId) {
        emit AgentLeft(agentId, msg.sender);
        _dissolve(agentId, msg.sender);
    }

    function dissolveAgent(uint256 agentId) external onlyMember(agentId) {
        _dissolve(agentId, msg.sender);
    }

    function _dissolve(uint256 agentId, address by) internal {
        Agent storage a = _agents[agentId];
        require(
            a.status == Status.Proposed || a.status == Status.Active || a.status == Status.Paused,
            "not dissolvable"
        );
        a.status = Status.Dissolved;
        emit AgentDissolved(agentId, by);
        // Delegations are implicitly revoked: _authorized checks status.
    }

    // ------------------------------------------------------------------
    // Shared Record Corpus
    // ------------------------------------------------------------------

    function appendRecord(uint256 agentId, RecordType recordType, bytes32 contentHash, string calldata uri)
        external returns (uint256 recordIndex)
    {
        require(_agents[agentId].status == Status.Active, "not active");
        require(
            _member[agentId][msg.sender] || _authorized(agentId, msg.sender, SRC_APPEND),
            "not member or SRC_APPEND operator"
        );
        recordIndex = _records[agentId].length;
        _records[agentId].push(Record({
            recordType: recordType,
            contentHash: contentHash,
            uri: uri,
            contributor: msg.sender,
            timestamp: uint64(block.timestamp),
            coSignCount: 0
        }));
        emit RecordAppended(agentId, recordIndex, recordType, contentHash, msg.sender);
    }

    function coSignRecord(uint256 agentId, uint256 recordIndex) external onlyMember(agentId) {
        require(recordIndex < _records[agentId].length, "no such record");
        Record storage r = _records[agentId][recordIndex];
        require(msg.sender != r.contributor, "contributor cannot co-sign");
        require(!_coSigned[agentId][recordIndex][msg.sender], "already co-signed");
        _coSigned[agentId][recordIndex][msg.sender] = true;
        r.coSignCount += 1;
        emit RecordCoSigned(agentId, recordIndex, msg.sender);
    }

    function recordCount(uint256 agentId) external view returns (uint256) {
        return _records[agentId].length;
    }

    function getRecord(uint256 agentId, uint256 recordIndex) external view returns (Record memory) {
        require(recordIndex < _records[agentId].length, "no such record");
        return _records[agentId][recordIndex];
    }

    function hasCoSigned(uint256 agentId, uint256 recordIndex, address member) external view returns (bool) {
        return _coSigned[agentId][recordIndex][member];
    }

    // ------------------------------------------------------------------
    // Delegation: all-keys grant, single-key revoke
    // ------------------------------------------------------------------

    function delegate(uint256 agentId, address operator, bytes32 scope, uint64 expiry) external onlyMember(agentId) {
        Agent storage a = _agents[agentId];
        require(a.status == Status.Active, "not active");
        require(operator != address(0) && expiry > block.timestamp, "bad params");
        Delegation storage d = _delegations[agentId][operator][scope];
        if (d.pendingExpiry != expiry) {
            // new grant round: reset confirmations
            d.pendingExpiry = expiry;
            d.confirmations = 0;
            for (uint256 i = 0; i < a.members.length; i++) {
                _delegationConfirmed[agentId][operator][scope][a.members[i]] = false;
            }
        }
        require(!_delegationConfirmed[agentId][operator][scope][msg.sender], "already confirmed");
        _delegationConfirmed[agentId][operator][scope][msg.sender] = true;
        d.confirmations += 1;
        if (d.confirmations == a.members.length) {
            d.expiry = expiry;
            d.pendingExpiry = 0;
            emit DelegationSet(agentId, operator, scope, expiry);
        }
    }

    function revokeDelegation(uint256 agentId, address operator, bytes32 scope) external onlyMember(agentId) {
        Delegation storage d = _delegations[agentId][operator][scope];
        d.expiry = 0;
        d.pendingExpiry = 0;
        d.confirmations = 0;
        emit DelegationRevoked(agentId, operator, scope);
    }

    function isAuthorized(uint256 agentId, address operator, bytes32 scope) external view returns (bool) {
        return _authorized(agentId, operator, scope);
    }

    function _authorized(uint256 agentId, address operator, bytes32 scope) internal view returns (bool) {
        if (_agents[agentId].status != Status.Active) return false;
        return _delegations[agentId][operator][scope].expiry > block.timestamp;
    }

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------

    function getAgent(uint256 agentId) external view returns (Agent memory) {
        return _agents[agentId];
    }

    function memberCount(uint256 agentId) external view returns (uint256) {
        return _agents[agentId].members.length;
    }

    function isMember(uint256 agentId, address human) external view returns (bool) {
        return _member[agentId][human];
    }

    function agentsOf(address human) external view returns (uint256[] memory) {
        return _agentsOf[human];
    }
}
