// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.8.0 <0.9.0;

/// @title Call Decryption Oracle Interface
/// @notice Oracle for executing calls with encrypted, hashed arguments.
interface ICallDecryptionOracle {
    /// @notice Encrypted argument blob with a hash commitment.
    /// @dev argsHash MUST be keccak256(argsPlain) where argsPlain is the decrypted payload.
    struct EncryptedHashedArguments {
        bytes32 argsHash;
        bytes32 publicKeyId;
        bytes   ciphertext;
    }

    /// @notice Transparent call descriptor bound to a particular argsHash.
    struct CallDescriptor {
        address[] eligibleCaller;
        address   targetContract;
        bytes4    selector;
        uint256   clientId;
        bytes32   argsHash;
        uint256   validUntilBlock;
    }

    /// @notice Encrypted call descriptor.
    struct EncryptedCallDescriptor {
        bytes32 publicKeyId;
        bytes   ciphertext;
    }

    /// @notice Emitted when an encrypted call + encrypted args is requested.
    event EncryptedCallRequested(
        uint256 indexed requestId,
        address indexed requester,
        bytes32 callPublicKeyId,
        bytes   callCiphertext,
        bytes32 argsPublicKeyId,
        bytes   argsCiphertext,
        bytes32 argsHash
    );

    /// @notice Emitted when a transparent call + encrypted args is requested.
    event TransparentCallRequested(
        uint256 indexed requestId,
        address indexed requester,
        address[] eligibleCaller,
        address   targetContract,
        bytes4    selector,
        uint256   clientId,
        bytes32   argsHash,
        uint256   validUntilBlock,
        bytes32   argsPublicKeyId,
        bytes     argsCiphertext
    );

    /// @notice Emitted when a call has been fulfilled.
    event CallFulfilled(
        uint256 indexed requestId,
        bool    success,
        bytes   returnData
    );

    function requestEncryptedCall(
        EncryptedCallDescriptor   calldata encCall,
        EncryptedHashedArguments  calldata encArgs
    ) external returns (uint256 requestId);

    function requestTransparentCall(
        CallDescriptor            calldata callDescriptor,
        EncryptedHashedArguments  calldata encArgs
    ) external returns (uint256 requestId);

    function fulfillEncryptedCall(
        uint256          requestId,
        CallDescriptor   calldata callDescriptor,
        bytes            calldata argsPlain
    ) external;

    function fulfillTransparentCall(
        uint256          requestId,
        bytes            calldata argsPlain
    ) external;
}
