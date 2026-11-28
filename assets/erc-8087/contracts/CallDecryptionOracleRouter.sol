// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.23;

/* ─────────────────────────────────────────────────────────────────────────────
 * Interface kept inline so the file stays single-file Remix-friendly
 * ────────────────────────────────────────────────────────────────────────────*/

interface ICallDecryptionOracle {
    enum RejectionReason { Unspecified, RequestNotFound, Expired, ArgsHashMismatch, CallerNotEligible, OperatorPolicy }

    struct ArgsDescriptor { address[] eligibleCaller; bytes argsPlain; }
    struct EncryptedHashedArguments { bytes32 argsHash; bytes32 publicKeyId; bytes   ciphertext; }
    struct CallDescriptor { address targetContract; bytes4 selector; uint256 validUntilBlock; }
    struct EncryptedCallDescriptor { bytes32 publicKeyId; bytes ciphertext; }

    function requestCall(
        CallDescriptor            calldata callDescriptor,
        EncryptedHashedArguments  calldata encArgs,
        bytes                     calldata secondFactor
    ) external payable returns (uint256 requestId);

    function requestEncryptedCall(
        EncryptedCallDescriptor   calldata encCall,
        EncryptedHashedArguments  calldata encArgs,
        bytes                     calldata secondFactor
    ) external payable returns (uint256 requestId);

    function fulfillCall(
        uint256 requestId,
        bytes   calldata argsPlain
    ) external;

    function fulfillEncryptedCall(
        uint256        requestId,
        CallDescriptor calldata callDescriptor,
        bytes          calldata argsPlain
    ) external;

    function rejectCall(
        uint256        requestId,
        RejectionReason reason,
        bytes          calldata details
    ) external;
}

/**
 * @title Contract that may serve as a router for encrypted hashed calls.
 *
 * @notice Simple contract that can serve as a router for encrypted hashed calls
 *   and that can be used for demonstration and testing. Illustrating use of the
 *   Call Decryption Oracle Contract.
 * @author Christian Fries
 */
contract CallDecryptionOracleRouterContract {

    struct ExecutionRecord {
        uint256 clientId;
        uint256 phase;   // 0 = new, 1 = stored, 2 = requested, 3 = callback, 4 = routed, 5 = final

        // --- phase 0->1: store encrypted hashed arguments & descriptors --
        address caller;
        ICallDecryptionOracle.CallDescriptor routingTargetCallDescriptor;
        ICallDecryptionOracle.CallDescriptor decryptionCallbackCallDescriptor;
        bytes   argsEncrypted;
        bytes32 argsHash;

        // --- phase 1->2: request decryption --
        uint256 requestId;

        // --- phase 2->3: receive decryption --
        bytes   argsPlain;
        bytes32 argsHashComputed;

        // --- phase 3->4: routing to target ---
        bool    routingSuccess;

        // --- phase 4->5: (DEMO MODE) decoded arguments of demo target ---
        uint256  arg1;
        string   arg2;
        uint256  arg3;
    }

    struct ClientKey {
        address caller;
        uint256 clientId;
    }

    /* ------------------------------- Storage -------------------------------- */

    ICallDecryptionOracle public oracle;   // on-chain decryption oracle contract
    address               public owner;    // can update oracle address

    /**
     * @notice All executions grouped by caller and clientId.
     */
    mapping(address => mapping(uint256 => ExecutionRecord)) public executionsByClientAndId;

    /// @notice map oracle requestId -> (caller, clientId) so that callbacks can find their record
    mapping(uint256 => ClientKey) public clientKeyByRequestId;

    /// @notice used by demoTargetFunction to know which record to write to
    address public currentCaller;
    uint256 public currentClientId;

    /* ------------------------------ Modifiers ------------------------------- */

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    /**
     * Instantiate. Link to a specific oracle contract.
     *
     * @param _oracle The call decryption oracle contract.
     */
    constructor(address _oracle) {
        owner  = msg.sender;
        oracle = ICallDecryptionOracle(_oracle);
    }

    /**
     * @notice Change oracle address (e.g. upgrade or switch instance).
     */
    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "oracle zero");
        oracle = ICallDecryptionOracle(_oracle);
    }

    /**
     * @notice Optional: transfer ownership of this demo/router.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "owner zero");
        owner = newOwner;
    }

    /* ---------------------------------------------------------------------- */
    /* Phase 1: store arguments and build CallDescriptors                     */
    /* ---------------------------------------------------------------------- */

    /**
     * Step 1: store an encrypted call.
     *
     * @param clientId           Client ID for this test case (local within msg.sender namespace).
     * @param callDescriptorPlain ABI-encoded ICallDecryptionOracle.CallDescriptor for the FINAL target
     *                            (for the routing step, e.g. demoTargetFunction).
     * @param argsEncrypted      Encryption of ArgsDescriptor (contains eligibleCaller + argsPlain).
     * @param argsHash           Hash of argsPlain (or ArgsDescriptor, depending on spec).
     */
    function store(
        uint256 clientId,
        bytes   calldata callDescriptorPlain,
        bytes   calldata argsEncrypted,
        bytes32 argsHash
    ) external {
        address caller = msg.sender;
        ExecutionRecord storage rec = executionsByClientAndId[caller][clientId];

        require(rec.phase == 0, "id used / wrong phase");

        rec.clientId = clientId;
        rec.phase    = 1;
        rec.caller   = caller;

        // Decode the call descriptor for the FINAL routed call
        ICallDecryptionOracle.CallDescriptor memory routingTargetCallDescriptor = decodeCallDescriptor(callDescriptorPlain);

        rec.routingTargetCallDescriptor = routingTargetCallDescriptor;

        /**
         * The callback of the decryption oracle is this contract itself.
         * The contact will then perform a rounting to the specified routingTargetCallDescriptor.
         */
        ICallDecryptionOracle.CallDescriptor memory decryptionCallbackCallDescriptor = ICallDecryptionOracle.CallDescriptor({
            targetContract:   address(this),
            selector:         bytes4(keccak256(bytes("decryptedArgumentsReceiver(uint256,bytes)"))),
            validUntilBlock:  routingTargetCallDescriptor.validUntilBlock // inherit
        });

        rec.decryptionCallbackCallDescriptor    = decryptionCallbackCallDescriptor;
        rec.argsEncrypted                       = argsEncrypted;
        rec.argsHash                            = argsHash;
    }

    /* ---------------------------------------------------------------------- */
    /* Phase 2: send request to oracle                                        */
    /* ---------------------------------------------------------------------- */

    /**
     * @notice Send decryption request to oracle.
     * @dev Marked payable so you can forward ETH for oracle fees if needed.
     */
    function decrypt(
        uint256 clientId
    ) external payable {
        address caller = msg.sender;
        ExecutionRecord storage rec = executionsByClientAndId[caller][clientId];
        require(rec.phase == 1, "wrong phase");

        rec.phase = 2;

        // Call the call decryption oracle - forward any msg.value as fee to the oracle (if it expects one)
        uint256 requestId = oracle.requestCall{value: msg.value}(
            rec.decryptionCallbackCallDescriptor,
            ICallDecryptionOracle.EncryptedHashedArguments(rec.argsHash, 0, rec.argsEncrypted),
            ""
        );

        rec.requestId = requestId;

        clientKeyByRequestId[requestId] = ClientKey({caller:   caller, clientId: clientId});
    }

    /* ---------------------------------------------------------------------- */
    /* Oracle callback: decryptedArgumentsReceiver                            */
    /* ---------------------------------------------------------------------- */

    /**
     * @notice Callback from the oracle. The oracle supplies the requestId and the
     *         decrypted plain arguments (ABI-encoded for the target function).
     */
    function decryptedArgumentsReceiver(
        uint256 requestId,
        bytes calldata argsPlain
    ) external {
        // Remove this require if you want to call manually from Remix
        require(msg.sender == address(oracle), "only oracle");

        ClientKey memory key = clientKeyByRequestId[requestId];
        ExecutionRecord storage rec = executionsByClientAndId[key.caller][key.clientId];

        require(rec.phase == 2, "wrong phase");

        rec.phase           = 3;
        rec.argsPlain       = argsPlain;
        rec.argsHashComputed = keccak256(argsPlain);
        // Depending on your spec, you may want to check inclusion of eligibleCaller here off-chain.
    }

    /* ---------------------------------------------------------------------- */
    /* Phase 4: route decrypted args to target function                       */
    /* ---------------------------------------------------------------------- */

    function execute(
        uint256 clientId
    ) external {
        address caller = msg.sender;
        ExecutionRecord storage rec = executionsByClientAndId[caller][clientId];
        require(rec.phase == 3, "wrong phase");

        // Optional on-chain integrity check
        require(rec.argsHash == rec.argsHashComputed, "argsHash mismatch");

        rec.phase = 4;

        // For storage within this demo only:
        currentCaller   = caller;
        currentClientId = clientId;

        ICallDecryptionOracle.CallDescriptor memory routingCallDescr = rec.routingTargetCallDescriptor;

        // Route to final target with already ABI-encoded argsPlain
        bool success;
        if(routingCallDescr.targetContract != address (0)) {
            (success, ) = routingCallDescr.targetContract.call(
                abi.encodePacked(routingCallDescr.selector, rec.argsPlain)
            );
        }
        else {
            string memory selectorSig = "demoTargetFunction(uint256,string,uint256)";
            bytes4 demoTargetSelector = bytes4(keccak256(bytes(selectorSig)));
            (success, ) = address (this).call(
                abi.encodePacked(demoTargetSelector, rec.argsPlain)
            );
        }

        rec.routingSuccess = success;
    }

    /* ---------------------------------------------------------------------- */
    /* Final target: prove we can route and decode                            */
    /* ---------------------------------------------------------------------- */

    /**
     * @notice Proof that we can receive the argsPlain with a given signature.
     *         This call will fail if the signature does not match.
     */
    function demoTargetFunction(
        uint256 arg1,
        string calldata arg2,
        uint256 arg3
    ) external {
        ExecutionRecord storage rec = executionsByClientAndId[currentCaller][currentClientId];

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
        uint256        phase,
        address        caller,
        address        targetContract,
        bytes4         targetSelector,
        bytes memory   argsEncrypted,
        bytes32        argsHash,
        uint256        requestId,
        bytes memory   argsPlain,
        bytes32        argsHashComputed,
        bool           routingSuccess
    ) {
        // Result is always looked up for msg.sender + clientId
        ExecutionRecord storage r = executionsByClientAndId[msg.sender][clientId];
        return (
            r.phase,
            r.caller,
            r.routingTargetCallDescriptor.targetContract,
            r.routingTargetCallDescriptor.selector,
            r.argsEncrypted,
            r.argsHash,
            r.requestId,
            r.argsPlain,
            r.argsHashComputed,
            r.routingSuccess
        );
    }

    function getDemoTargetValues(uint256 clientId) external view returns (
        uint256        arg1,
        string memory  arg2,
        uint256        arg3
    ) {
        // Result is always looked up for msg.sender + clientId
        ExecutionRecord storage r = executionsByClientAndId[msg.sender][clientId];
        return (
            r.arg1,
            r.arg2,
            r.arg3
        );
    }

    function decodeCallDescriptor(
        bytes calldata data
    ) internal pure returns (ICallDecryptionOracle.CallDescriptor memory cd) {
        // Support "null / empty call data": interpret empty bytes as a CallDescriptor with targetContract = address(0)
        if (data.length == 0) {
            return ICallDecryptionOracle.CallDescriptor({
                targetContract:  address(0),
                selector:        bytes4(0),
                validUntilBlock: 0
            });
        }

        (cd) = abi.decode(data, (ICallDecryptionOracle.CallDescriptor));
    }
}
