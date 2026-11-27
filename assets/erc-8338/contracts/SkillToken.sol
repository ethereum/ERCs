// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ISkillToken} from "./interfaces/ISkillToken.sol";
import {IOnchainSkillDocument} from "./interfaces/IOnchainSkillDocument.sol";

/// @title  SkillToken — reference implementation of Token-Bound Executable Skills
///         (KERNEL v4.3, frozen). Self-contained minimal ERC-721 + both interfaces.
/// @notice Reference quality: favors clarity and 1:1 spec traceability over gas.
contract SkillToken is ISkillToken, IOnchainSkillDocument {

    // ---------------------------------------------------------------- ERC-721 core
    string public name;
    string public symbol;

    mapping(uint256 => address) private _owner;
    mapping(address => uint256) private _balance;
    mapping(uint256 => address) private _tokenApproval;
    mapping(address => mapping(address => bool)) private _operatorApproval;

    // ------------------------------------------------------------- Skill binding
    mapping(uint256 => SkillBinding) private _binding;
    mapping(uint256 => string)  private _packageURI;      // transport hint, outside identity
    mapping(uint256 => address) private _updateAuthority; // publication right, outside ownership
    mapping(uint256 => bool)    private _frozen;

    // -------------------------------------------------- On-chain document (optional ext)
    mapping(uint256 => bytes) private _document;          // plaintext primary document
    mapping(uint256 => bool)  private _hasDocument;       // monotone: false -> true only

    uint256 public nextId = 1;

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    // =============================================================== modifiers
    modifier exists(uint256 tokenId) {
        require(_owner[tokenId] != address(0), "SkillToken: nonexistent token");
        _;
    }

    /// Publication powers belong to the update authority alone. ERC-721 owner,
    /// approved, and operators MUST NOT reach these functions (approval-leakage rule).
    modifier onlyUpdateAuthority(uint256 tokenId) {
        require(msg.sender == _updateAuthority[tokenId], "SkillToken: not update authority");
        _;
    }

    // =============================================================== ERC-165
    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == 0x01ffc9a7                              // ERC-165
            || id == 0x80ac58cd                              // ERC-721
            || id == 0x5b5e139f                              // ERC-721 Metadata
            || id == type(ISkillToken).interfaceId
            || id == type(IOnchainSkillDocument).interfaceId;
    }

    // =============================================================== mint
    /// @notice Mint a new skill token. Binding fully populated; placeholder minting
    ///         is impossible. Emits SkillUpdated (version 1) and the genesis
    ///         SkillUpdateAuthorityChanged so the event stream is complete history.
    function mintSkill(
        address to,
        address updateAuthority_,
        bytes32 mdHash,
        bytes32 packageHash,
        string calldata packageURI_
    ) external returns (uint256 tokenId) {
        require(to != address(0), "SkillToken: mint to zero");
        require(updateAuthority_ != address(0), "SkillToken: zero authority");
        require(mdHash != bytes32(0) && packageHash != bytes32(0), "SkillToken: zero hash");
        require(bytes(packageURI_).length != 0, "SkillToken: empty packageURI");

        tokenId = nextId++;
        _owner[tokenId] = to;
        _balance[to] += 1;
        emit Transfer(address(0), to, tokenId);

        _binding[tokenId] = SkillBinding(mdHash, packageHash, 1);
        _packageURI[tokenId] = packageURI_;
        _updateAuthority[tokenId] = updateAuthority_;

        emit SkillUpdated(tokenId, mdHash, packageHash, 1);
        emit SkillUpdateAuthorityChanged(tokenId, address(0), updateAuthority_);
    }

    // =============================================================== ISkillToken views
    function skillOf(uint256 tokenId) external view exists(tokenId) returns (SkillBinding memory) {
        return _binding[tokenId];
    }

    function skillURI(uint256 tokenId) external view exists(tokenId) returns (string memory) {
        return _packageURI[tokenId];
    }

    function updateAuthorityOf(uint256 tokenId) external view exists(tokenId) returns (address) {
        return _updateAuthority[tokenId];
    }

    function isSkillFrozen(uint256 tokenId) external view exists(tokenId) returns (bool) {
        return _frozen[tokenId];
    }

    // =============================================================== ISkillToken mutations
    function updateSkill(uint256 tokenId, bytes32 mdHash, bytes32 packageHash)
        external exists(tokenId) onlyUpdateAuthority(tokenId)
    {
        // On-chain document consistency: when a copy exists and mdHash would change,
        // the update MUST go through updateSkillWithDocument (atomic doc+binding).
        require(
            !_hasDocument[tokenId] || mdHash == _binding[tokenId].mdHash,
            "SkillToken: use updateSkillWithDocument"
        );
        _applyUpdate(tokenId, mdHash, packageHash);
    }

    function _applyUpdate(uint256 tokenId, bytes32 mdHash, bytes32 packageHash) private {
        require(!_frozen[tokenId], "SkillToken: frozen");
        require(mdHash != bytes32(0) && packageHash != bytes32(0), "SkillToken: zero hash");
        SkillBinding storage b = _binding[tokenId];
        require(packageHash != b.packageHash, "SkillToken: packageHash must differ");
        // uint64 overflow reverts natively under solc >= 0.8 (append-only guarantee)
        b.mdHash = mdHash;
        b.packageHash = packageHash;
        b.version += 1;
        emit SkillUpdated(tokenId, mdHash, packageHash, b.version);
    }

    /// Transport is outside identity: never changes version; allowed while frozen.
    function setSkillURI(uint256 tokenId, string calldata packageURI_)
        external exists(tokenId) onlyUpdateAuthority(tokenId)
    {
        require(bytes(packageURI_).length != 0, "SkillToken: empty packageURI");
        _packageURI[tokenId] = packageURI_;
        emit SkillURIUpdated(tokenId, packageURI_);
    }

    /// Zero authority is forbidden: abandonment is expressed by freezeSkill,
    /// never by burning the authority. Allowed while frozen (transport stewardship).
    function setUpdateAuthority(uint256 tokenId, address newAuthority)
        external exists(tokenId) onlyUpdateAuthority(tokenId)
    {
        require(newAuthority != address(0), "SkillToken: zero authority");
        address prev = _updateAuthority[tokenId];
        _updateAuthority[tokenId] = newAuthority;
        emit SkillUpdateAuthorityChanged(tokenId, prev, newAuthority);
    }

    /// Irreversible: binds content (hashes, version), not transport.
    function freezeSkill(uint256 tokenId)
        external exists(tokenId) onlyUpdateAuthority(tokenId)
    {
        require(!_frozen[tokenId], "SkillToken: already frozen");
        _frozen[tokenId] = true;
        emit SkillFrozen(tokenId);
    }

    // =============================================================== IOnchainSkillDocument
    function hasOnchainSkillDocument(uint256 tokenId)
        external view exists(tokenId) returns (bool)
    {
        return _hasDocument[tokenId];
    }

    function skillDocument(uint256 tokenId)
        external view exists(tokenId) returns (bytes memory)
    {
        require(_hasDocument[tokenId], "SkillToken: no on-chain document");
        return _document[tokenId];
    }

    /// Disclosure without a version change: document must be the current committed
    /// plaintext. Restricted to the update authority — publishing on-chain is an
    /// irreversible disclosure decision, i.e. a publication act.
    function publishSkillDocument(uint256 tokenId, bytes calldata document)
        external exists(tokenId) onlyUpdateAuthority(tokenId)
    {
        require(sha256(document) == _binding[tokenId].mdHash, "SkillToken: doc != mdHash");
        _document[tokenId] = document;
        _hasDocument[tokenId] = true; // monotone; never unset anywhere
        emit SkillDocumentPublished(tokenId, _binding[tokenId].mdHash);
    }

    /// Atomic document+binding update: mdHash computed in-contract, making the
    /// doc/hash-agreement invariant structural rather than procedural.
    function updateSkillWithDocument(uint256 tokenId, bytes calldata document, bytes32 packageHash)
        external exists(tokenId) onlyUpdateAuthority(tokenId)
    {
        bytes32 mdHash = sha256(document);
        _applyUpdate(tokenId, mdHash, packageHash);
        _document[tokenId] = document;
        _hasDocument[tokenId] = true; // may transition false -> true; never back
        emit SkillDocumentPublished(tokenId, mdHash);
    }

    // =============================================================== ERC-721 (minimal)
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function balanceOf(address a) external view returns (uint256) {
        require(a != address(0), "SkillToken: zero address");
        return _balance[a];
    }

    function ownerOf(uint256 tokenId) public view exists(tokenId) returns (address) {
        return _owner[tokenId];
    }

    function approve(address to, uint256 tokenId) external {
        address o = ownerOf(tokenId);
        require(msg.sender == o || _operatorApproval[o][msg.sender], "SkillToken: not authorized");
        _tokenApproval[tokenId] = to;
        emit Approval(o, to, tokenId);
    }

    function getApproved(uint256 tokenId) external view exists(tokenId) returns (address) {
        return _tokenApproval[tokenId];
    }

    function setApprovalForAll(address op, bool ok) external {
        _operatorApproval[msg.sender][op] = ok;
        emit ApprovalForAll(msg.sender, op, ok);
    }

    function isApprovedForAll(address o, address op) external view returns (bool) {
        return _operatorApproval[o][op];
    }

    /// NOTE: ERC-721 transfer moves the ASSET only. It never touches the update
    /// authority — buyers must inspect updateAuthorityOf and isSkillFrozen.
    function transferFrom(address from, address to, uint256 tokenId) public {
        address o = ownerOf(tokenId);
        require(o == from, "SkillToken: wrong from");
        require(to != address(0), "SkillToken: zero to");
        require(
            msg.sender == o || msg.sender == _tokenApproval[tokenId] || _operatorApproval[o][msg.sender],
            "SkillToken: not authorized"
        );
        delete _tokenApproval[tokenId];
        _balance[from] -= 1;
        _balance[to] += 1;
        _owner[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        transferFrom(from, to, tokenId);
        if (to.code.length != 0) {
            (bool ok, bytes memory ret) = to.call(
                abi.encodeWithSignature(
                    "onERC721Received(address,address,uint256,bytes)", msg.sender, from, tokenId, data
                )
            );
            require(ok && ret.length >= 32 && bytes4(ret) == 0x150b7a02, "SkillToken: unsafe receiver");
        }
    }

    /// Display convention only; MUST NOT be used for verification (spec rule).
    function tokenURI(uint256 tokenId) external view exists(tokenId) returns (string memory) {
        return _packageURI[tokenId]; // reference impl mirrors the transport hint for wallets
    }
}
