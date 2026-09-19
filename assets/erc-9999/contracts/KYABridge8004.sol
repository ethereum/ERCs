// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IKYARegistry} from "./interfaces/IKYARegistry.sol";
import {IKYATypes} from "./interfaces/IKYATypes.sol";
import {IERC8004ValidationRegistry} from "./interfaces/IERC8004Validation.sol";

/// @title KYABridge8004 — mirrors KYA conclusions into the ERC-8004 Validation Registry
/// @notice A bridge is a curated ERC-8004 *validator*: its operator decides, per scheme, which KYA
///         issuers it trusts and how scheme levels map onto ERC-8004's 0–100 response scale.
///         Anyone may call `sync` to refresh the mirrored response — including after a revocation
///         or expiry, which drives the response to `responseMap[0]` (normally 0).
///
///         Flow:
///           1. agent owner/operator: validation.validationRequest(bridge, agentId, requestURI, requestHashFor(agentId, schemeId))
///           2. anyone:                bridge.sync(agentId, schemeId)
///           3. ERC-8004-only client:  validation.getSummary(agentId, [bridge], "kya:xxxxxxxx")
contract KYABridge8004 {
    bytes32 public constant REQUEST_TYPE = keccak256("erc-kya-request-v1");
    bytes32 public constant SUBJECT_TYPE_ERC8004 = keccak256("erc8004");

    error NotOwner();
    error SchemeNotConfigured(bytes32 schemeId);
    error RequestNotFound(bytes32 requestHash);
    error RequestNotForBridge(bytes32 requestHash, address validator);
    error BadResponseMap();

    event SchemeConfigured(bytes32 indexed schemeId, address[] trustedIssuers, uint8[] responseMap);
    event Synced(uint256 indexed agentId, bytes32 indexed schemeId, bytes32 indexed requestHash, uint8 level, uint8 response, bytes32 assertionId);
    event OwnerTransferred(address indexed from, address indexed to);

    struct SchemeConfig {
        address[] trustedIssuers;
        uint8[] responseMap; // index = level; levels >= length clamp to last entry
        bool configured;
    }

    IKYARegistry public immutable kyaRegistry;
    IERC8004ValidationRegistry public immutable validationRegistry;
    address public immutable identityRegistry;
    address public owner;

    mapping(bytes32 => SchemeConfig) private _configs;

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address kyaRegistry_, address validationRegistry_, address owner_) {
        kyaRegistry = IKYARegistry(kyaRegistry_);
        validationRegistry = IERC8004ValidationRegistry(validationRegistry_);
        identityRegistry = IERC8004ValidationRegistry(validationRegistry_).getIdentityRegistry();
        owner = owner_;
    }

    // ---------------------------------------------------------------- admin

    function transferOwnership(address newOwner) external onlyOwner {
        emit OwnerTransferred(owner, newOwner);
        owner = newOwner;
    }

    function configureScheme(bytes32 schemeId, address[] calldata trustedIssuers, uint8[] calldata responseMap)
        external
        onlyOwner
    {
        if (trustedIssuers.length == 0) revert IKYATypes.KYA_EmptyIssuers();
        if (responseMap.length == 0) revert BadResponseMap();
        for (uint256 i = 0; i < responseMap.length; i++) {
            if (responseMap[i] > 100) revert BadResponseMap();
        }
        SchemeConfig storage c = _configs[schemeId];
        c.trustedIssuers = trustedIssuers;
        c.responseMap = responseMap;
        c.configured = true;
        emit SchemeConfigured(schemeId, trustedIssuers, responseMap);
    }

    function getSchemeConfig(bytes32 schemeId) external view returns (address[] memory, uint8[] memory, bool) {
        SchemeConfig storage c = _configs[schemeId];
        return (c.trustedIssuers, c.responseMap, c.configured);
    }

    // ---------------------------------------------------------------- helpers

    /// @notice The requestHash an agent MUST use in `validationRequest` for this (agentId, schemeId).
    function requestHashFor(uint256 agentId, bytes32 schemeId) public view returns (bytes32) {
        return keccak256(abi.encode(REQUEST_TYPE, block.chainid, identityRegistry, agentId, schemeId));
    }

    function subjectFor(uint256 agentId) public view returns (IKYATypes.Subject memory) {
        return IKYATypes.Subject({
            subjectType: SUBJECT_TYPE_ERC8004,
            subjectData: abi.encode(block.chainid, identityRegistry, agentId)
        });
    }

    /// @notice "kya:" + first 8 lowercase hex chars of schemeId.
    function tagFor(bytes32 schemeId) public pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory out = new bytes(12);
        out[0] = "k"; out[1] = "y"; out[2] = "a"; out[3] = ":";
        for (uint256 i = 0; i < 4; i++) {
            uint8 b = uint8(schemeId[i]);
            out[4 + 2 * i] = hexChars[b >> 4];
            out[5 + 2 * i] = hexChars[b & 0x0f];
        }
        return string(out);
    }

    // ---------------------------------------------------------------- sync

    function sync(uint256 agentId, bytes32 schemeId) external returns (uint8 response) {
        SchemeConfig storage c = _configs[schemeId];
        if (!c.configured) revert SchemeNotConfigured(schemeId);

        bytes32 requestHash = _checkRequest(agentId, schemeId);
        (uint8 level, bytes32 assertionId) = _resolveLevel(agentId, schemeId, c);

        uint256 idx = level < c.responseMap.length ? level : c.responseMap.length - 1;
        response = c.responseMap[idx];

        _respond(requestHash, response, keccak256(abi.encode(assertionId, level, c.trustedIssuers)), schemeId);
        emit Synced(agentId, schemeId, requestHash, level, response, assertionId);
    }

    function _checkRequest(uint256 agentId, bytes32 schemeId) internal view returns (bytes32 requestHash) {
        requestHash = requestHashFor(agentId, schemeId);
        (address validator, uint256 reqAgentId,,,, uint256 lastUpdate) = validationRegistry.getValidationStatus(requestHash);
        if (validator == address(0) && lastUpdate == 0) revert RequestNotFound(requestHash);
        if (validator != address(this) || reqAgentId != agentId) revert RequestNotForBridge(requestHash, validator);
    }

    function _resolveLevel(uint256 agentId, bytes32 schemeId, SchemeConfig storage c)
        internal
        view
        returns (uint8 level, bytes32 assertionId)
    {
        (level,, assertionId) = kyaRegistry.resolve(subjectFor(agentId), schemeId, c.trustedIssuers);
        if (assertionId == bytes32(0)) level = 0;
    }

    function _respond(bytes32 requestHash, uint8 response, bytes32 responseHash, bytes32 schemeId) internal {
        validationRegistry.validationResponse(requestHash, response, "", responseHash, tagFor(schemeId));
    }
}
