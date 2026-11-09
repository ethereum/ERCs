// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IERC165} from "./interfaces/IERC165.sol";
import {IERC6372} from "./interfaces/IERC6372.sol";
import {IAIFPChannelRegistry} from "./interfaces/IAIFPChannelRegistry.sol";
import {IAIFPParadigmRegistry} from "./interfaces/IAIFPParadigmRegistry.sol";
import {IAIFPParticipationRegistry} from "./interfaces/IAIFPParticipationRegistry.sol";
import {AIFPBindings} from "./libraries/AIFPBindings.sol";
import {AIFPRoles} from "./libraries/AIFPRoles.sol";
import {AIFPOutcomes} from "./libraries/AIFPOutcomes.sol";
import {AIFPSubject} from "./libraries/AIFPSubject.sol";

/// @title AIFPChannelRegistry
/// @notice Reference implementation of IAIFPChannelRegistry. One deployment is one clock domain
///         (ERC-6372, mode=timestamp). Adoptions, bindings and disclosure records are append-only.
contract AIFPChannelRegistry is IAIFPChannelRegistry, IERC165, IERC6372 {
    struct Disclosure {
        uint8 kind;
        bytes32 objectRef;
        bytes32 audienceRef;
        bytes32 authorizationRef;
        uint48 at;
    }

    IAIFPParadigmRegistry public immutable paradigmRegistry;
    address public immutable deployer;
    IAIFPParticipationRegistry public participationRegistry;

    uint256 private _nonce;
    mapping(bytes32 => ChannelRecord) private _channels;
    mapping(bytes32 => bool) private _exists;
    mapping(bytes32 => Adoption[]) private _adoptions;
    mapping(bytes32 => bytes32[]) private _bindingIds;
    mapping(bytes32 => mapping(bytes32 => BindingDecl)) private _bindings;
    mapping(bytes32 => Disclosure[]) private _disclosures;

    error AIFP_AlreadyInitialized();
    error AIFP_NotDeployer();

    constructor(IAIFPParadigmRegistry paradigmRegistry_) {
        paradigmRegistry = paradigmRegistry_;
        deployer = msg.sender;
    }

    /// @notice Links the participation registry once, so that MANAGE_RULES and MANAGE_DISCLOSURE holders
    ///         can act on channels. Until then only the channel authority and governance executors can.
    function setParticipationRegistry(IAIFPParticipationRegistry registry) external {
        if (msg.sender != deployer) revert AIFP_NotDeployer();
        if (address(participationRegistry) != address(0)) revert AIFP_AlreadyInitialized();
        participationRegistry = registry;
    }

    // ---------------------------------------------------------------- ERC-165 / ERC-6372

    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC6372).interfaceId
            || interfaceId == type(IAIFPChannelRegistry).interfaceId;
    }

    function clock() public view virtual returns (uint48) {
        return uint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure virtual returns (string memory) {
        return "mode=timestamp";
    }

    // ---------------------------------------------------------------- channels

    function openChannel(
        bytes32 paradigmId,
        address authority,
        bytes32 parent,
        string calldata metadataURI,
        BindingDecl[] calldata bindings
    ) external returns (bytes32 channelId) {
        if (!paradigmRegistry.exists(paradigmId)) revert IAIFPParadigmRegistry.AIFP_UnknownParadigm(paradigmId);
        if (parent != bytes32(0) && !_exists[parent]) revert AIFP_UnknownChannel(parent);
        channelId = keccak256(abi.encode(address(this), block.chainid, ++_nonce));
        _exists[channelId] = true;
        ChannelRecord storage c = _channels[channelId];
        c.authority = authority;
        c.parent = parent;
        c.state = ChannelState.Active;
        c.openedAt = clock();
        c.metadataURI = metadataURI;
        _adoptions[channelId].push(
            Adoption({
                paradigmId: paradigmId,
                effectiveAt: clock(),
                recordedAt: clock(),
                requiresReadmission: false,
                authorizationRef: bytes32(0)
            })
        );
        emit ChannelOpened(channelId, paradigmId, authority, parent, metadataURI);
        emit ParadigmAdopted(channelId, paradigmId, clock(), false, bytes32(0), 0);
        for (uint256 i = 0; i < bindings.length; i++) {
            _declareBinding(channelId, bindings[i]);
        }
    }

    function adoptParadigm(
        bytes32 channelId,
        bytes32 paradigmId,
        uint48 effectiveAt,
        bool requiresReadmission,
        bytes32 authorizationRef
    ) external {
        _requireActive(channelId);
        if (!_canChangeRules(channelId, msg.sender)) revert AIFP_NotAuthorized(channelId, msg.sender);
        if (!paradigmRegistry.exists(paradigmId)) revert IAIFPParadigmRegistry.AIFP_UnknownParadigm(paradigmId);
        uint48 now_ = clock();
        if (effectiveAt < now_) revert AIFP_EffectiveInPast(effectiveAt, now_);
        Adoption[] storage list = _adoptions[channelId];
        list.push(
            Adoption({
                paradigmId: paradigmId,
                effectiveAt: effectiveAt,
                recordedAt: now_,
                requiresReadmission: requiresReadmission,
                authorizationRef: authorizationRef
            })
        );
        emit ParadigmAdopted(channelId, paradigmId, effectiveAt, requiresReadmission, authorizationRef, list.length - 1);
    }

    function declareBinding(bytes32 channelId, BindingDecl calldata decl) external returns (bytes32 bindingId) {
        _requireActive(channelId);
        if (!_canChangeRules(channelId, msg.sender)) revert AIFP_NotAuthorized(channelId, msg.sender);
        bindingId = _declareBinding(channelId, decl);
    }

    function revokeBinding(bytes32 channelId, bytes32 bindingId) external {
        _requireNotClosed(channelId);
        if (!_canChangeRules(channelId, msg.sender)) revert AIFP_NotAuthorized(channelId, msg.sender);
        BindingDecl storage b = _bindings[channelId][bindingId];
        if (!b.active) revert AIFP_InvalidBinding();
        b.active = false;
        emit BindingRevoked(channelId, bindingId);
    }

    function recordDisclosure(bytes32 channelId, uint8 kind, bytes32 objectRef, bytes32 audienceRef, bytes32 authorizationRef)
        external
    {
        if (!_exists[channelId]) revert AIFP_UnknownChannel(channelId);
        if (kind > AIFPBindings.DISCLOSURE_RESTRICTED) revert AIFP_InvalidBinding();
        if (!_canDisclose(channelId, msg.sender)) revert AIFP_NotAuthorized(channelId, msg.sender);
        uint48 now_ = clock();
        Disclosure[] storage list = _disclosures[channelId];
        list.push(Disclosure({kind: kind, objectRef: objectRef, audienceRef: audienceRef, authorizationRef: authorizationRef, at: now_}));
        emit DisclosureRecorded(channelId, objectRef, kind, audienceRef, authorizationRef, now_, list.length - 1);
    }

    function setState(bytes32 channelId, ChannelState state) external {
        if (!_exists[channelId]) revert AIFP_UnknownChannel(channelId);
        ChannelRecord storage c = _channels[channelId];
        if (msg.sender != c.authority) revert AIFP_NotAuthorized(channelId, msg.sender);
        if (c.state == ChannelState.Closed) revert AIFP_ChannelClosed(channelId);
        c.state = state;
        emit ChannelStateChanged(channelId, state);
    }

    function transferAuthority(bytes32 channelId, address newAuthority) external {
        if (!_exists[channelId]) revert AIFP_UnknownChannel(channelId);
        ChannelRecord storage c = _channels[channelId];
        if (msg.sender != c.authority) revert AIFP_NotAuthorized(channelId, msg.sender);
        emit AuthorityTransferred(channelId, c.authority, newAuthority);
        c.authority = newAuthority;
    }

    // ---------------------------------------------------------------- views

    function channel(bytes32 channelId) external view returns (ChannelRecord memory) {
        if (!_exists[channelId]) revert AIFP_UnknownChannel(channelId);
        return _channels[channelId];
    }

    function currentParadigm(bytes32 channelId) external view returns (bytes32 paradigmId, uint48 effectiveSince) {
        return _paradigmAt(channelId, clock());
    }

    function paradigmAt(bytes32 channelId, uint48 timepoint) external view returns (bytes32 paradigmId) {
        (paradigmId,) = _paradigmAt(channelId, timepoint);
    }

    function readmissionEpochAt(bytes32 channelId, uint48 timepoint) public view returns (uint32 epoch) {
        if (!_exists[channelId]) revert AIFP_UnknownChannel(channelId);
        Adoption[] storage list = _adoptions[channelId];
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i].requiresReadmission && list[i].effectiveAt <= timepoint) epoch++;
        }
    }

    function adoptionCount(bytes32 channelId) external view returns (uint256) {
        return _adoptions[channelId].length;
    }

    function adoptionAt(bytes32 channelId, uint256 index) external view returns (Adoption memory) {
        return _adoptions[channelId][index];
    }

    function binding(bytes32 channelId, bytes32 bindingId) external view returns (BindingDecl memory) {
        return _bindings[channelId][bindingId];
    }

    function bindingIds(bytes32 channelId) external view returns (bytes32[] memory) {
        return _bindingIds[channelId];
    }

    function isGovernanceExecutor(bytes32 channelId, address executor, uint32 effect) public view returns (bool) {
        bytes32[] storage ids = _bindingIds[channelId];
        bytes32 target = AIFPBindings.toTarget(executor);
        for (uint256 i = 0; i < ids.length; i++) {
            BindingDecl storage b = _bindings[channelId][ids[i]];
            if (
                b.active && b.kind != AIFPBindings.KIND_TRANSPORT && b.kind != AIFPBindings.KIND_ECONOMIC
                    && b.adoptionMode == AIFPBindings.ADOPTION_AUTOMATIC && b.target == target && (b.effectScope & effect) == effect
            ) return true;
        }
        return false;
    }

    function disclosureCount(bytes32 channelId) external view returns (uint256) {
        return _disclosures[channelId].length;
    }

    function disclosureAt(bytes32 channelId, uint256 index)
        external
        view
        returns (uint8 kind, bytes32 objectRef, bytes32 audienceRef, bytes32 authorizationRef, uint48 at)
    {
        Disclosure storage d = _disclosures[channelId][index];
        return (d.kind, d.objectRef, d.audienceRef, d.authorizationRef, d.at);
    }

    function channelExists(bytes32 channelId) external view returns (bool) {
        return _exists[channelId];
    }

    // ---------------------------------------------------------------- internals

    function _paradigmAt(bytes32 channelId, uint48 timepoint) internal view returns (bytes32 paradigmId, uint48 effectiveSince) {
        if (!_exists[channelId]) revert AIFP_UnknownChannel(channelId);
        Adoption[] storage list = _adoptions[channelId];
        // Later-recorded adoptions win ties, so scan in order and keep the last match.
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i].effectiveAt <= timepoint) {
                paradigmId = list[i].paradigmId;
                effectiveSince = list[i].effectiveAt;
            }
        }
    }

    function _declareBinding(bytes32 channelId, BindingDecl calldata decl) internal returns (bytes32 bindingId) {
        if (decl.kind > AIFPBindings.MAX_KIND || decl.adoptionMode > AIFPBindings.ADOPTION_CONFIRMED) revert AIFP_InvalidBinding();
        if (decl.kind == AIFPBindings.KIND_TRANSPORT && decl.effectScope != 0) revert AIFP_InvalidBinding();
        bytes32[] storage ids = _bindingIds[channelId];
        bindingId = keccak256(abi.encode(channelId, ids.length, decl.kind, decl.target));
        ids.push(bindingId);
        BindingDecl storage b = _bindings[channelId][bindingId];
        b.kind = decl.kind;
        b.target = decl.target;
        b.version = decl.version;
        b.capabilities = decl.capabilities;
        b.effectScope = decl.effectScope;
        b.adoptionMode = decl.adoptionMode;
        b.authorizationRef = decl.authorizationRef;
        b.active = true;
        emit BindingDeclared(
            channelId, bindingId, decl.kind, decl.target, decl.version, decl.capabilities, decl.effectScope, decl.adoptionMode, decl.authorizationRef
        );
    }

    function _requireActive(bytes32 channelId) internal view {
        if (!_exists[channelId]) revert AIFP_UnknownChannel(channelId);
        if (_channels[channelId].state != ChannelState.Active) revert AIFP_ChannelNotActive(channelId);
    }

    function _requireNotClosed(bytes32 channelId) internal view {
        if (!_exists[channelId]) revert AIFP_UnknownChannel(channelId);
        if (_channels[channelId].state == ChannelState.Closed) revert AIFP_ChannelClosed(channelId);
    }

    function _canChangeRules(bytes32 channelId, address caller) internal view returns (bool) {
        if (caller == _channels[channelId].authority) return true;
        if (isGovernanceExecutor(channelId, caller, AIFPBindings.EFFECT_RULES)) return true;
        return _holdsRole(channelId, caller, AIFPRoles.MANAGE_RULES);
    }

    function _canDisclose(bytes32 channelId, address caller) internal view returns (bool) {
        if (caller == _channels[channelId].authority) return true;
        if (isGovernanceExecutor(channelId, caller, AIFPBindings.EFFECT_DISCLOSURE)) return true;
        return _holdsRole(channelId, caller, AIFPRoles.MANAGE_DISCLOSURE);
    }

    function _holdsRole(bytes32 channelId, address caller, uint16 role) internal view returns (bool) {
        if (address(participationRegistry) == address(0)) return false;
        return participationRegistry.evaluateNow(channelId, AIFPSubject.self(caller), role, bytes32(0)) == AIFPOutcomes.SATISFIED;
    }
}
