// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {
    IFundMetadata,
    LifecycleState,
    DistributionType,
    DistributionStatus,
    DistributionInfo
} from "./IFundMetadata.sol";

/// @title FundMetadataExample
/// @notice Reference implementation of the ERC-8318 core interface (`IFundMetadata`).
/// @dev The read functions and events are normative per ERC-8318; every write function below (setNav,
/// setLifecycleState, declareDistribution, markDistributionPaid, cancelDistribution,
/// and the parameter setters) is NON-NORMATIVE and only illustrates one admin model.
/// Not audited. Do not use in production without a full security review.
contract FundMetadataExample is IFundMetadata, AccessControl {
    bytes32 public constant FUND_ADMIN_ROLE = keccak256("FUND_ADMIN_ROLE");
    bytes32 public constant NAV_PUBLISHER_ROLE = keccak256("NAV_PUBLISHER_ROLE");
    bytes32 public constant DISTRIBUTION_AGENT_ROLE = keccak256("DISTRIBUTION_AGENT_ROLE");

    error ZeroAddress();
    error FutureNav();
    error ZeroEffectiveAt();
    error NavOutOfOrder();
    error FundClosed();
    error NoNavAtOrBefore(uint256 timestamp);
    error NoOpTransition();
    error IllegalTransition(LifecycleState from, LifecycleState to);
    error BadDistributionDates();
    error UnknownDistribution(uint256 id);
    error DistributionNotPending(uint256 id);
    error BeforeRecordDate(uint256 id);
    error FeeTooHigh();
    error BadWindow();

    struct NavPoint {
        uint256 nav;
        uint8 decimals;
        uint256 effectiveAt;
    }

    uint16 internal constant MAX_BPS = 10_000;

    IERC20 public immutable shareToken;

    // NAV: append-only history sorted by effectiveAt; the last element is the current NAV.
    NavPoint[] private _navHistory;
    uint256 private _stalenessThreshold;
    bytes3 private immutable _currency;

    // Lifecycle
    LifecycleState private _state;
    LifecycleState private _stateBeforePause;
    uint256 private _stateUpdatedAt;

    // Distributions: IDs are 1..count, 0 means "none".
    mapping(uint256 => DistributionInfo) private _distributions;
    uint256 private _distributionCount;
    uint256[] private _pendingIds;
    mapping(uint256 => uint256) private _pendingIndexPlusOne;
    uint256 private _lastPaidId;

    // Fund parameters
    uint16 private _mgmtFeeBps;
    uint16 private _perfFeeBps;
    uint16 private _subFeeBps;
    uint16 private _redFeeBps;
    uint256 private _minInvestment;
    uint8 private _minInvestmentDecimals;
    uint256 private _subOpensAt;
    uint256 private _subClosesAt;
    uint256 private _redOpensAt;
    uint256 private _redClosesAt;
    uint256 private _maturityDate;

    constructor(IERC20 shareToken_, bytes3 currency_, uint256 stalenessThreshold_, address admin) {
        if (address(shareToken_) == address(0) || admin == address(0)) revert ZeroAddress();

        shareToken = shareToken_;
        _currency = currency_;
        _stalenessThreshold = stalenessThreshold_;
        _state = LifecycleState.Pending;
        _stateUpdatedAt = block.timestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FUND_ADMIN_ROLE, admin);
        _grantRole(NAV_PUBLISHER_ROLE, admin);
        _grantRole(DISTRIBUTION_AGENT_ROLE, admin);
    }

    /*//////////////////////////////////////////////////////////////
                                ERC-165
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl, IERC165) returns (bool) {
        return interfaceId == type(IFundMetadata).interfaceId || super.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                               NAV READS
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns (0, 0) before the first NAV is published. Use `navUpdatedAt() == 0`
    /// to distinguish "never published" from a published NAV of zero.
    function navPerShare() external view returns (uint256, uint8) {
        uint256 n = _navHistory.length;
        if (n == 0) return (0, 0);
        NavPoint storage p = _navHistory[n - 1];
        return (p.nav, p.decimals);
    }

    /// @dev Binary search for the latest NAV with effectiveAt <= timestamp.
    /// Reverts with NoNavAtOrBefore if no NAV was effective at or before `timestamp`.
    function navAsOf(uint256 timestamp) external view returns (uint256, uint8) {
        uint256 lo = 0;
        uint256 hi = _navHistory.length;
        while (lo < hi) {
            uint256 mid = (lo + hi) / 2;
            if (_navHistory[mid].effectiveAt <= timestamp) lo = mid + 1;
            else hi = mid;
        }
        if (lo == 0) revert NoNavAtOrBefore(timestamp);
        NavPoint storage p = _navHistory[lo - 1];
        return (p.nav, p.decimals);
    }

    /// @dev Effective timestamp of the current NAV, or 0 if none has been published.
    function navUpdatedAt() public view returns (uint256) {
        uint256 n = _navHistory.length;
        return n == 0 ? 0 : _navHistory[n - 1].effectiveAt;
    }

    /// @dev Stale if no NAV exists, or if its age is strictly greater than the threshold.
    /// effectiveAt <= block.timestamp is enforced on write, so the subtraction cannot underflow.
    function navStale() external view returns (bool) {
        uint256 updatedAt = navUpdatedAt();
        if (updatedAt == 0) return true;
        return block.timestamp - updatedAt > _stalenessThreshold;
    }

    function navStalenessThreshold() external view returns (uint256) {
        return _stalenessThreshold;
    }

    function valuationCurrency() external view returns (bytes3) {
        return _currency;
    }

    /*//////////////////////////////////////////////////////////////
                            LIFECYCLE READS
    //////////////////////////////////////////////////////////////*/

    function lifecycleState() external view returns (LifecycleState) {
        return _state;
    }

    function lifecycleStateUpdatedAt() external view returns (uint256) {
        return _stateUpdatedAt;
    }

    /*//////////////////////////////////////////////////////////////
                           DISTRIBUTION READS
    //////////////////////////////////////////////////////////////*/

    function distributionCount() external view returns (uint256) {
        return _distributionCount;
    }

    /// @dev Reverts with UnknownDistribution for id 0 or id > distributionCount().
    /// A Declared distribution whose exDate has been reached is reported as ExDate.
    function distributionById(uint256 id) external view returns (DistributionInfo memory info) {
        if (id == 0 || id > _distributionCount) revert UnknownDistribution(id);
        info = _distributions[id];
        if (info.status == DistributionStatus.Declared && block.timestamp >= info.exDate) {
            info.status = DistributionStatus.ExDate;
        }
    }

    /// @dev Order is not guaranteed (swap-and-pop removal).
    function pendingDistributionIds() external view returns (uint256[] memory) {
        return _pendingIds;
    }

    function lastDistributionId() external view returns (uint256) {
        return _lastPaidId;
    }

    /// @dev Earliest paymentDate among pending distributions, or 0 if none are pending.
    function nextDistributionDate() external view returns (uint256 next) {
        uint256 n = _pendingIds.length;
        for (uint256 i = 0; i < n; ++i) {
            uint256 p = _distributions[_pendingIds[i]].paymentDate;
            if (next == 0 || p < next) next = p;
        }
    }

    /*//////////////////////////////////////////////////////////////
                              FUND PARAMS
    //////////////////////////////////////////////////////////////*/

    function managementFeeBps() external view returns (uint16) {
        return _mgmtFeeBps;
    }

    function performanceFeeBps() external view returns (uint16) {
        return _perfFeeBps;
    }

    function subscriptionFeeBps() external view returns (uint16) {
        return _subFeeBps;
    }

    function redemptionFeeBps() external view returns (uint16) {
        return _redFeeBps;
    }

    function minInvestment() external view returns (uint256, uint8) {
        return (_minInvestment, _minInvestmentDecimals);
    }

    function subscriptionWindow() external view returns (uint256, uint256) {
        return (_subOpensAt, _subClosesAt);
    }

    function redemptionWindow() external view returns (uint256, uint256) {
        return (_redOpensAt, _redClosesAt);
    }

    function maturityDate() external view returns (uint256) {
        return _maturityDate;
    }

    /*//////////////////////////////////////////////////////////////
                    NON-NORMATIVE WRITE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Publish a NAV. effectiveAt must be > 0, not in the future, and not earlier
    /// than the current NAV. Publishing with the same effectiveAt as the current NAV
    /// replaces it (a correction). Re-publishing identical values is a silent no-op.
    function setNav(uint256 nav_, uint8 decimals_, uint256 effectiveAt) external onlyRole(NAV_PUBLISHER_ROLE) {
        if (_state == LifecycleState.Closed) revert FundClosed();
        if (effectiveAt == 0) revert ZeroEffectiveAt();
        if (effectiveAt > block.timestamp) revert FutureNav();

        uint256 n = _navHistory.length;
        uint256 previousNav;
        if (n != 0) {
            NavPoint storage last = _navHistory[n - 1];
            if (last.nav == nav_ && last.decimals == decimals_ && last.effectiveAt == effectiveAt) return;
            if (effectiveAt < last.effectiveAt) revert NavOutOfOrder();
            previousNav = last.nav;
            if (effectiveAt == last.effectiveAt) {
                last.nav = nav_;
                last.decimals = decimals_;
                emit NavUpdated(previousNav, nav_, decimals_, effectiveAt);
                return;
            }
        }
        _navHistory.push(NavPoint({nav: nav_, decimals: decimals_, effectiveAt: effectiveAt}));
        emit NavUpdated(previousNav, nav_, decimals_, effectiveAt);
    }

    function setLifecycleState(LifecycleState newState) external onlyRole(FUND_ADMIN_ROLE) {
        LifecycleState prev = _state;
        if (newState == prev) revert NoOpTransition();
        if (!_isLegalTransition(prev, newState)) revert IllegalTransition(prev, newState);

        if (newState == LifecycleState.Paused) _stateBeforePause = prev;
        _state = newState;
        _stateUpdatedAt = block.timestamp;

        emit LifecycleStateChanged(prev, newState, block.timestamp);
    }

    function declareDistribution(
        uint256 exDate,
        uint256 recordDate,
        uint256 paymentDate,
        uint256 amountPerShare,
        uint8 amountDecimals,
        bytes3 currency,
        DistributionType distributionType
    ) external onlyRole(FUND_ADMIN_ROLE) returns (uint256 id) {
        if (_state == LifecycleState.Closed) revert FundClosed();
        if (exDate > recordDate || recordDate > paymentDate) revert BadDistributionDates();

        id = ++_distributionCount;
        _distributions[id] = DistributionInfo({
            id: id,
            declaredAt: block.timestamp,
            exDate: exDate,
            recordDate: recordDate,
            paymentDate: paymentDate,
            amountPerShare: amountPerShare,
            amountDecimals: amountDecimals,
            currency: currency,
            distributionType: distributionType,
            status: DistributionStatus.Declared
        });
        _pendingIds.push(id);
        _pendingIndexPlusOne[id] = _pendingIds.length;

        emit DistributionDeclared(
            id, distributionType, exDate, recordDate, paymentDate, amountPerShare, amountDecimals, currency
        );
    }

    /// @notice Record that a distribution has been settled.
    /// @dev This contract does not move cash. The DISTRIBUTION_AGENT_ROLE holder is trusted
    /// to call this only after settlement has actually occurred (on-chain or off-chain).
    /// Production deployments should bind this to verified settlement, e.g. a transfer
    /// performed in the same transaction or a confirmation from the paying agent.
    /// `totalAmount` uses the distribution's own amountDecimals and currency.
    function markDistributionPaid(uint256 id, uint256 totalAmount) external onlyRole(DISTRIBUTION_AGENT_ROLE) {
        DistributionInfo storage d = _pendingDistribution(id);
        if (block.timestamp < d.recordDate) revert BeforeRecordDate(id);

        d.status = DistributionStatus.Paid;
        _removePending(id);
        _lastPaidId = id;

        emit DistributionPaid(id, totalAmount, d.amountDecimals, d.currency, block.timestamp);
    }

    function cancelDistribution(uint256 id, string calldata reason) external onlyRole(FUND_ADMIN_ROLE) {
        DistributionInfo storage d = _pendingDistribution(id);
        d.status = DistributionStatus.Cancelled;
        _removePending(id);

        emit DistributionCancelled(id, reason);
    }

    function setFees(uint16 mgmt, uint16 perf, uint16 sub, uint16 red) external onlyRole(FUND_ADMIN_ROLE) {
        if (mgmt > MAX_BPS || perf > MAX_BPS || sub > MAX_BPS || red > MAX_BPS) revert FeeTooHigh();
        (_mgmtFeeBps, _perfFeeBps, _subFeeBps, _redFeeBps) = (mgmt, perf, sub, red);
    }

    function setMinInvestment(uint256 amount, uint8 decimals) external onlyRole(FUND_ADMIN_ROLE) {
        (_minInvestment, _minInvestmentDecimals) = (amount, decimals);
    }

    /// @dev Pass (0, 0) to clear a window.
    function setWindows(uint256 subOpens, uint256 subCloses, uint256 redOpens, uint256 redCloses)
        external
        onlyRole(FUND_ADMIN_ROLE)
    {
        if (subOpens > subCloses || redOpens > redCloses) revert BadWindow();
        (_subOpensAt, _subClosesAt, _redOpensAt, _redClosesAt) = (subOpens, subCloses, redOpens, redCloses);
    }

    /// @dev Pass 0 for no fixed maturity.
    function setMaturityDate(uint256 date) external onlyRole(FUND_ADMIN_ROLE) {
        _maturityDate = date;
    }

    function setStalenessThreshold(uint256 threshold) external onlyRole(FUND_ADMIN_ROLE) {
        _stalenessThreshold = threshold;
    }

    /*//////////////////////////////////////////////////////////////
                               INTERNALS
    //////////////////////////////////////////////////////////////*/

    function _pendingDistribution(uint256 id) private view returns (DistributionInfo storage d) {
        if (id == 0 || id > _distributionCount) revert UnknownDistribution(id);
        d = _distributions[id];
        if (d.status != DistributionStatus.Declared) revert DistributionNotPending(id);
    }

    function _removePending(uint256 id) private {
        uint256 idx = _pendingIndexPlusOne[id] - 1;
        uint256 lastIdx = _pendingIds.length - 1;
        if (idx != lastIdx) {
            uint256 moved = _pendingIds[lastIdx];
            _pendingIds[idx] = moved;
            _pendingIndexPlusOne[moved] = idx + 1;
        }
        _pendingIds.pop();
        delete _pendingIndexPlusOne[id];
    }

    function _isLegalTransition(LifecycleState from, LifecycleState to) internal view returns (bool) {
        if (from == LifecycleState.Closed) return false;
        if (to == LifecycleState.Paused) return true;
        if (from == LifecycleState.Paused) {
            return to == _stateBeforePause || _isLegalSuccessor(_stateBeforePause, to);
        }
        return _isLegalSuccessor(from, to);
    }

    function _isLegalSuccessor(LifecycleState f, LifecycleState t) internal pure returns (bool) {
        if (f == LifecycleState.Pending) return t == LifecycleState.SubscriptionOpen;
        if (f == LifecycleState.SubscriptionOpen) {
            return t == LifecycleState.SubscriptionClosed || t == LifecycleState.Operating;
        }
        if (f == LifecycleState.SubscriptionClosed) {
            return t == LifecycleState.SubscriptionOpen || t == LifecycleState.Operating
                || t == LifecycleState.RedemptionOnly || t == LifecycleState.WindingDown;
        }
        if (f == LifecycleState.Operating) {
            return t == LifecycleState.SubscriptionOpen || t == LifecycleState.SubscriptionClosed
                || t == LifecycleState.RedemptionOnly || t == LifecycleState.WindingDown;
        }
        if (f == LifecycleState.RedemptionOnly) {
            return t == LifecycleState.Operating || t == LifecycleState.WindingDown;
        }
        if (f == LifecycleState.WindingDown) {
            return t == LifecycleState.RedemptionOnly || t == LifecycleState.Closed;
        }
        return false;
    }
}
