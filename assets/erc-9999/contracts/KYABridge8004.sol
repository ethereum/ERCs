// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IKYARegistry} from "./interfaces/IKYARegistry.sol";
import {IKYATypes} from "./interfaces/IKYATypes.sol";
import {IERC8004ValidationRegistry} from "./interfaces/IERC8004Validation.sol";

/// @title KYABridge8004 — mirrors KYA conclusions into the ERC-8004 Validation Registry
/// @notice A bridge is a curated ERC-8004 *validator*: its operator decides, per scheme, which KYA
///         issuers it trusts and how scheme levels map onto ERC-8004's 0–100 response scale.
///         The mirrored value is an OPTIONAL, LOSSY SNAPSHOT of the KYA Registry taken at `sync`
///         time: it does not carry expiry, revocation or anchor, and it is only as fresh as the
///         last sync. ERC-8004-only clients that need the authoritative answer query the KYA
///         Registry. Anyone may call `sync` to refresh the snapshot — including after a revocation
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
    error LevelNotMapped(bytes32 schemeId, uint8 level);

    event SchemeConfigured(bytes32 indexed schemeId, bytes32 indexed configHash, address[] trustedIssuers, uint8[] responseMap);
    event Synced(uint256 indexed agentId, bytes32 indexed schemeId, bytes32 indexed requestHash, bytes32 configHash, uint8 level, uint8 response, bytes32 assertionId);
    event OwnerTransferred(address indexed from, address indexed to);

    struct SchemeConfig {
        address[] trustedIssuers;
        uint8[] responseMap; // index = level; a resolved level >= length makes sync revert (never guess upward)
        bytes32 configHash;  // keccak256(abi.encode(schemeId, trustedIssuers, responseMap)) — the interpretation identity
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
        c.configHash = configHashOf(schemeId, trustedIssuers, responseMap);
        c.configured = true;
        // NOTE: reconfiguring changes configHash and therefore requestHashFor(); existing requests filed
        // under the old configuration can no longer be synced — a new interpretation needs a new request.
        emit SchemeConfigured(schemeId, c.configHash, trustedIssuers, responseMap);
    }

    function getSchemeConfig(bytes32 schemeId) external view returns (address[] memory, uint8[] memory, bytes32, bool) {
        SchemeConfig storage c = _configs[schemeId];
        return (c.trustedIssuers, c.responseMap, c.configHash, c.configured);
    }

    /// @notice Interpretation identity of a bridge configuration.
    function configHashOf(bytes32 schemeId, address[] memory trustedIssuers, uint8[] memory responseMap) public pure returns (bytes32) {
        return keccak256(abi.encode(schemeId, trustedIssuers, responseMap));
    }

    // ---------------------------------------------------------------- helpers

    /// @notice The requestHash an agent MUST use in `validationRequest` for this (agentId, schemeId) under
    ///         the bridge's CURRENT configuration. Domain-separated by chain, identity registry, this bridge
    ///         and the configuration identity, so neither another bridge nor a reconfigured one shares it.
    function requestHashFor(uint256 agentId, bytes32 schemeId) public view returns (bytes32) {
        SchemeConfig storage c = _configs[schemeId];
        if (!c.configured) revert SchemeNotConfigured(schemeId);
        return keccak256(abi.encode(REQUEST_TYPE, block.chainid, identityRegistry, address(this), c.configHash, agentId, schemeId));
    }

    function subjectFor(uint256 agentId) public view returns (IKYATypes.Subject memory) {
        return IKYATypes.Subject({
            subjectType: SUBJECT_TYPE_ERC8004,
            subjectData: abi.encode(block.chainid, identityRegistry, agentId)
        });
    }

    /// @notice "kya:" + the full schemeId as 64 lowercase hex chars (collision-resistant tag).
    function tagFor(bytes32 schemeId) public pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory out = new bytes(68);
        out[0] = "k"; out[1] = "y"; out[2] = "a"; out[3] = ":";
        for (uint256 i = 0; i < 32; i++) {
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

        if (level >= c.responseMap.length) revert LevelNotMapped(schemeId, level);
        response = c.responseMap[level];

        _respond(requestHash, response, keccak256(abi.encode(assertionId, level, c.configHash)), schemeId);
        emit Synced(agentId, schemeId, requestHash, c.configHash, level, response, assertionId);
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
