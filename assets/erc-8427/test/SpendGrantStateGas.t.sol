// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {AssetLimit, GrantState, ISpendGrantRegistry, SpendGrant} from "../src/SpendGrantTypes.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";

/// @dev Answers every read with the gas it received at entry, so the caller can see the exact stipend.
contract StipendProbeToken {
    fallback() external {
        assembly {
            mstore(0, gas())
            return(0, 32)
        }
    }
}

/// @dev Burns all the gas it is given.
contract StipendBurnerToken {
    fallback() external {
        assembly {
            for {} 1 {} { mstore(0, keccak256(0, 0x20)) }
        }
    }
}

/// @notice The `grantState` gas guard, swept over the caller's gas limit, warm and cold, stepping by 1 across
/// each transition. Whenever the view returns, each read received the whole stipend. As the gas limit grows,
/// the outcome only moves forward, from out-of-gas to `InsufficientGas()` to a returned state, so a token that
/// burns its stipend never turns a call that passed the guard into an out-of-gas revert.
contract SpendGrantStateGasTest is Test {
    bytes4 internal constant INSUFFICIENT_GAS = bytes4(keccak256("InsufficientGas()"));
    uint256 internal constant READ_STIPEND = 100_000;
    uint256 internal constant OUT_OF_GAS = 0;
    uint256 internal constant GUARDED = 1;
    uint256 internal constant RETURNED = 2;
    uint256 internal constant COARSE_FROM = 1000;
    uint256 internal constant COARSE_STEP = 97;

    SpendGrantRegistry internal registry;
    address internal executor;
    address internal principal;
    address internal delegate;
    address internal payee;

    struct Tally {
        uint256 firstGuarded;
        uint256 firstReturned;
        uint256 firstBurned; // first InsufficientGas after the first read ran (the call used more than a stipend)
        uint256[3] seen; // calls per outcome
        uint256 regressions; // an outcome lower than one already seen at less gas
        uint256 shortReads; // returned, but a read got less than the whole stipend
    }

    function setUp() public {
        vm.warp(1_700_000_000);
        executor = makeAddr("executor");
        principal = makeAddr("principal");
        delegate = makeAddr("delegate");
        payee = makeAddr("payee");
        registry = new SpendGrantRegistry(executor);
    }

    function test_gasGuard_probeGetsFullStipendWheneverStateReturns_warm() public {
        _probeSweep(false);
    }

    function test_gasGuard_probeGetsFullStipendWheneverStateReturns_cold() public {
        _probeSweep(true);
    }

    function test_gasGuard_burnerNeverOutOfGasPastTheGuard_warm() public {
        _burnerSweep(false);
    }

    function test_gasGuard_burnerNeverOutOfGasPastTheGuard_cold() public {
        _burnerSweep(true);
    }

    /// One `grantState` call at `gas`, in its own frame: the outcome, what the view reported, and the gas the
    /// call used.
    function stateAtGas(bytes32 id, address asset, uint256 gas, bool cold)
        external
        returns (
            uint256 outcome,
            uint256 balance,
            uint256 allowance,
            bool balanceKnown,
            bool allowanceKnown,
            uint256 used
        )
    {
        if (cold) {
            vm.cool(address(registry));
            vm.cool(asset);
        }
        bytes memory data = abi.encodeCall(ISpendGrantRegistry.grantState, (id, asset));
        uint256 before = gasleft();
        (bool ok, bytes memory ret) = address(registry).staticcall{gas: gas}(data);
        used = before - gasleft();
        if (ok) {
            GrantState memory s = abi.decode(ret, (GrantState));
            return (RETURNED, s.balance, s.allowance, s.balanceKnown, s.allowanceKnown, used);
        }
        if (ret.length == 4 && bytes4(ret) == INSUFFICIENT_GAS) return (GUARDED, 0, 0, false, false, used);
        assertEq(ret.length, 0, "unexpected revert data");
        return (OUT_OF_GAS, 0, 0, false, false, used);
    }

    function _probeSweep(bool cold) internal {
        StipendProbeToken probe = new StipendProbeToken();
        uint256 full = _probeAt(probe, READ_STIPEND);
        console2.log("gas seen at entry with exactly 100000", full);
        // The probe's answer moves one for one with the gas it is given, so a short stipend would show.
        assertEq(full - _probeAt(probe, READ_STIPEND / 2), READ_STIPEND / 2, "probe does not report its gas");
        _run(address(probe), _register(address(probe)), cold, full);
    }

    function _burnerSweep(bool cold) internal {
        StipendBurnerToken burner = new StipendBurnerToken();
        _run(address(burner), _register(address(burner)), cold, 0);
    }

    function _probeAt(StipendProbeToken probe, uint256 gas) internal view returns (uint256) {
        (bool ok, bytes memory ret) =
            address(probe).staticcall{gas: gas}(abi.encodeWithSignature("balanceOf(address)", principal));
        assertTrue(ok);
        return abi.decode(ret, (uint256));
    }

    /// `full != 0`: every returned read must be known and equal `full`. `full == 0` (burner): never known.
    function _run(address asset, bytes32 id, bool cold, uint256 full) internal {
        // Warm everything grantState touches with one successful call, so the warm sweep is consistent.
        if (!cold) {
            (uint256 o,,,,,) = this.stateAtGas(id, asset, 1_000_000, false);
            assertEq(o, RETURNED);
        }
        Tally memory coarse = _sweep(id, asset, COARSE_FROM, full == 0 ? 260_000 : 160_000, COARSE_STEP, cold, full);
        console2.log(cold ? "cold" : "warm");
        console2.log("  coarse first InsufficientGas", coarse.firstGuarded);
        console2.log("  coarse first success", coarse.firstReturned);
        assertGt(coarse.firstGuarded, COARSE_FROM, "coarse sweep did not start out of gas");
        assertGt(coarse.firstReturned, 0);
        assertEq(coarse.regressions, 0, "coarse: outcome not monotone in gas");
        assertEq(coarse.shortReads, 0, "coarse: short read");

        // Step 1 across out-of-gas -> InsufficientGas.
        uint256 lo = coarse.firstGuarded - 200;
        Tally memory a = _sweep(id, asset, lo, coarse.firstGuarded + 200, 1, cold, full);
        assertGt(a.firstGuarded, lo, "fine range did not start out of gas");
        assertGt(a.seen[OUT_OF_GAS], 0);
        assertGt(a.seen[GUARDED], 0);
        // Step 1 across InsufficientGas -> success; the transition is within one coarse step below
        // coarse.firstReturned, and the range starts well below that.
        lo = coarse.firstReturned - 1500;
        Tally memory b = _sweep(id, asset, lo, coarse.firstReturned + 300, 1, cold, full);
        assertGt(b.firstReturned, lo, "fine range did not bracket the transition");
        assertGt(b.seen[GUARDED], 0);
        assertGt(b.seen[RETURNED], 0);
        console2.log("  exact first InsufficientGas", a.firstGuarded);
        console2.log("  exact first success", b.firstReturned);
        assertEq(a.regressions + b.regressions, 0, "fine: outcome not monotone in gas");
        assertEq(a.shortReads + b.shortReads, 0, "fine: short read");

        if (full == 0) {
            // Step 1 across the gas limit at which the first read first runs: the burner then leaves the
            // least gas for the rest of the call, so an out-of-gas after the first guard would start here.
            assertGt(coarse.firstBurned, 0, "first read never ran");
            lo = coarse.firstBurned - 200;
            Tally memory c = _sweep(id, asset, lo, coarse.firstBurned + 200, 1, cold, full);
            assertGt(c.firstBurned, lo, "fine range did not start before the first read");
            assertEq(c.seen[GUARDED], 400, "first read boundary: not InsufficientGas throughout");
            assertEq(c.regressions, 0, "first read boundary: outcome not monotone in gas");
            console2.log("  exact first InsufficientGas after the first read", c.firstBurned);
        }
    }

    function _sweep(bytes32 id, address asset, uint256 lo, uint256 hi, uint256 step, bool cold, uint256 full)
        internal
        returns (Tally memory t)
    {
        uint256 phase;
        for (uint256 gas = lo; gas < hi; gas += step) {
            (uint256 o, uint256 b, uint256 a, bool bk, bool ak, uint256 used) = this.stateAtGas(id, asset, gas, cold);
            t.seen[o]++;
            if (o == RETURNED) {
                if (t.firstReturned == 0) t.firstReturned = gas;
                if (full != 0) {
                    if (!(bk && ak && b == full && a == full)) {
                        if (t.shortReads == 0) console2.log("short read at gas", gas, b, a);
                        t.shortReads++;
                    }
                } else {
                    assertFalse(bk || ak, "burner reported known");
                }
            }
            if (o == GUARDED && t.firstGuarded == 0) t.firstGuarded = gas;
            if (o == GUARDED && used > READ_STIPEND && t.firstBurned == 0) t.firstBurned = gas;
            if (o < phase) {
                if (t.regressions == 0) console2.log("regression at gas", gas, o, phase);
                t.regressions++;
            }
            if (o > phase) phase = o;
        }
    }

    function _register(address asset) internal returns (bytes32 id) {
        SpendGrant memory g;
        g.principal = principal;
        g.delegate = delegate;
        g.recipient = payee;
        g.windowSeconds = 1 days;
        g.assets = new AssetLimit[](1);
        g.assets[0] = AssetLimit(asset, 100, 1000, 5000);
        g.validAfter = uint64(vm.getBlockTimestamp());
        g.validUntil = uint64(vm.getBlockTimestamp() + 30 days);
        g.salt = 1;
        vm.prank(principal);
        id = registry.register(g);
    }
}
