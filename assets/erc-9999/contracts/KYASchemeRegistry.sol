// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IKYASchemeRegistry} from "./interfaces/IKYASchemeRegistry.sol";
import {IERC165} from "./interfaces/IERC165.sol";

/// @title KYASchemeRegistry — reference implementation
/// @notice Permissionless. Anyone may register a scheme; only its controller may change or freeze it.
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
        address verifier,
        bytes32 predecessor
    ) external returns (bytes32 schemeId) {
        if (mode > uint8(SchemeMode.PROVED)) revert KYA_InvalidMode(mode);
        if (mode == uint8(SchemeMode.PROVED) && verifier == address(0)) revert KYA_VerifierRequired();
        if (mode == uint8(SchemeMode.ATTESTED)) verifier = address(0);
        if (predecessor != bytes32(0)) {
            if (!_exists[predecessor] || _schemes[predecessor].controller != msg.sender) {
                revert KYA_BadPredecessor(predecessor);
            }
        }

        uint256 nonce = _nonces[msg.sender]++;
        schemeId = keccak256(abi.encode(msg.sender, schemeHash, nonce));

        _schemes[schemeId] = Scheme({
            controller: msg.sender,
            schemeURI: schemeURI,
            schemeHash: schemeHash,
            mode: mode,
            verifier: verifier,
            predecessor: predecessor,
            frozen: false
        });
        _exists[schemeId] = true;

        emit SchemeRegistered(schemeId, msg.sender, mode, verifier, schemeURI, schemeHash, predecessor);
    }

    function updateScheme(bytes32 schemeId, string calldata schemeURI, bytes32 schemeHash, address verifier)
        external
        onlyController(schemeId)
    {
        Scheme storage s = _schemes[schemeId];
        if (s.frozen) revert KYA_Frozen(schemeId);
        if (s.mode == uint8(SchemeMode.PROVED)) {
            if (verifier == address(0)) revert KYA_VerifierRequired();
            s.verifier = verifier;
        }
        s.schemeURI = schemeURI;
        s.schemeHash = schemeHash;
        emit SchemeUpdated(schemeId, schemeURI, schemeHash, s.verifier);
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
