// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.19;

import {IERC7496} from "./interfaces/IERC7496.sol";

library DynamicTraitsStorage {
    struct Layout {
        /// @dev A mapping of token ID to a mapping of trait key to trait value.
        mapping(uint256 tokenId => mapping(bytes32 traitKey => bytes32 traitValue)) _traits;
        /// @dev An offchain string URI that points to a JSON file containing trait metadata.
        string _traitMetadataURI;
        /// @dev A mapping of valid trait keys.
        mapping(bytes32 traitKey => bool isValid) _validTraitKeys;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("contracts.storage.erc7496-dynamictraits");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}

/**
 * @title DynamicTraits
 *
 * @dev Implementation of [ERC-7496](https://eips.ethereum.org/EIPS/eip-7496) Dynamic Traits.
 * Uses a storage layout pattern for upgradeable contracts.
 *
 * Requirements:
 * - Overwrite `setTrait` with access role restriction.
 * - Expose a function for `setTraitMetadataURI` with access role restriction if desired.
 */
contract DynamicTraits is IERC7496 {
    using DynamicTraitsStorage for DynamicTraitsStorage.Layout;

    /// @dev Thrown when trying to get or set a trait that does not exist.
    error TraitDoesNotExist(bytes32 traitKey);

    /**
     * @notice Get the value of a trait for a given token ID.
     * @param tokenId The token ID to get the trait value for
     * @param traitKey The trait key to get the value of
     */
    function getTraitValue(uint256 tokenId, bytes32 traitKey) public view virtual returns (bytes32 traitValue) {
        // Revert if the trait key does not exist.
        DynamicTraitsStorage.Layout storage layout = DynamicTraitsStorage.layout();
        if (!layout._validTraitKeys[traitKey]) {
            revert TraitDoesNotExist(traitKey);
        }

        // Return the trait value.
        return layout._traits[tokenId][traitKey];
    }

    /**
     * @notice Get the values of traits for a given token ID.
     * @param tokenId The token ID to get the trait values for
     * @param traitKeys The trait keys to get the values of
     */
    function getTraitValues(uint256 tokenId, bytes32[] calldata traitKeys)
        public
        view
        virtual
        returns (bytes32[] memory traitValues)
    {
        // Set the length of the traitValues return array.
        uint256 length = traitKeys.length;
        traitValues = new bytes32[](length);

        // Assign each trait value to the corresponding key.
        for (uint256 i = 0; i < length; i++) {
            bytes32 traitKey = traitKeys[i];
            traitValues[i] = getTraitValue(tokenId, traitKey);
        }
    }

    /**
     * @notice Get the URI for the trait metadata
     */
    function getTraitMetadataURI() external view virtual returns (string memory labelsURI) {
        // Return the trait metadata URI.
        return DynamicTraitsStorage.layout()._traitMetadataURI;
    }

    /**
     * @notice Set the value of a trait for a given token ID.
     *         Reverts if the trait value is unchanged.
     * @dev    IMPORTANT: Override this method with access role restriction.
     * @param tokenId The token ID to set the trait value for
     * @param traitKey The trait key to set the value of
     * @param newValue The new trait value to set
     */
    function setTrait(uint256 tokenId, bytes32 traitKey, bytes32 newValue) public virtual {
        DynamicTraitsStorage.Layout storage layout = DynamicTraitsStorage.layout();

        // Revert if the trait key does not exist.
        if (!layout._validTraitKeys[traitKey]) {
            revert TraitDoesNotExist(traitKey);
        }

        // Revert if the new value is the same as the existing value.
        bytes32 existingValue = layout._traits[tokenId][traitKey];
        if (existingValue == newValue) {
            revert TraitValueUnchanged();
        }

        // Set the new trait value.
        _setTrait(tokenId, traitKey, newValue);

        // Emit the event noting the update.
        emit TraitUpdated(traitKey, tokenId, newValue);
    }

    /**
     * @notice Set the trait value (without emitting an event).
     * @param tokenId The token ID to set the trait value for
     * @param traitKey The trait key to set the value of
     * @param newValue The new trait value to set
     */
    function _setTrait(uint256 tokenId, bytes32 traitKey, bytes32 newValue) internal virtual {
        // Set the new trait value.
        DynamicTraitsStorage.layout()._traits[tokenId][traitKey] = newValue;
    }

    /**
     * @notice Set the URI for the trait metadata.
     * @param uri The new URI to set.
     */
    function _setTraitMetadataURI(string memory uri) internal virtual {
        // Set the new trait metadata URI.
        DynamicTraitsStorage.layout()._traitMetadataURI = uri;

        // Emit the event noting the update.
        emit TraitMetadataURIUpdated();
    }

    /**
     * @notice Set the URI for the trait metadata and register trait keys.
     * @param uri The new URI to set.
     * @param traitKeys The trait keys to register as valid.
     */
    function _setTraitMetadataURI(string memory uri, bytes32[] memory traitKeys) internal virtual {
        DynamicTraitsStorage.Layout storage layout = DynamicTraitsStorage.layout();

        // Set the new trait metadata URI.
        layout._traitMetadataURI = uri;

        // Register all trait keys.
        for (uint256 i = 0; i < traitKeys.length; i++) {
            layout._validTraitKeys[traitKeys[i]] = true;
        }

        // Emit the event noting the update.
        emit TraitMetadataURIUpdated();
    }

    /**
     * @notice Register a trait key as valid.
     * @param traitKey The trait key to register.
     */
    function _registerTraitKey(bytes32 traitKey) internal virtual {
        DynamicTraitsStorage.layout()._validTraitKeys[traitKey] = true;
    }

    /**
     * @notice Check if a trait key is registered.
     * @param traitKey The trait key to check.
     */
    function _isTraitKeyRegistered(bytes32 traitKey) internal view virtual returns (bool) {
        return DynamicTraitsStorage.layout()._validTraitKeys[traitKey];
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC7496).interfaceId;
    }
}
