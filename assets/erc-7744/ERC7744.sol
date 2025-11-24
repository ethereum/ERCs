// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;
import {IERC7744} from "./IERC7744.sol";

/**
 * @title Byte Code Indexer Contract
 * @notice You can use this contract to index contracts by their bytecode.
 * @dev This is global immutable library for functional code.
 * @author Tim Pechersky (@Peersky)
 */
contract ERC7744 is IERC7744 {
    mapping(bytes32 => address) private index;

    function isEIP7702(address account) public view returns (bool) {
        bytes3 prefix;
        assembly {
            extcodecopy(account, 0, mload(0x40), 3) // Copy first 3 bytes to memory
            prefix := mload(0x40) // Load the 3 bytes from memory
        }
        return prefix == bytes3(0xef0100);
    }

    function isValidContainer(address container) private view returns (bool) {
        bytes memory code = container.code;
        bytes32 codeHash = address(container).codehash;
        return (code.length > 0 &&
            codeHash != bytes32(0) &&
            !isEIP7702(container));
    }

    /**
     * @notice Registers a contract in the index by its bytecode hash
     * @param container The contract to register
     * @dev `msg.codeHash` will be used
     * @dev It will revert if the contract is already indexed or if returns EIP7702 delegated EOA
     */
    function register(address container) external {
        address etalon = index[container.codehash];
        require(isValidContainer(container), "Invalid container");
        if (etalon != address(0)) {
            if (isValidContainer(etalon))
                revert alreadyExists(container.codehash, container);
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
