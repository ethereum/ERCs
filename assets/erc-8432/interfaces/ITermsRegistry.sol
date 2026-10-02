// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {LicenseTerms} from "./IPAssetTypes.sol";
import {IERC165} from "./IERC165.sol";

/// @title ITermsRegistry
/// @notice Content-addressed registry of immutable `LicenseTerms` documents.
///
/// License terms in this ERC are identified by their content hash:
///
///     termsId = keccak256(abi.encode(terms))
///
/// `terms` is encoded as one `LicenseTerms` tuple argument. Packed,
/// field-by-field, textual, and implementation-defined encodings are not
/// canonical.
///
/// This interface isolates the local terms-storage role from the broader
/// `IIPAssetRegistry`. Every `IIPAssetRegistry` inherits this interface, and
/// assets and agreements may reference only terms registered in that same
/// registry. Identical terms may be mirrored into another registry and retain
/// the same content-addressed `termsId`.
///
/// Properties:
///
///   * **Content-addressed.** `termsId` is derived from the terms document;
///     anyone registering the same content produces the same id.
///   * **Immutable entries.** A registered `termsId` cannot be overwritten.
///   * **Permissionless deployment.** Multiple deployments may coexist;
///     content addressing guarantees they return equivalent terms for the
///     same id.
interface ITermsRegistry is IERC165 {
    error IncompleteLegalWrapper();

    // =====================================================================
    // License terms
    // =====================================================================

    /// @notice Register a content-addressed `LicenseTerms` document.
    /// @dev    Reverts with `IncompleteLegalWrapper` unless `uri` and
    ///         `contentHash` are either both present or both absent.
    ///         Re-registering an existing id succeeds without state changes
    ///         or events and returns that id.
    /// @param  terms   The canonical terms to register.
    /// @return termsId The content-addressed id
    ///         (`keccak256(abi.encode(terms))`).
    function registerTerms(LicenseTerms calldata terms) external returns (bytes32 termsId);

    /// @notice True iff `termsId` is registered in this registry.
    function termsExists(bytes32 termsId) external view returns (bool);

    /// @notice Resolve a registered `termsId` to its `LicenseTerms`.
    /// @dev    Reverts if `termsId` is unknown.
    function getTerms(bytes32 termsId) external view returns (LicenseTerms memory);
}
