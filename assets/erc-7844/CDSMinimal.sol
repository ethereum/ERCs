// SPDX-License-Identifier: CC0-1.0

/**
 * @title Consolidated Dynamic Storage - Basic Example
 * @author Cameron Warnick github.com/wisecameron, x.com/wisecameroneth
 * @notice Barebones CDS implementation - does not include optimization or safety checks.
 */
pragma solidity ^0.8.0;

contract CDSMinimal
{
    constructor(){}

    uint256 storageSpaces;
    uint256 constant MEMBERS_LIM = 1000;
    uint256 constant ENTRIES_LIM = 5000000000;

    /**
     * @notice Minimal, unoptimized example of init_create to demonstrate core logic.
     * Safety checks (e.g., input validation, bounds checking) are omitted for simplicity.
     * Production implementations must add these checks to ensure robustness.
     * This implementation follows the spec precisely.
    */
    function init_create(
        uint256[] memory types, 
        uint256[] memory sizes
    ) external
    {
        uint256 bitCount;
        uint256 safeIndex;
        uint256 stringIndex;
        uint256 len = sizes.length;

        storageSpaces += 1;
        uint256 ROOT_SLOT = _get_root_slot(storageSpaces - 1);

        for(uint256 i = 0; i < len; i++)
        {
            //validate size given type (omitted)
            uint256 valType = types[i];
            uint256 valSize = sizes[i];

            if(valType < 6)
            {
                //calculate bitCount for the new entry
                uint256 bitCountAsPage = (bitCount / 256);
                uint256 bitCountAsPageInBits = (bitCountAsPage * 256);
                uint256 bitCountOverflow = (bitCount + valSize) - bitCountAsPageInBits;

                if(bitCountOverflow > 256) bitCount = (bitCountAsPage + 1) * 256;

                uint256 packedValue;
                assembly
                {
                    //pack {bitCount, sizes, types}
                    packedValue := or(
                        or(
                            shl(128, bitCount),
                            shl(64, valSize)
                        ),
                        valType
                    )

                    sstore(add(ROOT_SLOT, add(1, i)), packedValue)

                    //bitCount := bitCount + size
                    bitCount := add(bitCount, valSize)

                    //set safeIndex to this
                    safeIndex := i
                }
            }
            else
            {
                uint256 packedValue;

                assembly
                {
                    //create packedValue {stringIndex, 6}
                    packedValue := or(
                        shl(128, stringIndex),
                        6
                    )

                    //store the packed value in the member data of the storage space
                    sstore(add(ROOT_SLOT, add(1, i)), packedValue)
                    
                    //increment stringIndex
                    stringIndex := add(stringIndex, 1)
                }

            }
        }

        //pack storage space data: {members, entries, stringIndex, safeIndex}
        uint256 storageSpaceMemberState;

        assembly
        {
            storageSpaceMemberState := or(
                or(
                    shl(192, len),
                    shl(64, stringIndex)
                ),
                safeIndex
            )

            sstore(ROOT_SLOT, storageSpaceMemberState)
        }
    }

    /**
     * @notice Minimal, unoptimized example of insert_new_member to demonstrate core logic.
     * Safety checks (e.g., input validation, bounds checking) are omitted for simplicity.
     * Production implementations must add these checks to ensure robustness.  
     * This implementation follows the spec precisely.
    */
    function insert_new_member(
        uint256 valType,
        uint256 valSize,
        uint256 storageSpace
    ) external
    {
        //verify type and size (omitted)

        //retrieve memberData
        uint256 packedStorageSpaceStateData;
        uint256 membersCount;

        uint256 ROOT_SLOT = _get_root_slot(storageSpace);

        assembly
        {
            packedStorageSpaceStateData := sload(ROOT_SLOT)
            membersCount := shr(192, packedStorageSpaceStateData)
        }

        if(valType < 6)
        {
            uint256 bitCount;
            uint256 prevSize;
            uint256 safeIndex;

            assembly
            {
                //get safeIndex
                safeIndex := shr(192, shl(192, packedStorageSpaceStateData))

                //get bitCount, verify size (omitted)
                let previousStoredValueMemberData := sload(add(ROOT_SLOT, add(1, safeIndex)))

                bitCount := shr(128, previousStoredValueMemberData)
                prevSize := shr(64, and(
                    previousStoredValueMemberData, 
                    0x00000000000000000000000000000000FFFFFFFFFFFFFFFF0000000000000000
                    )
                )
            }

            //get storage page, verify we will not overflow
            bitCount += prevSize;
            uint256 bitCountAsPage = (bitCount / 256);
            uint256 bitCountAsPageInBits = (bitCountAsPage * 256);
            uint256 bitCountOverflow = (bitCount + valSize) - bitCountAsPageInBits;

            //if overflow, push to next page (update bitCount to head of next page)
            if(bitCountOverflow > 256) bitCount = (bitCountAsPage + 1) * 256;

            assembly
            {
                //pack memberData
                let packedMemberData := or(
                    or(
                        shl(128, bitCount),
                        shl(64, valSize)
                    ),
                    valType
                )

                //store packedMemberData
                sstore(add(ROOT_SLOT, add(1, membersCount)), packedMemberData)

                //update safeIndex, members in state data for storage space
                safeIndex := membersCount

                packedStorageSpaceStateData := or(
                    and(
                        packedStorageSpaceStateData, 0x0000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000000000000000
                    ), 
                    or(safeIndex, shl(192, add(membersCount, 1)))
                )

                sstore(ROOT_SLOT, packedStorageSpaceStateData)
            }
        }
        else
        {
            uint256 stringIndex;

            assembly
            {
                //get stringIndex
                stringIndex := shr(64, 
                    and(
                        packedStorageSpaceStateData, 
                        0x00000000000000000000000000000000FFFFFFFFFFFFFFFF0000000000000000
                    )
                )

                //pack with type
                let packedMemberData := or(
                    shl(128, stringIndex),
                    valType
                )

                //store entry in memberData
                mstore(0x0, shl(
                    176, 
                    add(
                        mul(storageSpace, MEMBERS_LIM),
                        add(1, membersCount))
                    )
                )
                sstore(add(ROOT_SLOT, add(1, membersCount)), packedMemberData)

                //increment stringIndex, members
                membersCount := add(membersCount, 1)
                stringIndex := add(stringIndex, 1)

                //store updated state data for storage space
                packedStorageSpaceStateData := and(
                    packedStorageSpaceStateData, 0x0000000000000000FFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF
                )

                packedStorageSpaceStateData := or(
                    or(packedStorageSpaceStateData, shl(192, membersCount)),
                    shl(64, stringIndex)
                )

                sstore(ROOT_SLOT, packedStorageSpaceStateData)
            }
        }
    }

    function get_storage_space_state_data(
        uint256 storageSpace
    ) external view returns(
        uint256 members,
        uint256 entries,
        uint256 stringIndex,
        uint256 safeIndex
    )
    {
        uint256 ROOT_SLOT = _get_root_slot(storageSpace);

        assembly
        {
            let packedStorageSpaceStateData := sload(ROOT_SLOT)

            members := shr(192, packedStorageSpaceStateData)
            entries := shr(128, and(
                packedStorageSpaceStateData, 
                0x0000000000000000FFFFFFFFFFFFFFFF00000000000000000000000000000000
            ))
            stringIndex := shr(64, and(
                packedStorageSpaceStateData,
                0x00000000000000000000000000000000FFFFFFFFFFFFFFFF0000000000000000
            ))
            safeIndex := and(
                packedStorageSpaceStateData,
                0x000000000000000000000000000000000000000000000000FFFFFFFFFFFFFFFF
            )
        }
    }

    function get_member_data(
        uint256 memberIndex,
        uint256 storageSpace
    ) external view returns(
        uint256 bitCount, uint256 valSize, uint256 valType)
    {
        uint256 ROOT_SLOT = _get_root_slot(storageSpace);

        assembly
        {
            let packedStorageSpaceStateData := sload(add(ROOT_SLOT, add(1, memberIndex)))

            bitCount := shr(128, packedStorageSpaceStateData)
            valSize := shr(64, 
                and(packedStorageSpaceStateData, 0x00000000000000000000000000000000FFFFFFFFFFFFFFFF0000000000000000)
            )
            valType := and(
                packedStorageSpaceStateData,
                0x000000000000000000000000000000000000000000000000FFFFFFFFFFFFFFFF
            )
        }
    }

    function _get_root_slot(uint256 storageSpace)
    internal view returns(uint256 slot)
    {
        if(storageSpace >= storageSpaces)
        {
            revert("Invalid storage space!");
        }

        assembly
        {
            let offset := shl(176, mul(storageSpace, MEMBERS_LIM))
            mstore(0x0, offset)
            slot := keccak256(0x0, 0xA)
        }
    }
}