// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AssetLimit, GrantState, ISpendGrantRegistry, Reason, SpendGrant} from "../src/SpendGrantTypes.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";
import {SpendGrantExecutor} from "../src/SpendGrantExecutor.sol";
import {SpendGrantRedemptionEnforcer} from "../src/SpendGrantRedemptionEnforcer.sol";
import {SpendGrantRedemptionExecutor} from "../src/SpendGrantRedemptionExecutor.sol";
import {MockERC20} from "./MockERC20.sol";
import {MockDelegationManager, MockDeleGator} from "./SpendGrantRedemption.t.sol";

// Lifecycle interleavings: the principal changes or revokes a grant while a spend is in flight (from inside the
// token movement, between batch entries, and between the redemption record write and the execution), and a token
// re-enters `grantState` from inside the view's own read. Also pins the single-payment limit that `grantState`
// documents. Adopted from the final lifecycle review's proof-of-concept tests.

interface ISendHook {
    function onSend() external;
}

interface IReceiveHook {
    function onReceive() external;
}

/// Calls the sender back, then the recipient, after each transferFrom (ERC-777 style hooks).
contract TwoHookERC20 is MockERC20 {
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        if (from.code.length > 0) ISendHook(from).onSend();
        if (to.code.length > 0) IReceiveHook(to).onReceive();
        return true;
    }
}

/// A contract principal that makes one armed registry call from inside the token's sender hook.
contract HookedPrincipal {
    address internal immutable REGISTRY;
    bytes internal _call;
    bool public callOk;
    bytes public callRet;

    constructor(address registry_) {
        REGISTRY = registry_;
    }

    function approve(MockERC20 token, address spender) external {
        token.approve(spender, type(uint256).max);
    }

    function register(SpendGrant calldata g) external returns (bytes32) {
        return ISpendGrantRegistry(REGISTRY).register(g);
    }

    function arm(bytes calldata data) external {
        _call = data;
    }

    function onSend() external {
        bytes memory data = _call;
        if (data.length == 0) return;
        delete _call;
        (callOk, callRet) = REGISTRY.call(data);
    }
}

/// A contract delegate that, as the recipient, re-enters the executor once from the token's recipient hook,
/// after asking `check` about exactly that nested spend.
contract ReenteringDelegate {
    SpendGrantExecutor internal immutable EXECUTOR;
    ISpendGrantRegistry internal immutable REGISTRY;
    bytes32 internal grantId;
    address internal asset;
    uint256 internal nestedAmount;
    bool internal armed;
    bool public checked;
    bool public checkOk;
    uint8 public checkReason;
    bool public nestedOk;
    bytes public nestedErr;

    constructor(SpendGrantExecutor executor_, ISpendGrantRegistry registry_) {
        EXECUTOR = executor_;
        REGISTRY = registry_;
    }

    function arm(bytes32 id, address a, uint256 amount) external {
        (grantId, asset, nestedAmount, armed) = (id, a, amount, true);
    }

    function spend(bytes32 id, address a, uint256 amount, address to) external {
        EXECUTOR.spend(id, a, amount, to);
    }

    function onReceive() external {
        if (!armed) return;
        armed = false;
        (bool ok, Reason r) = REGISTRY.check(grantId, address(this), asset, nestedAmount, address(this));
        (checked, checkOk, checkReason) = (true, ok, uint8(r));
        try EXECUTOR.spend(grantId, asset, nestedAmount, address(this)) {
            nestedOk = true;
        } catch (bytes memory err) {
            nestedErr = err;
        }
    }
}

/// A principal smart account (driven by the manager) whose sender hook makes one armed registry call and then
/// one armed executor call as itself.
contract HookedDeleGator is MockDeleGator {
    address internal immutable REG;
    address internal immutable EXEC;
    bytes internal _regCall;
    bytes internal _execCall;
    bool public regOk;
    bytes public regRet;
    bool public execOk;
    bytes public execRet;

    constructor(address manager_, address owner_, address reg_, address exec_) MockDeleGator(manager_, owner_) {
        REG = reg_;
        EXEC = exec_;
    }

    function arm(bytes calldata regCall, bytes calldata execCall) external {
        (_regCall, _execCall) = (regCall, execCall);
    }

    function onSend() external {
        bytes memory r = _regCall;
        bytes memory e = _execCall;
        delete _regCall;
        delete _execCall;
        if (r.length > 0) (regOk, regRet) = REG.call(r);
        if (e.length > 0) (execOk, execRet) = EXEC.call(e);
    }
}

/// A second caveat on the principal's root delegation: in its beforeHook (after the record is written, before
/// the execution) it redeems a delegation the principal gave it, whose execution is a registry call.
contract UpdaterCaveat {
    MockDelegationManager internal immutable MANAGER;
    bytes internal _ctx;
    bytes internal _exec;
    bool internal _armed;

    constructor(MockDelegationManager manager_) {
        MANAGER = manager_;
    }

    function arm(bytes memory ctx, bytes memory exec) external {
        (_ctx, _exec, _armed) = (ctx, exec, true);
    }

    function beforeAllHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address)
        external
    {}

    function beforeHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address) external {
        if (!_armed) return;
        _armed = false;
        bytes[] memory cs = new bytes[](1);
        cs[0] = _ctx;
        bytes32[] memory ms = new bytes32[](1);
        bytes[] memory es = new bytes[](1);
        es[0] = _exec;
        MANAGER.redeemDelegations(cs, ms, es);
    }

    function afterHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address) external {}

    function afterAllHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address)
        external
    {}
}

/// balanceOf asks the registry for this very grantState from inside the outer read's STATICCALL and answers
/// with what happened (1 returned, 2 InsufficientGas, 3 other); allowance bubbles the inner revert verbatim.
contract ReentrantReadToken {
    ISpendGrantRegistry public registry;
    bytes32 public id;

    function set(ISpendGrantRegistry r, bytes32 i) external {
        (registry, id) = (r, i);
    }

    function balanceOf(address) external view returns (uint256) {
        (bool ok, bytes memory ret) =
            address(registry).staticcall(abi.encodeCall(ISpendGrantRegistry.grantState, (id, address(this))));
        if (ok) return 1;
        if (ret.length == 4 && bytes4(ret) == bytes4(keccak256("InsufficientGas()"))) return 2;
        return 3;
    }

    function allowance(address, address) external view returns (uint256) {
        (bool ok, bytes memory ret) =
            address(registry).staticcall(abi.encodeCall(ISpendGrantRegistry.grantState, (id, address(this))));
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
        return 1;
    }
}

bytes4 constant SPEND_GRANT_ERROR = bytes4(keccak256("SpendGrantError(uint8)"));

function sgErr(uint8 reason) pure returns (bytes memory) {
    return abi.encodeWithSelector(SPEND_GRANT_ERROR, reason);
}

/// Direct executor: the principal changes the grant from inside the movement, then the delegate re-enters.
/// P-EQ must hold for the nested spend against the just-changed terms; the outer debit stands.
contract SpendGrantDirectInterleavingTest is Test {
    SpendGrantRegistry internal registry;
    SpendGrantExecutor internal executor;
    TwoHookERC20 internal token;
    MockERC20 internal other;
    HookedPrincipal internal principal;
    ReenteringDelegate internal delegate;
    bytes32 internal id;

    function setUp() public {
        vm.warp(1_700_000_000);
        token = new TwoHookERC20();
        other = new MockERC20();
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        registry = new SpendGrantRegistry(predicted);
        executor = new SpendGrantExecutor(registry);
        assertEq(address(executor), predicted);
        principal = new HookedPrincipal(address(registry));
        delegate = new ReenteringDelegate(executor, registry);
        token.mint(address(principal), 1e6);
        principal.approve(token, address(executor));
        id = principal.register(_terms(100, 1000, 1000));
    }

    function _terms(uint256 perCall, uint256 perWindow, uint256 total) internal view returns (SpendGrant memory g) {
        uint64 t = uint64(vm.getBlockTimestamp());
        g.principal = address(principal);
        g.delegate = address(delegate);
        g.recipientMode = 1;
        g.windowSeconds = 1 days;
        g.validAfter = t - 1;
        g.validUntil = t + 30 days;
        g.salt = 1;
        g.assets = new AssetLimit[](1);
        g.assets[0] = AssetLimit(address(token), perCall, perWindow, total);
    }

    function _run(bytes memory principalCall, uint256 nestedAmount) internal {
        principal.arm(principalCall);
        delegate.arm(id, address(token), nestedAmount);
        delegate.spend(id, address(token), 100, address(delegate));
        assertTrue(principal.callOk(), "principal's in-hook registry call failed");
        assertTrue(delegate.checked(), "nested path not reached");
        // P-EQ inside the callback, right after the terms changed.
        if (delegate.checkOk()) {
            assertTrue(delegate.nestedOk(), "check OK but nested consume failed");
        } else {
            assertFalse(delegate.nestedOk(), "check failed but nested consume succeeded");
            assertEq(delegate.nestedErr(), sgErr(delegate.checkReason()), "nested revert differs from check");
        }
    }

    function test_principalLowersCapsInsideMove_nestedSpendMatchesCheck() public {
        _run(abi.encodeCall(ISpendGrantRegistry.update, (id, 1, _terms(100, 100, 100))), 1);
        assertEq(delegate.checkReason(), 9); // window cap now full with the outer 100
        (uint256 spent, uint256 calls) = registry.usage(id, address(token));
        assertEq(spent, 100);
        assertEq(calls, 1);
    }

    function test_principalRevokesInsideMove_nestedSpendMatchesCheck() public {
        _run(abi.encodeCall(ISpendGrantRegistry.revoke, (id)), 1);
        assertEq(delegate.checkReason(), 5);
        assertTrue(registry.revoked(id));
        (uint256 spent, uint256 calls) = registry.usage(id, address(token));
        assertEq(spent, 100);
        assertEq(calls, 1);
    }

    function test_principalRemovesAssetInsideMove_nestedSpendMatchesCheck() public {
        SpendGrant memory g = _terms(100, 1000, 1000);
        g.assets[0] = AssetLimit(address(other), 100, 1000, 1000);
        _run(abi.encodeCall(ISpendGrantRegistry.update, (id, 1, g)), 1);
        assertEq(delegate.checkReason(), 6);
    }

    function test_principalPausesInsideMove_nestedSpendMatchesCheck() public {
        SpendGrant memory g = _terms(100, 1000, 1000);
        g.validAfter = uint64(vm.getBlockTimestamp() + 10);
        _run(abi.encodeCall(ISpendGrantRegistry.update, (id, 1, g)), 1);
        assertEq(delegate.checkReason(), 3);
    }

    function test_principalRaisesCapsInsideMove_nestedSpendUsesNewTerms() public {
        // 150 is over the old per-call cap; the raise lands inside the movement, before the nested spend.
        (bool before,) = registry.check(id, address(delegate), address(token), 150, address(delegate));
        assertFalse(before);
        _run(abi.encodeCall(ISpendGrantRegistry.update, (id, 1, _terms(200, 2000, 2000))), 150);
        assertTrue(delegate.nestedOk());
        (uint256 spent, uint256 calls) = registry.usage(id, address(token));
        assertEq(spent, 250);
        assertEq(calls, 2);
        (, uint256 version,,,) = registry.getGrant(id);
        assertEq(version, 2);
    }
}

/// ERC-7710 path: state changes inside the movement, between batch entries, and between the record write and
/// the execution.
contract SpendGrantRedemptionInterleavingTest is Test {
    uint256 internal constant OWNER_PK = 0xA11CE;

    MockDelegationManager internal manager;
    SpendGrantRegistry internal registry;
    SpendGrantRedemptionEnforcer internal enforcer;
    SpendGrantRedemptionExecutor internal executor;
    TwoHookERC20 internal token;
    MockERC20 internal other;
    HookedDeleGator internal account;
    UpdaterCaveat internal updater;
    address internal delegate;
    address internal recipient;
    bytes32 internal id;

    function setUp() public {
        vm.warp(1_700_000_000);
        delegate = vm.addr(0xB0B);
        recipient = vm.addr(0xC0C);
        token = new TwoHookERC20();
        other = new MockERC20();
        manager = new MockDelegationManager();
        uint64 nonce = vm.getNonce(address(this));
        address predicted = vm.computeCreateAddress(address(this), nonce + 2);
        registry = new SpendGrantRegistry(predicted);
        enforcer = new SpendGrantRedemptionEnforcer(address(manager), predicted, address(registry));
        executor = new SpendGrantRedemptionExecutor(registry, enforcer);
        assertEq(address(executor), predicted);
        account = new HookedDeleGator(address(manager), vm.addr(OWNER_PK), address(registry), address(executor));
        updater = new UpdaterCaveat(manager);
        token.mint(address(account), 1e24);
        vm.prank(address(account));
        token.approve(address(executor), type(uint256).max);
        vm.prank(address(account));
        id = registry.register(_terms(1e18, 10e18, 100e18, address(token)));
    }

    function _terms(uint256 perCall, uint256 perWindow, uint256 total, address asset)
        internal
        view
        returns (SpendGrant memory g)
    {
        g.principal = address(account);
        g.delegate = delegate;
        g.recipientMode = 0;
        g.recipient = recipient;
        g.windowSeconds = 1 days;
        g.validAfter = 1_699_999_000;
        g.validUntil = 1_900_000_000;
        g.salt = 1;
        g.assets = new AssetLimit[](1);
        g.assets[0] = AssetLimit(asset, perCall, perWindow, total);
    }

    function _spendExec(uint256 amount) internal view returns (bytes memory) {
        return abi.encodePacked(
            address(executor),
            uint256(0),
            abi.encodeCall(SpendGrantExecutor.spend, (id, address(token), amount, recipient))
        );
    }

    function _registryExec(bytes memory data) internal view returns (bytes memory) {
        return abi.encodePacked(address(registry), uint256(0), data);
    }

    function _root(address delegate_, address[] memory enforcers)
        internal
        view
        returns (MockDelegationManager.Delegation[] memory chain)
    {
        chain = new MockDelegationManager.Delegation[](1);
        chain[0].delegate = delegate_;
        chain[0].delegator = address(account);
        chain[0].authority = manager.ROOT_AUTHORITY();
        chain[0].caveats = new MockDelegationManager.Caveat[](enforcers.length);
        for (uint256 i = 0; i < enforcers.length; i++) {
            chain[0].caveats[i] = MockDelegationManager.Caveat(enforcers[i], "", "");
        }
        bytes memory self = abi.encode(chain[0]);
        for (uint256 i = 0; i < enforcers.length; i++) {
            if (enforcers[i] == address(enforcer)) chain[0].caveats[i].args = self;
        }
    }

    function _withCaveat() internal view returns (MockDelegationManager.Delegation[] memory) {
        address[] memory e = new address[](1);
        e[0] = address(enforcer);
        return _root(delegate, e);
    }

    function _bare(address delegate_) internal view returns (MockDelegationManager.Delegation[] memory) {
        return _root(delegate_, new address[](0));
    }

    function _redeem2(bytes memory ctx0, bytes memory exec0, bytes memory ctx1, bytes memory exec1) internal {
        bytes[] memory cs = new bytes[](2);
        (cs[0], cs[1]) = (ctx0, ctx1);
        bytes32[] memory ms = new bytes32[](2);
        bytes[] memory es = new bytes[](2);
        (es[0], es[1]) = (exec0, exec1);
        vm.prank(delegate);
        manager.redeemDelegations(cs, ms, es);
    }

    function _redeem1(MockDelegationManager.Delegation[] memory chain, bytes memory exec) internal {
        bytes[] memory cs = new bytes[](1);
        cs[0] = abi.encode(chain);
        bytes32[] memory ms = new bytes32[](1);
        bytes[] memory es = new bytes[](1);
        es[0] = exec;
        vm.prank(delegate);
        manager.redeemDelegations(cs, ms, es);
    }

    /// Inside the movement the principal raises the caps, then calls spend itself on the same arguments: the
    /// record was taken before consume, so the re-entry finds none (13). One debit.
    function test_principalUpdatesAndReentersInsideMove_reentryFindsNoRecord() public {
        bytes memory reenter = abi.encodeCall(SpendGrantExecutor.spend, (id, address(token), 1e18, recipient));
        account.arm(
            abi.encodeCall(ISpendGrantRegistry.update, (id, 1, _terms(5e18, 50e18, 500e18, address(token)))), reenter
        );
        _redeem1(_withCaveat(), _spendExec(1e18));
        assertTrue(account.regOk(), "update inside the movement failed");
        assertFalse(account.execOk(), "re-entry as the principal spent");
        assertEq(account.execRet(), sgErr(13));
        (uint256 spent, uint256 calls) = registry.usage(id, address(token));
        assertEq(spent, 1e18);
        assertEq(calls, 1);
        assertEq(enforcer.recorded(address(account), id, address(token), 1e18, recipient), address(0));
    }

    /// Inside the movement the principal revokes; the outer debit stands, the re-entry fails, later spends REVOKED.
    function test_principalRevokesInsideMove_laterRedemptionIsRevoked() public {
        bytes memory reenter = abi.encodeCall(SpendGrantExecutor.spend, (id, address(token), 1e18, recipient));
        account.arm(abi.encodeCall(ISpendGrantRegistry.revoke, (id)), reenter);
        _redeem1(_withCaveat(), _spendExec(1e18));
        assertTrue(account.regOk());
        assertEq(account.execRet(), sgErr(13));
        assertTrue(registry.revoked(id));
        (uint256 spent, uint256 calls) = registry.usage(id, address(token));
        assertEq(spent, 1e18);
        assertEq(calls, 1);

        bytes[] memory cs = new bytes[](1);
        cs[0] = abi.encode(_withCaveat());
        bytes32[] memory ms = new bytes32[](1);
        bytes[] memory es = new bytes[](1);
        es[0] = _spendExec(1e18);
        vm.prank(delegate);
        vm.expectRevert(sgErr(5));
        manager.redeemDelegations(cs, ms, es);
    }

    /// Batch: entry 0 (a bare delegation of the principal's) revokes; entry 1 spends with the record: REVOKED.
    function test_batch_revokeThenSpend_isRevoked() public {
        bytes memory ctx0 = abi.encode(_bare(delegate));
        bytes memory exec0 = _registryExec(abi.encodeCall(ISpendGrantRegistry.revoke, (id)));
        bytes memory ctx1 = abi.encode(_withCaveat());
        bytes[] memory cs = new bytes[](2);
        (cs[0], cs[1]) = (ctx0, ctx1);
        bytes32[] memory ms = new bytes32[](2);
        bytes[] memory es = new bytes[](2);
        (es[0], es[1]) = (exec0, _spendExec(1e18));
        vm.prank(delegate);
        vm.expectRevert(sgErr(5));
        manager.redeemDelegations(cs, ms, es);
    }

    /// Batch: entry 0 lowers maxTotal to what was spent (a window later, so only the lifetime cap binds); entry 1
    /// spends: OVER_CUMULATIVE_CAP.
    function test_batch_lowerTotalToSpentThenSpend_overCumulativeCap() public {
        _redeem1(_withCaveat(), _spendExec(1e18));
        vm.warp(vm.getBlockTimestamp() + 1 days);
        bytes memory ctx0 = abi.encode(_bare(delegate));
        bytes memory exec0 =
            _registryExec(abi.encodeCall(ISpendGrantRegistry.update, (id, 1, _terms(1e18, 1e18, 1e18, address(token)))));
        bytes[] memory cs = new bytes[](2);
        (cs[0], cs[1]) = (ctx0, abi.encode(_withCaveat()));
        bytes32[] memory ms = new bytes32[](2);
        bytes[] memory es = new bytes[](2);
        (es[0], es[1]) = (exec0, _spendExec(1e18));
        vm.prank(delegate);
        vm.expectRevert(sgErr(10));
        manager.redeemDelegations(cs, ms, es);
    }

    /// Batch: entry 0 raises the per-call cap; entry 1 spends above the old cap: succeeds under the new terms.
    function test_batch_raisePerCallCapThenSpend_succeeds() public {
        _redeem2(
            abi.encode(_bare(delegate)),
            _registryExec(
                abi.encodeCall(ISpendGrantRegistry.update, (id, 1, _terms(2e18, 20e18, 200e18, address(token))))
            ),
            abi.encode(_withCaveat()),
            _spendExec(2e18)
        );
        (uint256 spent, uint256 calls) = registry.usage(id, address(token));
        assertEq(spent, 2e18);
        assertEq(calls, 1);
    }

    /// The root carries [enforcer, updater]: the record is written, then the updater has the principal raise the
    /// per-call cap, then the execution spends 2e18 (over the old cap) with the record: succeeds under the new terms.
    function test_updateBetweenRecordAndExecution_raiseApplies() public {
        (bool okBefore, Reason rBefore) = registry.check(id, delegate, address(token), 2e18, recipient);
        assertFalse(okBefore);
        assertEq(uint8(rBefore), 8);
        updater.arm(
            abi.encode(_bare(address(updater))),
            _registryExec(
                abi.encodeCall(ISpendGrantRegistry.update, (id, 1, _terms(2e18, 20e18, 200e18, address(token))))
            )
        );
        address[] memory e = new address[](2);
        (e[0], e[1]) = (address(enforcer), address(updater));
        _redeem1(_root(delegate, e), _spendExec(2e18));
        (uint256 spent, uint256 calls) = registry.usage(id, address(token));
        assertEq(spent, 2e18);
        assertEq(calls, 1);
        (, uint256 version,,,) = registry.getGrant(id);
        assertEq(version, 2);
    }

    /// Same, but the update removes the asset: the recorded spend fails WRONG_ASSET and nothing is spent.
    function test_updateBetweenRecordAndExecution_removeAssetIsWrongAsset() public {
        updater.arm(
            abi.encode(_bare(address(updater))),
            _registryExec(
                abi.encodeCall(ISpendGrantRegistry.update, (id, 1, _terms(1e18, 10e18, 100e18, address(other))))
            )
        );
        address[] memory e = new address[](2);
        (e[0], e[1]) = (address(enforcer), address(updater));
        bytes[] memory cs = new bytes[](1);
        cs[0] = abi.encode(_root(delegate, e));
        bytes32[] memory ms = new bytes32[](1);
        bytes[] memory es = new bytes[](1);
        es[0] = _spendExec(1e18);
        vm.prank(delegate);
        vm.expectRevert(sgErr(6));
        manager.redeemDelegations(cs, ms, es);
    }
}

/// grantState: a token that re-enters grantState inside the outer read's STATICCALL; and the single-payment limit.
contract SpendGrantStateViewTest is Test {
    SpendGrantRegistry internal registry;
    address internal executor;
    address internal principal;
    address internal delegate;
    address internal payee;

    function setUp() public {
        vm.warp(1_700_000_000);
        executor = makeAddr("executor");
        principal = makeAddr("principal");
        delegate = makeAddr("delegate");
        payee = makeAddr("payee");
        registry = new SpendGrantRegistry(executor);
    }

    function _grant(address asset, uint256 perCall, uint256 perWindow, uint256 total)
        internal
        view
        returns (SpendGrant memory g)
    {
        uint64 t = uint64(vm.getBlockTimestamp());
        g.principal = principal;
        g.delegate = delegate;
        g.recipient = payee;
        g.windowSeconds = 1 days;
        g.validAfter = t;
        g.validUntil = t + 30 days;
        g.salt = 1;
        g.assets = new AssetLimit[](1);
        g.assets[0] = AssetLimit(asset, perCall, perWindow, total);
    }

    /// The inner grantState starves inside the 100k stipend (InsufficientGas, caught by the token), and a token
    /// that bubbles that revert verbatim is reported unknown: the outer view returns and never surfaces the
    /// asset's InsufficientGas as its own.
    function test_tokenReentersGrantStateInsideRead_reportedUnknownNotReverted() public {
        ReentrantReadToken t = new ReentrantReadToken();
        vm.prank(principal);
        bytes32 gid = registry.register(_grant(address(t), 100, 1000, 5000));
        t.set(registry, gid);
        GrantState memory s = registry.grantState(gid, address(t));
        assertEq(uint8(s.status), 0);
        assertTrue(s.balanceKnown);
        assertEq(s.balance, 2, "inner grantState did not hit InsufficientGas");
        assertFalse(s.allowanceKnown);
        assertEq(s.allowance, 0);
        assertEq(s.spendableNow, 0);
    }

    /// Spec, grantState: "A single payment is further limited to the lesser of maxPerCall and any implementation
    /// amount bound." With every cap above the reference's amount bound (type(uint192).max), a payment of
    /// min(spendableNow, maxPerCall, type(uint192).max) by the delegate to the grant's recipient passes check and
    /// consume, and one unit more fails OVER_TX_CAP (8) in both.
    function test_singlePayment_isLimitedByMaxPerCallAndTheAmountBound() public {
        MockERC20 big = new MockERC20();
        uint256 cap = uint256(1) << 200;
        big.mint(principal, cap);
        vm.prank(principal);
        big.approve(executor, type(uint256).max);
        SpendGrant memory g = _grant(address(big), cap, cap, cap);
        vm.prank(principal);
        bytes32 gid = registry.register(g);
        GrantState memory s = registry.grantState(gid, address(big));
        assertEq(uint8(s.status), 0);
        // Both of the old rule's terms exceed the amount bound, so the bound is what limits the payment.
        assertEq(s.spendableNow, cap);
        assertEq(s.maxPerCall, cap);
        assertGt(s.spendableNow, type(uint192).max);
        assertGt(s.maxPerCall, type(uint192).max);
        uint256 pay = s.spendableNow < s.maxPerCall ? s.spendableNow : s.maxPerCall;
        if (pay > type(uint192).max) pay = type(uint192).max;
        assertEq(pay, type(uint192).max);
        uint256 over = pay + 1;

        (bool ok, Reason r) = registry.check(gid, delegate, address(big), over, payee);
        assertFalse(ok);
        assertEq(uint8(r), 8);
        (ok, r) = registry.check(gid, delegate, address(big), pay, payee);
        assertTrue(ok, "min(spendableNow, maxPerCall, amount bound) fails check");
        assertEq(uint8(r), 0);

        vm.prank(executor);
        registry.consume(gid, delegate, address(big), pay, payee);
        (uint256 spent, uint256 calls) = registry.usage(gid, address(big));
        assertEq(spent, type(uint192).max);
        assertEq(calls, 1);

        bytes memory overTxCap = sgErr(8);
        vm.prank(executor);
        vm.expectRevert(overTxCap);
        registry.consume(gid, delegate, address(big), over, payee);
    }
}
