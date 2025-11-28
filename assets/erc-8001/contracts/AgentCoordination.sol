// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IAgentCoordination} from "./IAgentCoordination.sol";
import {IERC1271} from "./interfaces/IERC1271.sol";
import {ECDSA} from "./utils/ECDSA.sol";

contract AgentCoordination is IAgentCoordination {
    using ECDSA for bytes32;

    // EIP-712
    bytes32 public constant DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant AGENT_INTENT_TYPEHASH = keccak256(
        "AgentIntent(bytes32 payloadHash,uint64 expiry,uint64 nonce,address agentId,bytes32 coordinationType,uint256 coordinationValue,address[] participants)"
    );
    bytes32 public constant ACCEPTANCE_TYPEHASH = keccak256(
        "AcceptanceAttestation(bytes32 intentHash,address participant,uint64 nonce,uint64 expiry,bytes32 conditionsHash)"
    );

    bytes32 public immutable DOMAIN_SEPARATOR;

    struct CoordinationState {
        address proposer;
        bytes32 payloadHash;
        uint8 status; // 0=PROPOSED,1=READY,2=EXECUTED,3=CANCELLED,4=EXPIRED
        uint64 expiry;
        address[] participants;
        mapping(address => bool) accepted;
        mapping(address => uint64) acceptanceExpiry;
        uint256 acceptedCount;
        uint256 coordinationValue;
    }

    mapping(address => uint64) public agentNonces;
    mapping(bytes32 => CoordinationState) private states;
    bool private _locked;

    modifier nonReentrant() {
        require(!_locked, "Reentrant");
        _locked = true;
        _;
        _locked = false;
    }

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256("ERC-8001-Core"), keccak256("1"), block.chainid, address(this))
        );
    }

    // Helpers
    function _isSortedUnique(address[] memory a) internal pure returns (bool) {
        if (a.length == 0) return false;
        for (uint256 i = 1; i < a.length; i++) {
            if (a[i] <= a[i - 1]) return false;
        }
        return true;
    }

    function _contains(address[] memory a, address x) internal pure returns (bool) {
        for (uint256 i = 0; i < a.length; i++) {
            if (a[i] == x) return true;
        }
        return false;
    }

    // Introspection
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
        // EIP-5267 minimal fields: name, version, chainId, verifyingContract
        fields = 0x0f;
        name = "ERC-8001";
        version = "1";
        chainId = block.chainid;
        verifyingContract = address(this);
        salt = 0x0;
        extensions = new uint256[](0);
    }

    function getDomainSeparator() external view returns (bytes32) {
        return DOMAIN_SEPARATOR;
    }

    function getTypedDataDigest(bytes32 structHash) public view returns (bytes32) {
        return keccak256(abi.encodePacked(hex"1901", DOMAIN_SEPARATOR, structHash));
    }

    // Hash builders
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

    // Verification
    function _isValidSig(address signer, bytes32 digest, bytes memory signature) internal view returns (bool) {
        if (signer.code.length == 0) {
            (address rec, ECDSA.RecoverError err) = digest.tryRecover(signature);
            return err == ECDSA.RecoverError.NoError && rec == signer;
        } else {
            try IERC1271(signer).isValidSignature(digest, signature) returns (bytes4 magic) {
                return magic == IERC1271.isValidSignature.selector;
            } catch {
                return false;
            }
        }
    }

    // Core functions
    function proposeCoordination(
        AgentIntent calldata intent,
        bytes calldata signature,
        CoordinationPayload calldata payload
    ) external nonReentrant returns (bytes32 intentHash) {
        require(intent.expiry > block.timestamp, "Intent expired");
        require(intent.participants.length > 0, "No participants");
        require(_isSortedUnique(intent.participants), "Participants not canonical");
        require(_contains(intent.participants, intent.agentId), "Proposer not participant");
        require(payload.coordinationType == intent.coordinationType, "Type mismatch");

        bytes32 pHash = getPayloadHash(payload);
        require(pHash == intent.payloadHash, "Payload hash mismatch");

        require(intent.nonce > agentNonces[intent.agentId], "Nonce not strictly increasing");

        intentHash = getIntentHash(intent);
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", DOMAIN_SEPARATOR, intentHash));
        require(_isValidSig(intent.agentId, digest, signature), "Bad intent signature");

        CoordinationState storage st = states[intentHash];
        require(st.proposer == address(0), "Intent exists");

        st.proposer = intent.agentId;
        st.payloadHash = pHash;
        st.status = 0;
        st.expiry = intent.expiry;
        st.participants = intent.participants;
        st.coordinationValue = intent.coordinationValue;

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
        require(st.proposer != address(0), "Unknown intent");
        require(st.status == 0, "Not proposed");
        require(block.timestamp <= st.expiry, "Intent expired");
        require(attestation.intentHash == intentHash, "Intent hash mismatch");
        require(attestation.expiry > block.timestamp, "Acceptance expired");

        // participant check
        bool isParticipant = false;
        for (uint256 i = 0; i < st.participants.length; i++) {
            if (st.participants[i] == attestation.participant) {
                isParticipant = true;
                break;
            }
        }
        require(isParticipant, "Not participant");
        require(!st.accepted[attestation.participant], "Already accepted");

        // verify signature
        bytes32 aHash = getAcceptanceHash(attestation);
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", DOMAIN_SEPARATOR, aHash));
        require(_isValidSig(attestation.participant, digest, attestation.signature), "Bad acceptance signature");

        st.accepted[attestation.participant] = true;
        st.acceptanceExpiry[attestation.participant] = attestation.expiry;
        st.acceptedCount += 1;

        emit CoordinationAccepted(intentHash, attestation.participant, aHash, st.acceptedCount, st.participants.length);

        if (st.acceptedCount == st.participants.length) {
            st.status = 1; // READY
            return true;
        }
        return false;
    }

    function executeCoordination(
        bytes32 intentHash,
        CoordinationPayload calldata payload,
        bytes calldata /*executionData*/
    ) external nonReentrant returns (bool success, bytes memory result) {
        CoordinationState storage st = states[intentHash];
        require(st.proposer != address(0), "Unknown intent");
        require(st.status == 1, "Not ready");
        require(block.timestamp <= st.expiry, "Intent expired");

        // verify payload
        bytes32 pHash = getPayloadHash(payload);
        require(pHash == st.payloadHash, "Payload hash mismatch");

        // verify all acceptances present and fresh
        for (uint256 i = 0; i < st.participants.length; i++) {
            address p = st.participants[i];
            require(st.accepted[p], "Missing acceptance");
            require(block.timestamp <= st.acceptanceExpiry[p], "Acceptance expired");
        }

        uint256 start = gasleft();
        // Core does not define execution semantics. Echo back coordinationData.
        st.status = 2;
        success = true;
        result = payload.coordinationData;
        uint256 used = start - gasleft();
        emit CoordinationExecuted(intentHash, msg.sender, success, used, result);
    }

    function cancelCoordination(bytes32 intentHash, string calldata reason) external nonReentrant {
        CoordinationState storage st = states[intentHash];
        require(st.proposer != address(0), "Unknown intent");
        require(st.status < 2, "Already executed");
        require(msg.sender == st.proposer || block.timestamp > st.expiry, "Not authorised");

        uint8 finalStatus = block.timestamp > st.expiry ? uint8(4) : uint8(3);
        st.status = finalStatus;
        emit CoordinationCancelled(intentHash, msg.sender, reason, finalStatus);
    }

    function getCoordinationStatus(bytes32 intentHash)
    external
    view
    returns (
        uint8 status,
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

        uint256 count;
        for (uint256 i = 0; i < participants.length; i++) {
            if (st.accepted[participants[i]]) count++;
        }
        acceptedBy = new address[](count);
        uint256 idx;
        for (uint256 i = 0; i < participants.length; i++) {
            if (st.accepted[participants[i]]) acceptedBy[idx++] = participants[i];
        }
    }

    function getRequiredAcceptances(bytes32 intentHash) external view returns (uint256) {
        return states[intentHash].participants.length;
    }

    function getAgentNonce(address agent) external view returns (uint64) {
        return agentNonces[agent];
    }
}
