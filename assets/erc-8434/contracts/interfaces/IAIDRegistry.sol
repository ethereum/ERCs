// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title ERC-AID: Agent Identity registry interface
/// @notice Thin on-chain layer for address-anchored agent identity.
///         Everything stored here is anchor-authorised: binding to an ERC-8004 agent,
///         liveness, self-declared document/facet pointers and retirement.
interface IAIDRegistry {
    // ------------------------------------------------------------------
    // Types
    // ------------------------------------------------------------------

    /// @dev On-chain state. Resolvers refine ACTIVE→STALE with off-chain data (registration file `active`).
    enum State {
        DORMANT,
        ACTIVE,
        STALE,
        RETIRED
    }

    /// @dev Access mode of a self-declared facet.
    enum Access {
        PUBLIC,
        GATED,
        ZK
    }

    struct Binding {
        address registry; // ERC-8004 Identity Registry
        uint256 agentId;  // token id in that registry
        uint64 boundAt;   // block.timestamp of bind
    }

    struct Facet {
        bytes32 digest;    // keccak256 of canonical content, or a commitment for ZK facets
        uint64 validFrom;
        uint64 validUntil; // MUST be non-zero and > validFrom
        uint8 access;      // Access enum
        string uri;        // where the (possibly gated) content lives; MAY be empty for ZK
    }

    // ------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------

    error AIDRetired(address anchor);
    error AlreadyBound(address anchor);
    error AgentAlreadyBound(address registry, uint256 agentId, address by);
    error NotBound(address anchor);
    error NotAgentOfAnchor(address anchor, address registry, uint256 agentId);
    error InvalidWindow(uint64 window);
    error InvalidFacet();
    error InvalidAccess(uint8 access);
    error SignatureExpired(uint256 deadline);
    error InvalidSignature();
    error UnknownFacet(bytes32 facetType);

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------

    event Bound(address indexed anchor, address indexed registry, uint256 indexed agentId);
    event Unbound(address indexed anchor, address indexed registry, uint256 indexed agentId);
    event Heartbeat(address indexed anchor, uint64 at);
    event LivenessWindowSet(address indexed anchor, uint64 window);
    event DocumentURISet(address indexed anchor, string uri, bytes32 digest);
    event FacetSet(
        address indexed anchor,
        bytes32 indexed facetType,
        bytes32 digest,
        uint64 validFrom,
        uint64 validUntil,
        uint8 access,
        string uri
    );
    event FacetCleared(address indexed anchor, bytes32 indexed facetType);
    event Retired(address indexed anchor, address successor);

    // ------------------------------------------------------------------
    // Binding (anchor-authorised)
    // ------------------------------------------------------------------

    /// @notice Bind msg.sender (the anchor) to an ERC-8004 agent, one-to-one.
    function bind(address registry, uint256 agentId) external;

    /// @notice Same as bind, authorised by an EIP-712 signature of `anchor` (EIP-1271 for contract anchors).
    function bindWithSig(
        address anchor,
        address registry,
        uint256 agentId,
        uint256 deadline,
        bytes calldata sig
    ) external;

    /// @notice Release the binding of msg.sender. History (events, facets) is retained.
    function unbind() external;

    // ------------------------------------------------------------------
    // Liveness
    // ------------------------------------------------------------------

    function heartbeat() external;

    /// @param window seconds; 0 resets to defaultLivenessWindow(); MUST be <= maxLivenessWindow()
    function setLivenessWindow(uint64 window) external;

    // ------------------------------------------------------------------
    // Self-declared document & facets
    // ------------------------------------------------------------------

    function setDocumentURI(string calldata uri, bytes32 digest) external;

    function setFacet(
        bytes32 facetType,
        bytes32 digest,
        uint64 validFrom,
        uint64 validUntil,
        uint8 access,
        string calldata uri
    ) external;

    function clearFacet(bytes32 facetType) external;

    // ------------------------------------------------------------------
    // Retirement (irreversible)
    // ------------------------------------------------------------------

    /// @notice Retire msg.sender. Releases the binding so a successor may bind the same agent.
    function retire(address successor) external;

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------

    function bindingOf(address anchor) external view returns (Binding memory);
    function anchorOf(address registry, uint256 agentId) external view returns (address);
    function state(address anchor) external view returns (State);
    function lastSeen(address anchor) external view returns (uint64);
    function livenessWindow(address anchor) external view returns (uint64);
    function defaultLivenessWindow() external view returns (uint64);
    function maxLivenessWindow() external view returns (uint64);
    function documentURI(address anchor) external view returns (string memory uri, bytes32 digest);
    function getFacet(address anchor, bytes32 facetType) external view returns (Facet memory);
    function facetTypesOf(address anchor) external view returns (bytes32[] memory);
    function isRetired(address anchor) external view returns (bool);
    function successorOf(address anchor) external view returns (address);
    function nonces(address anchor) external view returns (uint256);
}
