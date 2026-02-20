// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title Call Decryption Oracle Interface
 * @notice Oracle for executing calls with encrypted arguments.
 * @author Christian Fries.
 * @dev ERC-style interface & type definitions.
 */
interface ICallDecryptionOracle {

    /*------------------------------------------- TYPE DEFINITIONS ---------------------------------------------------*/

    /**
     * @notice Argument in plain bytes (may be abi.encode(args...)).
     * @dev Implementations typically decrypt to this struct off-chain; the oracle itself only ever sees argsPlain.
     */
    struct ArgsDescriptor {
        /**
         * List of addresses allowed to request decryption.
         * If empty, any requester is allowed. This is enforced off-chain by the oracle operator.
         */
        address[] eligibleCaller;

        /**
         * Plain argument payload, may be abi.encode(args...) (see router).
         */
        bytes argsPlain;
    }

    /**
     * @notice Encrypted argument blob with a hash commitment.
     * @dev argsHash MUST be keccak256(argsPlain) where argsPlain is the decrypted payload.
     */
    struct EncryptedHashedArguments {
        /**
         * Commitment to the plaintext argument payload.
         * The target contract should check keccak256(argsPlain) == argsHash
         */
        bytes32 argsHash;

        /**
         * Identifier of the public key used for encryption (e.g. keccak256 of key material).
         */
        bytes32 publicKeyId;

        /**
         * Ciphertext of abi.encode(ArgsDescriptor), encrypted under publicKeyId.
         */
        bytes ciphertext;
    }

    /**
     * @notice  call descriptor.
     */
    struct CallDescriptor {
        /**
         * Contract that will be called by the oracle.
         */
        address targetContract;

        /**
         * Function that will be called by the oracle.
         * 4-byte function selector for the targetContract.
         */
        bytes4 selector;

        /**
         * Optional expiry (block number). 0 means "no explicit expiry".
         */
        uint256 validUntilBlock;
    }

    /**
     * @notice Encrypted call descriptor.
     */
    struct EncryptedCallDescriptor {
        /**
         * Identifier of the public key used for encryption.
         */
        bytes32 publicKeyId;

        /**
         * Ciphertext of abi.encode(CallDescriptor), encrypted under publicKeyId.
         */
        bytes ciphertext;
    }

    /*---------------------------------------------- EVENTS ----------------------------------------------------------*/

    /// @notice Emitted when a request with transparent call descriptor + encrypted arguments is registered.
    event CallRequested(
        uint256 indexed requestId,
        address indexed requester,
        address   targetContract,
        bytes4    selector,
        uint256   validUntilBlock,
        bytes32   argsPublicKeyId,
        bytes     argsCiphertext,
        bytes32   argsHash,
        bytes     secondFactor
    );

    /// @notice Emitted when a request with encrypted call descriptor + encrypted arguments is registered.
    event EncryptedCallRequested(
        uint256 indexed requestId,
        address indexed requester,
        bytes32 callPublicKeyId,
        bytes   callCiphertext,
        bytes32 argsPublicKeyId,
        bytes   argsCiphertext,
        bytes32 argsHash,
        bytes   secondFactor
    );

    /// @notice Emitted when a call has been fulfilled.
    event CallFulfilled(
        uint256 indexed requestId,
        bytes   returnData
    );

    enum RejectionReason {
        // "unspecified/other" for forward-compatibility
        Unspecified,
        RequestNotFound,
        Expired,
        ArgsHashMismatch,
        CallerNotEligible,
        OperatorPolicy,
        TargetCallFailed
    }

    /// @notice Emitted when a call has been rejected.
    event CallRejected(
        uint256 indexed requestId,
        RejectionReason reason,
        bytes   details  // optional extra info, may be empty
    );

    /**
     * @notice Emitted when the oracle provides a new public key.
     * @dev Announcement of a new key does not imply key rotation semantics.
     *      Key expiry / rotation is an off-chain policy detail.
     */
    event PublicKeyUpdated(
        bytes   newPublicKey,
        bytes32 newKeyId
    );

    /*------------------------------------------- EXTERNAL INTERFACE -------------------------------------------------*/

    /**
     * @notice Returns a public key that can be used to encrypt arguments and the public key id.
     */
    function getPublicKey() external view returns (bytes memory key, bytes32 keyId);

    /**
     * @notice Request execution with transparent call descriptor + encrypted arguments.
     *
     * @param callDescriptor Describes the target of the call (target address and selector of the method (method name)).
     * @param encArgs Encrypted arguments that will be decrypted.
     * @param secondFactor An optional second factor that may be required to decrypt the encrypted arguments
     *                     If a secondFactor is required depends on the implementation of the decryption, if not leave empty (0x).
     *
     * @dev MUST:
     * - require encArgs.argsHash to be consistent with any application-level commitments,
     * - register a unique requestId and store callDescriptor data + requester,
     * - emit CallRequested.
     */
    function requestCall(
        CallDescriptor            calldata callDescriptor,
        EncryptedHashedArguments  calldata encArgs,
        bytes                     calldata secondFactor
    ) external payable returns (uint256 requestId);

    /**
     * @notice Request execution with encrypted call descriptor + encrypted arguments.
     *
     * @param encCall Encrypted CallDescriptor that describes the target of the call (target address and selector of the method (method name)).
     * @param encArgs Encrypted arguments that will be decrypted.
     * @param secondFactor An optional second factor that may be required to decrypt the encrypted arguments
     *                     If a secondFactor is required depends on the implementation of the decryption, if not leave empty (0x).
     *
     * @dev MUST:
     * - register a unique requestId,
     * - store (requestId → requester, argsHash, and auxiliary metadata),
     * - emit EncryptedCallRequested.
     */
    function requestEncryptedCall(
        EncryptedCallDescriptor   calldata encCall,
        EncryptedHashedArguments  calldata encArgs,
        bytes                     calldata secondFactor
    ) external payable returns (uint256 requestId);

    /**
     * @notice Fulfill a transparent-call request after off-chain decryption of the arguments.
     *
     * @param requestId The id obtained from requestCall.
     * @param argsPlain The decrypted argument payload bytes.
     *
     * @dev MUST:
     * - verify that requestId exists and was created with requestCall,
     * - load stored CallDescriptor from state,
     * - verify storedCall.validUntilBlock is zero or >= current block.number,
     * - verify that keccak256(argsPlain) equals the stored argsHash,
     * - perform low-level call:
     *     storedCall.targetContract.call(abi.encodePacked(storedCall.selector, argsPlain))
     * - emit CallFulfilled(requestId, returnData),
     * - clean up stored state for this requestId.
     */
    function fulfillCall(
        uint256          requestId,
        bytes            calldata argsPlain
    ) external;

    /**
     * @notice Fulfill an encrypted-call request after off-chain decryption.
     *
     * @param requestId     The id obtained from requestEncryptedCall.
     * @param callDescriptor The decrypted CallDescriptor.
     * @param argsPlain     The decrypted argument payload bytes.
     *
     * @dev MUST:
     * - verify that requestId exists and was created with requestEncryptedCall,
     * - perform low-level call:
     *     callDescriptor.targetContract.call(abi.encodePacked(callDescriptor.selector, argsPlain))
     * - emit CallFulfilled(requestId, returnData),
     * - clean up stored state for this requestId.
     * Note that eligibility / expiry / policy must be checked off-chain before calling fulfill*.
     */
    function fulfillEncryptedCall(
        uint256          requestId,
        CallDescriptor   calldata callDescriptor,
        bytes            calldata argsPlain
    ) external;

    /**
     * @notice Reject a previously registered request (transparent or encrypted).
     *
     * @param requestId The id obtained from requestCall or requestEncryptedCall.
     * @param reason    RejectionReason enum.
     * @param details   Additional details (may encode error text, revert data, policy code, ...).
     *
     * @dev MUST:
     * - verify that requestId exists (or, if it does not, MAY emit RequestNotFound),
     * - emit CallRejected(requestId, reason, details),
     * - clean up stored state for this requestId.
     */
    function rejectCall(
        uint256 requestId,
        RejectionReason reason,
        bytes calldata details
    ) external;
}
