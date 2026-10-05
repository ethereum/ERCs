// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AssetLimit, IERC1271, SpendGrant, SpendGrantError, Reason} from "../src/SpendGrantTypes.sol";
import {SpendGrantHash} from "../src/SpendGrantHash.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";
import {SpendGrantExecutor} from "../src/SpendGrantExecutor.sol";
import {SpendGrantRedemptionEnforcer} from "../src/SpendGrantRedemptionEnforcer.sol";
import {SpendGrantRedemptionExecutor} from "../src/SpendGrantRedemptionExecutor.sol";
import {MockERC20} from "./MockERC20.sol";

interface ICaveatHooks {
    function beforeHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address) external;
    function afterHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address) external;
}

interface IDeleGator {
    function executeFromExecutor(bytes32 mode, bytes calldata executionCalldata) external;
}

/// @dev The parts of an ERC-7710 manager that decide who calls whom, modelled on MetaMask's
/// DelegationManager v1.3.0: the caller must be the leaf delegation's delegate unless that delegation
/// names ANY_DELEGATE; each delegation's delegator must be the next delegation's delegate; every
/// caveat's beforeHook receives the caller as redeemer and its own delegation's delegator; the root
/// delegation's delegator performs the execution; afterHooks run after it. Delegation signatures and
/// authority hashes are not verified here; they do not change the call shape.
contract MockDelegationManager {
    address public constant ANY_DELEGATE = address(0xa11);

    error InvalidDelegate();

    struct Caveat {
        address enforcer;
        bytes terms;
        bytes args;
    }

    struct Delegation {
        address delegate;
        address delegator;
        bytes32 authority;
        Caveat[] caveats;
        uint256 salt;
        bytes signature;
    }

    function redeemDelegations(
        bytes[] memory permissionContexts,
        bytes32[] memory modes,
        bytes[] memory executionCalldatas
    ) external {
        for (uint256 b = 0; b < permissionContexts.length; b++) {
            _redeem(abi.decode(permissionContexts[b], (Delegation[])), modes[b], executionCalldatas[b]);
        }
    }

    function _redeem(Delegation[] memory chain, bytes32 mode, bytes memory executionCalldata) internal {
        if (chain[0].delegate != msg.sender && chain[0].delegate != ANY_DELEGATE) revert InvalidDelegate();
        for (uint256 i = 0; i + 1 < chain.length; i++) {
            if (chain[i + 1].delegate != ANY_DELEGATE && chain[i].delegator != chain[i + 1].delegate) {
                revert InvalidDelegate();
            }
        }
        for (uint256 i = 0; i < chain.length; i++) {
            _hooks(chain[i], mode, executionCalldata, true);
        }
        IDeleGator(chain[chain.length - 1].delegator).executeFromExecutor(mode, executionCalldata);
        for (uint256 i = chain.length; i > 0; i--) {
            _hooks(chain[i - 1], mode, executionCalldata, false);
        }
    }

    function _hooks(Delegation memory d, bytes32 mode, bytes memory executionCalldata, bool before) internal {
        bytes32 delegationHash = keccak256(abi.encode(d.delegate, d.delegator, d.authority, d.salt));
        for (uint256 c = 0; c < d.caveats.length; c++) {
            _hook(d.caveats[c], mode, executionCalldata, delegationHash, d.delegator, before);
        }
    }

    function _hook(
        Caveat memory caveat,
        bytes32 mode,
        bytes memory executionCalldata,
        bytes32 delegationHash,
        address delegator,
        bool before
    ) internal {
        if (before) {
            ICaveatHooks(caveat.enforcer).beforeHook(
                caveat.terms, caveat.args, mode, executionCalldata, delegationHash, delegator, msg.sender
            );
        } else {
            ICaveatHooks(caveat.enforcer).afterHook(
                caveat.terms, caveat.args, mode, executionCalldata, delegationHash, delegator, msg.sender
            );
        }
    }
}

/// @dev A smart account the manager drives: executes a single call and bubbles its revert, and
/// validates ERC-1271 signatures by its owner key.
contract MockDeleGator {
    error NotManager();
    error UnsupportedMode();

    address internal immutable MANAGER;
    address internal immutable OWNER;

    constructor(address manager_, address owner_) {
        MANAGER = manager_;
        OWNER = owner_;
    }

    function executeFromExecutor(bytes32 mode, bytes calldata executionCalldata) external virtual {
        if (msg.sender != MANAGER) revert NotManager();
        if (mode[0] != 0x00 || mode[1] != 0x00) revert UnsupportedMode();
        _exec(executionCalldata);
    }

    function isValidSignature(bytes32 hash_, bytes calldata sig) external view returns (bytes4) {
        if (sig.length != 65) return 0xffffffff;
        bytes32 r = bytes32(sig[:32]);
        bytes32 s = bytes32(sig[32:64]);
        uint8 v = uint8(sig[64]);
        return ecrecover(hash_, v, r, s) == OWNER ? IERC1271.isValidSignature.selector : bytes4(0xffffffff);
    }

    function _exec(bytes calldata executionCalldata) internal {
        address target = address(bytes20(executionCalldata[:20]));
        uint256 value = uint256(bytes32(executionCalldata[20:52]));
        (bool ok, bytes memory ret) = target.call{value: value}(executionCalldata[52:]);
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
    }
}

/// @dev An account that performs the execution twice: the second call must find no record left.
contract DoubleExecDeleGator is MockDeleGator {
    constructor(address manager_, address owner_) MockDeleGator(manager_, owner_) {}

    function executeFromExecutor(bytes32, bytes calldata executionCalldata) external override {
        _exec(executionCalldata);
        _exec(executionCalldata);
    }
}

contract SpendGrantRedemptionTest is Test {
    uint256 internal constant OWNER_PK = 0xA11CE;
    uint256 internal constant EOA_PRINCIPAL_PK = 0xA11CF;

    bytes32 internal constant SINGLE_DEFAULT = bytes32(0);
    bytes32 internal constant BATCH_DEFAULT = bytes32(uint256(0x01) << 248);
    bytes32 internal constant SINGLE_TRY = bytes32(uint256(0x01) << 240);

    MockDelegationManager internal manager;
    SpendGrantRegistry internal registry;
    SpendGrantRedemptionEnforcer internal enforcer;
    SpendGrantRedemptionExecutor internal executor;
    MockERC20 internal token;
    MockDeleGator internal principalAccount;

    address internal owner;
    address internal delegate;
    address internal subDelegate;
    address internal recipient;
    address internal stranger;

    function setUp() public {
        owner = vm.addr(OWNER_PK);
        delegate = vm.addr(0xB0B);
        subDelegate = vm.addr(0x5AB);
        recipient = vm.addr(0xC0C);
        stranger = vm.addr(0xBAD);

        token = new MockERC20();
        manager = new MockDelegationManager();

        uint64 nonce = vm.getNonce(address(this));
        address predictedExecutor = vm.computeCreateAddress(address(this), nonce + 2);
        registry = new SpendGrantRegistry(predictedExecutor);
        enforcer = new SpendGrantRedemptionEnforcer(address(manager), predictedExecutor, address(registry));
        executor = new SpendGrantRedemptionExecutor(registry, enforcer);
        assertEq(address(executor), predictedExecutor);

        principalAccount = new MockDeleGator(address(manager), owner);
        _fund(address(principalAccount));

        vm.warp(1_700_000_000);
    }

    // ---------------------------------------------------------------- shape two: redeemer is the delegate

    function test_redemption_byDelegate_recordsRedeemerAndSpends() public {
        SpendGrant memory m = _grant(address(principalAccount), delegate);
        bytes memory sig = _sign(OWNER_PK, m);
        bytes32 h = _hash(m);
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](1);
        chain[0] = _delegation(delegate, address(principalAccount), true);

        uint256 principalBefore = token.balanceOf(address(principalAccount));

        _redeem(delegate, chain, SINGLE_DEFAULT, _execution(m, sig, 1e18, recipient));

        assertEq(principalBefore - token.balanceOf(address(principalAccount)), 1e18);
        assertEq(token.balanceOf(recipient), 1e18);
        (uint256 spent, uint256 calls) = registry.usage(h, address(token));
        assertEq(spent, 1e18);
        assertEq(calls, 1);
        // Cleared when taken, so nothing in this transaction can use it again.
        assertEq(enforcer.recorded(address(principalAccount), h, address(token), 1e18, recipient), address(0));
    }

    function test_redemption_bySubDelegate_isRejected() public {
        SpendGrant memory m = _grant(address(principalAccount), delegate);
        bytes memory sig = _sign(OWNER_PK, m);
        // Leaf: delegate -> subDelegate. Root: principal -> delegate, carrying the caveat.
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](2);
        chain[0] = _delegation(subDelegate, delegate, false);
        chain[1] = _delegation(delegate, address(principalAccount), true);

        _redeemExpecting(Reason.UNAUTHORIZED_DELEGATE, subDelegate, chain, _execution(m, sig, 1e18, recipient));
        _assertNothingSpent(m);
    }

    function test_redemption_openDelegation_onlyGrantDelegatePasses() public {
        SpendGrant memory m = _grant(address(principalAccount), delegate);
        bytes memory sig = _sign(OWNER_PK, m);
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](1);
        chain[0] = _delegation(manager.ANY_DELEGATE(), address(principalAccount), true);
        bytes memory execution = _execution(m, sig, 1e18, recipient);

        // Whoever calls is recorded as the redeemer; the registry rejects everyone but the delegate.
        _redeemExpecting(Reason.UNAUTHORIZED_DELEGATE, stranger, chain, execution);
        _assertNothingSpent(m);

        _redeem(delegate, chain, SINGLE_DEFAULT, execution);
        (uint256 spent,) = registry.usage(_hash(m), address(token));
        assertEq(spent, 1e18);
    }

    function test_redemption_recordAuthorizesOneConsume() public {
        DoubleExecDeleGator twice = new DoubleExecDeleGator(address(manager), owner);
        _fund(address(twice));
        SpendGrant memory m = _grant(address(twice), delegate);
        bytes memory sig = _sign(OWNER_PK, m);
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](1);
        chain[0] = _delegation(delegate, address(twice), true);

        // The first spend takes the record; the second finds none and the whole redemption reverts.
        _redeemExpecting(Reason.UNAUTHORIZED_DELEGATE, delegate, chain, _execution(m, sig, 1e18, recipient));
        _assertNothingSpent(m);
        assertEq(token.balanceOf(address(twice)), 1e24);
    }

    function test_redemption_recordBoundToAnotherAccountIsNeverRead() public {
        // The redeemer is the grant's delegate, so the record names an acceptable authorizer. It sits
        // on the leaf, whose delegator is an intermediary, not the account that executes, so the
        // executor never finds it: the binding to the executing account alone causes the rejection.
        address intermediary = vm.addr(0x1111);
        SpendGrant memory m = _grant(address(principalAccount), delegate);
        bytes memory sig = _sign(OWNER_PK, m);
        bytes32 h = _hash(m);
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](2);
        chain[0] = _delegation(delegate, intermediary, true);
        chain[1] = _delegation(intermediary, address(principalAccount), false);

        _redeemExpecting(Reason.UNAUTHORIZED_DELEGATE, delegate, chain, _execution(m, sig, 1e18, recipient));
        _assertNothingSpent(m);
        // The reverted redemption also rolled the record back.
        assertEq(enforcer.recorded(intermediary, h, address(token), 1e18, recipient), address(0));
    }

    // ---------------------------------------------------------------- shape one: the delegate's account calls

    function test_directCall_byDelegateAccount_acceptsItsSubDelegate() public {
        // Principal is an EOA; the delegate is a smart account that re-delegated to subDelegate.
        MockDeleGator delegateAccount = new MockDeleGator(address(manager), owner);
        address eoaPrincipal = vm.addr(EOA_PRINCIPAL_PK);
        _fund(eoaPrincipal);
        SpendGrant memory m = _grant(eoaPrincipal, address(delegateAccount));
        bytes memory sig = _sign(EOA_PRINCIPAL_PK, m);
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](1);
        chain[0] = _delegation(subDelegate, address(delegateAccount), true);

        // The executor is called by grant.delegate itself, so this is a direct call: the record the
        // enforcer wrote (naming subDelegate) is not consulted, and the delegate account's own
        // delegation policy is what let subDelegate drive it.
        _redeem(subDelegate, chain, SINGLE_DEFAULT, _execution(m, sig, 1e18, recipient));

        assertEq(token.balanceOf(recipient), 1e18);
        assertEq(token.balanceOf(eoaPrincipal), 1e24 - 1e18);
        (uint256 spent,) = registry.usage(_hash(m), address(token));
        assertEq(spent, 1e18);
    }

    function test_directCall_byDelegate_needsNoRecord() public {
        SpendGrant memory m = _grant(address(principalAccount), delegate);
        bytes memory sig = _sign(OWNER_PK, m);

        vm.prank(delegate);
        executor.spend(m, sig, address(token), 1e18, recipient);

        assertEq(token.balanceOf(recipient), 1e18);
    }

    function test_directCall_byStranger_isRejectedWithoutRecord() public {
        SpendGrant memory m = _grant(address(principalAccount), delegate);
        bytes memory sig = _sign(OWNER_PK, m);

        // The executor rejects before the registry is reached: no record is no authorization, and it
        // never passes a placeholder authorizer.
        vm.expectCall(address(registry), abi.encodeWithSelector(registry.consume.selector), 0);
        vm.prank(stranger);
        _expect(Reason.UNAUTHORIZED_DELEGATE);
        executor.spend(m, sig, address(token), 1e18, recipient);
        _assertNothingSpent(m);
    }

    // ---------------------------------------------------------------- the record itself

    function test_take_clearsAndIsExecutorOnly() public {
        SpendGrant memory m = _grant(address(principalAccount), delegate);
        bytes32 h = _hash(m);
        _writeRecord(m, address(principalAccount), delegate);
        assertEq(enforcer.recorded(address(principalAccount), h, address(token), 1e18, recipient), delegate);

        vm.prank(stranger);
        vm.expectRevert(SpendGrantRedemptionEnforcer.NotExecutor.selector);
        enforcer.take(address(principalAccount), h, address(token), 1e18, recipient);

        vm.prank(address(executor));
        assertEq(enforcer.take(address(principalAccount), h, address(token), 1e18, recipient), delegate);
        vm.prank(address(executor));
        assertEq(enforcer.take(address(principalAccount), h, address(token), 1e18, recipient), address(0));
        assertEq(enforcer.recorded(address(principalAccount), h, address(token), 1e18, recipient), address(0));
    }

    function test_record_isScopedToSpendAndExecutingAccount() public {
        SpendGrant memory m = _grant(address(principalAccount), delegate);
        bytes32 h = _hash(m);
        _writeRecord(m, address(principalAccount), delegate);

        SpendGrant memory other = m;
        other.salt = 2;
        bytes32 otherHash = _hash(other);

        vm.startPrank(address(executor));
        assertEq(enforcer.take(address(principalAccount), h, address(token), 2e18, recipient), address(0));
        assertEq(enforcer.take(address(principalAccount), h, address(token), 1e18, stranger), address(0));
        assertEq(enforcer.take(address(principalAccount), h, address(0xA55E7), 1e18, recipient), address(0));
        assertEq(enforcer.take(address(principalAccount), otherHash, address(token), 1e18, recipient), address(0));
        assertEq(enforcer.take(stranger, h, address(token), 1e18, recipient), address(0));
        // Misses do not disturb the record; the exact spend still finds it.
        assertEq(enforcer.recorded(address(principalAccount), h, address(token), 1e18, recipient), delegate);
        assertEq(enforcer.take(address(principalAccount), h, address(token), 1e18, recipient), delegate);
        vm.stopPrank();
    }

    function test_enforcer_onlyManagerWrites() public {
        SpendGrant memory m = _grant(address(principalAccount), delegate);
        bytes memory execution = _execution(m, _sign(OWNER_PK, m), 1e18, recipient);

        vm.prank(stranger);
        vm.expectRevert(SpendGrantRedemptionEnforcer.NotManager.selector);
        enforcer.beforeHook("", "", SINGLE_DEFAULT, execution, bytes32(0), address(principalAccount), delegate);
        assertEq(enforcer.recorded(address(principalAccount), _hash(m), address(token), 1e18, recipient), address(0));
    }

    function test_enforcer_failsClosed() public {
        SpendGrant memory m = _grant(address(principalAccount), delegate);
        bytes memory sig = _sign(OWNER_PK, m);
        bytes memory execution = _execution(m, sig, 1e18, recipient);
        bytes memory spendCall = abi.encodeCall(SpendGrantExecutor.spend, (m, sig, address(token), 1e18, recipient));

        vm.startPrank(address(manager));

        vm.expectRevert(SpendGrantRedemptionEnforcer.UnsupportedMode.selector);
        enforcer.beforeHook("", "", BATCH_DEFAULT, execution, bytes32(0), address(principalAccount), delegate);

        vm.expectRevert(SpendGrantRedemptionEnforcer.UnsupportedMode.selector);
        enforcer.beforeHook("", "", SINGLE_TRY, execution, bytes32(0), address(principalAccount), delegate);

        vm.expectRevert(SpendGrantRedemptionEnforcer.MalformedExecution.selector);
        enforcer.beforeHook("", "", SINGLE_DEFAULT, hex"00", bytes32(0), address(principalAccount), delegate);

        vm.expectRevert(SpendGrantRedemptionEnforcer.WrongTarget.selector);
        enforcer.beforeHook(
            "",
            "",
            SINGLE_DEFAULT,
            abi.encodePacked(address(token), uint256(0), spendCall),
            bytes32(0),
            address(principalAccount),
            delegate
        );

        vm.expectRevert(SpendGrantRedemptionEnforcer.NonzeroValue.selector);
        enforcer.beforeHook(
            "",
            "",
            SINGLE_DEFAULT,
            abi.encodePacked(address(executor), uint256(1), spendCall),
            bytes32(0),
            address(principalAccount),
            delegate
        );

        vm.expectRevert(SpendGrantRedemptionEnforcer.WrongCall.selector);
        enforcer.beforeHook(
            "",
            "",
            SINGLE_DEFAULT,
            abi.encodePacked(address(executor), uint256(0), abi.encodeCall(SpendGrantExecutor.registry, ())),
            bytes32(0),
            address(principalAccount),
            delegate
        );

        vm.stopPrank();
        assertEq(enforcer.recorded(address(principalAccount), _hash(m), address(token), 1e18, recipient), address(0));
    }

    function test_constructor_rejectsEnforcerForAnotherExecutor() public {
        uint64 nonce = vm.getNonce(address(this));
        address predicted = vm.computeCreateAddress(address(this), nonce + 1);
        SpendGrantRegistry other = new SpendGrantRegistry(predicted);
        vm.expectRevert(SpendGrantRedemptionExecutor.EnforcerMismatch.selector);
        new SpendGrantRedemptionExecutor(other, enforcer);
    }

    // ---------------------------------------------------------------- helpers

    function _fund(address account) internal {
        token.mint(account, 1e24);
        vm.prank(account);
        token.approve(address(executor), type(uint256).max);
    }

    function _grant(address principal_, address delegate_) internal view returns (SpendGrant memory m) {
        m.principal = principal_;
        m.delegate = delegate_;
        m.recipientMode = 0;
        m.recipient = recipient;
        m.assetCombine = 0;
        m.windowSeconds = 86400;
        m.validAfter = 1_699_999_000;
        m.validUntil = 1_900_000_000;
        m.salt = 1;
        m.assets = new AssetLimit[](1);
        m.assets[0] = AssetLimit(address(token), 1e18, 10e18, 100e18);
    }

    function _hash(SpendGrant memory m) internal view returns (bytes32) {
        return SpendGrantHash.digest(block.chainid, address(registry), m);
    }

    function _sign(uint256 pk, SpendGrant memory m) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _hash(m));
        return abi.encodePacked(r, s, v);
    }

    /// @dev ERC-7579 single execution targeting the executor's `spend`.
    function _execution(SpendGrant memory m, bytes memory sig, uint256 amount, address to)
        internal
        view
        returns (bytes memory)
    {
        return abi.encodePacked(
            address(executor),
            uint256(0),
            abi.encodeCall(SpendGrantExecutor.spend, (m, sig, address(token), amount, to))
        );
    }

    function _delegation(address delegate_, address delegator_, bool withCaveat)
        internal
        view
        returns (MockDelegationManager.Delegation memory d)
    {
        d.delegate = delegate_;
        d.delegator = delegator_;
        d.authority = bytes32(0);
        d.salt = 0;
        d.caveats = new MockDelegationManager.Caveat[](withCaveat ? 1 : 0);
        if (withCaveat) d.caveats[0] = MockDelegationManager.Caveat(address(enforcer), "", "");
    }

    function _redeem(
        address caller,
        MockDelegationManager.Delegation[] memory chain,
        bytes32 mode,
        bytes memory execution
    ) internal {
        bytes[] memory contexts = new bytes[](1);
        contexts[0] = abi.encode(chain);
        bytes32[] memory modes = new bytes32[](1);
        modes[0] = mode;
        bytes[] memory executions = new bytes[](1);
        executions[0] = execution;
        vm.prank(caller);
        manager.redeemDelegations(contexts, modes, executions);
    }

    function _redeemExpecting(
        Reason r,
        address caller,
        MockDelegationManager.Delegation[] memory chain,
        bytes memory execution
    ) internal {
        bytes[] memory contexts = new bytes[](1);
        contexts[0] = abi.encode(chain);
        bytes32[] memory modes = new bytes32[](1);
        modes[0] = SINGLE_DEFAULT;
        bytes[] memory executions = new bytes[](1);
        executions[0] = execution;
        vm.prank(caller);
        _expect(r);
        manager.redeemDelegations(contexts, modes, executions);
    }

    /// @dev Writes a record the way the manager would, for tests of the record alone.
    function _writeRecord(SpendGrant memory m, address executingAccount, address redeemer) internal {
        bytes memory execution = _execution(m, _sign(OWNER_PK, m), 1e18, recipient);
        vm.prank(address(manager));
        enforcer.beforeHook("", "", SINGLE_DEFAULT, execution, bytes32(0), executingAccount, redeemer);
    }

    function _assertNothingSpent(SpendGrant memory m) internal view {
        (uint256 spent, uint256 calls) = registry.usage(_hash(m), address(token));
        assertEq(spent, 0);
        assertEq(calls, 0);
        assertEq(token.balanceOf(recipient), 0);
    }

    function _expect(Reason r) internal {
        vm.expectRevert(abi.encodeWithSelector(SpendGrantError.selector, r));
    }
}
