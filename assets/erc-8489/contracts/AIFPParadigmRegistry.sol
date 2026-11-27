// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IERC165} from "./interfaces/IERC165.sol";
import {IERC6372} from "./interfaces/IERC6372.sol";
import {IAIFPParadigmRegistry} from "./interfaces/IAIFPParadigmRegistry.sol";
import {AIFPRoles} from "./libraries/AIFPRoles.sol";

/// @title AIFPParadigmRegistry
/// @notice Reference implementation of IAIFPParadigmRegistry. Records content-addressed paradigm versions,
///         their labels and per-role predicate commitments. The descriptor itself is validated off-chain by
///         the canonical validator; the registry checks identity (hash), family control and succession only.
contract AIFPParadigmRegistry is IAIFPParadigmRegistry, IERC165, IERC6372 {
    struct Stored {
        bytes32 family;
        bytes32 supersedes;
        address registrant;
        uint48 registeredAt;
        bool exists;
        string descriptorURI;
        bytes32[] labels;
    }

    mapping(bytes32 => Stored) private _paradigms;
    mapping(bytes32 => mapping(bytes32 => bool)) private _hasLabel;
    mapping(bytes32 => mapping(uint16 => bytes32)) private _rolePredicate;
    mapping(bytes32 => address) private _familyController;

    // ---------------------------------------------------------------- ERC-165 / ERC-6372

    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC6372).interfaceId
            || interfaceId == type(IAIFPParadigmRegistry).interfaceId;
    }

    function clock() public view virtual returns (uint48) {
        return uint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure virtual returns (string memory) {
        return "mode=timestamp";
    }

    // ---------------------------------------------------------------- registration

    function registerParadigm(
        bytes calldata canonicalDescriptor,
        bytes32 family,
        bytes32 supersedes,
        bytes32[] calldata labels,
        RolePredicate[] calldata rolePredicates,
        string calldata descriptorURI
    ) external returns (bytes32 paradigmId) {
        if (canonicalDescriptor.length == 0) revert AIFP_EmptyDescriptor();
        paradigmId = keccak256(canonicalDescriptor);
        if (_paradigms[paradigmId].exists) revert AIFP_ParadigmExists(paradigmId);

        address controller = _familyController[family];
        if (controller == address(0)) {
            _familyController[family] = msg.sender;
            emit FamilyControllerChanged(family, address(0), msg.sender);
        } else if (controller != msg.sender) {
            revert AIFP_NotFamilyController(family, msg.sender);
        }

        if (supersedes != bytes32(0)) {
            Stored storage prev = _paradigms[supersedes];
            if (!prev.exists) revert AIFP_UnknownParadigm(supersedes);
            if (prev.family != family) revert AIFP_SupersedesOutsideFamily(supersedes, family);
        }

        Stored storage s = _paradigms[paradigmId];
        s.family = family;
        s.supersedes = supersedes;
        s.registrant = msg.sender;
        s.registeredAt = clock();
        s.exists = true;
        s.descriptorURI = descriptorURI;
        for (uint256 i = 0; i < labels.length; i++) {
            if (!_hasLabel[paradigmId][labels[i]]) {
                _hasLabel[paradigmId][labels[i]] = true;
                s.labels.push(labels[i]);
            }
        }
        for (uint256 i = 0; i < rolePredicates.length; i++) {
            uint16 role = rolePredicates[i].role;
            if (!AIFPRoles.isSingle(role)) revert AIFP_InvalidRole(role);
            _rolePredicate[paradigmId][role] = rolePredicates[i].predicateHash;
        }

        emit ParadigmRegistered(paradigmId, family, supersedes, msg.sender, descriptorURI);
        emit ParadigmDescriptor(paradigmId, canonicalDescriptor);
    }

    function transferFamily(bytes32 family, address newController) external {
        address controller = _familyController[family];
        if (controller == address(0) || controller != msg.sender) revert AIFP_NotFamilyController(family, msg.sender);
        _familyController[family] = newController;
        emit FamilyControllerChanged(family, controller, newController);
    }

    // ---------------------------------------------------------------- views

    function paradigm(bytes32 paradigmId) external view returns (ParadigmRecord memory) {
        Stored storage s = _paradigms[paradigmId];
        if (!s.exists) revert AIFP_UnknownParadigm(paradigmId);
        return ParadigmRecord({
            family: s.family,
            supersedes: s.supersedes,
            registrant: s.registrant,
            registeredAt: s.registeredAt,
            descriptorURI: s.descriptorURI
        });
    }

    function exists(bytes32 paradigmId) external view returns (bool) {
        return _paradigms[paradigmId].exists;
    }

    function hasLabel(bytes32 paradigmId, bytes32 label) external view returns (bool) {
        return _hasLabel[paradigmId][label];
    }

    function labelsOf(bytes32 paradigmId) external view returns (bytes32[] memory) {
        return _paradigms[paradigmId].labels;
    }

    function rolePredicateHash(bytes32 paradigmId, uint16 role) external view returns (bytes32) {
        return _rolePredicate[paradigmId][role];
    }

    function familyController(bytes32 family) external view returns (address) {
        return _familyController[family];
    }
}
