// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title Test Target for Call Decryption Oracle / Router
 * @notice Simple contract that can be used as a callback/target in tests.
 *         It implements the expected callback signature
 *             executeWithVerification(uint256 clientId, bytes argsPlain)
 *         and simply stores all received calls so that tests can inspect them.
 */
contract CallDecryptionOracleTestTarget {

    struct ExecutionRecord {
        address caller;
        uint256 clientId;
        bytes   argsPlain;
    }

    /**
     * @notice All executions grouped by clientId.
     */
    mapping(uint256 => ExecutionRecord[]) private _executionsByClientId;

    event Executed(
        uint256 indexed clientId,
        address indexed caller,
        bytes   argsPlain
    );

    /**
     * @notice Callback to be used by the CallDecryptionOracleRouter (or directly by the Call Decryption Oracle).
     * 
     * @param clientId Business correlation id.
     * @param argsPlain Decrypted argument payload bytes as delivered by the oracle/router.
     */
    function executeWithVerification(
        uint256 clientId,
        bytes   calldata argsPlain
    ) external {
        ExecutionRecord memory rec = ExecutionRecord({
        caller: msg.sender,
        clientId: clientId,
        argsPlain: argsPlain
        });
        _executionsByClientId[clientId].push(rec);

        emit Executed(clientId, msg.sender, argsPlain);
    }

    /**
     * @notice Get the number of executions recorded for a given clientId.
     */
    function getExecutionCount(uint256 clientId) external view returns (uint256) {
        return _executionsByClientId[clientId].length;
    }

    /**
     * @notice Get a specific execution record for a given clientId and index.
     * @param clientId Business correlation id.
     * @param index    Zero-based index into the list of executions for this clientId.
     * @return caller   The address that called executeWithVerification.
     * @return argsPlain The argument payload bytes that were passed.
     */
    function getExecution(
        uint256 clientId,
        uint256 index
    ) external view returns (address caller, bytes memory argsPlain) {
        ExecutionRecord storage rec = _executionsByClientId[clientId][index];
        return (rec.caller, rec.argsPlain);
    }
}
