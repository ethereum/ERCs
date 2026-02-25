// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ChainidTools} from "./ChainidTools.sol";

/// @dev DataPoint is a 32 bytes structure which contains information about data point
type DataPoint is bytes32;

/**
 * DataPoint structure:
 * 0xPPPPVVRRIIIIIIIIHHHHHHHHAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
 * - Prefix (bytes4)
 * -- PPPP - Type prefix (0x4450) - ASCII representation of letters "DP"
 * -- VV   - Version of DataPoint specification, currently 0x00
 * -- RR   - Reserved byte (should be 0x00 in current specification)
 * - Registry-local identifier
 * -- IIIIIIII - 32 bit implementation-specific id of the DataPoint
 * - Chain ID (bytes4)
 * -- HHHHHHHH - 32 bit of chain identifier
 * - Registry Address (bytes20)
 * -- AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA - Address of Registry which allocated the DataPoint
 *
 * !!! COMPATIBILITY REQUIREMENTS !!!
 * - Registry address MUST be located in last 20 bytes of the DataPoint in ALL DataPoint implementations
 * - PREFIX 0x44500000 SHOULD be used only by implementations with same DataPoint structure
 */

/**
 * @title DataPoints library
 * @notice Library with utility functions to encode and decode DataPoint
 */
library DataPoints {
    /// @dev Represents PPPPVVRR prefix
    bytes4 internal constant PREFIX = 0x44500000;

    /// @dev Offset of the DataPoint prefix
    uint256 internal constant PREFIX_BIT_OFFSET = 224;

    /// @dev Offset of the DataPoint id
    uint256 internal constant ID_BIT_OFFSET = 192;

    /// @dev Offset of the DataPoint chainid
    uint256 internal constant CHAINID_BIT_OFFSET = 160;

    /// @dev Error thrown when DataPoint structure is not supported
    error UnsupportedDataPointStructure();

    /**
     * @dev Encode DataPoint
     * @param registry Address of the registry which allocated the DataPoint
     * @param id 32 bit implementation-specific id of the DataPoint
     * @return Encoded DataPoint
     */
    function encode(address registry, uint32 id) internal view returns (DataPoint) {
        return
            DataPoint.wrap(
                bytes32(
                    (uint256(uint32(PREFIX)) << PREFIX_BIT_OFFSET) |
                        (uint256(id) << ID_BIT_OFFSET) |
                        (uint256(ChainidTools.chainid()) << CHAINID_BIT_OFFSET) |
                        uint256(uint160(registry))
                )
            );
    }

    /**
     * @dev Decode DataPoint
     * @param dp DataPoint to decode
     * @return chainid Chain ID of the DataPoint
     * @return registry Address of the registry which allocated the DataPoint
     * @return id 32 bit implementation-specific id of the DataPoint
     */
    function decode(DataPoint dp) internal pure returns (uint32 chainid, address registry, uint32 id) {
        uint256 dpu = uint256(DataPoint.unwrap(dp));
        bytes4 prefix = bytes4(uint32(dpu >> PREFIX_BIT_OFFSET));
        if (prefix != PREFIX) revert UnsupportedDataPointStructure();
        registry = address(uint160(dpu));
        chainid = uint32(dpu >> CHAINID_BIT_OFFSET);
        id = uint32(dpu >> ID_BIT_OFFSET);
    }
}