// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AssetLimit, SpendGrant, Reason} from "../src/SpendGrantTypes.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";
import {SpendGrantExecutor} from "../src/SpendGrantExecutor.sol";
import {SpendGrantRedemptionEnforcer} from "../src/SpendGrantRedemptionEnforcer.sol";
import {SpendGrantRedemptionExecutor} from "../src/SpendGrantRedemptionExecutor.sol";
import {MockERC20} from "./MockERC20.sol";
import {MockDelegationManager, MockDeleGator} from "./SpendGrantRedemption.t.sol";

// Money path: spends beyond the caps, twice, or with altered execution calldata, and a delegation open to any
// delegate that carries the SpendGrant caveat, signed by an account that is also a delegate, which the enforcer
// refuses. Adopted from the final money-path review's proof-of-concept tests.

/// Token that is also the grant's delegate: on every transferFrom it re-enters executor.spend as the delegate.
contract SelfDelegateToken is MockERC20 {
    SpendGrantExecutor public exec;
    bytes32 public id;
    address public to;
    uint256 public amt;
    uint256 public depth;
    uint256 public maxDepth;
    bytes public lastRevert;
    uint256 public reentrySuccesses;

    function arm(SpendGrantExecutor e, bytes32 id_, address to_, uint256 amt_, uint256 maxDepth_) external {
        (exec, id, to, amt, maxDepth) = (e, id_, to_, amt_, maxDepth_);
    }

    function start() external {
        exec.spend(id, address(this), amt, to);
    }

    function transferFrom(address from, address to_, uint256 amount) external override returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to_] += amount;
        if (msg.sender == address(exec) && depth < maxDepth) {
            depth++;
            try exec.spend(id, address(this), amt, to) {
                reentrySuccesses++;
            } catch (bytes memory r) {
                lastRevert = r;
            }
        }
        return true;
    }
}

/// Principal account that swallows the executor's revert, fixes its allowance, and retries the same call,
/// then tries again and once more with a different amount. Never reverts itself.
contract RetryDeleGator {
    address internal immutable MANAGER;
    MockERC20 internal immutable TOKEN;
    bool[4] public ok;
    bytes[4] public ret;

    constructor(address manager_, MockERC20 token_) {
        MANAGER = manager_;
        TOKEN = token_;
    }

    function executeFromExecutor(bytes32, bytes calldata executionCalldata) external {
        require(msg.sender == MANAGER, "not manager");
        address target = address(bytes20(executionCalldata[:20]));
        bytes memory callData = executionCalldata[52:];
        // 1: no allowance yet -> consume runs, movement fails, whole executor frame (incl. take's clear) reverts.
        (ok[0], ret[0]) = target.call(callData);
        TOKEN.approve(target, type(uint256).max);
        // 2: same call -> record restored by the revert -> succeeds.
        (ok[1], ret[1]) = target.call(callData);
        // 3: same call again -> record already taken.
        (ok[2], ret[2]) = target.call(callData);
        // 4: different amount -> different key, nothing recorded for it.
        (bytes32 gid, address asset, uint256 amount, address recipient) =
            abi.decode(_slice(callData, 4), (bytes32, address, uint256, address));
        (ok[3], ret[3]) = target.call(abi.encodeCall(SpendGrantExecutor.spend, (gid, asset, amount / 2, recipient)));
    }

    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return 0x1626ba7e;
    }

    function _slice(bytes memory b, uint256 from) internal pure returns (bytes memory out) {
        out = new bytes(b.length - from);
        for (uint256 i = 0; i < out.length; i++) {
            out[i] = b[from + i];
        }
    }
}

contract SpendGrantMoneyPathTest is Test {
    address internal principal = vm.addr(0xA11CE);
    address internal recipient = vm.addr(0xC0C);
    address internal delegate = vm.addr(0xB0B);
    address internal stranger = vm.addr(0xBAD);

    function _err(Reason r) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(bytes4(keccak256("SpendGrantError(uint8)")), uint8(r));
    }

    function _grant(address p, address d, address asset, uint8 mode, address r)
        internal
        pure
        returns (SpendGrant memory m)
    {
        m.principal = p;
        m.delegate = d;
        m.recipientMode = mode;
        m.recipient = r;
        m.windowSeconds = 86400;
        m.validAfter = 1_699_999_000;
        m.validUntil = 1_900_000_000;
        m.salt = 1;
        m.assets = new AssetLimit[](1);
        m.assets[0] = AssetLimit(asset, 1e18, 3e18, 100e18);
    }

    // ------------------------------------------------------------ 1. reentrancy where the re-entrant caller IS the delegate

    function test_tokenThatIsTheDelegate_reentrantSpendsStopAtWindowCap() public {
        vm.warp(1_700_000_000);
        uint64 n = vm.getNonce(address(this));
        SpendGrantRegistry registry = new SpendGrantRegistry(vm.computeCreateAddress(address(this), n + 1));
        SpendGrantExecutor exec = new SpendGrantExecutor(registry);
        SelfDelegateToken t = new SelfDelegateToken();
        t.mint(principal, 1e24);
        vm.prank(principal);
        t.approve(address(exec), type(uint256).max);

        SpendGrant memory m = _grant(principal, address(t), address(t), 1, address(0));
        vm.prank(principal);
        bytes32 id = registry.register(m);

        t.arm(exec, id, recipient, 1e18, 10);
        t.start();

        (uint256 spent, uint256 calls) = registry.usage(id, address(t));
        assertEq(spent, 3e18, "window cap must bound reentrant spends");
        assertEq(calls, 3);
        assertEq(t.balanceOf(recipient), 3e18);
        assertEq(t.reentrySuccesses(), 2);
        assertEq(t.lastRevert(), _err(Reason.OVER_WINDOW_CAP));
    }

    // ------------------------------------------------------------ redemption fixtures

    MockDelegationManager internal manager;
    SpendGrantRegistry internal reg;
    SpendGrantRedemptionEnforcer internal enf;
    SpendGrantRedemptionExecutor internal rexec;
    MockERC20 internal token;

    function _deployRedemption() internal {
        vm.warp(1_700_000_000);
        token = new MockERC20();
        manager = new MockDelegationManager();
        uint64 n = vm.getNonce(address(this));
        address predicted = vm.computeCreateAddress(address(this), n + 2);
        reg = new SpendGrantRegistry(predicted);
        enf = new SpendGrantRedemptionEnforcer(address(manager), predicted, address(reg));
        rexec = new SpendGrantRedemptionExecutor(reg, enf);
        assertEq(address(rexec), predicted);
    }

    function _rootWithCaveat(address d, address delegator)
        internal
        view
        returns (MockDelegationManager.Delegation[] memory chain)
    {
        chain = new MockDelegationManager.Delegation[](1);
        chain[0].delegate = d;
        chain[0].delegator = delegator;
        chain[0].authority = manager.ROOT_AUTHORITY();
        chain[0].caveats = new MockDelegationManager.Caveat[](1);
        chain[0].caveats[0] = MockDelegationManager.Caveat(address(enf), "", "");
        chain[0].caveats[0].args = abi.encode(chain[0]);
    }

    function _redeemRaw(address caller, MockDelegationManager.Delegation[] memory chain, bytes memory execution)
        internal
        returns (bool ok, bytes memory ret)
    {
        bytes[] memory contexts = new bytes[](1);
        contexts[0] = abi.encode(chain);
        bytes32[] memory modes = new bytes32[](1);
        bytes[] memory executions = new bytes[](1);
        executions[0] = execution;
        vm.prank(caller);
        (ok, ret) = address(manager).call(
            abi.encodeCall(MockDelegationManager.redeemDelegations, (contexts, modes, executions))
        );
    }

    // ------------------------------------------------------------ 2. principal account swallows reverts and retries

    function test_principalAccountRetriesAfterRevert_oneRecordOneConsume() public {
        _deployRedemption();
        RetryDeleGator acct = new RetryDeleGator(address(manager), token);
        token.mint(address(acct), 1e24);
        vm.prank(address(acct));
        bytes32 id = reg.register(_grant(address(acct), delegate, address(token), 0, recipient));

        bytes memory execution = abi.encodePacked(
            address(rexec), uint256(0), abi.encodeCall(SpendGrantExecutor.spend, (id, address(token), 1e18, recipient))
        );
        (bool ok,) = _redeemRaw(delegate, _rootWithCaveat(delegate, address(acct)), execution);
        assertTrue(ok);

        assertFalse(acct.ok(0));
        assertEq(acct.ret(0), abi.encodeWithSelector(SpendGrantExecutor.TransferFailed.selector));
        assertTrue(acct.ok(1), "rolled-back take restores the record: first successful spend");
        assertFalse(acct.ok(2));
        assertEq(acct.ret(2), _err(Reason.UNAUTHORIZED_DELEGATE));
        assertFalse(acct.ok(3));
        assertEq(acct.ret(3), _err(Reason.UNAUTHORIZED_DELEGATE));

        (uint256 spent, uint256 calls) = reg.usage(id, address(token));
        assertEq(spent, 1e18);
        assertEq(calls, 1);
        assertEq(token.balanceOf(recipient), 1e18);
    }

    // ------------------------------------------------------------ 3. execution calldata: trailing bytes, dirty words

    function test_trailingExecutionBytes_decodeTheSameSpend() public {
        _deployRedemption();
        MockDeleGator acct = new MockDeleGator(address(manager), principal);
        token.mint(address(acct), 1e24);
        vm.prank(address(acct));
        token.approve(address(rexec), type(uint256).max);
        vm.prank(address(acct));
        bytes32 id = reg.register(_grant(address(acct), delegate, address(token), 1, address(0)));

        // Trailing junk that itself looks like a second spend's arguments, to another recipient.
        bytes memory execution = abi.encodePacked(
            address(rexec),
            uint256(0),
            abi.encodeCall(SpendGrantExecutor.spend, (id, address(token), 1e18, recipient)),
            abi.encode(id, address(token), uint256(2e18), stranger)
        );
        (bool ok,) = _redeemRaw(delegate, _rootWithCaveat(delegate, address(acct)), execution);
        assertTrue(ok);
        (uint256 spent, uint256 calls) = reg.usage(id, address(token));
        assertEq(spent, 1e18);
        assertEq(calls, 1);
        assertEq(token.balanceOf(recipient), 1e18);
        assertEq(token.balanceOf(stranger), 0);
    }

    function test_dirtyAddressWords_revertEverywhere() public {
        _deployRedemption();
        MockDeleGator acct = new MockDeleGator(address(manager), principal);
        token.mint(address(acct), 1e24);
        vm.prank(address(acct));
        token.approve(address(rexec), type(uint256).max);
        vm.prank(address(acct));
        bytes32 id = reg.register(_grant(address(acct), delegate, address(token), 1, address(0)));

        uint256 tried;
        for (uint256 w = 1; w <= 3; w += 2) {
            // word 1 = asset, word 3 = recipient; set a high bit above the 160-bit address.
            bytes memory callData = abi.encodeCall(SpendGrantExecutor.spend, (id, address(token), 1e18, recipient));
            uint256 off = 4 + 32 * w;
            callData[off] = 0x01;
            bytes memory execution = abi.encodePacked(address(rexec), uint256(0), callData);
            (bool ok, bytes memory ret) = _redeemRaw(delegate, _rootWithCaveat(delegate, address(acct)), execution);
            assertFalse(ok);
            assertEq(ret.length, 0);
            tried++;
        }
        assertEq(tried, 2);
        (uint256 spent,) = reg.usage(id, address(token));
        assertEq(spent, 0);
    }

    // ------------------------------------------------------------ 4. open delegation with the caveat, by a delegate

    /// The money-path review's FC-1. P is the principal of its own grant and the delegate of Q's grant, which Q
    /// registered without P doing anything. P signs a delegation open to any delegate carrying only the SpendGrant
    /// caveat. A stranger redeems it for Q's grant. Before, the hook was inert there (the delegator P is not Q's
    /// principal) and the executor saw P, Q's delegate, as its caller on the direct path, so the stranger spent Q's
    /// grant. Now the hook reverts for any delegator but the grant's principal, and nothing moves.
    function test_openDelegationByADelegateAccount_carryingTheCaveat_reverts() public {
        _deployRedemption();
        MockDeleGator p = new MockDeleGator(address(manager), principal);
        // P's own grant, to `delegate`.
        vm.prank(address(p));
        reg.register(_grant(address(p), delegate, address(token), 0, recipient));
        address q = vm.addr(0x0A0);
        token.mint(q, 1e24);
        vm.prank(q);
        token.approve(address(rexec), type(uint256).max);
        // Q's grant names P as delegate, any recipient (Q registers it; P did nothing).
        vm.prank(q);
        bytes32 qId = reg.register(_grant(q, address(p), address(token), 1, address(0)));

        // P's open delegation carrying only the SpendGrant caveat.
        MockDelegationManager.Delegation[] memory chain = _rootWithCaveat(manager.ANY_DELEGATE(), address(p));
        bytes memory execution = abi.encodePacked(
            address(rexec), uint256(0), abi.encodeCall(SpendGrantExecutor.spend, (qId, address(token), 1e18, stranger))
        );
        (bool ok, bytes memory ret) = _redeemRaw(stranger, chain, execution);
        assertFalse(ok, "stranger spent Q's grant through P's open delegation");
        assertEq(ret, abi.encodeWithSelector(bytes4(keccak256("WrongDelegator()"))), "not refused at the hook");
        assertEq(token.balanceOf(stranger), 0);
        assertEq(token.balanceOf(q), 1e24);
        (uint256 spent, uint256 calls) = reg.usage(qId, address(token));
        assertEq(spent, 0);
        assertEq(calls, 0);
    }
}
