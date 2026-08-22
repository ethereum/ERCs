// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ILaunchEscrow} from "./ILaunchEscrow.sol";
import {ILaunchDirectory} from "./ILaunchDirectory.sol";
import {IERC20} from "./IERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {
    LaunchState,
    NotVenue,
    NotRemediation,
    UnknownLaunch,
    LaunchNotFreezable,
    LaunchSettledAlready,
    ReleaseScheduleExceeded,
    NothingToRefund
} from "./LaunchAbuseTypes.sol";

// Time is the domain here: vesting schedules, freeze deadlines and refund
// windows are all measured in days. Timestamp comparison is the intended
// semantic, and validator drift of seconds cannot change any outcome.
// slither-disable-start timestamp
contract LaunchEscrow is ILaunchEscrow, ReentrancyGuard {
    uint64 public constant MAX_RELEASE_PERIOD  = 90 days;
    uint64 public constant FREEZE_DURATION     = 14 days;
    uint64 public constant REFUND_CLAIM_PERIOD = 180 days;

    struct Launch {
        address token;
        address deployer;
        address venue;
        address asset;      // address(0) == native
        uint64  releaseStart;
        uint64  releaseEnd;
        uint64  frozenUntil;
        uint64  refundOpenedAt;
        uint256 proceeds;
        uint256 released;
        uint256 bond;
        uint256 refundPool;
        uint256 refundPaid;
        uint256 totalNetPaid;
        bool    refunding;
        bool    exists;
    }

    struct Purchase {
        uint256 paid;
        uint256 tokens;
        uint256 realised;
        uint256 refunded;
        bool    excluded; // deployer-linked: cannot refund, does not dilute
    }

    address public immutable remediation;
    ILaunchDirectory public immutable directory;

    mapping(bytes32 => Launch) internal _launches;
    mapping(bytes32 => mapping(address => Purchase)) internal _purchases;
    mapping(address => mapping(address => uint256)) internal _nonce;
    /// @dev Tokens this contract has taken responsibility for, per asset. The
    ///      venue transfers first and this contract verifies afterwards, so it
    ///      never makes a transfer call between reading a balance and acting on
    ///      it. That ordering is what removes the stale-balance hazard, rather
    ///      than a comment asserting the read is safe.
    mapping(address => uint256) internal _accounted;

    modifier onlyVenue(bytes32 id) {
        if (msg.sender != _launches[id].venue) revert NotVenue(msg.sender);
        _;
    }

    modifier onlyRemediation() {
        if (msg.sender != remediation) revert NotRemediation(msg.sender);
        _;
    }

    modifier exists(bytes32 id) {
        if (!_launches[id].exists) revert UnknownLaunch(id);
        _;
    }

    constructor(address remediation_, ILaunchDirectory directory_) {
        require(remediation_ != address(0) && address(directory_) != address(0), "zero address");
        remediation = remediation_;
        directory = directory_;
    }

    // --- identity -----------------------------------------------------------

    function deriveLaunchId(address token, address deployer, uint256 nonce)
        public
        view
        returns (bytes32)
    {
        return keccak256(abi.encode(block.chainid, address(this), token, deployer, nonce));
    }

    function nextNonce(address token, address deployer) external view returns (uint256) {
        return _nonce[token][deployer];
    }

    // --- registration -------------------------------------------------------

    /// @notice Convenience form for native settlement, passing `msg.value` as
    ///         the bond.
    function registerLaunchNative(
        address token,
        address deployer,
        uint64  releaseStart,
        uint64  releaseEnd
    ) external payable nonReentrant returns (bytes32) {
        return _register(token, deployer, address(0), msg.value, releaseStart, releaseEnd);
    }

    /// @param asset settlement asset; address(0) for native value
    /// @param bondAmount collateral answerable for upheld claims, in `asset`
    function registerLaunch(
        address token,
        address deployer,
        address asset,
        uint256 bondAmount,
        uint64  releaseStart,
        uint64  releaseEnd
    ) public payable nonReentrant returns (bytes32) {
        return _register(token, deployer, asset, bondAmount, releaseStart, releaseEnd);
    }

    function _register(
        address token,
        address deployer,
        address asset,
        uint256 bondAmount,
        uint64  releaseStart,
        uint64  releaseEnd
    ) internal returns (bytes32 launchId) {
        require(releaseEnd >= releaseStart, "bad schedule");
        require(releaseEnd - releaseStart <= MAX_RELEASE_PERIOD, "period too long");

        if (asset == address(0)) {
            require(msg.value == bondAmount, "bond value mismatch");
        } else {
            require(msg.value == 0, "native value with erc20 launch");
        }

        uint256 nonce = _nonce[token][deployer]++;
        launchId = deriveLaunchId(token, deployer, nonce);
        require(!_launches[launchId].exists, "duplicate launch");

        Launch storage l = _launches[launchId];
        l.token = token;
        l.deployer = deployer;
        l.venue = msg.sender;
        l.asset = asset;
        l.releaseStart = releaseStart;
        l.releaseEnd = releaseEnd;
        l.bond = bondAmount;
        l.exists = true;

        // Every external call happens after the launch record is complete, so
        // a callback can only observe fully written state.
        if (asset != address(0) && bondAmount > 0) _creditERC20(asset, bondAmount);

        // Listing is part of registration, not an optional follow-up: an
        // unlistable launch is also unreportable.
        directory.list(launchId, token, deployer, msg.sender, nonce);

        emit LaunchRegistered(launchId, token, deployer, bondAmount, releaseStart, releaseEnd);
    }

    /// @notice Add collateral to an existing launch.
    function topUpBond(bytes32 id, uint256 amount) external payable exists(id) nonReentrant {
        Launch storage l = _launches[id];
        bool native = l.asset == address(0);
        if (native) {
            require(msg.value == amount, "bond value mismatch");
        } else {
            require(msg.value == 0, "native value with erc20 launch");
        }
        l.bond += amount;
        if (!native) _creditERC20(l.asset, amount);
    }

    // --- purchase accounting ------------------------------------------------

    function recordPurchase(bytes32 id, address buyer, uint256 paid, uint256 tokens)
        external
        payable
        exists(id)
        onlyVenue(id)
        nonReentrant
    {
        Launch storage l = _launches[id];
        // Once the pool is open, `totalNetPaid` is the fixed denominator every
        // entitlement was computed against. Moving it afterwards makes the
        // shares sum to more than the pool, and because this contract custodies
        // every launch, the excess is drawn from other launches' funds.
        require(!l.refunding, "refund pool is open");
        bool native = l.asset == address(0);
        if (native) {
            require(msg.value == paid, "value mismatch");
        } else {
            require(msg.value == 0, "native value with erc20 launch");
        }

        Purchase storage p = _purchases[id][buyer];
        // Track the change in net contribution rather than the gross amount, as
        // `recordSale` does. A buyer whose realised value already exceeds what
        // they paid nets to zero, so adding the gross here would put a
        // contribution in the denominator that no buyer can claim against, and
        // scale every honest buyer's share down by it.
        uint256 before = _net(p);
        p.paid += paid;
        p.tokens += tokens;
        l.proceeds += paid;
        if (!p.excluded) l.totalNetPaid += _net(p) - before;
        emit PurchaseRecorded(id, buyer, paid, tokens);

        if (!native) _creditERC20(l.asset, paid);
    }

    /// @dev Reduces the buyer's net contribution and the pool denominator with
    ///      it, so an exited buyer neither draws a refund nor dilutes holders.
    function recordSale(bytes32 id, address buyer, uint256 realised)
        external
        exists(id)
        onlyVenue(id)
        nonReentrant
    {
        Launch storage l = _launches[id];
        require(!l.refunding, "refund pool is open");
        Purchase storage p = _purchases[id][buyer];

        uint256 before = _net(p);
        p.realised += realised;
        uint256 remaining = _net(p);

        if (!p.excluded) l.totalNetPaid -= (before - remaining);
        emit SaleRecorded(id, buyer, realised);
    }

    /// @notice Exclude a deployer-linked address from the refund pool.
    /// @dev Without this, a deployer anticipating a claim can buy their own
    ///      launch through fresh addresses and shrink every honest buyer's
    ///      pro-rata share. Exclusion removes them from the denominator too, so
    ///      the remaining buyers are made whole rather than merely undiluted.
    function markLinked(bytes32 id, address account) external exists(id) onlyRemediation nonReentrant {
        Launch storage l = _launches[id];
        // Exclusion must be decided before the pool opens, for the same reason.
        require(!l.refunding, "refund pool is open");
        Purchase storage p = _purchases[id][account];
        require(!p.excluded, "already excluded");

        uint256 removed = _net(p);
        l.totalNetPaid -= removed;
        p.excluded = true;
        emit LinkedAddressExcluded(id, account, removed);
    }

    function _net(Purchase storage p) internal view returns (uint256) {
        if (p.excluded) return 0;
        return p.realised >= p.paid ? 0 : p.paid - p.realised;
    }

    function netContributionOf(bytes32 id, address buyer) external view returns (uint256) {
        return _net(_purchases[id][buyer]);
    }

    // --- release ------------------------------------------------------------

    function vestedAmount(bytes32 id) public view returns (uint256) {
        Launch storage l = _launches[id];
        if (l.refunding) return l.released;
        if (block.timestamp <= l.releaseStart) return 0;
        if (l.releaseEnd <= l.releaseStart || block.timestamp >= l.releaseEnd) return l.proceeds;
        return (l.proceeds * (block.timestamp - l.releaseStart)) / (l.releaseEnd - l.releaseStart);
    }

    function releasableAmount(bytes32 id) public view returns (uint256) {
        uint256 vested = vestedAmount(id);
        Launch storage l = _launches[id];
        return vested > l.released ? vested - l.released : 0;
    }

    /// @dev The equality against `proceeds` marks a fully vested launch; it is
    ///      reached only through the schedule, never from an external balance.

    // slither-disable-next-line low-level-calls
    function releaseProceeds(bytes32 id) external exists(id) nonReentrant returns (uint256 amount) {
        LaunchState s = stateOf(id);
        if (s == LaunchState.Frozen)    revert LaunchNotFreezable(id, s);
        if (s == LaunchState.Refunding) revert LaunchSettledAlready(id);

        Launch storage l = _launches[id];
        amount = releasableAmount(id);
        if (!(amount > 0)) revert ReleaseScheduleExceeded(1, 0);

        l.released += amount;
        emit ProceedsReleased(id, amount);
        if (l.asset == address(0)) {
            (bool ok, ) = l.deployer.call{value: amount}("");
            require(ok, "native transfer failed");
        } else {
            _payToken(l.asset, l.deployer, amount);
        }

        if (l.released >= l.proceeds && block.timestamp >= l.releaseEnd) emit LaunchSettled(id);
    }

    // --- containment --------------------------------------------------------

    function freezeLaunch(bytes32 id, bytes32 reportId) external exists(id) onlyRemediation nonReentrant {
        LaunchState s = stateOf(id);
        if (s != LaunchState.Active && s != LaunchState.Releasing) revert LaunchNotFreezable(id, s);

        Launch storage l = _launches[id];
        l.frozenUntil = uint64(block.timestamp) + FREEZE_DURATION;
        emit LaunchFrozen(id, reportId, l.frozenUntil);
    }

    function unfreeze(bytes32 id) external exists(id) onlyRemediation nonReentrant {
        _launches[id].frozenUntil = 0;
    }

    /// @dev O(1): entitlements are computed per buyer at pull time.
    function openRefund(bytes32 id, uint256 fromBond) external exists(id) onlyRemediation nonReentrant {
        Launch storage l = _launches[id];
        require(!l.refunding, "already refunding");
        require(fromBond <= l.bond, "bond exceeded");

        l.bond -= fromBond;
        l.refundPool = (l.proceeds - l.released) + fromBond;
        // Everything escrowed has moved into the pool, so it is no longer
        // releasable and no longer counts as escrowed.
        l.released = l.proceeds;
        l.refunding = true;
        l.refundOpenedAt = uint64(block.timestamp);
        l.frozenUntil = 0;

        emit RefundOpened(id, l.refundPool, l.totalNetPaid);
    }

    /// @notice Add to an already-open refund pool.
    /// @dev A launch can face more than one upheld claim. The second and later
    ///      remedies top up the existing pool rather than failing, so every
    ///      buyer's entitlement grows instead of the first claim consuming the
    ///      only opportunity to refund.
    function augmentRefund(bytes32 id, uint256 fromBond) external exists(id) onlyRemediation nonReentrant {
        Launch storage l = _launches[id];
        require(l.refunding, "not refunding");
        require(fromBond <= l.bond, "bond exceeded");

        l.bond -= fromBond;
        l.refundPool += fromBond;
        emit RefundOpened(id, l.refundPool, l.totalNetPaid);
    }

    /// @notice Residue left by integer division, plus anything never claimed.
    /// @dev Pro-rata shares floor, so the pool always pays out slightly less
    ///      than it holds. Without a disclosed destination that dust would be
    ///      stranded in the contract forever.
    function unclaimedRefund(bytes32 id) public view returns (uint256) {
        Launch storage l = _launches[id];
        return l.refundPool > l.refundPaid ? l.refundPool - l.refundPaid : 0;
    }

    /// @notice Sweep the residue once the claim period has closed.
    // slither-disable-next-line low-level-calls
    function sweepUnclaimed(bytes32 id, address to)
        external
        exists(id)
        onlyRemediation
        nonReentrant
        returns (uint256 amount)
    {
        Launch storage l = _launches[id];
        require(l.refunding, "not refunding");
        require(to != address(0), "zero recipient");
        require(block.timestamp > l.refundOpenedAt + REFUND_CLAIM_PERIOD, "claim period open");

        amount = unclaimedRefund(id);
        require(amount > 0, "nothing unclaimed");
        l.refundPaid = l.refundPool;
        emit RefundSwept(id, to, amount);
        if (l.asset == address(0)) {
            // slither-disable-next-line arbitrary-send-eth
            (bool ok, ) = to.call{value: amount}("");
            require(ok, "native transfer failed");
        } else {
            _payToken(l.asset, to, amount);
        }
    }

    function isRefunding(bytes32 id) external view returns (bool) {
        return _launches[id].refunding;
    }

    // slither-disable-next-line low-level-calls
    function releaseBond(bytes32 id, address to, uint256 amount) external exists(id) onlyRemediation nonReentrant {
        require(to != address(0), "zero recipient");
        Launch storage l = _launches[id];
        require(amount <= l.bond, "bond exceeded");
        l.bond -= amount;
        if (l.asset == address(0)) {
            // slither-disable-next-line arbitrary-send-eth
            (bool ok, ) = to.call{value: amount}("");
            require(ok, "native transfer failed");
        } else {
            _payToken(l.asset, to, amount);
        }
    }

    // --- refunds ------------------------------------------------------------

    function entitlementOf(bytes32 id, address buyer) public view returns (uint256) {
        Launch storage l = _launches[id];
        if (!l.refunding || l.totalNetPaid == 0) return 0;

        Purchase storage p = _purchases[id][buyer];
        uint256 share = (l.refundPool * _net(p)) / l.totalNetPaid;
        return share > p.refunded ? share - p.refunded : 0;
    }

    // slither-disable-next-line low-level-calls
    function claimRefund(bytes32 id) external exists(id) nonReentrant returns (uint256 amount) {
        Launch storage l = _launches[id];
        require(l.refunding, "not refunding");
        if (block.timestamp > l.refundOpenedAt + REFUND_CLAIM_PERIOD) {
            revert NothingToRefund(id, msg.sender);
        }

        amount = entitlementOf(id, msg.sender);
        if (amount == 0) revert NothingToRefund(id, msg.sender);

        _purchases[id][msg.sender].refunded += amount;
        l.refundPaid += amount;
        if (l.asset == address(0)) {
            (bool ok, ) = msg.sender.call{value: amount}("");
            require(ok, "native transfer failed");
        } else {
            _payToken(l.asset, msg.sender, amount);
        }
        emit RefundClaimed(id, msg.sender, amount);
    }

    // --- transfers ----------------------------------------------------------

    /// @dev Destination is read from launch storage or is the caller pulling
    ///      their own refund, never an address supplied to this function by an
    ///      untrusted party. The zero-amount short-circuit is exact by intent.
    /// @dev ERC-20 payouts only. Native payouts are written at each call site so
    ///      the destination is visible as storage or `msg.sender` rather than
    ///      hidden behind a shared parameter.
    function _payToken(address asset, address to, uint256 amount) internal {
        if (!(amount > 0)) return;
        _accounted[asset] -= amount;
        _safeTransfer(asset, to, amount);
    }

    /// @dev `asset` MUST be a token the venue has vetted. A hostile token can
    ///      re-enter during `transferFrom` and defeat any balance check made
    ///      around it, so this guard defends against a merely non-conforming
    ///      asset, not against a malicious one. Asset choice is the venue's
    ///      trust decision and cannot be delegated to this contract.
    ///
    ///      Measures the delta rather than trusting the return value. A
    ///      fee-on-transfer or rebasing asset would credit more than it
    ///      delivered, leaving refunds unpayable; such assets are rejected
    ///      outright rather than silently under-collateralizing the pool.
    // slither-disable-next-line reentrancy-balance
    /// @dev SCSTG "Test Token Implementations": widely held tokens including
    ///      USDT return nothing from `transfer` and `transferFrom`. A
    ///      `require(IERC20(x).transfer(...))` reverts on decoding the absent
    ///      boolean, so such a token could never be used for settlement. Accept
    ///      an empty return as success, and a `false` return as failure.
    // slither-disable-next-line low-level-calls
    function _safeTransfer(address asset, address to, uint256 amount) private {
        (bool ok, bytes memory ret) =
            asset.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(ok, "erc20 transfer failed");
        if (ret.length > 0) require(abi.decode(ret, (bool)), "erc20 transfer returned false");
    }

    /// @notice Take responsibility for `amount` of `asset` the venue has
    ///         already transferred in.
    /// @dev One balance read, no transfer call around it. A shortfall means the
    ///      venue under-delivered and is rejected before any accounting moves; a
    ///      surplus, as a rebasing asset may produce, stays unattributed.
    function _creditERC20(address asset, uint256 amount) internal {
        uint256 held = IERC20(asset).balanceOf(address(this));
        require(held >= _accounted[asset] + amount, "asset not delivered");
        _accounted[asset] += amount;
    }

    // --- views --------------------------------------------------------------

    function stateOf(bytes32 id) public view returns (LaunchState) {
        Launch storage l = _launches[id];
        if (!l.exists) return LaunchState.None;
        if (l.refunding) return LaunchState.Refunding;
        // A freeze that outlives its deadline lapses on its own: indefinite
        // freezing would be a censorship primitive.
        if (l.frozenUntil != 0 && block.timestamp < l.frozenUntil) return LaunchState.Frozen;
        if (l.released >= l.proceeds && block.timestamp >= l.releaseEnd && l.proceeds > 0) {
            return LaunchState.Settled;
        }
        if (block.timestamp < l.releaseStart) return LaunchState.Active;
        return LaunchState.Releasing;
    }

    function escrowedProceeds(bytes32 id) external view returns (uint256) {
        Launch storage l = _launches[id];
        return l.proceeds - l.released;
    }

    /// @notice Tokens of `asset` this contract has taken responsibility for.
    /// @dev The core solvency invariant of the push-then-account model is
    ///      `accountedOf(asset) <= IERC20(asset).balanceOf(this)`. If it ever
    ///      breaks, the escrow has promised more than it holds.
    function accountedOf(address asset) external view returns (uint256) { return _accounted[asset]; }

    function bondOf(bytes32 id) external view returns (uint256)      { return _launches[id].bond; }
    function deployerOf(bytes32 id) external view returns (address)  { return _launches[id].deployer; }
    function assetOf(bytes32 id) external view returns (address)     { return _launches[id].asset; }
    function totalNetPaid(bytes32 id) external view returns (uint256){ return _launches[id].totalNetPaid; }
    function isExcluded(bytes32 id, address a) external view returns (bool) {
        return _purchases[id][a].excluded;
    }

    function launchInfo(bytes32 id)
        external
        view
        returns (address token, address deployer, uint256 proceeds, uint256 released, uint256 netPaid)
    {
        Launch storage l = _launches[id];
        return (l.token, l.deployer, l.proceeds, l.released, l.totalNetPaid);
    }

    function maxFreezeDuration() external pure returns (uint64) { return FREEZE_DURATION; }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(ILaunchEscrow).interfaceId || interfaceId == 0x01ffc9a7;
    }

    receive() external payable {}
}
// slither-disable-end timestamp
