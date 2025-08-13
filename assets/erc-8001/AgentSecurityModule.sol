// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/**
 * @title Agent Security Module
 * @dev Implements security features for the Agent Coordination Framework (EIP-8001)
 * @notice Provides encryption, access control, and security validation for agent coordination
 */
contract AgentSecurityModule {

    // Security level definitions matching EIP-8001
    enum SecurityLevel { BASIC, STANDARD, ENHANCED, MAXIMUM }

    // Security context for coordination intents
    struct SecurityContext {
        SecurityLevel level;
        bytes32[] authorizedAgents;
        bytes encryptionKey;
        uint256 timelock;
        bytes32 accessControlHash;
        uint256 createdAt;
        address creator;
    }

    // Events
    event SecurityContextCreated(bytes32 indexed intentHash, SecurityLevel level, uint256 participantCount);
    event EncryptionKeyGenerated(bytes32 indexed intentHash, bytes32 keyHash);
    event AccessGranted(bytes32 indexed intentHash, address indexed participant);
    event AccessRevoked(bytes32 indexed intentHash, address indexed participant);
    event SecurityLevelUpgraded(bytes32 indexed intentHash, SecurityLevel from, SecurityLevel to);

    // State variables
    mapping(bytes32 => SecurityContext) private _securityContexts;
    mapping(bytes32 => mapping(address => bool)) private _participantAccess;
    mapping(address => bytes32) private _agentPublicKeys; // Simulated public keys
    mapping(SecurityLevel => uint256) private _minTimelocks;

    // Access control
    address public immutable COORDINATION_FRAMEWORK;
    address public owner;

    // Constants
    uint256 private constant MAX_PARTICIPANTS = 100;
    uint256 private constant MIN_ENCRYPTION_KEY_LENGTH = 32;

    modifier onlyFramework() {
        require(msg.sender == COORDINATION_FRAMEWORK, "Unauthorized: framework only");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Unauthorized: owner only");
        _;
    }

    modifier validSecurityLevel(SecurityLevel level) {
        require(uint8(level) <= uint8(SecurityLevel.MAXIMUM), "Invalid security level");
        _;
    }

    constructor(address coordinationFramework) {
        COORDINATION_FRAMEWORK = coordinationFramework;
        owner = msg.sender;

        // Set minimum timelocks for each security level
        _minTimelocks[SecurityLevel.BASIC] = 0;
        _minTimelocks[SecurityLevel.STANDARD] = 300; // 5 minutes
        _minTimelocks[SecurityLevel.ENHANCED] = 1800; // 30 minutes
        _minTimelocks[SecurityLevel.MAXIMUM] = 7200; // 2 hours
    }

    /**
     * @dev Creates a security context for a coordination intent
     * @param intentHash Hash of the coordination intent
     * @param level Security level required
     * @param participants List of authorized participants
     * @param customTimelock Custom timelock period (must meet minimum for level)
     */
    function createSecurityContext(
        bytes32 intentHash,
        SecurityLevel level,
        address[] calldata participants,
        uint256 customTimelock
    ) external onlyFramework validSecurityLevel(level) {
        require(_securityContexts[intentHash].creator == address(0), "Context already exists");
        require(participants.length > 0 && participants.length <= MAX_PARTICIPANTS, "Invalid participant count");
        require(customTimelock >= _minTimelocks[level], "Timelock too short for security level");

        // Convert participants to bytes32 array for storage
        bytes32[] memory authorizedAgents = new bytes32[](participants.length);
        for (uint256 i = 0; i < participants.length; i++) {
            require(participants[i] != address(0), "Invalid participant address");
            authorizedAgents[i] = bytes32(uint256(uint160(participants[i])));
            _participantAccess[intentHash][participants[i]] = true;
        }

        // Generate encryption key based on security level
        bytes memory encryptionKey = _generateEncryptionKey(intentHash, level, participants);

        // Create access control hash
        bytes32 accessControlHash = keccak256(abi.encodePacked(
            intentHash,
            level,
            participants,
            block.timestamp,
            block.prevrandao
        ));

        // Store security context
        _securityContexts[intentHash] = SecurityContext({
            level: level,
            authorizedAgents: authorizedAgents,
            encryptionKey: encryptionKey,
            timelock: customTimelock,
            accessControlHash: accessControlHash,
            createdAt: block.timestamp,
            creator: tx.origin
        });

        emit SecurityContextCreated(intentHash, level, participants.length);
        emit EncryptionKeyGenerated(intentHash, keccak256(encryptionKey));
    }

    /**
     * @dev Validates security level requirements for a coordination intent
     * @param intentHash Hash of the coordination intent
     * @param level Required security level
     * @param proof Security proof data (implementation-specific)
     * @return valid True if security requirements are met
     * @return reason Explanation if validation fails
     */
    function validateSecurityLevel(
        bytes32 intentHash,
        SecurityLevel level,
        bytes calldata proof
    ) external view validSecurityLevel(level) returns (bool valid, string memory reason) {
        SecurityContext storage context = _securityContexts[intentHash];

        // Check if context exists
        if (context.creator == address(0)) {
            return (false, "Security context not found");
        }

        // Check if requested level matches or is lower than configured level
        if (uint8(level) > uint8(context.level)) {
            return (false, "Insufficient security level");
        }

        // Check timelock requirements
        if (block.timestamp < context.createdAt + context.timelock) {
            return (false, "Timelock not satisfied");
        }

        // Validate proof based on security level
        if (level >= SecurityLevel.ENHANCED) {
            if (proof.length == 0) {
                return (false, "Security proof required for enhanced levels");
            }

            // Validate proof signature or zkProof depending on implementation
            if (!_validateSecurityProof(intentHash, proof, level)) {
                return (false, "Invalid security proof");
            }
        }

        // Additional checks for MAXIMUM security level
        if (level == SecurityLevel.MAXIMUM) {
            // Require all participants to have registered public keys
            for (uint256 i = 0; i < context.authorizedAgents.length; i++) {
                address participant = address(uint160(uint256(context.authorizedAgents[i])));
                if (_agentPublicKeys[participant] == bytes32(0)) {
                    return (false, "Participant missing public key registration");
                }
            }
        }

        return (true, "");
    }

    /**
     * @dev Encrypts coordination data for authorized participants
     * @param data Data to encrypt
     * @param participants List of authorized participants
     * @param level Security level for encryption
     * @return encryptedData Encrypted coordination data
     * @return keyData Key derivation data for participants
     */
    function encryptCoordinationData(
        bytes calldata data,
        address[] calldata participants,
        SecurityLevel level
    ) external view validSecurityLevel(level) returns (bytes memory encryptedData, bytes memory keyData) {
        require(data.length > 0, "No data to encrypt");
        require(participants.length > 0, "No participants provided");

        if (level == SecurityLevel.BASIC) {
            // Basic level: no encryption, just obfuscation
            return (_obfuscateData(data), "");
        }

        // Generate deterministic encryption key
        bytes32 masterKey = keccak256(abi.encodePacked(
            data,
            participants,
            block.chainid,
            level
        ));

        if (level == SecurityLevel.STANDARD) {
            // Standard level: simple XOR encryption
            encryptedData = _xorEncrypt(data, masterKey);
            keyData = abi.encode(masterKey);
        } else if (level >= SecurityLevel.ENHANCED) {
            // Enhanced/Maximum: multi-layer encryption
            encryptedData = _multiLayerEncrypt(data, masterKey, participants);
            keyData = _generateKeyShares(masterKey, participants);
        }

        return (encryptedData, keyData);
    }

    /**
     * @dev Decrypts coordination data for authorized participant
     * @param encryptedData Encrypted coordination data
     * @param keyData Key derivation data
     * @param participant Participant requesting decryption
     * @param level Security level used for encryption
     * @return decryptedData Decrypted coordination data
     */
    function decryptCoordinationData(
        bytes calldata encryptedData,
        bytes calldata keyData,
        address participant,
        SecurityLevel level
    ) external view validSecurityLevel(level) returns (bytes memory decryptedData) {
        require(encryptedData.length > 0, "No data to decrypt");
        require(participant != address(0), "Invalid participant");

        if (level == SecurityLevel.BASIC) {
            // Basic level: reverse obfuscation
            return _deobfuscateData(encryptedData);
        }

        if (level == SecurityLevel.STANDARD) {
            // Standard level: XOR decryption
            require(keyData.length >= 32, "Invalid key data");
            bytes32 key = abi.decode(keyData, (bytes32));
            return _xorDecrypt(encryptedData, key);
        }

        if (level >= SecurityLevel.ENHANCED) {
            // Enhanced/Maximum: multi-layer decryption
            return _multiLayerDecrypt(encryptedData, keyData, participant);
        }

        revert("Unsupported security level");
    }

    /**
     * @dev Registers a public key for an agent (required for MAXIMUM security)
     * @param publicKey The agent's public key
     */
    function registerPublicKey(bytes32 publicKey) external {
        require(publicKey != bytes32(0), "Invalid public key");
        _agentPublicKeys[msg.sender] = publicKey;
    }

    /**
     * @dev Upgrades security level for existing coordination (if timelock allows)
     * @param intentHash Hash of the coordination intent
     * @param newLevel New security level (must be higher)
     */
    function upgradeSecurityLevel(
        bytes32 intentHash,
        SecurityLevel newLevel
    ) external validSecurityLevel(newLevel) {
        SecurityContext storage context = _securityContexts[intentHash];
        require(context.creator != address(0), "Context not found");
        require(context.creator == msg.sender, "Unauthorized: not creator");
        require(uint8(newLevel) > uint8(context.level), "Cannot downgrade security level");
        require(block.timestamp >= context.createdAt + context.timelock, "Timelock not satisfied");

        SecurityLevel oldLevel = context.level;
        context.level = newLevel;
        context.timelock = _minTimelocks[newLevel];

        emit SecurityLevelUpgraded(intentHash, oldLevel, newLevel);
    }

    /**
     * @dev Revokes access for a participant (emergency function)
     * @param intentHash Hash of the coordination intent
     * @param participant Participant to revoke access for
     */
    function revokeAccess(bytes32 intentHash, address participant) external {
        SecurityContext storage context = _securityContexts[intentHash];
        require(context.creator != address(0), "Context not found");
        require(context.creator == msg.sender || msg.sender == owner, "Unauthorized");
        require(_participantAccess[intentHash][participant], "Participant not authorized");

        _participantAccess[intentHash][participant] = false;
        emit AccessRevoked(intentHash, participant);
    }

    // View functions
    function getSecurityContext(bytes32 intentHash) external view returns (SecurityContext memory) {
        return _securityContexts[intentHash];
    }

    function hasAccess(bytes32 intentHash, address participant) external view returns (bool) {
        return _participantAccess[intentHash][participant];
    }

    function getPublicKey(address agent) external view returns (bytes32) {
        return _agentPublicKeys[agent];
    }

    function getMinTimelock(SecurityLevel level) external view returns (uint256) {
        return _minTimelocks[level];
    }

    // Owner functions
    function updateMinTimelock(SecurityLevel level, uint256 timelock) external onlyOwner {
        _minTimelocks[level] = timelock;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid new owner");
        owner = newOwner;
    }

    // Internal functions
    function _generateEncryptionKey(
        bytes32 intentHash,
        SecurityLevel level,
        address[] calldata participants
    ) internal view returns (bytes memory) {
        bytes memory keyMaterial = abi.encodePacked(
            intentHash,
            level,
            participants,
            block.timestamp,
            block.prevrandao,
            block.coinbase
        );

        if (level == SecurityLevel.BASIC) {
            return abi.encodePacked(keccak256(keyMaterial));
        } else if (level == SecurityLevel.STANDARD) {
            return abi.encodePacked(keccak256(keyMaterial), keccak256(abi.encodePacked(keyMaterial, "salt")));
        } else {
            // Enhanced/Maximum: longer key
            return abi.encodePacked(
                keccak256(keyMaterial),
                keccak256(abi.encodePacked(keyMaterial, "salt1")),
                keccak256(abi.encodePacked(keyMaterial, "salt2")),
                keccak256(abi.encodePacked(keyMaterial, "salt3"))
            );
        }
    }

    function _validateSecurityProof(
        bytes32 intentHash,
        bytes calldata proof,
        SecurityLevel level
    ) internal view returns (bool) {
        // Simplified proof validation - in production this would be more sophisticated
        if (level == SecurityLevel.ENHANCED) {
            // Require proof to be a signature over intentHash
            return proof.length == 65; // Standard signature length
        } else if (level == SecurityLevel.MAXIMUM) {
            // Require more complex proof (could be zk-proof)
            return proof.length >= 32 && proof.length <= 1024;
        }
        return false;
    }

    function _obfuscateData(bytes calldata data) internal pure returns (bytes memory) {
        bytes memory result = new bytes(data.length);
        for (uint256 i = 0; i < data.length; i++) {
            result[i] = bytes1(uint8(data[i]) ^ 0xAA); // Simple XOR with constant
        }
        return result;
    }

    function _deobfuscateData(bytes calldata data) internal pure returns (bytes memory) {
        return _obfuscateData(data); // XOR is symmetric
    }

    function _xorEncrypt(bytes calldata data, bytes32 key) internal pure returns (bytes memory) {
        bytes memory result = new bytes(data.length);
        bytes32 currentKey = key;

        for (uint256 i = 0; i < data.length; i++) {
            if (i > 0 && i % 32 == 0) {
                currentKey = keccak256(abi.encodePacked(currentKey, i));
            }
            uint8 keyByte = uint8(currentKey[i % 32]);
            result[i] = bytes1(uint8(data[i]) ^ keyByte);
        }
        return result;
    }

    function _xorEncryptMemory(bytes memory data, bytes32 key) internal pure returns (bytes memory) {
        bytes memory result = new bytes(data.length);
        bytes32 currentKey = key;

        for (uint256 i = 0; i < data.length; i++) {
            if (i > 0 && i % 32 == 0) {
                currentKey = keccak256(abi.encodePacked(currentKey, i));
            }
            uint8 keyByte = uint8(currentKey[i % 32]);
            result[i] = bytes1(uint8(data[i]) ^ keyByte);
        }
        return result;
    }

    function _xorDecrypt(bytes calldata data, bytes32 key) internal pure returns (bytes memory) {
        return _xorEncrypt(data, key); // XOR is symmetric
    }

    function _xorDecryptMemory(bytes memory data, bytes32 key) internal pure returns (bytes memory) {
        return _xorEncryptMemory(data, key); // XOR is symmetric
    }

    function _multiLayerEncrypt(
        bytes calldata data,
        bytes32 masterKey,
        address[] calldata participants
    ) internal pure returns (bytes memory) {
        bytes memory result = data;

        // Layer 1: XOR with master key
        result = _xorEncryptMemory(result, masterKey);

        // Layer 2: XOR with participant-derived key
        bytes32 participantKey = keccak256(abi.encodePacked(participants));
        result = _xorEncryptMemory(result, participantKey);

        // Layer 3: Additional obfuscation
        bytes memory obfuscated = new bytes(result.length);
        for (uint256 i = 0; i < result.length; i++) {
            obfuscated[i] = bytes1(uint8(result[i]) ^ uint8(i + 1));
        }

        return obfuscated;
    }

    function _multiLayerDecrypt(
        bytes calldata encryptedData,
        bytes calldata keyData,
        address participant
    ) internal pure returns (bytes memory) {
        // This is a simplified implementation
        // In production, this would properly handle key shares and participant verification
        require(keyData.length >= 64, "Insufficient key data");

        bytes32 masterKey = abi.decode(keyData[:32], (bytes32));
        bytes32 participantKey = abi.decode(keyData[32:64], (bytes32));

        bytes memory result = encryptedData;

        // Reverse layer 3: Remove obfuscation
        bytes memory deobfuscated = new bytes(result.length);
        for (uint256 i = 0; i < result.length; i++) {
            deobfuscated[i] = bytes1(uint8(result[i]) ^ uint8(i + 1));
        }
        result = deobfuscated;

        // Reverse layer 2: XOR with participant key
        result = _xorDecryptMemory(result, participantKey);

        // Reverse layer 1: XOR with master key
        result = _xorDecryptMemory(result, masterKey);

        return result;
    }

    function _generateKeyShares(
        bytes32 masterKey,
        address[] calldata participants
    ) internal pure returns (bytes memory) {
        bytes32 participantKey = keccak256(abi.encodePacked(participants));
        return abi.encode(masterKey, participantKey);
    }
}