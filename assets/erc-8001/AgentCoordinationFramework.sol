// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

interface IAgentCoordinationCore {
    event CoordinationProposed(bytes32 indexed intentHash, address indexed proposer, bytes32 coordinationType);
    event CoordinationAccepted(bytes32 indexed intentHash, address indexed participant, bytes32 acceptanceHash);
    event CoordinationExecuted(bytes32 indexed intentHash, address indexed executor, bool success, uint256 gasUsed);
    event CoordinationCancelled(bytes32 indexed intentHash, address indexed canceller, string reason);

    struct AgentIntent {
        bytes32 payloadHash;
        uint64  expiry;
        uint64  nonce;
        uint32  chainId;
        address agentId;
        bytes32 coordinationType;
        uint256 maxGasCost;
        uint8   priority;
        bytes32 dependencyHash;
        uint8   securityLevel;
        address[] participants;
        uint256 coordinationValue;
    }

    struct CoordinationPayload {
        bytes32 version;
        bytes32 coordinationType;
        bytes   coordinationData;
        bytes32 conditionsHash;
        uint256 timestamp;
        bytes   metadata;
    }

    function proposeCoordination(AgentIntent calldata intent, bytes calldata signature, CoordinationPayload calldata payload)
        external returns (bytes32 intentHash);

    function acceptCoordination(bytes32 intentHash, bytes calldata acceptanceSignature) external returns (bool);

    function executeCoordination(bytes32 intentHash, CoordinationPayload calldata payload, bytes calldata executionData)
        external returns (bool success, bytes memory result);

    function cancelCoordination(bytes32 intentHash, string calldata reason) external;

    function getCoordinationStatus(bytes32 intentHash) external view returns (uint8 status, address[] memory acceptedBy);
}

contract AgentCoordinationFramework is IAgentCoordinationCore {
    function _payloadHash(CoordinationPayload calldata p) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            p.version,
            p.coordinationType,
            p.coordinationData,
            p.conditionsHash,
            p.timestamp,
            p.metadata
        ));
    }

    struct State {
        address proposer;
        bytes32 payloadHash;
        uint8   status; // 0 proposed, 1 ready, 2 executed, 3 cancelled
        mapping(address => bool) accepted;
        address[] participants;
    }

    mapping(bytes32 => State) private _coordinations;

    function _hashIntent(AgentIntent calldata intent) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            intent.payloadHash,
            intent.expiry,
            intent.nonce,
            intent.chainId,
            intent.agentId,
            intent.coordinationType,
            intent.maxGasCost,
            intent.priority,
            intent.dependencyHash,
            intent.securityLevel,
            keccak256(abi.encodePacked(intent.participants)),
            intent.coordinationValue
        ));
    }

    function proposeCoordination(AgentIntent calldata intent, bytes calldata, CoordinationPayload calldata payload)
        external override returns (bytes32 intentHash)
    {
        require(intent.expiry > block.timestamp, "expired");
        require(intent.chainId == block.chainid, "chain");
        require(intent.coordinationType == payload.coordinationType, "type");

        intentHash = _hashIntent(intent);
        State storage s = _coordinations[intentHash];
        require(s.proposer == address(0), "exists");
        s.proposer = intent.agentId;
        s.payloadHash = _payloadHash(payload);
        s.status = 0;
        s.participants = intent.participants;
        emit CoordinationProposed(intentHash, intent.agentId, intent.coordinationType);
    }

    function acceptCoordination(bytes32 intentHash, bytes calldata) external override returns (bool) {
        State storage s = _coordinations[intentHash];
        require(s.proposer != address(0), "missing");
        // For skeleton: allow any address to accept if listed as participant.
        bool ok;
        for (uint i = 0; i < s.participants.length; i++) {
            if (s.participants[i] == msg.sender) { ok = true; break; }
        }
        require(ok, "not participant");
        s.accepted[msg.sender] = true;
        bytes32 accHash = keccak256(abi.encodePacked(intentHash, msg.sender, block.number));
        emit CoordinationAccepted(intentHash, msg.sender, accHash);
        return true;
    }

    function executeCoordination(bytes32 intentHash, CoordinationPayload calldata payload, bytes calldata)
        external override returns (bool success, bytes memory result)
    {
        State storage s = _coordinations[intentHash];
        require(s.proposer != address(0), "missing");
        require(s.status < 2, "done");
        require(_payloadHash(payload) == s.payloadHash, "payload");
        // Minimal execution stub
        s.status = 2;
        emit CoordinationExecuted(intentHash, msg.sender, true, 0);
        return (true, payload.coordinationData);
    }

    function cancelCoordination(bytes32 intentHash, string calldata reason) external override {
        State storage s = _coordinations[intentHash];
        require(s.proposer != address(0), "missing");
        require(s.status < 2, "done");
        s.status = 3;
        emit CoordinationCancelled(intentHash, msg.sender, reason);
    }

    function getCoordinationStatus(bytes32 intentHash) external view override returns (uint8 status, address[] memory acceptedBy) {
        State storage s = _coordinations[intentHash];
        status = s.status;
        // Build accepted list
        uint count;
        for (uint i = 0; i < s.participants.length; i++) {
            if (s.accepted[s.participants[i]]) { count++; }
        }
        acceptedBy = new address[](count);
        uint idx;
        for (uint i = 0; i < s.participants.length; i++) {
            if (s.accepted[s.participants[i]]) { acceptedBy[idx++] = s.participants[i]; }
        }
    }
}
