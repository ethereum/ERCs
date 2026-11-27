// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IKYASchemeRegistry} from "./interfaces/IKYASchemeRegistry.sol";
import {IERC165} from "./interfaces/IERC165.sol";

/// @title KYASchemeRegistry — reference implementation
/// @notice Permissionless. Anyone may register a scheme; only its controller may re-point its URI,
///         freeze it or hand it over. Semantics (hash, mode, verifier, predecessor) never change.
contract KYASchemeRegistry is IKYASchemeRegistry, IERC165 {
    mapping(bytes32 => Scheme) private _schemes;
    mapping(bytes32 => bool) private _exists;
    mapping(address => uint256) private _nonces;

    modifier onlyController(bytes32 schemeId) {
        if (!_exists[schemeId]) revert KYA_SchemeNotFound(schemeId);
        if (_schemes[schemeId].controller != msg.sender) revert KYA_NotController(schemeId, msg.sender);
        _;
    }

    function registerScheme(SchemeInput calldata input) external returns (bytes32 schemeId) {
        if (input.mode > uint8(SchemeMode.PROVED)) revert KYA_InvalidMode(input.mode);
        if (input.binding > uint8(BindingKind.INSTANCE)) revert KYA_InvalidBinding(input.binding);
        if (input.resultKind > uint8(ResultKind.OPAQUE)) revert KYA_InvalidResultKind(input.resultKind);
        if (input.schemeHash == bytes32(0)) revert KYA_SchemeHashRequired();
        _checkLevelMask(input.resultKind, input.levelMask);
        address verifier = input.verifier;
        bytes32 codehash;
        if (input.mode == uint8(SchemeMode.PROVED)) {
            if (verifier == address(0)) revert KYA_VerifierRequired();
            if (verifier.code.length == 0) revert KYA_VerifierNotContract(verifier);
            codehash = verifier.codehash;
        } else {
            verifier = address(0);
        }
        if (input.predecessor != bytes32(0)) {
            if (!_exists[input.predecessor] || _schemes[input.predecessor].controller != msg.sender) {
                revert KYA_BadPredecessor(input.predecessor);
            }
        }

        uint256 nonce = _nonces[msg.sender]++;
        schemeId = keccak256(abi.encode(block.chainid, address(this), msg.sender, input.schemeHash, nonce));
        Scheme storage s = _schemes[schemeId];
        s.controller = msg.sender;
        s.schemeURI = input.schemeURI;
        s.schemeHash = input.schemeHash;
        s.mode = input.mode;
        s.binding = input.binding;
        s.resultKind = input.resultKind;
        s.levelMask = input.levelMask;
        s.verifier = verifier;
        s.verifierCodehash = codehash;
        s.predecessor = input.predecessor;
        _exists[schemeId] = true;
        _emitRegistered(schemeId, s);
    }

    /// @dev The result domain is committed per result kind (Section 3.1).
    function _checkLevelMask(uint8 resultKind, uint256 levelMask) internal pure {
        if (resultKind == uint8(ResultKind.ORDERED_LEVEL)) {
            // level 0 ("not verified / failed") MUST be declared, and at least one positive level
            if (levelMask & 1 == 0 || levelMask < 2) revert KYA_InvalidLevelMask(resultKind, levelMask);
        } else if (resultKind == uint8(ResultKind.CATEGORICAL)) {
            if (levelMask == 0) revert KYA_InvalidLevelMask(resultKind, levelMask);
        } else {
            if (levelMask != 1) revert KYA_InvalidLevelMask(resultKind, levelMask);
        }
    }

    function _emitRegistered(bytes32 schemeId, Scheme storage s) internal {
        emit SchemeRegistered(
            schemeId, s.controller, s.mode, s.binding, s.resultKind, s.levelMask, s.verifier, s.verifierCodehash,
            s.schemeURI, s.schemeHash, s.predecessor
        );
    }

    function setSchemeURI(bytes32 schemeId, string calldata schemeURI) external onlyController(schemeId) {
        Scheme storage s = _schemes[schemeId];
        if (s.frozen) revert KYA_Frozen(schemeId);
        s.schemeURI = schemeURI;
        emit SchemeURIUpdated(schemeId, schemeURI);
    }

    function freezeScheme(bytes32 schemeId) external onlyController(schemeId) {
        Scheme storage s = _schemes[schemeId];
        if (s.frozen) revert KYA_Frozen(schemeId);
        s.frozen = true;
        emit SchemeFrozen(schemeId);
    }

    function transferSchemeController(bytes32 schemeId, address newController) external onlyController(schemeId) {
        address from = _schemes[schemeId].controller;
        _schemes[schemeId].controller = newController;
        emit SchemeControllerTransferred(schemeId, from, newController);
    }

    function getScheme(bytes32 schemeId) external view returns (Scheme memory) {
        if (!_exists[schemeId]) revert KYA_SchemeNotFound(schemeId);
        return _schemes[schemeId];
    }

    function schemeExists(bytes32 schemeId) external view returns (bool) {
        return _exists[schemeId];
    }

    function schemeNonce(address controller) external view returns (uint256) {
        return _nonces[controller];
    }

    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        return interfaceId == type(IKYASchemeRegistry).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
