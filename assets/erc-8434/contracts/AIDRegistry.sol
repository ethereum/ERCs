// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IAIDRegistry} from "./interfaces/IAIDRegistry.sol";
import {IERC8004Identity} from "./interfaces/IERC8004Identity.sol";

interface IERC1271 {
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4);
}

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/// @title AIDRegistry — reference implementation of ERC-AID (Agent Identity)
/// @notice Ownerless, upgrade-free, one deployment per chain. No governance surface:
///         the only parameters are the two immutable liveness bounds set at deployment.
contract AIDRegistry is IAIDRegistry, IERC165 {
    // ------------------------------------------------------------------
    // Immutable parameters
    // ------------------------------------------------------------------

    uint64 private immutable _defaultWindow;
    uint64 private immutable _maxWindow;

    // ------------------------------------------------------------------
    // EIP-712
    // ------------------------------------------------------------------

    bytes32 private constant _DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _NAME_HASH = keccak256("AIDRegistry");
    bytes32 private constant _VERSION_HASH = keccak256("1");
    bytes32 public constant BIND_TYPEHASH =
        keccak256("Bind(address anchor,address registry,uint256 agentId,uint256 nonce,uint256 deadline)");
    bytes4 private constant _ERC1271_MAGIC = 0x1626ba7e;

    // ------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------

    mapping(address => Binding) private _binding;
    mapping(address => mapping(uint256 => address)) private _anchorOf;
    mapping(address => uint64) private _lastSeen;
    mapping(address => uint64) private _window; // 0 => default
    mapping(address => bool) private _retired;
    mapping(address => address) private _successor;
    mapping(address => string) private _docURI;
    mapping(address => bytes32) private _docDigest;
    mapping(address => mapping(bytes32 => Facet)) private _facet;
    mapping(address => bytes32[]) private _facetTypes;
    mapping(address => mapping(bytes32 => uint256)) private _facetIndex; // index+1, 0 => absent
    mapping(address => uint256) private _nonces;

    constructor(uint64 defaultWindow_, uint64 maxWindow_) {
        require(defaultWindow_ > 0 && defaultWindow_ <= maxWindow_, "AID: bad windows");
        _defaultWindow = defaultWindow_;
        _maxWindow = maxWindow_;
    }

    // ------------------------------------------------------------------
    // Modifiers / internal helpers
    // ------------------------------------------------------------------

    modifier notRetired(address anchor) {
        if (_retired[anchor]) revert AIDRetired(anchor);
        _;
    }

    /// @dev Every anchor-authorised write refreshes liveness.
    function _touch(address anchor) internal {
        _lastSeen[anchor] = uint64(block.timestamp);
        emit Heartbeat(anchor, uint64(block.timestamp));
    }

    /// @dev Binding precondition: anchor is the agent wallet or the owner of the ERC-8004 agent.
    function _isAgentOfAnchor(address anchor, address registry, uint256 agentId) internal view returns (bool ok) {
        if (registry.code.length == 0) return false;
        try IERC8004Identity(registry).ownerOf(agentId) returns (address owner) {
            if (owner == anchor) return true;
        } catch {
            return false;
        }
        try IERC8004Identity(registry).getAgentWallet(agentId) returns (address wallet) {
            return wallet == anchor;
        } catch {
            return false;
        }
    }

    function _bind(address anchor, address registry, uint256 agentId) internal {
        if (_binding[anchor].registry != address(0)) revert AlreadyBound(anchor);
        address by = _anchorOf[registry][agentId];
        if (by != address(0)) revert AgentAlreadyBound(registry, agentId, by);
        if (!_isAgentOfAnchor(anchor, registry, agentId)) revert NotAgentOfAnchor(anchor, registry, agentId);

        _binding[anchor] = Binding({registry: registry, agentId: agentId, boundAt: uint64(block.timestamp)});
        _anchorOf[registry][agentId] = anchor;
        emit Bound(anchor, registry, agentId);
        _touch(anchor);
    }

    function _release(address anchor) internal {
        Binding memory b = _binding[anchor];
        if (b.registry == address(0)) revert NotBound(anchor);
        delete _anchorOf[b.registry][b.agentId];
        delete _binding[anchor];
        emit Unbound(anchor, b.registry, b.agentId);
    }

    // ------------------------------------------------------------------
    // Binding
    // ------------------------------------------------------------------

    function bind(address registry, uint256 agentId) external override notRetired(msg.sender) {
        _bind(msg.sender, registry, agentId);
    }

    function bindWithSig(
        address anchor,
        address registry,
        uint256 agentId,
        uint256 deadline,
        bytes calldata sig
    ) external override notRetired(anchor) {
        if (block.timestamp > deadline) revert SignatureExpired(deadline);
        uint256 nonce = _nonces[anchor]++;
        bytes32 structHash = keccak256(abi.encode(BIND_TYPEHASH, anchor, registry, agentId, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
        if (!_isValidSignature(anchor, digest, sig)) revert InvalidSignature();
        _bind(anchor, registry, agentId);
    }

    function unbind() external override notRetired(msg.sender) {
        _release(msg.sender);
        _touch(msg.sender);
    }

    // ------------------------------------------------------------------
    // Liveness
    // ------------------------------------------------------------------

    function heartbeat() external override notRetired(msg.sender) {
        _touch(msg.sender);
    }

    function setLivenessWindow(uint64 window) external override notRetired(msg.sender) {
        if (window > _maxWindow) revert InvalidWindow(window);
        _window[msg.sender] = window; // 0 resets to default
        emit LivenessWindowSet(msg.sender, window == 0 ? _defaultWindow : window);
        _touch(msg.sender);
    }

    // ------------------------------------------------------------------
    // Document & facets
    // ------------------------------------------------------------------

    function setDocumentURI(string calldata uri, bytes32 digest) external override notRetired(msg.sender) {
        _docURI[msg.sender] = uri;
        _docDigest[msg.sender] = digest;
        emit DocumentURISet(msg.sender, uri, digest);
        _touch(msg.sender);
    }

    function setFacet(
        bytes32 facetType,
        bytes32 digest,
        uint64 validFrom,
        uint64 validUntil,
        uint8 access,
        string calldata uri
    ) external override notRetired(msg.sender) {
        if (validUntil == 0 || validUntil <= validFrom) revert InvalidFacet();
        if (access > uint8(Access.ZK)) revert InvalidAccess(access);
        address anchor = msg.sender;
        if (_facetIndex[anchor][facetType] == 0) {
            _facetTypes[anchor].push(facetType);
            _facetIndex[anchor][facetType] = _facetTypes[anchor].length;
        }
        _facet[anchor][facetType] = Facet({digest: digest, validFrom: validFrom, validUntil: validUntil, access: access, uri: uri});
        emit FacetSet(anchor, facetType, digest, validFrom, validUntil, access, uri);
        _touch(anchor);
    }

    function clearFacet(bytes32 facetType) external override notRetired(msg.sender) {
        address anchor = msg.sender;
        uint256 idx1 = _facetIndex[anchor][facetType];
        if (idx1 == 0) revert UnknownFacet(facetType);
        uint256 last = _facetTypes[anchor].length;
        if (idx1 != last) {
            bytes32 moved = _facetTypes[anchor][last - 1];
            _facetTypes[anchor][idx1 - 1] = moved;
            _facetIndex[anchor][moved] = idx1;
        }
        _facetTypes[anchor].pop();
        delete _facetIndex[anchor][facetType];
        delete _facet[anchor][facetType];
        emit FacetCleared(anchor, facetType);
        _touch(anchor);
    }

    // ------------------------------------------------------------------
    // Retirement
    // ------------------------------------------------------------------

    function retire(address successor) external override notRetired(msg.sender) {
        address anchor = msg.sender;
        if (_binding[anchor].registry != address(0)) _release(anchor);
        _retired[anchor] = true;
        _successor[anchor] = successor;
        _lastSeen[anchor] = uint64(block.timestamp);
        emit Retired(anchor, successor);
    }

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------

    function bindingOf(address anchor) external view override returns (Binding memory) {
        return _binding[anchor];
    }

    function anchorOf(address registry, uint256 agentId) external view override returns (address) {
        return _anchorOf[registry][agentId];
    }

    /// @inheritdoc IAIDRegistry
    function state(address anchor) public view override returns (State) {
        if (_retired[anchor]) return State.RETIRED;
        Binding memory b = _binding[anchor];
        if (b.registry == address(0)) return State.DORMANT;
        if (!_isAgentOfAnchor(anchor, b.registry, b.agentId)) return State.STALE;
        if (uint256(_lastSeen[anchor]) + uint256(livenessWindow(anchor)) < block.timestamp) return State.STALE;
        return State.ACTIVE;
    }

    function lastSeen(address anchor) external view override returns (uint64) {
        return _lastSeen[anchor];
    }

    function livenessWindow(address anchor) public view override returns (uint64) {
        uint64 w = _window[anchor];
        return w == 0 ? _defaultWindow : w;
    }

    function defaultLivenessWindow() external view override returns (uint64) {
        return _defaultWindow;
    }

    function maxLivenessWindow() external view override returns (uint64) {
        return _maxWindow;
    }

    function documentURI(address anchor) external view override returns (string memory uri, bytes32 digest) {
        return (_docURI[anchor], _docDigest[anchor]);
    }

    function getFacet(address anchor, bytes32 facetType) external view override returns (Facet memory) {
        return _facet[anchor][facetType];
    }

    function facetTypesOf(address anchor) external view override returns (bytes32[] memory) {
        return _facetTypes[anchor];
    }

    function isRetired(address anchor) external view override returns (bool) {
        return _retired[anchor];
    }

    function successorOf(address anchor) external view override returns (address) {
        return _successor[anchor];
    }

    function nonces(address anchor) external view override returns (uint256) {
        return _nonces[anchor];
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(_DOMAIN_TYPEHASH, _NAME_HASH, _VERSION_HASH, block.chainid, address(this)));
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IAIDRegistry).interfaceId;
    }

    // ------------------------------------------------------------------
    // Signature verification (EOA via ecrecover, contracts via EIP-1271)
    // ------------------------------------------------------------------

    function _isValidSignature(address signer, bytes32 digest, bytes calldata sig) internal view returns (bool) {
        if (signer.code.length > 0) {
            try IERC1271(signer).isValidSignature(digest, sig) returns (bytes4 magic) {
                return magic == _ERC1271_MAGIC;
            } catch {
                return false;
            }
        }
        if (sig.length != 65) return false;
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        // EIP-2: reject high-s malleable signatures
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) return false;
        if (v != 27 && v != 28) return false;
        address rec = ecrecover(digest, v, r, s);
        return rec != address(0) && rec == signer;
    }
}
