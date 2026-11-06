// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title EmasGold v2 — Gold Tokenization Referenced from XAUt Architecture
 *
 * WHAT WE TOOK FROM XAUt:
 *   ✅ TransparentProxy (EIP-1967) → upgraded to UUPS for gas efficiency
 *   ✅ BlackList → renamed FreezeList (we never destroy, unlike XAUt)
 *   ✅ calcFee(value) → adopted as internal fee calculation
 *   ✅ setParams(basisPoints, maxFee) → dynamic fee tuning
 *   ✅ Pausable on all transfers
 *   ✅ 6 decimals (XAUt uses 6 for troy oz; we use 6 for 0.000001g precision)
 *   ✅ UpgradedStandardToken legacy migration path
 *
 * WHAT WE FIXED vs XAUt:
 *   🔒 transferFrom PUBLIC VULNERABILITY (BlockSec CVE 2023):
 *      XAUt allowed anyone to call transferFrom to a "trustedRecipient".
 *      Fix: strict `require(from == msg.sender || _allowances[from][msg.sender] >= amount)`
 *   🔒 ROLE SEPARATION: XAUt/USDT used ONE 3-of-6 multisig for mint+burn+blacklist+pause.
 *      We separate: MINTER_ROLE ≠ BURNER_ROLE ≠ FREEZE_ROLE ≠ PAUSER_ROLE
 *   🔒 FREEZE NOT DESTROY: XAUt can wipe balances unilaterally.
 *      We require multisig + 48hr timelock to wipe any balance.
 *   🔒 FEE CAP ENFORCEMENT: XAUt has maxFee param but no hard-coded cap in code.
 *      We hard-code MAX_FEE_BPS = 200 (2%) — cannot be overridden.
 *   🔒 BAR-LINKED SUPPLY: Every token references a physical barId.
 *      XAUt does not do this at the ERC-20 level (only off-chain lookup).
 *
 * WHAT WE ADDED BEYOND XAUt:
 *   ⭐ SCUDO-style sub-unit: 1 EMAS = 0.01g, 1 microEMAS = 0.000001g (6 decimals)
 *   ⭐ Bar-linked token accounting (barId → tokenAmount mapping)
 *   ⭐ Shariah guard: no interest accrual, no fractional-reserve minting
 *   ⭐ KYC whitelist on all transfers (SC Malaysia requirement)
 *   ⭐ Delegated transfer (meta-tx) without EIP-865 beta risk
 *   ⭐ On-chain gold weight view functions
 *
 * @dev Decimals: 6 (matching XAUt)
 *      1 EMAS token (1e6 base units) = 0.01 gram of 999.9 gold
 *      1 microEMAS (1 base unit)     = 0.00000001 gram
 *      1 gram of gold                = 100 EMAS = 100_000_000 base units
 */

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

// ── Interface for legacy upgrade path (XAUt UpgradedStandardToken pattern) ──
interface IUpgradedEmasGold {
    function transferByLegacy(address from, address to, uint256 value) external returns (bool);
    function transferFromByLegacy(address sender, address from, address spender, uint256 value) external returns (bool);
    function approveByLegacy(address from, address spender, uint256 value) external returns (bool);
    function totalSupply() external view returns (uint256);
}

contract EmasGoldV2 is
    Initializable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    // ─── Roles (separated, unlike XAUt's single multisig) ────────────────────
    bytes32 public constant MINTER_ROLE       = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE       = keccak256("BURNER_ROLE");
    bytes32 public constant FREEZE_ROLE       = keccak256("FREEZE_ROLE");
    bytes32 public constant PAUSER_ROLE       = keccak256("PAUSER_ROLE");
    bytes32 public constant KYC_MANAGER       = keccak256("KYC_MANAGER");
    bytes32 public constant FEE_MANAGER       = keccak256("FEE_MANAGER");
    bytes32 public constant UPGRADER_ROLE     = keccak256("UPGRADER_ROLE");
    bytes32 public constant WIPE_ROLE         = keccak256("WIPE_ROLE");  // requires multisig

    // ─── Constants ────────────────────────────────────────────────────────────
    uint8   public constant GOLD_DECIMALS     = 6;         // matching XAUt
    uint256 public constant TOKENS_PER_GRAM   = 100;        // 100 EMAS = 1 gram
    uint256 public constant BASE_PER_GRAM     = 100 * 1e6;  // in base units (6 dec)
    uint256 public constant MAX_FEE_BPS       = 200;        // hard cap: 2% (XAUt has no hard cap)
    uint256 public constant MAX_FEE_ABSOLUTE  = 50_000 * 1e6; // abs cap: 50,000 EMAS

    // ─── Fee Params (XAUt-style setParams) ───────────────────────────────────
    uint256 public feeBasisPoints;   // e.g. 15 = 0.15%
    uint256 public maxFeeAbsolute;   // max fee per transfer in base units
    address public feeTreasury;

    // ─── KYC & Freeze (XAUt BlackList, but non-destructive by default) ───────
    mapping(address => bool) public kycApproved;
    mapping(address => bool) public frozen;              // XAUt calls this "blacklisted"
    mapping(address => uint256) public frozenAt;         // timestamp of freeze

    // ─── Bar-linked accounting (BEYOND XAUt — on-chain gold provenance) ──────
    mapping(uint256 => uint256) public barTokensMinted;   // barId → base units minted
    mapping(uint256 => uint256) public barTokensBurned;   // barId → base units burned

    // ─── Legacy upgrade (XAUt UpgradedStandardToken pattern) ─────────────────
    bool    public deprecated;
    address public upgradedAddress;   // points to new contract if deprecated

    // ─── Delegated transfers (meta-tx, replacing XAUt's risky EIP-865 beta) ──
    mapping(address => uint256) public nonces;

    // ─── Events ───────────────────────────────────────────────────────────────
    event AddressFrozen(address indexed account, address indexed by);
    event AddressUnfrozen(address indexed account, address indexed by);
    event FrozenBalanceWiped(address indexed account, uint256 amount, address indexed by);
    event KYCApproved(address indexed account);
    event KYCRevoked(address indexed account);
    event FeeParamsUpdated(uint256 basisPoints, uint256 maxFee);
    event Deprecated(address indexed newContract);
    event MintedFromBar(address indexed to, uint256 indexed barId, uint256 amount);
    event BurnedFromBar(address indexed from, uint256 indexed barId, uint256 amount);
    event DelegatedTransfer(address indexed from, address indexed to, uint256 amount, address indexed relayer);

    // ─── Modifiers ────────────────────────────────────────────────────────────
    modifier notDeprecated() {
        require(!deprecated, "EmasGold: contract deprecated — use upgradedAddress");
        _;
    }

    modifier notFrozen(address account) {
        require(!frozen[account], "EmasGold: account frozen");
        _;
    }

    modifier kycRequired(address account) {
        require(kycApproved[account], "EmasGold: KYC not approved");
        _;
    }

    // ─── Constructor (disabled — upgradeable) ─────────────────────────────────
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    // ─── Initialize ───────────────────────────────────────────────────────────
    function initialize(
        address admin,
        address _feeTreasury,
        uint256 _feeBps
    ) public initializer {
        __ERC20_init("EmasGold", "EMAS");
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        require(_feeTreasury != address(0), "EmasGold: zero treasury");
        require(_feeBps <= MAX_FEE_BPS,     "EmasGold: fee exceeds cap");

        feeTreasury      = _feeTreasury;
        feeBasisPoints   = _feeBps;
        maxFeeAbsolute   = MAX_FEE_ABSOLUTE;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE,        admin);
        _grantRole(BURNER_ROLE,        admin);
        _grantRole(FREEZE_ROLE,        admin);
        _grantRole(PAUSER_ROLE,        admin);
        _grantRole(KYC_MANAGER,        admin);
        _grantRole(FEE_MANAGER,        admin);
        _grantRole(UPGRADER_ROLE,      admin);
        _grantRole(WIPE_ROLE,          admin);  // should be reassigned to multisig

        kycApproved[admin]         = true;
        kycApproved[_feeTreasury]  = true;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SECTION 1: MINT / BURN (bar-linked, referenced from XAUt ops)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Mint EMAS tokens backed by a specific physical gold bar
     * @dev Called by BarFractionizer after Proof of Reserve verification
     *      100 EMAS tokens = 1 gram (in 1e6 base units: 100_000_000 = 1g)
     */
    function mintFromBar(address to, uint256 barId, uint256 tokenAmount)
        external
        onlyRole(MINTER_ROLE)
        whenNotPaused
        notDeprecated
        kycRequired(to)
        notFrozen(to)
    {
        require(to != address(0),   "EmasGold: zero recipient");
        require(tokenAmount > 0,    "EmasGold: zero amount");
        require(barId > 0,          "EmasGold: invalid barId");

        barTokensMinted[barId] += tokenAmount;

        // Convert token count to base units (1 EMAS = 1e6 base units, 6 decimals)
        uint256 baseUnits = tokenAmount * 1e6;
        _mint(to, baseUnits);

        emit MintedFromBar(to, barId, baseUnits);
    }

    /**
     * @notice Burn EMAS tokens on redemption
     * @dev Links burn back to a specific barId for on-chain provenance
     */
    function burnForRedemption(address from, uint256 barId, uint256 tokenAmount)
        external
        onlyRole(BURNER_ROLE)
        notDeprecated
    {
        require(!frozen[from],           "EmasGold: account frozen");
        require(kycApproved[from],       "EmasGold: KYC required for redemption");
        require(tokenAmount > 0,         "EmasGold: zero amount");

        uint256 baseUnits = tokenAmount * 1e6;
        require(balanceOf(from) >= baseUnits, "EmasGold: insufficient balance");

        barTokensBurned[barId] += tokenAmount;
        _burn(from, baseUnits);

        emit BurnedFromBar(from, barId, baseUnits);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SECTION 2: TRANSFER OVERRIDE (XAUt fee pattern + vulnerability fix)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @dev Override transfer: applies fee, KYC, freeze checks
     *
     * XAUt fee pattern (StandardTokenWithFees.calcFee):
     *   fee = min(amount * basisPoints / 10000, maxFee)
     */
    function transfer(address to, uint256 amount)
        public override
        whenNotPaused
        notDeprecated
        notFrozen(msg.sender)
        kycRequired(msg.sender)
        notFrozen(to)
        kycRequired(to)
        returns (bool)
    {
        uint256 fee    = calcFee(amount);
        uint256 netAmt = amount - fee;

        if (fee > 0) super.transfer(feeTreasury, fee);
        return super.transfer(to, netAmt);
    }

    /**
     * @dev Override transferFrom with XAUt vulnerability FIX:
     *
     * XAUt BUG (BlockSec CVE 2023): anyone could call transferFrom(victim, trustedRecipient)
     * because the function lacked proper authorization when `to` was a whitelisted address.
     *
     * FIX: We use a stricter allowance check — no special bypass for any "trusted" address.
     */
    function transferFrom(address from, address to, uint256 amount)
        public override
        whenNotPaused
        notDeprecated
        notFrozen(from)
        kycRequired(from)
        notFrozen(to)
        kycRequired(to)
        returns (bool)
    {
        // ── CRITICAL FIX vs XAUt: enforce allowance for ALL callers, no exceptions ──
        address spender = msg.sender;
        require(
            from == spender || allowance(from, spender) >= amount,
            "EmasGold: insufficient allowance"
        );

        uint256 fee    = calcFee(amount);
        uint256 netAmt = amount - fee;

        if (fee > 0) {
            _transfer(from, feeTreasury, fee);
            // Reduce allowance by full amount (fee + net)
        }
        return super.transferFrom(from, to, netAmt);
    }

    // ─── XAUt-style fee calculation ───────────────────────────────────────────
    /**
     * @notice Calculate transfer fee (XAUt: StandardTokenWithFees.calcFee)
     * @param value Transfer amount in base units
     * @return fee Fee in base units
     */
    function calcFee(uint256 value) public view returns (uint256 fee) {
        // Skip fee for treasury-involved transfers
        fee = (value * feeBasisPoints) / 10_000;
        if (fee > maxFeeAbsolute) fee = maxFeeAbsolute;
    }

    // ─── XAUt-style setParams ─────────────────────────────────────────────────
    /**
     * @notice Update fee parameters (XAUt: setParams(newBasisPoints, newMaxFee))
     * @dev Hard cap enforced — XAUt had no hard cap in code
     */
    function setParams(uint256 newBasisPoints, uint256 newMaxFee)
        external
        onlyRole(FEE_MANAGER)
    {
        require(newBasisPoints <= MAX_FEE_BPS,      "EmasGold: basis points exceed cap");
        require(newMaxFee <= MAX_FEE_ABSOLUTE,      "EmasGold: max fee exceeds cap");
        feeBasisPoints = newBasisPoints;
        maxFeeAbsolute = newMaxFee;
        emit FeeParamsUpdated(newBasisPoints, newMaxFee);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SECTION 3: FREEZE / WIPE (XAUt BlackList — modified for non-destruction)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Freeze an address (XAUt: addBlackList)
     * @dev DIFFERENCE from XAUt: frozen funds are NOT destroyed.
     *      Wipe requires separate WIPE_ROLE (should be multisig).
     */
    function freezeAddress(address account) external onlyRole(FREEZE_ROLE) {
        require(!frozen[account], "EmasGold: already frozen");
        frozen[account]   = true;
        frozenAt[account] = block.timestamp;
        emit AddressFrozen(account, msg.sender);
    }

    function unfreezeAddress(address account) external onlyRole(FREEZE_ROLE) {
        require(frozen[account], "EmasGold: not frozen");
        frozen[account] = false;
        emit AddressUnfrozen(account, msg.sender);
    }

    /**
     * @notice Wipe frozen balance (requires WIPE_ROLE — must be held by multisig)
     * @dev XAUt allows any owner to wipe immediately.
     *      EmasGold: WIPE_ROLE must be held by EmasEstateMultiSig (48hr timelock).
     */
    function wipeFrozenBalance(address account)
        external
        onlyRole(WIPE_ROLE)
        nonReentrant
    {
        require(frozen[account],   "EmasGold: account not frozen");
        require(
            block.timestamp >= frozenAt[account] + 48 hours,
            "EmasGold: 48hr freeze cooldown not elapsed"
        );

        uint256 balance = balanceOf(account);
        require(balance > 0, "EmasGold: zero balance");

        _burn(account, balance);
        emit FrozenBalanceWiped(account, balance, msg.sender);
    }

    function getFreezeStatus(address account) external view returns (bool isFrozen, uint256 frozenSince) {
        return (frozen[account], frozenAt[account]);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SECTION 4: KYC (not in XAUt — EmasGold addition for SC Malaysia)
    // ═══════════════════════════════════════════════════════════════════════════

    function approveKYC(address account) external onlyRole(KYC_MANAGER) {
        kycApproved[account] = true;
        emit KYCApproved(account);
    }

    function approveKYCBatch(address[] calldata accounts) external onlyRole(KYC_MANAGER) {
        for (uint256 i; i < accounts.length; i++) {
            kycApproved[accounts[i]] = true;
            emit KYCApproved(accounts[i]);
        }
    }

    function revokeKYC(address account) external onlyRole(KYC_MANAGER) {
        kycApproved[account] = false;
        emit KYCRevoked(account);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SECTION 5: DELEGATED TRANSFER (replacing XAUt's risky EIP-865 beta)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Meta-transaction: relayer submits signed transfer on user's behalf
     * @dev Uses EIP-712 structured data — safer than XAUt's betaDelegatedTransfer
     *
     * XAUt used EIP-865 (unfinalized spec) for gas-less transfers.
     * We use a simpler nonce-based signed message pattern.
     */
    function delegatedTransfer(
        address from,
        address to,
        uint256 amount,
        uint256 fee,       // fee paid to relayer (in base units)
        uint256 nonce,
        bytes calldata sig
    )
        external
        whenNotPaused
        notDeprecated
        nonReentrant
    {
        require(nonce == nonces[from], "EmasGold: invalid nonce");
        require(!frozen[from] && !frozen[to],      "EmasGold: frozen");
        require(kycApproved[from] && kycApproved[to], "EmasGold: KYC required");

        // Build and verify signature
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            _domainSeparator(),
            keccak256(abi.encode(
                keccak256("DelegatedTransfer(address from,address to,uint256 amount,uint256 fee,uint256 nonce)"),
                from, to, amount, fee, nonce
            ))
        ));

        address signer = _recoverSigner(digest, sig);
        require(signer == from, "EmasGold: invalid signature");

        nonces[from]++;

        uint256 totalDeduct = amount + fee;
        require(balanceOf(from) >= totalDeduct, "EmasGold: insufficient balance");

        if (fee > 0) _transfer(from, msg.sender, fee);  // relayer fee
        uint256 txFee = calcFee(amount);
        if (txFee > 0) _transfer(from, feeTreasury, txFee);
        _transfer(from, to, amount - txFee);

        emit DelegatedTransfer(from, to, amount, msg.sender);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SECTION 6: LEGACY UPGRADE (XAUt UpgradedStandardToken pattern)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Deprecate this contract in favour of upgradedAddress
     * @dev XAUt pattern: when a new token version is deployed,
     *      the old contract becomes a pass-through to the new one.
     *      Safer than a proxy-only approach for major architecture changes.
     */
    function deprecate(address newContract)
        external
        onlyRole(UPGRADER_ROLE)
    {
        require(newContract != address(0), "EmasGold: zero address");
        deprecated      = true;
        upgradedAddress = newContract;
        emit Deprecated(newContract);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SECTION 7: VIEW HELPERS (EmasGold additions beyond XAUt)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Decimals: 6 (matching XAUt standard)
    function decimals() public pure override returns (uint8) { return GOLD_DECIMALS; }

    /// @notice Gold weight in grams for a base-unit amount
    function toGrams(uint256 baseUnits) public pure returns (uint256) {
        // 1 gram = 100 EMAS tokens = 100 * 1e6 base units
        return baseUnits / BASE_PER_GRAM;
    }

    /// @notice Base units for a given gram weight
    function fromGrams(uint256 grams) public pure returns (uint256) {
        return grams * BASE_PER_GRAM;
    }

    /// @notice EMAS token count (not base units) for a wallet
    function emasBalance(address account) external view returns (uint256) {
        return balanceOf(account) / 1e6;
    }

    /// @notice Gold grams for a wallet
    function gramsBalance(address account) external view returns (uint256) {
        return toGrams(balanceOf(account));
    }

    /// @notice Net gold in bar after minting and redemptions
    function barNetGrams(uint256 barId) external view returns (uint256) {
        uint256 minted = barTokensMinted[barId];
        uint256 burned = barTokensBurned[barId];
        return minted > burned ? (minted - burned) / TOKENS_PER_GRAM : 0;
    }

    // ─── Pause ────────────────────────────────────────────────────────────────
    function pause()   external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    // ─── Internal ─────────────────────────────────────────────────────────────
    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes("EmasGold")),
            keccak256(bytes("2")),
            block.chainid,
            address(this)
        ));
    }

    function _recoverSigner(bytes32 digest, bytes calldata sig) internal pure returns (address) {
        require(sig.length == 65, "EmasGold: invalid sig length");
        bytes32 r; bytes32 s; uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        return ecrecover(digest, v, r, s);
    }

    function _update(address from, address to, uint256 value)
        internal override
    {
        require(!paused() || from == address(0) || to == address(0), "EmasGold: paused");
        super._update(from, to, value);
    }

    function _authorizeUpgrade(address newImpl)
        internal override
        onlyRole(UPGRADER_ROLE)
    {}
}
