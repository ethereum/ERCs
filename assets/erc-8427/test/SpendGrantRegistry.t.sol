// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {
    AssetLimit,
    ISpendGrantRegistry,
    MAX_LIVE_DEBITS,
    NATIVE,
    NotPrincipal,
    Reason,
    SpendGrant,
    SpendGrantError
} from "../src/SpendGrantTypes.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";
import {SpendGrantExecutor} from "../src/SpendGrantExecutor.sol";
import {MockERC20} from "./MockERC20.sol";

contract FalseERC20 {
    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }
}

contract RevertingERC20 {
    function transferFrom(address, address, uint256) external pure returns (bool) {
        revert();
    }
}

/// @dev EIP-7702 delegation targets for a principal: no functions at all, an ERC-1271 that rejects everything,
/// and code that reverts on every call. None of them may matter to a registered grant.
contract No1271 {}

contract AlwaysRejects1271 {
    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return 0xffffffff;
    }
}

contract RevertsOnEveryCall {
    fallback() external payable {
        revert();
    }
}

/// @dev A contract account that makes whatever call its owner asks for, bubbling the callee's revert.
contract OwnedAccount {
    address internal immutable OWNER;

    error NotOwner();

    constructor(address owner_) {
        OWNER = owner_;
    }

    function exec(address target, bytes calldata data) external returns (bytes memory ret) {
        if (msg.sender != OWNER) revert NotOwner();
        bool ok;
        (ok, ret) = target.call(data);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(ret, 32), mload(ret))
            }
        }
    }
}

contract SpendGrantRegistryTest is Test {
    uint256 internal constant PRINCIPAL_PK = 0xA11CE;
    uint256 internal constant DELEGATE_PK = 0xB0B;

    SpendGrantRegistry internal registry; // this test contract is its executor
    SpendGrantRegistry internal execRegistry;
    SpendGrantExecutor internal executor;
    MockERC20 internal token;

    address internal principal;
    address internal delegate;
    address internal recipient;

    // Declared here, not taken from ISpendGrantRegistry, so a change to the registry's indexing fails the tests.
    event GrantRevoked(bytes32 indexed grantId, address indexed principal, address indexed delegate);
    event GrantConsumed(
        bytes32 indexed grantId, address indexed principal, address asset, uint256 amount, address indexed recipient
    );

    function setUp() public {
        principal = vm.addr(PRINCIPAL_PK);
        delegate = vm.addr(DELEGATE_PK);
        recipient = vm.addr(0xC0C);

        token = new MockERC20();
        registry = new SpendGrantRegistry(address(this));

        uint64 nonce = vm.getNonce(address(this));
        address predicted = vm.computeCreateAddress(address(this), nonce + 1);
        execRegistry = new SpendGrantRegistry(predicted);
        executor = new SpendGrantExecutor(execRegistry);
        assertEq(address(executor), predicted);
        // Asset lists are ascending; _andGrant lists the token before NATIVE.
        assertLt(uint160(address(token)), uint160(NATIVE));

        token.mint(principal, 1e24);
        vm.prank(principal);
        token.approve(address(executor), type(uint256).max);

        vm.warp(1_700_000_000);
    }

    /// Only the principal revokes: anyone else's attempt reverts and leaves the grant spendable. The principal's
    /// revocation emits once, a repeat emits nothing, and consume then fails REVOKED.
    function test_revoke_emitsOnceAndBlocksConsume() public {
        bytes32 id = _register(_andGrant());

        vm.prank(address(0xBEEF));
        (bool ok, bytes memory ret) = address(registry).call(abi.encodeCall(ISpendGrantRegistry.revoke, (id)));
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(NotPrincipal.selector));
        assertFalse(registry.revoked(id));

        _consume(id, NATIVE, 1 ether, recipient);

        vm.expectEmit(true, true, true, true, address(registry));
        emit GrantRevoked(id, principal, delegate);
        vm.prank(principal);
        registry.revoke(id);
        assertTrue(registry.revoked(id));

        vm.prank(principal);
        vm.recordLogs();
        registry.revoke(id);
        assertEq(vm.getRecordedLogs().length, 0);

        _expect(Reason.REVOKED);
        _consume(id, NATIVE, 1 ether, recipient);
    }

    function test_unauthorizedConsume() public {
        bytes32 id = _register(_andGrant());
        vm.prank(delegate);
        _expect(Reason.UNAUTHORIZED_EXECUTOR);
        registry.consume(id, delegate, NATIVE, 1 ether, recipient);
    }

    function test_consume_authorizerMustBeDelegate() public {
        bytes32 id = _register(_andGrant());

        address[3] memory badAuthorizers = [principal, vm.addr(0xBAD), address(0)];
        for (uint256 i = 0; i < badAuthorizers.length; i++) {
            _assertRejects(id, badAuthorizers[i], NATIVE, 1 ether, recipient, Reason.UNAUTHORIZED_DELEGATE);
        }

        (uint256 spent, uint256 calls) = registry.usage(id, NATIVE);
        assertEq(spent, 0);
        assertEq(calls, 0);

        registry.consume(id, delegate, NATIVE, 1 ether, recipient);
        (spent, calls) = registry.usage(id, NATIVE);
        assertEq(spent, 1 ether);
        assertEq(calls, 1);
    }

    function test_ordering_unauthorizedExecutorBeforeDelegate() public {
        bytes32 id = _register(_andGrant());
        address bad = vm.addr(0xBAD);

        vm.prank(bad);
        _expect(Reason.UNAUTHORIZED_EXECUTOR);
        registry.consume(id, bad, NATIVE, 1, recipient);
    }

    /// The delegate check (step 2) precedes the only INVALID_GRANT consume still returns, the code check on the
    /// spent asset (step 8): a wrong authorizer learns UNAUTHORIZED_DELEGATE for an asset with no code and for an
    /// EIP-7702 account listed as an asset. (The structural failures it used to precede never reach consume:
    /// register refuses them, see test_ordering_invalidGrantWithRightAuthorizer.)
    function test_ordering_unauthorizedDelegateBeforeInvalidGrant() public {
        (bytes32 id, address codeless, address designator) = _registerCodeCheckGrant();
        address bad = vm.addr(0xBAD);

        _assertRejects(id, bad, designator, 1, recipient, Reason.UNAUTHORIZED_DELEGATE);
        _assertRejects(id, principal, codeless, 1, recipient, Reason.UNAUTHORIZED_DELEGATE);
        _assertRejects(id, address(0), codeless, 1, recipient, Reason.UNAUTHORIZED_DELEGATE);
        _assertRejects(id, delegate, codeless, 1, recipient, Reason.INVALID_GRANT);

        _expect(Reason.UNAUTHORIZED_DELEGATE);
        registry.consume(id, bad, codeless, 1, recipient);
    }

    /// A zero window, a zero delegate and a delegate equal to the principal are refused at register with
    /// INVALID_GRANT. With the right authorizer, consume reports INVALID_GRANT for a spent asset that fails the
    /// code check.
    function test_ordering_invalidGrantWithRightAuthorizer() public {
        SpendGrant memory m = _andGrant();
        m.windowSeconds = 0;
        _assertRegisterRejects(m);

        m = _andGrant();
        m.delegate = address(0);
        _assertRegisterRejects(m);

        m = _andGrant();
        m.delegate = principal;
        _assertRegisterRejects(m);

        (bytes32 id, address codeless, address designator) = _registerCodeCheckGrant();
        _assertRejects(id, delegate, designator, 1, recipient, Reason.INVALID_GRANT);
        _expect(Reason.INVALID_GRANT);
        registry.consume(id, delegate, codeless, 1, recipient);
    }

    function test_timeBounds() public {
        SpendGrant memory m = _andGrant();
        bytes32 id = _register(m);
        uint256 validAfter = uint256(m.validAfter);
        uint256 validUntil = uint256(m.validUntil);

        vm.warp(validAfter - 1);
        _assertRejects(id, delegate, NATIVE, 1, recipient, Reason.NOT_YET_VALID);

        vm.warp(validAfter);
        _consume(id, NATIVE, 1, recipient);

        vm.warp(validUntil - 1);
        _consume(id, NATIVE, 1, recipient);

        vm.warp(validUntil);
        _expect(Reason.EXPIRED);
        _consume(id, NATIVE, 1, recipient);
    }

    function test_wrongAssetAndRecipient() public {
        bytes32 id = _register(_andGrant());
        _assertRejects(id, delegate, address(0x1234), 1, recipient, Reason.WRONG_ASSET);

        // The same terms with an open recipient are another grant, and it pays anyone.
        SpendGrant memory open = _andGrant();
        open.recipientMode = 1;
        open.recipient = address(0);
        bytes32 openId = _register(open);
        _consume(openId, NATIVE, 1, address(0x9999));
        (uint256 spent,) = registry.usage(openId, NATIVE);
        assertEq(spent, 1);

        _expect(Reason.WRONG_RECIPIENT);
        _consume(id, NATIVE, 1, address(0x9999));
    }

    function test_perCallWindowLifetime() public {
        SpendGrant memory m = _andGrant();
        m.assets[1] = AssetLimit(NATIVE, 10, 25, 30);
        bytes32 id = _register(m);

        _assertRejects(id, delegate, NATIVE, 0, recipient, Reason.OVER_TX_CAP);
        _assertRejects(id, delegate, NATIVE, 11, recipient, Reason.OVER_TX_CAP);

        _consume(id, NATIVE, 10, recipient);
        _consume(id, NATIVE, 10, recipient);
        _assertRejects(id, delegate, NATIVE, 10, recipient, Reason.OVER_WINDOW_CAP);

        uint256 t = vm.getBlockTimestamp();
        vm.warp(t + m.windowSeconds);
        _consume(id, NATIVE, 10, recipient);

        (uint256 spent, uint256 calls) = registry.usage(id, NATIVE);
        assertEq(spent, 30);
        assertEq(calls, 3);

        _expect(Reason.OVER_CUMULATIVE_CAP);
        _consume(id, NATIVE, 10, recipient);
    }

    function test_andIndependent() public {
        bytes32 id = _register(_andGrant());
        _consume(id, NATIVE, 1 ether, recipient);
        _consume(id, address(token), 1e18, recipient);

        (uint256 nativeSpent,) = registry.usage(id, NATIVE);
        (uint256 tokenSpent,) = registry.usage(id, address(token));
        assertEq(nativeSpent, 1 ether);
        assertEq(tokenSpent, 1e18);

        (uint256 nativeRoll,) = registry.rollingUsage(id, NATIVE);
        (uint256 tokenRoll,) = registry.rollingUsage(id, address(token));
        assertEq(nativeRoll, 1 ether);
        assertEq(tokenRoll, 1e18);
    }

    function test_executor_erc20HappyPath() public {
        bytes32 id = _registerOn(execRegistry, _andGrant());

        uint256 recipientBefore = token.balanceOf(recipient);
        uint256 principalBefore = token.balanceOf(principal);

        vm.prank(delegate);
        executor.spend(id, address(token), 1e18, recipient);

        assertEq(token.balanceOf(recipient) - recipientBefore, 1e18);
        assertEq(principalBefore - token.balanceOf(principal), 1e18);
        (uint256 spent, uint256 calls) = execRegistry.usage(id, address(token));
        assertEq(spent, 1e18);
        assertEq(calls, 1);
    }

    function test_executor_mode1_callerRecipient() public {
        SpendGrant memory m = _andGrant();
        m.recipientMode = 1;
        m.recipient = address(0);
        bytes32 id = _registerOn(execRegistry, m);
        address other = vm.addr(0xD0D);

        uint256 principalBefore = token.balanceOf(principal);

        vm.prank(delegate);
        executor.spend(id, address(token), 1e18, other);

        assertEq(token.balanceOf(other), 1e18);
        assertEq(principalBefore - token.balanceOf(principal), 1e18);
    }

    function test_executor_revertsIfTransferFails() public {
        RevertingERC20 bad = new RevertingERC20();
        SpendGrant memory m = _andGrant();
        AssetLimit[] memory assets = new AssetLimit[](1);
        assets[0] = AssetLimit(address(bad), 1, 1, 1);
        m.assets = assets;
        bytes32 id = _registerOn(execRegistry, m);

        _assertSpendRejects(
            delegate, id, address(bad), 1, recipient, abi.encodeWithSelector(SpendGrantExecutor.TransferFailed.selector)
        );

        (uint256 spent, uint256 calls) = execRegistry.usage(id, address(bad));
        assertEq(spent, 0);
        assertEq(calls, 0);
    }

    function test_executor_rejectsMsgValue() public {
        bytes32 id = _registerOn(execRegistry, _andGrant());

        vm.deal(delegate, 1 ether);
        uint256 delegateBalanceBefore = delegate.balance;
        // Funded, so an empty revert below is the non-payable dispatcher, not OutOfFunds.
        assertEq(delegateBalanceBefore, 1 ether);
        uint256 principalTokenBefore = token.balanceOf(principal);
        uint256 recipientTokenBefore = token.balanceOf(recipient);

        // spend is non-payable: the dispatcher reverts with empty data before the body runs, so
        // neither the ERC-20 path nor the NATIVE guard (which reverts with a selector) is reached.
        vm.prank(delegate);
        (bool ok, bytes memory ret) = address(executor).call{value: 1}(
            abi.encodeCall(SpendGrantExecutor.spend, (id, address(token), 1e18, recipient))
        );
        assertFalse(ok);
        assertEq(ret.length, 0);

        vm.prank(delegate);
        (bool okNative, bytes memory retNative) =
            address(executor).call{value: 1}(abi.encodeCall(SpendGrantExecutor.spend, (id, NATIVE, 1e18, recipient)));
        assertFalse(okNative);
        assertEq(retNative.length, 0);

        (uint256 tokenSpent, uint256 tokenCalls) = execRegistry.usage(id, address(token));
        (uint256 nativeSpent, uint256 nativeCalls) = execRegistry.usage(id, NATIVE);
        assertEq(tokenSpent, 0);
        assertEq(tokenCalls, 0);
        assertEq(nativeSpent, 0);
        assertEq(nativeCalls, 0);
        assertEq(token.balanceOf(principal), principalTokenBefore);
        assertEq(token.balanceOf(recipient), recipientTokenBefore);
        assertEq(delegate.balance, delegateBalanceBefore);

        // Control: the same call without value succeeds, so the value alone caused the revert.
        vm.prank(delegate);
        executor.spend(id, address(token), 1e18, recipient);
        (tokenSpent, tokenCalls) = execRegistry.usage(id, address(token));
        assertEq(tokenSpent, 1e18);
        assertEq(tokenCalls, 1);
    }

    function test_executor_erc20FalseReturnRollsBack() public {
        FalseERC20 bad = new FalseERC20();
        SpendGrant memory m = _andGrant();
        m.assets = _two(AssetLimit(address(bad), 1, 1, 1), m.assets[1]);
        bytes32 id = _registerOn(execRegistry, m);

        _assertSpendRejects(
            delegate, id, address(bad), 1, recipient, abi.encodeWithSelector(SpendGrantExecutor.TransferFailed.selector)
        );

        (uint256 spent, uint256 calls) = execRegistry.usage(id, address(bad));
        assertEq(spent, 0);
        assertEq(calls, 0);
    }

    function test_executor_rejectsNative() public {
        vm.deal(delegate, 2 ether);
        uint256 delegateBalanceBefore = delegate.balance;
        bytes memory refused = abi.encodeWithSelector(SpendGrantExecutor.NativeRequiresAccountAdapter.selector);

        bytes32 id0 = _registerOn(execRegistry, _andGrant());
        uint256 recipientBalanceBefore = recipient.balance;

        _assertSpendRejects(delegate, id0, NATIVE, 1 ether, recipient, refused);

        (uint256 spent0, uint256 calls0) = execRegistry.usage(id0, NATIVE);
        (uint256 rolling0, uint256 rollingCalls0) = execRegistry.rollingUsage(id0, NATIVE);
        assertEq(spent0, 0);
        assertEq(calls0, 0);
        assertEq(rolling0, 0);
        assertEq(rollingCalls0, 0);
        assertEq(recipient.balance, recipientBalanceBefore);
        assertEq(delegate.balance, delegateBalanceBefore);

        SpendGrant memory m1 = _andGrant();
        m1.recipientMode = 1;
        m1.recipient = address(0);
        bytes32 id1 = _registerOn(execRegistry, m1);
        address other = vm.addr(0xD0D);
        uint256 otherBalanceBefore = other.balance;

        _assertSpendRejects(delegate, id1, NATIVE, 1 ether, other, refused);

        (uint256 spent1, uint256 calls1) = execRegistry.usage(id1, NATIVE);
        (uint256 rolling1, uint256 rollingCalls1) = execRegistry.rollingUsage(id1, NATIVE);
        assertEq(spent1, 0);
        assertEq(calls1, 0);
        assertEq(rolling1, 0);
        assertEq(rollingCalls1, 0);
        assertEq(other.balance, otherBalanceBefore);
        assertEq(delegate.balance, delegateBalanceBefore);
    }

    /// The NATIVE guard runs before the id is looked up and before consume: each call below would otherwise fail
    /// with a different reason (UNAUTHORIZED_DELEGATE, NONEXISTENT, WRONG_ASSET), which `check` confirms.
    function test_executor_rejectsNativeBeforeConsume() public {
        bytes32 id = _registerOn(execRegistry, _andGrant());
        bytes32 unknown = keccak256("unregistered");
        address bad = vm.addr(0xBAD);
        bytes memory refused = abi.encodeWithSelector(SpendGrantExecutor.NativeRequiresAccountAdapter.selector);

        SpendGrant memory tokenOnly = _andGrant();
        AssetLimit[] memory one = new AssetLimit[](1);
        one[0] = tokenOnly.assets[0];
        tokenOnly.assets = one;
        bytes32 tokenOnlyId = _registerOn(execRegistry, tokenOnly);

        _assertCheck(execRegistry, id, bad, NATIVE, Reason.UNAUTHORIZED_DELEGATE);
        _assertCheck(execRegistry, unknown, delegate, NATIVE, Reason.NONEXISTENT);
        _assertCheck(execRegistry, tokenOnlyId, delegate, NATIVE, Reason.WRONG_ASSET);

        _assertSpendRejects(bad, id, NATIVE, 1 ether, recipient, refused);
        _assertSpendRejects(delegate, unknown, NATIVE, 1 ether, recipient, refused);

        vm.prank(delegate);
        vm.expectRevert(refused);
        executor.spend(tokenOnlyId, NATIVE, 1 ether, recipient);
    }

    /// The delegate spends once (making the id public), then a third party or the principal replays the same id
    /// through the executor. Snapshots every balance and usage counter that must stay frozen across the blocked
    /// replay.
    function _assertExecutorReplayBlocked(bytes32 id, address caller, address recipientArg) internal {
        uint256 principalBefore = token.balanceOf(principal);
        uint256 recipientBefore = token.balanceOf(recipientArg);
        uint256 callerBefore = token.balanceOf(caller);
        (uint256 spentBefore, uint256 callsBefore) = execRegistry.usage(id, address(token));
        (uint256 rollingBefore, uint256 rollingCallsBefore) = execRegistry.rollingUsage(id, address(token));

        _assertSpendRejects(caller, id, address(token), 1e18, recipientArg, _err(Reason.UNAUTHORIZED_DELEGATE));

        assertEq(token.balanceOf(principal), principalBefore);
        assertEq(token.balanceOf(recipientArg), recipientBefore);
        assertEq(token.balanceOf(caller), callerBefore);
        (uint256 spentAfter, uint256 callsAfter) = execRegistry.usage(id, address(token));
        (uint256 rollingAfter, uint256 rollingCallsAfter) = execRegistry.rollingUsage(id, address(token));
        assertEq(spentAfter, spentBefore);
        assertEq(callsAfter, callsBefore);
        assertEq(rollingAfter, rollingBefore);
        assertEq(rollingCallsAfter, rollingCallsBefore);
    }

    function test_executor_replayByThirdParty_mode0() public {
        bytes32 id = _registerOn(execRegistry, _andGrant());

        vm.prank(delegate);
        executor.spend(id, address(token), 1e18, recipient);

        _assertExecutorReplayBlocked(id, vm.addr(0xBAD), recipient);
    }

    function test_executor_replayByThirdParty_mode1() public {
        SpendGrant memory m = _andGrant();
        m.recipientMode = 1;
        m.recipient = address(0);
        bytes32 id = _registerOn(execRegistry, m);

        vm.prank(delegate);
        executor.spend(id, address(token), 1e18, recipient);

        address attacker = vm.addr(0xBAD);
        _assertExecutorReplayBlocked(id, attacker, attacker);
    }

    function test_executor_replayByPrincipal_mode0() public {
        bytes32 id = _registerOn(execRegistry, _andGrant());

        vm.prank(delegate);
        executor.spend(id, address(token), 1e18, recipient);

        _assertExecutorReplayBlocked(id, principal, recipient);
    }

    function test_executor_replayByPrincipal_mode1() public {
        SpendGrant memory m = _andGrant();
        m.recipientMode = 1;
        m.recipient = address(0);
        bytes32 id = _registerOn(execRegistry, m);

        vm.prank(delegate);
        executor.spend(id, address(token), 1e18, recipient);

        _assertExecutorReplayBlocked(id, principal, principal);
    }

    function test_executor_mode0_wrongRecipientReverts() public {
        bytes32 id = _registerOn(execRegistry, _andGrant());
        address other = vm.addr(0xD0D);
        uint256 principalBefore = token.balanceOf(principal);

        _assertSpendRejects(delegate, id, address(token), 1e18, other, _err(Reason.WRONG_RECIPIENT));

        assertEq(token.balanceOf(principal), principalBefore);
        assertEq(token.balanceOf(other), 0);
        (uint256 spent, uint256 calls) = execRegistry.usage(id, address(token));
        assertEq(spent, 0);
        assertEq(calls, 0);

        vm.prank(delegate);
        executor.spend(id, address(token), 1e18, recipient);
        assertEq(token.balanceOf(recipient), 1e18);
    }

    function test_registry_rejectsZeroExecutor() public {
        vm.expectRevert(abi.encodeWithSelector(SpendGrantRegistry.ZeroExecutor.selector));
        new SpendGrantRegistry(address(0));
    }

    function testFuzz_executor_onlyDelegateCanSpend(address caller, address to, bool mode1) public {
        vm.assume(caller != delegate);
        SpendGrant memory m = _andGrant();
        if (mode1) {
            m.recipientMode = 1;
            m.recipient = address(0);
        }
        bytes32 id = _registerOn(execRegistry, m);

        uint256 principalBefore = token.balanceOf(principal);
        (uint256 spentBefore, uint256 callsBefore) = execRegistry.usage(id, address(token));

        _assertSpendRejects(caller, id, address(token), 1e18, to, _err(Reason.UNAUTHORIZED_DELEGATE));

        assertEq(token.balanceOf(principal), principalBefore);
        (uint256 spentAfter, uint256 callsAfter) = execRegistry.usage(id, address(token));
        assertEq(spentAfter, spentBefore);
        assertEq(callsAfter, callsBefore);
    }

    function test_windowExpiryAtExactAge() public {
        SpendGrant memory m = _andGrant();
        m.windowSeconds = 100;
        m.assets[1] = AssetLimit(NATIVE, 5, 5, 100);
        bytes32 id = _register(m);

        uint256 t0 = vm.getBlockTimestamp();
        _consume(id, NATIVE, 5, recipient);

        (uint256 rolling,) = registry.rollingUsage(id, NATIVE);
        assertEq(rolling, 5);

        vm.warp(t0 + 99);
        (rolling,) = registry.rollingUsage(id, NATIVE);
        assertEq(rolling, 5);
        _assertRejects(id, delegate, NATIVE, 1, recipient, Reason.OVER_WINDOW_CAP);

        vm.warp(t0 + 100);
        (rolling,) = registry.rollingUsage(id, NATIVE);
        assertEq(rolling, 0);
        _consume(id, NATIVE, 5, recipient);
        (rolling,) = registry.rollingUsage(id, NATIVE);
        assertEq(rolling, 5);

        _expect(Reason.OVER_WINDOW_CAP);
        _consume(id, NATIVE, 1, recipient);
    }

    function test_windowFullAtMaxLiveDebitsEvents() public {
        SpendGrant memory m = _andGrant();
        m.assets[1] = AssetLimit(NATIVE, 1, type(uint192).max, type(uint192).max);
        m.windowSeconds = 365 days;
        bytes32 id = _register(m);

        for (uint256 i = 0; i < MAX_LIVE_DEBITS; i++) {
            _consume(id, NATIVE, 1, recipient);
        }
        (, uint256 calls) = registry.rollingUsage(id, NATIVE);
        assertEq(calls, MAX_LIVE_DEBITS);

        _assertRejects(id, delegate, NATIVE, 1, recipient, Reason.WINDOW_FULL);

        uint256 t = vm.getBlockTimestamp();
        vm.warp(t + m.windowSeconds);
        _consume(id, NATIVE, 1, recipient);
        (, calls) = registry.rollingUsage(id, NATIVE);
        assertEq(calls, 1);
    }

    // ---------------------------------------------------------------- structure: refused at register

    function test_invalidGrant() public {
        SpendGrant memory m = _andGrant();
        m.delegate = principal;
        _assertRegisterRejects(m);

        m = _andGrant();
        m.recipientMode = 2;
        _assertRegisterRejects(m);

        m = _andGrant();
        m.recipientMode = 1;
        _assertRegisterRejects(m);

        m = _andGrant();
        m.windowSeconds = 0;
        _assertRegisterRejects(m);

        // An unknown recipientMode fails closed by itself: with the zero recipient that mode 1 requires, modes 2 and
        // 255 are still INVALID_GRANT. The lifecycle suite checks the same at update.
        uint8[2] memory unknownModes = [2, type(uint8).max];
        for (uint256 i = 0; i < unknownModes.length; i++) {
            m = _andGrant();
            m.recipientMode = unknownModes[i];
            m.recipient = address(0);
            _assertRegisterRejects(m);
        }

        // Descending: 0x1234 sorts before the token listed first.
        m = _andGrant();
        m.assets[1] = AssetLimit(address(0x1234), 1, 1, 1);
        assertLt(uint160(address(0x1234)), uint160(address(token)));
        _expectRegisterRejects(m);
    }

    function test_invalidGrant_remainingStructure() public {
        SpendGrant memory m = _andGrant();
        m.principal = address(0);
        _assertRegisterRejects(m);

        m = _andGrant();
        m.delegate = address(0);
        _assertRegisterRejects(m);

        m = _andGrant();
        m.recipient = principal;
        _assertRegisterRejects(m);

        m = _andGrant();
        m.recipient = address(0);
        _assertRegisterRejects(m);

        m = _andGrant();
        m.assetCombine = 1;
        _assertRegisterRejects(m);

        m = _andGrant();
        m.assetCombine = 2;
        _assertRegisterRejects(m);

        m = _andGrant();
        m.validAfter = m.validUntil;
        _assertRegisterRejects(m);

        m = _andGrant();
        m.assets = new AssetLimit[](0);
        _assertRegisterRejects(m);

        m = _andGrant();
        m.assets[0].maxPerCall = 0;
        _assertRegisterRejects(m);

        m = _andGrant();
        m.assets[0] = AssetLimit(address(token), 5, 4, 10);
        _assertRegisterRejects(m);

        m = _andGrant();
        m.assets[0] = AssetLimit(address(token), 1, 10, 9);
        _assertRegisterRejects(m);

        m = _andGrant();
        m.assets[0] = AssetLimit(address(token), 1, 1, 1);
        m.assets[1] = AssetLimit(address(0), 1, 1, 1);
        _assertRegisterRejects(m);

        m = _andGrant();
        m.assets[1] = AssetLimit(address(0), 1, 1, 1);
        _expectRegisterRejects(m);
    }

    function test_zeroAddressAsset_isInvalidGrant() public {
        SpendGrant memory m = _andGrant();
        m.assets[0] = AssetLimit(address(0), 1, 1, 1);
        _expectRegisterRejects(m);
    }

    function test_nativeAsset_withNoCode_isAccepted() public {
        bytes32 id = _register(_andGrant());
        assertEq(NATIVE.code.length, 0);
        _consume(id, NATIVE, 1, recipient);
        (uint256 spent,) = registry.usage(id, NATIVE);
        assertEq(spent, 1);
    }

    function test_assets_oneToSixteen() public {
        SpendGrant memory m = _andGrant();
        AssetLimit[] memory one = new AssetLimit[](1);
        one[0] = AssetLimit(NATIVE, 1, 1, 1);
        m.assets = one;
        bytes32 oneId = _register(m);
        _consume(oneId, NATIVE, 1, recipient);

        m = _andGrant();
        AssetLimit[] memory max = new AssetLimit[](16);
        for (uint256 i = 0; i < 15; i++) {
            address a = address(uint160(0x1000 + i));
            vm.etch(a, hex"00");
            max[i] = AssetLimit(a, 1, 1, 1);
        }
        max[15] = AssetLimit(NATIVE, 1, 1, 1);
        m.assets = max;
        m.salt = 99;
        bytes32 maxId = _register(m);
        _consume(maxId, NATIVE, 1, recipient);

        // Ascending, so the count is the only rule broken.
        AssetLimit[] memory tooMany = new AssetLimit[](17);
        for (uint256 i = 0; i < 16; i++) {
            address a = address(uint160(0x1000 + i));
            vm.etch(a, hex"00");
            tooMany[i] = AssetLimit(a, 1, 1, 1);
        }
        tooMany[16] = AssetLimit(NATIVE, 1, 1, 1);
        m.assets = tooMany;
        m.salt = 100;
        _expectRegisterRejects(m);
    }

    // ---------------------------------------------------------------- principals: no grant signature exists

    /// Any account, EOA or contract, registers only grants naming itself as principal. A contract principal's
    /// grants are what its own calls register; its owner's key, calling directly, registers nothing for it, and
    /// the account cannot register a grant naming anyone else.
    function test_anyAccountRegistersOnlyGrantsNamingItself() public {
        OwnedAccount account = new OwnedAccount(principal);
        SpendGrant memory forAccount = _andGrant();
        forAccount.principal = address(account);
        bytes memory registerForAccount = abi.encodeCall(ISpendGrantRegistry.register, (forAccount));

        vm.prank(principal);
        (bool ok, bytes memory ret) = address(registry).call(registerForAccount);
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(NotPrincipal.selector));

        vm.prank(principal);
        bytes32 id = abi.decode(account.exec(address(registry), registerForAccount), (bytes32));
        assertEq(id, registry.hashGrant(forAccount));
        (address p, address d) = registry.parties(id);
        assertEq(p, address(account));
        assertEq(d, delegate);
        _consume(id, NATIVE, 1, recipient);
        (uint256 spent,) = registry.usage(id, NATIVE);
        assertEq(spent, 1);

        bytes memory registerForOwner = abi.encodeCall(ISpendGrantRegistry.register, (_andGrant()));
        vm.prank(principal);
        vm.expectRevert(abi.encodeWithSelector(NotPrincipal.selector));
        account.exec(address(registry), registerForOwner);
    }

    /// A grant does not depend on its principal's code. The principal registers as a plain EOA, then delegates
    /// under EIP-7702 to code with no ERC-1271, to an ERC-1271 that rejects everything, and to code that reverts
    /// on every call, then clears the delegation: the grant keeps spending by id through the executor at every
    /// step. While delegated the account registers and revokes by its own calls; another key registers nothing
    /// for it.
    function test_7702Principal_delegationNeverTouchesItsGrants() public {
        bytes32 id = _registerOn(execRegistry, _andGrant());
        address noErc1271 = address(new No1271());
        address rejecting = address(new AlwaysRejects1271());
        address reverting = address(new RevertsOnEveryCall());

        // 1. Plain EOA.
        assertEq(principal.code.length, 0);
        _spendAndAssertSpent(id, 10, 10);

        // 2. Delegated to code with no ERC-1271, then to an ERC-1271 that always rejects.
        vm.signAndAttachDelegation(noErc1271, PRINCIPAL_PK);
        assertEq(principal.code, abi.encodePacked(hex"ef0100", noErc1271));
        _spendAndAssertSpent(id, 10, 20);
        vm.signAndAttachDelegation(rejecting, PRINCIPAL_PK);
        assertEq(principal.code, abi.encodePacked(hex"ef0100", rejecting));
        _spendAndAssertSpent(id, 10, 30);

        // 3. Delegated to code that reverts on every call, so a spend that called the principal would fail.
        vm.signAndAttachDelegation(reverting, PRINCIPAL_PK);
        assertEq(principal.code, abi.encodePacked(hex"ef0100", reverting));
        (bool called,) = principal.call("");
        assertFalse(called);
        _spendAndAssertSpent(id, 10, 40);

        // The delegated account registers a second grant by its own call; another key cannot register it.
        SpendGrant memory second = _andGrant();
        second.salt = 2;
        address otherKey = vm.addr(0x7702D);
        vm.prank(otherKey);
        (bool ok, bytes memory ret) = address(execRegistry).call(abi.encodeCall(ISpendGrantRegistry.register, (second)));
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(NotPrincipal.selector));
        bytes32 secondId = _registerOn(execRegistry, second);
        _spendAndAssertSpent(secondId, 10, 10);

        // 4. Delegation cleared: a plain EOA again.
        vm.etch(principal, "");
        assertEq(principal.code.length, 0);
        _spendAndAssertSpent(id, 10, 50);

        // 5. Delegated again, the account revokes by id; the next spend is REVOKED.
        vm.signAndAttachDelegation(reverting, PRINCIPAL_PK);
        assertEq(principal.code, abi.encodePacked(hex"ef0100", reverting));
        vm.prank(principal);
        execRegistry.revoke(id);
        vm.prank(delegate);
        _expect(Reason.REVOKED);
        executor.spend(id, address(token), 10, recipient);
    }

    /// 23 bytes of code that are not an EIP-7702 designator are an ordinary contract when spent as the asset: the
    /// code check passes and the debit is recorded. A designator begins with all three bytes `0xef0100`, so the same
    /// code with `0x00` or `0x60` in place of `0xef` passes the check too. The designator prefix in the same place
    /// fails it.
    function test_23ByteCodeNotDesignator_asAssetPassesCodeCheck() public {
        address asset23 = address(uint160(address(token)) - 1);
        vm.etch(asset23, new bytes(23));
        assertEq(asset23.code.length, 23);
        SpendGrant memory m = _andGrant();
        m.assets[0] = AssetLimit(asset23, 5, 10, 10);
        bytes32 id = _register(m);

        _consume(id, asset23, 5, recipient);
        (uint256 spent, uint256 calls) = registry.usage(id, asset23);
        assertEq(spent, 5);
        assertEq(calls, 1);

        bytes[2] memory nearDesignators =
            [abi.encodePacked(hex"000100", address(0xC0DE1E55)), abi.encodePacked(hex"600100", address(0xC0DE1E55))];
        for (uint256 i = 0; i < nearDesignators.length; i++) {
            vm.etch(asset23, nearDesignators[i]);
            assertEq(asset23.code.length, 23);
            (bool ok, Reason r) = registry.check(id, delegate, asset23, 5, recipient);
            assertTrue(ok);
            assertEq(uint8(r), uint8(Reason.OK));
        }

        vm.etch(asset23, abi.encodePacked(hex"ef0100", address(0xC0DE1E55)));
        assertEq(asset23.code.length, 23);
        _expect(Reason.INVALID_GRANT);
        _consume(id, asset23, 5, recipient);
    }

    function test_window_liveIfTimestampGoesBackwards() public {
        SpendGrant memory m = _andGrant();
        m.windowSeconds = 100;
        m.assets[1] = AssetLimit(NATIVE, 5, 5, 100);
        bytes32 id = _register(m);

        uint256 t0 = vm.getBlockTimestamp() + 50;
        vm.warp(t0);
        _consume(id, NATIVE, 5, recipient);

        vm.warp(t0 - 1);
        (uint256 rolling,) = registry.rollingUsage(id, NATIVE);
        assertEq(rolling, 5);
        _expect(Reason.OVER_WINDOW_CAP);
        _consume(id, NATIVE, 1, recipient);
    }

    function test_consume_emitsGrantConsumed() public {
        bytes32 id = _register(_andGrant());
        vm.expectEmit(true, true, true, true, address(registry));
        emit GrantConsumed(id, principal, NATIVE, 1 ether, recipient);
        _consume(id, NATIVE, 1 ether, recipient);
    }

    function testFuzz_consumeNeverExceedsCaps(uint256 amount, uint256 warpBy, uint8 nCalls) public {
        SpendGrant memory m = _andGrant();
        m.assets[1] = AssetLimit(NATIVE, 100, 1_000, 5_000);
        nCalls = uint8(bound(nCalls, 1, 40));
        bytes32 id = _register(m);

        for (uint256 i = 0; i < nCalls; i++) {
            uint256 t = vm.getBlockTimestamp();
            vm.warp(t + bound(warpBy, 0, uint256(m.windowSeconds) * 2));
            if (vm.getBlockTimestamp() >= m.validUntil) break;

            uint256 amt = bound(amount, 1, m.assets[1].maxPerCall);
            (uint256 spent,) = registry.usage(id, NATIVE);
            (uint256 rolling, uint256 liveCalls) = registry.rollingUsage(id, NATIVE);

            // Check order mirrors the registry: OVER_WINDOW_CAP, then OVER_CUMULATIVE_CAP,
            // then WINDOW_FULL last (unreachable at nCalls <= 40 but kept for parity).
            if (rolling + amt > m.assets[1].maxPerWindow) {
                _assertRejects(id, delegate, NATIVE, amt, recipient, Reason.OVER_WINDOW_CAP);
                continue;
            }
            if (spent + amt > m.assets[1].maxTotal) {
                _assertRejects(id, delegate, NATIVE, amt, recipient, Reason.OVER_CUMULATIVE_CAP);
                break;
            }
            if (liveCalls >= MAX_LIVE_DEBITS) {
                _assertRejects(id, delegate, NATIVE, amt, recipient, Reason.WINDOW_FULL);
                break;
            }
            _consume(id, NATIVE, amt, recipient);
        }

        (uint256 endSpent,) = registry.usage(id, NATIVE);
        (uint256 endRolling,) = registry.rollingUsage(id, NATIVE);
        assertLe(endSpent, m.assets[1].maxTotal);
        assertLe(endRolling, m.assets[1].maxPerWindow);
    }

    function test_reason_ordinalsStable() public pure {
        assertEq(uint8(Reason.OK), 0);
        assertEq(uint8(Reason.INVALID_GRANT), 1);
        // Reserved: no grant signature exists, so this version never returns 2; the number keeps its meaning.
        assertEq(uint8(Reason.BAD_SIGNATURE), 2);
        assertEq(uint8(Reason.NOT_YET_VALID), 3);
        assertEq(uint8(Reason.EXPIRED), 4);
        assertEq(uint8(Reason.REVOKED), 5);
        assertEq(uint8(Reason.WRONG_ASSET), 6);
        assertEq(uint8(Reason.WRONG_RECIPIENT), 7);
        assertEq(uint8(Reason.OVER_TX_CAP), 8);
        assertEq(uint8(Reason.OVER_WINDOW_CAP), 9);
        assertEq(uint8(Reason.OVER_CUMULATIVE_CAP), 10);
        assertEq(uint8(Reason.WINDOW_FULL), 11);
        assertEq(uint8(Reason.UNAUTHORIZED_EXECUTOR), 12);
        assertEq(uint8(Reason.UNAUTHORIZED_DELEGATE), 13);
        assertEq(uint8(Reason.NONEXISTENT), 14);
        assertEq(uint8(type(Reason).max), 14);
    }

    // ---------------------------------------------------------------- helpers

    function _andGrant() internal view returns (SpendGrant memory m) {
        m.principal = principal;
        m.delegate = delegate;
        m.recipientMode = 0;
        m.recipient = recipient;
        m.assetCombine = 0;
        m.windowSeconds = 3600;
        m.validAfter = 1_700_000_000;
        m.validUntil = 1_800_000_000;
        m.salt = 1;
        m.assets = new AssetLimit[](2);
        m.assets[0] = AssetLimit(address(token), 1e18, 5e18, 10e18);
        m.assets[1] = AssetLimit(NATIVE, 1 ether, 5 ether, 10 ether);
    }

    /// Registered on `registry`: an asset with an EIP-7702 designator for code, one with no code, the token and
    /// NATIVE, in ascending order.
    function _registerCodeCheckGrant() internal returns (bytes32 id, address codeless, address designator) {
        designator = address(uint160(address(token)) - 2);
        codeless = address(uint160(address(token)) - 1);
        vm.etch(designator, abi.encodePacked(hex"ef0100", address(0xC0DE1E55)));
        assertEq(codeless.code.length, 0);
        SpendGrant memory m = _andGrant();
        AssetLimit[] memory assets = new AssetLimit[](4);
        assets[0] = AssetLimit(designator, 1, 1, 1);
        assets[1] = AssetLimit(codeless, 1, 1, 1);
        assets[2] = m.assets[0];
        assets[3] = m.assets[1];
        m.assets = assets;
        id = _register(m);
    }

    function _register(SpendGrant memory m) internal returns (bytes32) {
        return _registerOn(registry, m);
    }

    function _registerOn(SpendGrantRegistry reg, SpendGrant memory m) internal returns (bytes32 id) {
        vm.prank(m.principal);
        id = reg.register(m);
    }

    /// `consume` on `registry`, whose executor is this contract, authorized by the delegate.
    function _consume(bytes32 id, address asset, uint256 amount, address to) internal {
        registry.consume(id, delegate, asset, amount, to);
    }

    /// The delegate spends `amount` of the token by id through the executor; the grant's lifetime spend is then
    /// `expectedSpent`.
    function _spendAndAssertSpent(bytes32 id, uint256 amount, uint256 expectedSpent) internal {
        vm.prank(delegate);
        executor.spend(id, address(token), amount, recipient);
        (uint256 spent,) = execRegistry.usage(id, address(token));
        assertEq(spent, expectedSpent);
    }

    /// `consume` on `registry` (from its executor) fails with exactly `SpendGrantError(r)`.
    function _assertRejects(bytes32 id, address authorizer, address asset, uint256 amount, address to, Reason r)
        internal
    {
        (bool ok, bytes memory ret) =
            address(registry).call(abi.encodeCall(ISpendGrantRegistry.consume, (id, authorizer, asset, amount, to)));
        assertFalse(ok);
        assertEq(ret, _err(r));
    }

    /// `executor.spend` called by `caller` fails with exactly `expected`.
    function _assertSpendRejects(
        address caller,
        bytes32 id,
        address asset,
        uint256 amount,
        address to,
        bytes memory expected
    ) internal {
        vm.prank(caller);
        (bool ok, bytes memory ret) =
            address(executor).call(abi.encodeCall(SpendGrantExecutor.spend, (id, asset, amount, to)));
        assertFalse(ok);
        assertEq(ret, expected);
    }

    function _assertCheck(SpendGrantRegistry reg, bytes32 id, address authorizer, address asset, Reason expected)
        internal
        view
    {
        (bool ok, Reason r) = reg.check(id, authorizer, asset, 1 ether, recipient);
        assertFalse(ok);
        assertEq(uint8(r), uint8(expected));
    }

    /// `register` by the terms' principal fails with exactly `SpendGrantError(INVALID_GRANT)`.
    function _assertRegisterRejects(SpendGrant memory m) internal {
        vm.prank(m.principal);
        (bool ok, bytes memory ret) = address(registry).call(abi.encodeCall(ISpendGrantRegistry.register, (m)));
        assertFalse(ok);
        assertEq(ret, _err(Reason.INVALID_GRANT));
    }

    /// As `_assertRegisterRejects`, for the last call of a test.
    function _expectRegisterRejects(SpendGrant memory m) internal {
        vm.prank(m.principal);
        _expect(Reason.INVALID_GRANT);
        registry.register(m);
    }

    function _two(AssetLimit memory a, AssetLimit memory b) internal pure returns (AssetLimit[] memory list) {
        list = new AssetLimit[](2);
        (list[0], list[1]) = a.asset < b.asset ? (a, b) : (b, a);
    }

    function _err(Reason r) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(SpendGrantError.selector, r);
    }

    function _expect(Reason r) internal {
        vm.expectRevert(_err(r));
    }
}
