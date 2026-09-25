// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AssetLimit, MAX_LIVE_DEBITS, NATIVE, SpendGrant} from "../src/SpendGrantTypes.sol";
import {SpendGrantHash} from "../src/SpendGrantHash.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";
import {MockERC20} from "./MockERC20.sol";

contract SpendGrantHandler is Test {
    uint256 internal constant PRINCIPAL_PK = 0xA11CE;

    SpendGrantRegistry public registry;
    MockERC20 public token;

    address public principal;
    address public delegate;
    address public recipient;

    SpendGrant public andGrant;
    bytes public andSig;
    bytes32 public andHash;

    // A second grant with a small window and a maxPerCall of 1, so the fuzzer actually churns
    // the ring through frequent eviction. At the configured invariant depth (16 calls per run,
    // foundry.toml [invariant]) this cannot fill or wrap a 1024-slot ring; exhaustive fill/wrap
    // coverage lives in test/SpendGrantRing.t.sol, not here.
    SpendGrant public ringGrant;
    bytes public ringSig;
    bytes32 public ringHash;

    constructor() {
        principal = vm.addr(PRINCIPAL_PK);
        delegate = vm.addr(0xB0B);
        recipient = vm.addr(0xC0C);
        token = new MockERC20();
        registry = new SpendGrantRegistry(address(this));

        vm.warp(1_700_000_100);

        andGrant = _build(1);
        andSig = _sign(andGrant);
        andHash = SpendGrantHash.digest(block.chainid, address(registry), andGrant);

        ringGrant = _buildRing(2);
        ringSig = _sign(ringGrant);
        ringHash = SpendGrantHash.digest(block.chainid, address(registry), ringGrant);
    }

    function consumeAnd(uint256 assetPick, uint256 amount, uint256 dt) external {
        _consume(andGrant, andSig, andHash, assetPick, amount, dt);
    }

    function consumeRing(uint256 assetPick, uint256 dt) external {
        _consume(ringGrant, ringSig, ringHash, assetPick, 1, dt);
    }

    function andCap(uint256 i) external view returns (address asset, uint256 maxPerWindow, uint256 maxTotal) {
        AssetLimit memory a = andGrant.assets[i];
        return (a.asset, a.maxPerWindow, a.maxTotal);
    }

    function ringCap(uint256 i) external view returns (address asset, uint256 maxPerWindow, uint256 maxTotal) {
        AssetLimit memory a = ringGrant.assets[i];
        return (a.asset, a.maxPerWindow, a.maxTotal);
    }

    function _consume(SpendGrant memory m, bytes memory sig, bytes32 h, uint256 assetPick, uint256 amount, uint256 dt)
        internal
    {
        uint256 ts = vm.getBlockTimestamp();
        dt = bound(dt, 0, uint256(m.windowSeconds) * 2);
        uint256 next = ts + dt;
        if (next >= m.validUntil) next = m.validUntil - 1;
        if (next < m.validAfter) next = m.validAfter;
        vm.warp(next);

        uint256 idx = bound(assetPick, 0, 1);
        AssetLimit memory lim = m.assets[idx];
        amount = bound(amount, 1, lim.maxPerCall);

        (, uint256 liveCalls) = registry.rollingUsage(h, lim.asset);
        if (liveCalls >= MAX_LIVE_DEBITS) return;

        (uint256 spent,) = registry.usage(h, lim.asset);
        (uint256 rolling,) = registry.rollingUsage(h, lim.asset);
        if (rolling + amount > lim.maxPerWindow) return;
        if (spent + amount > lim.maxTotal) return;

        registry.consume(m, sig, lim.asset, amount, m.recipient);
    }

    function _build(uint256 salt) internal view returns (SpendGrant memory m) {
        m.principal = principal;
        m.delegate = delegate;
        m.recipientMode = 0;
        m.recipient = recipient;
        m.assetCombine = 0;
        m.windowSeconds = 86400;
        m.validAfter = 1_700_000_000;
        m.validUntil = 1_900_000_000;
        m.salt = salt;
        m.assets = new AssetLimit[](2);
        m.assets[0] = AssetLimit(address(token), 1e18, 10e18, 100e18);
        m.assets[1] = AssetLimit(NATIVE, 1 ether, 10 ether, 100 ether);
    }

    /// @dev maxPerCall 1, small windowSeconds: unlike `_build`'s wide per-call caps, this shape
    /// drives real eviction traffic through the ring at invariant depth. It does not reach a full
    /// ring (1024 live) or a wrap at depth 16; see test/SpendGrantRing.t.sol for that coverage.
    function _buildRing(uint256 salt) internal view returns (SpendGrant memory m) {
        m.principal = principal;
        m.delegate = delegate;
        m.recipientMode = 0;
        m.recipient = recipient;
        m.assetCombine = 0;
        m.windowSeconds = 8;
        m.validAfter = 1_700_000_000;
        m.validUntil = 1_900_000_000;
        m.salt = salt;
        m.assets = new AssetLimit[](2);
        m.assets[0] = AssetLimit(address(token), 1, 2000, type(uint192).max);
        m.assets[1] = AssetLimit(NATIVE, 1, 2000, type(uint192).max);
    }

    function _sign(SpendGrant memory m) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(PRINCIPAL_PK, SpendGrantHash.digest(block.chainid, address(registry), m));
        return abi.encodePacked(r, s, v);
    }
}

contract SpendGrantInvariantTest is Test {
    SpendGrantHandler internal handler;

    function setUp() public {
        handler = new SpendGrantHandler();
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = SpendGrantHandler.consumeAnd.selector;
        selectors[1] = SpendGrantHandler.consumeRing.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_spentLeMaxTotal() public view {
        _assertSpent(handler.andHash(), false);
        _assertSpent(handler.ringHash(), true);
    }

    function invariant_rollingLeMaxPerWindow() public view {
        _assertRolling(handler.andHash(), false);
        _assertRolling(handler.ringHash(), true);
    }

    function invariant_liveCallsNeverExceedsMaxLiveDebits() public view {
        _assertLiveBound(handler.andHash(), false);
        _assertLiveBound(handler.ringHash(), true);
    }

    function _assertSpent(bytes32 h, bool ring) internal view {
        for (uint256 i = 0; i < 2; i++) {
            (address asset,, uint256 maxTotal) = ring ? handler.ringCap(i) : handler.andCap(i);
            (uint256 spent,) = handler.registry().usage(h, asset);
            assertLe(spent, maxTotal);
        }
    }

    function _assertRolling(bytes32 h, bool ring) internal view {
        for (uint256 i = 0; i < 2; i++) {
            (address asset, uint256 maxPerWindow,) = ring ? handler.ringCap(i) : handler.andCap(i);
            (uint256 rolling,) = handler.registry().rollingUsage(h, asset);
            assertLe(rolling, maxPerWindow);
        }
    }

    function _assertLiveBound(bytes32 h, bool ring) internal view {
        for (uint256 i = 0; i < 2; i++) {
            (address asset,,) = ring ? handler.ringCap(i) : handler.andCap(i);
            (uint256 rolling, uint256 liveCalls) = handler.registry().rollingUsage(h, asset);
            assertLe(liveCalls, MAX_LIVE_DEBITS);
            (uint256 spent,) = handler.registry().usage(h, asset);
            assertLe(rolling, spent);
        }
    }
}
