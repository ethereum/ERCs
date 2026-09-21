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

    function registerScheme(
        string calldata schemeURI,
        bytes32 schemeHash,
        uint8 mode,
        uint8 binding,
        address verifier,
        bytes32 predecessor
    ) external returns (bytes32 schemeId) {
        if (mode > uint8(SchemeMode.PROVED)) revert KYA_InvalidMode(mode);
        if (binding > uint8(BindingKind.INSTANCE)) revert KYA_InvalidBinding(binding);
        if (schemeHash == bytes32(0)) revert KYA_SchemeHashRequired();
        bytes32 codehash;
        if (mode == uint8(SchemeMode.PROVED)) {
            if (verifier == address(0)) revert KYA_VerifierRequired();
            if (verifier.code.length == 0) revert KYA_VerifierNotContract(verifier);
            codehash = verifier.codehash;
        } else {
            verifier = address(0);
        }
        if (predecessor != bytes32(0)) {
            if (!_exists[predecessor] || _schemes[predecessor].controller != msg.sender) {
                revert KYA_BadPredecessor(predecessor);
            }
        }

        schemeId = _store(schemeURI, schemeHash, mode, binding, verifier, codehash, predecessor);
    }

    function _store(
        string calldata schemeURI,
        bytes32 schemeHash,
        uint8 mode,
        uint8 binding,
        address verifier,
        bytes32 codehash,
        bytes32 predecessor
    ) internal returns (bytes32 schemeId) {
        uint256 nonce = _nonces[msg.sender]++;
        schemeId = keccak256(abi.encode(block.chainid, address(this), msg.sender, schemeHash, nonce));
        Scheme storage s = _schemes[schemeId];
        s.controller = msg.sender;
        s.schemeURI = schemeURI;
        s.schemeHash = schemeHash;
        s.mode = mode;
        s.binding = binding;
        s.verifier = verifier;
        s.verifierCodehash = codehash;
        s.predecessor = predecessor;
        _exists[schemeId] = true;
        _emitRegistered(schemeId, s, schemeURI);
    }

    function _emitRegistered(bytes32 schemeId, Scheme storage s, string calldata schemeURI) internal {
        emit SchemeRegistered(schemeId, s.controller, s.mode, s.binding, s.verifier, s.verifierCodehash, schemeURI, s.schemeHash, s.predecessor);
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
