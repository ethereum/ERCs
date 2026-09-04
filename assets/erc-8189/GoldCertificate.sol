// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title GoldCertificate
 * @notice ERC-721 NFT representing a certified physical gold bar deposited into vault
 * @dev Each token = one physical bar. Metadata stored on IPFS. Used by BarFractionizer.
 */

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract GoldCertificate is ERC721, ERC721URIStorage, AccessControl {
    using Counters for Counters.Counter;

    // ─── Roles ───────────────────────────────────────────────────────────────
    bytes32 public constant VAULT_OPERATOR = keccak256("VAULT_OPERATOR");
    bytes32 public constant AUDITOR_ROLE   = keccak256("AUDITOR_ROLE");

    // ─── Counter ─────────────────────────────────────────────────────────────
    Counters.Counter private _barIds;

    // ─── Bar Status ───────────────────────────────────────────────────────────
    enum BarStatus { Active, PartiallyRedeemed, FullyRedeemed }

    // ─── Structs ──────────────────────────────────────────────────────────────
    struct GoldBar {
        string  serialNumber;       // e.g. "PAMP-2024-00421"
        string  refinery;           // e.g. "PAMP Suisse" / "Public Gold MY"
        uint256 weightGrams;        // stored as integer grams (e.g. 12441 for 400oz)
        uint256 purityBps;          // basis points: 9999 = 99.99%
        string  assayNumber;        // assay certificate reference
        string  ipfsDocHash;        // IPFS CID of cert PDF + photos
        BarStatus status;
        uint256 depositTimestamp;
        uint256 remainingGrams;     // decreases as tokens are redeemed
    }

    // ─── Storage ──────────────────────────────────────────────────────────────
    mapping(uint256 => GoldBar) public bars;

    // track which bars are linked to EmasGold fractions
    mapping(uint256 => address) public barFractionContract; // barId => EmasGold address
    mapping(uint256 => bool)    public barFractionized;

    // ─── Events ───────────────────────────────────────────────────────────────
    event BarDeposited(
        uint256 indexed barId,
        string  serialNumber,
        string  refinery,
        uint256 weightGrams,
        uint256 purityBps,
        string  ipfsDocHash
    );
    event BarStatusUpdated(uint256 indexed barId, BarStatus newStatus);
    event BarFractionized(uint256 indexed barId, address fractionContract);
    event RemainingGramsUpdated(uint256 indexed barId, uint256 remaining);

    // ─── Constructor ──────────────────────────────────────────────────────────
    constructor() ERC721("EmasGold Certificate", "EMASCERT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_OPERATOR,     msg.sender);
        _grantRole(AUDITOR_ROLE,       msg.sender);
    }

    // ─── Deposit & Certify ────────────────────────────────────────────────────

    /**
     * @notice Vault operator deposits a physical bar and mints a certificate NFT
     * @param to         Recipient of the certificate (usually treasury/issuer)
     * @param serial     Bar serial number
     * @param refinery   Refinery name
     * @param grams      Total weight in grams (integer)
     * @param purityBps  Purity in basis points (9999 = 99.99%)
     * @param assay      Assay certificate number
     * @param ipfsCid    IPFS CID of supporting documents
     * @return barId     The minted token ID
     */
    function depositBar(
        address to,
        string calldata serial,
        string calldata refinery,
        uint256 grams,
        uint256 purityBps,
        string calldata assay,
        string calldata ipfsCid
    )
        external
        onlyRole(VAULT_OPERATOR)
        returns (uint256 barId)
    {
        require(grams > 0,            "GoldCert: zero weight");
        require(purityBps <= 10000,   "GoldCert: invalid purity");
        require(bytes(serial).length > 0, "GoldCert: empty serial");

        _barIds.increment();
        barId = _barIds.current();

        bars[barId] = GoldBar({
            serialNumber:     serial,
            refinery:         refinery,
            weightGrams:      grams,
            purityBps:        purityBps,
            assayNumber:      assay,
            ipfsDocHash:      ipfsCid,
            status:           BarStatus.Active,
            depositTimestamp: block.timestamp,
            remainingGrams:   grams
        });

        _safeMint(to, barId);
        _setTokenURI(barId, string(abi.encodePacked("ipfs://", ipfsCid)));

        emit BarDeposited(barId, serial, refinery, grams, purityBps, ipfsCid);
    }

    // ─── Fractionization Link ─────────────────────────────────────────────────

    /**
     * @notice Links a bar certificate to an EmasGold fraction contract
     * @dev Called by BarFractionizer after minting tokens
     */
    function markFractionized(uint256 barId, address fractionContract)
        external
        onlyRole(VAULT_OPERATOR)
    {
        require(_exists(barId),           "GoldCert: bar not found");
        require(!barFractionized[barId],  "GoldCert: already fractionized");

        barFractionized[barId]      = true;
        barFractionContract[barId]  = fractionContract;

        emit BarFractionized(barId, fractionContract);
    }

    // ─── Redemption Updates ───────────────────────────────────────────────────

    /**
     * @notice Reduces remainingGrams when tokens are redeemed
     * @dev Only callable by the linked fraction contract
     */
    function reduceRemaining(uint256 barId, uint256 gramsRedeemed)
        external
    {
        require(
            msg.sender == barFractionContract[barId],
            "GoldCert: caller not fraction contract"
        );
        GoldBar storage bar = bars[barId];
        require(bar.remainingGrams >= gramsRedeemed, "GoldCert: exceeds remaining");

        bar.remainingGrams -= gramsRedeemed;

        if (bar.remainingGrams == 0) {
            bar.status = BarStatus.FullyRedeemed;
        } else {
            bar.status = BarStatus.PartiallyRedeemed;
        }

        emit RemainingGramsUpdated(barId, bar.remainingGrams);
        emit BarStatusUpdated(barId, bar.status);
    }

    // ─── Auditor Functions ────────────────────────────────────────────────────

    /**
     * @notice Auditor updates IPFS document hash (e.g. new monthly audit)
     */
    function updateAuditDoc(uint256 barId, string calldata newIpfsCid)
        external
        onlyRole(AUDITOR_ROLE)
    {
        require(_exists(barId), "GoldCert: bar not found");
        bars[barId].ipfsDocHash = newIpfsCid;
        _setTokenURI(barId, string(abi.encodePacked("ipfs://", newIpfsCid)));
    }

    // ─── View Functions ───────────────────────────────────────────────────────

    function getBar(uint256 barId) external view returns (GoldBar memory) {
        require(_exists(barId), "GoldCert: bar not found");
        return bars[barId];
    }

    function totalBars() external view returns (uint256) {
        return _barIds.current();
    }

    function isBarActive(uint256 barId) external view returns (bool) {
        return bars[barId].status == BarStatus.Active ||
               bars[barId].status == BarStatus.PartiallyRedeemed;
    }

    // ─── Overrides ────────────────────────────────────────────────────────────
    function tokenURI(uint256 tokenId)
        public view override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721, ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
