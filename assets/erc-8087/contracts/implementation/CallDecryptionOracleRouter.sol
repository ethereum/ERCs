// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 *  @title Generic Call Router for Call Decryption Oracle
 *  @notice Example router/adapter contract that can be used as the callback/target
 *          for a Call Decryption Oracle. It verifies a pre-committed argsHash under
 *          a clientId and then forwards the call to an arbitrary target contract
 *          using a routing envelope encoded in argsPlain.
 * 
 *  @dev Expected callback signature from the Call Decryption Oracle:
 *       executeWithVerification(uint256 clientId, bytes argsPlain)
 * 
 *       The router expects argsPlain to be encoded as:
 * 
 *       abi.encode(
 *           address routingTarget,
 *           bytes4  routingSelector,
 *           bytes   routingCalldata
 *       )
 * 
 *       where routingCalldata is already ABI-encoded arguments for routingSelector.
 *       The router recomputes keccak256(argsPlain) and checks it against a pre-
 *       committed hash for the given clientId, then forwards:
 * 
 *           routingTarget.call(abi.encodePacked(routingSelector, routingCalldata))
 *
 */
contract CallDecryptionOracleRouter {

    /**
     *  @notice Address of the on-chain Call Decryption Oracle that is allowed to
     *          call executeWithVerification.
     */
    address public immutable callDecryptionOracle;

    /**
     *  @notice Owner allowed to register or update argsHashByClientId.
     */
    address public owner;

    /**
     *  @notice Mapping from clientId to pre-committed argsHash.
     *          The argsHash is defined as keccak256(argsPlain) for the encrypted payload.
    mapping(uint256 => bytes32) public argsHashByClientId;

    event Registered(uint256 indexed clientId, bytes32 argsHash);
    event Routed(
        uint256 indexed clientId,
        address indexed routingTarget,
        bytes4  routingSelector,
        bytes   routingCalldata,
        bytes   returnData
    );
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error UnknownClientId(uint256 clientId);
    error HashMismatch();
    error TargetCallFailed();
    error NotOwner();

    modifier onlyOracle() {
        require(msg.sender == callDecryptionOracle, "Router: caller is not oracle");
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /**
     *  @param _callDecryptionOracle Address of the CallDecryptionOracle contract
     *         which will call executeWithVerification.
     */
    constructor(address _callDecryptionOracle) {
        require(_callDecryptionOracle != address(0), "Router: oracle is zero address");
        callDecryptionOracle = _callDecryptionOracle;
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /**
     *  @notice Transfer ownership to a new owner.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Router: new owner is zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /**
     *  @notice Init phase: register the hash of the arguments that should later be used.
     *  @param clientId Application-level identifier linking to this set of arguments.
     *  @param argsHash Commitment to keccak256(argsPlain) for the encrypted payload.
     * 
     *  @dev Restricted to the router owner to avoid arbitrary overwrites of clientId.
     */
    function registerArguments(uint256 clientId, bytes32 argsHash) external onlyOwner {
        argsHashByClientId[clientId] = argsHash;
        emit Registered(clientId, argsHash);
    }

    /**
     *  @notice Execution phase callback: verify argsPlain against the pre-committed hash
     *          for clientId, decode the routing envelope, and forward the call to the
     *          indicated target contract.
     * 
     *  @param clientId Business correlation id.
     *  @param argsPlain Decrypted argument payload bytes. Must be encoded as
     *         abi.encode(address routingTarget, bytes4 routingSelector, bytes routingCalldata).
     */
    function executeWithVerification(
        uint256 clientId,
        bytes   calldata argsPlain
    ) external onlyOracle {
        bytes32 stored = argsHashByClientId[clientId];
        if (stored == bytes32(0)) {
            revert UnknownClientId(clientId);
        }

        bytes32 computed = keccak256(argsPlain);
        if (computed != stored) {
            revert HashMismatch();
        }

        // Decode routing envelope from argsPlain
        (address routingTarget, bytes4 routingSelector, bytes memory routingCalldata) =
            abi.decode(argsPlain, (address, bytes4, bytes));

        // Forward the call generically: selector + calldata (low level call)
        (bool ok, bytes memory ret) =
            routingTarget.call(abi.encodePacked(routingSelector, routingCalldata));

        if (!ok) {
            revert TargetCallFailed();
        }

        emit Routed(clientId, routingTarget, routingSelector, routingCalldata, ret);
    }
}
