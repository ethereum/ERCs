// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./ICallDecryptionOracle.sol";

/**
 * @title Call Decryption Oracle Contract. On-chain proxy for an off-chain call-decryption-oracle
 * @notice Reference implementation of ICallDecryptionOracle, see ERC-8087.
 *         The fulfillment is idempotent. If the off-chain oracle oberserves an event for
 *         the same requestId twice, the second fulfillment will not be propagated
 *         to the requester.
 *
 * Gas forwarding:
 * - Off-chain oracle controls tx gasLimit (total budget).
 * - Proxy forwards "all but a reserve" to callback, keeping gasReserve to execute catch + emit + finalize.
 *
 * @author Christian Fries.
 * @dev Off-chain operator is expected to decrypt and call fulfill* as owner.
 */
contract CallDecryptionOracle is ICallDecryptionOracle {
    /* ---------------- Errors ---------------- */
    error NotOracle();
    error IncorrectFee();
    error RequestNotFound(uint256 requestId);

    /* -------------------------------- Types -------------------------------- */

    struct PendingCall {
        address requester;
        bytes32 argsHash;

        // Only used for plain-call variant
        address targetContract;
        bytes4  selector;
        uint256 validUntilBlock;
        bool    useStoredDescriptor;
    }

    /* ------------------------------- Storage -------------------------------- */

    address public oracle;             // off-chain relayer
    address public owner;              // admin

    bytes public publicKey;
    bytes32 public publicKeyId;   // = keccak256(publicKey)

    uint256 public feeCall;           // in wei (ETH on mainnet / POL on Polygon)
    uint256 public feeEncryptedCall;

    /// @notice Gas reserve kept by fulfill* after forwarding gas to the callback.
    /// @dev Unit: gas (NOT wei). Purpose: ensure fulfill* can still run catch + emit + finalize.
    uint256 public gasReserve = 50_000;

    uint256 public lastRequestId;
    mapping(uint256 => PendingCall) public pendingCalls;

    /* ---------------- Events ---------------- */

    event FeesUpdated(uint256 feeCall, uint256 feeEncryptedCall);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event FeesWithdrawn(address indexed to, uint256 amount);

    event GasReserveUpdated(uint256 gasReserve);

    /* ---------------- Modifiers ---------------- */

    modifier onlyOracle() { if (msg.sender != oracle) revert NotOracle(); _; }
    modifier onlyOwner() { require(msg.sender == owner, "not owner"); _; }

    /* --- constructor ------------------------------------------------------ */

    constructor(address _oracle, bytes memory _publicKey) {
        require(_oracle != address(0), "CallDecryptionOracle: oracle zero address");
        require(_publicKey.length != 0, "CallDecryptionOracle: empty public key");

        oracle = _oracle;
        owner  = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);

        publicKey = _publicKey;
        publicKeyId = keccak256(_publicKey);
        emit PublicKeyUpdated(publicKey, publicKeyId);
    }

    /* ---------------- Admin ---------------- */

    /**
     * @notice transfer ownership of this oracle.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "CallDecryptionOracle: owner zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /**
     * @notice Change oracle address (e.g. upgrade or switch instance).
     */
    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "CallDecryptionOracle: oracle zero address");
        oracle = address (_oracle);
    }

    function setFees(uint256 callWei, uint256 encryptedCallWei) external onlyOwner {
        feeCall = callWei;
        feeEncryptedCall = encryptedCallWei;
        emit FeesUpdated(callWei, feeEncryptedCall);
    }

    function setGasReserve(uint256 newReserve) external onlyOwner {
        // Conservative bounds: avoid accidental misconfiguration (too small to finish, too large to be useful).
        require(newReserve >= 10_000 && newReserve <= 300_000, "CallDecryptionOracle: reserve out of bounds");
        gasReserve = newReserve;
        emit GasReserveUpdated(newReserve);
    }

    /**
     * @notice Route accumulated fees to the off-chain oracle EOA or a treasury.
     */
    function withdraw(uint256 amount, address payable to) public onlyOwner {
        require(to != address(0), "CallDecryptionOracle: zero address");
        require(amount <= address(this).balance, "CallDecryptionOracle: insufficient balance");

        (bool s, ) = to.call{value: amount}("");
        require(s, "CallDecryptionOracle: withdraw failed");

        emit FeesWithdrawn(to, amount);
    }

    /**
     * @notice Transfers all fees to the external oracle
     */
    function fundOracle() external onlyOwner {
        uint256 amount = address(this).balance;
        require(amount > 0, "CallDecryptionOracle: no balance");

        withdraw(amount, payable(oracle));
    }

    /* --- Key management ------------------------------------------------------ */


    function setPublicKey(bytes calldata newPublicKey) external onlyOwner {
        require(newPublicKey.length != 0, "CallDecryptionOracle: empty public key");

        publicKey = newPublicKey;
        publicKeyId = keccak256(newPublicKey);
        emit PublicKeyUpdated(publicKey, publicKeyId);
    }

    function getPublicKey() external view override returns (bytes memory key, bytes32 keyId) {
        return (publicKey, publicKeyId);
    }


    /* ---------------- Requests ------------------------- */

    function requestCall(
        CallDescriptor           calldata callDescriptor,
        EncryptedHashedArguments calldata encArgs,
        bytes                    calldata secondFactor
    ) external payable override returns (uint256 requestId) {
        if (msg.value != feeCall) revert IncorrectFee();

        require(callDescriptor.targetContract != address(0), "CallDecryptionOracle: no target");

        requestId = ++lastRequestId;

        PendingCall storage p = pendingCalls[requestId];
        p.requester       = msg.sender;
        p.argsHash        = encArgs.argsHash;
        p.targetContract  = callDescriptor.targetContract;
        p.selector        = callDescriptor.selector;
        p.validUntilBlock = callDescriptor.validUntilBlock;
        p.useStoredDescriptor = true;

        emit CallRequested(
            requestId,
            msg.sender,
            callDescriptor.targetContract,
            callDescriptor.selector,
            callDescriptor.validUntilBlock,
            encArgs.publicKeyId,
            encArgs.ciphertext,
            encArgs.argsHash,
            secondFactor
        );
    }

    function requestEncryptedCall(
        EncryptedCallDescriptor   calldata encCall,
        EncryptedHashedArguments  calldata encArgs,
        bytes                     calldata secondFactor
    ) external payable override returns (uint256 requestId) {
        if (msg.value != feeEncryptedCall) revert IncorrectFee();

        require(encCall.ciphertext.length > 0, "CallDecryptionOracle: empty call ciphertext");
        require(encArgs.ciphertext.length > 0, "CallDecryptionOracle: empty args ciphertext");

        requestId = ++lastRequestId;

        PendingCall storage p = pendingCalls[requestId];
        p.requester           = msg.sender;
        p.argsHash            = encArgs.argsHash;
        p.useStoredDescriptor = false;

        emit EncryptedCallRequested(
            requestId,
            msg.sender,
            encCall.publicKeyId,
            encCall.ciphertext,
            encArgs.publicKeyId,
            encArgs.ciphertext,
            encArgs.argsHash,
            secondFactor
        );
    }

    /* ------------------------------ Fulfillments ---------------------------- */

    /**
     * @notice Fulfillment for requestCall.
     */
    function fulfillCall(
        uint256          requestId,
        bytes            calldata argsPlain
    ) external override onlyOracle {
        PendingCall storage p = pendingCalls[requestId];

        // request state check
        if (p.requester == address(0)) revert RequestNotFound(requestId);
        require(p.useStoredDescriptor, "CallDecryptionOracle: not a plain call request");

        // execute call: callback(requestId, argsPlain)
        bytes memory callData = abi.encodeWithSelector(
            p.selector,
            requestId,
            argsPlain
        );

        // Forward as much as possible while keeping a reserve for catch + event + finalization.
        uint256 g = _gasToForward(gasReserve);
        require(g > 0, "CallDecryptionOracle: insufficient gas to forward");

        // Low level call
        (bool success, bytes memory ret) = p.targetContract.call{gas: g}(callData);

        if (!success) {
            emit CallRejected(requestId, RejectionReason.TargetCallFailed, ret);
            delete pendingCalls[requestId];
        }
        else {
            emit CallFulfilled(requestId, ret);
            delete pendingCalls[requestId];
        }
    }

    function fulfillEncryptedCall(
        uint256          requestId,
        CallDescriptor   calldata callDescriptor,
        bytes            calldata argsPlain
    ) external override onlyOracle {
        PendingCall storage p = pendingCalls[requestId];

        // request state check
        if (p.requester == address(0)) revert RequestNotFound(requestId);
        require(!p.useStoredDescriptor, "CallDecryptionOracle: not an encrypted-call request");

        // execute call: callback(requestId, argsPlain)
        bytes memory callData = abi.encodeWithSelector(
            callDescriptor.selector,
            requestId,
            argsPlain
        );

        // Forward as much as possible while keeping a reserve for catch + event + finalization.
        uint256 g = _gasToForward(gasReserve);
        require(g > 0, "CallDecryptionOracle: insufficient gas to forward");

        // Low level call
        (bool success, bytes memory ret) = callDescriptor.targetContract.call{gas: g}(callData);

        if (!success) {
            emit CallRejected(requestId, RejectionReason.TargetCallFailed, ret);
            delete pendingCalls[requestId];
        }
        else {
            emit CallFulfilled(requestId, ret);
            delete pendingCalls[requestId];
        }
    }

    function rejectCall(
        uint256 requestId,
        RejectionReason reason,
        bytes calldata details  // optional extra info, may be empty
    ) external override onlyOracle {
        PendingCall storage p = pendingCalls[requestId];
        require(p.requester != address(0), "CallDecryptionOracle: request not found");
        emit CallRejected(requestId, reason, details);
        delete pendingCalls[requestId];
    }

    /* ------------------------------- Internals ------------------------------ */

    function _gasToForward(uint256 reserve) internal view returns (uint256) {
        uint256 g = gasleft();
        if (g <= reserve) return 0;
        // EIP-150 caps forwarded gas to <= g - g/64 anyway; this keeps explicit headroom.
        return g - reserve;
    }
}
