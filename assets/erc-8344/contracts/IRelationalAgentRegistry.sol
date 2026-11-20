// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

interface IRelationalAgentRegistry {
    enum Status { None, Proposed, Active, Paused, Dissolved }

    enum RecordType {
        MeetingNote,
        ChatHistory,
        Letter,
        Photo,
        Document,
        Transaction,
        Attestation,
        Other
    }

    struct Agent {
        address[] members;          // sorted ascending if undirected; [from, to] if directed
        bool directed;              // pairs only
        Status status;
        string metadataURI;         // agent card: model, prompt policy, capabilities
        uint64 createdAt;
        uint64 reconsentPeriod;     // seconds; see pause semantics
        uint256 predecessorAgentId; // 0 if none
    }

    struct Record {
        RecordType recordType;
        bytes32 contentHash;
        string uri;
        address contributor;
        uint64 timestamp;
        uint16 coSignCount;
    }

    // --- Lifecycle ---
    // A new generation is opened automatically; if a prior generation exists for
    // the same relationship it must be Dissolved, and predecessorAgentId is set to it.
    function proposeAgent(
        address[] calldata members,
        bool directed,
        string calldata metadataURI,
        uint64 reconsentPeriod
    ) external returns (uint256 agentId);
    function acceptAgent(uint256 agentId) external;
    function pauseAgent(uint256 agentId) external;
    function resumeAgent(uint256 agentId) external;
    function leaveAgent(uint256 agentId) external;
    function dissolveAgent(uint256 agentId) external;

    // --- Shared Record Corpus ---
    function appendRecord(uint256 agentId, RecordType recordType, bytes32 contentHash, string calldata uri)
        external returns (uint256 recordIndex);
    function coSignRecord(uint256 agentId, uint256 recordIndex) external;
    function recordCount(uint256 agentId) external view returns (uint256);
    function getRecord(uint256 agentId, uint256 recordIndex) external view returns (Record memory);
    function hasCoSigned(uint256 agentId, uint256 recordIndex, address member) external view returns (bool);

    // --- Delegation ---
    function delegate(uint256 agentId, address operator, bytes32 scope, uint64 expiry) external;
    function revokeDelegation(uint256 agentId, address operator, bytes32 scope) external;
    function isAuthorized(uint256 agentId, address operator, bytes32 scope) external view returns (bool);

    // --- Views ---
    function relationshipIdOf(address[] calldata members, bool directed) external pure returns (uint256);
    function agentIdOf(uint256 relationshipId, uint64 generation) external pure returns (uint256);
    function currentAgentOf(uint256 relationshipId) external view returns (uint256 agentId);
    function generationOf(uint256 relationshipId) external view returns (uint64);
    function getAgent(uint256 agentId) external view returns (Agent memory);
    function memberCount(uint256 agentId) external view returns (uint256);
    function isMember(uint256 agentId, address human) external view returns (bool);
    function agentsOf(address human) external view returns (uint256[] memory);

    // --- Events ---
    event AgentProposed(uint256 indexed agentId, address indexed proposer, address[] members, bool directed);
    event AgentAccepted(uint256 indexed agentId, address indexed by);
    event AgentActivated(uint256 indexed agentId);
    event AgentLeft(uint256 indexed agentId, address indexed by);
    event AgentPaused(uint256 indexed agentId, address by);
    event AgentResumed(uint256 indexed agentId);
    event AgentDissolved(uint256 indexed agentId, address by);
    event RecordAppended(uint256 indexed agentId, uint256 indexed recordIndex, RecordType recordType, bytes32 contentHash, address contributor);
    event RecordCoSigned(uint256 indexed agentId, uint256 indexed recordIndex, address by);
    event DelegationSet(uint256 indexed agentId, address indexed operator, bytes32 scope, uint64 expiry);
    event DelegationRevoked(uint256 indexed agentId, address indexed operator, bytes32 scope);
}
