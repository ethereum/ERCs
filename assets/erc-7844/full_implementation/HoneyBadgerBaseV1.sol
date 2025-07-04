//SPDX-License-Identifier: UNLICENSED

import "./IHoneyBadgerBaseV1.sol";

pragma solidity ^0.8.0;

    /// @notice   ERC-7844++.  An extended, highly-optimized ERC-7844 implementation.
    /// @author   Cameron Warnick @wisecameron https://www.linkedin.com/in/cameron-warnick-64a25222a/
    
    /// @dev Note:
    /// - HoneyBadger is a full-service storage and permission management solution extending ERC-7844.  It consolidates storage
    /// into a single contract layer that leverages hash-deliniated namespacing to securely manage data in 
    /// distinct storage spaces.  Dependent contracts leverage RBAC to define their access picture.
    /// - Mapped data structures are defined with the custom "extendible struct" type: each storage space maps 
    /// entries to a single extendible struct interface.  The "insert_new_member" function appends a new member to 
    /// an extendible struct in-place.
    /// - Storage spaces can be created with the "init_create" function.
    /// - Address indexing is enabled via the "address_indexed" and "add_address_index" functions.
    /// - Arbitrary-formed nested indexing can be enabled with specialAccess = true during init_create().
    /// Custom access patterns are passed with a packed-encoded "specialAccess" dynamic bytes array in 
    /// functions such as "put" and "get."
    /// - Overall, HoneyBadger effectively consolidates the benefits of numerous individual proposals (ie; storage namespacing,
    /// preventing collisions, enabling upgradeability, standardizing access patterns) into a plug-and-play 
    /// context, while introducing novel advantages via in-place storage upgradeability.
    /// For more information, visit: https://honeybadgerframework.com/docs
    /// ERC-7844 proposal: https://ethereum-magicians.org/t/erc-7844-consolidated-dynamic-storage-cds/22217

    /// Supported types: 
    /// 1: uint
    /// 2: int
    /// 3: bool
    /// 4: address
    /// 5: bytes32
    /// 6: string 

contract HoneyBadgerBaseV1 is IHoneyBadgerBaseV1 
{
    /// @dev total storage spaces
    uint256 public storageSpaces;

    /// @dev Up to 1,000 members per storage space.
    uint256 constant MEMBERS_LIM = 1000;

    /// @dev Up to 5,000,000,000 entries per storage space.
    uint256 constant ENTRIES_LIM = 5_000_000_000;

    
    /// @dev open record of current permission holders.
    address[] public permissionHolders;

    /// @dev internal permission bitmaps for each permission holder.  [32...256: 0/1 flags for PermissionLevel enum][bit 1: isContract flag]
    mapping(address => uint256) permissions;//optimization: refactor to single-hash slot derivation (LOW impact)

    /// @dev address indices mapped to entry indices for address-indexing.
    mapping(uint256 => mapping(address => uint256)) addressIndices;


    /*------------------------------------------------------------------------------------------------
                                        Events
    ------------------------------------------------------------------------------------------------*/
    event DataModified(uint256 storageSpace);
    event PermissionsChanged(address recipient);
    event Initialized();
    event StorageSpaceCreated(uint256 newStorageSpace);
    event StorageSpaceExtended(uint256 storageSpace);
    event Push(uint256 pushAmount, uint256 storageSpace);

    constructor(address _owner) 
    {
        uint8[] memory ownerPerms = new uint8[](3);

        ownerPerms[0] = uint8(PermissionFlags.Modify);
        ownerPerms[1] = uint8(PermissionFlags.PermissionManagement);
        ownerPerms[2] = uint8(PermissionFlags.StorageSpace);
        
        uint256 permData = _update_permission_data(ownerPerms, msg.sender, false);
        permissions[msg.sender] = permData;
        permissionHolders.push(_owner);

        emit Initialized();
    }

    /*------------------------------------------------------------------------------------------------
                                        Permission Management
    ------------------------------------------------------------------------------------------------*/

    /**
     * @notice Removes all permissions from an address.
     * @dev Zeroes the user's entry in the permissionHolders array and permissions mapping.
     * @return Describes whether a user was removed from the permission list.
     */
    function strip_permissions(address user) external returns (bool) 
    {
        _access_control(user, PermissionFlags.PermissionManagement, false);

        uint256 i = 0;
        uint256 l = permissionHolders.length;
        bool removed = false;

        for (i; i < l; i++) 
        {
            if (permissionHolders[i] == user) 
            {
                permissionHolders[i] = address(0);
                permissions[user] = 0;
                removed = true;
            }
        }

        emit PermissionsChanged(user);
        return removed;
    }

    /** 

        @notice Updates recipient's permissions.  If no permissions exist, it will 
        populate a new entry in the permissionHolders array.
        @dev Tries to fill an empty existing slot in permissionHolders before pushing.
    */
    function update_permissions(address recipient, uint8[] memory flags, bool remove) external 
    {
        _access_control(msg.sender, PermissionFlags.PermissionManagement, false);

        uint256 i;
        uint256 l = permissionHolders.length;
        bool replace = false;
        bool already_included = (permissions[recipient] != 0);

        if (already_included == false) 
        {
            for (i; i < l; i++) 
            {
                if (permissionHolders[i] == address(0)) {
                    permissionHolders[i] = recipient;
                    replace = true;
                }
            }
            if (!replace) {
                permissionHolders.push(recipient);
            }
        }

        uint256 updatedPerms = _update_permission_data(flags, recipient, remove);

        //update permission level
        permissions[recipient] = updatedPerms;

        emit PermissionsChanged(recipient);
    }

    /**
        @notice Returns the raw permission bitmap for a user.
        @dev Slot layout: 0x [256 ... 32 : flags (shl(32, 1) + PermissionFlags.Flag)][32...0 : flags : ContractOnly(bit 1)]
    */
    function view_permissions(address user) external view returns (uint256) 
    {
        return (permissions[user]);
    }

    /*------------------------------------------------------------------------------------------------
                                        Owner-Level
    ------------------------------------------------------------------------------------------------*/

    /** 
        @notice Creates a storage space. Storage spaces are defined by an array of 
        types and sizes.  Types range from 1...6 [uint, int, bool, address, 
        bytes32, string.

        @dev refer to ERC-7844 specification:
        https://github.com/wisecameron/ERCs/blob/wisecameron/erc-cds/ERCS/erc-7844.md
    */
    function init_create(
    uint256[] memory types,
    uint256[] memory sizes,
    bool specialAccess) 
    external returns(uint256)
    {
        _access_control(msg.sender, PermissionFlags.StorageSpace, false);

        storageSpaces += 1;
        uint256 ROOT_SLOT = _get_root_slot(storageSpaces - 1);

        /*      --- Validate Input ---     */
        if (types.length != sizes.length) 
        {
            revert("Input size mismatch!");
        }

        if (types.length == 0 || types.length > 999) 
        {
            revert("Invalid input length!");
        }

        uint256 i;
        uint256 size;
        uint256 valType;
        uint256 bitCount;
        uint256 packValue;
        uint256 safeIndex;
        uint256 stringIndex = 1;
        uint256 len = sizes.length;
        
        for(i; i < len; i++)
        {
            valType = types[i];
            size = sizes[i];

            if(valType == 0 || valType > 6) revert("Invalid type!");
            _validate_new_member_size(valType, size);

            if(valType != 6)
            {
                assembly
                {
                    /*
                        OVERFLOW PROTECTION
                        if (bitCount - (256 * (bitCount / 256))) + size > 256, 
                        add bitCount up to nearest 256

                        Why?  That means a packed storage slot would exceed 256 bits.
                    */

                    //gives number of bits already taken in slot
                    let bitsAlreadyTakenInSlot := sub(bitCount, mul(256, div(bitCount, 256)))

                    //check whether this value fits into the slot
                    if gt(add(bitsAlreadyTakenInSlot, size), 256) 
                    {
                        //if it does not fit, it will start the next slot
                        bitCount := add(bitCount, sub(256, bitsAlreadyTakenInSlot))
                    }

                    /*
                        packValue[0...63] = types[i] 
                        packValue[64...128] = sizes[i]
                        packValue[128...256] = bitCount
                    */
                    packValue := or(
                        or(valType, shl(64, size)),
                        shl(
                            128,
                            and(bitCount, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
                        )
                    )

                    //Store new member data
                    sstore(
                        add(ROOT_SLOT, add(1, i)),
                        packValue
                    )

                    //the next value is going to start at bitCount[i-1] + size[i-1]
                    bitCount := add(bitCount, size)
                    safeIndex := i
                }
            }
            else 
            {
                assembly
                {
                    //create member data
                    //does not include size because size is entry-specific for string
                    packValue := or(6, shl(128, stringIndex))

                    sstore(
                        add(ROOT_SLOT, add(1, i)),
                        packValue
                    )

                    packValue := 0
                    stringIndex := add(stringIndex, 1)
                }
            }
        }

        assembly 
        {   
            //store 0x[members(64)][entries(64)][stringIndex(64)][safeIndex (32)][specialAccess(32)]
            let storageSpaceMetadata := or(
                shl(32, safeIndex),
                or(
                    or(shl(64, stringIndex), shl(192, len)),
                    or(shl(128, 1), specialAccess)
                )
            )

            sstore(ROOT_SLOT, storageSpaceMetadata)
        }

        if(specialAccess)
        {
            push(ENTRIES_LIM - 1, storageSpaces - 1);
            emit Push(ENTRIES_LIM - 1, storageSpaces - 1);
        }

        emit StorageSpaceCreated(storageSpaces - 1);
        return storageSpaces - 1;
    }

    /** 
        @notice Extends a storage space, adding a new member that is automatically integrated 
        with the existing mapping for all entries.

        @dev refer to ERC-7844 specification:
        https://github.com/wisecameron/ERCs/blob/wisecameron/erc-cds/ERCS/erc-7844.md
    */
    function insert_new_member(
        uint256 valType,
        uint256 size,
        uint256 storageSpace
    ) external 
    {
        _access_control(msg.sender, PermissionFlags.StorageSpace, false);
        require(valType > 0 && valType < 7, "Invalid type!");
        _validate_new_member_size(valType, size);

        uint256 ROOT_SLOT = _get_root_slot(storageSpace);
        uint256 members;
        uint256 bitCount;
        uint256 stringIndex;
        uint256 safeIndex;
        uint256 fullSlot;
        uint256 packValue;

        assembly 
        {
            //retrieve safeindex 0x[members][entries][stringIndex][safeIndex(32)][specialAccess(32)]
            fullSlot := sload(ROOT_SLOT)
            safeIndex := and(shr(32, fullSlot), 0xFFFFFFFF)
            stringIndex := and(shr(64, fullSlot), 0xFFFFFFFFFFFFFFFF)
            members := shr(192, fullSlot)
        }

        if(valType < 6)
        {
            uint256 safeMemberMetadataSlot;
            uint256 lastSafeMemberSize;
            uint256 lastSafeMemberType;

            assembly
            {
                safeMemberMetadataSlot := sload(add(ROOT_SLOT, add(1, safeIndex)))
                lastSafeMemberSize := and(shr(64, safeMemberMetadataSlot), 0xFFFFFFFFFFFFFFFF)
                lastSafeMemberType := and(safeMemberMetadataSlot, 0xFFFFFFFFFFFFFFFF)

                //Our new bitCount is prev bitCount + prev size -- unless we only have strings.
                if iszero(eq(lastSafeMemberType, 6))
                {
                    bitCount := add(shr(128, safeMemberMetadataSlot), lastSafeMemberSize)
                }
                safeIndex := members

                //set up proper bit count for the new entry
                //by ensuring that it fits within its slot
                let localBitCount := sub(bitCount, mul(256, div(bitCount, 256)))

                //if we will exceed the size of the slot,
                //add bitCount to the nearest 256
                if gt(add(localBitCount, size), 256) 
                {
                    bitCount := add(bitCount, sub(256, localBitCount))
                }

                //now we know our data is valid, so  we can store it
                packValue := and(valType, 0xFFFFFFFFFFFFFFFF)
                packValue := or(
                    packValue,
                    shl(64, and(size, 0xFFFFFFFFFFFFFFFF))
                )
                packValue := or(
                    packValue,
                    shl(128, and(bitCount, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))
                )
            }
        }
        else 
        {
            assembly
            {
                //handle string
                if eq(valType, 6) 
                {
                    packValue := or(valType, shl(128, stringIndex))
                    stringIndex := add(stringIndex, 1)
                }
            }
        }
        assembly
        {
            //store new member
            sstore(add(ROOT_SLOT, add(members, 1)), packValue)

            //store new 0x[members][entries][stringIndex][safeIndex]
            fullSlot := 
            or(
                or(
                    or(
                        and(fullSlot, 0x0000000000000000FFFFFFFFFFFFFFFF000000000000000000000000000000FF),
                        shl(192, add(members, 1))
                    ),
                    shl(64, stringIndex)
                ),
                shl(32, safeIndex)
            )

            sstore(ROOT_SLOT, fullSlot)
        }

        emit StorageSpaceExtended(storageSpace);
    }

    /**
     * @notice Maps an entry index to an address.
     */
    function add_address_index(
        address addressIndex, 
        uint256 storageSpace,
        uint256 entryIndex)
    external
    {
        _access_control(msg.sender, PermissionFlags.Modify, false);
        
        addressIndices[storageSpace][addressIndex] = entryIndex;
    }

    /*------------------------------------------------------------------------------------------------
                                            Push
    ------------------------------------------------------------------------------------------------*/

    /**
        @notice Adds "amount" entries to a storage space.

        @dev refer to ERC-7844 specification:
        https://github.com/wisecameron/ERCs/blob/wisecameron/erc-cds/ERCS/erc-7844.md
    */
    function push(uint256 amount, uint256 storageSpace) public 
    returns(uint256)
    {
        _access_control(msg.sender, PermissionFlags.StorageSpace, false);
        require(storageSpace < storageSpaces, "invalid storage space");
        uint256 ROOT_SLOT = _get_root_slot(storageSpace);

        uint256 earliestNewEntry;
        uint256 adjustedEntries;

        assembly 
        {
            //update the bits on the second level
            let fullSlot := sload(ROOT_SLOT)

            earliestNewEntry := and(shr(128, fullSlot), 0xFFFFFFFFFFFFFFFF)

            adjustedEntries := add(earliestNewEntry, amount)

            if gt(adjustedEntries, ENTRIES_LIM)
            {
                //Exceeds max entries!
                mstore(0x0, 0x45786365656473206d617820656e747269657321)
                revert(0x0, 0x20)
            }

            sstore(
                ROOT_SLOT,
                or(
                    and(fullSlot, 0xFFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF),
                    shl(128, adjustedEntries)
                )
            )
        }

        emit Push(amount, storageSpace);
        
        return earliestNewEntry;
    }

    /*------------------------------------------------------------------------------------------------
                                            Put
    ------------------------------------------------------------------------------------------------*/

    /**
        @notice Modify a valid slot - types 1..5

        @dev refer to ERC-7844 specification:
        https://github.com/wisecameron/ERCs/blob/wisecameron/erc-cds/ERCS/erc-7844.md
    */
    function put(
        uint256 data,
        uint256 memberIndex,
        uint256 entryIndex,
        uint256 storageSpace,
        bytes calldata specialAccess
    ) public
    {
        uint256 ROOT_SLOT = _get_root_slot(storageSpace);

        require(entryIndex > 0 && storageSpace < storageSpaces, 
        "Failed to validate entry index or storage space");

        _access_control(msg.sender, PermissionFlags.Modify, false);
        _validate_memberIndex_and_entryIndex(ROOT_SLOT, memberIndex, entryIndex);
        uint256 slot = _derive_user_slot(entryIndex, storageSpace, 0, false, ROOT_SLOT, specialAccess);

        //verify type and size
        uint256 packValue;
        uint256 size;
        uint256 bitCount;

        assembly 
        {
            packValue := sload(add(ROOT_SLOT, add(1, memberIndex)))
            size := and(shr(64, packValue), 0xFFFFFFFFFFFFFFFF)
            bitCount := shr(128, packValue)
        }

        _validate_data(
            packValue & 0xFFFFFFFFFFFFFFFF, /* valType */
            size, 
            data
        );

        //prep data to match any type
        assembly {
            let page := div(bitCount, 256)

            //add up to the data page -- hash(index + storageSpace * ENTRIES_LIM) + page
            packValue := sload(add(slot, page))

            /* zero out the area that will be replaced */

            //start index is bitCount - (256 * (bitCount / 256))
            //let a := div(bitCount, 256) -> 1042 -> 4.0703125 -> 4
            //a := mul(a, 256) -> 4 * 256 = 1024
            //a := sub(bitCount, a) -> 1042 - 1024 = 18
            //so, our slot is filled until bit 18
            let precedingBits := mod(bitCount, 256)

            //Clear the old value and insert our new data
            packValue := or(
                and(
                    packValue, 
                    not(shl(precedingBits, sub(shl(size, 1), 1)))
                ), 
                shl(precedingBits, data)
            )

            sstore(add(slot, page), packValue)
        }

        emit DataModified(storageSpace);
    }

    /**
        @notice |256-BIT| Modify a valid slot
        
        @dev refer to ERC-7844 specification:
        https://github.com/wisecameron/ERCs/blob/wisecameron/erc-cds/ERCS/erc-7844.md
    */
    function put256(
        uint256 data,
        uint256 memberIndex,
        uint256 entryIndex,
        uint256 storageSpace,
        bytes calldata specialAccess
    ) external
    {
        uint256 ROOT_SLOT = _get_root_slot(storageSpace);

        require((storageSpace < storageSpaces) && (entryIndex > 0), 
        "Failed to validate entry index or storage space");

        _access_control(msg.sender, PermissionFlags.Modify, false);       
        _validate_memberIndex_and_entryIndex(ROOT_SLOT, memberIndex, entryIndex);

        uint256 slot = _derive_user_slot(entryIndex, storageSpace, 0, false, ROOT_SLOT, specialAccess);
        uint256 packValue;

        assembly 
        {
            packValue := sload(add(ROOT_SLOT, add(1, memberIndex)))
        }

        uint256 valType = packValue & 0xFFFFFFFFFFFFFFFF;
        uint256 size = (packValue >> 64) & 0xFFFFFFFFFFFFFFFF;
        uint256 bitCount = (packValue >> 128);

        //check bitCount, type
        if (bitCount - (256 * (bitCount / 256)) > 0 || size != 256) revert("Not 256 bits!");
        if (valType != 1 && valType != 2 && valType != 5) revert("Invalid type!");

        assembly {
            sstore(add(slot, div(bitCount, 256)), data)
        }

        emit DataModified(storageSpace);
    }

    /**
     * @notice Modify a string entry: strings can also be used as arrays.
     * 
     * @dev refer to ERC-7844 specification:
        https://github.com/wisecameron/ERCs/blob/wisecameron/erc-cds/ERCS/erc-7844.md
     */
    function put_string(
        string memory data,
        uint256 memberIndex,
        uint256 entryIndex,
        uint256 storageSpace,
        bytes calldata specialAccess
    ) public
    {
        uint256 ROOT_SLOT = _get_root_slot(storageSpace);

        require((storageSpace < storageSpaces) && (entryIndex > 0), 
        "Failed to validate entry index or storage space");

        _access_control(msg.sender, PermissionFlags.Modify, false);
        _validate_memberIndex_and_entryIndex(ROOT_SLOT, memberIndex, entryIndex);

        uint256 inputStringSize;
        uint256 entryStringIndex;
        uint256 packedMetadataForMember;
        uint256 fullSlot; 

        //verify input data
        assembly 
        {
            //0x[bitCount(128)][type(128)]
            fullSlot := sload(ROOT_SLOT)
            packedMetadataForMember := sload(add(ROOT_SLOT, add(memberIndex, 1)))

            //verify type is string
            if iszero(eq(and(packedMetadataForMember, 0xFFFFFFFFFFFFFFFF), 6)) 
            {
                mstore(0x0, 0x496e707574206e6f74206120737472696e6721)
                revert(0x0, 0x20)
            }

            inputStringSize := mload(data)
            entryStringIndex := shr(128, packedMetadataForMember)
        }

        uint256 slot = _derive_user_slot(entryIndex, storageSpace, entryStringIndex, true, ROOT_SLOT,  specialAccess);

        assembly 
        {
            //store string size
            sstore(slot, inputStringSize)

            //convert to bits
            inputStringSize := mul(8, inputStringSize)

            //handle a quick 1-slot entry
            if or(iszero(inputStringSize), lt(inputStringSize, 257)) {
                //can avoid loop and just store the value in the slot.  
                //We could free the other data in the slot, but it's a waste of effort since 
                //it can't cause any problems
                sstore(add(slot, 1), mload(add(data, 0x20)))
                return(0x0, 0x0)
            }

            //handle multi-slot entries
            let i := 0
            for {} gt(inputStringSize, 0) { i := add(i, 1) } 
            {
                //store input data in storage -> add 1 to slot due to size storage on slot + 0
                sstore(
                    add(slot, add(i, 1)),
                    mload(add(add(data, 0x20), mul(0x20, i)))
                )

                if gt(inputStringSize, 256) {
                    inputStringSize := sub(inputStringSize, 256)
                    mstore(0x0, 1)
                }

                if iszero(mload(0x0)) {
                    inputStringSize := 0
                }

                mstore(0x0, 0)
            }
        }

        emit DataModified(storageSpace);
    }

    /**
     * @notice Modify multiple entries in a single transaction.
     * @dev Excludes string.  Use nbatch for cross-storage-space and entry operations.
     */
    function put_batch(
        uint256[] memory values,
        uint256[] memory members,
        uint256 entryIndex,
        uint256 storageSpace,
        bytes calldata specialAccess
    ) public
    {
        uint256 ROOT_SLOT = _get_root_slot(storageSpace);

        require(
            (entryIndex > 0) && 
            (values.length == members.length) && 
            (values.length > 0) && 
            (storageSpace < storageSpaces),
            "Failed to validate entry index, input, or storage space"
        );

        _access_control(msg.sender, PermissionFlags.Modify, false);
        _validate_members_and_entryIndex(ROOT_SLOT, entryIndex, members);

        if(true)
        {
            uint256 slot = _derive_user_slot(entryIndex, storageSpace, 0, false, ROOT_SLOT,  specialAccess);
            assembly
            {
                mstore(0x0, slot)
            }
        }

        uint256 previousPage = 1e18;
        uint256 page;
        uint256 packValue; 
        uint256 bitCount;
        uint256 size;
        uint256 valType;

        assembly 
        {
            let i

            /*
                a: start index (in page)
                b: end index (in page)
                0x...b...a...
            */
            //identify page, create mask, pack value into slot
            //Only update packValue when on last iteration or previousPage != page
            for {} lt(i, mload(values)) {i := add(i, 1)} 
            {
                valType := sload(
                    add(ROOT_SLOT, add(1, mload(add(add(0x20, members), mul(0x20, i)))))
                )
                size := and(shr(64, valType), 0xFFFFFFFFFFFFFFFF)
                bitCount := and(
                    shr(128, valType),
                    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
                )
                valType := and(valType, 0xFFFFFFFFFFFFFFFF)

                if gt(valType, 5) 
                {
                    //String detected!
                    mstore(0x0, 0x537472696e6720646574656374656421)
                    revert(0x0, 0x20)
                }

                //get the current page based on bitCount
                page := div(bitCount, 256)

                /*
                    If i is not zero, we need to store
                    the previous page if it is different than 
                    the current page.

                    Then, we need to load the new packValue 
                    for future operations.

                    If i is zero, we need to get packValue.
                */
                if iszero(eq(i, 0)) 
                {
                    if iszero(eq(previousPage, page)) 
                    {
                        //store prev
                        sstore(add(mload(0x0), previousPage), packValue)

                        //update packValue
                        packValue := sload(add(mload(0x0), page))
                    }
                }
                if iszero(i) 
                {
                    //init packValue for i == 0
                    packValue := sload(add(mload(0x0), page))
                }

                /*
                    Now we need to update packValue by inserting the 
                    new entry into the slot.

                    First, construct a mask to zero out the data slice.
                */
                let precedingBits := sub(bitCount, mul(div(bitCount, 256), 256))

                //Create a mask to zero out our target 
                //let mask2 := not(shl(precedingBits, sub(shl(size, 1), 1)))
                packValue := and(packValue, not(shl(precedingBits, sub(shl(size, 1), 1))))

                //store data value and fix it if needed

                let entry := mload(add(add(0x20, values), mul(0x20, i)))

                if gt(entry, sub(shl(size, 1), 1)) 
                {
                    //Data too big!
                    mstore(0x0, 0x4461746120746f6f2062696721)
                    revert(0x0, 0x20)
                }

                if iszero(eq(mload(0x0), 1)) 
                {
                    entry := shl(precedingBits, entry)
                }

                packValue := or(packValue, entry)
                previousPage := page
            }

            //store final packValue, it was not stored in the for logic
            sstore(add(mload(0x0), page), packValue)
        }

        emit DataModified(storageSpace);
    }

    /*------------------------------------------------------------------------------------------------
                                            Get
    ------------------------------------------------------------------------------------------------*/

    /**
     * @notice Retrieve a value from a storage space-member-entry.
     * @dev Supports types 1..5
     */
    function get(
        uint256 memberIndex,
        uint256 entryIndex,
        uint256 storageSpace,
        bytes calldata specialAccess
    ) public view returns (uint256) 
    {
        require(entryIndex > 0, "invalid entry index");
        require(storageSpace < storageSpaces);

        uint256 ROOT_SLOT = _get_root_slot(storageSpace);
        _validate_memberIndex_and_entryIndex(ROOT_SLOT, memberIndex, entryIndex);
        uint256 slot = _derive_user_slot(entryIndex, storageSpace, 0, false, ROOT_SLOT,  specialAccess);

        assembly {
            //get a description of the value: type [64], size[64], bitCount[64]
            let packValue := sload(add(ROOT_SLOT, add(1, memberIndex)))
            let valType := and(0xFFFFFFFFFFFFFFFF, packValue)
            let size := and(0xFFFFFFFFFFFFFFFF, shr(64, packValue))
            let bitCount := shr(128, packValue)

            //if the type is string or zero, revert
            if or(gt(valType, 5), iszero(valType)) 
            {
                //Invalid type!
                mstore(0x0, 0x496e76616c6964207479706521)
                revert(0x0, 0x20)
            }

            /*
                Use bitwise operations to grab the value from the storage page and 
                shift it into place.
            */

            //get packed value
            packValue := sload(add(slot, div(bitCount, 256)))

            //isolate value
            let precedingBits := sub(bitCount, mul(div(bitCount, 256), 256))
            packValue := and(shr(precedingBits, packValue), sub(shl(size, 1), 1))

            mstore(0x0, packValue)
            return(0x0, 0x20)
        }
    }

    /**
     * @notice Retrieve a 256-bit value from a storage space-member-entry.
     * @dev Supports types 1..5
     */
    function get256(
        uint256 memberIndex,
        uint256 entryIndex,
        uint256 storageSpace,
        bytes calldata specialAccess
    ) external view returns (uint256) 
    {
        require(entryIndex > 0, "invalid entry index");
        require(storageSpace < storageSpaces, "Invalid storage space!");

        uint256 ROOT_SLOT = _get_root_slot(storageSpace);
        _validate_memberIndex_and_entryIndex(ROOT_SLOT, memberIndex, entryIndex);
        uint256 slot = _derive_user_slot(entryIndex, storageSpace, 0, false,  ROOT_SLOT, specialAccess);

        assembly 
        {
            mstore(0x0, 
            sload(
                    add(
                        slot, 
                        div(shr(128, sload(add(ROOT_SLOT, add(1, memberIndex)))), 256)
                    )
                )
            )

            return(0x0, 0x20)
        }
    }

    /**
     * @notice Retrieve a string from a storage space-member-entry.
     * @dev Supports type 6
     */
    function get_string(
        uint256 memberIndex,
        uint256 entryIndex,
        uint256 storageSpace,
        bytes calldata specialAccess
    ) external view returns (string memory returnValue)
    {
        require(entryIndex > 0, "invalid entry index");
        require(storageSpace < storageSpaces);

        uint256 ROOT_SLOT = _get_root_slot(storageSpace);
        uint256 packValue;
        uint256 stringIndex;

        assembly 
        {
            //get member-specific data 0x[strindex][size][valType]
            packValue := sload(add(ROOT_SLOT, add(1, memberIndex)))

            //valType is the first 64 bits
            if iszero(eq(and(packValue, 0xFFFFFFFFFFFFFFFF), 6)) 
            {
                //Invalid type!
                mstore(0x0, 0x496e76616c6964207479706521)
                revert(0x0, 0x20)
            }

            stringIndex := and(
                shr(128, packValue),
                0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
            )

            if iszero(stringIndex) 
            {
                //System not initialized!
                mstore(0x0, 0x53797374656d206e6f7420696e697469616c697a656421)
                revert(0x0, 0x20)
            }
        }

        uint256 slot = _derive_user_slot(entryIndex, storageSpace, stringIndex, true, ROOT_SLOT,  specialAccess);

        assembly 
        {
            let size := sload(slot)

            //Empty string: nothing to return
            if eq(size, 0) 
            {
                mstore(0x0, 0x0)
                return(0x0, 0x20)
            }
            
            //now that we have the size in bytes, we can allocate memory to returnValue
            returnValue := mload(0x40)
            mstore(returnValue, size)

            //convert size to bits
            size := mul(size, 8)

            //this will be used in an upcoming for loop, and it makes the next line way more readable
            //( page + 1 ) * (32 bytes) => we know that it will take at least 1 page since 
            //we already returned if size is zero. Storing any data will obviously require a page 
            //to be occupied.  However, this is kind of confusing when you first look at it.
            let length := mul(0x20, add(div(size, 256), 1))
            let i := 0

            //store at 0x40 - mload(0x40) + advance 1 slot + advance slots per page
            mstore(0x40, add(mload(0x40), add(0x20, length)))

            //now that returnValue is allocated, we can start piling data into it
            for {} lt(i, length) {i := add(i, 1)} 
            {
                mstore(
                    add(add(returnValue, 0x20), mul(0x20, i)),
                    sload(add(add(slot, 1), i))
                )
            }
        }
    }

    /**
     * @notice Retrieve multiple values from a storage space-member-entry.
     * @dev Supports types 1..5
     */
    function get_batch(
        uint256[] memory members,
        uint256 entryIndex,
        uint256 storageSpace,
        bytes calldata specialAccess
    ) external view returns (uint256[] memory result)
    {
        require(entryIndex > 0, "invalid entry index");
        require(storageSpace < storageSpaces, "Invalid storage space!");

        uint256 ROOT_SLOT = _get_root_slot(storageSpace);
        uint256 slot = _derive_user_slot(entryIndex, storageSpace, 0, false, ROOT_SLOT,  specialAccess);

        //Allocate memory to the result array
        assembly 
        {
            result := mload(0x40)
            mstore(0x40, add(result, add(0x20, mul(0x20, mload(members)))))
            mstore(result, mload(members))
        }

        uint256 previousPage = 1e18;
        uint256 page;
        uint256 packValue;
        uint256 bitCount;
        uint256 size;
        uint256 valType;

        assembly 
        {
            /*
                a: start index (in page)
                b: end index (in page)
                0x...b...a...
            */
            let i := 0

            //identify page, create mask, pack value into slot
            //Only update packValue when on last iteration or previousPage != page
            for {} lt(i, mload(members)) {i := add(i, 1)} 
            {
                valType := sload(
                    add(
                            ROOT_SLOT, 
                            add(
                                    1, 
                                    mload(add(add(0x20, members), mul(0x20, i)))
                                )
                        )
                )
                
                size := and(shr(64, valType), 0xFFFFFFFFFFFFFFFF)
                bitCount := and(
                    shr(128, valType),
                    0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
                )
                valType := and(valType, 0xFFFFFFFFFFFFFFFF)

                if eq(valType, 6) 
                {
                    //No strings!
                    mstore(0x0, 0x4e6f20737472696e677321)
                    revert(0x0, 0x20)
                }

                //get the current page based on bitCount
                page := div(bitCount, 256)

                if iszero(eq(previousPage, page)) 
                {
                    //update packValue
                    packValue := sload(add(slot, page))
                }

                //local page offset ie 0x0000[bDATAa]...0
                let a := sub(bitCount, mul(256, div(bitCount, 256)))

                //0x0000...FFFF...0000
                let mask := shl(a, sub(shl(sub(add(a, size), a), 1), 1))

                //get value
                size := shr(a, and(packValue, mask))

                //put value in result
                mstore(add(add(result, 0x20), mul(0x20, i)), size)

                previousPage := page
            }
        }
    }

    /*
     * @notice get the size of a string in bytes
     * @dev Supports type 6
     */
    function get_string_size(
        uint256 memberIndex,
        uint256 entryIndex,
        uint256 storageSpace
    ) external view returns (uint256 size) 
    {
        require(entryIndex > 0, "invalid entry index");
        
        require(storageSpace < storageSpaces);
        uint256 ROOT_SLOT = _get_root_slot(storageSpace);

        assembly {
            //get strindex
            let stringIndex
            stringIndex := and(
                shr(64, sload(add(ROOT_SLOT, add(1, memberIndex)))),
                0xFFFFFFFFFFFFFFFF
            )

            mstore(
                0x0,
                or(
                    or(shl(224, stringIndex), shl(192, entryIndex)),
                    shl(160, and(storageSpace, 0xFFFF))
                )
            )
            let slot := keccak256(0x0, 0xC)
            size := sload(slot)
        }
    }

    /*------------------------------------------------------------------------------------------------
                                            View
    ------------------------------------------------------------------------------------------------*/

    /**
     * @notice Retrieve the metadata for a storage space member.
     * @dev Returns type, size, bitCount (slot offset up-to value).
     */
    function get_member_data(
        uint256 index,
        uint256 storageSpace
    ) public view returns (
        uint64 valType,
        uint64 size,
        uint128 bitCount
    ) 
    {
        require(storageSpace < storageSpaces, "invalid storage space");
        (uint64 members,,,,) = get_storage_space_metadata(storageSpace);
        require(index < members, "invalid member index");

        uint256 ROOT_SLOT = _get_root_slot(storageSpace);
        uint256 packValue;

        assembly {
            packValue := sload(add(ROOT_SLOT, add(1, index)))

            valType := and(packValue, 0xFFFFFFFFFFFFFFFF)
            size := and(shr(64, packValue), 0xFFFFFFFFFFFFFFFF)
            bitCount := and(shr(128, packValue), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)

        }
    }

    /**
     * @notice Retrieve the metadata for a storage space.
     * @dev Returns members, entries, stringIndex, safeIndex.
     * specification: github.com/wisecameron/ERCs/blob/wisecameron/erc-cds/ERCS/erc-7844.md
     */
    function get_storage_space_metadata(uint256 storageSpace)
    public view
    returns(
        uint64 members, 
        uint64 entries, 
        uint64 stringIndex, 
        uint64 safeIndex, 
        bool specialAccess)
    {
        require(storageSpace < storageSpaces);
        uint256 ROOT_SLOT = _get_root_slot(storageSpace);

        //sload(ROOT_SLOT) -> {members(64), entries(64), stringIndex(64), safeIndex (64)}
        assembly 
        {
            let fullSlot := sload(ROOT_SLOT)
            specialAccess := and(fullSlot, 0xFF)
            safeIndex := and(shr(32, fullSlot), 0xFFFFFFFF)
            stringIndex := and(shr(64, fullSlot), 0xFFFFFFFFFFFFFFFF)
            entries := and(shr(128, fullSlot), 0xFFFFFFFFFFFFFFFF)
            members := and(shr(192, fullSlot), 0xFFFFFFFFFFFFFFFF)
        }
    }

    function transparency_audit()
        external
        view
        returns (address[] memory, uint256[] memory permissionLevels)
    {
        uint256 l = permissionHolders.length;
        uint256 i;

        for (; i < l; i++) {
            permissionLevels[i] = permissions[permissionHolders[i]];
        }

        return (permissionHolders, permissionLevels);
    }

    /*------------------------------------------------------------------------------------------------
                                            2-Stage Put
    ------------------------------------------------------------------------------------------------*/

    /**
     * @notice Stage 1 of a 2-stage put operation.
     * @dev Supports types 1..5.  Pre-computes slot hash, page, and 
     * the packed data slot for a put operation within a gas-free 
     * view function.  This data is then passed ot stage2_put for 
     * a minimum-cost operation.
     */
    function stage1_put(
        uint256 data,
        uint256 memberIndex,
        uint256 entryIndex,
        uint256 storageSpace,
        bytes calldata specialAccess
    ) external view returns (uint256, uint256, uint256) 
    {

        uint256 ROOT_SLOT = _get_root_slot(storageSpace);

        require(entryIndex > 0 && storageSpace < storageSpaces, 
        "Failed to validate entry index or storage space");

        _access_control(msg.sender, PermissionFlags.Modify, false);
        _validate_memberIndex_and_entryIndex(ROOT_SLOT, memberIndex, entryIndex);
        uint256 slot = _derive_user_slot(entryIndex, storageSpace, 0, false, ROOT_SLOT, specialAccess);

        //verify type and size
        uint256 packValue;
        uint256 size;
        uint256 page;
        uint256 bitCount;

        assembly 
        {
            packValue := sload(add(ROOT_SLOT, add(1, memberIndex)))
            size := and(shr(64, packValue), 0xFFFFFFFFFFFFFFFF)
            bitCount := shr(128, packValue)
        }

        _validate_data(
            packValue & 0xFFFFFFFFFFFFFFFF, /* valType */
            size, 
            data
        );

        //prep data to match any type
        assembly {
            page := div(bitCount, 256)

            //add up to the data page -- hash(index + storageSpace * ENTRIES_LIM) + page
            packValue := sload(add(slot, page))

            /* zero out the area that will be replaced */

            //start index is bitCount - (256 * (bitCount / 256))
            //let a := div(bitCount, 256) -> 1042 -> 4.0703125 -> 4
            //a := mul(a, 256) -> 4 * 256 = 1024
            //a := sub(bitCount, a) -> 1042 - 1024 = 18
            //so, our slot is filled until bit 18
            let precedingBits := mod(bitCount, 256)

            //Clear the old value and insert our new data
            packValue := or(
                and(
                    packValue, 
                    not(shl(precedingBits, sub(shl(size, 1), 1)))
                ), 
                shl(precedingBits, data)
            )
        }
        return (slot, page, packValue);
    }

    /**
     * @notice Stage 2 of a 2-stage put operation.
     * @dev Writes the data to the storage system.  
     */
    function stage2_put(
        uint256 slotHash,
        uint256 page,
        uint256 packValue
    ) external 
    {
        _access_control(msg.sender, PermissionFlags.Modify, false);

        assembly {
            mstore(0x0, slotHash)
            sstore(add(keccak256(0x0, 0x8), page), packValue)
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
            mstore(0x0, shl(176, mul(storageSpace, MEMBERS_LIM)))
            slot := keccak256(0x0, 0xA)
        }
    }

    function _validate_memberIndex_and_entryIndex(
        uint256 ROOT_SLOT, 
        uint256 memberIndex, 
        uint256 entryIndex
    )
    internal view
    {
        require(entryIndex > 0, "invalid entry index");
        assembly 
        {
            let fullSlot := sload(ROOT_SLOT)

            
            if or(
                iszero(gt(shr(192, fullSlot) /*totalMembers*/, memberIndex)),
                iszero(gt(and(shr(128, fullSlot), 0xFFFFFFFFFFFFFFFF) /*totalEntries*/, entryIndex))
            )
            {
                //invalid entry or member
                mstore(0x0, 0x496e76616c696420656e747279206f72206d656d626572)
                revert(0x0, 0x20)
            }
        }
    }

    function _validate_members_and_entryIndex(
        uint256 ROOT_SLOT, 
        uint256 entryIndex,
        uint256[] memory members
    ) internal view
    {
        require(entryIndex > 0, "invalid entry index");
        uint256 fullSlot;
        uint256 totalMembers;
        uint256 totalEntries;

        if(members.length == 0) revert("No members!");

        assembly
        {
            fullSlot := sload(ROOT_SLOT)

            totalMembers := shr(192, fullSlot)
            totalEntries := and(shr(128, fullSlot), 0xFFFFFFFFFFFFFFFF)

            //invalid entry!
            if iszero(gt(totalEntries, entryIndex))
            {
                mstore(0x0, 0x496e76616c696420656e74727921)
                revert(0x0, 0x20)
            }

            let len := mload(members)

            for {let i := 0} lt(i, members) {i := add(i, 1)}
            {
                let currentMember := mload(add(add(members, 0x20), mul(0x20, i)))

                //invalid member!
                if iszero(gt(totalMembers, currentMember))
                {
                    mstore(0x0, 0x496e76616c6964206d656d62657221)
                    revert(0x0, 0x20)
                }
            }
            
        }
    }

    function _validate_new_member_size(uint256 valType, uint256 size)
    internal pure
    {
        assembly
        {
            if or(eq(valType, 1), eq(valType, 2)) 
            {
                //not in pow2!
                if iszero(iszero(and(size, sub(size, 1)))) 
                {
                    mstore(0x0, 0x4e6f7420696e20706f773221)
                    revert(0x0, 0x20)
                }

                //invalid size!
                if or(lt(size, 8), gt(size, 256)) 
                {
                    mstore(0x0, 0x496e76616c69642073697a6521)
                    revert(0x0, 0x20)
                }
            }

            //if bool set size to 8
            if eq(valType, 3) 
            {
                if iszero(eq(size, 8))
                {
                    //invalid size!
                    mstore(0x0, 0x496e76616c69642073697a6521)
                    revert(0x0, 0x20)
                }
            }

            if eq(valType, 4) 
            {
                if iszero(eq(size, 160))
                {
                    //invalid size!
                    mstore(0x0, 0x496e76616c69642073697a6521)
                    revert(0x0, 0x20)
                }
            }

            //if bytes32 set size to 256
            if eq(valType, 5) 
            {
                if iszero(eq(size, 256))
                {
                    //invalid size!
                    mstore(0x0, 0x496e76616c69642073697a6521)
                    revert(0x0, 0x20)
                }
            }
        }
    }

    function _validate_data(uint256 valType, uint256 size, uint256 data)
    internal pure
    {
        uint256 adjustedData;
        if (valType == 2) valType = 1;

        //prep data to match any type
        assembly 
        {
            switch valType
            case 1 //int, uint
            { 
                adjustedData := and(data, sub(shl(size, 1), 1))
            }
            case 3 //bool
            { 
                adjustedData := and(data, 0x1)
            }
            case 4 //addr
            { 
                adjustedData := and(data, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            }
            case 5 {} //bytes32
            default 
            {
                //function doesn't support string!
                mstore(0x0, 0x46756e6374696f6e20646f65736e277420737570706f727420737472696e6721)
                revert(0x0, 0x20)
            }
        }

        require(adjustedData == data, "Data too large for type!");
    }

    /**
     * @notice Map address index to uint256 entryIndex.
     * 
     * usage: get(memberIndex, address_indexed(..., storageSpace), storageSpace)
     */
    function address_indexed(
        address target,
        uint256 storageSpace
    ) external view returns(uint256 userIndex)
    {
        userIndex = addressIndices[storageSpace][target];
    }

    /*------------------------------------------------------------------------------------------------
                                            Internal
    ------------------------------------------------------------------------------------------------*/

    function _validate_permission_changes(
        address target,
        address sender
    ) internal view
    {
        uint8 senderPermSlot;
        uint8 targetPermSlot;

        assembly
        {
            mstore(0x0, target)
            mstore(0x20, permissions.slot)
            targetPermSlot := sload(keccak256(0x0, 0x40))

            mstore(0x0, sender)
            senderPermSlot := sload(keccak256(0x0, 0x40))

            //verify sender can grant permissions
            if iszero(
                and(
                    shr(35, senderPermSlot),
                    0x1
                )
            )
            {
                mstore(0x0, 0x696e76616c6964207065726d697373696f6e7321)
                revert(0x0, 0x20)   
            }   

            //if target can grant permissions, only they can modify their own permissions
            if and(
                    shr(35, targetPermSlot),
                    0x1
                ) 
            {
                //verify sender is target
                if iszero(eq(sender, target))
                {
                    //Invalid permissions!
                    mstore(0x0, 0x496e76616c6964205065726d697373696f6e7321)
                    revert(0x0, 0x20)
                }
            }
        }
    }

    //for basic mode, only the first permissionData element is used 
    //to determine permission level.
    /**
     * @dev 0x|...(@32 bits : granular permissions) (@8 bits: 8 bit size)|
     */
    function _update_permission_data(
        uint8[] memory permissionData,
        address user,
        bool remove
    ) 
    internal view returns(uint256)
    {
        uint256 packedPermissionData;

        assembly
        {   
            let len := mload(permissionData)
            let i := 0
            let currentPermission

            //set contract flag -- 1st bit
            if iszero(iszero(extcodesize(user)))
            {
                packedPermissionData := 0x1
            }

            for{} lt(i, len) {i := add(i, 1)}
            {
                currentPermission := mload(add(add(permissionData, 0x20), mul(0x20, i)))

                if remove
                {
                    packedPermissionData := and(
                        packedPermissionData,
                        not(shl(add(currentPermission, 32), 1))
                    )
                }

                if iszero(remove)
                {
                    packedPermissionData := or(
                        packedPermissionData, shl(add(currentPermission, 32), 1)
                    )
                }

            }
            
        }
        return packedPermissionData;
    }

    function _derive_user_slot(
        uint256 entryIndex,
        uint256 storageSpace,
        uint256 entryStringIndex,
        bool isString,
        uint256 root_slot,
        bytes calldata specialAccess
    )
    internal view
    returns(uint256 slot)
    {
        bool isSpecialAccess = false;
        uint256 length = specialAccess.length;

        assembly
        {
            let fullSlot := sload(root_slot)
            isSpecialAccess := and(fullSlot, 0x1)

            //always + 2 bytes for storageSpace, 4 bytes for entryStringIndex
            if isSpecialAccess
            {
                let ptr := mload(0x40)
                let offsetSize := 2
                mstore(ptr, storageSpace)

                if isString
                {
                    mstore(add(ptr, 2), entryStringIndex)
                    offsetSize := 6
                }

                calldatacopy(add(ptr, offsetSize), add(specialAccess.offset, 32), length)
                length := add(offsetSize, length)
                slot := keccak256(ptr, length)
            }


            if iszero(isSpecialAccess)
            {
                if isString
                {
                    mstore(
                        0x0,
                        or(
                            or(shl(224, entryStringIndex), shl(192, entryIndex)),
                            shl(160, and(storageSpace, 0xFFFF))
                        )
                    )
                    slot := keccak256(0x0, 0xC)
                }

                if iszero(isString)
                {
                    mstore(
                        0x0,
                        shl(
                            168,
                            add(entryIndex, mul(ENTRIES_LIM, storageSpace))
                        )
                    )
                    slot := keccak256(0x0, 0xB)
                }   
            }
        }

        return slot;
    }

    
    function _access_control(
        address user, 
        PermissionFlags functionType,
        bool contractsOnly
    )
    internal view
    {
        if(msg.sender == address(this)) return;

        assembly
        {
            mstore(0x0, user)
            mstore(0x20, permissions.slot)
            let userPerms := sload(keccak256(0x0, 0x40))

            if or(
                and(
                    contractsOnly,
                    iszero(
                        eq(
                            and(userPerms, 0x1),
                            1
                        )
                    )
                ),
                iszero(
                    eq(
                        and(
                            shr(
                                add(32, functionType),
                                userPerms
                            ),
                            1
                        ),
                        1
                    )
                )
            )
            {
                //Inadequate permissions!
                mstore(0x0, userPerms)
                revert(0x0, 0x20)
            }
        }
    }
}