// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title Launch Observations
/// @notice Immutable, block-pinned facts an independent detector observed about a token launch.
interface ILaunchObservations {
    enum KeyKind { None, Erc8376, Token, Erc8462Venue }

    enum Lean { None, Clear, Careful, Against }

    struct Tally {
        uint16 against;
        uint16 careful;
        uint16 clear;
    }

    struct Finding {
        bytes32 kind;
        uint256 value;
        uint64 param;
        Lean lean;
    }

    struct ObservationInput {
        KeyKind kind;
        bytes32 launchId;
        uint256 chainId;
        address token;
        uint64 observedBlock;
        bytes32 observedBlockHash;
        Tally tally;
        bytes32 reportHash;
        string reportURI;
        bytes32 evidenceRoot;
    }

    struct Observation {
        bytes32 launchKey;
        uint256 chainId;
        address token;
        KeyKind kind;
        uint64 observedBlock;
        bool hashChecked;
        address detector;
        uint64 recordedAt;
        address identityRegistry;
        Tally tally;
        uint256 agentId;
        uint256 supersedes;
        bytes32 reportHash;
        bytes32 evidenceRoot;
        bytes32 declarationId;
        string reportURI;
    }

    event ObservationRecorded(
        uint256 indexed observationId,
        bytes32 indexed launchKey,
        address indexed detector,
        KeyKind kind,
        uint256 chainId,
        address token,
        bytes32 declarationId,
        uint64 observedBlock,
        bytes32 observedBlockHash,
        bool hashChecked,
        uint256 supersedes,
        Tally tally,
        bytes32 reportHash,
        string reportURI,
        bytes32 evidenceRoot
    );
    event FindingObserved(uint256 indexed observationId, bytes32 indexed kind, uint256 value, uint64 param, Lean lean);
    event DetectorIdentitySet(address indexed detector, address indexed identityRegistry, uint256 indexed agentId);

    function launchDirectory() external view returns (address);
    function tokenKey(uint256 chainId, address token) external pure returns (bytes32);
    function declarationKey(uint256 chainId, bytes32 declarationId) external pure returns (bytes32);
    function recordObservation(ObservationInput calldata input, Finding[] calldata findings) external returns (uint256 observationId, bytes32 launchKey);
    function setDetectorIdentity(address identityRegistry, uint256 agentId) external;
    function detectorIdentity(address detector) external view returns (address identityRegistry, uint256 agentId);
    function getObservation(uint256 observationId) external view returns (Observation memory observation, Finding[] memory findings);
    function latestOf(bytes32 launchKey, address detector) external view returns (uint256 observationId);
    function latestByToken(uint256 chainId, address token, address detector) external view returns (uint256 observationId);
    function latestFinding(uint256 chainId, address token, address detector, bytes32 kind, uint64 param)
        external
        view
        returns (uint256 observationId, uint64 observedBlock, uint64 recordedAt, uint256 value, Lean lean);
    function latestFindingFrom(uint256 chainId, address token, address[] calldata detectors, bytes32 kind, uint64 param)
        external
        view
        returns (address detector, uint256 observationId, uint64 observedBlock, uint64 recordedAt, uint256 value, Lean lean);
    function observationsOf(bytes32 launchKey, uint256 start, uint256 limit) external view returns (uint256[] memory);
    function observationsBy(bytes32 launchKey, address detector, uint256 start, uint256 limit) external view returns (uint256[] memory);
    function detectorsOf(bytes32 launchKey, uint256 start, uint256 limit) external view returns (address[] memory);
}
