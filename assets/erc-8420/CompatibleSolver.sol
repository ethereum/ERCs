// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.35;
/// @author Helkomine (@Helkomine)

/**
 * @title Compatible Solver Interface
 * @notice Standard interface for coordinating Context, Validation, and
 *         Execution phases of Solver-compatible intent execution.
 */
interface ICompatibleSolver {
    /**
     * @notice Represents the current execution phase of the Solver.
     *
     * `INACTIVE` indicates that the Solver is not processing a batch.
     * `CONTEXT` indicates that Executors are being called to collect
     * pre-execution context.
     * `VALIDATION` indicates that Senders are validating their execution
     * envelopes and acknowledging the corresponding execution envelope
     * through `senderCallback`.
     * `EXECUTION` indicates that Executors are executing the validated
     * Intents.
     */
    enum Phase {
        INACTIVE,
        CONTEXT,
        VALIDATION,
        EXECUTION
    }

    /**
     * @notice Represents an envelope transaction submitted for Solver
     *         execution.
     *
     * `sender` identifies the account responsible for validating the
     * envelope. `sliceInfo` identifies the contiguous portion of
     * `envelopeTx` containing the execution envelope, encoded as
     * `Executor || Intent`.
     */
    struct UserEnvelopeTx {
        address sender;
        uint256 sliceInfo;
        bytes envelopeTx;
    }

    /**
     * @notice Processes a batch of UserEnvelopeTx objects through the Context,
     *         Validation, and Execution phases.
      *
     * The operation is atomic: any failure during any phase reverts the entire
     * batch. The initiator is recorded as the caller of this function and remains
     * unchanged throughout the execution.
     *
     * @param userEnvelopeTxs The batch of envelope transactions to process.
     */
    function resolve(UserEnvelopeTx[] calldata userEnvelopeTxs) external;

    /**
     * @notice Acknowledges the execution envelope currently being validated by
     *         the Solver.
     *
     * The Sender calls this function during the Validation phase to confirm the
     * exact `Executor || Intent` associated with the current UserEnvelopeTx.
     *
     * The callback is accepted only when it is made by the Sender currently being
     * validated and its execution envelope matches the commitment cached for the
     * current batch item.
     *
     * A Sender may successfully acknowledge at most one execution envelope during
     * its validation.
     *
     * @param intentInfo The execution envelope consisting of `Executor || Intent`.
     */
    function senderCallback(bytes calldata intentInfo) external;

    /**
     * @notice Returns the current execution context of the Solver.
     *
     * The returned arrays represent distinct categories of execution state and
     * are not required to have identical lengths. In particular,
     * `executorPostContext` contains post-execution context for each batch item
     * that has a subsequent item.
     *
     * When the Solver is inactive, the returned context represents the current
     * transient state, which is normally empty after a successful `resolve`
     * operation.
     *
     * @return phase The current Solver execution phase.
     * @return currentIndex The index of the UserEnvelopeTx currently being
     *         processed.
     * @return initiator The address that initiated the current `resolve` call.
     * @return executionHash The execution-envelope commitments for the current
     *         batch.
     * @return userEnvelopeTxs The UserEnvelopeTx objects in the current batch.
     * @return executorPreContext The pre-execution context returned by each
     *         Executor during the Context phase.
     * @return executorPostContext The post-execution context returned by each
     *         Executor for preceding batch items during the Execution phase.
     */
    function context() external view returns (
        Phase phase,
        uint256 currentIndex,
        address initiator,
        bytes32[] memory executionHash,
        UserEnvelopeTx[] memory userEnvelopeTxs,
        bytes[] memory executorPreContext,
        bytes[] memory executorPostContext
    );
}

/**
 * @title IGetterSolver
 * @notice Provides specialized getters for accessing individual pieces of
 *         Solver execution context without retrieving and decoding the full
 *         context returned by `ICompatibleSolver.context()`.
 *
 * These getters are intended to reduce the amount of data that callers need
 * to retrieve when only a subset of the Solver context is required.
 *
 * Indexed getters do not perform bounds checking. Callers are expected to
 * provide an index corresponding to an existing batch item, unless otherwise
 * specified.
 */
interface IGetterSolver is ICompatibleSolver {
    /**
     * @notice Returns the current execution phase of the Solver.
     */
    function phase() external view returns (Phase);

    /**
     * @notice Returns the index of the batch item currently being processed.
     *
     * During an active `resolve` call, this identifies the current
     * `UserEnvelopeTx` being processed by the Solver.
     */
    function currentIndex() external view returns (uint256);

    /**
     * @notice Returns the address that initiated the current `resolve` call.
     *
     * The initiator remains unchanged throughout the execution of `resolve`.
     */
    function initiator() external view returns (address);

    /**
     * @notice Returns the execution hashes of all UserEnvelopeTx items in
     *         the current batch.
     *
     * Each execution hash is the hash of the execution envelope
     * `executor || intent`.
     */
    function getExecutionHashes() external view returns (bytes32[] memory);

    /**
     * @notice Returns the execution hash of the UserEnvelopeTx at `index`.
     *
     * @param index The zero-based index of the batch item.
     */
    function getExecutionHash(uint256 index) external view returns (bytes32);

    /**
     * @notice Returns the execution hash of the UserEnvelopeTx currently
     *         being processed.
     */
    function getCurrentExecutionHash() external view returns (bytes32);

    /**
     * @notice Returns the Sender addresses of all UserEnvelopeTx items in
     *         the current batch.
     */
    function getSenders() external view returns (address[] memory);

    /**
     * @notice Returns the Sender address of the UserEnvelopeTx at `index`.
     *
     * @param index The zero-based index of the batch item.
     */
    function getSender(uint256 index) external view returns (address);

    /**
     * @notice Returns the Sender address of the UserEnvelopeTx currently
     *         being processed.
     */
    function getCurrentSender() external view returns (address);

    /**
     * @notice Returns the `sliceInfo` values of all UserEnvelopeTx items in
     *         the current batch.
     */
    function getSliceInfos() external view returns (uint256[] memory);

    /**
     * @notice Returns the `sliceInfo` value of the UserEnvelopeTx at `index`.
     *
     * @param index The zero-based index of the batch item.
     */
    function getSliceInfo(uint256 index) external view returns (uint256);

    /**
     * @notice Returns the `sliceInfo` value of the UserEnvelopeTx currently
     *         being processed.
     */
    function getCurrentSliceInfo() external view returns (uint256);

    /**
     * @notice Returns the complete `envelopeTx` values of all UserEnvelopeTx
     *         items in the current batch.
     */
    function getEnvelopeTxs() external view returns (bytes[] memory);

    /**
     * @notice Returns the complete `envelopeTx` of the UserEnvelopeTx at
     *         `index`.
     *
     * @param index The zero-based index of the batch item.
     */
    function getEnvelopeTx(uint256 index) external view returns (bytes memory);

    /**
     * @notice Returns the complete `envelopeTx` of the UserEnvelopeTx
     *         currently being processed.
     */
    function getCurrentEnvelopeTx() external view returns (bytes memory);

    /**
     * @notice Returns all UserEnvelopeTx items in the current batch.
     *
     * This is equivalent to retrieving the corresponding Sender,
     * `sliceInfo`, and `envelopeTx` values together.
     */
    function getUserEnvelopeTxs()
        external
        view
        returns (UserEnvelopeTx[] memory);

    /**
     * @notice Returns the UserEnvelopeTx at `index`.
     *
     * @param index The zero-based index of the batch item.
     */
    function getUserEnvelopeTx(uint256 index)
        external
        view
        returns (UserEnvelopeTx memory);

    /**
     * @notice Returns the UserEnvelopeTx currently being processed.
     */
    function getCurrentUserEnvelopeTx()
        external
        view
        returns (UserEnvelopeTx memory);

    /**
     * @notice Returns the pre-execution contexts produced by all Executors
     *         in the current batch.
     *
     * Each entry corresponds to the Executor at the same batch index.
     */
    function getExecutorPreContexts()
        external
        view
        returns (bytes[] memory);

    /**
     * @notice Returns the pre-execution context produced by the Executor at
     *         `index`.
     *
     * @param index The zero-based index of the batch item.
     */
    function getExecutorPreContext(uint256 index)
        external
        view
        returns (bytes memory);

    /**
     * @notice Returns the pre-execution context produced by the Executor
     *         currently being processed.
     */
    function getCurrentExecutorPreContext()
        external
        view
        returns (bytes memory);

    /**
     * @notice Returns the post-execution contexts produced for the batch.
     *
     * The returned array contains the post-context produced after execution
     * of each completed batch item for which a subsequent item exists.
     * Therefore, for a batch of `n` items, the array contains `n - 1`
     * entries when `n > 0`, and zero entries when `n == 0`.
     */
    function getExecutorPostContexts()
        external
        view
        returns (bytes[] memory);

    /**
     * @notice Returns the post-execution context associated with the batch
     *         item at `index`.
     *
     * @param index The zero-based index of the post-context.
     */
    function getExecutorPostContext(uint256 index)
        external
        view
        returns (bytes memory);

    /**
     * @notice Returns the most recently produced post-execution context
     *         preceding the current batch item.
     *
     * When `currentIndex == k` and `k > 0`, this returns the post-context
     * produced for batch item `k - 1`.
     *
     * When `currentIndex == 0`, no preceding item has been executed and
     * the function returns an empty byte string.
     */
    function getCurrentExecutorPostContext()
        external
        view
        returns (bytes memory);
}

contract CompatibleSolver is ICompatibleSolver, IGetterSolver {
    /**
     * @dev Maximum number of bytes that a cache entry can contain.
     *
     * This limit protects the transient-storage cache implementation and is
     * not part of the Solver protocol semantics.
     */
    uint64 constant MAX_TOTAL_LENGTH = type(uint64).max;

    /**
     * @dev Mask used to extract the lower 128-bit `length` field from
     *      `sliceInfo`.
     */
    uint256 constant SLICE_INFO_MASKING = type(uint128).max;

    /**
     * @dev Transient-storage namespace used for the current batch of
     *      UserEnvelopeTx objects.
     */
    bytes32 constant USER_ENVELOPE_TX_SLOT =
        bytes32(erc7201("user.envelope.tx.slot"));

    /**
     * @dev Transient-storage namespace used for Executor pre-context values.
     */
    bytes32 constant PRE_CONTEXT_SLOT =
        bytes32(erc7201("pre.context.slot"));

    /**
     * @dev Transient-storage namespace used for Executor post-context values.
     */
    bytes32 constant POST_CONTEXT_SLOT =
        bytes32(erc7201("post.context.slot"));

    /**
     * @dev Transient-storage namespace used for execution-envelope hashes.
     */
    bytes32 constant EXECUTION_HASHES_SLOT =
        bytes32(erc7201("execution.hashes.slot"));

    /// @inheritdoc IGetterSolver
    Phase public transient phase;

    /// @inheritdoc IGetterSolver
    uint256 public transient currentIndex;

    /// @inheritdoc IGetterSolver
    address public transient initiator;

    /**
     * @dev Sender currently authorized to perform the Solver callback during
     *      the Validation phase.
     */
    address transient validSenderCallback;

    /**
     * @dev Indicates whether the current Sender has successfully acknowledged
     *      its expected execution envelope through `senderCallback`.
     */
    bool transient callbackAccepted;

    /**
     * @dev Emitted when a UserEnvelopeTx is cached for the current Solver
     *      execution.
     *
     * @param userEnvelopeTx The cached UserEnvelopeTx.
     */
    event CacheUserEnvelopeTx(UserEnvelopeTx userEnvelopeTx);

    /**
     * @dev Emitted when an Executor successfully returns pre-execution
     *      context during the Context phase.
     *
     * @param sender The Sender associated with the UserEnvelopeTx.
     * @param executor The Executor that produced the context.
     * @param preContext The context returned by the Executor.
     */
    event CachePreContext(
        address indexed sender,
        address indexed executor,
        bytes preContext
    );

    /**
     * @dev Emitted when the Context phase completes successfully.
     */
    event ContextPhaseSuccess();

    /**
     * @dev Emitted when a Sender successfully validates its execution
     *      envelope.
     *
     * @param sender The Sender that validated the envelope.
     * @param result The return data produced by the Sender.
     */
    event ValidateSenderSuccess(
        address indexed sender,
        bytes result
    );

    /**
     * @dev Emitted when the Validation phase completes successfully.
     */
    event ValidateSenderPhaseSuccess();

    /**
     * @dev Emitted when a Sender successfully acknowledges its execution
     *      envelope through `senderCallback`.
     *
     * @param sender The Sender performing the callback.
     * @param result The callback result data.
     */
    event SenderCallbackSuccess(
        address indexed sender,
        bytes result
    );

    /**
     * @dev Emitted when an Executor successfully executes an Intent.
     *
     * @param executor The Executor that executed the Intent.
     * @param result The return data produced by the Executor.
     */
    event ExecuteIntentSuccess(
        address indexed executor,
        bytes result
    );

    /**
     * @dev Emitted when the Execution phase completes successfully.
     */
    event ExecuteIntentPhaseSuccess();

    /**
     * @dev Reverts when transient-storage slot arithmetic overflows.
     *
     * This error protects the cache implementation and is not part of the
     * Solver protocol semantics.
     */
    error Overflow();

    /**
     * @dev Reverts when `resolve` is called while the Solver is already
     *      processing another execution.
     */
    error Reentrancy();

    /**
     * @dev Reverts when a function requiring an active Solver execution is
     *      called while the Solver is inactive.
     */
    error InactiveSolver();

    /**
     * @dev Reverts when the current Sender completes validation without
     *      successfully acknowledging its execution envelope through
     *      `senderCallback`.
     */
    error IntentNotAccepted();

    /**
     * @dev Reverts when a cached `bytes` value exceeds
     *      `MAX_TOTAL_LENGTH`.
     *
     * @param totalLength The length that exceeded the implementation limit.
     */
    error TotalLengthTooLarge(uint256 totalLength);

    /**
     * @dev Reverts when a callback is made by an address other than the
     *      Sender currently being validated.
     *
     * @param sender The address that attempted the callback.
     */
    error InvalidSender(address sender);

    /**
     * @dev Reverts when a Sender execution envelope fails during the
     *      Validation phase.
     *
     * @param result The revert data returned by the Sender.
     */
    error ValidateSenderFailed(bytes result);

    /**
     * @dev Reverts when an Executor fails during the Execution phase.
     *
     * @param result The revert data returned by the Executor.
     */
    error ExecuteIntentFailed(bytes result);

    /**
     * @dev Reverts when an Executor fails to provide pre-execution context
     *      during the Context phase.
     *
     * @param executor The Executor that failed.
     * @param reason The revert data returned by the Executor.
     */
    error PreContextFailed(
        address executor,
        bytes reason
    );

    /**
     * @dev Reverts when the current Sender attempts to acknowledge more than
     *      one execution envelope during its validation.
     *
     * @param executor The Executor encoded in the attempted callback.
     * @param intent The Intent encoded in the attempted callback.
     */
    error CallbackAlreadyAccepted(
        address executor,
        bytes intent
    );

    /**
     * @dev Reverts when the execution envelope supplied to `senderCallback`
     *      does not match the execution-envelope commitment for the current
     *      UserEnvelopeTx.
     *
     * @param executor The Executor encoded in the attempted callback.
     * @param intent The Intent encoded in the attempted callback.
     */
    error InvalidIntent(
        address executor,
        bytes intent
    );

    /**
     * @dev Prevents a new Solver execution from starting while another
     *      execution is active.
     *
     * Sets the Solver phase to `CONTEXT` before executing the modified
     * function body and restores it to `INACTIVE` after successful
     * completion.
     */
    modifier nonReentrant {
        require(phase == Phase.INACTIVE, Reentrancy());
        phase = Phase.CONTEXT;
        _;
        phase = Phase.INACTIVE;
    }

    /**
     * @dev Restricts execution to an active Solver session.
     */
    modifier onlySolverActive {
        require(phase != Phase.INACTIVE, InactiveSolver());
        _;
    }

    /**
     * @dev No-op fallback used to allow the Solver to act as a technical
     *      Sender or Executor for blob-only UserEnvelopeTx objects.
     *
     * This fallback intentionally performs no state-changing operation.
     */
    fallback() external {}

    /// @inheritdoc ICompatibleSolver
    function resolve(UserEnvelopeTx[] calldata userEnvelopeTxs) external nonReentrant {
        _setContextPhase(userEnvelopeTxs);
        _validateSenderPhase(userEnvelopeTxs);
        _executeIntentPhase(userEnvelopeTxs);
        _clearContext();
    }

    /// @inheritdoc ICompatibleSolver
    function senderCallback(bytes calldata intentInfo) external onlySolverActive {
        require(msg.sender == validSenderCallback, InvalidSender(msg.sender));
        
        (address executor, bytes calldata intent) = _decodeIntentInfo(intentInfo);

        if (callbackAccepted) revert CallbackAlreadyAccepted(executor, intent);
        unchecked {
            bytes32 intentHash = bytes32(_tload(bytes32((uint256(EXECUTION_HASHES_SLOT) + 1) + currentIndex)));
            require(keccak256(intentInfo) == intentHash, InvalidIntent(executor, intent));
        }
        callbackAccepted = true;
        emit SenderCallbackSuccess(msg.sender, intent);
    }

    /// @inheritdoc ICompatibleSolver
    function context() external view returns (
        Phase _phase,
        uint256 _currentIndex,
        address _initiator,
        bytes32[] memory executionHash,
        UserEnvelopeTx[] memory userEnvelopeTxs,
        bytes[] memory executorPreContext,
        bytes[] memory executorPostContext
    ) {
        uint256 length = _tload(USER_ENVELOPE_TX_SLOT);
        executionHash = new bytes32[](length);
        userEnvelopeTxs = new UserEnvelopeTx[](length);
        executorPreContext = new bytes[](length);
        if (length > 0) executorPostContext = new bytes[](length - 1);
        unchecked {
            for (uint256 i = 0 ; i < length ; i++) {
                executionHash[i] = bytes32(_tload(bytes32((uint256(EXECUTION_HASHES_SLOT) + 1) + i)));
                userEnvelopeTxs[i] = _getUserEnvelopeTx(USER_ENVELOPE_TX_SLOT, i);
                executorPreContext[i] = _getCacheData(_getHashedSlot(PRE_CONTEXT_SLOT, i));
                if (i + 1 < length) {
                    executorPostContext[i] = _getCacheData(_getHashedSlot(POST_CONTEXT_SLOT, i));
                }
            }
        }
        return (phase, currentIndex, initiator, executionHash, userEnvelopeTxs, executorPreContext, executorPostContext);
    }

    /// @inheritdoc IGetterSolver
    function getExecutionHashes() external view returns (bytes32[] memory) {
        uint256 length = _tload(EXECUTION_HASHES_SLOT);
        bytes32[] memory hashes = new bytes32[](length);
        uint256 start = uint256(EXECUTION_HASHES_SLOT) + 1;
        for (uint256 i = 0 ; i < length ; ) {
            unchecked {
                hashes[i] = bytes32(_tload(bytes32(start + i)));
                ++i;
            }
        }
        return hashes;
    }

    /// @inheritdoc IGetterSolver
    function getExecutionHash(uint256 index) external view returns (bytes32) {
        unchecked {
            uint256 start = uint256(EXECUTION_HASHES_SLOT) + 1;
            return bytes32(_tload(bytes32(start + index)));
        }
    }

    /// @inheritdoc IGetterSolver
    function getCurrentExecutionHash() external view returns (bytes32) {
        unchecked {
            uint256 start = uint256(EXECUTION_HASHES_SLOT) + 1;
            return bytes32(_tload(bytes32(start + currentIndex)));
        }
    }

    /// @inheritdoc IGetterSolver
    function getSenders() external view returns (address[] memory) {
        uint256 length = _tload(USER_ENVELOPE_TX_SLOT);
        address[] memory senders = new address[](length);
        for (uint256 i = 0 ; i < length ; ) {
            unchecked {
                bytes32 slot = _getHashedSlot(USER_ENVELOPE_TX_SLOT, i);
                senders[i] = address(uint160(_tload(slot)));
                ++i;
            }
        }
        return senders;
    }

    /// @inheritdoc IGetterSolver
    function getSender(uint256 index) external view returns (address) {
        bytes32 slot = _getHashedSlot(USER_ENVELOPE_TX_SLOT, index);
        return address(uint160(_tload(slot)));
    }

    /// @inheritdoc IGetterSolver
    function getCurrentSender() external view returns (address) {
        bytes32 slot = _getHashedSlot(USER_ENVELOPE_TX_SLOT, currentIndex);
        return address(uint160(_tload(slot)));
    }

    /// @inheritdoc IGetterSolver
    function getSliceInfos() external view returns (uint256[] memory) {
        uint256 length = _tload(USER_ENVELOPE_TX_SLOT);
        uint256[] memory infos = new uint256[](length);
        for (uint256 i = 0 ; i < length ; ) {
            unchecked {
                bytes32 slot = _getHashedSlot(USER_ENVELOPE_TX_SLOT, i);
                infos[i] = _tload(bytes32(uint256(slot) + 1));
                ++i;
            }
        }
        return infos;
    }

    /// @inheritdoc IGetterSolver
    function getSliceInfo(uint256 index) external view returns (uint256) {
        unchecked {
            bytes32 slot = _getHashedSlot(USER_ENVELOPE_TX_SLOT, index);
            return _tload(bytes32(uint256(slot) + 1));
        }
    }

    /// @inheritdoc IGetterSolver
    function getCurrentSliceInfo() external view returns (uint256) {
        unchecked {
            bytes32 slot = _getHashedSlot(USER_ENVELOPE_TX_SLOT, currentIndex);
            return _tload(bytes32(uint256(slot) + 1));
        }
    }

    /// @inheritdoc IGetterSolver
    function getEnvelopeTxs() external view returns (bytes[] memory) {
        uint256 length = _tload(USER_ENVELOPE_TX_SLOT);
        bytes[] memory envelopeTxs = new bytes[](length);
        for (uint256 i = 0 ; i < length ; ) {
            unchecked {
                bytes32 slot = _getHashedSlot(USER_ENVELOPE_TX_SLOT, i);
                envelopeTxs[i] = _getCacheData(bytes32(uint256(slot) + 2));
                ++i;
            }
        }
        return envelopeTxs;
    }

    /// @inheritdoc IGetterSolver
    function getEnvelopeTx(uint256 index) external view returns (bytes memory) {
        unchecked {
            bytes32 slot = _getHashedSlot(USER_ENVELOPE_TX_SLOT, index);
            return _getCacheData(bytes32(uint256(slot) + 2));
        }
    }

    /// @inheritdoc IGetterSolver
    function getCurrentEnvelopeTx() external view returns (bytes memory) {
        unchecked {
            bytes32 slot = _getHashedSlot(USER_ENVELOPE_TX_SLOT, currentIndex);
            return _getCacheData(bytes32(uint256(slot) + 2));
        }
    }

    /// @inheritdoc IGetterSolver
    function getUserEnvelopeTxs() external view returns (UserEnvelopeTx[] memory) {
        uint256 length = _tload(USER_ENVELOPE_TX_SLOT);
        UserEnvelopeTx[] memory userEnvelopeTxs = new UserEnvelopeTx[](length);
        for (uint256 i = 0 ; i < length ; ) {
            userEnvelopeTxs[i] = _getUserEnvelopeTx(USER_ENVELOPE_TX_SLOT, i);
            ++i;
        }
        return userEnvelopeTxs;
    }

    /// @inheritdoc IGetterSolver
    function getUserEnvelopeTx(uint256 index) external view returns (UserEnvelopeTx memory) {
        return _getUserEnvelopeTx(USER_ENVELOPE_TX_SLOT, index);
    }

    /// @inheritdoc IGetterSolver
    function getCurrentUserEnvelopeTx() external view returns (UserEnvelopeTx memory) {
        return _getUserEnvelopeTx(USER_ENVELOPE_TX_SLOT, currentIndex);
    }

    /// @inheritdoc IGetterSolver
    function getExecutorPreContexts() external view returns (bytes[] memory) {
        uint256 length = _tload(PRE_CONTEXT_SLOT);
        bytes[] memory preContexts = new bytes[](length);
        for (uint256 i = 0 ; i < length ; ) {
            unchecked {
                preContexts[i] = _getCacheData(_getHashedSlot(PRE_CONTEXT_SLOT, i));
                ++i;
            }
        }
        return preContexts;
    }

    /// @inheritdoc IGetterSolver
    function getExecutorPreContext(uint256 index) external view returns (bytes memory) {
        return _getCacheData(_getHashedSlot(PRE_CONTEXT_SLOT, index));
    }

    /// @inheritdoc IGetterSolver
    function getCurrentExecutorPreContext() external view returns (bytes memory) {
        return _getCacheData(_getHashedSlot(PRE_CONTEXT_SLOT, currentIndex));
    }

    /// @inheritdoc IGetterSolver
    function getExecutorPostContexts() external view returns (bytes[] memory) {
        uint256 length = _tload(POST_CONTEXT_SLOT);
        bytes[] memory postContexts = new bytes[](length);
        for (uint256 i = 0 ; i < length ; ) {
            unchecked {
                postContexts[i] = _getCacheData(_getHashedSlot(POST_CONTEXT_SLOT, i));
                ++i;
            }
        }
        return postContexts;
    }

    /// @inheritdoc IGetterSolver
    function getExecutorPostContext(uint256 index) external view returns (bytes memory) {
        return _getCacheData(_getHashedSlot(POST_CONTEXT_SLOT, index));
    }

    /// @inheritdoc IGetterSolver
    function getCurrentExecutorPostContext() external view returns (bytes memory) {
        unchecked {
            uint256 index = currentIndex;
            bytes memory postContext;
            if (index > 0) {
                postContext = _getCacheData(_getHashedSlot(POST_CONTEXT_SLOT, index - 1));
            }
            return postContext;
        }
    }

    /**
     * @dev Initializes the execution context for the Context phase.
     *
     * Records the `resolve` initiator, caches the UserEnvelopeTx batch, and stores
     * an execution-envelope hash for each batch item. The cached hash is later
     * used by `senderCallback` to verify that the Sender acknowledges the exact
     * `Executor || Intent` associated with the current UserEnvelopeTx.
     *
     * The function then invokes each Executor using `STATICCALL` to collect its
     * pre-execution context. Because the calls are static, the Executor and its
     * downstream call tree cannot modify persistent or transient state.
     *
     * Sets `currentIndex` to the currently processed batch item while each Executor
     * is invoked and advances the Solver to the Validation phase after all
     * pre-context has been collected successfully.
     *
     * @param userEnvelopeTxs The batch of envelope transactions to initialize
     *        for Solver execution.
     */
    function _setContextPhase(UserEnvelopeTx[] calldata userEnvelopeTxs) internal {
        initiator = msg.sender;
        _tstore(USER_ENVELOPE_TX_SLOT, userEnvelopeTxs.length);
        _tstore(EXECUTION_HASHES_SLOT, userEnvelopeTxs.length);
        _tstore(PRE_CONTEXT_SLOT, userEnvelopeTxs.length);
        for (uint256 i = 0 ; i < userEnvelopeTxs.length ; i++) {
            UserEnvelopeTx calldata userEnvelopeTx = userEnvelopeTxs[i];

            (uint256 offset, uint256 length) = _getOffsetAndLength(userEnvelopeTx.sliceInfo);

            bytes calldata intentInfo = _sliceEnvelopeTx(offset, length, userEnvelopeTx.envelopeTx);

            _cacheUserEnvelopeTx(USER_ENVELOPE_TX_SLOT, i, userEnvelopeTx);
            _tstore(bytes32((uint256(EXECUTION_HASHES_SLOT) + 1) + i), uint256(keccak256(intentInfo)));
        }
        for (uint256 i = 0 ; i < userEnvelopeTxs.length ; ) {
            UserEnvelopeTx calldata userEnvelopeTx = userEnvelopeTxs[i];

            (uint256 offset, uint256 length) = _getOffsetAndLength(userEnvelopeTx.sliceInfo);

            bytes calldata intentInfo = _sliceEnvelopeTx(offset, length, userEnvelopeTx.envelopeTx);

            (address executor, bytes calldata intent) = _decodeIntentInfo(intentInfo);

            currentIndex = i;
            _cachePreContext(PRE_CONTEXT_SLOT, i, userEnvelopeTx.sender, executor, intent);
            unchecked { ++i; }
        }
        _markPhase1Pass();
    }

    /**
     * @dev Validates each Sender and verifies that it acknowledges its expected
     *      execution envelope.
     *
     * For each UserEnvelopeTx, the Solver calls the Sender with its complete
     * `envelopeTx`. The Sender MUST successfully return and MUST invoke
     * `senderCallback` with the exact `Executor || Intent` associated with the
     * current UserEnvelopeTx.
     *
     * The callback acceptance flag is reset after each successfully validated
     * Sender. The callback target is cleared after the entire Validation phase
     * completes.
     *
     * Reverts if a Sender call fails or if the Sender completes without
     * successfully acknowledging its execution envelope.
     *
     * @param userEnvelopeTxs The batch of envelope transactions whose Senders are
     *        validated.
     */
    function _validateSenderPhase(UserEnvelopeTx[] calldata userEnvelopeTxs) internal {
        for (uint256 i = 0 ; i < userEnvelopeTxs.length ; ) {
            uint256 ptr = _getFreePtr();
            UserEnvelopeTx calldata userEnvelopeTx = userEnvelopeTxs[i];

            currentIndex = i;
            validSenderCallback = userEnvelopeTx.sender;
            (bool success, bytes memory result)
            = userEnvelopeTx.sender.call(userEnvelopeTx.envelopeTx);
            require(success, ValidateSenderFailed(result));
            require(callbackAccepted, IntentNotAccepted());
            callbackAccepted = false;

            emit ValidateSenderSuccess(userEnvelopeTx.sender, result);
            _restoreFreePtr(ptr);
            unchecked { ++i; }
        }
        validSenderCallback = address(0);
        _markPhase2Pass();
    }

    /**
     * @dev Executes each validated Intent through its corresponding Executor.
     *
     * The execution envelope is decoded again from the original `envelopeTx`,
     * ensuring that the Executor and Intent executed here are derived from the
     * same envelope that was validated during the Validation phase.
     *
     * The Executor is called with the decoded Intent. When a subsequent batch
     * item exists, the returned data is stored as post-execution context for that
     * item and can be accessed through `context()`.
     *
     * Reverts if any Executor call fails. Because `resolve` is atomic, such a
     * failure reverts the entire Solver execution.
     *
     * @param userEnvelopeTxs The batch of envelope transactions whose validated
     *        Intents are to be executed.
     */
    function _executeIntentPhase(
        UserEnvelopeTx[] calldata userEnvelopeTxs
    ) internal {
        unchecked {
            if (userEnvelopeTxs.length > 0) _tstore(POST_CONTEXT_SLOT, userEnvelopeTxs.length - 1);
            for (uint256 i = 0 ; i < userEnvelopeTxs.length ; i++) {
                uint256 ptr = _getFreePtr();
                UserEnvelopeTx calldata userEnvelopeTx = userEnvelopeTxs[i];

                (uint256 offset, uint256 length) = _getOffsetAndLength(userEnvelopeTx.sliceInfo);

                (address executor, bytes calldata intent)
                = _decodeIntentInfo(
                    _sliceEnvelopeTx(offset, length, userEnvelopeTx.envelopeTx)
                );

                currentIndex = i;
                (bool success, bytes memory result) = executor.call(intent);
                require(success, ExecuteIntentFailed(result));
                if (i + 1 < userEnvelopeTxs.length) {
                    _setCacheData(_getHashedSlot(POST_CONTEXT_SLOT, i), result);
                }
                emit ExecuteIntentSuccess(executor, result);
                _restoreFreePtr(ptr);
            }
            emit ExecuteIntentPhaseSuccess();
        }
    }

    /**
     * @dev Clears transient execution context remaining after a Solver session.
     *
     * Resets the initiator and current batch index and clears the cached batch,
     * execution-envelope hashes, pre-execution context, and post-execution
     * context.
     *
     * This function is an implementation-level cleanup operation. The transient
     * storage layout and cleanup strategy are not part of the Solver protocol
     * semantics.
     */
    function _clearContext() internal {
        initiator = address(0);
        currentIndex = 0;
        uint256 length = _tload(USER_ENVELOPE_TX_SLOT);
        _tstore(USER_ENVELOPE_TX_SLOT, 0);
        _tstore(PRE_CONTEXT_SLOT, 0);
        _tstore(POST_CONTEXT_SLOT, 0);
        _tstore(EXECUTION_HASHES_SLOT, 0);
        unchecked {
            for (uint256 i = 0 ; i < length ; i++) {
                _clearUserEnvelopeTx(USER_ENVELOPE_TX_SLOT, i);
                _setCacheData(_getHashedSlot(PRE_CONTEXT_SLOT, i), new bytes(0));
                _tstore(bytes32(uint256(EXECUTION_HASHES_SLOT) + 1 + i), 0);
            }
            for (uint256 i = 0 ; i + 1 < length ; i++) {
                _setCacheData(_getHashedSlot(POST_CONTEXT_SLOT, i), new bytes(0));
            }
        }
    }

    /**
     * @dev Clears a cached UserEnvelopeTx from transient storage.
     *
     * Removes the cached Sender, slice information, and envelope transaction
     * associated with the specified namespace and index.
     *
     * @param namespace The transient storage namespace containing the cached
     *        UserEnvelopeTx.
     * @param index The index of the UserEnvelopeTx within the namespace.
     */
    function _clearUserEnvelopeTx(bytes32 namespace, uint256 index) internal {
        bytes32 slot = _getHashedSlot(namespace, index);
        unchecked {
            _tstore(slot, 0);
            _tstore(bytes32(uint256(slot) + 1), 0);
            _setCacheData(bytes32(uint256(slot) + 2), new bytes(0));
        }
    }

    /**
     * @dev Caches a UserEnvelopeTx in transient storage.
     *
     * Stores the Sender address, packed slice information, and complete envelope
     * transaction under the specified namespace and index.
     *
     * The transient-storage representation is an implementation detail and is
     * used to make the complete UserEnvelopeTx batch available through the
     * Solver execution context.
     *
     * @param namespace The transient storage namespace used for the cached
     *        UserEnvelopeTx.
     * @param index The index of the UserEnvelopeTx within the namespace.
     * @param userEnvelopeTx The UserEnvelopeTx to cache.
     */
    function _cacheUserEnvelopeTx(
        bytes32 namespace,
        uint256 index,
        UserEnvelopeTx calldata userEnvelopeTx
    ) internal {
        bytes32 slot = _getHashedSlot(namespace, index);
        _tstore(slot, uint256(uint160(userEnvelopeTx.sender)));
        unchecked { _tstore(bytes32(uint256(slot) + 1), userEnvelopeTx.sliceInfo); }
        _setCacheCallData(bytes32(uint256(slot) + 2), userEnvelopeTx.envelopeTx);
        emit CacheUserEnvelopeTx(userEnvelopeTx);
    }

    /**
     * @dev Collects and caches pre-execution context from an Executor.
     *
     * Calls the Executor using `STATICCALL` with the Intent as calldata. The
     * Executor and its downstream call tree therefore cannot modify state during
     * this phase.
     *
     * The returned data is cached as pre-execution context and can subsequently
     * be accessed through `context()` during Validation and Execution.
     *
     * Reverts with `PreContextFailed` if the Executor call fails.
     *
     * @param namespace The transient storage namespace used for pre-execution
     *        context.
     * @param index The index of the corresponding UserEnvelopeTx.
     * @param sender The Sender associated with the UserEnvelopeTx. Used for
     *        context events.
     * @param executor The Executor from the execution envelope.
     * @param intent The Intent passed to the Executor.
     */
    function _cachePreContext(
        bytes32 namespace,
        uint256 index,
        address sender,
        address executor,
        bytes calldata intent
    ) internal {
        uint256 ptr = _getFreePtr();
        (bool success, bytes memory preContext) = executor.staticcall(intent);
        require(success, PreContextFailed(executor, preContext));
        _setCacheData(_getHashedSlot(namespace, index), preContext);
        emit CachePreContext(sender, executor, preContext);
        _restoreFreePtr(ptr);
    }

    // Hàm trả về đối tượng có kiểu UserEnvelopeTx
    function _getUserEnvelopeTx(
        bytes32 namespace,
        uint256 index
    ) internal view returns (UserEnvelopeTx memory) {
        bytes32 slot = _getHashedSlot(namespace, index);
        unchecked {
            return UserEnvelopeTx(
                address(uint160(_tload(slot))),
                _tload(bytes32(uint256(slot) + 1)),
                _getCacheData(bytes32(uint256(slot) + 2))
            );
        }
    }

    /**
     * @dev Copies a `bytes` value from calldata into transient storage.
     *
     * The value is stored as a length word followed by its data words. If the
     * length is not a multiple of 32 bytes, the unused bytes in the final word
     * are zeroed to produce a canonical representation.
     *
     * If the new value is shorter than the previously cached value at the same
     * namespace, trailing transient storage slots are cleared to prevent stale
     * data from remaining in the cache.
     *
     * Reverts with `TotalLengthTooLarge` if the value or previous cached value
     * exceeds `MAX_TOTAL_LENGTH`, or with `Overflow` if the transient storage
     * slot arithmetic overflows.
     *
     * @param namespace The transient storage namespace used to cache the value.
     * @param data The calldata bytes to cache.
     */
    function _setCacheCallData(bytes32 namespace, bytes calldata data) internal {
        bytes4 lengthTooLargeSelector = TotalLengthTooLarge.selector;
        bytes4 overflowSelector = Overflow.selector;
        uint64 maxTotalLength = MAX_TOTAL_LENGTH;
        assembly ("memory-safe") {
            let length := data.length
            if gt(length, maxTotalLength) {
                mstore(0, lengthTooLargeSelector)
                mstore(4, length)
                revert(0, 36)
            }
            let totalSlot := shr(5, add(length, 31))
            let cacheLength := tload(namespace)
            let totalCacheSlot
            {
                let _cacheLength := add(cacheLength, 31)
                if gt(cacheLength, _cacheLength) {
                    mstore(0, overflowSelector)
                    revert(0, 4)
                }
                totalCacheSlot := shr(5, _cacheLength)
            }
            tstore(namespace, length)
            {
                let _namespace := add(namespace, 1)
                if gt(namespace, _namespace) {
                    mstore(0, overflowSelector)
                    revert(0, 4)
                }
                namespace := _namespace
            }
            if length {
                let floorTotalSlot := shr(5, length)
                let lastSlot := add(namespace, floorTotalSlot)
                if gt(namespace, lastSlot) {
                    mstore(0, overflowSelector)
                    revert(0, 4)
                }
                let offset := data.offset
                for { let i } lt(i, floorTotalSlot) { i := add(i, 1) } {
                    tstore(add(namespace, i), calldataload(add(offset, shl(5, i))))
                }
                let roundingLength := shl(5, floorTotalSlot)
                let bytesLeft := sub(length, roundingLength)
                if bytesLeft {
                    let bitsLeft := shl(3, bytesLeft)
                    let bitPadding := sub(256, bitsLeft)
                    let rawWord := calldataload(add(offset, roundingLength))
                    let mask := shl(bitPadding, shr(bitPadding, rawWord))
                    tstore(lastSlot, mask)
                }
            }
            if gt(totalCacheSlot, totalSlot) {
                if gt(cacheLength, maxTotalLength) {
                    mstore(0, lengthTooLargeSelector)
                    mstore(4, cacheLength)
                    revert(0, 36)
                }
                if gt(namespace, add(namespace, totalCacheSlot)) {
                    mstore(0, overflowSelector)
                    revert(0, 4)
                }
                let slotLeft := sub(totalCacheSlot, totalSlot)
                namespace := add(namespace, totalSlot)
                for { let j } lt(j, slotLeft) { j := add(j, 1) } {
                    tstore(add(namespace, j), 0)
                }
            }
        }
    }

    /**
     * @dev Copies a `bytes` value from memory into transient storage.
     *
     * The value is stored as a length word followed by its data words. If the
     * length is not a multiple of 32 bytes, the unused bytes in the final word
     * are zeroed to produce a canonical representation.
     *
     * If the new value is shorter than the previously cached value at the same
     * namespace, trailing transient storage slots are cleared to prevent stale
     * data from remaining in the cache.
     *
     * Reverts with `TotalLengthTooLarge` if the value or previous cached value
     * exceeds `MAX_TOTAL_LENGTH`, or with `Overflow` if the transient storage
     * slot arithmetic overflows.
     *
     * @param namespace The transient storage namespace used to cache the value.
     * @param data The memory bytes to cache.
     */
    function _setCacheData(bytes32 namespace, bytes memory data) internal {
        bytes4 lengthTooLargeSelector = TotalLengthTooLarge.selector;
        bytes4 overflowSelector = Overflow.selector;
        uint64 maxTotalLength = MAX_TOTAL_LENGTH;
        assembly ("memory-safe") {
            let length := mload(data)
            if gt(length, maxTotalLength) {
                mstore(0, lengthTooLargeSelector)
                mstore(4, length)
                revert(0, 36)
            }
            let totalSlot := shr(5, add(length, 31))
            let cacheLength := tload(namespace)
            let totalCacheSlot := shr(5, add(cacheLength, 31))
            tstore(namespace, length)
            {
                let _namespace := add(namespace, 1)
                if gt(namespace, _namespace) {
                    mstore(0, overflowSelector)
                    revert(0, 4)
                }
                namespace := _namespace
            }
            if length {
                let floorTotalSlot := shr(5, length)
                let lastSlot := add(namespace, floorTotalSlot)
                if gt(namespace, lastSlot) {
                    mstore(0, overflowSelector)
                    revert(0, 4)
                }
                let offset := add(data, 32)
                for { let i } lt(i, floorTotalSlot) { i := add(i, 1) } {
                    tstore(add(namespace, i), mload(add(offset, shl(5, i))))
                }
                let roundingLength := shl(5, floorTotalSlot)
                let bytesLeft := sub(length, roundingLength)
                if bytesLeft {
                    let bitsLeft := shl(3, bytesLeft)
                    let bitPadding := sub(256, bitsLeft)
                    let rawWord := mload(add(offset, roundingLength))
                    let mask := shl(bitPadding, shr(bitPadding, rawWord))
                    tstore(lastSlot, mask)
                }
            }
            if gt(totalCacheSlot, totalSlot)  {
                if gt(cacheLength, maxTotalLength) {
                    mstore(0, lengthTooLargeSelector)
                    mstore(4, maxTotalLength)
                    revert(0, 36)
                }
                if gt(namespace, add(namespace, totalCacheSlot)) {
                    mstore(0, overflowSelector)
                    revert(0, 4)
                }
                let slotLeft := sub(totalCacheSlot, totalSlot)
                namespace := add(namespace, totalSlot)
                for { let j } lt(j, slotLeft) { j := add(j, 1) } {
                    tstore(add(namespace, j), 0)
                }
            }
        }
    }

    /**
     * @dev Loads a cached `bytes` value from transient storage into memory.
     *
     * The value is expected to be stored as a length word followed by its data
     * words. If the length is not a multiple of 32 bytes, only the bytes within
     * the logical length are copied into memory; unused bytes in the final word
     * are ignored.
     *
     * Reverts with `TotalLengthTooLarge` if the cached length exceeds
     * `MAX_TOTAL_LENGTH`, or with `Overflow` if the transient storage slot
     * arithmetic overflows.
     *
     * @param namespace The transient storage namespace containing the cached value.
     * @return data The cached bytes value reconstructed in memory.
     */
    function _getCacheData(bytes32 namespace) 
        internal 
        view 
        returns (bytes memory data) 
    {
        bytes4 lengthTooLargeSelector = TotalLengthTooLarge.selector;
        bytes4 overflowSelector = Overflow.selector;
        uint64 maxTotalLength = MAX_TOTAL_LENGTH;
        assembly ("memory-safe") {
            data := mload(64)
            let length := tload(namespace)
            if gt(length, maxTotalLength) {
                mstore(0, lengthTooLargeSelector)
                mstore(4, length)
                revert(0, 36)
            }
            mstore(data, length)
            let offset := add(data, 32)
            if length {
                let floorTotalSlot := shr(5, length)
                let totalSlot := shr(5, add(length, 31))
                let lastSlot := add(namespace, floorTotalSlot)
                {
                    let _namespace := add(namespace, 1)
                    if gt(namespace, _namespace) {
                        mstore(0, overflowSelector)
                        revert(0, 4)
                    }
                    namespace := _namespace
                    if gt(namespace, lastSlot) {
                        mstore(0, overflowSelector)
                        revert(0, 4)
                    }
                }
                for { let i } lt(i, floorTotalSlot) { i := add(i, 1) } {
                    mstore(add(offset, shl(5, i)), tload(add(namespace, i)))
                }
                let roundingLength := shl(5, floorTotalSlot)
                let bytesLeft := sub(length, roundingLength)
                if bytesLeft {
                    let bitsLeft := shl(3, bytesLeft)
                    let bitPadding := sub(256, bitsLeft)
                    let rawWord := tload(lastSlot)
                    let mask := shl(bitPadding, shr(bitPadding, rawWord))
                    mstore(add(offset, roundingLength), mask)
                }
                offset := add(offset, shl(5, totalSlot))
            }
            mstore(64, offset)
        }
    }

    function _markPhase1Pass() internal {
        emit ContextPhaseSuccess();
        phase = Phase.VALIDATION;
    }

    function _markPhase2Pass() internal {
        emit ValidateSenderPhaseSuccess();
        phase = Phase.EXECUTION;
    }

    /**
     * @dev Stores a value in transient storage at `key`.
     *
     * This helper provides a high-level Solidity-callable wrapper around the
     * `TSTORE` instruction.
     *
     * @param key The transient storage key.
     * @param value The value to store.
     */
    function _tstore(bytes32 key, uint256 value) internal {
        assembly ("memory-safe") {
            tstore(key, value)
        }
    }

    /**
     * @dev Loads a value from transient storage at `key`.
     *
     * This helper provides a high-level Solidity-callable wrapper around the
     * `TLOAD` instruction.
     *
     * @param key The transient storage key.
     * @return value The value stored at `key`.
     */
    function _tload(bytes32 key) internal view returns (uint256 value) {
        assembly ("memory-safe") {
            value := tload(key)
        }
    }

    /**
     * @dev Decodes the `offset` and `length` fields from `sliceInfo`.
     *
     * The upper 128 bits encode `offset` and the lower 128 bits encode `length`,
     * as specified by the Solver protocol.
     *
     * @param sliceInfo The packed slice information.
     * @return offset The byte offset of the execution envelope slice.
     * @return length The length of the execution envelope slice.
     */
    function _getOffsetAndLength(uint256 sliceInfo) 
        internal 
        pure 
        returns (uint256 offset, uint256 length) 
    {
        return (sliceInfo >> 128, sliceInfo & SLICE_INFO_MASKING);
    }

    /**
     * @dev Derives a transient storage slot from a namespace and an index.
     *
     * The returned slot is equivalent to `keccak256(abi.encode(namespace, index))`
     * while computing the hash directly in assembly to avoid the intermediate
     * memory allocation performed by high-level ABI encoding.
     *
     * @param namespace The logical transient storage namespace.
     * @param index The index within the namespace.
     * @return slot The derived transient storage slot.
     */
    function _getHashedSlot(
        bytes32 namespace,
        uint256 index
    ) internal pure returns (bytes32 slot) {
        assembly ("memory-safe") {
            mstore(0, namespace)
            mstore(32, index)
            slot := keccak256(0, 64)
        }
    }

    /**
     * @dev Decodes an execution envelope into its Executor and Intent.
     *
     * The first 20 bytes of `intentInfo` encode the Executor address, while the
     * remaining bytes encode the Intent.
     *
     * @param intentInfo The execution envelope encoded as `Executor || Intent`.
     * @return executor The Executor address encoded in the first 20 bytes.
     * @return intent The Intent bytes following the Executor address.
     */
    function _decodeIntentInfo(
        bytes calldata intentInfo
    ) internal pure returns (
        address executor,
        bytes calldata intent
    ) {
        return (address(bytes20(intentInfo[0 : 20])), intentInfo[20 : ]);
    }

    /**
     * @dev Returns a slice of `envelopeTx` representing the execution envelope.
     *
     * The slice is determined by the `offset` and `length` decoded from
     * `sliceInfo`. The returned bytes consist of the Executor address followed
     * by the Intent.
     *
     * @param offset The starting byte offset within `envelopeTx`.
     * @param length The length of the execution envelope slice.
     * @param envelopeTx The original envelope transaction.
     * @return intentInfo The selected execution envelope slice.
     */
    function _sliceEnvelopeTx(
        uint256 offset,
        uint256 length,
        bytes calldata envelopeTx
    ) internal pure returns (
        bytes calldata intentInfo
    ) {
        return envelopeTx[offset : offset + length];
    }

    /**
     * save free memory pointer.
     * save "free memory" pointer, so that it can be restored later using restoreFreePtr.
     * This reduce unneeded memory expansion, and reduce memory expansion cost.
     * NOTE: all dynamic allocations between saveFreePtr and restoreFreePtr MUST NOT be used after restoreFreePtr is called.
     */
    function _getFreePtr() internal pure returns (uint256 ptr) {
        assembly ("memory-safe") {
            ptr := mload(0x40)
        }
    }

    /**
     * restore free memory pointer.
     * any allocated memory since saveFreePtr is cleared, and MUST NOT be accessed later.
     */
    function _restoreFreePtr(uint256 ptr) internal pure {
        assembly ("memory-safe") {
            mstore(0x40, ptr)
        }
    }
}
