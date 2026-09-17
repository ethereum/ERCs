// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AssetLimit, Mandate, WAD} from "../src/MandateTypes.sol";
import {MandateHash} from "../src/MandateHash.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {MockERC20} from "./MockERC20.sol";

contract MandateHandler is Test {
    uint256 internal constant PRINCIPAL_PK = 0xA11CE;

    MandateRegistry public registry;
    MockERC20 public token;

    address public principal;
    address public delegate;
    address public recipient;

    Mandate public andMandate;
    Mandate public orMandate;
    bytes public andSig;
    bytes public orSig;
    bytes32 public andHash;
    bytes32 public orHash;

    constructor() {
        principal = vm.addr(PRINCIPAL_PK);
        delegate = vm.addr(0xB0B);
        recipient = vm.addr(0xC0C);
        token = new MockERC20();
        registry = new MandateRegistry(address(this));

        vm.warp(1_700_000_100);

        andMandate = _build(0, 1);
        orMandate = _build(1, 2);
        andSig = _sign(andMandate);
        orSig = _sign(orMandate);
        andHash = MandateHash.digest(block.chainid, address(registry), andMandate);
        orHash = MandateHash.digest(block.chainid, address(registry), orMandate);
    }

    function consumeAnd(uint256 assetPick, uint256 amount, uint256 dt) external {
        _consume(andMandate, andSig, andHash, false, assetPick, amount, dt);
    }

    function consumeOr(uint256 assetPick, uint256 amount, uint256 dt) external {
        _consume(orMandate, orSig, orHash, true, assetPick, amount, dt);
    }

    function andCap(uint256 i) external view returns (address asset, uint256 maxPerWindow, uint256 maxTotal) {
        AssetLimit memory a = andMandate.assets[i];
        return (a.asset, a.maxPerWindow, a.maxTotal);
    }

    function orCap(uint256 i) external view returns (address asset, uint256 maxPerWindow, uint256 maxTotal) {
        AssetLimit memory a = orMandate.assets[i];
        return (a.asset, a.maxPerWindow, a.maxTotal);
    }

    function _consume(
        Mandate memory m,
        bytes memory sig,
        bytes32 h,
        bool pie,
        uint256 assetPick,
        uint256 amount,
        uint256 dt
    ) internal {
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
        if (liveCalls >= 256) return;

        if (pie) {
            (uint256 lifePie, uint256 winPie) = registry.pieUsed(h);
            uint256 wAdd = (amount * WAD + lim.maxPerWindow - 1) / lim.maxPerWindow;
            uint256 tAdd = (amount * WAD + lim.maxTotal - 1) / lim.maxTotal;
            if (winPie + wAdd > WAD) return;
            if (lifePie + tAdd > WAD) return;
        } else {
            (uint256 spent,) = registry.usage(h, lim.asset);
            (uint256 rolling,) = registry.rollingUsage(h, lim.asset);
            if (rolling + amount > lim.maxPerWindow) return;
            if (spent + amount > lim.maxTotal) return;
        }

        registry.consume(m, sig, lim.asset, amount, m.recipient);
    }

    function _build(uint8 combine, uint256 salt) internal view returns (Mandate memory m) {
        m.principal = principal;
        m.delegate = delegate;
        m.recipientMode = 0;
        m.recipient = recipient;
        m.assetCombine = combine;
        m.windowSeconds = 86400;
        m.validAfter = 1_700_000_000;
        m.validUntil = 1_900_000_000;
        m.salt = salt;
        m.renderingHash = bytes32(salt);
        m.assets = new AssetLimit[](2);
        m.assets[0] = AssetLimit(address(0), 1 ether, 10 ether, 100 ether);
        m.assets[1] = AssetLimit(address(token), 1e18, 10e18, 100e18);
    }

    function _sign(Mandate memory m) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(PRINCIPAL_PK, MandateHash.digest(block.chainid, address(registry), m));
        return abi.encodePacked(r, s, v);
    }
}

contract MandateInvariantTest is Test {
    MandateHandler internal handler;

    function setUp() public {
        handler = new MandateHandler();
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = MandateHandler.consumeAnd.selector;
        selectors[1] = MandateHandler.consumeOr.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_spentLeMaxTotal() public view {
        _assertSpent(handler.andHash(), false);
        _assertSpent(handler.orHash(), true);
    }

    function invariant_rollingLeMaxPerWindow() public view {
        _assertRolling(handler.andHash(), false);
        _assertRolling(handler.orHash(), true);
    }

    function invariant_pieUsedLeWad() public view {
        (uint256 lifePie, uint256 winPie) = handler.registry().pieUsed(handler.orHash());
        assertLe(lifePie, WAD);
        assertLe(winPie, WAD);
        (lifePie, winPie) = handler.registry().pieUsed(handler.andHash());
        assertEq(lifePie, 0);
        assertEq(winPie, 0);
    }

    function _assertSpent(bytes32 h, bool orCombine) internal view {
        for (uint256 i = 0; i < 2; i++) {
            (address asset,, uint256 maxTotal) = orCombine ? handler.orCap(i) : handler.andCap(i);
            (uint256 spent,) = handler.registry().usage(h, asset);
            assertLe(spent, maxTotal);
        }
    }

    function _assertRolling(bytes32 h, bool orCombine) internal view {
        for (uint256 i = 0; i < 2; i++) {
            (address asset, uint256 maxPerWindow,) = orCombine ? handler.orCap(i) : handler.andCap(i);
            (uint256 rolling,) = handler.registry().rollingUsage(h, asset);
            assertLe(rolling, maxPerWindow);
        }
    }
}
