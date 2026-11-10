// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title IAIFPChannelRegistry
/// @notice Registry of channels (interaction contexts). A channel adopts exactly one paradigm version at
///         any timepoint; adoptions are append-only with an explicit effective timepoint; transport,
///         governance and economic bindings are declared with their capabilities and effect scope;
///         disclosure records are append-only facts. All timepoints use the registry's ERC-6372 clock.
interface IAIFPChannelRegistry {
    enum ChannelState {
        Active,
        Frozen,
        Closed
    }

    struct Adoption {
        bytes32 paradigmId;
        uint48 effectiveAt;
        uint48 recordedAt;
        bool requiresReadmission;
        bytes32 authorizationRef; // reference to the evidence authorizing the adoption; confers nothing
    }

    struct BindingDecl {
        uint8 kind;
        bytes32 target; // transport endpoint id, or the governance contract address left-padded
        bytes32 version; // version of the target protocol / policy
        uint32 capabilities; // transport capability bits
        uint32 effectScope; // governance effect bits
        uint8 adoptionMode;
        bytes32 authorizationRef;
        bool active;
    }

    struct ChannelRecord {
        address authority;
        bytes32 parent;
        ChannelState state;
        uint48 openedAt;
        string metadataURI;
    }

    event ChannelOpened(bytes32 indexed channelId, bytes32 indexed paradigmId, address indexed authority, bytes32 parent, string metadataURI);
    // Management events name the caller, on what grounds it was authorized (`authorityKind`: 0 channel
    // authority - or the opener, for the records written by `openChannel` -, 1 governance executor, 2 a holder
    // of the management role) and, for kind 2, the role binding relied on (`authorizingBinding`).
    event ParadigmAdopted(
        bytes32 indexed channelId,
        bytes32 indexed paradigmId,
        uint48 effectiveAt,
        bool requiresReadmission,
        bytes32 authorizationRef,
        uint256 adoptionIndex,
        address by,
        uint8 authorityKind,
        bytes32 authorizingBinding
    );
    event BindingDeclared(
        bytes32 indexed channelId,
        bytes32 indexed bindingId,
        uint8 kind,
        bytes32 target,
        bytes32 version,
        uint32 capabilities,
        uint32 effectScope,
        uint8 adoptionMode,
        bytes32 authorizationRef,
        address by,
        uint8 authorityKind,
        bytes32 authorizingBinding
    );
    event BindingRevoked(bytes32 indexed channelId, bytes32 indexed bindingId, address by, uint8 authorityKind, bytes32 authorizingBinding);
    event DisclosureRecorded(
        bytes32 indexed channelId,
        bytes32 indexed objectRef,
        uint8 kind,
        bytes32 audienceRef,
        bytes32 authorizationRef,
        uint48 at,
        uint256 recordIndex,
        address by,
        uint8 authorityKind,
        bytes32 authorizingBinding
    );
    event ChannelStateChanged(bytes32 indexed channelId, ChannelState state);
    event AuthorityTransferred(bytes32 indexed channelId, address indexed previousAuthority, address indexed newAuthority);

    error AIFP_UnknownChannel(bytes32 channelId);
    error AIFP_ChannelNotActive(bytes32 channelId);
    error AIFP_ChannelClosed(bytes32 channelId);
    error AIFP_NotAuthorized(bytes32 channelId, address caller);
    error AIFP_EffectiveInPast(uint48 effectiveAt, uint48 now_);
    error AIFP_InvalidBinding();

    function openChannel(
        bytes32 paradigmId,
        address authority,
        bytes32 parent,
        string calldata metadataURI,
        BindingDecl[] calldata bindings
    ) external returns (bytes32 channelId);

    function adoptParadigm(
        bytes32 channelId,
        bytes32 paradigmId,
        uint48 effectiveAt,
        bool requiresReadmission,
        bytes32 authorizationRef
    ) external;

    function declareBinding(bytes32 channelId, BindingDecl calldata decl) external returns (bytes32 bindingId);
    function revokeBinding(bytes32 channelId, bytes32 bindingId) external;

    function recordDisclosure(bytes32 channelId, uint8 kind, bytes32 objectRef, bytes32 audienceRef, bytes32 authorizationRef) external;

    function setState(bytes32 channelId, ChannelState state) external;
    function transferAuthority(bytes32 channelId, address newAuthority) external;

    function channel(bytes32 channelId) external view returns (ChannelRecord memory);
    /// @notice `paradigmAt` at the current clock value, with the `effectiveAt` of the adoption in force.
    function currentParadigm(bytes32 channelId) external view returns (bytes32 paradigmId, uint48 effectiveSince);
    /// @notice The paradigm in force at `timepoint`: that of the adoption with the latest effectiveAt not
    ///         after `timepoint`, whatever the order in which adoptions were recorded; among adoptions with
    ///         the same effectiveAt the later-recorded one; 0 before the first adoption.
    function paradigmAt(bytes32 channelId, uint48 timepoint) external view returns (bytes32 paradigmId);
    /// @notice Number of adoptions requiring re-admission with effectiveAt <= timepoint.
    function readmissionEpochAt(bytes32 channelId, uint48 timepoint) external view returns (uint32);
    function adoptionCount(bytes32 channelId) external view returns (uint256);
    function adoptionAt(bytes32 channelId, uint256 index) external view returns (Adoption memory);
    function binding(bytes32 channelId, bytes32 bindingId) external view returns (BindingDecl memory);
    function bindingIds(bytes32 channelId) external view returns (bytes32[] memory);
    /// @notice True when `executor` is the target of an active governance binding with the given effect
    ///         in automatic adoption mode.
    function isGovernanceExecutor(bytes32 channelId, address executor, uint32 effect) external view returns (bool);
    function disclosureCount(bytes32 channelId) external view returns (uint256);
    function disclosureAt(bytes32 channelId, uint256 index) external view returns (uint8 kind, bytes32 objectRef, bytes32 audienceRef, bytes32 authorizationRef, uint48 at);
}
