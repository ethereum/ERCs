// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {FinancialLease} from "../../src/FinancialLease.sol";
import {Handler, MockERC20} from "./Handler.sol";

/// @title Invariants and fuzzing
/// @dev INV-LESSEE is a genuine handler-based invariant: it explores
///      random sequences of assignLessee calls from arbitrary
///      callers. It failed before the S4-02 fix and passes after it.
///
///      INV-FREQ (S3-01) does NOT live here as a handler invariant_: it requires
///      comparing TWO identical leases under TWO controlled call
///      cadences (1 vs 90), which is a directed comparison, not
///      a property that emerges from a single random sequence
///      (scenario tests attack specific patterns more effectively
///      than pure fuzzing). It lives in
///      test/invariant/InvFreq.t.sol as a directed test, and is documented
///      here as well because it belongs to the same set of properties.
contract LeaseInvariantsTest is StdInvariant, Test {
    FinancialLease internal lease;
    MockERC20 internal token;
    Handler internal handler;

    function setUp() public {
        lease = new FinancialLease();
        token = new MockERC20();
        handler = new Handler(lease, token);

        targetContract(address(handler));
    }

    /// @dev Regression for S4-02. Before the fix, assignLessee did not
    ///      require the caller to be the outgoing lessee: any caller
    ///      that was the configured defaultDeclarer (by default, the
    ///      lessor) could reassign the lessee without consent.
    function invariant_INV_LESSEE_onlyOutgoingLesseeReassigns() public view {
        uint256 n = handler.leaseIdsLength();
        for (uint256 i = 0; i < n; i++) {
            uint256 id = handler.leaseIdAt(i);
            assertFalse(
                handler.ghost_lesseeHijacked(id),
                "INV-LESSEE violated: assignLessee accepted a caller other than the outgoing lessee (S4-02)"
            );
        }
    }

    /// @dev Sanity invariant (not derived from a
    ///      finding): PurchaseExercised is a genuinely
    ///      absorbing status (see Handler._isAbsorbing) — once reached, it
    ///      must never report another status. Expected to PASS; it serves
    ///      as a check that the harness actually exercises that path
    ///      and that pay()/declareDefault()/
    ///      exercisePurchaseOption() do not overwrite each other (a
    ///      cross-layer check: several functions write
    ///      `status`, each reviewed individually;
    ///      this invariant tests their interaction under
    ///      arbitrary sequences). Note: the first version of this
    ///      invariant also treated Completed as absorbing and
    ///      "failed" — that was a bug in the invariant, not in the contract:
    ///      Completed -> PurchaseExercised is a legitimate transition
    ///      (see the comment in Handler.sol).
    function invariant_statusNeverLeavesTerminal() public view {
        assertFalse(
            handler.ghost_anyTerminalRegression(), "a lease in status PurchaseExercised later reported a different status"
        );
    }
}
