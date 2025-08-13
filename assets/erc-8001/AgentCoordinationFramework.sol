// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

interface IAgentCoordinationCore {
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

    struct AcceptanceAttestation {
        bytes32 intentHash;
        address participant;
        uint64  nonce;
        uint64  expiry;
        bytes32 conditionsHash;
        bytes   signature;
    }

    event CoordinationProposed(bytes32 indexed intentHash, address indexed proposer, bytes32 coordinationType, uint256 participantCount, uint256 coordinationValue);
    event CoordinationAccepted(bytes32 indexed intentHash, address indexed participant, bytes32 acceptanceHash, uint256 acceptedCount, uint256 requiredCount);
    event CoordinationExecuted(bytes32 indexed intentHash, address indexed executor, bool success, uint256 gasUsed, bytes result);
    event CoordinationCancelled(bytes32 indexed intentHash, address indexed canceller, string reason, uint8 finalStatus);
    event AgentNonceUpdated(address indexed agent, uint64 newNonce);

    function proposeCoordination(AgentIntent calldata intent, bytes calldata signature, CoordinationPayload calldata payload)
    external returns (bytes32 intentHash);

    function acceptCoordination(bytes32 intentHash, AcceptanceAttestation calldata attestation) external returns (bool);

    function executeCoordination(bytes32 intentHash, CoordinationPayload calldata payload, bytes calldata executionData)
    external returns (bool success, bytes memory result);

    function cancelCoordination(bytes32 intentHash, string calldata reason) external;

    function getCoordinationStatus(bytes32 intentHash) external view returns (
        uint8 status,
        address proposer,
        address[] memory participants,
        address[] memory acceptedBy,
        uint256 expiry
    );

    function validateIntent(AgentIntent calldata intent, bytes calldata signature) external view returns (bool valid, string memory reason);
    function getAgentNonce(address agent) external view returns (uint64);
    function getRequiredAcceptances(bytes32 intentHash) external view returns (uint256);
}

contract AgentCoordinationFramework is IAgentCoordinationCore {
    // EIP-712 Domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant AGENT_INTENT_TYPEHASH = keccak256("AgentIntent(bytes32 payloadHash,uint64 expiry,uint64 nonce,uint32 chainId,address agentId,bytes32 coordinationType,uint256 maxGasCost,uint8 priority,bytes32 dependencyHash,uint8 securityLevel,bytes32 participantsHash,uint256 coordinationValue)");
    bytes32 public constant ACCEPTANCE_TYPEHASH = keccak256("AcceptanceAttestation(bytes32 intentHash,address participant,uint64 nonce,uint64 expiry,bytes32 conditionsHash)");

    bytes32 public immutable DOMAIN_SEPARATOR;

    struct CoordinationState {
        address proposer;
        bytes32 payloadHash;
        uint8   status; // 0=PROPOSED, 1=READY, 2=EXECUTED, 3=CANCELLED, 4=EXPIRED
        uint64  expiry;
        address[] participants;
        mapping(address => bool) accepted;
        uint256 acceptedCount;
        uint8   securityLevel;
        uint256 coordinationValue;
    }

    mapping(bytes32 => CoordinationState) private _coordinations;
    mapping(address => uint64) public agentNonces;

    modifier nonReentrant() {
        require(!_locked, "Reentrant call");
        _locked = true;
        _;
        _locked = false;
    }
    bool private _locked;

    constructor() {
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            DOMAIN_TYPEHASH,
            keccak256("AgentCoordinationFramework"),
            keccak256("1"),
            block.chainid,
            address(this)
        ));
    }

    function proposeCoordination(AgentIntent calldata intent, bytes calldata signature, CoordinationPayload calldata payload)
    external override nonReentrant returns (bytes32 intentHash)
    {
        // Validate intent structure
        require(intent.expiry > block.timestamp, "Intent expired");
        require(intent.chainId == block.chainid, "Invalid chain ID");
        require(intent.participants.length > 0, "No participants");
        require(intent.coordinationType == payload.coordinationType, "Type mismatch");
        require(intent.nonce > agentNonces[intent.agentId], "Invalid nonce");

        // Validate payload hash
        bytes32 computedPayloadHash = getPayloadHash(payload);
        require(intent.payloadHash == computedPayloadHash, "Payload hash mismatch");

        // Verify proposer is in participants list
        bool proposerInList = false;
        for (uint256 i = 0; i < intent.participants.length; i++) {
            if (intent.participants[i] == intent.agentId) {
                proposerInList = true;
                break;
            }
        }
        require(proposerInList, "Proposer not in participants");

        // Verify signature
        intentHash = getIntentHash(intent);
        require(verifyIntentSignature(intentHash, signature, intent.agentId), "Invalid signature");

        // Store coordination state
        CoordinationState storage state = _coordinations[intentHash];
        require(state.proposer == address(0), "Coordination exists");

        state.proposer = intent.agentId;
        state.payloadHash = computedPayloadHash;
        state.status = 0; // PROPOSED
        state.expiry = intent.expiry;
        state.participants = intent.participants;
        state.securityLevel = intent.securityLevel;
        state.coordinationValue = intent.coordinationValue;

        // Update nonce
        agentNonces[intent.agentId] = intent.nonce;
        emit AgentNonceUpdated(intent.agentId, intent.nonce);

        emit CoordinationProposed(intentHash, intent.agentId, intent.coordinationType, intent.participants.length, intent.coordinationValue);

        return intentHash;
    }

    function acceptCoordination(bytes32 intentHash, AcceptanceAttestation calldata attestation)
    external override nonReentrant returns (bool)
    {
        CoordinationState storage state = _coordinations[intentHash];
        require(state.proposer != address(0), "Coordination not found");
        require(state.status == 0, "Invalid status");
        require(block.timestamp <= state.expiry, "Coordination expired");
        require(attestation.intentHash == intentHash, "Intent hash mismatch");
        require(attestation.expiry > block.timestamp, "Acceptance expired");

        // Verify participant is in list
        bool isParticipant = false;
        for (uint256 i = 0; i < state.participants.length; i++) {
            if (state.participants[i] == attestation.participant) {
                isParticipant = true;
                break;
            }
        }
        require(isParticipant, "Not a participant");
        require(!state.accepted[attestation.participant], "Already accepted");

        // Verify acceptance signature
        bytes32 acceptanceHash = getAcceptanceHash(attestation);
        require(verifyAcceptanceSignature(acceptanceHash, attestation.signature, attestation.participant), "Invalid acceptance signature");

        // Record acceptance
        state.accepted[attestation.participant] = true;
        state.acceptedCount++;

        bytes32 acceptanceCommitment = keccak256(abi.encodePacked(intentHash, attestation.participant, block.number));

        emit CoordinationAccepted(intentHash, attestation.participant, acceptanceCommitment, state.acceptedCount, state.participants.length);

        // Check if all participants have accepted
        bool allAccepted = (state.acceptedCount == state.participants.length);
        if (allAccepted) {
            state.status = 1; // READY
        }

        return allAccepted;
    }

    function executeCoordination(bytes32 intentHash, CoordinationPayload calldata payload, bytes calldata executionData)
    external override nonReentrant returns (bool success, bytes memory result)
    {
        CoordinationState storage state = _coordinations[intentHash];
        require(state.proposer != address(0), "Coordination not found");
        require(state.status == 1, "Not ready for execution");
        require(block.timestamp <= state.expiry, "Coordination expired");

        // Verify payload
        bytes32 computedPayloadHash = getPayloadHash(payload);
        require(state.payloadHash == computedPayloadHash, "Payload hash mismatch");

        // Execute coordination logic
        uint256 gasStart = gasleft();

        // Basic execution - can be extended by modules
        state.status = 2; // EXECUTED
        success = true;
        result = payload.coordinationData;

        uint256 gasUsed = gasStart - gasleft();

        emit CoordinationExecuted(intentHash, msg.sender, success, gasUsed, result);

        return (success, result);
    }

    function cancelCoordination(bytes32 intentHash, string calldata reason) external override nonReentrant {
        CoordinationState storage state = _coordinations[intentHash];
        require(state.proposer != address(0), "Coordination not found");
        require(state.status < 2, "Already executed");
        require(msg.sender == state.proposer || block.timestamp > state.expiry, "Not authorized");

        uint8 finalStatus = block.timestamp > state.expiry ? 4 : 3; // EXPIRED : CANCELLED
        state.status = finalStatus;

        emit CoordinationCancelled(intentHash, msg.sender, reason, finalStatus);
    }

    function getCoordinationStatus(bytes32 intentHash) external view override returns (
        uint8 status,
        address proposer,
        address[] memory participants,
        address[] memory acceptedBy,
        uint256 expiry
    ) {
        CoordinationState storage state = _coordinations[intentHash];
        status = state.status;
        proposer = state.proposer;
        participants = state.participants;
        expiry = state.expiry;

        // Build accepted participants list
        uint256 acceptedCount = 0;
        for (uint256 i = 0; i < state.participants.length; i++) {
            if (state.accepted[state.participants[i]]) {
                acceptedCount++;
            }
        }

        acceptedBy = new address[](acceptedCount);
        uint256 index = 0;
        for (uint256 i = 0; i < state.participants.length; i++) {
            if (state.accepted[state.participants[i]]) {
                acceptedBy[index++] = state.participants[i];
            }
        }
    }

    function validateIntent(AgentIntent calldata intent, bytes calldata signature)
    external view override returns (bool valid, string memory reason)
    {
        if (intent.expiry <= block.timestamp) {
            return (false, "Intent expired");
        }

        if (intent.chainId != block.chainid) {
            return (false, "Invalid chain ID");
        }

        if (intent.nonce <= agentNonces[intent.agentId]) {
            return (false, "Invalid nonce");
        }

        if (intent.participants.length == 0) {
            return (false, "No participants");
        }

        bytes32 intentHash = getIntentHash(intent);
        if (!verifyIntentSignature(intentHash, signature, intent.agentId)) {
            return (false, "Invalid signature");
        }

        return (true, "");
    }

    function getAgentNonce(address agent) external view override returns (uint64) {
        return agentNonces[agent];
    }

    function getRequiredAcceptances(bytes32 intentHash) external view override returns (uint256) {
        return _coordinations[intentHash].participants.length;
    }

    function getDomainSeparator() external view returns (bytes32) {
        return DOMAIN_SEPARATOR;
    }

    function getIntentHash(AgentIntent calldata intent) public pure returns (bytes32) {
        return keccak256(abi.encode(
            AGENT_INTENT_TYPEHASH,
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

    function getPayloadHash(CoordinationPayload calldata payload) public pure returns (bytes32) {
        return keccak256(abi.encode(
            payload.version,
            payload.coordinationType,
            payload.coordinationData,
            payload.conditionsHash,
            payload.timestamp,
            payload.metadata
        ));
    }

    function getAcceptanceHash(AcceptanceAttestation calldata attestation) public pure returns (bytes32) {
        return keccak256(abi.encode(
            ACCEPTANCE_TYPEHASH,
            attestation.intentHash,
            attestation.participant,
            attestation.nonce,
            attestation.expiry,
            attestation.conditionsHash
        ));
    }

    function verifyIntentSignature(bytes32 intentHash, bytes calldata signature, address expectedSigner)
    public view returns (bool)
    {
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, intentHash));
        return recoverSigner(digest, signature) == expectedSigner;
    }

    function verifyAcceptanceSignature(bytes32 acceptanceHash, bytes calldata signature, address expectedSigner)
    public view returns (bool)
    {
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, acceptanceHash));
        return recoverSigner(digest, signature) == expectedSigner;
    }

    function recoverSigner(bytes32 digest, bytes calldata signature) internal pure returns (address) {
        require(signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        return ecrecover(digest, v, r, s);
    }
}