// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {
    AssetLimit,
    IERC1271,
    MAX_LIVE_DEBITS,
    NATIVE,
    SpendGrant,
    SpendGrantError,
    Reason
} from "../src/SpendGrantTypes.sol";
import {SpendGrantHash} from "../src/SpendGrantHash.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";
import {SpendGrantExecutor} from "../src/SpendGrantExecutor.sol";
import {MockERC20} from "./MockERC20.sol";

contract Mock1271 {
    bytes32 public allowed;

    function setAllowed(bytes32 hash_) external {
        allowed = hash_;
    }

    function isValidSignature(bytes32 hash_, bytes calldata) external view returns (bytes4) {
        return hash_ == allowed ? IERC1271.isValidSignature.selector : bytes4(0);
    }
}

/// @dev Has code but no isValidSignature; a 7702 delegation target whose ERC-1271 call reverts.
contract No1271 {}

contract Short1271 {
    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        assembly {
            mstore(0, shl(224, 0x1626ba7e))
            return(0, 4)
        }
    }
}

contract Reverting1271 {
    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        revert();
    }
}

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

/// @dev 7702 delegate implementation with an ERC-1271 function that always rejects.
contract AlwaysRejects1271 {
    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return 0xffffffff;
    }
}

contract SpendGrantRegistryTest is Test {
    uint256 internal constant PRINCIPAL_PK = 0xA11CE;
    uint256 internal constant DELEGATE_PK = 0xB0B;

    SpendGrantRegistry internal registry;
    SpendGrantRegistry internal execRegistry;
    SpendGrantExecutor internal executor;
    MockERC20 internal token;

    address internal principal;
    address internal delegate;
    address internal recipient;

    event GrantRevoked(address indexed principal, bytes32 indexed grantHash);
    event GrantConsumed(bytes32 indexed grantHash, address indexed asset, uint256 amount, address indexed recipient);

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

        token.mint(principal, 1e24);
        vm.prank(principal);
        token.approve(address(executor), type(uint256).max);

        vm.warp(1_700_000_000);
    }

    function test_revoke_emitsOnceAndBlocksConsume() public {
        SpendGrant memory m = _andGrant();
        bytes32 h = SpendGrantHash.digest(block.chainid, address(registry), m);

        vm.prank(address(0xBEEF));
        registry.revoke(h);
        assertTrue(registry.revoked(address(0xBEEF), h));
        assertFalse(registry.revoked(principal, h));

        _consume(m, NATIVE, 1 ether, recipient);

        vm.prank(principal);
        vm.expectEmit(true, true, false, true);
        emit GrantRevoked(principal, h);
        registry.revoke(h);
        assertTrue(registry.revoked(principal, h));

        vm.prank(principal);
        vm.recordLogs();
        registry.revoke(h);
        assertEq(vm.getRecordedLogs().length, 0);

        _expect(Reason.REVOKED);
        _consume(m, NATIVE, 1 ether, recipient);
    }

    function test_unauthorizedConsume() public {
        SpendGrant memory m = _andGrant();
        vm.prank(delegate);
        _expect(Reason.UNAUTHORIZED_EXECUTOR);
        registry.consume(m, _sig(m, address(registry)), m.delegate, NATIVE, 1 ether, recipient);
    }

    function test_consume_authorizerMustBeDelegate() public {
        SpendGrant memory m = _andGrant();
        bytes memory sig = _sig(m, address(registry));
        bytes32 h = _hash(m);

        address[3] memory badAuthorizers = [principal, vm.addr(0xBAD), address(0)];
        for (uint256 i = 0; i < badAuthorizers.length; i++) {
            _expect(Reason.UNAUTHORIZED_DELEGATE);
            registry.consume(m, sig, badAuthorizers[i], NATIVE, 1 ether, recipient);
        }

        (uint256 spent, uint256 calls) = registry.usage(h, NATIVE);
        assertEq(spent, 0);
        assertEq(calls, 0);

        registry.consume(m, sig, m.delegate, NATIVE, 1 ether, recipient);
        (spent, calls) = registry.usage(h, NATIVE);
        assertEq(spent, 1 ether);
        assertEq(calls, 1);
    }

    function test_ordering_unauthorizedExecutorBeforeDelegate() public {
        SpendGrant memory m = _andGrant();
        bytes memory sig = _sig(m, address(registry));

        vm.prank(vm.addr(0xBAD));
        _expect(Reason.UNAUTHORIZED_EXECUTOR);
        registry.consume(m, sig, vm.addr(0xBAD), NATIVE, 1, recipient);
    }

    function test_ordering_unauthorizedDelegateBeforeInvalidGrant() public {
        SpendGrant memory m = _andGrant();
        m.windowSeconds = 0;
        _expect(Reason.UNAUTHORIZED_DELEGATE);
        registry.consume(m, _sig(m, address(registry)), vm.addr(0xBAD), NATIVE, 1, recipient);

        m = _andGrant();
        m.delegate = address(0);
        _expect(Reason.UNAUTHORIZED_DELEGATE);
        registry.consume(m, _sig(m, address(registry)), vm.addr(0xBAD), NATIVE, 1, recipient);

        m = _andGrant();
        m.delegate = principal;
        _expect(Reason.UNAUTHORIZED_DELEGATE);
        registry.consume(m, _sig(m, address(registry)), vm.addr(0xBAD), NATIVE, 1, recipient);
    }

    function test_ordering_invalidGrantWithRightAuthorizer() public {
        SpendGrant memory m = _andGrant();
        m.windowSeconds = 0;
        _expect(Reason.INVALID_GRANT);
        registry.consume(m, _sig(m, address(registry)), m.delegate, NATIVE, 1, recipient);

        m = _andGrant();
        m.delegate = address(0);
        _expect(Reason.INVALID_GRANT);
        registry.consume(m, _sig(m, address(registry)), address(0), NATIVE, 1, recipient);

        m = _andGrant();
        m.delegate = principal;
        _expect(Reason.INVALID_GRANT);
        registry.consume(m, _sig(m, address(registry)), principal, NATIVE, 1, recipient);
    }

    function test_ordering_unauthorizedDelegateBeforeBadSignature() public {
        SpendGrant memory m = _andGrant();
        _expect(Reason.UNAUTHORIZED_DELEGATE);
        registry.consume(m, hex"11", vm.addr(0xBAD), NATIVE, 1, recipient);
    }

    function test_timeBounds() public {
        SpendGrant memory m = _andGrant();
        uint256 validAfter = uint256(m.validAfter);
        uint256 validUntil = uint256(m.validUntil);

        vm.warp(validAfter - 1);
        _expect(Reason.NOT_YET_VALID);
        _consume(m, NATIVE, 1, recipient);

        vm.warp(validAfter);
        _consume(m, NATIVE, 1, recipient);

        vm.warp(validUntil);
        _expect(Reason.EXPIRED);
        _consume(m, NATIVE, 1, recipient);

        vm.warp(validUntil - 1);
        _consume(m, NATIVE, 1, recipient);
    }

    function test_wrongAssetAndRecipient() public {
        SpendGrant memory m = _andGrant();
        _expect(Reason.WRONG_ASSET);
        _consume(m, address(0x1234), 1, recipient);

        _expect(Reason.WRONG_RECIPIENT);
        _consume(m, NATIVE, 1, address(0x9999));

        m.recipientMode = 1;
        m.recipient = address(0);
        _consume(m, NATIVE, 1, address(0x9999));
    }

    function test_perCallWindowLifetime() public {
        SpendGrant memory m = _andGrant();
        m.assets[1] = AssetLimit(NATIVE, 10, 25, 30);

        _expect(Reason.OVER_TX_CAP);
        _consume(m, NATIVE, 0, recipient);
        _expect(Reason.OVER_TX_CAP);
        _consume(m, NATIVE, 11, recipient);

        _consume(m, NATIVE, 10, recipient);
        _consume(m, NATIVE, 10, recipient);
        _expect(Reason.OVER_WINDOW_CAP);
        _consume(m, NATIVE, 10, recipient);

        uint256 t = vm.getBlockTimestamp();
        vm.warp(t + m.windowSeconds);
        _consume(m, NATIVE, 10, recipient);
        _expect(Reason.OVER_CUMULATIVE_CAP);
        _consume(m, NATIVE, 10, recipient);

        (uint256 spent, uint256 calls) = registry.usage(_hash(m), NATIVE);
        assertEq(spent, 30);
        assertEq(calls, 3);
    }

    function test_andIndependent() public {
        SpendGrant memory m = _andGrant();
        _consume(m, NATIVE, 1 ether, recipient);
        _consume(m, address(token), 1e18, recipient);

        (uint256 nativeSpent,) = registry.usage(_hash(m), NATIVE);
        (uint256 tokenSpent,) = registry.usage(_hash(m), address(token));
        assertEq(nativeSpent, 1 ether);
        assertEq(tokenSpent, 1e18);

        (uint256 nativeRoll,) = registry.rollingUsage(_hash(m), NATIVE);
        (uint256 tokenRoll,) = registry.rollingUsage(_hash(m), address(token));
        assertEq(nativeRoll, 1 ether);
        assertEq(tokenRoll, 1e18);
    }

    function test_executor_erc20HappyPath() public {
        SpendGrant memory m = _andGrant();
        bytes memory sig = _sig(m, address(execRegistry));
        bytes32 grantHash = SpendGrantHash.digest(block.chainid, address(execRegistry), m);

        uint256 recipientBefore = token.balanceOf(recipient);
        uint256 principalBefore = token.balanceOf(principal);

        vm.prank(delegate);
        executor.spend(m, sig, address(token), 1e18, recipient);

        assertEq(token.balanceOf(recipient) - recipientBefore, 1e18);
        assertEq(principalBefore - token.balanceOf(principal), 1e18);
        (uint256 spent, uint256 calls) = execRegistry.usage(grantHash, address(token));
        assertEq(spent, 1e18);
        assertEq(calls, 1);
    }

    function test_executor_mode1_callerRecipient() public {
        SpendGrant memory m = _andGrant();
        m.recipientMode = 1;
        m.recipient = address(0);
        bytes memory sig = _sig(m, address(execRegistry));
        address other = vm.addr(0xD0D);

        uint256 principalBefore = token.balanceOf(principal);

        vm.prank(delegate);
        executor.spend(m, sig, address(token), 1e18, other);

        assertEq(token.balanceOf(other), 1e18);
        assertEq(principalBefore - token.balanceOf(principal), 1e18);
    }

    function test_executor_revertsIfTransferFails() public {
        RevertingERC20 bad = new RevertingERC20();
        SpendGrant memory m = _andGrant();
        AssetLimit[] memory assets = new AssetLimit[](1);
        assets[0] = AssetLimit(address(bad), 1, 1, 1);
        m.assets = assets;
        bytes memory sig = _sig(m, address(execRegistry));

        vm.prank(delegate);
        vm.expectRevert(SpendGrantExecutor.TransferFailed.selector);
        executor.spend(m, sig, address(bad), 1, recipient);

        (uint256 spent, uint256 calls) =
            execRegistry.usage(SpendGrantHash.digest(block.chainid, address(execRegistry), m), address(bad));
        assertEq(spent, 0);
        assertEq(calls, 0);
    }

    function test_executor_rejectsMsgValue() public {
        SpendGrant memory m = _andGrant();
        bytes memory sig = _sig(m, address(execRegistry));
        bytes32 grantHash = SpendGrantHash.digest(block.chainid, address(execRegistry), m);

        vm.deal(delegate, 1 ether);
        uint256 delegateBalanceBefore = delegate.balance;
        // Funded, so an empty revert below is the non-payable dispatcher, not OutOfFunds.
        assertEq(delegateBalanceBefore, 1 ether);
        uint256 principalTokenBefore = token.balanceOf(principal);
        uint256 recipientTokenBefore = token.balanceOf(recipient);

        // spend is non-payable: the dispatcher reverts with empty data before the body runs, so
        // neither the ERC-20 path nor the NATIVE guard (which reverts with a selector) is reached.
        vm.prank(delegate);
        (bool ok, bytes memory ret) =
            address(executor).call{value: 1}(abi.encodeCall(executor.spend, (m, sig, address(token), 1e18, recipient)));
        assertFalse(ok);
        assertEq(ret.length, 0);

        vm.prank(delegate);
        (bool okNative, bytes memory retNative) =
            address(executor).call{value: 1}(abi.encodeCall(executor.spend, (m, sig, NATIVE, 1e18, recipient)));
        assertFalse(okNative);
        assertEq(retNative.length, 0);

        (uint256 tokenSpent, uint256 tokenCalls) = execRegistry.usage(grantHash, address(token));
        (uint256 nativeSpent, uint256 nativeCalls) = execRegistry.usage(grantHash, NATIVE);
        assertEq(tokenSpent, 0);
        assertEq(tokenCalls, 0);
        assertEq(nativeSpent, 0);
        assertEq(nativeCalls, 0);
        assertEq(token.balanceOf(principal), principalTokenBefore);
        assertEq(token.balanceOf(recipient), recipientTokenBefore);
        assertEq(delegate.balance, delegateBalanceBefore);

        // Control: the same call without value succeeds, so the value alone caused the revert.
        vm.prank(delegate);
        executor.spend(m, sig, address(token), 1e18, recipient);
        (tokenSpent, tokenCalls) = execRegistry.usage(grantHash, address(token));
        assertEq(tokenSpent, 1e18);
        assertEq(tokenCalls, 1);
    }

    function test_executor_erc20FalseReturnRollsBack() public {
        FalseERC20 bad = new FalseERC20();
        SpendGrant memory m = _andGrant();
        m.assets[0] = AssetLimit(address(bad), 1, 1, 1);
        bytes memory sig = _sig(m, address(execRegistry));

        vm.prank(delegate);
        vm.expectRevert(SpendGrantExecutor.TransferFailed.selector);
        executor.spend(m, sig, address(bad), 1, recipient);

        (uint256 spent, uint256 calls) =
            execRegistry.usage(SpendGrantHash.digest(block.chainid, address(execRegistry), m), address(bad));
        assertEq(spent, 0);
        assertEq(calls, 0);
    }

    function test_executor_rejectsNative() public {
        vm.deal(delegate, 2 ether);
        uint256 delegateBalanceBefore = delegate.balance;

        SpendGrant memory m0 = _andGrant();
        bytes memory sig0 = _sig(m0, address(execRegistry));
        bytes32 grantHash0 = SpendGrantHash.digest(block.chainid, address(execRegistry), m0);
        uint256 recipientBalanceBefore = recipient.balance;

        vm.prank(delegate);
        vm.expectRevert(SpendGrantExecutor.NativeRequiresAccountAdapter.selector);
        executor.spend(m0, sig0, NATIVE, 1 ether, recipient);

        (uint256 spent0, uint256 calls0) = execRegistry.usage(grantHash0, NATIVE);
        (uint256 rolling0, uint256 rollingCalls0) = execRegistry.rollingUsage(grantHash0, NATIVE);
        assertEq(spent0, 0);
        assertEq(calls0, 0);
        assertEq(rolling0, 0);
        assertEq(rollingCalls0, 0);
        assertEq(recipient.balance, recipientBalanceBefore);
        assertEq(delegate.balance, delegateBalanceBefore);

        SpendGrant memory m1 = _andGrant();
        m1.recipientMode = 1;
        m1.recipient = address(0);
        bytes memory sig1 = _sig(m1, address(execRegistry));
        bytes32 grantHash1 = SpendGrantHash.digest(block.chainid, address(execRegistry), m1);
        address other = vm.addr(0xD0D);
        uint256 otherBalanceBefore = other.balance;

        vm.prank(delegate);
        vm.expectRevert(SpendGrantExecutor.NativeRequiresAccountAdapter.selector);
        executor.spend(m1, sig1, NATIVE, 1 ether, other);

        (uint256 spent1, uint256 calls1) = execRegistry.usage(grantHash1, NATIVE);
        (uint256 rolling1, uint256 rollingCalls1) = execRegistry.rollingUsage(grantHash1, NATIVE);
        assertEq(spent1, 0);
        assertEq(calls1, 0);
        assertEq(rolling1, 0);
        assertEq(rollingCalls1, 0);
        assertEq(other.balance, otherBalanceBefore);
        assertEq(delegate.balance, delegateBalanceBefore);
    }

    /// @dev The NATIVE guard runs before consume: each call below would otherwise fail inside
    /// consume with a different reason (UNAUTHORIZED_DELEGATE, BAD_SIGNATURE, WRONG_ASSET).
    function test_executor_rejectsNativeBeforeConsume() public {
        SpendGrant memory m = _andGrant();
        bytes memory sig = _sig(m, address(execRegistry));

        vm.prank(vm.addr(0xBAD));
        vm.expectRevert(SpendGrantExecutor.NativeRequiresAccountAdapter.selector);
        executor.spend(m, sig, NATIVE, 1 ether, recipient);

        vm.prank(delegate);
        vm.expectRevert(SpendGrantExecutor.NativeRequiresAccountAdapter.selector);
        executor.spend(m, hex"11", NATIVE, 1 ether, recipient);

        SpendGrant memory tokenOnly = _andGrant();
        AssetLimit[] memory one = new AssetLimit[](1);
        one[0] = tokenOnly.assets[0];
        tokenOnly.assets = one;
        bytes memory tokenOnlySig = _sig(tokenOnly, address(execRegistry));

        vm.prank(delegate);
        vm.expectRevert(SpendGrantExecutor.NativeRequiresAccountAdapter.selector);
        executor.spend(tokenOnly, tokenOnlySig, NATIVE, 1 ether, recipient);
    }

    /// @dev The delegate spends once (making the grant and signature public), then a third party
    /// or the principal replays the same grant/signature through the executor. Snapshots every
    /// balance and usage counter that must stay frozen across the blocked replay.
    function _assertExecutorReplayBlocked(SpendGrant memory m, bytes memory sig, address caller, address recipientArg)
        internal
    {
        bytes32 grantHash = SpendGrantHash.digest(block.chainid, address(execRegistry), m);
        address effectiveRecipient = recipientArg;

        uint256 principalBefore = token.balanceOf(principal);
        uint256 recipientBefore = token.balanceOf(effectiveRecipient);
        uint256 callerBefore = token.balanceOf(caller);
        (uint256 spentBefore, uint256 callsBefore) = execRegistry.usage(grantHash, address(token));
        (uint256 rollingBefore, uint256 rollingCallsBefore) = execRegistry.rollingUsage(grantHash, address(token));

        vm.prank(caller);
        _expect(Reason.UNAUTHORIZED_DELEGATE);
        executor.spend(m, sig, address(token), 1e18, recipientArg);

        assertEq(token.balanceOf(principal), principalBefore);
        assertEq(token.balanceOf(effectiveRecipient), recipientBefore);
        assertEq(token.balanceOf(caller), callerBefore);
        (uint256 spentAfter, uint256 callsAfter) = execRegistry.usage(grantHash, address(token));
        (uint256 rollingAfter, uint256 rollingCallsAfter) = execRegistry.rollingUsage(grantHash, address(token));
        assertEq(spentAfter, spentBefore);
        assertEq(callsAfter, callsBefore);
        assertEq(rollingAfter, rollingBefore);
        assertEq(rollingCallsAfter, rollingCallsBefore);
    }

    function test_executor_replayByThirdParty_mode0() public {
        SpendGrant memory m = _andGrant();
        bytes memory sig = _sig(m, address(execRegistry));

        vm.prank(delegate);
        executor.spend(m, sig, address(token), 1e18, recipient);

        _assertExecutorReplayBlocked(m, sig, vm.addr(0xBAD), recipient);
    }

    function test_executor_replayByThirdParty_mode1() public {
        SpendGrant memory m = _andGrant();
        m.recipientMode = 1;
        m.recipient = address(0);
        bytes memory sig = _sig(m, address(execRegistry));

        vm.prank(delegate);
        executor.spend(m, sig, address(token), 1e18, recipient);

        address attacker = vm.addr(0xBAD);
        _assertExecutorReplayBlocked(m, sig, attacker, attacker);
    }

    function test_executor_replayByPrincipal_mode0() public {
        SpendGrant memory m = _andGrant();
        bytes memory sig = _sig(m, address(execRegistry));

        vm.prank(delegate);
        executor.spend(m, sig, address(token), 1e18, recipient);

        _assertExecutorReplayBlocked(m, sig, principal, recipient);
    }

    function test_executor_replayByPrincipal_mode1() public {
        SpendGrant memory m = _andGrant();
        m.recipientMode = 1;
        m.recipient = address(0);
        bytes memory sig = _sig(m, address(execRegistry));

        vm.prank(delegate);
        executor.spend(m, sig, address(token), 1e18, recipient);

        _assertExecutorReplayBlocked(m, sig, principal, principal);
    }

    function test_executor_mode0_wrongRecipientReverts() public {
        SpendGrant memory m = _andGrant();
        bytes memory sig = _sig(m, address(execRegistry));
        bytes32 grantHash = SpendGrantHash.digest(block.chainid, address(execRegistry), m);
        address other = vm.addr(0xD0D);
        uint256 principalBefore = token.balanceOf(principal);

        vm.prank(delegate);
        _expect(Reason.WRONG_RECIPIENT);
        executor.spend(m, sig, address(token), 1e18, other);

        assertEq(token.balanceOf(principal), principalBefore);
        assertEq(token.balanceOf(other), 0);
        (uint256 spent, uint256 calls) = execRegistry.usage(grantHash, address(token));
        assertEq(spent, 0);
        assertEq(calls, 0);

        vm.prank(delegate);
        executor.spend(m, sig, address(token), 1e18, recipient);
        assertEq(token.balanceOf(recipient), 1e18);
    }

    function test_registry_rejectsZeroExecutor() public {
        vm.expectRevert(SpendGrantRegistry.ZeroExecutor.selector);
        new SpendGrantRegistry(address(0));
    }

    function testFuzz_executor_onlyDelegateCanSpend(address caller, address to, bool mode1) public {
        vm.assume(caller != delegate);
        SpendGrant memory m = _andGrant();
        if (mode1) {
            m.recipientMode = 1;
            m.recipient = address(0);
        }
        bytes memory sig = _sig(m, address(execRegistry));
        bytes32 grantHash = SpendGrantHash.digest(block.chainid, address(execRegistry), m);

        uint256 principalBefore = token.balanceOf(principal);
        (uint256 spentBefore, uint256 callsBefore) = execRegistry.usage(grantHash, address(token));

        vm.prank(caller);
        _expect(Reason.UNAUTHORIZED_DELEGATE);
        executor.spend(m, sig, address(token), 1e18, to);

        assertEq(token.balanceOf(principal), principalBefore);
        (uint256 spentAfter, uint256 callsAfter) = execRegistry.usage(grantHash, address(token));
        assertEq(spentAfter, spentBefore);
        assertEq(callsAfter, callsBefore);
    }

    function test_windowExpiryAtExactAge() public {
        SpendGrant memory m = _andGrant();
        m.windowSeconds = 100;
        m.assets[1] = AssetLimit(NATIVE, 5, 5, 100);

        uint256 t0 = vm.getBlockTimestamp();
        _consume(m, NATIVE, 5, recipient);

        (uint256 rolling,) = registry.rollingUsage(_hash(m), NATIVE);
        assertEq(rolling, 5);

        vm.warp(t0 + 99);
        (rolling,) = registry.rollingUsage(_hash(m), NATIVE);
        assertEq(rolling, 5);
        _expect(Reason.OVER_WINDOW_CAP);
        _consume(m, NATIVE, 1, recipient);

        vm.warp(t0 + 100);
        (rolling,) = registry.rollingUsage(_hash(m), NATIVE);
        assertEq(rolling, 0);
        _consume(m, NATIVE, 5, recipient);
        (rolling,) = registry.rollingUsage(_hash(m), NATIVE);
        assertEq(rolling, 5);
    }

    function test_windowFullAtMaxLiveDebitsEvents() public {
        SpendGrant memory m = _andGrant();
        m.assets[1] = AssetLimit(NATIVE, 1, type(uint192).max, type(uint192).max);
        m.windowSeconds = 365 days;

        for (uint256 i = 0; i < MAX_LIVE_DEBITS; i++) {
            _consume(m, NATIVE, 1, recipient);
        }
        (, uint256 calls) = registry.rollingUsage(_hash(m), NATIVE);
        assertEq(calls, MAX_LIVE_DEBITS);

        _expect(Reason.WINDOW_FULL);
        _consume(m, NATIVE, 1, recipient);

        uint256 t = vm.getBlockTimestamp();
        vm.warp(t + m.windowSeconds);
        _consume(m, NATIVE, 1, recipient);
        (, calls) = registry.rollingUsage(_hash(m), NATIVE);
        assertEq(calls, 1);
    }

    function test_badSignatureAnd1271() public {
        SpendGrant memory m = _andGrant();
        bytes memory sig = _sig(m, address(registry));
        sig[0] = bytes1(uint8(sig[0]) ^ 1);
        _expect(Reason.BAD_SIGNATURE);
        registry.consume(m, sig, m.delegate, NATIVE, 1, recipient);

        Mock1271 wallet = new Mock1271();
        m.principal = address(wallet);
        bytes32 digest_ = SpendGrantHash.digest(block.chainid, address(registry), m);
        _expect(Reason.BAD_SIGNATURE);
        registry.consume(m, hex"11", m.delegate, NATIVE, 1, recipient);

        wallet.setAllowed(digest_);
        registry.consume(m, hex"11", m.delegate, NATIVE, 1, recipient);
    }

    function test_invalidGrant() public {
        SpendGrant memory m = _andGrant();
        m.delegate = principal;
        _expect(Reason.INVALID_GRANT);
        _consume(m, NATIVE, 1, recipient);

        m = _andGrant();
        m.recipientMode = 2;
        _expect(Reason.INVALID_GRANT);
        _consume(m, NATIVE, 1, recipient);

        m = _andGrant();
        m.recipientMode = 1;
        _expect(Reason.INVALID_GRANT);
        _consume(m, NATIVE, 1, recipient);

        m = _andGrant();
        m.windowSeconds = 0;
        _expect(Reason.INVALID_GRANT);
        _consume(m, NATIVE, 1, recipient);

        m = _andGrant();
        m.assets[1] = AssetLimit(address(0x1234), 1, 1, 1);
        _expect(Reason.INVALID_GRANT);
        _consume(m, NATIVE, 1, recipient);
    }

    function test_invalidGrant_remainingStructure() public {
        SpendGrant memory m = _andGrant();
        m.principal = address(0);
        _expect(Reason.INVALID_GRANT);
        _consume(m, NATIVE, 1, recipient);

        m = _andGrant();
        m.delegate = address(0);
        _expect(Reason.INVALID_GRANT);
        _consume(m, NATIVE, 1, recipient);

        m = _andGrant();
        m.recipient = principal;
        _expect(Reason.INVALID_GRANT);
        _consume(m, NATIVE, 1, recipient);

        m = _andGrant();
        m.recipient = address(0);
        _expect(Reason.INVALID_GRANT);
        _consume(m, NATIVE, 1, recipient);

        m = _andGrant();
        m.assetCombine = 1;
        _expect(Reason.INVALID_GRANT);
        _consume(m, NATIVE, 1, recipient);

        m = _andGrant();
        m.assetCombine = 2;
        _expect(Reason.INVALID_GRANT);
        _consume(m, NATIVE, 1, recipient);

        m = _andGrant();
        m.validAfter = m.validUntil;
        _expect(Reason.INVALID_GRANT);
        _consume(m, NATIVE, 1, recipient);

        m = _andGrant();
        m.assets = new AssetLimit[](0);
        _expect(Reason.INVALID_GRANT);
        _consume(m, NATIVE, 1, recipient);

        m = _andGrant();
        m.assets[0].maxPerCall = 0;
        _expect(Reason.INVALID_GRANT);
        _consume(m, NATIVE, 1, recipient);

        m = _andGrant();
        m.assets[0] = AssetLimit(address(token), 5, 4, 10);
        _expect(Reason.INVALID_GRANT);
        _consume(m, NATIVE, 1, recipient);

        m = _andGrant();
        m.assets[0] = AssetLimit(address(token), 1, 10, 9);
        _expect(Reason.INVALID_GRANT);
        _consume(m, NATIVE, 1, recipient);

        m = _andGrant();
        m.assets[0] = AssetLimit(address(token), 1, 1, 1);
        m.assets[1] = AssetLimit(address(0), 1, 1, 1);
        _expect(Reason.INVALID_GRANT);
        _consume(m, address(token), 1, recipient);

        m = _andGrant();
        m.assets[1] = AssetLimit(address(0), 1, 1, 1);
        _expect(Reason.INVALID_GRANT);
        _consume(m, NATIVE, 1, recipient);
    }

    function test_zeroAddressAsset_isInvalidGrant() public {
        SpendGrant memory m = _andGrant();
        m.assets[0] = AssetLimit(address(0), 1, 1, 1);
        _expect(Reason.INVALID_GRANT);
        _consume(m, address(0), 1, recipient);
    }

    function test_nativeAsset_withNoCode_isAccepted() public {
        SpendGrant memory m = _andGrant();
        assertEq(NATIVE.code.length, 0);
        _consume(m, NATIVE, 1, recipient);
    }

    function test_assets_oneToSixteen() public {
        SpendGrant memory m = _andGrant();
        AssetLimit[] memory one = new AssetLimit[](1);
        one[0] = AssetLimit(NATIVE, 1, 1, 1);
        m.assets = one;
        _consume(m, NATIVE, 1, recipient);

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
        _consume(m, NATIVE, 1, recipient);

        AssetLimit[] memory tooMany = new AssetLimit[](17);
        tooMany[0] = AssetLimit(NATIVE, 1, 1, 1);
        for (uint256 i = 1; i < 17; i++) {
            address a = address(uint160(0x1000 + i));
            vm.etch(a, hex"00");
            tooMany[i] = AssetLimit(a, 1, 1, 1);
        }
        m.assets = tooMany;
        m.salt = 100;
        _expect(Reason.INVALID_GRANT);
        _consume(m, NATIVE, 1, recipient);
    }

    function test_signature_rejectsHighSBadVAndLength() public {
        SpendGrant memory m = _andGrant();
        bytes memory sig = _sig(m, address(registry));

        bytes32 highS = bytes32(uint256(0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) + 1);
        assembly {
            mstore(add(sig, 64), highS)
        }
        _expect(Reason.BAD_SIGNATURE);
        registry.consume(m, sig, m.delegate, NATIVE, 1, recipient);

        sig = _sig(m, address(registry));
        sig[64] = bytes1(uint8(26));
        _expect(Reason.BAD_SIGNATURE);
        registry.consume(m, sig, m.delegate, NATIVE, 1, recipient);

        _expect(Reason.BAD_SIGNATURE);
        registry.consume(m, hex"11", m.delegate, NATIVE, 1, recipient);
    }

    function test_1271_shortReturnRevertAndNoEcdsaFallback() public {
        SpendGrant memory m = _andGrant();

        Short1271 shortWallet = new Short1271();
        m.principal = address(shortWallet);
        _expect(Reason.BAD_SIGNATURE);
        registry.consume(m, hex"11", m.delegate, NATIVE, 1, recipient);

        Reverting1271 reverting = new Reverting1271();
        m.principal = address(reverting);
        _expect(Reason.BAD_SIGNATURE);
        registry.consume(m, hex"11", m.delegate, NATIVE, 1, recipient);

        // Code-bearing principal must not fall back to ECDSA even with a 65-byte sig.
        m.principal = address(shortWallet);
        bytes memory eoaSig = _sig(m, address(registry));
        _expect(Reason.BAD_SIGNATURE);
        registry.consume(m, eoaSig, m.delegate, NATIVE, 1, recipient);
    }

    function test_7702_delegatedPrincipal_strictEcdsaSucceeds() public {
        uint256 delegatedPk = 0x7702A;
        address delegated = vm.addr(delegatedPk);
        Mock1271 impl = new Mock1271();
        vm.signAndAttachDelegation(address(impl), delegatedPk);
        assertEq(delegated.code.length, 23);

        SpendGrant memory m = _andGrant();
        m.principal = delegated;
        bytes32 digest_ = SpendGrantHash.digest(block.chainid, address(registry), m);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(delegatedPk, digest_);
        registry.consume(m, abi.encodePacked(r, s, v), m.delegate, NATIVE, 1, recipient);

        (uint256 spent,) = registry.usage(SpendGrantHash.digest(block.chainid, address(registry), m), NATIVE);
        assertEq(spent, 1);
    }

    function test_7702_delegatedPrincipal_fallsBackTo1271() public {
        uint256 delegatedPk = 0x7702B;
        address delegated = vm.addr(delegatedPk);
        Mock1271 impl = new Mock1271();
        vm.signAndAttachDelegation(address(impl), delegatedPk);

        SpendGrant memory m = _andGrant();
        m.principal = delegated;
        bytes32 digest_ = SpendGrantHash.digest(block.chainid, address(registry), m);
        Mock1271(delegated).setAllowed(digest_);

        // A signature that is not a valid 65-byte ECDSA triple, in a "different format".
        registry.consume(m, hex"11", m.delegate, NATIVE, 1, recipient);
    }

    function test_7702_delegatedPrincipal_wrongEcdsaAndNo1271_revertsBadSignature() public {
        uint256 delegatedPk = 0x7702C;
        uint256 wrongPk = 0x7702D;
        address delegated = vm.addr(delegatedPk);
        No1271 impl = new No1271();
        vm.signAndAttachDelegation(address(impl), delegatedPk);

        SpendGrant memory m = _andGrant();
        m.principal = delegated;
        bytes32 digest_ = SpendGrantHash.digest(block.chainid, address(registry), m);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPk, digest_);
        _expect(Reason.BAD_SIGNATURE);
        registry.consume(m, abi.encodePacked(r, s, v), m.delegate, NATIVE, 1, recipient);
    }

    function test_normalContractPrincipal_neverFallsBackToEcdsa() public {
        uint256 ownerPk = 0x0DEADBEEF;
        address owner = vm.addr(ownerPk);
        Mock1271 wallet = new Mock1271();
        vm.etch(owner, address(wallet).code);

        SpendGrant memory m = _andGrant();
        m.principal = owner;
        bytes32 digest_ = SpendGrantHash.digest(block.chainid, address(registry), m);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest_);
        _expect(Reason.BAD_SIGNATURE);
        registry.consume(m, abi.encodePacked(r, s, v), m.delegate, NATIVE, 1, recipient);
    }

    function test_23ByteCodeNotDesignator_treatedAsOrdinaryContract() public {
        uint256 pk = 0x7702E;
        address principalAddr = vm.addr(pk);
        vm.etch(principalAddr, hex"0000000000000000000000000000000000000000000000");
        assertEq(principalAddr.code.length, 23);

        SpendGrant memory m = _andGrant();
        m.principal = principalAddr;
        bytes32 digest_ = SpendGrantHash.digest(block.chainid, address(registry), m);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest_);
        _expect(Reason.BAD_SIGNATURE);
        registry.consume(m, abi.encodePacked(r, s, v), m.delegate, NATIVE, 1, recipient);
    }

    /// @dev End-to-end through SpendGrantExecutor.spend (ERC-20 via transferFrom): a treasury
    /// signs a grant as a plain EOA, then upgrades to (and away from, and back out of) EIP-7702
    /// delegation without ever re-signing. The original ECDSA signature keeps spending because
    /// _validSignature always tries strict ECDSA first for a delegation-designator principal,
    /// independent of whatever the delegate implementation's ERC-1271 does or doesn't do.
    function test_7702_upgradeAfterSigning_keepsGrantValid() public {
        SpendGrant memory m = _andGrant();
        bytes32 grantHash = SpendGrantHash.digest(block.chainid, address(execRegistry), m);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRINCIPAL_PK, grantHash);
        bytes memory sig = abi.encodePacked(r, s, v);

        // 1. Plain EOA, plain EIP-712 ECDSA signature.
        assertEq(principal.code.length, 0);
        vm.prank(delegate);
        executor.spend(m, sig, address(token), 10, recipient);
        (uint256 spent,) = execRegistry.usage(grantHash, address(token));
        assertEq(spent, 10);

        // 2a. Delegate to an implementation with no isValidSignature at all; same signature.
        No1271 implNo1271 = new No1271();
        vm.signAndAttachDelegation(address(implNo1271), PRINCIPAL_PK);
        assertEq(principal.code.length, 23);
        vm.prank(delegate);
        executor.spend(m, sig, address(token), 10, recipient);
        (spent,) = execRegistry.usage(grantHash, address(token));
        assertEq(spent, 20);

        // 2b. Delegate to an implementation whose ERC-1271 always rejects; same signature.
        AlwaysRejects1271 implRejects = new AlwaysRejects1271();
        vm.signAndAttachDelegation(address(implRejects), PRINCIPAL_PK);
        vm.prank(delegate);
        executor.spend(m, sig, address(token), 10, recipient);
        (spent,) = execRegistry.usage(grantHash, address(token));
        assertEq(spent, 30);

        // 3. Delegation changed to a different implementation; same signature still spends.
        Mock1271 implOther = new Mock1271();
        vm.signAndAttachDelegation(address(implOther), PRINCIPAL_PK);
        vm.prank(delegate);
        executor.spend(m, sig, address(token), 10, recipient);
        (spent,) = execRegistry.usage(grantHash, address(token));
        assertEq(spent, 40);

        // 4. Delegation cleared; principal is a plain EOA again; same signature still spends.
        vm.etch(principal, "");
        assertEq(principal.code.length, 0);
        vm.prank(delegate);
        executor.spend(m, sig, address(token), 10, recipient);
        (spent,) = execRegistry.usage(grantHash, address(token));
        assertEq(spent, 50);

        // 5. Revoke while delegated; the next spend reverts REVOKED regardless of signature validity.
        vm.signAndAttachDelegation(address(implOther), PRINCIPAL_PK);
        vm.prank(principal);
        execRegistry.revoke(grantHash);
        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(SpendGrantError.selector, Reason.REVOKED));
        executor.spend(m, sig, address(token), 10, recipient);
    }

    /// @dev Companion to the upgrade-after-signing test: a 7702 principal whose delegate
    /// implementation validates a non-ECDSA (e.g. ERC-7739-style) signature format via
    /// ERC-1271 still spends through the executor's ERC-20 path when that format is used.
    function test_7702_delegatedPrincipal_1271FormatSpendsViaExecutor() public {
        SpendGrant memory m = _andGrant();
        bytes32 grantHash = SpendGrantHash.digest(block.chainid, address(execRegistry), m);

        Mock1271 impl = new Mock1271();
        vm.signAndAttachDelegation(address(impl), PRINCIPAL_PK);
        Mock1271(principal).setAllowed(grantHash);

        // Not a valid 65-byte ECDSA triple; only the ERC-1271 path can accept this format.
        bytes memory altFormatSig = hex"11";
        vm.prank(delegate);
        executor.spend(m, altFormatSig, address(token), 10, recipient);

        (uint256 spent,) = execRegistry.usage(grantHash, address(token));
        assertEq(spent, 10);
    }

    function test_window_liveIfTimestampGoesBackwards() public {
        SpendGrant memory m = _andGrant();
        m.windowSeconds = 100;
        m.assets[1] = AssetLimit(NATIVE, 5, 5, 100);

        uint256 t0 = vm.getBlockTimestamp() + 50;
        vm.warp(t0);
        _consume(m, NATIVE, 5, recipient);

        vm.warp(t0 - 1);
        (uint256 rolling,) = registry.rollingUsage(_hash(m), NATIVE);
        assertEq(rolling, 5);
        _expect(Reason.OVER_WINDOW_CAP);
        _consume(m, NATIVE, 1, recipient);
    }

    function test_consume_emitsGrantConsumed() public {
        SpendGrant memory m = _andGrant();
        bytes32 h = _hash(m);
        vm.expectEmit(true, true, true, true);
        emit GrantConsumed(h, NATIVE, 1 ether, recipient);
        _consume(m, NATIVE, 1 ether, recipient);
    }

    function testFuzz_consumeNeverExceedsCaps(uint256 amount, uint256 warpBy, uint8 nCalls) public {
        SpendGrant memory m = _andGrant();
        m.assets[1] = AssetLimit(NATIVE, 100, 1_000, 5_000);
        nCalls = uint8(bound(nCalls, 1, 40));
        bytes32 h = _hash(m);

        for (uint256 i = 0; i < nCalls; i++) {
            uint256 t = vm.getBlockTimestamp();
            vm.warp(t + bound(warpBy, 0, uint256(m.windowSeconds) * 2));
            if (vm.getBlockTimestamp() >= m.validUntil) break;

            uint256 amt = bound(amount, 1, m.assets[1].maxPerCall);
            (uint256 spent,) = registry.usage(h, NATIVE);
            (uint256 rolling,) = registry.rollingUsage(h, NATIVE);
            (, uint256 liveCalls) = registry.rollingUsage(h, NATIVE);

            // Check order mirrors the registry: OVER_WINDOW_CAP, then OVER_CUMULATIVE_CAP,
            // then WINDOW_FULL last (unreachable at nCalls <= 40 but kept for parity).
            if (rolling + amt > m.assets[1].maxPerWindow) {
                _expect(Reason.OVER_WINDOW_CAP);
                _consume(m, NATIVE, amt, recipient);
                continue;
            }
            if (spent + amt > m.assets[1].maxTotal) {
                _expect(Reason.OVER_CUMULATIVE_CAP);
                _consume(m, NATIVE, amt, recipient);
                break;
            }
            if (liveCalls >= MAX_LIVE_DEBITS) {
                _expect(Reason.WINDOW_FULL);
                _consume(m, NATIVE, amt, recipient);
                break;
            }
            _consume(m, NATIVE, amt, recipient);
        }

        (uint256 endSpent,) = registry.usage(h, NATIVE);
        (uint256 endRolling,) = registry.rollingUsage(h, NATIVE);
        assertLe(endSpent, m.assets[1].maxTotal);
        assertLe(endRolling, m.assets[1].maxPerWindow);
    }

    function test_reason_ordinalsStable() public pure {
        assertEq(uint8(Reason.OK), 0);
        assertEq(uint8(Reason.INVALID_GRANT), 1);
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
    }

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

    function _hash(SpendGrant memory m) internal view returns (bytes32) {
        return SpendGrantHash.digest(block.chainid, address(registry), m);
    }

    function _sig(SpendGrant memory m, address reg) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRINCIPAL_PK, SpendGrantHash.digest(block.chainid, reg, m));
        return abi.encodePacked(r, s, v);
    }

    function _consume(SpendGrant memory m, address asset, uint256 amount, address to) internal {
        registry.consume(m, _sig(m, address(registry)), m.delegate, asset, amount, to);
    }

    function _expect(Reason r) internal {
        vm.expectRevert(abi.encodeWithSelector(SpendGrantError.selector, r));
    }
}
