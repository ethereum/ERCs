// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title  ARD Onchain Registry — kernel interface
/// @notice A record binds an ARD entry (its descriptor hash and canonical URN) to an onchain
///         anchor and, through the kind adapter, to the address that controls the anchor.
///         Authority belongs to addresses; a domain is an endorsement that an address collects by
///         claiming it here and being acknowledged in the domain's own ARD manifest. Controllers
///         are never stored: every authority check asks the kind adapter at call time.
interface IARDOnchainRegistry {
    // ------------------------------------------------------------------ types

    enum Status {
        None,       // no record
        Active,
        Suspended,  // controller-paused; reversible
        Retired     // terminal
    }

    struct Record {
        bytes32 kind;            // keccak256("ard-onchain.kind.<name>")
        address target;          // token contract, subject address, or registry operator
        uint256 id;              // token id; 0 for an agent anchor; nonzero discriminator for a registry anchor
        bytes32 descriptorHash;  // SHA-256 over the JCS (RFC 8785) form of the authored descriptor
        string  descriptorURI;   // where the authored descriptor can be fetched; never a trust source
        string  urn;             // canonical URN supplied by the controller; may be empty
        Status  status;
        address attestor;        // the controller that committed the current descriptor (register / updateDescriptor)
        uint64  updatedAt;
    }

    // ----------------------------------------------------------------- errors

    error NotOwner();
    error ZeroAddress();
    error KindExists(bytes32 kind);
    error UnknownKind(bytes32 kind);
    error AdapterKindMismatch(bytes32 expected, bytes32 reported);
    error AnchorMissing();
    error NotController();
    error EmptyDescriptor();
    error AlreadyRegistered(bytes32 recordId);
    error UnknownRecord(bytes32 recordId);
    error RecordRetired(bytes32 recordId);
    error InvalidTransition(Status from, Status to);
    error InvalidDomain();
    error AlreadyClaimed();
    error NotClaimed();
    error TooManyClaims();
    error SignatureExpired(uint256 deadline);
    error BadNonce(uint256 expected, uint256 given);
    error InvalidSignature();

    // ----------------------------------------------------------------- events

    event Registered(
        bytes32 indexed recordId,
        bytes32 indexed kind,
        address indexed target,
        uint256 id,
        address attestor,
        bytes32 descriptorHash,
        string descriptorURI,
        string urn
    );
    event DescriptorUpdated(bytes32 indexed recordId, bytes32 descriptorHash, string descriptorURI, string urn);
    event StatusChanged(bytes32 indexed recordId, Status status);
    event DomainClaimed(bytes32 indexed domainHash, address indexed controller, string domain);
    event DomainReleased(bytes32 indexed domainHash, address indexed controller);
    event KindRegistered(bytes32 indexed kind, address adapter, string uri);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ---------------------------------------------------------------- records

    /// @notice Register a value record for an anchor. Reverts unless the kind has an adapter,
    ///         the adapter reports the anchor as existing, and msg.sender is its controller.
    ///         recordId = keccak256(abi.encode(block.chainid, target, id)); one record per anchor.
    function register(
        bytes32 kind,
        address target,
        uint256 id,
        bytes32 descriptorHash,
        string calldata descriptorURI,
        string calldata urn
    ) external returns (bytes32 recordId);

    /// @notice Replace the descriptor commitment. Current controller only; not after Retired. Records
    ///         msg.sender as the attestor, so a controller that acquired the anchor adopts the served
    ///         descriptor by committing it again (the same hash is allowed). A record whose attestor is not
    ///         its current controller is unadopted: resolvers do not serve it in discovery.
    function updateDescriptor(bytes32 recordId, bytes32 descriptorHash, string calldata descriptorURI, string calldata urn)
        external;

    /// @notice Active <-> Suspended, either -> Retired. Retired is terminal. Current controller only.
    function setStatus(bytes32 recordId, Status status) external;

    // ---------------------------------------------------------- domain claims

    /// @notice msg.sender claims control of `domain` (lowercase, no trailing dot, punycode).
    function claimDomain(string calldata domain) external;

    /// @notice Same claim authorised by an EIP-712 signature of `controller`; ERC-1271 for contracts.
    function claimDomainBySig(
        string calldata domain,
        address controller,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /// @notice msg.sender withdraws its claim of `domain`.
    function releaseDomain(string calldata domain) external;

    // ------------------------------------------------------------------ kinds

    /// @notice Bind a kind to its adapter. Write-once per kind; instance owner only.
    function registerKind(bytes32 kind, address adapter, string calldata uri) external;

    function transferOwnership(address newOwner) external;

    // ------------------------------------------------------------------ views

    function owner() external view returns (address);
    function recordIdOf(address target, uint256 id) external view returns (bytes32);
    function recordOf(bytes32 recordId) external view returns (Record memory);
    /// @dev Forwarded to the kind adapter; never cached. address(0) when the anchor no longer exists.
    function controllerOf(bytes32 recordId) external view returns (address);
    /// @dev Forwarded to the kind adapter: the L2 test.
    function backed(bytes32 recordId) external view returns (bool);
    /// @dev Forwarded to the kind adapter: provenance cross-check value, 0 when the kind has none.
    function anchorHintOf(bytes32 recordId) external view returns (bytes32);
    function claimsOf(bytes32 domainHash) external view returns (address[] memory);
    function hasClaim(bytes32 domainHash, address controller) external view returns (bool);
    function domainHashOf(string calldata domain) external pure returns (bytes32);
    function kindAdapter(bytes32 kind) external view returns (address);
    function nonces(address controller) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /// @dev ERC-165.
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
