// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.21;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title ERC-7508 Public On-Chain NFT Attributes Repository
 * @author Steven Pineda, Jan Turk
 * @notice Interface smart contract of Dynamic On-Chain Token Attributes Repository
 */
interface IERC7508 is IERC165 {
    /**
     * @notice A list of supported access types.
     * @return The `Owner` type, where only the owner can manage the parameter.
     * @return The `Collaborator` type, where only the collaborators can manage the parameter.
     * @return The `OwnerOrCollaborator` type, where only the owner or collaborators can manage the parameter.
     * @return The `TokenOwner` type, where only the token owner can manage the parameters of their tokens.
     * @return The `SpecificAddress` type, where only specific addresses can manage the parameter.
     */
    enum AccessType {
        Owner,
        Collaborator,
        OwnerOrCollaborator,
        TokenOwner,
        SpecificAddress
    }

    /**
     * @notice Structure used to represent an address attribute.
     * @return key The key of the attribute
     * @return value The value of the attribute
     */
    struct AddressAttribute {
        string key;
        address value;
    }

    /**
     * @notice Structure used to represent a boolean attribute.
     * @return key The key of the attribute
     * @return value The value of the attribute
     */
    struct BoolAttribute {
        string key;
        bool value;
    }

    /**
     * @notice Structure used to represent a bytes attribute.
     * @return key The key of the attribute
     * @return value The value of the attribute
     */
    struct BytesAttribute {
        string key;
        bytes value;
    }

    /**
     * @notice Structure used to represent an int attribute.
     * @return key The key of the attribute
     * @return value The value of the attribute
     */
    struct IntAttribute {
        string key;
        int256 value;
    }

    /**
     * @notice Structure used to represent a string attribute.
     * @return key The key of the attribute
     * @return value The value of the attribute
     */
    struct StringAttribute {
        string key;
        string value;
    }

    /**
     * @notice Structure used to represent an uint attribute.
     * @return key The key of the attribute
     * @return value The value of the attribute
     */
    struct UintAttribute {
        string key;
        uint256 value;
    }

    /**
     * @notice Used to notify listeners that a new collection has been registered to use the repository.
     * @param collection Address of the collection
     * @param owner Address of the owner of the collection; the addess authorized to manage the access control
     * @param registeringAddress Address that registered the collection
     * @param useOwnable A boolean value indicating whether the collection uses the Ownable extension to verify the
     *  owner (`true`) or not (`false`)
     */
    event AccessControlRegistration(
        address indexed collection,
        address indexed owner,
        address indexed registeringAddress,
        bool useOwnable
    );

    /**
     * @notice Used to notify listeners that the access control settings for a specific parameter have been updated.
     * @param collection Address of the collection
     * @param key The name of the parameter for which the access control settings have been updated
     * @param accessType The AccessType of the parameter for which the access control settings have been updated
     * @param specificAddress The specific addresses that has been updated
     */
    event AccessControlUpdate(
        address indexed collection,
        string key,
        AccessType accessType,
        address specificAddress
    );

    /**
     * @notice Used to notify listeners that the metadata URI for a collection has been updated.
     * @param collection Address of the collection
     * @param attributesMetadataURI The new attributes metadata URI
     */
    event MetadataURIUpdated(
        address indexed collection,
        string attributesMetadataURI
    );

    /**
     * @notice Used to notify listeners that a new collaborator has been added or removed.
     * @param collection Address of the collection
     * @param collaborator Address of the collaborator
     * @param isCollaborator A boolean value indicating whether the collaborator has been added (`true`) or removed
     *  (`false`)
     */
    event CollaboratorUpdate(
        address indexed collection,
        address indexed collaborator,
        bool isCollaborator
    );

    /**
     * @notice Used to notify listeners that an address attribute has been updated.
     * @param collection The collection address
     * @param tokenId The token ID
     * @param key The key of the attribute
     * @param value The new value of the attribute
     */
    event AddressAttributeUpdated(
        address indexed collection,
        uint256 indexed tokenId,
        string key,
        address value
    );

    /**
     * @notice Used to notify listeners that a boolean attribute has been updated.
     * @param collection The collection address
     * @param tokenId The token ID
     * @param key The key of the attribute
     * @param value The new value of the attribute
     */
    event BoolAttributeUpdated(
        address indexed collection,
        uint256 indexed tokenId,
        string key,
        bool value
    );

    /**
     * @notice Used to notify listeners that a bytes attribute has been updated.
     * @param collection The collection address
     * @param tokenId The token ID
     * @param key The key of the attribute
     * @param value The new value of the attribute
     */
    event BytesAttributeUpdated(
        address indexed collection,
        uint256 indexed tokenId,
        string key,
        bytes value
    );

    /**
     * @notice Used to notify listeners that an int attribute has been updated.
     * @param collection The collection address
     * @param tokenId The token ID
     * @param key The key of the attribute
     * @param value The new value of the attribute
     */
    event IntAttributeUpdated(
        address indexed collection,
        uint256 indexed tokenId,
        string key,
        int256 value
    );

    /**
     * @notice Used to notify listeners that a string attribute has been updated.
     * @param collection The collection address
     * @param tokenId The token ID
     * @param key The key of the attribute
     * @param value The new value of the attribute
     */
    event StringAttributeUpdated(
        address indexed collection,
        uint256 indexed tokenId,
        string key,
        string value
    );

    /**
     * @notice Used to notify listeners that an uint attribute has been updated.
     * @param collection The collection address
     * @param tokenId The token ID
     * @param key The key of the attribute
     * @param value The new value of the attribute
     */
    event UintAttributeUpdated(
        address indexed collection,
        uint256 indexed tokenId,
        string key,
        uint256 value
    );

    // ------------------- ACCESS CONTROL -------------------

    /**
     * @notice Used to check if the specified address is listed as a collaborator of the given collection's parameter.
     * @param collaborator Address to be checked.
     * @param collection Address of the collection.
     * @return isCollaborator_ Boolean value indicating if the address is a collaborator of the given collection's (`true`) or not
     *  (`false`).
     */
    function isCollaborator(
        address collaborator,
        address collection
    ) external view returns (bool isCollaborator_);

    /**
     * @notice Used to check if the specified address is listed as a specific address of the given collection's
     *  parameter.
     * @param specificAddress Address to be checked.
     * @param collection Address of the collection.
     * @param key The key of the attribute
     * @return isSpecificAddress_ Boolean value indicating if the address is a specific address of the given collection's parameter
     *  (`true`) or not (`false`).
     */
    function isSpecificAddress(
        address specificAddress,
        address collection,
        string memory key
    ) external view returns (bool isSpecificAddress_);

    /**
     * @notice Used to register a collection to use the RMRK token attributes repository.
     * @dev  If the collection does not implement the Ownable interface, the `useOwnable` value must be set to `false`.
     * @dev Emits an {AccessControlRegistration} event.
     * @param collection The address of the collection that will use the RMRK token attributes repository.
     * @param owner The address of the owner of the collection.
     * @param useOwnable The boolean value to indicate if the collection implements the Ownable interface and whether it
     *  should be used to validate that the caller is the owner (`true`) or to use the manually set owner address
     *  (`false`).
     */
    function registerAccessControl(
        address collection,
        address owner,
        bool useOwnable
    ) external;

    /**
     * @notice Used to manage the access control settings for a specific parameter.
     * @dev Only the `owner` of the collection can call this function.
     * @dev The possible `accessType` values are:
     *  [
     *      Owner,
     *      Collaborator,
     *      OwnerOrCollaborator,
     *      TokenOwner,
     *      SpecificAddress,
     *  ]
     * @dev Emits an {AccessControlUpdated} event.
     * @param collection The address of the collection being managed.
     * @param key The key of the attribute
     * @param accessType The type of access control to be applied to the parameter.
     * @param specificAddress The address to be added as a specific addresses allowed to manage the given
     *  parameter.
     */
    function manageAccessControl(
        address collection,
        string memory key,
        AccessType accessType,
        address specificAddress
    ) external;

    /**
     * @notice Used to manage the collaborators of a collection.
     * @dev The `collaboratorAddresses` and `collaboratorAddressAccess` arrays must be of the same length.
     * @dev Emits a {CollaboratorUpdate} event.
     * @param collection The address of the collection
     * @param collaboratorAddresses The array of collaborator addresses being managed
     * @param collaboratorAddressAccess The array of boolean values indicating if the collaborator address should
     *  receive the permission (`true`) or not (`false`).
     */
    function manageCollaborators(
        address collection,
        address[] memory collaboratorAddresses,
        bool[] memory collaboratorAddressAccess
    ) external;

    // ------------------- METADATA URI -------------------

    /**
     * @notice Used to retrieve the attributes metadata URI for a collection, which contains all the information about the collection attributes.
     * @param collection Address of the collection
     * @return attributesMetadataURI The URI of the attributes metadata
     */
    function getAttributesMetadataURIForCollection(
        address collection
    ) external view returns (string memory attributesMetadataURI);

    /**
     * @notice Used to set the metadata URI for a collection, which contains all the information about the collection attributes.
     * @dev Emits a {MetadataURIUpdated} event.
     * @param collection Address of the collection
     * @param attributesMetadataURI The URI of the attributes metadata
     */
    function setAttributesMetadataURIForCollection(
        address collection,
        string memory attributesMetadataURI
    ) external;

    // ------------------- GETTERS -------------------

    /**
     * @notice Used to retrieve the address type token attributes.
     * @param collection The collection address
     * @param tokenId The token ID
     * @param key The key of the attribute
     * @return attribute The value of the address attribute
     */
    function getAddressAttribute(
        address collection,
        uint256 tokenId,
        string memory key
    ) external view returns (address attribute);

    /**
     * @notice Used to retrieve the bool type token attributes.
     * @param collection The collection address
     * @param tokenId The token ID
     * @param key The key of the attribute
     * @return attribute The value of the bool attribute
     */
    function getBoolAttribute(
        address collection,
        uint256 tokenId,
        string memory key
    ) external view returns (bool attribute);

    /**
     * @notice Used to retrieve the bytes type token attributes.
     * @param collection The collection address
     * @param tokenId The token ID
     * @param key The key of the attribute
     * @return attribute The value of the bytes attribute
     */
    function getBytesAttribute(
        address collection,
        uint256 tokenId,
        string memory key
    ) external view returns (bytes memory attribute);

    /**
     * @notice Used to retrieve the uint type token attributes.
     * @param collection The collection address
     * @param tokenId The token ID
     * @param key The key of the attribute
     * @return attribute The value of the uint attribute
     */
    function getUintAttribute(
        address collection,
        uint256 tokenId,
        string memory key
    ) external view returns (uint256 attribute);
    /**
     * @notice Used to retrieve the string type token attributes.
     * @param collection The collection address
     * @param tokenId The token ID
     * @param key The key of the attribute
     * @return attribute The value of the string attribute
     */
    function getStringAttribute(
        address collection,
        uint256 tokenId,
        string memory key
    ) external view returns (string memory attribute);

    /**
     * @notice Used to retrieve the int type token attributes.
     * @param collection The collection address
     * @param tokenId The token ID
     * @param key The key of the attribute
     * @return attribute The value of the uint attribute
     */
    function getIntAttribute(
        address collection,
        uint256 tokenId,
        string memory key
    ) external view returns (int256 attribute);

    // ------------------- BATCH GETTERS -------------------

    /**
     * @notice Used to get multiple address parameter values for a token.
     * @dev The `AddressAttribute` struct contains the following fields:
     *  [
     *     string key,
     *     address value
     *  ]
     * @param collections Addresses of the collections, in the same order as the attribute keys. If all tokens are from the same collection the array can contain a single element with the collection address.
     * @param tokenIds IDs of the tokens, in the same order as the attribute keys. If all attributes are for the same token the array can contain a single element with the token ID.
     * @param attributeKeys An array of address keys to retrieve
     * @return attributes An array of addresses, in the same order as the attribute keys
     */
    function getAddressAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        string[] memory attributeKeys
    ) external view returns (address[] memory attributes);

    /**
     * @notice Used to get multiple bool parameter values for a token.
     * @dev The `BoolAttribute` struct contains the following fields:
     *  [
     *     string key,
     *     bool value
     *  ]
     * @param collections Addresses of the collections, in the same order as the attribute keys. If all tokens are from the same collection the array can contain a single element with the collection address.
     * @param tokenIds IDs of the tokens, in the same order as the attribute keys. If all attributes are for the same token the array can contain a single element with the token ID.
     * @param attributeKeys An array of bool keys to retrieve
     * @return attributes An array of bools, in the same order as the attribute keys
     */
    function getBoolAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        string[] memory attributeKeys
    ) external view returns (bool[] memory attributes);

    /**
     * @notice Used to get multiple bytes parameter values for a token.
     * @dev The `BytesAttribute` struct contains the following fields:
     *  [
     *     string key,
     *     bytes value
     *  ]
     * @param collections Addresses of the collections, in the same order as the attribute keys. If all tokens are from the same collection the array can contain a single element with the collection address.
     * @param tokenIds IDs of the tokens, in the same order as the attribute keys. If all attributes are for the same token the array can contain a single element with the token ID.
     * @param attributeKeys An array of bytes keys to retrieve
     * @return attributes An array of bytes, in the same order as the attribute keys
     */
    function getBytesAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        string[] memory attributeKeys
    ) external view returns (bytes[] memory attributes);

    /**
     * @notice Used to get multiple int parameter values for a token.
     * @param collections Addresses of the collections, in the same order as the attribute keys. If all tokens are from the same collection the array can contain a single element with the collection address.
     * @param tokenIds IDs of the tokens, in the same order as the attribute keys. If all attributes are for the same token the array can contain a single element with the token ID.
     * @param attributeKeys An array of int keys to retrieve
     * @return attributes An array of ints, in the same order as the attribute keys
     */
    function getIntAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        string[] memory attributeKeys
    ) external view returns (int256[] memory attributes);

    /**
     * @notice Used to get multiple sting parameter values for a token.
     * @param collections Addresses of the collections, in the same order as the attribute keys. If all tokens are from the same collection the array can contain a single element with the collection address.
     * @param tokenIds IDs of the tokens, in the same order as the attribute keys. If all attributes are for the same token the array can contain a single element with the token ID.
     * @param attributeKeys An array of string keys to retrieve
     * @return attributes An array of strings, in the same order as the attribute keys
     */
    function getStringAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        string[] memory attributeKeys
    ) external view returns (string[] memory attributes);

    /**
     * @notice Used to get multiple uint parameter values for a token.
     * @param collections Addresses of the collections, in the same order as the attribute keys. If all tokens are from the same collection the array can contain a single element with the collection address.
     * @param tokenIds IDs of the tokens, in the same order as the attribute keys. If all attributes are for the same token the array can contain a single element with the token ID.
     * @param attributeKeys An array of uint keys to retrieve
     * @return attributes An array of uints, in the same order as the attribute keys
     */
    function getUintAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        string[] memory attributeKeys
    ) external view returns (uint256[] memory attributes);

    /**
     * @notice Used to retrieve multiple token attributes of any type at once.
     * @dev The `StringAttribute`, `UintAttribute`, `IntAttribute`, `BoolAttribute`, `AddressAttribute` and `BytesAttribute` structs consists
     *  to the following fields (where `value` is of the appropriate type):
     *  [
     *      key,
     *      value,
     *  ]
     * @param collection The collection address
     * @param tokenId The token ID
     * @param addressKeys An array of address type attribute keys to retrieve
     * @param boolKeys An array of bool type attribute keys to retrieve
     * @param bytesKeys An array of bytes type attribute keys to retrieve
     * @param intKeys An array of int type attribute keys to retrieve
     * @param stringKeys An array of string type attribute keys to retrieve
     * @param uintKeys An array of uint type attribute keys to retrieve
     * @return addressAttributes An array of addresses, in the same order as the addressKeys
     * @return boolAttributes An array of bools, in the same order as the boolKeys
     * @return bytesAttributes An array of bytes, in the same order as the bytesKeys
     * @return intAttributes An array of ints, in the same order as the intKeys
     * @return stringAttributes An array of strings, in the same order as the stringKeys
     * @return uintAttributes An array of uints, in the same order as the uintKeys
     */
    function getAttributes(
        address collection,
        uint256 tokenId,
        string[] memory addressKeys,
        string[] memory boolKeys,
        string[] memory bytesKeys,
        string[] memory intKeys,
        string[] memory stringKeys,
        string[] memory uintKeys
    )
        external
        view
        returns (
            address[] memory addressAttributes,
            bool[] memory boolAttributes,
            bytes[] memory bytesAttributes,
            int256[] memory intAttributes,
            string[] memory stringAttributes,
            uint256[] memory uintAttributes
        );

    // ------------------- PREPARE PRESIGNED MESSAGES -------------------

    /**
     * @notice Used to retrieve the message to be signed for submitting a presigned address attribute change.
     * @param collection The address of the collection smart contract of the token receiving the attribute
     * @param tokenId The ID of the token receiving the attribute
     * @param key The attribute key
     * @param value The attribute value
     * @param deadline The deadline timestamp for the presigned transaction after which the message is invalid
     * @return message Raw message to be signed by the authorized account
     */
    function prepareMessageToPresignAddressAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        address value,
        uint256 deadline
    ) external view returns (bytes32 message);

    /**
     * @notice Used to retrieve the message to be signed for submitting a presigned bool attribute change.
     * @param collection The address of the collection smart contract of the token receiving the attribute
     * @param tokenId The ID of the token receiving the attribute
     * @param key The attribute key
     * @param value The attribute value
     * @param deadline The deadline timestamp for the presigned transaction after which the message is invalid
     * @return message Raw message to be signed by the authorized account
     */
    function prepareMessageToPresignBoolAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        bool value,
        uint256 deadline
    ) external view returns (bytes32 message);

    /**
     * @notice Used to retrieve the message to be signed for submitting a presigned bytes attribute change.
     * @param collection The address of the collection smart contract of the token receiving the attribute
     * @param tokenId The ID of the token receiving the attribute
     * @param key The attribute key
     * @param value The attribute value
     * @param deadline The deadline timestamp for the presigned transaction after which the message is invalid
     * @return message Raw message to be signed by the authorized account
     */
    function prepareMessageToPresignBytesAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        bytes memory value,
        uint256 deadline
    ) external view returns (bytes32 message);

    /**
     * @notice Used to retrieve the message to be signed for submitting a presigned int attribute change.
     * @param collection The address of the collection smart contract of the token receiving the attribute
     * @param tokenId The ID of the token receiving the attribute
     * @param key The attribute key
     * @param value The attribute value
     * @param deadline The deadline timestamp for the presigned transaction after which the message is invalid
     * @return message Raw message to be signed by the authorized account
     */
    function prepareMessageToPresignIntAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        int256 value,
        uint256 deadline
    ) external view returns (bytes32 message);

    /**
     * @notice Used to retrieve the message to be signed for submitting a presigned string attribute change.
     * @param collection The address of the collection smart contract of the token receiving the attribute
     * @param tokenId The ID of the token receiving the attribute
     * @param key The attribute key
     * @param value The attribute value
     * @param deadline The deadline timestamp for the presigned transaction after which the message is invalid
     * @return message Raw message to be signed by the authorized account
     */
    function prepareMessageToPresignStringAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        string memory value,
        uint256 deadline
    ) external view returns (bytes32 message);

    /**
     * @notice Used to retrieve the message to be signed for submitting a presigned uint attribute change.
     * @param collection The address of the collection smart contract of the token receiving the attribute
     * @param tokenId The ID of the token receiving the attribute
     * @param key The attribute key
     * @param value The attribute value
     * @param deadline The deadline timestamp for the presigned transaction after which the message is invalid
     * @return message Raw message to be signed by the authorized account
     */
    function prepareMessageToPresignUintAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        uint256 value,
        uint256 deadline
    ) external view returns (bytes32 message);

    // ------------------- SETTERS -------------------

    /**
     * @notice Used to set an address attribute.
     * @dev Emits a {AddressAttributeUpdated} event.
     * @param collection Address of the collection receiving the attribute
     * @param tokenId The token ID
     * @param key The attribute key
     * @param value The attribute value
     */
    function setAddressAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        address value
    ) external;

    /**
     * @notice Used to set a boolean attribute.
     * @dev Emits a {BoolAttributeUpdated} event.
     * @param collection Address of the collection receiving the attribute
     * @param tokenId The token ID
     * @param key The attribute key
     * @param value The attribute value
     */
    function setBoolAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        bool value
    ) external;

    /**
     * @notice Used to set an bytes attribute.
     * @dev Emits a {BytesAttributeUpdated} event.
     * @param collection Address of the collection receiving the attribute
     * @param tokenId The token ID
     * @param key The attribute key
     * @param value The attribute value
     */
    function setBytesAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        bytes memory value
    ) external;

    /**
     * @notice Used to set a signed number attribute.
     * @dev Emits a {IntAttributeUpdated} event.
     * @param collection Address of the collection receiving the attribute
     * @param tokenId The token ID
     * @param key The attribute key
     * @param value The attribute value
     */
    function setIntAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        int256 value
    ) external;

    /**
     * @notice Used to set a string attribute.
     * @dev Emits a {StringAttributeUpdated} event.
     * @param collection Address of the collection receiving the attribute
     * @param tokenId The token ID
     * @param key The attribute key
     * @param value The attribute value
     */
    function setStringAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        string memory value
    ) external;

    /**
     * @notice Used to set an unsigned number attribute.
     * @dev Emits a {UintAttributeUpdated} event.
     * @param collection Address of the collection receiving the attribute
     * @param tokenId The token ID
     * @param key The attribute key
     * @param value The attribute value
     */
    function setUintAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        uint256 value
    ) external;

    // ------------------- BATCH SETTERS -------------------

    /**
     * @notice Sets multiple address attributes for a token at once.
     * @dev The `AddressAttribute` struct contains the following fields:
     *  [
     *      string key,
     *      address value
     *  ]
     * @param collections Addresses of the collections, in the same order as the attributes. If all tokens are from the same collection the array can contain a single element with the collection address.
     * @param tokenIds IDs of the tokens, in the same order as the attributes. If all attributes are for the same token the array can contain a single element with the token ID.
     * @param attributes An array of `AddressAttribute` structs to be assigned to the given token
     */
    function setAddressAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        AddressAttribute[] memory attributes
    ) external;

    /**
     * @notice Sets multiple bool attributes for a token at once.
     * @dev The `BoolAttribute` struct contains the following fields:
     *  [
     *      string key,
     *      bool value
     *  ]
     * @param collections Addresses of the collections, in the same order as the attributes. If all tokens are from the same collection the array can contain a single element with the collection address.
     * @param tokenIds IDs of the tokens, in the same order as the attributes. If all attributes are for the same token the array can contain a single element with the token ID.
     * @param attributes An array of `BoolAttribute` structs to be assigned to the given token
     */
    function setBoolAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        BoolAttribute[] memory attributes
    ) external;

    /**
     * @notice Sets multiple bytes attributes for a token at once.
     * @dev The `BytesAttribute` struct contains the following fields:
     *  [
     *      string key,
     *      bytes value
     *  ]
     * @param collections Addresses of the collections, in the same order as the attributes. If all tokens are from the same collection the array can contain a single element with the collection address.
     * @param tokenIds IDs of the tokens, in the same order as the attributes. If all attributes are for the same token the array can contain a single element with the token ID.
     * @param attributes An array of `BytesAttribute` structs to be assigned to the given token
     */
    function setBytesAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        BytesAttribute[] memory attributes
    ) external;

    /**
     * @notice Sets multiple int attributes for a token at once.
     * @dev The `UintAttribute` struct contains the following fields:
     *  [
     *      string key,
     *      int value
     *  ]
     * @param collections Addresses of the collections, in the same order as the attributes. If all tokens are from the same collection the array can contain a single element with the collection address.
     * @param tokenIds IDs of the tokens, in the same order as the attributes. If all attributes are for the same token the array can contain a single element with the token ID.
     * @param attributes An array of `IntAttribute` structs to be assigned to the given token
     */
    function setIntAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        IntAttribute[] memory attributes
    ) external;

    /**
     * @notice Sets multiple string attributes for a token at once.
     * @dev The `StringAttribute` struct contains the following fields:
     *  [
     *      string key,
     *      string value
     *  ]
     * @param collections Addresses of the collections, in the same order as the attributes. If all tokens are from the same collection the array can contain a single element with the collection address.
     * @param tokenIds IDs of the tokens, in the same order as the attributes. If all attributes are for the same token the array can contain a single element with the token ID.
     * @param attributes An array of `StringAttribute` structs to be assigned to the given token
     */
    function setStringAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        StringAttribute[] memory attributes
    ) external;

    /**
     * @notice Sets multiple uint attributes for a token at once.
     * @dev The `UintAttribute` struct contains the following fields:
     *  [
     *      string key,
     *      uint value
     *  ]
     * @param collections Addresses of the collections, in the same order as the attributes. If all tokens are from the same collection the array can contain a single element with the collection address.
     * @param tokenIds IDs of the tokens, in the same order as the attributes. If all attributes are for the same token the array can contain a single element with the token ID.
     * @param attributes An array of `UintAttribute` structs to be assigned to the given token
     */
    function setUintAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        UintAttribute[] memory attributes
    ) external;

    /**
     * @notice Sets multiple attributes of multiple types for a token at the same time.
     * @dev Emits a separate event for each attribute set.
     * @dev The `StringAttribute`, `UintAttribute`, `BoolAttribute`, `AddressAttribute` and `BytesAttribute` structs consists
     *  to the following fields (where `value` is of the appropriate type):
     *  [
     *      key,
     *      value,
     *  ]
     * @param collection The address of the collection
     * @param tokenId The token ID
     * @param addressAttributes An array of `AddressAttribute` structs containing address attributes to set
     * @param boolAttributes An array of `BoolAttribute` structs containing bool attributes to set
     * @param bytesAttributes An array of `BytesAttribute` structs containing bytes attributes to set
     * @param intAttributes An array of `IntAttribute` structs containing int attributes to set
     * @param stringAttributes An array of `StringAttribute` structs containing string attributes to set
     * @param uintAttributes An array of `UintAttribute` structs containing uint attributes to set
     */
    function setAttributes(
        address collection,
        uint256 tokenId,
        AddressAttribute[] memory addressAttributes,
        BoolAttribute[] memory boolAttributes,
        BytesAttribute[] memory bytesAttributes,
        IntAttribute[] memory intAttributes,
        StringAttribute[] memory stringAttributes,
        UintAttribute[] memory uintAttributes
    ) external;

    // ------------------- PRESIGNED SETTERS -------------------

    /**
     * @notice Used to set the address attribute on behalf of an authorized account.
     * @dev Emits a {AddressAttributeUpdated} event.
     * @param setter Address of the account that presigned the attribute change
     * @param collection Address of the collection receiving the attribute
     * @param tokenId The ID of the token receiving the attribute
     * @param key The attribute key
     * @param value The attribute value
     * @param deadline The deadline timestamp for the presigned transaction
     * @param v `v` value of an ECDSA signature of the presigned message
     * @param r `r` value of an ECDSA signature of the presigned message
     * @param s `s` value of an ECDSA signature of the presigned message
     */
    function presignedSetAddressAttribute(
        address setter,
        address collection,
        uint256 tokenId,
        string memory key,
        address value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @notice Used to set the bool attribute on behalf of an authorized account.
     * @dev Emits a {BoolAttributeUpdated} event.
     * @param setter Address of the account that presigned the attribute change
     * @param collection Address of the collection receiving the attribute
     * @param tokenId The ID of the token receiving the attribute
     * @param key The attribute key
     * @param value The attribute value
     * @param deadline The deadline timestamp for the presigned transaction
     * @param v `v` value of an ECDSA signature of the presigned message
     * @param r `r` value of an ECDSA signature of the presigned message
     * @param s `s` value of an ECDSA signature of the presigned message
     */
    function presignedSetBoolAttribute(
        address setter,
        address collection,
        uint256 tokenId,
        string memory key,
        bool value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @notice Used to set the bytes attribute on behalf of an authorized account.
     * @dev Emits a {BytesAttributeUpdated} event.
     * @param setter Address of the account that presigned the attribute change
     * @param collection Address of the collection receiving the attribute
     * @param tokenId The ID of the token receiving the attribute
     * @param key The attribute key
     * @param value The attribute value
     * @param deadline The deadline timestamp for the presigned transaction
     * @param v `v` value of an ECDSA signature of the presigned message
     * @param r `r` value of an ECDSA signature of the presigned message
     * @param s `s` value of an ECDSA signature of the presigned message
     */
    function presignedSetBytesAttribute(
        address setter,
        address collection,
        uint256 tokenId,
        string memory key,
        bytes memory value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @notice Used to set the int attribute on behalf of an authorized account.
     * @dev Emits a {IntAttributeUpdated} event.
     * @param setter Address of the account that presigned the attribute change
     * @param collection Address of the collection receiving the attribute
     * @param tokenId The ID of the token receiving the attribute
     * @param key The attribute key
     * @param value The attribute value
     * @param deadline The deadline timestamp for the presigned transaction
     * @param v `v` value of an ECDSA signature of the presigned message
     * @param r `r` value of an ECDSA signature of the presigned message
     * @param s `s` value of an ECDSA signature of the presigned message
     */
    function presignedSetIntAttribute(
        address setter,
        address collection,
        uint256 tokenId,
        string memory key,
        int256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @notice Used to set the string attribute on behalf of an authorized account.
     * @dev Emits a {StringAttributeUpdated} event.
     * @param setter Address of the account that presigned the attribute change
     * @param collection Address of the collection receiving the attribute
     * @param tokenId The ID of the token receiving the attribute
     * @param key The attribute key
     * @param value The attribute value
     * @param deadline The deadline timestamp for the presigned transaction
     * @param v `v` value of an ECDSA signature of the presigned message
     * @param r `r` value of an ECDSA signature of the presigned message
     * @param s `s` value of an ECDSA signature of the presigned message
     */
    function presignedSetStringAttribute(
        address setter,
        address collection,
        uint256 tokenId,
        string memory key,
        string memory value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @notice Used to set the uint attribute on behalf of an authorized account.
     * @dev Emits a {UintAttributeUpdated} event.
     * @param setter Address of the account that presigned the attribute change
     * @param collection Address of the collection receiving the attribute
     * @param tokenId The ID of the token receiving the attribute
     * @param key The attribute key
     * @param value The attribute value
     * @param deadline The deadline timestamp for the presigned transaction
     * @param v `v` value of an ECDSA signature of the presigned message
     * @param r `r` value of an ECDSA signature of the presigned message
     * @param s `s` value of an ECDSA signature of the presigned message
     */
    function presignedSetUintAttribute(
        address setter,
        address collection,
        uint256 tokenId,
        string memory key,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}
