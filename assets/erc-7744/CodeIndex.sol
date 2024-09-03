// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.20;
import "./ICodeIndex.sol";

/**
 * @title Byte Code Indexer Contract
 * @notice You can use this contract to index contracts by their bytecode.
 * @dev This allows to query contracts by their bytecode instead of addresses.
 * @author Tim Pechersky (@Peersky)
 */
contract CodeIndex is ICodeIndex {
    mapping(bytes32 => address) private index;

    /**
     * @notice Registers a contract in the index by its bytecode hash
     * @param container The contract to register
     * @dev `msg.codeHash` will be used
     * @dev It will revert if the contract is already indexed
     */
    function register(address container) external {
        address etalon = index[container.codehash];
        if (etalon != address(0)) {
            revert alreadyExists(container.codehash, etalon);
        }
        index[container.codehash] = container;
        emit Indexed(container, container.codehash);
    }

    /**
     * @notice Returns the contract address by its bytecode hash
     * @dev returns zero if the contract is not indexed
     * @param id The bytecode hash
     * @return The contract address
     */
    function get(bytes32 id) external view returns (address) {
        return index[id];
    }
}