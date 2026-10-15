// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IARDOnchainRegistry} from "./interfaces/IARDOnchainRegistry.sol";
import {IARDKindAdapter} from "./interfaces/IARDKindAdapter.sol";
import {IERC165} from "./interfaces/IERC165.sol";
import {SignatureChecker} from "./libraries/SignatureChecker.sol";

/// @title  ARD Onchain Registry — reference kernel
/// @notice Thin by design: the kernel stores a record's kind, anchor, descriptor commitment, canonical
///         URN and status, plus domain claims and the kind table. Prices, escrow, credit and identity
///         state live in the anchored contracts and are only ever referenced. Not upgradeable.
contract ARDOnchainRegistry is IARDOnchainRegistry {
    // ------------------------------------------------------------------ EIP-712

    string public constant NAME = "ARD Onchain Registry";
    string public constant VERSION = "1";
    bytes32 private constant _EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant DOMAIN_CLAIM_TYPEHASH =
        keccak256("DomainClaim(string domain,address controller,uint256 nonce,uint256 deadline)");

    uint256 public constant MAX_CLAIMS_PER_DOMAIN = 64;
    uint256 public constant MAX_DOMAIN_LENGTH = 253;

    // ------------------------------------------------------------------ storage

    address private _owner;
    mapping(bytes32 => address) private _adapters;                       // kind => adapter
    mapping(bytes32 => Record) private _records;                         // recordId => record
    mapping(bytes32 => address[]) private _claims;                       // domainHash => claimants
    mapping(bytes32 => mapping(address => uint256)) private _claimIndex; // domainHash => claimant => index + 1
    mapping(address => uint256) private _nonces;

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert NotOwner();
        _;
    }

    // ------------------------------------------------------------------ records

    function register(
        bytes32 kind,
        address target,
        uint256 id,
        bytes32 descriptorHash,
        string calldata descriptorURI,
        string calldata urn
    ) external override returns (bytes32 recordId) {
        address adapter = _adapters[kind];
        if (adapter == address(0)) revert UnknownKind(kind);
        if (descriptorHash == bytes32(0)) revert EmptyDescriptor();
        if (!IARDKindAdapter(adapter).exists(target, id)) revert AnchorMissing();
        if (IARDKindAdapter(adapter).controllerOf(target, id) != msg.sender) revert NotController();

        recordId = recordIdOf(target, id);
        if (_records[recordId].status != Status.None) revert AlreadyRegistered(recordId);

        _records[recordId] = Record({
            kind: kind,
            target: target,
            id: id,
            descriptorHash: descriptorHash,
            descriptorURI: descriptorURI,
            urn: urn,
            status: Status.Active,
            registrant: msg.sender,
            updatedAt: uint64(block.timestamp)
        });
        emit Registered(recordId, kind, target, id, msg.sender, descriptorHash, descriptorURI, urn);
    }

    function updateDescriptor(bytes32 recordId, bytes32 descriptorHash, string calldata descriptorURI, string calldata urn)
        external
        override
    {
        Record storage r = _requireController(recordId);
        if (descriptorHash == bytes32(0)) revert EmptyDescriptor();
        r.descriptorHash = descriptorHash;
        r.descriptorURI = descriptorURI;
        r.urn = urn;
        r.updatedAt = uint64(block.timestamp);
        emit DescriptorUpdated(recordId, descriptorHash, descriptorURI, urn);
    }

    function setStatus(bytes32 recordId, Status status) external override {
        Record storage r = _requireController(recordId);
        Status from = r.status;
        bool ok = (from == Status.Active && (status == Status.Suspended || status == Status.Retired))
            || (from == Status.Suspended && (status == Status.Active || status == Status.Retired));
        if (!ok) revert InvalidTransition(from, status);
        r.status = status;
        r.updatedAt = uint64(block.timestamp);
        emit StatusChanged(recordId, status);
    }

    /// @dev Record must exist and not be retired; msg.sender must be the adapter-derived controller now.
    function _requireController(bytes32 recordId) internal view returns (Record storage r) {
        r = _records[recordId];
        if (r.status == Status.None) revert UnknownRecord(recordId);
        if (r.status == Status.Retired) revert RecordRetired(recordId);
        address c = IARDKindAdapter(_adapters[r.kind]).controllerOf(r.target, r.id);
        if (c == address(0) || c != msg.sender) revert NotController();
    }

    // ------------------------------------------------------------ domain claims

    function claimDomain(string calldata domain) external override {
        _validateDomain(bytes(domain));
        _claim(keccak256(bytes(domain)), msg.sender, domain);
    }

    function claimDomainBySig(
        string calldata domain,
        address controller,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external override {
        _validateDomain(bytes(domain));
        if (block.timestamp > deadline) revert SignatureExpired(deadline);
        if (nonce != _nonces[controller]) revert BadNonce(_nonces[controller], nonce);
        bytes32 structHash =
            keccak256(abi.encode(DOMAIN_CLAIM_TYPEHASH, keccak256(bytes(domain)), controller, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
        if (!SignatureChecker.isValid(controller, digest, signature)) revert InvalidSignature();
        _nonces[controller] = nonce + 1;
        _claim(keccak256(bytes(domain)), controller, domain);
    }

    function releaseDomain(string calldata domain) external override {
        bytes32 h = keccak256(bytes(domain));
        uint256 idx = _claimIndex[h][msg.sender];
        if (idx == 0) revert NotClaimed();
        address[] storage list = _claims[h];
        uint256 last = list.length - 1;
        if (idx - 1 != last) {
            address moved = list[last];
            list[idx - 1] = moved;
            _claimIndex[h][moved] = idx;
        }
        list.pop();
        delete _claimIndex[h][msg.sender];
        emit DomainReleased(h, msg.sender);
    }

    function _claim(bytes32 h, address controller, string calldata domain) internal {
        if (_claimIndex[h][controller] != 0) revert AlreadyClaimed();
        address[] storage list = _claims[h];
        if (list.length >= MAX_CLAIMS_PER_DOMAIN) revert TooManyClaims();
        list.push(controller);
        _claimIndex[h][controller] = list.length;
        emit DomainClaimed(h, controller, domain);
    }

    /// @dev Normalized form only: lowercase ASCII letters, digits, '-' and '.', 1..253 bytes,
    ///      no leading or trailing '.', no empty label. IDNA/punycode is the caller's duty.
    function _validateDomain(bytes memory d) internal pure {
        uint256 n = d.length;
        if (n == 0 || n > MAX_DOMAIN_LENGTH) revert InvalidDomain();
        if (d[0] == "." || d[n - 1] == ".") revert InvalidDomain();
        for (uint256 i = 0; i < n; i++) {
            bytes1 c = d[i];
            bool ok = (c >= "a" && c <= "z") || (c >= "0" && c <= "9") || c == "-" || c == ".";
            if (!ok) revert InvalidDomain();
            if (c == "." && d[i - 1] == ".") revert InvalidDomain();
        }
    }

    // ------------------------------------------------------------------ kinds

    function registerKind(bytes32 kind, address adapter, string calldata uri) external override onlyOwner {
        if (adapter == address(0)) revert ZeroAddress();
        if (_adapters[kind] != address(0)) revert KindExists(kind);
        bytes32 reported = IARDKindAdapter(adapter).kind();
        if (reported != kind) revert AdapterKindMismatch(kind, reported);
        _adapters[kind] = adapter;
        emit KindRegistered(kind, adapter, uri);
    }

    /// @dev address(0) renounces: the kind table becomes final.
    function transferOwnership(address newOwner) external override onlyOwner {
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ------------------------------------------------------------------ views

    function owner() external view override returns (address) {
        return _owner;
    }

    function recordIdOf(address target, uint256 id) public view override returns (bytes32) {
        return keccak256(abi.encode(block.chainid, target, id));
    }

    function recordOf(bytes32 recordId) external view override returns (Record memory) {
        return _records[recordId];
    }

    function controllerOf(bytes32 recordId) external view override returns (address) {
        Record storage r = _records[recordId];
        if (r.status == Status.None) revert UnknownRecord(recordId);
        return IARDKindAdapter(_adapters[r.kind]).controllerOf(r.target, r.id);
    }

    function backed(bytes32 recordId) external view override returns (bool) {
        Record storage r = _records[recordId];
        if (r.status == Status.None) revert UnknownRecord(recordId);
        return IARDKindAdapter(_adapters[r.kind]).backed(r.target, r.id);
    }

    function anchorHintOf(bytes32 recordId) external view override returns (bytes32) {
        Record storage r = _records[recordId];
        if (r.status == Status.None) revert UnknownRecord(recordId);
        return IARDKindAdapter(_adapters[r.kind]).anchorHint(r.target, r.id);
    }

    function claimsOf(bytes32 domainHash) external view override returns (address[] memory) {
        return _claims[domainHash];
    }

    function hasClaim(bytes32 domainHash, address controller) external view override returns (bool) {
        return _claimIndex[domainHash][controller] != 0;
    }

    function domainHashOf(string calldata domain) external pure override returns (bytes32) {
        return keccak256(bytes(domain));
    }

    function kindAdapter(bytes32 kind) external view override returns (address) {
        return _adapters[kind];
    }

    function nonces(address controller) external view override returns (uint256) {
        return _nonces[controller];
    }

    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        return keccak256(
            abi.encode(_EIP712_DOMAIN_TYPEHASH, keccak256(bytes(NAME)), keccak256(bytes(VERSION)), block.chainid, address(this))
        );
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IARDOnchainRegistry).interfaceId;
    }
}
