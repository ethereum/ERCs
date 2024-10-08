// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ChainidTools} from "./ChainidTools.sol";

/// @dev OmnichainAddress is a structure that represents address on specific chain
type OmnichainAddress is bytes32;

/**
 * OmnichainAddress structure:
 * 0xPPPPVVRRRRRRRRRRHHHHHHHHAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
 * - Prefix (bytes4):
 * -- PPPP - Type prefix (0x4F41) - ASCII representation of letters "OA"
 * -- VV   - Version of OmnichainAddress specification, currently 0x00
 * -- RR   - Reserved byte
 * - Reserved bytes (bytes4)
 * -- RRRRRRRR - Reserved bytes (should be 0x00000000 in current specification)
 * - Chain ID (bytes4)
 * -- HHHHHHHH - 32 bit of chain identifier
 * - User Address (bytes20)
 * -- AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA - Address of the user
 *
 * Note: cheap conversion to `address` is possible:
 * `address account = address(uint160(uint256(OmnichainAddress.unwrap(omnichainAddress))))`
 * but it ignores chainid and prefix, so must be used with care
 *
 * !!! COMPATIBILITY REQUIREMENTS !!!
 * - PREFIX 0x4F410000 SHOULD be used only by implementations with same OmnichainAddress structure
 * - Requirements for other implementations:
 * -- User Identifier MUST be persistent between compatible DataIndex implementations (so that user can use same ID in all compatible implementations)
 * -- Any of compatible DataIndex implementation SHOULD be able to find owner of ID issued by any other compatible implementation
 */

/**
 * @title OmnichainAddresses library
 * @notice Library with utility functions to encode and decode OmnichainAddress
 */
library OmnichainAddresses {
    /// @dev represent PPPPVVRR prefix
    bytes4 internal constant PREFIX = 0x4F410000;

    /// @dev Error thrown when OmnichainAddress structure is not supported
    error UnsupportedOmnichainAddressesStructure();

    /**
     * @notice Encode OmnichainAddress
     * @param account Address of the user
     * @return Encoded OmnichainAddress
     */
    function encode(address account) internal view returns (OmnichainAddress) {
        return encode(ChainidTools.chainid(), account);
    }

    /**
     * @notice Encode OmnichainAddress
     * @param chainid Chain ID to encode
     * @param account Address of the user
     * @return Encoded OmnichainAddress
     */
    function encode(uint32 chainid, address account) internal pure returns (OmnichainAddress) {
        return OmnichainAddress.wrap(bytes32((uint256(uint32(PREFIX)) << 224) | (uint256(chainid) << 160) | uint256(uint160(account))));
    }

    /**
     * @notice Decode OmnichainAddress
     * @param oa OmnichainAddress to decode
     * @return chainid Chain ID of the OmnichainAddress
     * @return account Address of the user
     */
    function decode(OmnichainAddress oa) internal pure returns (uint32 chainid, address account) {
        uint256 oau = uint256(OmnichainAddress.unwrap(oa));
        bytes4 prefix = bytes4(uint32(oau >> 224));
        if (prefix != PREFIX) revert UnsupportedOmnichainAddressesStructure();
        account = address(uint160(oau));
        chainid = uint32(oau >> 160);
    }
}
