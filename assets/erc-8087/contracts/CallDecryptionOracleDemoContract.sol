// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.23;

/* ─────────────────────────────────────────────────────────────────────────────
 * Interface kept inline so the file stays single-file Remix-friendly
 * ────────────────────────────────────────────────────────────────────────────*/

interface ICallDecryptionOracle {
    enum RejectionReason { Unspecified, RequestNotFound, Expired, ArgsHashMismatch, CallerNotEligible, OperatorPolicy }
    struct ArgsDescriptor { address[] eligibleCaller; bytes argsPlain; }
    struct EncryptedHashedArguments { bytes32 argsHash; bytes32 publicKeyId; bytes ciphertext; }
    struct CallDescriptor { address targetContract; bytes4 selector; uint256 validUntilBlock; }
    struct EncryptedCallDescriptor { bytes32 publicKeyId; bytes ciphertext; }
    function requestEncryptedCall(EncryptedCallDescriptor calldata encCall, EncryptedHashedArguments  calldata encArgs) external payable returns (uint256 requestId);
    function requestCall(CallDescriptor calldata callDescriptor, EncryptedHashedArguments  calldata encArgs) external payable returns (uint256 requestId);
    function fulfillCall(uint256 requestId, bytes calldata argsPlain) external;
    function fulfillEncryptedCall(uint256 requestId, CallDescriptor calldata callDescriptor, bytes calldata argsPlain) external;
    function rejectCall(uint256 requestId, RejectionReason reason, bytes calldata details) external;
}

/**
 * @title Contract illustrating use of the Call Decryption Oracle Contract.
 * @notice Simple contract that can be used for demonstration and testing.
 * @author Christian Fries
 */
contract CallDecryptionOracleDemoContract {

    struct ExecutionRecord {
        uint256 clientId;
        uint256 phase;                  // 0 = new, 1 = stored, 2 = requested, 3 = callback, 4 = routed, 5 = final
        // --- phase 0->1: store encrypted hashed arguments --
        address caller;
        ICallDecryptionOracle.CallDescriptor callDescriptor;
        bytes   argsEncrypted;
        bytes32 argsHash;
        // --- phase 1->2: request decryption --
        uint256 requestId;
        // --- phase 2->3: receive decryption --
        bytes   argsPlain;
        bytes32 argsHashComputed;
        // --- phase 3->4: routing to func(uint256, string, uint256) ---
        // --- phase 4->5: receive decoded arguments
        uint256  arg1;
        string   arg2;
        uint256  arg3;
    }

    /* ------------------------------- Storage -------------------------------- */

    ICallDecryptionOracle public oracle;     // off-chain relayer

    /**
     * @notice All executions grouped by clientId.
     */
    mapping(uint256 => ExecutionRecord) public executionsByClientId;

    /// @notice map oracle requestId -> clientId so that callbacks can find their record
    mapping(uint256 => uint256) public clientIdByRequestId;

    /// @notice used by finalTargetFunction to know which record to write to
    uint256 public currentClientId;

    /**
     * Instantiate. Link to a specific oracle contract.
     *
     * @param _oracle The call decryption oracle contract.
     */
    constructor(address _oracle) {
        oracle = ICallDecryptionOracle(_oracle);
    }

    /* ---------------------------------------------------------------------- */
    /* Phase 1: store arguments and build CallDescriptor                      */
    /* ---------------------------------------------------------------------- */

    /**
     * @param clientId Client ID for this test case.
     * @param argsEncrypted Encryption of ArgDescriptor (contaings eligibleCaller and argsPlain)
     * @param argsHash Hash of argsPlain
     */
    function step1_storeArguments(
        uint256 clientId,
        bytes   calldata argsEncrypted,
        bytes32 argsHash
    ) external {

        ExecutionRecord storage rec = executionsByClientId[clientId];

        require(rec.phase == 0, "id used / wrong phase");

        rec.clientId = clientId;
        rec.phase    = 1;
        rec.caller   = msg.sender;

        /**
         * These arguments could also be passed and chosen freely, but for the sake of this
         * demo we build them here, defining this contract as the target.
         */
        address targetContract    = address(this);
        // Assumption: callback signature is (uint256 requestId, bytes argsPlain)
        string memory selectorSig = "routingTargetFunction(uint256,bytes)";
        uint256 validUntilBlock   = 0; // no expiry

        // Build CallDescriptor
        bytes4 selector = bytes4(keccak256(bytes(selectorSig)));

        // Assumption: CallDescriptor is (address targetContract, bytes4 selector, uint256 validUntilBlock)
        ICallDecryptionOracle.CallDescriptor memory callDescriptor = ICallDecryptionOracle.CallDescriptor(
            targetContract,
            selector,
            validUntilBlock
        );

        rec.callDescriptor = callDescriptor;
        rec.argsEncrypted  = argsEncrypted;
        rec.argsHash       = argsHash;
    }

    /* ---------------------------------------------------------------------- */
    /* Phase 2: send request to oracle                                        */
    /* ---------------------------------------------------------------------- */

    function step2_execute(
        uint256 clientId
    ) external {

        ExecutionRecord storage rec = executionsByClientId[clientId];
        require(rec.phase == 1, "wrong phase");

        ICallDecryptionOracle.CallDescriptor memory callDescriptor = rec.callDescriptor;
        ICallDecryptionOracle.EncryptedHashedArguments memory encArgs = ICallDecryptionOracle.EncryptedHashedArguments(rec.argsHash, 0, rec.argsEncrypted);

        rec.phase = 2;

        // Assumption: requestCall returns a requestId
        uint256 requestId = oracle.requestCall(
            callDescriptor,
            encArgs
        );

        rec.requestId = requestId;

        clientIdByRequestId[requestId] = clientId;
    }

    /* ---------------------------------------------------------------------- */
    /* Oracle callback: routingTargetFunction                                 */
    /* ---------------------------------------------------------------------- */

    /**
     * @notice Callback from the oracle. The oracle supplies the requestId and the
     *         decrypted plain arguments (ABI-encoded for finalTargetFunction).
     */
    function routingTargetFunction(
        uint256 requestId,
        bytes calldata argsPlain
    ) external {
        // Remove this require if you want to call it manually from Remix with some other address
        require(msg.sender == address(oracle), "only oracle");

        uint256 clientId = clientIdByRequestId[requestId];
        ExecutionRecord storage rec = executionsByClientId[clientId];

        require(rec.phase == 2, "wrong phase");

        rec.phase     = 3;
        rec.argsPlain = argsPlain;
        rec.argsHashComputed = keccak256(argsPlain);    // Verify should compare this to rec.argsHash
    }

    /* ---------------------------------------------------------------------- */
    /* Phase 4: route decrypted args to finalTargetFunction                   */
    /* ---------------------------------------------------------------------- */

    function step3_routing(
        uint256 clientId
    ) external {

        ExecutionRecord storage rec = executionsByClientId[clientId];
        require(rec.phase == 3, "wrong phase");

        rec.phase = 4;

        // For storage within this demo only:
        currentClientId = clientId;

        // This call will fail if the signature does not match or argsPlain is malformed.
        bytes memory argsPlain = rec.argsPlain;

        (bool success, ) = address(this).call(
            abi.encodePacked(this.finalTargetFunction.selector, argsPlain)
        );
        require(success, "finalTargetFunction call failed");
    }

    /* ---------------------------------------------------------------------- */
    /* Final target: prove we can route and decode                            */
    /* ---------------------------------------------------------------------- */

    /**
     * @notice Proof that we can receive the argsPlain with a given signature.
     *         This call will fail if the signature does not match.
     */
    function finalTargetFunction(
        uint256 arg1,
        string calldata arg2,
        uint256 arg3
    ) external {
        ExecutionRecord storage rec = executionsByClientId[currentClientId];

        require(rec.phase == 4, "wrong phase");

        rec.phase = 5;
        rec.arg1  = arg1;
        rec.arg2  = arg2;
        rec.arg3  = arg3;
    }

    /* ---------------------------------------------------------------------- */
    /* Helper                                                                  */
    /* ---------------------------------------------------------------------- */

    function getResult(uint256 clientId) external view returns (
        uint256 phase,
        address caller,
        address targetContract,
        bytes memory argsEncrypted,
        bytes32 argsHash,
        uint256 requestId,
        bytes memory argsPlain,
        bytes32 argsHashComputed,
        uint256 arg1,
        string memory arg2,
        uint256 arg3
    ) {
        ExecutionRecord storage r = executionsByClientId[clientId];
        return (
        r.phase,
        r.caller,
        r.callDescriptor.targetContract,
        r.argsEncrypted,
        r.argsHash,
        r.requestId,
        r.argsPlain,
        r.argsHashComputed,
        r.arg1,
        r.arg2,
        r.arg3
        );
    }
}
