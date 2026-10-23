// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IAgentCoordination, Status} from "./IAgentCoordination.sol";
import {IERC1271} from "./interfaces/IERC1271.sol";
import {ECDSA} from "./utils/ECDSA.sol";

/**
 * @title AgentCoordination
 */
contract AgentCoordination is IAgentCoordination {
    using ECDSA for bytes32;

    // ============ Constants ============

    bytes32 public constant DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 public constant AGENT_INTENT_TYPEHASH = keccak256(
        "AgentIntent(bytes32 payloadHash,uint64 expiry,uint64 nonce,address agentId,bytes32 coordinationType,uint256 coordinationValue,address[] participants)"
    );

    bytes32 public constant ACCEPTANCE_TYPEHASH = keccak256(
        "AcceptanceAttestation(bytes32 intentHash,address participant,uint64 nonce,uint64 expiry,bytes32 conditionsHash)"
    );

    /// @notice Domain name used in EIP-712 signatures
    string public constant DOMAIN_NAME = "ERC-8001-Core";

    /// @notice Domain version
    string public constant DOMAIN_VERSION = "1";

    /// @notice Maximum participants per coordination (prevents DoS)
    uint256 public constant MAX_PARTICIPANTS = 32;

    // ============ Immutables ============

    bytes32 public immutable DOMAIN_SEPARATOR;

    // ============ Storage ============

    // Note: Status enum is defined at file level in IAgentCoordination.sol
    // Status { None, Proposed, Ready, Executed, Cancelled, Expired }

    struct CoordinationState {
        address proposer;
        bytes32 payloadHash;
        Status status; // 0=PROPOSED,1=READY,2=EXECUTED,3=CANCELLED,4=EXPIRED
        uint64 expiry;
        uint64 minAcceptanceExpiry; // Track earliest acceptance expiry
        address[] participants;
        mapping(address => bool) accepted;
        mapping(address => uint64) acceptanceExpiry;
        uint256 acceptedCount;
        uint256 coordinationValue;
    }

    /// @notice Nonce tracking per agent for replay protection
    mapping(address => uint64) public agentNonces;

    /// @notice Intent hash to coordination state
    mapping(bytes32 => CoordinationState) private states;

    /// @notice Reentrancy lock
    bool private _locked;

    // ============ Events ============

    /// @notice Emitted when coordination reaches READY status
    event CoordinationReady(bytes32 indexed intentHash, uint256 participantCount, uint64 minAcceptanceExpiry);

    // ============ Modifiers ============

    modifier nonReentrant() {
        require(!_locked, "Reentrant");
        _locked = true;
        _;
        _locked = false;
    }

    // ============ Constructor ============

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(DOMAIN_NAME)),
                keccak256(bytes(DOMAIN_VERSION)),
                block.chainid,
                address(this)
            )
        );
    }

    // ============ Internal Utilities ============

    /**
     * @notice Binary search for address in sorted array
     * @dev O(log n) complexity, requires array to be sorted ascending
     * @param arr Sorted array of addresses
     * @param target Address to find
     * @return found Whether the address was found
     * @return index Index of the address (only valid if found)
     */
    function _binarySearch(address[] memory arr, address target) internal pure returns (bool found, uint256 index) {
        if (arr.length == 0) return (false, 0);

        uint256 low = 0;
        uint256 high = arr.length - 1;

        while (low <= high) {
            uint256 mid = low + (high - low) / 2;
            address midVal = arr[mid];

            if (midVal == target) {
                return (true, mid);
            } else if (midVal < target) {
                low = mid + 1;
            } else {
                if (mid == 0) break;
                high = mid - 1;
            }
        }

        return (false, 0);
    }

    /**
     * @notice Verify array is sorted ascending with unique elements
     * @dev O(n) but only called once during proposal
     */
    function _isSortedUnique(address[] memory a) internal pure returns (bool) {
        if (a.length == 0) return false;
        for (uint256 i = 1; i < a.length; i++) {
            if (a[i] <= a[i - 1]) return false;
        }
        return true;
    }

    /**
     * @notice Verify signature from EOA or ERC-1271 contract
     */
    function _isValidSig(address signer, bytes32 digest, bytes memory signature) internal view returns (bool) {
        if (signer.code.length == 0) {
            // EOA verification
            (address recovered, ECDSA.RecoverError err) = digest.tryRecover(signature);
            return err == ECDSA.RecoverError.NoError && recovered == signer;
        } else {
            // ERC-1271 smart contract wallet
            try IERC1271(signer).isValidSignature(digest, signature) returns (bytes4 magic) {
                return magic == IERC1271.isValidSignature.selector;
            } catch {
                return false;
            }
        }
    }

    // ============ EIP-712 Introspection ============

    /**
     * @notice EIP-5267 domain introspection
     * @dev Domain name now matches DOMAIN_SEPARATOR construction
     */
    function eip712Domain()
    external
    view
    returns (
        bytes1 fields,
        string memory name,
        string memory version,
        uint256 chainId,
        address verifyingContract,
        bytes32 salt,
        uint256[] memory extensions
    )
    {
        fields = 0x0f; // name, version, chainId, verifyingContract
        name = DOMAIN_NAME;
        version = DOMAIN_VERSION;
        chainId = block.chainid;
        verifyingContract = address(this);
        salt = bytes32(0);
        extensions = new uint256[](0);
    }

    function getDomainSeparator() external view returns (bytes32) {
        return DOMAIN_SEPARATOR;
    }

    function getTypedDataDigest(bytes32 structHash) public view returns (bytes32) {
        return keccak256(abi.encodePacked(hex"1901", DOMAIN_SEPARATOR, structHash));
    }

    // ============ Hash Builders ============

    function getIntentHash(AgentIntent calldata intent) public pure returns (bytes32) {
        bytes32 participantsHash = keccak256(abi.encodePacked(intent.participants));
        return keccak256(
            abi.encode(
                AGENT_INTENT_TYPEHASH,
                intent.payloadHash,
                intent.expiry,
                intent.nonce,
                intent.agentId,
                intent.coordinationType,
                intent.coordinationValue,
                participantsHash
            )
        );
    }

    function getAcceptanceHash(AcceptanceAttestation calldata att) public pure returns (bytes32) {
        return keccak256(
            abi.encode(ACCEPTANCE_TYPEHASH, att.intentHash, att.participant, att.nonce, att.expiry, att.conditionsHash)
        );
    }

    function getPayloadHash(CoordinationPayload calldata payload) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                payload.version,
                payload.coordinationType,
                payload.coordinationData,
                payload.conditionsHash,
                payload.timestamp,
                payload.metadata
            )
        );
    }

    // ============ Core Functions ============

    function proposeCoordination(
        AgentIntent calldata intent,
        bytes calldata signature,
        CoordinationPayload calldata payload
    ) external nonReentrant returns (bytes32 intentHash) {
        // Validate timing
        require(intent.expiry > block.timestamp, "Intent expired");

        // Validate participants
        require(intent.participants.length > 0, "No participants");
        require(intent.participants.length <= MAX_PARTICIPANTS, "Too many participants");
        require(_isSortedUnique(intent.participants), "Participants not canonical");

        // Verify proposer is participant using binary search
        (bool isParticipant,) = _binarySearch(intent.participants, intent.agentId);
        require(isParticipant, "Proposer not participant");

        // Validate payload consistency
        require(payload.coordinationType == intent.coordinationType, "Type mismatch");
        bytes32 pHash = getPayloadHash(payload);
        require(pHash == intent.payloadHash, "Payload hash mismatch");

        // Validate nonce
        require(intent.nonce > agentNonces[intent.agentId], "Nonce not strictly increasing");

        // Compute and verify intent signature
        intentHash = getIntentHash(intent);
        bytes32 digest = getTypedDataDigest(intentHash);
        require(_isValidSig(intent.agentId, digest, signature), "Bad intent signature");

        // Check intent doesn't already exist
        CoordinationState storage st = states[intentHash];
        require(st.proposer == address(0), "Intent exists");

        // Initialize state
        st.proposer = intent.agentId;
        st.payloadHash = pHash;
        st.status = Status.Proposed;
        st.expiry = intent.expiry;
        st.participants = intent.participants;
        st.coordinationValue = intent.coordinationValue;
        st.minAcceptanceExpiry = type(uint64).max; // Will be updated on acceptances

        // Update nonce
        agentNonces[intent.agentId] = intent.nonce;

        emit CoordinationProposed(
            intentHash, intent.agentId, intent.coordinationType, intent.participants.length, intent.coordinationValue
        );
    }

    function acceptCoordination(bytes32 intentHash, AcceptanceAttestation calldata attestation)
    external
    nonReentrant
    returns (bool allAccepted)
    {
        CoordinationState storage st = states[intentHash];

        // Validate state
        require(st.proposer != address(0), "Unknown intent");
        require(st.status == Status.Proposed, "Not proposed");
        require(block.timestamp <= st.expiry, "Intent expired");

        // Validate attestation
        require(attestation.intentHash == intentHash, "Intent hash mismatch");
        require(attestation.expiry > block.timestamp, "Acceptance expired");

        // Verify participant using binary search
        (bool isParticipant,) = _binarySearch(st.participants, attestation.participant);
        require(isParticipant, "Not participant");
        require(!st.accepted[attestation.participant], "Already accepted");

        // Verify signature
        bytes32 aHash = getAcceptanceHash(attestation);
        bytes32 digest = getTypedDataDigest(aHash);
        require(_isValidSig(attestation.participant, digest, attestation.signature), "Bad acceptance signature");

        // Record acceptance
        st.accepted[attestation.participant] = true;
        st.acceptanceExpiry[attestation.participant] = attestation.expiry;
        st.acceptedCount += 1;

        // Track minimum acceptance expiry
        if (attestation.expiry < st.minAcceptanceExpiry) {
            st.minAcceptanceExpiry = attestation.expiry;
        }

        emit CoordinationAccepted(intentHash, attestation.participant, aHash, st.acceptedCount, st.participants.length);

        // Check if all participants accepted
        if (st.acceptedCount == st.participants.length) {
            st.status = Status.Ready;
            emit CoordinationReady(intentHash, st.participants.length, st.minAcceptanceExpiry);
            return true;
        }

        return false;
    }

    function executeCoordination(bytes32 intentHash, CoordinationPayload calldata payload, bytes calldata executionData)
    external
    nonReentrant
    returns (bool success, bytes memory result)
    {
        CoordinationState storage st = states[intentHash];

        // Validate state
        require(st.proposer != address(0), "Unknown intent");
        require(st.status == Status.Ready, "Not ready");
        require(block.timestamp <= st.expiry, "Intent expired");

        // Verify payload
        bytes32 pHash = getPayloadHash(payload);
        require(pHash == st.payloadHash, "Payload hash mismatch");

        // Verify all acceptances are still valid
        // Use cached minAcceptanceExpiry for gas optimization
        require(block.timestamp <= st.minAcceptanceExpiry, "Acceptance expired");

        // Mark as executed before external calls (CEI pattern)
        st.status = Status.Executed;

        // Execute via virtual hook (extensions override this)
        uint256 gasStart = gasleft();
        (success, result) = _executeInternal(intentHash, payload, executionData, st);
        uint256 gasUsed = gasStart - gasleft();

        emit CoordinationExecuted(intentHash, msg.sender, success, gasUsed, result);
    }

    /**
     * @notice Internal execution hook for extensions to override
     * @dev Base implementation echoes coordinationData. Extensions should override
     *      to implement actual coordination logic (token transfers, swaps, etc.)
     * @param intentHash The intent being executed
     * @param payload The coordination payload
     * @param executionData Additional execution parameters
     * @param state Reference to coordination state
     * @return success Whether execution succeeded
     * @return result Execution result data
     */
    function _executeInternal(
        bytes32 intentHash,
        CoordinationPayload calldata payload,
        bytes calldata executionData,
        CoordinationState storage state
    ) internal virtual returns (bool success, bytes memory result) {
        // Silence unused variable warnings
        intentHash;
        executionData;
        state;

        // Base implementation: echo coordination data
        return (true, payload.coordinationData);
    }

    function cancelCoordination(bytes32 intentHash, string calldata reason) external nonReentrant {
        CoordinationState storage st = states[intentHash];

        require(st.proposer != address(0), "Unknown intent");
        require(st.status < Status.Executed, "Already executed");

        // Only proposer can cancel before expiry; anyone can clean up after
        require(msg.sender == st.proposer || block.timestamp > st.expiry, "Not authorised");

        Status finalStatus = block.timestamp > st.expiry ? Status.Expired : Status.Cancelled;
        st.status = finalStatus;

        emit CoordinationCancelled(intentHash, msg.sender, reason, uint8(finalStatus));
    }

    // ============ View Functions ============

    function getCoordinationStatus(bytes32 intentHash)
    external
    view
    returns (
        Status status,
        address proposer,
        address[] memory participants,
        address[] memory acceptedBy,
        uint256 expiry
    )
    {
        CoordinationState storage st = states[intentHash];

        status = st.status;
        proposer = st.proposer;
        participants = st.participants;
        expiry = st.expiry;

        // Build accepted array
        uint256 count = st.acceptedCount;
        acceptedBy = new address[](count);
        uint256 idx;
        for (uint256 i = 0; i < participants.length && idx < count; i++) {
            if (st.accepted[participants[i]]) {
                acceptedBy[idx++] = participants[i];
            }
        }
    }

    /**
     * @notice Get detailed coordination state including expiry info
     */
    function getCoordinationDetails(bytes32 intentHash)
    external
    view
    returns (
        Status status,
        address proposer,
        bytes32 payloadHash,
        uint64 intentExpiry,
        uint64 minAcceptanceExpiry,
        uint256 acceptedCount,
        uint256 totalParticipants,
        uint256 coordinationValue
    )
    {
        CoordinationState storage st = states[intentHash];

        return (
            st.status,
            st.proposer,
            st.payloadHash,
            st.expiry,
            st.minAcceptanceExpiry,
            st.acceptedCount,
            st.participants.length,
            st.coordinationValue
        );
    }

    function getRequiredAcceptances(bytes32 intentHash) external view returns (uint256) {
        return states[intentHash].participants.length;
    }

    function getAgentNonce(address agent) external view returns (uint64) {
        return agentNonces[agent];
    }

    /**
     * @notice Check if a participant has accepted
     */
    function hasAccepted(bytes32 intentHash, address participant) external view returns (bool) {
        return states[intentHash].accepted[participant];
    }

    /**
     * @notice Get acceptance expiry for a participant
     */
    function getAcceptanceExpiry(bytes32 intentHash, address participant) external view returns (uint64) {
        return states[intentHash].acceptanceExpiry[participant];
    }
}
