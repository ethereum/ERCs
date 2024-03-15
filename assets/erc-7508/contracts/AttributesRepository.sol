// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.21;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC7508} from "./IERC7508.sol";

/**
 * @title ERC-7508 Public On-Chain NFT Attributes Repository
 * @author Steven Pineda, Jan Turk
 * @notice Implementation smart contract of the ERC-7508 Public On-Chain NFT Attributes Repository
 */
contract AttributesRepository is IERC7508, Context {
    bytes32 public immutable DOMAIN_SEPARATOR =
        keccak256(
            abi.encode(
                "ERC-7508: Public On-Chain NFT Attributes Repository",
                "1",
                block.chainid,
                address(this)
            )
        );
    bytes32 public immutable SET_UINT_ATTRIBUTE_TYPEHASH =
        keccak256(
            "setUintAttribute(address collection,uint256 tokenId,string memory key,uint256 value)"
        );
    bytes32 public immutable SET_INT_ATTRIBUTE_TYPEHASH =
        keccak256(
            "setUintAttribute(address collection,uint256 tokenId,string memory key,int256 value)"
        );
    bytes32 public immutable SET_STRING_ATTRIBUTE_TYPEHASH =
        keccak256(
            "setStringAttribute(address collection,uint256 tokenId,string memory key,string memory value)"
        );
    bytes32 public immutable SET_BOOL_ATTRIBUTE_TYPEHASH =
        keccak256(
            "setBoolAttribute(address collection,uint256 tokenId,string memory key,bool value)"
        );
    bytes32 public immutable SET_BYTES_ATTRIBUTE_TYPEHASH =
        keccak256(
            "setBytesAttribute(address collection,uint256 tokenId,string memory key,bytes memory value)"
        );
    bytes32 public immutable SET_ADDRESS_ATTRIBUTE_TYPEHASH =
        keccak256(
            "setAddressAttribute(address collection,uint256 tokenId,string memory key,address value)"
        );

    mapping(address collection => mapping(uint256 parameterId => AccessType accessType))
        private _parameterAccessType;
    mapping(address collection => mapping(uint256 parameterId => address specificAddress))
        private _parameterSpecificAddress;
    mapping(address collection => IssuerSetting setting)
        private _issuerSettings;
    mapping(address collection => mapping(address collaborator => bool isCollaborator))
        private _collaborators;

    // For keys, we use a mapping from strings to IDs.
    // The purpose is to store unique string keys only once, since they are more expensive.
    mapping(string key => uint256 id) private _keysToIds;
    uint256 private _nextKeyId;

    mapping(address collection => string attributesMetadataURI)
        private _attributesMetadataURIs;
    mapping(address collection => mapping(uint256 => mapping(uint256 => address)))
        private _addressValues;
    mapping(address collection => mapping(uint256 => mapping(uint256 => bytes)))
        private _bytesValues;
    mapping(address collection => mapping(uint256 => mapping(uint256 => uint256)))
        private _uintValues;
    mapping(address collection => mapping(uint256 => mapping(uint256 => int256)))
        private _intValues;
    mapping(address collection => mapping(uint256 => mapping(uint256 => bool)))
        private _boolValues;
    mapping(address collection => mapping(uint256 => mapping(uint256 => string)))
        private _stringValues;

    struct IssuerSetting {
        bool registered;
        bool useOwnable;
        address issuer;
    }

    /// Used to signal that the length of the arrays is not equal.
    error LengthsMismatch();
    /// Used to signal that the smart contract interacting with the repository does not implement Ownable pattern.
    error OwnableNotImplemented();
    /// Used to signal that the caller is not the issuer of the collection.
    error NotCollectionIssuer();
    /// Used to signal that the collaborator and collaborator rights array are not of equal length.
    error CollaboratorArraysNotEqualLength();
    /// Used to signal that the collection is not registered in the repository yet.
    error CollectionNotRegistered();
    /// Used to signal that the caller is not aa collaborator of the collection.
    error NotCollectionCollaborator();
    /// Used to signal that the caller is not the issuer or a collaborator of the collection.
    error NotCollectionIssuerOrCollaborator();
    /// Used to signal that the caller is not the owner of the token.
    error NotTokenOwner();
    /// Used to signal that the caller is not the specific address allowed to manage the attribute.
    error NotSpecificAddress();
    /// Used to signal that the presigned message's signature is invalid.
    error InvalidSignature();
    /// Used to signal that the presigned message's deadline has expired.
    error ExpiredDeadline();

    /**
     * @inheritdoc IERC7508
     */
    function registerAccessControl(
        address collection,
        address issuer,
        bool useOwnable
    ) external {
        (bool ownableSuccess, bytes memory ownableReturn) = collection.call(
            abi.encodeWithSignature("owner()")
        );

        if (address(uint160(uint256(bytes32(ownableReturn)))) == address(0)) {
            revert OwnableNotImplemented();
        }
        if (
            ownableSuccess &&
            address(uint160(uint256(bytes32(ownableReturn)))) != _msgSender()
        ) {
            revert NotCollectionIssuer();
        }

        _issuerSettings[collection] = IssuerSetting({
            registered: true,
            issuer: issuer,
            useOwnable: useOwnable
        });

        emit AccessControlRegistration(
            collection,
            issuer,
            _msgSender(),
            useOwnable
        );
    }

    /**
     * @inheritdoc IERC7508
     */
    function manageAccessControl(
        address collection,
        string memory key,
        AccessType accessType,
        address specificAddress
    ) external onlyRegisteredCollection(collection) onlyIssuer(collection) {
        uint256 parameterId = _getIdForKey(key);

        _parameterAccessType[collection][parameterId] = accessType;
        _parameterSpecificAddress[collection][parameterId] = specificAddress;

        emit AccessControlUpdate(collection, key, accessType, specificAddress);
    }

    /**
     * @inheritdoc IERC7508
     */
    function manageCollaborators(
        address collection,
        address[] memory collaboratorAddresses,
        bool[] memory collaboratorAddressAccess
    ) external onlyRegisteredCollection(collection) onlyIssuer(collection) {
        uint256 length = collaboratorAddresses.length;
        if (length != collaboratorAddressAccess.length) {
            revert CollaboratorArraysNotEqualLength();
        }
        for (uint256 i; i < length; ) {
            _collaborators[collection][
                collaboratorAddresses[i]
            ] = collaboratorAddressAccess[i];
            emit CollaboratorUpdate(
                collection,
                collaboratorAddresses[i],
                collaboratorAddressAccess[i]
            );
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IERC7508
     */
    function getAttributesMetadataURI(
        address collection
    ) external view returns (string memory attributesMetadataURI) {
        attributesMetadataURI = _attributesMetadataURIs[collection];
    }

    /**
     * @inheritdoc IERC7508
     */
    function setAttributesMetadataURI(
        address collection,
        string memory attributesMetadataURI
    ) external onlyIssuer(collection) {
        _attributesMetadataURIs[collection] = attributesMetadataURI;
        emit MetadataURIUpdated(collection, attributesMetadataURI);
    }

    /**
     * @inheritdoc IERC7508
     */
    function isCollaborator(
        address collaborator,
        address collection
    ) external view returns (bool isCollaborator_) {
        isCollaborator_ = _collaborators[collection][collaborator];
    }

    /**
     * @inheritdoc IERC7508
     */
    function isSpecificAddress(
        address specificAddress,
        address collection,
        string memory key
    ) external view returns (bool isSpecificAddress_) {
        isSpecificAddress_ =
            _parameterSpecificAddress[collection][_keysToIds[key]] ==
            specificAddress;
    }

    /**
     * @notice Modifier to check if the caller is authorized to call the function.
     * @dev If the authorization is set to TokenOwner and the tokenId provided is of the non-existent token, the
     *  execution will revert with `ERC721InvalidTokenId` rather than `NotTokenOwner`.
     * @dev The tokenId parameter is only needed for the TokenOwner authorization type, other authorization types ignore
     *  it.
     * @param collection The address of the collection.
     * @param key Key of the attribute.
     * @param tokenId The ID of the token.
     */
    modifier onlyAuthorizedCaller(
        address collection,
        string memory key,
        uint256 tokenId
    ) {
        _onlyAuthorizedCaller(_msgSender(), collection, key, tokenId);
        _;
    }

    /**
     * @notice Modifier to check if the collection is registered.
     * @param collection Address of the collection.
     */
    modifier onlyRegisteredCollection(address collection) {
        if (!_issuerSettings[collection].registered) {
            revert CollectionNotRegistered();
        }
        _;
    }

    /**
     * @notice Modifier to check if the caller is the issuer of the collection.
     * @param collection Address of the collection.
     */
    modifier onlyIssuer(address collection) {
        if (_issuerSettings[collection].useOwnable) {
            if (Ownable(collection).owner() != _msgSender()) {
                revert NotCollectionIssuer();
            }
        } else if (_issuerSettings[collection].issuer != _msgSender()) {
            revert NotCollectionIssuer();
        }
        _;
    }

    /**
     * @notice Function to check if the caller is authorized to mamage a given parameter.
     * @param collection The address of the collection.
     * @param key Key of the attribute.
     * @param tokenId The ID of the token.
     */
    function _onlyAuthorizedCaller(
        address caller,
        address collection,
        string memory key,
        uint256 tokenId
    ) private view {
        AccessType accessType = _parameterAccessType[collection][
            _keysToIds[key]
        ];

        if (
            accessType == AccessType.Issuer &&
            ((_issuerSettings[collection].useOwnable &&
                Ownable(collection).owner() != caller) ||
                (!_issuerSettings[collection].useOwnable &&
                    _issuerSettings[collection].issuer != caller))
        ) {
            revert NotCollectionIssuer();
        } else if (
            accessType == AccessType.Collaborator &&
            !_collaborators[collection][caller]
        ) {
            revert NotCollectionCollaborator();
        } else if (
            accessType == AccessType.IssuerOrCollaborator &&
            ((_issuerSettings[collection].useOwnable &&
                Ownable(collection).owner() != caller) ||
                (!_issuerSettings[collection].useOwnable &&
                    _issuerSettings[collection].issuer != caller)) &&
            !_collaborators[collection][caller]
        ) {
            revert NotCollectionIssuerOrCollaborator();
        } else if (
            accessType == AccessType.TokenOwner &&
            IERC721(collection).ownerOf(tokenId) != caller
        ) {
            revert NotTokenOwner();
        } else if (
            accessType == AccessType.SpecificAddress &&
            !(_parameterSpecificAddress[collection][_keysToIds[key]] == caller)
        ) {
            revert NotSpecificAddress();
        }
    }

    /**
     * @inheritdoc IERC7508
     */
    function getStringAttribute(
        address collection,
        uint256 tokenId,
        string memory key
    ) public view returns (string memory attribute) {
        attribute = _stringValues[collection][tokenId][_keysToIds[key]];
    }

    /**
     * @inheritdoc IERC7508
     */
    function getUintAttribute(
        address collection,
        uint256 tokenId,
        string memory key
    ) public view returns (uint256 attribute) {
        attribute = _uintValues[collection][tokenId][_keysToIds[key]];
    }

    /**
     * @inheritdoc IERC7508
     */
    function getIntAttribute(
        address collection,
        uint256 tokenId,
        string memory key
    ) public view returns (int256 attribute) {
        attribute = _intValues[collection][tokenId][_keysToIds[key]];
    }

    /**
     * @inheritdoc IERC7508
     */
    function getBoolAttribute(
        address collection,
        uint256 tokenId,
        string memory key
    ) public view returns (bool attribute) {
        attribute = _boolValues[collection][tokenId][_keysToIds[key]];
    }

    /**
     * @inheritdoc IERC7508
     */
    function getAddressAttribute(
        address collection,
        uint256 tokenId,
        string memory key
    ) public view returns (address attribute) {
        attribute = _addressValues[collection][tokenId][_keysToIds[key]];
    }

    /**
     * @inheritdoc IERC7508
     */
    function getBytesAttribute(
        address collection,
        uint256 tokenId,
        string memory key
    ) public view returns (bytes memory attribute) {
        attribute = _bytesValues[collection][tokenId][_keysToIds[key]];
    }

    /**
     * @inheritdoc IERC7508
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
        )
    {
        uint256 length = stringKeys.length;
        stringAttributes = new string[](length);
        for (uint256 i; i < length; ) {
            stringAttributes[i] = getStringAttribute(
                collection,
                tokenId,
                stringKeys[i]
            );
            unchecked {
                ++i;
            }
        }

        length = uintKeys.length;
        uintAttributes = new uint256[](uintKeys.length);
        for (uint256 i; i < length; ) {
            uintAttributes[i] = getUintAttribute(
                collection,
                tokenId,
                uintKeys[i]
            );
            unchecked {
                ++i;
            }
        }

        length = intKeys.length;
        intAttributes = new int256[](intKeys.length);
        for (uint256 i; i < length; ) {
            intAttributes[i] = getIntAttribute(collection, tokenId, intKeys[i]);
            unchecked {
                ++i;
            }
        }

        length = boolKeys.length;
        boolAttributes = new bool[](boolKeys.length);
        for (uint256 i; i < length; ) {
            boolAttributes[i] = getBoolAttribute(
                collection,
                tokenId,
                boolKeys[i]
            );
            unchecked {
                ++i;
            }
        }

        length = addressKeys.length;
        addressAttributes = new address[](addressKeys.length);
        for (uint256 i; i < length; ) {
            addressAttributes[i] = getAddressAttribute(
                collection,
                tokenId,
                addressKeys[i]
            );
            unchecked {
                ++i;
            }
        }

        length = bytesKeys.length;
        bytesAttributes = new bytes[](bytesKeys.length);
        for (uint256 i; i < length; ) {
            bytesAttributes[i] = getBytesAttribute(
                collection,
                tokenId,
                bytesKeys[i]
            );
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IERC7508
     */
    function getStringAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        string[] memory attributeKeys
    ) public view returns (string[] memory attributes) {
        (
            bool multipleCollections,
            bool multipleTokens,
            bool multipleAttributes,
            uint256 loopLength
        ) = _checkIfMultipleCollectionsAndTokens(
                collections,
                tokenIds,
                attributeKeys.length
            );

        attributes = new string[](loopLength);

        for (uint256 i; i < loopLength; ) {
            attributes[i] = getStringAttribute(
                multipleCollections ? collections[i] : collections[0],
                multipleTokens ? tokenIds[i] : tokenIds[0],
                multipleAttributes ? attributeKeys[i] : attributeKeys[0]
            );
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IERC7508
     */
    function getUintAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        string[] memory attributeKeys
    ) public view returns (uint256[] memory attributes) {
        (
            bool multipleCollections,
            bool multipleTokens,
            bool multipleAttributes,
            uint256 loopLength
        ) = _checkIfMultipleCollectionsAndTokens(
                collections,
                tokenIds,
                attributeKeys.length
            );

        attributes = new uint256[](loopLength);

        for (uint256 i; i < loopLength; ) {
            attributes[i] = getUintAttribute(
                multipleCollections ? collections[i] : collections[0],
                multipleTokens ? tokenIds[i] : tokenIds[0],
                multipleAttributes ? attributeKeys[i] : attributeKeys[0]
            );
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IERC7508
     */
    function getIntAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        string[] memory attributeKeys
    ) public view returns (int256[] memory attributes) {
        (
            bool multipleCollections,
            bool multipleTokens,
            bool multipleAttributes,
            uint256 loopLength
        ) = _checkIfMultipleCollectionsAndTokens(
                collections,
                tokenIds,
                attributeKeys.length
            );

        attributes = new int256[](loopLength);

        for (uint256 i; i < loopLength; ) {
            attributes[i] = getIntAttribute(
                multipleCollections ? collections[i] : collections[0],
                multipleTokens ? tokenIds[i] : tokenIds[0],
                multipleAttributes ? attributeKeys[i] : attributeKeys[0]
            );
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IERC7508
     */
    function getBoolAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        string[] memory attributeKeys
    ) public view returns (bool[] memory attributes) {
        (
            bool multipleCollections,
            bool multipleTokens,
            bool multipleAttributes,
            uint256 loopLength
        ) = _checkIfMultipleCollectionsAndTokens(
                collections,
                tokenIds,
                attributeKeys.length
            );

        attributes = new bool[](loopLength);

        for (uint256 i; i < loopLength; ) {
            attributes[i] = getBoolAttribute(
                multipleCollections ? collections[i] : collections[0],
                multipleTokens ? tokenIds[i] : tokenIds[0],
                multipleAttributes ? attributeKeys[i] : attributeKeys[0]
            );
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IERC7508
     */
    function getAddressAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        string[] memory attributeKeys
    ) public view returns (address[] memory attributes) {
        (
            bool multipleCollections,
            bool multipleTokens,
            bool multipleAttributes,
            uint256 loopLength
        ) = _checkIfMultipleCollectionsAndTokens(
                collections,
                tokenIds,
                attributeKeys.length
            );

        attributes = new address[](loopLength);

        for (uint256 i; i < loopLength; ) {
            attributes[i] = getAddressAttribute(
                multipleCollections ? collections[i] : collections[0],
                multipleTokens ? tokenIds[i] : tokenIds[0],
                multipleAttributes ? attributeKeys[i] : attributeKeys[0]
            );
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IERC7508
     */
    function getBytesAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        string[] memory attributeKeys
    ) public view returns (bytes[] memory attributes) {
        (
            bool multipleCollections,
            bool multipleTokens,
            bool multipleAttributes,
            uint256 loopLength
        ) = _checkIfMultipleCollectionsAndTokens(
                collections,
                tokenIds,
                attributeKeys.length
            );

        attributes = new bytes[](loopLength);

        for (uint256 i; i < loopLength; ) {
            attributes[i] = getBytesAttribute(
                multipleCollections ? collections[i] : collections[0],
                multipleTokens ? tokenIds[i] : tokenIds[0],
                multipleAttributes ? attributeKeys[i] : attributeKeys[0]
            );
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IERC7508
     */
    function prepareMessageToPresignUintAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        uint256 value,
        uint256 deadline
    ) public view returns (bytes32 message) {
        message = keccak256(
            abi.encode(
                DOMAIN_SEPARATOR,
                SET_UINT_ATTRIBUTE_TYPEHASH,
                collection,
                tokenId,
                key,
                value,
                deadline
            )
        );
    }

    /**
     * @inheritdoc IERC7508
     */
    function prepareMessageToPresignIntAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        int256 value,
        uint256 deadline
    ) public view returns (bytes32 message) {
        message = keccak256(
            abi.encode(
                DOMAIN_SEPARATOR,
                SET_UINT_ATTRIBUTE_TYPEHASH,
                collection,
                tokenId,
                key,
                value,
                deadline
            )
        );
    }

    /**
     * @inheritdoc IERC7508
     */
    function prepareMessageToPresignStringAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        string memory value,
        uint256 deadline
    ) public view returns (bytes32 message) {
        message = keccak256(
            abi.encode(
                DOMAIN_SEPARATOR,
                SET_STRING_ATTRIBUTE_TYPEHASH,
                collection,
                tokenId,
                key,
                value,
                deadline
            )
        );
    }

    /**
     * @inheritdoc IERC7508
     */
    function prepareMessageToPresignBoolAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        bool value,
        uint256 deadline
    ) public view returns (bytes32 message) {
        message = keccak256(
            abi.encode(
                DOMAIN_SEPARATOR,
                SET_BOOL_ATTRIBUTE_TYPEHASH,
                collection,
                tokenId,
                key,
                value,
                deadline
            )
        );
    }

    /**
     * @inheritdoc IERC7508
     */
    function prepareMessageToPresignBytesAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        bytes memory value,
        uint256 deadline
    ) public view returns (bytes32 message) {
        message = keccak256(
            abi.encode(
                DOMAIN_SEPARATOR,
                SET_BYTES_ATTRIBUTE_TYPEHASH,
                collection,
                tokenId,
                key,
                value,
                deadline
            )
        );
    }

    /**
     * @inheritdoc IERC7508
     */
    function prepareMessageToPresignAddressAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        address value,
        uint256 deadline
    ) public view returns (bytes32 message) {
        message = keccak256(
            abi.encode(
                DOMAIN_SEPARATOR,
                SET_ADDRESS_ATTRIBUTE_TYPEHASH,
                collection,
                tokenId,
                key,
                value,
                deadline
            )
        );
    }

    /**
     * @inheritdoc IERC7508
     */
    function setBoolAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        bool value
    ) external {
        _setBoolAttribute(_msgSender(), collection, tokenId, key, value);
    }

    /**
     * @inheritdoc IERC7508
     */
    function setBytesAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        bytes memory value
    ) external {
        _setBytesAttribute(_msgSender(), collection, tokenId, key, value);
    }

    /**
     * @inheritdoc IERC7508
     */
    function setAddressAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        address value
    ) external {
        _setAddressAttribute(_msgSender(), collection, tokenId, key, value);
    }

    /**
     * @inheritdoc IERC7508
     */
    function setUintAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        uint256 value
    ) external {
        _setUintAttribute(_msgSender(), collection, tokenId, key, value);
    }

    /**
     * @inheritdoc IERC7508
     */
    function setIntAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        int256 value
    ) external {
        _setIntAttribute(_msgSender(), collection, tokenId, key, value);
    }

    /**
     * @inheritdoc IERC7508
     */
    function setStringAttribute(
        address collection,
        uint256 tokenId,
        string memory key,
        string memory value
    ) external {
        _setStringAttribute(_msgSender(), collection, tokenId, key, value);
    }

    /**
     * @inheritdoc IERC7508
     */
    function setBoolAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        BoolAttribute[] memory attributes
    ) external {
        (
            bool multipleCollections,
            bool multipleTokens,
            bool multipleAttributes,
            uint256 loopLength
        ) = _checkIfMultipleCollectionsAndTokens(
                collections,
                tokenIds,
                attributes.length
            );
        for (uint256 i; i < loopLength; ) {
            BoolAttribute memory attribute = multipleAttributes
                ? attributes[i]
                : attributes[0];
            _setBoolAttribute(
                _msgSender(),
                multipleCollections ? collections[i] : collections[0],
                multipleTokens ? tokenIds[i] : tokenIds[0],
                attribute.key,
                attribute.value
            );
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IERC7508
     */
    function setBytesAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        BytesAttribute[] memory attributes
    ) external {
        (
            bool multipleCollections,
            bool multipleTokens,
            bool multipleAttributes,
            uint256 loopLength
        ) = _checkIfMultipleCollectionsAndTokens(
                collections,
                tokenIds,
                attributes.length
            );
        for (uint256 i; i < loopLength; ) {
            BytesAttribute memory attribute = multipleAttributes
                ? attributes[i]
                : attributes[0];
            _setBytesAttribute(
                _msgSender(),
                multipleCollections ? collections[i] : collections[0],
                multipleTokens ? tokenIds[i] : tokenIds[0],
                attribute.key,
                attribute.value
            );
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IERC7508
     */
    function setStringAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        StringAttribute[] memory attributes
    ) external {
        (
            bool multipleCollections,
            bool multipleTokens,
            bool multipleAttributes,
            uint256 loopLength
        ) = _checkIfMultipleCollectionsAndTokens(
                collections,
                tokenIds,
                attributes.length
            );
        for (uint256 i; i < loopLength; ) {
            StringAttribute memory attribute = multipleAttributes
                ? attributes[i]
                : attributes[0];
            _setStringAttribute(
                _msgSender(),
                multipleCollections ? collections[i] : collections[0],
                multipleTokens ? tokenIds[i] : tokenIds[0],
                attribute.key,
                attribute.value
            );
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IERC7508
     */
    function setUintAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        UintAttribute[] memory attributes
    ) external {
        (
            bool multipleCollections,
            bool multipleTokens,
            bool multipleAttributes,
            uint256 loopLength
        ) = _checkIfMultipleCollectionsAndTokens(
                collections,
                tokenIds,
                attributes.length
            );
        for (uint256 i; i < loopLength; ) {
            UintAttribute memory attribute = multipleAttributes
                ? attributes[i]
                : attributes[0];
            _setUintAttribute(
                _msgSender(),
                multipleCollections ? collections[i] : collections[0],
                multipleTokens ? tokenIds[i] : tokenIds[0],
                attribute.key,
                attribute.value
            );
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IERC7508
     */
    function setIntAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        IntAttribute[] memory attributes
    ) external {
        (
            bool multipleCollections,
            bool multipleTokens,
            bool multipleAttributes,
            uint256 loopLength
        ) = _checkIfMultipleCollectionsAndTokens(
                collections,
                tokenIds,
                attributes.length
            );
        for (uint256 i; i < loopLength; ) {
            IntAttribute memory attribute = multipleAttributes
                ? attributes[i]
                : attributes[0];
            _setIntAttribute(
                _msgSender(),
                multipleCollections ? collections[i] : collections[0],
                multipleTokens ? tokenIds[i] : tokenIds[0],
                attribute.key,
                attribute.value
            );
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IERC7508
     */
    function setAddressAttributes(
        address[] memory collections,
        uint256[] memory tokenIds,
        AddressAttribute[] memory attributes
    ) external {
        (
            bool multipleCollections,
            bool multipleTokens,
            bool multipleAttributes,
            uint256 loopLength
        ) = _checkIfMultipleCollectionsAndTokens(
                collections,
                tokenIds,
                attributes.length
            );
        for (uint256 i; i < loopLength; ) {
            AddressAttribute memory attribute = multipleAttributes
                ? attributes[i]
                : attributes[0];
            _setAddressAttribute(
                _msgSender(),
                multipleCollections ? collections[i] : collections[0],
                multipleTokens ? tokenIds[i] : tokenIds[0],
                attribute.key,
                attribute.value
            );
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IERC7508
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
    ) external {
        uint256 length = stringAttributes.length;
        for (uint256 i; i < length; ) {
            _setStringAttribute(
                _msgSender(),
                collection,
                tokenId,
                stringAttributes[i].key,
                stringAttributes[i].value
            );
            unchecked {
                ++i;
            }
        }

        length = uintAttributes.length;
        for (uint256 i; i < length; ) {
            _setUintAttribute(
                _msgSender(),
                collection,
                tokenId,
                uintAttributes[i].key,
                uintAttributes[i].value
            );
            unchecked {
                ++i;
            }
        }

        length = intAttributes.length;
        for (uint256 i; i < length; ) {
            _setIntAttribute(
                _msgSender(),
                collection,
                tokenId,
                intAttributes[i].key,
                intAttributes[i].value
            );
            unchecked {
                ++i;
            }
        }

        length = boolAttributes.length;
        for (uint256 i; i < length; ) {
            _setBoolAttribute(
                _msgSender(),
                collection,
                tokenId,
                boolAttributes[i].key,
                boolAttributes[i].value
            );
            unchecked {
                ++i;
            }
        }

        length = addressAttributes.length;
        for (uint256 i; i < length; ) {
            _setAddressAttribute(
                _msgSender(),
                collection,
                tokenId,
                addressAttributes[i].key,
                addressAttributes[i].value
            );
            unchecked {
                ++i;
            }
        }

        length = bytesAttributes.length;
        for (uint256 i; i < length; ) {
            _setBytesAttribute(
                _msgSender(),
                collection,
                tokenId,
                bytesAttributes[i].key,
                bytesAttributes[i].value
            );
            unchecked {
                ++i;
            }
        }
    }

    function _checkIfMultipleCollectionsAndTokens(
        address[] memory collections,
        uint256[] memory tokenIds,
        uint256 attributesLength
    )
        internal
        pure
        returns (
            bool multipleCollections,
            bool multipleTokens,
            bool multipleAttributes,
            uint256 loopLength
        )
    {
        multipleCollections = collections.length != 1;
        multipleTokens = tokenIds.length != 1;
        multipleAttributes = attributesLength != 1;
        if (
            (multipleCollections &&
                multipleAttributes &&
                collections.length != attributesLength) ||
            (multipleTokens &&
                multipleAttributes &&
                tokenIds.length != attributesLength) ||
            (multipleCollections &&
                multipleTokens &&
                collections.length != tokenIds.length)
        ) {
            revert LengthsMismatch();
        }

        if (multipleCollections) {
            loopLength = collections.length;
        } else if (multipleTokens) {
            loopLength = tokenIds.length;
        } else {
            loopLength = attributesLength;
        }
    }

    function _setBoolAttribute(
        address caller,
        address collection,
        uint256 tokenId,
        string memory key,
        bool value
    ) internal {
        _onlyAuthorizedCaller(caller, collection, key, tokenId);
        _boolValues[collection][tokenId][_getIdForKey(key)] = value;
        emit BoolAttributeUpdated(collection, tokenId, key, value);
    }

    function _setBytesAttribute(
        address caller,
        address collection,
        uint256 tokenId,
        string memory key,
        bytes memory value
    ) internal {
        _onlyAuthorizedCaller(caller, collection, key, tokenId);
        _bytesValues[collection][tokenId][_getIdForKey(key)] = value;
        emit BytesAttributeUpdated(collection, tokenId, key, value);
    }

    function _setAddressAttribute(
        address caller,
        address collection,
        uint256 tokenId,
        string memory key,
        address value
    ) internal {
        _onlyAuthorizedCaller(caller, collection, key, tokenId);
        _addressValues[collection][tokenId][_getIdForKey(key)] = value;
        emit AddressAttributeUpdated(collection, tokenId, key, value);
    }

    function _setStringAttribute(
        address caller,
        address collection,
        uint256 tokenId,
        string memory key,
        string memory value
    ) internal {
        _onlyAuthorizedCaller(caller, collection, key, tokenId);
        _stringValues[collection][tokenId][_getIdForKey(key)] = value;
        emit StringAttributeUpdated(collection, tokenId, key, value);
    }

    function _setUintAttribute(
        address caller,
        address collection,
        uint256 tokenId,
        string memory key,
        uint256 value
    ) internal {
        _onlyAuthorizedCaller(caller, collection, key, tokenId);
        _uintValues[collection][tokenId][_getIdForKey(key)] = value;
        emit UintAttributeUpdated(collection, tokenId, key, value);
    }

    function _setIntAttribute(
        address caller,
        address collection,
        uint256 tokenId,
        string memory key,
        int256 value
    ) internal {
        _onlyAuthorizedCaller(caller, collection, key, tokenId);
        _intValues[collection][tokenId][_getIdForKey(key)] = value;
        emit IntAttributeUpdated(collection, tokenId, key, value);
    }

    /**
     * @inheritdoc IERC7508
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
    ) external {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(
                    abi.encode(
                        DOMAIN_SEPARATOR,
                        SET_UINT_ATTRIBUTE_TYPEHASH,
                        collection,
                        tokenId,
                        key,
                        value,
                        deadline
                    )
                )
            )
        );
        _checkDeadlineAndSigner(setter, deadline, digest, v, r, s);
        _setUintAttribute(setter, collection, tokenId, key, value);
    }

    /**
     * @inheritdoc IERC7508
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
    ) external {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(
                    abi.encode(
                        DOMAIN_SEPARATOR,
                        SET_UINT_ATTRIBUTE_TYPEHASH,
                        collection,
                        tokenId,
                        key,
                        value,
                        deadline
                    )
                )
            )
        );
        _checkDeadlineAndSigner(setter, deadline, digest, v, r, s);
        _setIntAttribute(setter, collection, tokenId, key, value);
    }

    /**
     * @inheritdoc IERC7508
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
    ) external {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(
                    abi.encode(
                        DOMAIN_SEPARATOR,
                        SET_STRING_ATTRIBUTE_TYPEHASH,
                        collection,
                        tokenId,
                        key,
                        value,
                        deadline
                    )
                )
            )
        );
        _checkDeadlineAndSigner(setter, deadline, digest, v, r, s);
        _setStringAttribute(setter, collection, tokenId, key, value);
    }

    /**
     * @inheritdoc IERC7508
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
    ) external {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(
                    abi.encode(
                        DOMAIN_SEPARATOR,
                        SET_BOOL_ATTRIBUTE_TYPEHASH,
                        collection,
                        tokenId,
                        key,
                        value,
                        deadline
                    )
                )
            )
        );
        _checkDeadlineAndSigner(setter, deadline, digest, v, r, s);
        _setBoolAttribute(setter, collection, tokenId, key, value);
    }

    /**
     * @inheritdoc IERC7508
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
    ) external {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(
                    abi.encode(
                        DOMAIN_SEPARATOR,
                        SET_BYTES_ATTRIBUTE_TYPEHASH,
                        collection,
                        tokenId,
                        key,
                        value,
                        deadline
                    )
                )
            )
        );
        _checkDeadlineAndSigner(setter, deadline, digest, v, r, s);
        _setBytesAttribute(setter, collection, tokenId, key, value);
    }

    /**
     * @inheritdoc IERC7508
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
    ) external {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(
                    abi.encode(
                        DOMAIN_SEPARATOR,
                        SET_ADDRESS_ATTRIBUTE_TYPEHASH,
                        collection,
                        tokenId,
                        key,
                        value,
                        deadline
                    )
                )
            )
        );
        _checkDeadlineAndSigner(setter, deadline, digest, v, r, s);
        _setAddressAttribute(setter, collection, tokenId, key, value);
    }

    function _checkDeadlineAndSigner(
        address setter,
        uint256 deadline,
        bytes32 digest,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal view {
        if (block.timestamp > deadline) {
            revert ExpiredDeadline();
        }
        address signer = ecrecover(digest, v, r, s);
        if (signer != setter) {
            revert InvalidSignature();
        }
    }

    /**
     * @notice Used to get the Id for a key. If the key does not exist, a new ID is created.
     *  IDs are shared among all tokens and types
     * @dev The ID of 0 is not used as it represents the default value.
     * @param key The attribute key
     * @return keyID The ID of the key
     */
    function _getIdForKey(string memory key) internal returns (uint256 keyID) {
        if (_keysToIds[key] == 0) {
            _nextKeyId++;
            _keysToIds[key] = _nextKeyId;
            keyID = _nextKeyId;
        } else {
            keyID = _keysToIds[key];
        }
    }

    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual returns (bool) {
        return
            interfaceId == type(IERC7508).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }
}
