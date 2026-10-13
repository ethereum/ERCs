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
    function beforeAllHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address)
        external;
    function beforeHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address) external;
    function afterHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address) external;
    function afterAllHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address)
        external;
}

interface IDeleGator {
    function executeFromExecutor(bytes32 mode, bytes calldata executionCalldata) external;
}

/// @dev The parts of an ERC-7710 manager that decide who calls whom, modelled on MetaMask's
/// DelegationManager v1.3.0: the caller must be the leaf delegation's delegate unless that delegation
/// names ANY_DELEGATE; each delegation's delegator must be the next delegation's delegate; each
/// delegation's authority is the next delegation's hash, and the root's is ROOT_AUTHORITY; a delegation's
/// hash commits to each caveat's enforcer and terms but not its args. Hooks run in v1.3.0's order, which
/// HookOrderFork.t.sol checks against the live manager: a beforeAllHook pass over every entry; then per
/// entry, beforeHooks leaf to root, the root delegator's execution, afterHooks root to leaf with each
/// delegation's caveats reversed; then an afterAllHook pass in that reversed order. Every hook receives the
/// caller as redeemer and its own delegation's hash and delegator. Signatures are not verified here.
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

    bytes32 public constant ROOT_AUTHORITY = bytes32(type(uint256).max);

    error InvalidAuthority();

    function getDelegationHash(Delegation calldata d) external pure returns (bytes32) {
        return _hash(d);
    }

    function redeemDelegations(
        bytes[] memory permissionContexts,
        bytes32[] memory modes,
        bytes[] memory executionCalldatas
    ) external {
        uint256 n = permissionContexts.length;
        Delegation[][] memory chains = new Delegation[][](n);
        bytes32[][] memory hashes = new bytes32[][](n);
        for (uint256 b = 0; b < n; b++) {
            chains[b] = abi.decode(permissionContexts[b], (Delegation[]));
            hashes[b] = _validate(chains[b]);
        }
        for (uint256 b = 0; b < n; b++) {
            for (uint256 i = 0; i < chains[b].length; i++) {
                for (uint256 c = 0; c < chains[b][i].caveats.length; c++) {
                    _hook(0, chains[b][i], c, modes[b], executionCalldatas[b], hashes[b][i]);
                }
            }
        }
        for (uint256 b = 0; b < n; b++) {
            Delegation[] memory chain = chains[b];
            for (uint256 i = 0; i < chain.length; i++) {
                for (uint256 c = 0; c < chain[i].caveats.length; c++) {
                    _hook(1, chain[i], c, modes[b], executionCalldatas[b], hashes[b][i]);
                }
            }
            IDeleGator(chain[chain.length - 1].delegator).executeFromExecutor(modes[b], executionCalldatas[b]);
            for (uint256 i = chain.length; i > 0; i--) {
                for (uint256 c = chain[i - 1].caveats.length; c > 0; c--) {
                    _hook(2, chain[i - 1], c - 1, modes[b], executionCalldatas[b], hashes[b][i - 1]);
                }
            }
        }
        for (uint256 b = 0; b < n; b++) {
            for (uint256 i = chains[b].length; i > 0; i--) {
                for (uint256 c = chains[b][i - 1].caveats.length; c > 0; c--) {
                    _hook(3, chains[b][i - 1], c - 1, modes[b], executionCalldatas[b], hashes[b][i - 1]);
                }
            }
        }
    }

    function _validate(Delegation[] memory chain) internal view returns (bytes32[] memory hashes) {
        if (chain[0].delegate != msg.sender && chain[0].delegate != ANY_DELEGATE) revert InvalidDelegate();
        hashes = new bytes32[](chain.length);
        for (uint256 i = 0; i < chain.length; i++) {
            hashes[i] = _hash(chain[i]);
        }
        for (uint256 i = 0; i + 1 < chain.length; i++) {
            if (chain[i + 1].delegate != ANY_DELEGATE && chain[i].delegator != chain[i + 1].delegate) {
                revert InvalidDelegate();
            }
            if (chain[i].authority != hashes[i + 1]) revert InvalidAuthority();
        }
        if (chain[chain.length - 1].authority != ROOT_AUTHORITY) revert InvalidAuthority();
    }

    function _hash(Delegation memory d) internal pure returns (bytes32) {
        bytes32[] memory caveatHashes = new bytes32[](d.caveats.length);
        for (uint256 c = 0; c < d.caveats.length; c++) {
            caveatHashes[c] = keccak256(abi.encode(d.caveats[c].enforcer, keccak256(d.caveats[c].terms)));
        }
        return keccak256(
            abi.encode(d.delegate, d.delegator, d.authority, keccak256(abi.encodePacked(caveatHashes)), d.salt)
        );
    }

    function _hook(
        uint256 kind,
        Delegation memory d,
        uint256 c,
        bytes32 mode,
        bytes memory executionCalldata,
        bytes32 delegationHash
    ) internal {
        Caveat memory cv = d.caveats[c];
        ICaveatHooks e = ICaveatHooks(cv.enforcer);
        if (kind == 0) {
            e.beforeAllHook(cv.terms, cv.args, mode, executionCalldata, delegationHash, d.delegator, msg.sender);
        } else if (kind == 1) {
            e.beforeHook(cv.terms, cv.args, mode, executionCalldata, delegationHash, d.delegator, msg.sender);
        } else if (kind == 2) {
            e.afterHook(cv.terms, cv.args, mode, executionCalldata, delegationHash, d.delegator, msg.sender);
        } else {
            e.afterAllHook(cv.terms, cv.args, mode, executionCalldata, delegationHash, d.delegator, msg.sender);
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

/// @dev A hostile intermediate delegator that is also a caveat enforcer on its own delegation. During a
/// hook it calls the executor itself with the execution's spend data, trying to ride the delegate's
/// redemption for a second spend. Its ERC-1271 accepts anything so a manager can validate its delegation.
contract EvilDelegator {
    SpendGrantRedemptionExecutor internal immutable EXECUTOR;
    bool internal immutable IN_BEFORE;

    constructor(SpendGrantRedemptionExecutor executor_, bool inBefore) {
        EXECUTOR = executor_;
        IN_BEFORE = inBefore;
    }

    function beforeHook(bytes calldata, bytes calldata, bytes32, bytes calldata exec, bytes32, address, address)
        external
    {
        if (IN_BEFORE) _strike(exec);
    }

    function afterHook(bytes calldata, bytes calldata, bytes32, bytes calldata exec, bytes32, address, address)
        external
    {
        if (!IN_BEFORE) _strike(exec);
    }

    function beforeAllHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address)
        external
        pure
    {}

    function afterAllHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address)
        external
        pure
    {}

    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return IERC1271.isValidSignature.selector;
    }

    function _strike(bytes calldata exec) internal {
        (bool ok, bytes memory ret) = address(EXECUTOR).call(exec[52:]);
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

/// @dev The scenario matrix's adversary. It strikes once, at one chosen point: one of its own hooks when it
/// sits on a delegation, or the token callback when it is the recipient. It redeems a caveat-free delegation
/// whose execution is the same spend, and catches whatever that does.
contract MatrixThief {
    uint8 internal constant NONE = 0;
    uint8 internal constant BEFORE_ALL = 1;
    uint8 internal constant BEFORE = 2;
    uint8 internal constant AFTER = 3;
    uint8 internal constant AFTER_ALL = 4;
    uint8 internal constant TOKEN = 5;

    MockDelegationManager internal immutable MANAGER;
    uint8 internal point;
    bool public struck;
    bool public nestedSpent;
    bytes internal nestedContext;
    bytes internal nestedExecution;

    constructor(MockDelegationManager manager_) {
        MANAGER = manager_;
    }

    function arm(uint8 point_, bytes memory context, bytes memory execution) external {
        (point, struck, nestedSpent, nestedContext, nestedExecution) = (point_, false, false, context, execution);
    }

    function beforeAllHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address)
        external
    {
        _strike(BEFORE_ALL);
    }

    function beforeHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address) external {
        _strike(BEFORE);
    }

    function afterHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address) external {
        _strike(AFTER);
    }

    function afterAllHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address)
        external
    {
        _strike(AFTER_ALL);
    }

    function onTokenReceived() external {
        _strike(TOKEN);
    }

    function _strike(uint8 at) internal {
        if (struck || at != point) return;
        struck = true;
        bytes[] memory contexts = new bytes[](1);
        contexts[0] = nestedContext;
        bytes32[] memory modes = new bytes32[](1);
        bytes[] memory executions = new bytes[](1);
        executions[0] = nestedExecution;
        try MANAGER.redeemDelegations(contexts, modes, executions) {
            nestedSpent = true;
        } catch {}
    }
}

/// @dev Reads the principal's record from its own hooks, so a test sees what is live inside the redemption.
contract RecordProbe {
    SpendGrantRedemptionEnforcer internal immutable ENFORCER;
    address internal principal;
    bytes32 internal grantHash;
    address internal asset;
    uint256 internal amount;
    address internal recipient;
    address public seenBefore;
    address public seenAfter;

    constructor(SpendGrantRedemptionEnforcer enforcer_) {
        ENFORCER = enforcer_;
    }

    function watch(address principal_, bytes32 grantHash_, address asset_, uint256 amount_, address recipient_)
        external
    {
        (principal, grantHash, asset, amount, recipient) = (principal_, grantHash_, asset_, amount_, recipient_);
    }

    function beforeAllHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address)
        external
    {}

    function beforeHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address) external {
        seenBefore = ENFORCER.recorded(principal, grantHash, asset, amount, recipient);
    }

    function afterHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address) external {
        seenAfter = ENFORCER.recorded(principal, grantHash, asset, amount, recipient);
    }

    function afterAllHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address)
        external
    {}
}

/// @dev Calls a contract recipient back after each transfer, as tokens with transfer hooks do.
contract HookERC20 is MockERC20 {
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        if (to.code.length > 0) MatrixThief(to).onTokenReceived();
        return true;
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
        // The redeemer is the grant's delegate. The caveat sits on the leaf, whose delegator is an
        // intermediary, so the enforcer writes nothing, and the principal's account finds no record.
        address intermediary = vm.addr(0x1111);
        SpendGrant memory m = _grant(address(principalAccount), delegate);
        bytes memory sig = _sign(OWNER_PK, m);
        bytes32 h = _hash(m);
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](2);
        chain[0] = _delegation(delegate, intermediary, true);
        chain[1] = _delegation(intermediary, address(principalAccount), false);

        _redeemExpecting(Reason.UNAUTHORIZED_DELEGATE, delegate, chain, _execution(m, sig, 1e18, recipient));
        _assertNothingSpent(m);
        assertEq(enforcer.recorded(intermediary, h, address(token), 1e18, recipient), address(0));
    }

    function test_redemption_hostileIntermediaryCannotRideTheRedemption() public {
        // Chain: principal -> evil (caveat), evil -> delegate (caveat + evil as its own enforcer). The
        // delegate redeems once. In a hook, evil calls the executor with the same spend. The enforcer wrote
        // no record for evil, and the executor rejects any record-path caller but the principal, so the
        // strike reverts and takes the whole redemption with it.
        for (uint256 variant = 0; variant < 2; variant++) {
            EvilDelegator evil = new EvilDelegator(executor, variant == 0);
            SpendGrant memory m = _grant(address(principalAccount), delegate);
            m.salt = 100 + variant;
            bytes memory sig = _sign(OWNER_PK, m);
            MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](2);
            chain[0] = _delegation(delegate, address(evil), true);
            chain[0].caveats = new MockDelegationManager.Caveat[](2);
            chain[0].caveats[0] = MockDelegationManager.Caveat(address(enforcer), "", "");
            chain[0].caveats[1] = MockDelegationManager.Caveat(address(evil), "", "");
            chain[1] = _delegation(address(evil), address(principalAccount), true);

            _redeemExpecting(Reason.UNAUTHORIZED_DELEGATE, delegate, chain, _execution(m, sig, 1e18, recipient));
            _assertNothingSpent(m);
        }
    }

    function test_redemption_caveatOnOtherHopsIsInertAndLeavesNoRecord() public {
        // Chain: principal -> intermediary (caveat), intermediary -> delegate (caveat). One redemption, one
        // spend. No record exists for the intermediary afterwards, and it cannot spend on its own.
        address intermediary = vm.addr(0x1111);
        SpendGrant memory m = _grant(address(principalAccount), delegate);
        bytes memory sig = _sign(OWNER_PK, m);
        bytes32 h = _hash(m);
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](2);
        chain[0] = _delegation(delegate, intermediary, true);
        chain[1] = _delegation(intermediary, address(principalAccount), true);

        _redeem(delegate, chain, SINGLE_DEFAULT, _execution(m, sig, 1e18, recipient));

        (uint256 spent, uint256 calls) = registry.usage(h, address(token));
        assertEq(spent, 1e18);
        assertEq(calls, 1);
        assertEq(enforcer.recorded(intermediary, h, address(token), 1e18, recipient), address(0));
        assertEq(enforcer.recorded(address(principalAccount), h, address(token), 1e18, recipient), address(0));

        vm.prank(intermediary);
        _expect(Reason.UNAUTHORIZED_DELEGATE);
        executor.spend(m, sig, address(token), 1e18, recipient);
    }

    function test_recordPath_onlyThePrincipalMayUseIt() public {
        // A record written for the principal does not help any other caller, even with the right spend.
        SpendGrant memory m = _grant(address(principalAccount), delegate);
        bytes memory sig = _sign(OWNER_PK, m);
        _writeRecord(m, address(principalAccount), delegate);

        vm.expectCall(address(enforcer), abi.encodeWithSelector(enforcer.take.selector), 0);
        vm.prank(stranger);
        _expect(Reason.UNAUTHORIZED_DELEGATE);
        executor.spend(m, sig, address(token), 1e18, recipient);
    }

    function test_afterHook_clearsWhatWasNotTaken() public {
        SpendGrant memory m = _grant(address(principalAccount), delegate);
        bytes32 h = _hash(m);
        bytes memory execution = _execution(m, _sign(OWNER_PK, m), 1e18, recipient);
        _writeRecord(m, address(principalAccount), delegate);
        assertEq(enforcer.recorded(address(principalAccount), h, address(token), 1e18, recipient), delegate);

        vm.prank(stranger);
        vm.expectRevert(SpendGrantRedemptionEnforcer.NotManager.selector);
        enforcer.afterHook("", "", SINGLE_DEFAULT, execution, bytes32(0), address(principalAccount), delegate);

        vm.prank(address(manager));
        enforcer.afterHook("", "", SINGLE_DEFAULT, execution, bytes32(0), address(principalAccount), delegate);
        assertEq(enforcer.recorded(address(principalAccount), h, address(token), 1e18, recipient), address(0));
    }

    function test_enforcer_rejectsVendorModeBytes() public {
        SpendGrant memory m = _grant(address(principalAccount), delegate);
        bytes memory execution = _execution(m, _sign(OWNER_PK, m), 1e18, recipient);
        // Call type and exec type are zero, but a vendor selector is set.
        bytes32 vendorMode = bytes32(uint256(0xdeadbeef) << 176);

        vm.prank(address(manager));
        vm.expectRevert(SpendGrantRedemptionEnforcer.UnsupportedMode.selector);
        enforcer.beforeHook("", "", vendorMode, execution, bytes32(0), address(principalAccount), delegate);
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

    // ---------------------------------------------------------------- the record is written only at the root

    function test_enforcer_writesOnlyAtTheRootDelegation() public {
        SpendGrant memory m = _grant(address(principalAccount), delegate);
        bytes32 h = _hash(m);
        bytes memory execution = _execution(m, _sign(OWNER_PK, m), 1e18, recipient);
        MockDelegationManager.Delegation memory d = _delegation(delegate, address(principalAccount), true);

        // Not the root: the authority is another delegation's hash. The args check out, and nothing is written.
        d.authority = keccak256("parent");
        bytes32 lowerHash = manager.getDelegationHash(d);
        vm.prank(address(manager));
        enforcer.beforeHook("", abi.encode(d), SINGLE_DEFAULT, execution, lowerHash, d.delegator, delegate);
        assertEq(enforcer.recorded(address(principalAccount), h, address(token), 1e18, recipient), address(0));

        // No args: a delegation of the principal's must show itself, so the call reverts.
        d.authority = manager.ROOT_AUTHORITY();
        bytes32 rootHash = manager.getDelegationHash(d);
        vm.prank(address(manager));
        vm.expectRevert(SpendGrantRedemptionEnforcer.MissingDelegation.selector);
        enforcer.beforeHook("", "", SINGLE_DEFAULT, execution, rootHash, d.delegator, delegate);

        // The root, shown by args whose hash is the one the manager passed: written.
        vm.prank(address(manager));
        enforcer.beforeHook("", abi.encode(d), SINGLE_DEFAULT, execution, rootHash, d.delegator, delegate);
        assertEq(enforcer.recorded(address(principalAccount), h, address(token), 1e18, recipient), delegate);
    }

    function test_enforcer_argsThatAreNotTheHookedDelegationRevert() public {
        SpendGrant memory m = _grant(address(principalAccount), delegate);
        bytes memory execution = _execution(m, _sign(OWNER_PK, m), 1e18, recipient);
        // A root delegation the principal signed elsewhere, offered for a lower delegation's hook.
        (bytes memory otherRoot,) = _rootArgs(address(principalAccount), delegate);
        MockDelegationManager.Delegation memory lower = _delegation(delegate, address(principalAccount), true);
        lower.authority = keccak256("parent");
        bytes32 lowerHash = manager.getDelegationHash(lower);
        vm.prank(address(manager));
        vm.expectRevert(SpendGrantRedemptionEnforcer.DelegationMismatch.selector);
        enforcer.beforeHook("", otherRoot, SINGLE_DEFAULT, execution, lowerHash, lower.delegator, delegate);
    }

    function test_redemption_rootCarryingTheCaveatTwiceReverts() public {
        // A second copy would write the record again after a hook between the copies could have taken it.
        SpendGrant memory m = _grant(address(principalAccount), delegate);
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](1);
        chain[0] = _delegation(delegate, address(principalAccount), true);
        MockDelegationManager.Caveat[] memory twice = new MockDelegationManager.Caveat[](2);
        twice[0] = chain[0].caveats[0];
        twice[1] = MockDelegationManager.Caveat(address(enforcer), "", "");
        chain[0].caveats = twice;
        bytes memory execution = _execution(m, _sign(OWNER_PK, m), 1e18, recipient);
        _link(chain);
        bytes[] memory contexts = new bytes[](1);
        contexts[0] = abi.encode(chain);
        bytes[] memory executions = new bytes[](1);
        executions[0] = execution;
        vm.prank(delegate);
        vm.expectRevert(SpendGrantRedemptionEnforcer.CaveatNotOnce.selector);
        manager.redeemDelegations(contexts, new bytes32[](1), executions);
    }

    function test_redemption_principalBelowTheRootLeavesNoRecord() public {
        // The delegate's own account is the root delegator, so the principal's delegation, carrying the caveat,
        // is a lower one: inert. A probe on the root reads the principal's record in its beforeHook, which runs
        // after the principal's, and in its afterHook, which runs before the principal's clears anything: under
        // the earlier rule both would see the delegate. The execution is the delegate account's direct call.
        MockDeleGator delegateAccount = new MockDeleGator(address(manager), owner);
        RecordProbe probe = new RecordProbe(enforcer);
        SpendGrant memory m = _grant(address(principalAccount), address(delegateAccount));
        probe.watch(address(principalAccount), _hash(m), address(token), 1e18, recipient);
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](2);
        chain[0] = _delegation(address(delegateAccount), address(principalAccount), true);
        chain[1] = _delegation(address(principalAccount), address(delegateAccount), false);
        chain[1].caveats = new MockDelegationManager.Caveat[](1);
        chain[1].caveats[0] = MockDelegationManager.Caveat(address(probe), "", "");
        _redeem(address(delegateAccount), chain, SINGLE_DEFAULT, _execution(m, _sign(OWNER_PK, m), 1e18, recipient));
        assertEq(probe.seenBefore(), address(0), "a record was live before the execution");
        assertEq(probe.seenAfter(), address(0), "a record was live after the execution");
        (uint256 spent, uint256 calls) = registry.usage(_hash(m), address(token));
        assertEq(calls, 1);
        assertEq(spent, 1e18);
    }

    // ---------------------------------------------------------------- the scenario matrix

    struct Matrix {
        MockDeleGator delegateAccount;
        MockDeleGator otherAccount;
        HookERC20 asset;
        MatrixThief thief;
        bytes execution;
        bytes32 grantHash;
        bytes driveP;
        bytes driveD;
        bytes viaCaveat;
        bytes viaCaveatNoArgs;
    }

    /// @notice Every chain shape in `_shape`, with the thief in every caveat slot or none, striking at every
    /// point with either delegation it may hold, alone and paired with every shape in one batch: a call that does
    /// not revert pays each of its entries at most once, plus one for a delegate-account call that the thief's own
    /// delegation drove, which is that account's own authorization. One test per first shape, to stay under the
    /// per-test gas limit.
    function test_matrix_S1_principalRoot() public {
        _matrixFrom(0, 0, 4);
    }

    function test_matrix_S1_principalRoot_pairedWithS6S7() public {
        _matrixFrom(0, 5, 8);
    }

    function test_matrix_S2_delegateRoot() public {
        _matrixFrom(1, 0, 4);
    }

    function test_matrix_S2_delegateRoot_pairedWithS6S7() public {
        _matrixFrom(1, 5, 8);
    }

    function test_matrix_S3_delegateRootWithOtherBetween() public {
        _matrixFrom(2, 0, 4);
    }

    function test_matrix_S3_delegateRootWithOtherBetween_pairedWithS6S7() public {
        _matrixFrom(2, 5, 8);
    }

    function test_matrix_S4_otherRoot() public {
        _matrixFrom(3, 0, 4);
    }

    function test_matrix_S4_otherRoot_pairedWithS6S7() public {
        _matrixFrom(3, 5, 8);
    }

    function test_matrix_S5_subDelegateRedeems() public {
        _matrixFrom(4, 0, 4);
    }

    function test_matrix_S6_principalTwiceCaveatLower() public {
        _matrixFrom(5, 0, 4);
    }

    function test_matrix_S6_principalTwiceCaveatLower_pairedWithS6S7() public {
        _matrixFrom(5, 5, 8);
    }

    function test_matrix_S6_principalTwiceCaveatAtRoot() public {
        _matrixFrom(6, 0, 4);
    }

    function test_matrix_S6_principalTwiceCaveatAtRoot_pairedWithS6S7() public {
        _matrixFrom(6, 5, 8);
    }

    function test_matrix_S6_principalTwiceCaveatAtBoth() public {
        _matrixFrom(7, 0, 4);
    }

    function test_matrix_S6_principalTwiceCaveatAtBoth_pairedWithS6S7() public {
        _matrixFrom(7, 5, 8);
    }

    function test_matrix_S7_rootCarriesTheCaveatTwice() public {
        _matrixFrom(8, 0, 4);
    }

    function test_matrix_S7_rootCarriesTheCaveatTwice_pairedWithS6S7() public {
        _matrixFrom(8, 5, 8);
    }

    /// @dev Shape `a` alone (when `bFrom` is 0) and paired with shapes `bFrom` to `bTo` in one batch; split so
    /// each test stays under the per-test gas and memory limits.
    function _matrixFrom(uint256 a, uint256 bFrom, uint256 bTo) internal {
        Matrix memory x = _matrix();
        uint256 cases;
        uint256 struck;
        if (bFrom == 0) (cases, struck) = _runShapes(x, a, type(uint256).max);
        for (uint256 b = bFrom; b <= bTo; b++) {
            (uint256 c, uint256 s) = _runShapes(x, a, b);
            cases += c;
            struck += s;
        }
        emit log_named_uint("cases", cases);
        emit log_named_uint("cases where the thief struck and the call still succeeded", struck);
        assertGt(cases, 0, "this matrix test ran no cases");
        // Not vacuous: wherever the shape can succeed, the thief must have run inside successful calls.
        if (a != 3 && a != 4 && a != 5 && a != 8) assertGt(struck, 0, "the thief never struck in a successful call");
    }

    function test_matrix_legitimateShapesPayOnceAndTheRestRevert() public {
        Matrix memory x = _matrix();
        // S1, S2, S3, S6 with the caveat at the root: one payment. S4 (another account at the root), S5 (a
        // sub-delegate redeems), S6 with the caveat only lower down, S7 (the caveat twice on the root): revert.
        bool[9] memory pays = [true, true, true, false, false, false, true, true, false];
        for (uint256 a = 0; a < 9; a++) {
            (MockDelegationManager.Delegation[] memory chain, address redeemer) = _shape(x, a);
            _link(chain);
            x.thief.arm(0, "", "");
            uint256 snap = vm.snapshotState();
            (bool ok, uint256 calls) = _attempt(x, redeemer, _one(chain), 1);
            assertEq(ok, pays[a], "legitimate shape outcome");
            if (ok) assertEq(calls, 1, "legitimate shape pays once");
            vm.revertToState(snap);
        }
    }

    function _runShapes(Matrix memory x, uint256 a, uint256 b) internal returns (uint256 cases, uint256 struck) {
        (MockDelegationManager.Delegation[] memory ca, address ra) = _shape(x, a);
        MockDelegationManager.Delegation[] memory cb;
        uint256 entries = 1;
        if (b != type(uint256).max) {
            address rb;
            (cb, rb) = _shape(x, b);
            if (rb != ra) return (0, 0);
            entries = 2;
        }
        uint256 slotsA = _slots(ca);
        uint256 slotsB = entries == 2 ? _slots(cb) : 0;
        // slot 0: no thief caveat; 1..slotsA: in chain a; slotsA+1..slotsA+slotsB: in chain b
        for (uint256 slot = 0; slot <= slotsA + slotsB; slot++) {
            for (uint8 pt = 0; pt <= 5; pt++) {
                if (slot == 0 && pt != 0 && pt != 5) continue;
                if (slot != 0 && (pt == 0 || pt == 5)) continue;
                for (uint256 act = 0; act < (pt == 0 ? 1 : 4); act++) {
                    MockDelegationManager.Delegation[] memory ia =
                        slot >= 1 && slot <= slotsA ? _withThief(ca, slot - 1, address(x.thief)) : _copy(ca);
                    MockDelegationManager.Delegation[][] memory chains;
                    if (entries == 1) {
                        chains = _one(ia);
                    } else {
                        MockDelegationManager.Delegation[] memory ib =
                            slot > slotsA ? _withThief(cb, slot - slotsA - 1, address(x.thief)) : _copy(cb);
                        chains = new MockDelegationManager.Delegation[][](2);
                        chains[0] = ia;
                        chains[1] = ib;
                    }
                    for (uint256 i = 0; i < chains.length; i++) {
                        _link(chains[i]);
                    }
                    bytes memory nested =
                        act == 0 ? x.driveP : act == 1 ? x.driveD : act == 2 ? x.viaCaveat : x.viaCaveatNoArgs;
                    x.thief.arm(pt, nested, x.execution);
                    uint256 snap = vm.snapshotState();
                    (bool ok, uint256 calls) = _attempt(x, ra, chains, entries);
                    if (ok) {
                        uint256 allowed = entries + (act == 1 && x.thief.nestedSpent() ? 1 : 0);
                        assertLe(calls, allowed, "a redemption paid more than once");
                        if (x.thief.struck()) {
                            struck++;
                            // The thief's own moves behave as they should, so a broken nested path cannot pass
                            // for a safe one: the delegate account's call through the thief's own delegation is
                            // that account's authorization and goes through; everything else fails.
                            if (act == 1) assertTrue(x.thief.nestedSpent(), "the delegate-account call failed");
                            else assertFalse(x.thief.nestedSpent(), "a thief move without authority paid");
                        }
                    }
                    vm.revertToState(snap);
                    cases++;
                }
            }
        }
    }

    function _attempt(
        Matrix memory x,
        address redeemer,
        MockDelegationManager.Delegation[][] memory chains,
        uint256 entries
    ) internal returns (bool ok, uint256 calls) {
        bytes[] memory contexts = new bytes[](entries);
        bytes32[] memory modes = new bytes32[](entries);
        bytes[] memory executions = new bytes[](entries);
        for (uint256 i = 0; i < entries; i++) {
            contexts[i] = abi.encode(chains[i]);
            executions[i] = x.execution;
        }
        vm.prank(redeemer);
        (ok,) = address(manager).call(abi.encodeCall(manager.redeemDelegations, (contexts, modes, executions)));
        (, calls) = registry.usage(x.grantHash, address(x.asset));
    }

    function _matrix() internal returns (Matrix memory x) {
        x.delegateAccount = new MockDeleGator(address(manager), owner);
        x.otherAccount = new MockDeleGator(address(manager), owner);
        x.asset = new HookERC20();
        x.thief = new MatrixThief(manager);
        x.asset.mint(address(principalAccount), 1e24);
        vm.prank(address(principalAccount));
        x.asset.approve(address(executor), type(uint256).max);
        SpendGrant memory m = _grant(address(principalAccount), address(x.delegateAccount));
        m.recipient = address(x.thief);
        m.assets[0].asset = address(x.asset);
        x.grantHash = _hash(m);
        x.execution = abi.encodePacked(
            address(executor),
            uint256(0),
            abi.encodeCall(SpendGrantExecutor.spend, (m, _sign(OWNER_PK, m), address(x.asset), 1e18, address(x.thief)))
        );
        MockDelegationManager.Delegation[] memory p = new MockDelegationManager.Delegation[](1);
        p[0] = _delegation(address(x.thief), address(principalAccount), false);
        _link(p);
        x.driveP = abi.encode(p);
        MockDelegationManager.Delegation[] memory d = new MockDelegationManager.Delegation[](1);
        d[0] = _delegation(address(x.thief), address(x.delegateAccount), false);
        _link(d);
        x.driveD = abi.encode(d);
        // A delegation from the principal to the thief that carries the SpendGrant caveat: with its args, it
        // records the thief, whom consume rejects; without them, it reverts.
        MockDelegationManager.Delegation[] memory v = new MockDelegationManager.Delegation[](1);
        v[0] = _delegation(address(x.thief), address(principalAccount), true);
        _link(v);
        x.viaCaveat = abi.encode(v);
        v[0].caveats[0].args = "";
        x.viaCaveatNoArgs = abi.encode(v);
    }

    /// @dev Chains leaf to root, and who redeems each. P principal account, D delegate account, X another account.
    function _shape(Matrix memory x, uint256 id)
        internal
        view
        returns (MockDelegationManager.Delegation[] memory c, address redeemer)
    {
        address pa = address(principalAccount);
        address da = address(x.delegateAccount);
        address xa = address(x.otherAccount);
        redeemer = da;
        if (id == 0) {
            // S1: P is the root.
            c = new MockDelegationManager.Delegation[](1);
            c[0] = _delegation(da, pa, true);
        } else if (id == 1) {
            // S2: D is the root, P's delegation below it.
            c = new MockDelegationManager.Delegation[](2);
            c[0] = _delegation(da, pa, true);
            c[1] = _delegation(pa, da, false);
        } else if (id == 2) {
            // S3: D is the root, X between.
            c = new MockDelegationManager.Delegation[](3);
            c[0] = _delegation(da, pa, true);
            c[1] = _delegation(pa, xa, false);
            c[2] = _delegation(xa, da, false);
        } else if (id == 3) {
            // S4: X is the root.
            c = new MockDelegationManager.Delegation[](2);
            c[0] = _delegation(da, pa, true);
            c[1] = _delegation(pa, xa, false);
        } else if (id == 4) {
            // S5: P is the root, a sub-delegate of D redeems.
            c = new MockDelegationManager.Delegation[](2);
            c[0] = _delegation(subDelegate, da, false);
            c[1] = _delegation(da, pa, true);
            redeemer = subDelegate;
        } else if (id == 8) {
            // S7: P is the root and its delegation carries the caveat twice.
            c = new MockDelegationManager.Delegation[](1);
            c[0] = _delegation(da, pa, true);
            MockDelegationManager.Caveat[] memory twice = new MockDelegationManager.Caveat[](2);
            twice[0] = c[0].caveats[0];
            twice[1] = MockDelegationManager.Caveat(address(enforcer), "", "");
            c[0].caveats = twice;
        } else {
            // S6: P twice, P is the root; the caveat lower only (5), at the root only (6), or both (7).
            c = new MockDelegationManager.Delegation[](3);
            c[0] = _delegation(da, pa, id != 6);
            c[1] = _delegation(pa, da, false);
            c[2] = _delegation(da, pa, id != 5);
        }
    }

    function _slots(MockDelegationManager.Delegation[] memory c) internal pure returns (uint256 n) {
        for (uint256 i = 0; i < c.length; i++) {
            n += c[i].caveats.length + 1;
        }
    }

    function _withThief(MockDelegationManager.Delegation[] memory c, uint256 slot, address thief)
        internal
        pure
        returns (MockDelegationManager.Delegation[] memory out)
    {
        out = _copy(c);
        for (uint256 i = 0; i < out.length; i++) {
            uint256 positions = out[i].caveats.length + 1;
            if (slot >= positions) {
                slot -= positions;
                continue;
            }
            MockDelegationManager.Caveat[] memory cv = new MockDelegationManager.Caveat[](out[i].caveats.length + 1);
            uint256 k;
            for (uint256 j = 0; j < cv.length; j++) {
                cv[j] = j == slot ? MockDelegationManager.Caveat(thief, "", "") : out[i].caveats[k++];
            }
            out[i].caveats = cv;
            return out;
        }
    }

    function _copy(MockDelegationManager.Delegation[] memory c)
        internal
        pure
        returns (MockDelegationManager.Delegation[] memory out)
    {
        // Field by field: assigning a memory struct copies a reference, and the copy must not alias the shape.
        out = new MockDelegationManager.Delegation[](c.length);
        for (uint256 i = 0; i < c.length; i++) {
            MockDelegationManager.Delegation memory d;
            d.delegate = c[i].delegate;
            d.delegator = c[i].delegator;
            d.authority = c[i].authority;
            d.salt = c[i].salt;
            d.signature = c[i].signature;
            d.caveats = new MockDelegationManager.Caveat[](c[i].caveats.length);
            for (uint256 j = 0; j < c[i].caveats.length; j++) {
                d.caveats[j] =
                    MockDelegationManager.Caveat(c[i].caveats[j].enforcer, c[i].caveats[j].terms, c[i].caveats[j].args);
            }
            out[i] = d;
        }
    }

    function _one(MockDelegationManager.Delegation[] memory c)
        internal
        pure
        returns (MockDelegationManager.Delegation[][] memory chains)
    {
        chains = new MockDelegationManager.Delegation[][](1);
        chains[0] = c;
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

    /// @dev Sets each delegation's authority to the next one's hash and the root's to ROOT_AUTHORITY, then
    /// puts each delegation into the args of its SpendGrant caveats: the enforcer writes a record only for
    /// a delegation it can show is the root, and args are not part of the delegation hash.
    function _link(MockDelegationManager.Delegation[] memory chain) internal view {
        chain[chain.length - 1].authority = manager.ROOT_AUTHORITY();
        for (uint256 i = chain.length - 1; i > 0; i--) {
            chain[i - 1].authority = manager.getDelegationHash(chain[i]);
        }
        for (uint256 i = 0; i < chain.length; i++) {
            for (uint256 c = 0; c < chain[i].caveats.length; c++) {
                if (chain[i].caveats[c].enforcer == address(enforcer)) chain[i].caveats[c].args = "";
            }
            bytes memory self = abi.encode(chain[i]);
            for (uint256 c = 0; c < chain[i].caveats.length; c++) {
                if (chain[i].caveats[c].enforcer == address(enforcer)) chain[i].caveats[c].args = self;
            }
        }
    }

    function _redeem(
        address caller,
        MockDelegationManager.Delegation[] memory chain,
        bytes32 mode,
        bytes memory execution
    ) internal {
        _link(chain);
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
        _link(chain);
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

    /// @dev Writes a record the way the manager would at a root delegation from `executingAccount`, for tests
    /// of the record alone.
    function _writeRecord(SpendGrant memory m, address executingAccount, address redeemer) internal {
        bytes memory execution = _execution(m, _sign(OWNER_PK, m), 1e18, recipient);
        (bytes memory args, bytes32 delegationHash) = _rootArgs(executingAccount, redeemer);
        vm.prank(address(manager));
        enforcer.beforeHook("", args, SINGLE_DEFAULT, execution, delegationHash, executingAccount, redeemer);
    }

    /// @dev A root delegation from `delegator` to `delegate_` carrying the SpendGrant caveat: as the
    /// enforcer's args, and the manager's hash of it.
    function _rootArgs(address delegator, address delegate_)
        internal
        view
        returns (bytes memory args, bytes32 delegationHash)
    {
        MockDelegationManager.Delegation memory d = _delegation(delegate_, delegator, true);
        d.authority = manager.ROOT_AUTHORITY();
        delegationHash = manager.getDelegationHash(d);
        args = abi.encode(d);
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
