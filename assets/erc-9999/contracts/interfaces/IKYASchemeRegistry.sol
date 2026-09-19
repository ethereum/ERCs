// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IKYATypes} from "./IKYATypes.sol";

/// @title ERC-KYA Scheme Registry
/// @notice Registers KYA Schemes — versioned, addressable descriptions of a KYA principle.
///         The registry stores WHERE a principle lives and HOW assertions under it are admitted;
///         it never interprets the principle itself.
interface IKYASchemeRegistry is IKYATypes {
    event SchemeRegistered(
        bytes32 indexed schemeId,
        address indexed controller,
        uint8 mode,
        address verifier,
        string schemeURI,
        bytes32 schemeHash,
        bytes32 predecessor
    );
    event SchemeUpdated(bytes32 indexed schemeId, string schemeURI, bytes32 schemeHash, address verifier);
    event SchemeFrozen(bytes32 indexed schemeId);
    event SchemeControllerTransferred(bytes32 indexed schemeId, address indexed from, address indexed to);

    /// @notice Register a new scheme. schemeId = keccak256(abi.encode(msg.sender, schemeHash, nonce)).
    /// @param schemeURI   URI of the Scheme Descriptor JSON.
    /// @param schemeHash  keccak256 of the descriptor bytes (MAY be 0x0 for content-addressed URIs).
    /// @param mode        SchemeMode (0 = ATTESTED, 1 = PROVED).
    /// @param verifier    IKYAVerifier address; MUST be non-zero iff mode == PROVED.
    /// @param predecessor Previous version's schemeId (same controller) or 0x0.
    function registerScheme(
        string calldata schemeURI,
        bytes32 schemeHash,
        uint8 mode,
        address verifier,
        bytes32 predecessor
    ) external returns (bytes32 schemeId);

    /// @notice Update an unfrozen scheme's descriptor pointer and/or verifier. Controller only.
    function updateScheme(bytes32 schemeId, string calldata schemeURI, bytes32 schemeHash, address verifier) external;

    /// @notice Irreversibly freeze a scheme. Controller only.
    function freezeScheme(bytes32 schemeId) external;

    /// @notice Transfer control of a scheme. Controller only.
    function transferSchemeController(bytes32 schemeId, address newController) external;

    function getScheme(bytes32 schemeId) external view returns (Scheme memory);
    function schemeExists(bytes32 schemeId) external view returns (bool);
    function schemeNonce(address controller) external view returns (uint256);
}
