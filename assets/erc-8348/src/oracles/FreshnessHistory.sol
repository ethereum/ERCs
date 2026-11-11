// SPDX-License-Identifier: CC0-1.0
// src/oracles/FreshnessHistory.sol
pragma solidity ^0.8.24;

import {AggregatorV3Interface} from "./ChainlinkConversionOracle.sol";

/// @notice Walks an observation history backwards to answer
///         IConversionOracleHistory.continuouslyFresh.
/// @dev Both walks start at the latest observation and stop after MAX_STEPS
///      observations (counting those after `to`), then return false
///      (fail-closed: the lease reads false as "recovery not proven" and keeps
///      default blocked). Configure maxOracleStaleness so the recovery grace
///      (maxOracleStaleness / 2 in the reference lease) spans well under
///      MAX_STEPS observations of the feed in use.
error NoRoundHistory();

library FreshnessHistory {
    uint256 internal constant MAX_STEPS = 256;

    /// @dev `asOfs` is append-only and non-decreasing (attested/mock oracles).
    function walkStored(uint64[] storage asOfs, uint64 from, uint64 to, uint64 tolerance)
        internal
        view
        returns (bool)
    {
        uint256 n = asOfs.length;
        uint256 cursor = to;
        uint256 end = n > MAX_STEPS ? n - MAX_STEPS : 0;
        for (uint256 k = n; k > end; k--) {
            uint256 a = asOfs[k - 1];
            if (a > cursor) continue; // after the window (or out of order)
            // Stale iff the gap exceeds the tolerance: at timestamp `cursor`, a
            // transaction ordered before the update sees an observation of age
            // cursor - a, exactly as the lease's own staleness check does.
            if (cursor - a > tolerance) return false;
            if (a <= from) return true; // this observation covers back to `from`
            cursor = a;
        }
        return false;
    }

    /// @dev Chainlink-style feed. A round with answer <= 0 or updatedAt == 0
    ///      is one during which latestRate reverts, so pay() was impossible:
    ///      reaching such a round inside the window returns false, exactly as a
    ///      stale interval does. The walk does not cross a phase boundary
    ///      (aggregator round id 1); reaching it returns false. It never
    ///      reverts: failing feed calls return false.
    function walkFeed(AggregatorV3Interface feed, uint64 from, uint64 to, uint64 tolerance)
        internal
        view
        returns (bool)
    {
        uint80 rid;
        int256 answer;
        uint256 upd;
        try feed.latestRoundData() returns (uint80 r_, int256 a_, uint256, uint256 u_, uint80) {
            (rid, answer, upd) = (r_, a_, u_);
        } catch {
            return false;
        }
        uint256 cursor = to;
        for (uint256 steps; steps < MAX_STEPS; steps++) {
            if (upd == 0 || upd <= cursor) {
                // in force during [upd, cursor): unusable -> path unavailable
                if (answer <= 0 || upd == 0) return false;
                if (cursor - upd > tolerance) return false;
                if (upd <= from) return true;
                cursor = upd;
            }
            if (uint64(rid) <= 1) return false; // first round of the phase
            rid--;
            try feed.getRoundData(rid) returns (uint80, int256 a_, uint256, uint256 u_, uint80) {
                answer = a_;
                upd = u_;
            } catch {
                return false;
            }
        }
        return false;
    }

    /// @dev Origination-time probe used by the adapters' constructors: the
    ///      feed must expose a non-zero round id and serve that round through
    ///      getRoundData, otherwise walkFeed could never look past the latest
    ///      round and default could stay blocked for good.
    function requireRoundHistory(AggregatorV3Interface feed) internal view {
        (uint80 rid,,, uint256 upd,) = feed.latestRoundData();
        if (uint64(rid) == 0) revert NoRoundHistory();
        try feed.getRoundData(rid) returns (uint80, int256, uint256, uint256 u_, uint80) {
            if (u_ != upd) revert NoRoundHistory();
        } catch {
            revert NoRoundHistory();
        }
    }
}
