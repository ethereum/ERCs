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
        uint8 binding,
        uint8 resultKind,
        uint256 levelMask,
        address verifier,
        bytes32 verifierCodehash,
        string schemeURI,
        bytes32 schemeHash,
        bytes32 predecessor
    );
    event SchemeURIUpdated(bytes32 indexed schemeId, string schemeURI);
    event SchemeFrozen(bytes32 indexed schemeId);
    event SchemeControllerTransferred(bytes32 indexed schemeId, address indexed from, address indexed to);

    /// @notice Register a new scheme.
    ///         schemeId = keccak256(abi.encode(block.chainid, address(this), msg.sender, schemeHash, nonce)),
    ///         so a schemeId is unique across chains and scheme registries. It names a RULE, not a place of use:
    ///         the KYA Registry that admits a proof under the scheme enters the proof's admission domain
    ///         (IKYAVerifier.verify's admissionDomain), not the scheme identity, so one scheme can be adopted by
    ///         several KYA Registries sharing this catalogue.
    ///         schemeHash, mode, binding, resultKind, levelMask, verifier (address AND code hash) and predecessor
    ///         are immutable. The result domain is part of the scheme's committed semantics (Section 3.1):
    ///           - resultKind ORDERED_LEVEL: levelMask MUST have bit 0 set (level 0 = "not verified / failed")
    ///             and at least one other bit;
    ///           - resultKind CATEGORICAL: levelMask MUST be non-zero;
    ///           - resultKind OPAQUE: levelMask MUST be exactly 1 (level 0 only).
    ///         A KYA Registry refuses any assertion whose level is not in levelMask.
    function registerScheme(SchemeInput calldata input) external returns (bytes32 schemeId);

    /// @notice Re-point an unfrozen scheme's descriptor URI to another copy of the SAME bytes
    ///         (schemeHash is unchanged and MUST still match). Controller only.
    function setSchemeURI(bytes32 schemeId, string calldata schemeURI) external;

    /// @notice Irreversibly freeze a scheme. Controller only.
    function freezeScheme(bytes32 schemeId) external;

    /// @notice Transfer control of a scheme. Controller only.
    function transferSchemeController(bytes32 schemeId, address newController) external;

    function getScheme(bytes32 schemeId) external view returns (Scheme memory);
    function schemeExists(bytes32 schemeId) external view returns (bool);
    function schemeNonce(address controller) external view returns (uint256);
}
