// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

/// @title Call Decryption Oracle Interface
/// @notice Oracle for executing calls with encrypted, hashed arguments.
/// @dev ERC-style interface & type definition.
interface ICallDecryptionOracle {
    /// @notice Encrypted argument blob with a hash commitment.
    /// @dev argsHash MUST be keccak256(abi.encode(arguments_without_argsHash)).
    struct EncryptedHashedArguments {
        bytes32 argsHash;
        bytes32 publicKeyId;
        bytes   ciphertext;
    }

    /// @notice Transparent call descriptor bound to a particular argsHash.
    struct CallDescriptor {
        address[] eligibleCaller;    // if empty: any requester allowed
        address   targetContract;
        bytes4    selector;
        bytes32   argsHash;          // MUST equal EncryptedHashedArguments.argsHash
        uint256   validUntilBlock;   // 0 = no explicit expiry
    }

    /// @notice Encrypted call descriptor.
    struct EncryptedCallDescriptor {
        bytes32 publicKeyId;
        bytes   ciphertext;          // ENC(abi.encode(CallDescriptor))
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

    /// @notice Request execution with encrypted call descriptor + encrypted arguments.
    /// @dev Must emit EncryptedCallRequested.
    function requestEncryptedCall(
        EncryptedCallDescriptor calldata encCall,
        EncryptedHashedArguments calldata encArgs
    ) external returns (uint256 requestId);

    /// @notice Request execution with transparent call descriptor + encrypted arguments.
    /// @dev Must emit TransparentCallRequested and check callDescriptor.argsHash == encArgs.argsHash.
    function requestTransparentCall(
        CallDescriptor calldata callDescriptor,
        EncryptedHashedArguments calldata encArgs
    ) external returns (uint256 requestId);

    /// @notice Fulfill an encrypted-call request after off-chain decryption.
    /// @param requestId The id obtained from requestEncryptedCall.
    /// @param callDescriptor The decrypted CallDescriptor.
    /// @param argsPlain The decrypted arguments, ABI-encoded as in the original args.
    function fulfillEncryptedCall(
        uint256 requestId,
        CallDescriptor calldata callDescriptor,
        bytes calldata argsPlain
    ) external;

    /// @notice Fulfill a transparent-call request after off-chain decryption of the arguments.
    /// @param requestId The id obtained from requestTransparentCall.
    /// @param argsPlain The decrypted arguments, ABI-encoded.
    function fulfillTransparentCall(
        uint256 requestId,
        bytes calldata argsPlain
    ) external;
}
