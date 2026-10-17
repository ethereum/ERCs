// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AssetLimit, IERC1271, SpendGrant, SpendGrantError, Reason} from "../src/SpendGrantTypes.sol";
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
/// A refused call reverts with `StrikeRefused` carrying the executor's revert data, so a test can tell the
/// executor's refusal of evil's own call from any other revert in the redemption.
contract EvilDelegator {
    error StrikeRefused(bytes reason);

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
        if (!ok) revert StrikeRefused(ret);
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
/// whose execution is the same spend, and catches whatever that does, keeping the revert data.
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
    bytes public nestedError;
    bytes internal nestedContext;
    bytes internal nestedExecution;

    constructor(MockDelegationManager manager_) {
        MANAGER = manager_;
    }

    function arm(uint8 point_, bytes memory context, bytes memory execution) external {
        (point, struck, nestedSpent, nestedContext, nestedExecution) = (point_, false, false, context, execution);
        nestedError = "";
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
        } catch (bytes memory err) {
            nestedError = err;
        }
    }
}

/// @dev Reads the principal's record from its own hooks, so a test sees what is live inside the redemption.
contract RecordProbe {
    SpendGrantRedemptionEnforcer internal immutable ENFORCER;
    address internal principal;
    bytes32 internal grantId;
    address internal asset;
    uint256 internal amount;
    address internal recipient;
    address public seenBefore;
    address public seenAfter;

    constructor(SpendGrantRedemptionEnforcer enforcer_) {
        ENFORCER = enforcer_;
    }

    function watch(address principal_, bytes32 grantId_, address asset_, uint256 amount_, address recipient_)
        external
    {
        (principal, grantId, asset, amount, recipient) = (principal_, grantId_, asset_, amount_, recipient_);
    }

    function beforeAllHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address)
        external
    {}

    function beforeHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address) external {
        seenBefore = ENFORCER.recorded(principal, grantId, asset, amount, recipient);
    }

    function afterHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address) external {
        seenAfter = ENFORCER.recorded(principal, grantId, asset, amount, recipient);
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
    bytes4 internal constant SPEND_GRANT_ERROR = bytes4(keccak256("SpendGrantError(uint8)"));
    bytes4 internal constant WRONG_DELEGATOR = bytes4(keccak256("WrongDelegator()"));
    bytes4 internal constant NOT_ROOT = bytes4(keccak256("NotRoot()"));
    bytes4 internal constant WRONG_DELEGATE = bytes4(keccak256("WrongDelegate()"));
    bytes4 internal constant WRONG_REDEEMER = bytes4(keccak256("WrongRedeemer()"));

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
        bytes32 id = _register(_grant(address(principalAccount), delegate));
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](1);
        chain[0] = _delegation(delegate, address(principalAccount), true);

        uint256 principalBefore = token.balanceOf(address(principalAccount));

        _redeem(delegate, chain, SINGLE_DEFAULT, _execution(id, 1e18, recipient));

        assertEq(principalBefore - token.balanceOf(address(principalAccount)), 1e18);
        assertEq(token.balanceOf(recipient), 1e18);
        (uint256 spent, uint256 calls) = registry.usage(id, address(token));
        assertEq(spent, 1e18);
        assertEq(calls, 1);
        // Cleared when taken, so nothing in this transaction can use it again.
        assertEq(enforcer.recorded(address(principalAccount), id, address(token), 1e18, recipient), address(0));
    }

    function test_redemption_bySubDelegate_isRejected() public {
        bytes32 id = _register(_grant(address(principalAccount), delegate));
        // Leaf: delegate -> subDelegate. Root: principal -> delegate, carrying the caveat. The root's hook sees the
        // sub-delegate as the redeemer, not the grant's delegate, and reverts before anything is recorded.
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](2);
        chain[0] = _delegation(subDelegate, delegate, false);
        chain[1] = _delegation(delegate, address(principalAccount), true);

        _redeemReverting(abi.encodeWithSelector(WRONG_REDEEMER), subDelegate, chain, _execution(id, 1e18, recipient));
        _assertNothingSpent(id);
    }

    function test_redemption_openDelegation_revertsEvenForTheDelegate() public {
        // The principal's root delegation open to any delegate, carrying the caveat: it does not name the grant's
        // delegate, so its hook reverts for whoever redeems it, the grant's delegate included.
        bytes32 id = _register(_grant(address(principalAccount), delegate));
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](1);
        chain[0] = _delegation(manager.ANY_DELEGATE(), address(principalAccount), true);
        bytes memory execution = _execution(id, 1e18, recipient);

        _redeemReverting(abi.encodeWithSelector(WRONG_DELEGATE), delegate, chain, execution);
        _redeemReverting(abi.encodeWithSelector(WRONG_DELEGATE), stranger, chain, execution);
        _assertNothingSpent(id);
    }

    function test_redemption_recordAuthorizesOneConsume() public {
        DoubleExecDeleGator twice = new DoubleExecDeleGator(address(manager), owner);
        _fund(address(twice));
        bytes32 id = _register(_grant(address(twice), delegate));
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](1);
        chain[0] = _delegation(delegate, address(twice), true);

        // The first spend takes the record; the second finds none and the whole redemption reverts.
        _redeemExpecting(Reason.UNAUTHORIZED_DELEGATE, delegate, chain, _execution(id, 1e18, recipient));
        _assertNothingSpent(id);
        assertEq(token.balanceOf(address(twice)), 1e24);
    }

    function test_redemption_chainThroughAnotherAccount_reverts() public {
        // principal -> intermediary, the root, carrying the caveat; intermediary -> delegate; the delegate redeems.
        // The root names the intermediary, not the grant's delegate, so its hook reverts.
        address intermediary = vm.addr(0x1111);
        bytes32 id = _register(_grant(address(principalAccount), delegate));
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](2);
        chain[0] = _delegation(delegate, intermediary, false);
        chain[1] = _delegation(intermediary, address(principalAccount), true);

        _redeemReverting(abi.encodeWithSelector(WRONG_DELEGATE), delegate, chain, _execution(id, 1e18, recipient));
        _assertNothingSpent(id);
    }

    function test_redemption_loopThroughAnotherAccountPays() public {
        // principal -> delegate, the root, carrying the caveat; delegate -> another account; that account -> delegate;
        // the delegate redeems. The enforcer checks the root delegation and the redeemer, not the hops between: the
        // root names the delegate and the delegate redeems, so this pays once, and no record is left.
        address other = vm.addr(0x7777);
        bytes32 id = _register(_grant(address(principalAccount), delegate));
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](3);
        chain[0] = _delegation(delegate, other, false);
        chain[1] = _delegation(other, delegate, false);
        chain[2] = _delegation(delegate, address(principalAccount), true);
        uint256 principalBefore = token.balanceOf(address(principalAccount));

        _redeem(delegate, chain, SINGLE_DEFAULT, _execution(id, 1e18, recipient));

        assertEq(principalBefore - token.balanceOf(address(principalAccount)), 1e18);
        assertEq(token.balanceOf(recipient), 1e18);
        (uint256 spent, uint256 calls) = registry.usage(id, address(token));
        assertEq(spent, 1e18);
        assertEq(calls, 1);
        assertEq(enforcer.recorded(address(principalAccount), id, address(token), 1e18, recipient), address(0));
    }

    function test_redemption_caveatOnAnIntermediarysDelegationReverts() public {
        // The redeemer is the grant's delegate. The caveat sits on the leaf, whose delegator is an intermediary, not
        // the grant's principal, so its hook reverts and nothing is recorded for anyone.
        address intermediary = vm.addr(0x1111);
        bytes32 id = _register(_grant(address(principalAccount), delegate));
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](2);
        chain[0] = _delegation(delegate, intermediary, true);
        chain[1] = _delegation(intermediary, address(principalAccount), false);

        _redeemReverting(abi.encodeWithSelector(WRONG_DELEGATOR), delegate, chain, _execution(id, 1e18, recipient));
        _assertNothingSpent(id);
        assertEq(enforcer.recorded(intermediary, id, address(token), 1e18, recipient), address(0));
    }

    function test_redemption_hostileIntermediaryCannotRideTheRedemption() public {
        // Chain: principal -> delegate, the root, carrying the caveat; delegate -> evil; evil -> delegate, carrying evil
        // as its own enforcer. The root names the delegate and the delegate redeems, so the rule accepts the chain and
        // evil's hook runs: its beforeHook before the root's hook writes the record, its afterHook after the execution
        // took it. From either, evil calls the executor with the same spend, as neither the grant's principal nor its
        // delegate, so the executor refuses that call itself (13), before it asks the enforcer for any record, and the
        // whole redemption reverts with evil's StrikeRefused carrying that refusal.
        for (uint256 variant = 0; variant < 2; variant++) {
            EvilDelegator evil = new EvilDelegator(executor, variant == 0);
            SpendGrant memory m = _grant(address(principalAccount), delegate);
            m.salt = 100 + variant;
            bytes32 id = _register(m);
            MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](3);
            chain[0] = _delegation(delegate, address(evil), false);
            chain[0].caveats = new MockDelegationManager.Caveat[](1);
            chain[0].caveats[0] = MockDelegationManager.Caveat(address(evil), "", "");
            chain[1] = _delegation(address(evil), delegate, false);
            chain[2] = _delegation(delegate, address(principalAccount), true);

            vm.expectCall(address(enforcer), abi.encodeWithSelector(enforcer.take.selector, address(evil)), 0);
            // In the afterHook variant the principal's execution took the record once before evil struck, so the same
            // prefix with the principal's account matches a real call.
            if (variant == 1) {
                vm.expectCall(
                    address(enforcer), abi.encodeWithSelector(enforcer.take.selector, address(principalAccount)), 1
                );
            }
            _redeemReverting(
                abi.encodeWithSelector(EvilDelegator.StrikeRefused.selector, _err(13)),
                delegate,
                chain,
                _execution(id, 1e18, recipient)
            );
            _assertNothingSpent(id);
            assertEq(enforcer.recorded(address(principalAccount), id, address(token), 1e18, recipient), address(0));
        }
    }

    function test_redemption_caveatOnOtherHopsReverts() public {
        // Chain: principal -> intermediary (caveat), intermediary -> delegate (caveat). The leaf's hook runs first,
        // and its delegator is the intermediary, not the grant's principal, so the redemption reverts. No record
        // exists for either account afterwards, and the intermediary cannot spend on its own.
        address intermediary = vm.addr(0x1111);
        bytes32 id = _register(_grant(address(principalAccount), delegate));
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](2);
        chain[0] = _delegation(delegate, intermediary, true);
        chain[1] = _delegation(intermediary, address(principalAccount), true);

        _redeemReverting(abi.encodeWithSelector(WRONG_DELEGATOR), delegate, chain, _execution(id, 1e18, recipient));
        _assertNothingSpent(id);
        assertEq(enforcer.recorded(intermediary, id, address(token), 1e18, recipient), address(0));
        assertEq(enforcer.recorded(address(principalAccount), id, address(token), 1e18, recipient), address(0));

        vm.prank(intermediary);
        _expect(Reason.UNAUTHORIZED_DELEGATE);
        executor.spend(id, address(token), 1e18, recipient);
    }

    function test_recordPath_onlyThePrincipalMayUseIt() public {
        // A record written for the principal does not help any other caller, even with the right spend.
        bytes32 id = _register(_grant(address(principalAccount), delegate));
        _writeRecord(id, address(principalAccount), delegate);

        vm.expectCall(address(enforcer), abi.encodeWithSelector(enforcer.take.selector), 0);
        vm.prank(stranger);
        _expect(Reason.UNAUTHORIZED_DELEGATE);
        executor.spend(id, address(token), 1e18, recipient);
    }

    function test_afterHook_clearsWhatWasNotTaken() public {
        bytes32 id = _register(_grant(address(principalAccount), delegate));
        bytes memory execution = _execution(id, 1e18, recipient);
        _writeRecord(id, address(principalAccount), delegate);
        assertEq(enforcer.recorded(address(principalAccount), id, address(token), 1e18, recipient), delegate);

        vm.prank(stranger);
        vm.expectRevert(SpendGrantRedemptionEnforcer.NotManager.selector);
        enforcer.afterHook("", "", SINGLE_DEFAULT, execution, bytes32(0), address(principalAccount), delegate);

        vm.prank(address(manager));
        enforcer.afterHook("", "", SINGLE_DEFAULT, execution, bytes32(0), address(principalAccount), delegate);
        assertEq(enforcer.recorded(address(principalAccount), id, address(token), 1e18, recipient), address(0));
    }

    function test_enforcer_rejectsVendorModeBytes() public {
        bytes32 id = _register(_grant(address(principalAccount), delegate));
        bytes memory execution = _execution(id, 1e18, recipient);
        // Call type and exec type are zero, but a vendor selector is set.
        bytes32 vendorMode = bytes32(uint256(0xdeadbeef) << 176);

        vm.prank(address(manager));
        vm.expectRevert(SpendGrantRedemptionEnforcer.UnsupportedMode.selector);
        enforcer.beforeHook("", "", vendorMode, execution, bytes32(0), address(principalAccount), delegate);
    }

    // ---------------------------------------------------------------- shape one: the delegate's account calls

    function test_directCall_byDelegateAccount_acceptsItsSubDelegate() public {
        // Principal is an EOA; the delegate is a smart account that re-delegated to subDelegate, with no
        // SpendGrant caveat on that sub-delegation.
        MockDeleGator delegateAccount = new MockDeleGator(address(manager), owner);
        address eoaPrincipal = vm.addr(EOA_PRINCIPAL_PK);
        _fund(eoaPrincipal);
        bytes32 id = _register(_grant(eoaPrincipal, address(delegateAccount)));
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](1);
        chain[0] = _delegation(subDelegate, address(delegateAccount), false);

        // The executor is called by the grant's delegate itself, so this is a direct call and no record is
        // consulted; the delegate account's own delegation policy is what let subDelegate drive it.
        _redeem(subDelegate, chain, SINGLE_DEFAULT, _execution(id, 1e18, recipient));

        assertEq(token.balanceOf(recipient), 1e18);
        assertEq(token.balanceOf(eoaPrincipal), 1e24 - 1e18);
        (uint256 spent,) = registry.usage(id, address(token));
        assertEq(spent, 1e18);
    }

    function test_directCall_byDelegateAccount_subDelegationCarryingTheCaveatReverts() public {
        // The same sub-delegation carrying the SpendGrant caveat. The caveat's delegator is the delegate account, not
        // the grant's principal, so its hook reverts: the caveat cannot restrict a delegate account's sub-delegation.
        MockDeleGator delegateAccount = new MockDeleGator(address(manager), owner);
        address eoaPrincipal = vm.addr(EOA_PRINCIPAL_PK);
        _fund(eoaPrincipal);
        bytes32 id = _register(_grant(eoaPrincipal, address(delegateAccount)));
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](1);
        chain[0] = _delegation(subDelegate, address(delegateAccount), true);

        _redeemReverting(abi.encodeWithSelector(WRONG_DELEGATOR), subDelegate, chain, _execution(id, 1e18, recipient));
        _assertNothingSpent(id);
        assertEq(token.balanceOf(eoaPrincipal), 1e24);
    }

    function test_directCall_byDelegate_needsNoRecord() public {
        bytes32 id = _register(_grant(address(principalAccount), delegate));

        vm.prank(delegate);
        executor.spend(id, address(token), 1e18, recipient);

        assertEq(token.balanceOf(recipient), 1e18);
    }

    function test_directCall_byStranger_isRejectedWithoutRecord() public {
        bytes32 id = _register(_grant(address(principalAccount), delegate));

        // The executor rejects before the registry is reached: no record is no authorization, and it
        // never passes a placeholder authorizer.
        vm.expectCall(address(registry), abi.encodeWithSelector(registry.consume.selector), 0);
        vm.prank(stranger);
        _expect(Reason.UNAUTHORIZED_DELEGATE);
        executor.spend(id, address(token), 1e18, recipient);
        _assertNothingSpent(id);
    }

    // ---------------------------------------------------------------- the record itself

    function test_take_clearsAndIsExecutorOnly() public {
        bytes32 id = _register(_grant(address(principalAccount), delegate));
        _writeRecord(id, address(principalAccount), delegate);
        assertEq(enforcer.recorded(address(principalAccount), id, address(token), 1e18, recipient), delegate);

        vm.prank(stranger);
        vm.expectRevert(SpendGrantRedemptionEnforcer.NotExecutor.selector);
        enforcer.take(address(principalAccount), id, address(token), 1e18, recipient);

        vm.prank(address(executor));
        assertEq(enforcer.take(address(principalAccount), id, address(token), 1e18, recipient), delegate);
        vm.prank(address(executor));
        assertEq(enforcer.take(address(principalAccount), id, address(token), 1e18, recipient), address(0));
        assertEq(enforcer.recorded(address(principalAccount), id, address(token), 1e18, recipient), address(0));
    }

    function test_record_isScopedToSpendAndExecutingAccount() public {
        SpendGrant memory m = _grant(address(principalAccount), delegate);
        bytes32 id = _register(m);
        _writeRecord(id, address(principalAccount), delegate);

        // Another registered grant of the same principal: a different id, so none of this one's records.
        m.salt = 2;
        bytes32 otherId = _register(m);

        vm.startPrank(address(executor));
        assertEq(enforcer.take(address(principalAccount), id, address(token), 2e18, recipient), address(0));
        assertEq(enforcer.take(address(principalAccount), id, address(token), 1e18, stranger), address(0));
        assertEq(enforcer.take(address(principalAccount), id, address(0xA55E7), 1e18, recipient), address(0));
        assertEq(enforcer.take(address(principalAccount), otherId, address(token), 1e18, recipient), address(0));
        assertEq(enforcer.take(stranger, id, address(token), 1e18, recipient), address(0));
        // Misses do not disturb the record; the exact spend still finds it.
        assertEq(enforcer.recorded(address(principalAccount), id, address(token), 1e18, recipient), delegate);
        assertEq(enforcer.take(address(principalAccount), id, address(token), 1e18, recipient), delegate);
        vm.stopPrank();
    }

    function test_enforcer_onlyManagerWrites() public {
        bytes32 id = _register(_grant(address(principalAccount), delegate));
        bytes memory execution = _execution(id, 1e18, recipient);
        // The principal's own root, shown by its args: what the manager would pass. A stranger still cannot write.
        (bytes memory args, bytes32 delegationHash) = _rootArgs(address(principalAccount), delegate);

        vm.prank(stranger);
        vm.expectRevert(SpendGrantRedemptionEnforcer.NotManager.selector);
        enforcer.beforeHook("", args, SINGLE_DEFAULT, execution, delegationHash, address(principalAccount), delegate);
        assertEq(enforcer.recorded(address(principalAccount), id, address(token), 1e18, recipient), address(0));
    }

    function test_enforcer_failsClosed() public {
        bytes32 id = _register(_grant(address(principalAccount), delegate));
        bytes memory execution = _execution(id, 1e18, recipient);
        bytes memory spendCall = abi.encodeCall(SpendGrantExecutor.spend, (id, address(token), 1e18, recipient));

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

        // Another call on the executor. Bare, it is shorter than a spend's call data: malformed.
        bytes memory otherCall = abi.encodeCall(SpendGrantExecutor.registry, ());
        vm.expectRevert(SpendGrantRedemptionEnforcer.MalformedExecution.selector);
        enforcer.beforeHook(
            "",
            "",
            SINGLE_DEFAULT,
            abi.encodePacked(address(executor), uint256(0), otherCall),
            bytes32(0),
            address(principalAccount),
            delegate
        );

        // Padded with a spend's four argument words, it is the wrong call.
        vm.expectRevert(SpendGrantRedemptionEnforcer.WrongCall.selector);
        enforcer.beforeHook(
            "",
            "",
            SINGLE_DEFAULT,
            abi.encodePacked(address(executor), uint256(0), otherCall, abi.encode(id, address(token), 1e18, recipient)),
            bytes32(0),
            address(principalAccount),
            delegate
        );

        vm.stopPrank();
        assertEq(enforcer.recorded(address(principalAccount), id, address(token), 1e18, recipient), address(0));
    }

    function test_enforcer_valueWithOnlyItsTopByteSetReverts() public {
        // The execution's value is the whole 32-byte word after the target, and a spend carries none: a value with
        // only its top byte set (2**248) is nonzero.
        bytes32 id = _register(_grant(address(principalAccount), delegate));
        bytes memory spendCall = abi.encodeCall(SpendGrantExecutor.spend, (id, address(token), 1e18, recipient));
        bytes memory execution = abi.encodePacked(address(executor), uint256(1) << 248, spendCall);
        vm.prank(address(manager));
        vm.expectRevert(SpendGrantRedemptionEnforcer.NonzeroValue.selector);
        enforcer.beforeHook("", "", SINGLE_DEFAULT, execution, bytes32(0), address(principalAccount), delegate);
    }

    function test_constructor_rejectsEnforcerForAnotherExecutor() public {
        uint64 nonce = vm.getNonce(address(this));
        address predicted = vm.computeCreateAddress(address(this), nonce + 1);
        SpendGrantRegistry other = new SpendGrantRegistry(predicted);
        vm.expectRevert(SpendGrantRedemptionExecutor.EnforcerMismatch.selector);
        new SpendGrantRedemptionExecutor(other, enforcer);
    }

    function test_constructor_rejectsEnforcerForAnotherRegistry() public {
        // The enforcer takes each grant's principal from its own registry; an executor on another registry would
        // take records written against principals that registry never named.
        uint64 nonce = vm.getNonce(address(this));
        address predicted = vm.computeCreateAddress(address(this), nonce + 2);
        SpendGrantRegistry other = new SpendGrantRegistry(predicted);
        SpendGrantRedemptionEnforcer elsewhere =
            new SpendGrantRedemptionEnforcer(address(manager), predicted, address(registry));
        vm.expectRevert(SpendGrantRedemptionExecutor.EnforcerMismatch.selector);
        new SpendGrantRedemptionExecutor(other, elsewhere);
    }

    function test_constructor_rejectsEnforcerForAnotherExecutorOnTheSameRegistry() public {
        // The enforcer reads this executor's own registry, so only its executor() differs: its records are for another
        // executor to take, and its hooks accept only executions that target that one.
        uint64 nonce = vm.getNonce(address(this));
        address predicted = vm.computeCreateAddress(address(this), nonce + 2);
        SpendGrantRegistry same = new SpendGrantRegistry(predicted);
        SpendGrantRedemptionEnforcer forAnother =
            new SpendGrantRedemptionEnforcer(address(manager), stranger, address(same));
        vm.expectRevert(SpendGrantRedemptionExecutor.EnforcerMismatch.selector);
        new SpendGrantRedemptionExecutor(same, forAnother);
    }

    // ---------------------------------------------------------------- the record is written only at the root

    function test_enforcer_writesOnlyAtTheRootDelegation() public {
        bytes32 id = _register(_grant(address(principalAccount), delegate));
        bytes memory execution = _execution(id, 1e18, recipient);
        MockDelegationManager.Delegation memory d = _delegation(delegate, address(principalAccount), true);

        // Not the root: the authority is another delegation's hash. The args check out, and the hook reverts.
        d.authority = keccak256("parent");
        bytes32 lowerHash = manager.getDelegationHash(d);
        vm.prank(address(manager));
        vm.expectRevert(abi.encodeWithSelector(NOT_ROOT));
        enforcer.beforeHook("", abi.encode(d), SINGLE_DEFAULT, execution, lowerHash, d.delegator, delegate);
        assertEq(enforcer.recorded(address(principalAccount), id, address(token), 1e18, recipient), address(0));

        // No args: a delegation of the principal's must show itself, so the call reverts.
        d.authority = manager.ROOT_AUTHORITY();
        bytes32 rootHash = manager.getDelegationHash(d);
        vm.prank(address(manager));
        vm.expectRevert(SpendGrantRedemptionEnforcer.MissingDelegation.selector);
        enforcer.beforeHook("", "", SINGLE_DEFAULT, execution, rootHash, d.delegator, delegate);

        // The root, shown by args whose hash is the one the manager passed: written.
        vm.prank(address(manager));
        enforcer.beforeHook("", abi.encode(d), SINGLE_DEFAULT, execution, rootHash, d.delegator, delegate);
        assertEq(enforcer.recorded(address(principalAccount), id, address(token), 1e18, recipient), delegate);
    }

    function test_enforcer_notRootComesBeforeWrongDelegate() public {
        // A principal's delegation below the root that also names another delegate fails both checks. The ERC requires
        // only a revert; the reference checks that the delegation is the root before it checks the delegate it names,
        // so its hook reverts NotRoot.
        bytes32 id = _register(_grant(address(principalAccount), delegate));
        bytes memory execution = _execution(id, 1e18, recipient);
        MockDelegationManager.Delegation memory d = _delegation(stranger, address(principalAccount), true);
        d.authority = keccak256("parent");
        bytes32 lowerHash = manager.getDelegationHash(d);
        vm.prank(address(manager));
        vm.expectRevert(abi.encodeWithSelector(NOT_ROOT));
        enforcer.beforeHook("", abi.encode(d), SINGLE_DEFAULT, execution, lowerHash, d.delegator, delegate);
    }

    function test_enforcer_argsThatAreNotTheHookedDelegationRevert() public {
        bytes32 id = _register(_grant(address(principalAccount), delegate));
        bytes memory execution = _execution(id, 1e18, recipient);
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
        bytes32 id = _register(_grant(address(principalAccount), delegate));
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](1);
        chain[0] = _delegation(delegate, address(principalAccount), true);
        MockDelegationManager.Caveat[] memory twice = new MockDelegationManager.Caveat[](2);
        twice[0] = chain[0].caveats[0];
        twice[1] = MockDelegationManager.Caveat(address(enforcer), "", "");
        chain[0].caveats = twice;
        bytes memory execution = _execution(id, 1e18, recipient);
        _link(chain);
        bytes[] memory contexts = new bytes[](1);
        contexts[0] = abi.encode(chain);
        bytes[] memory executions = new bytes[](1);
        executions[0] = execution;
        vm.prank(delegate);
        vm.expectRevert(SpendGrantRedemptionEnforcer.CaveatNotOnce.selector);
        manager.redeemDelegations(contexts, new bytes32[](1), executions);
    }

    function test_redemption_principalBelowTheRootReverts() public {
        // The delegate's own account is the root delegator, so the principal's delegation, carrying the caveat, is a
        // lower one, and its hook reverts. A record written there would stay live through the hooks above it and the
        // execution, which is the delegate account's direct call and never takes it.
        MockDeleGator delegateAccount = new MockDeleGator(address(manager), owner);
        bytes32 id = _register(_grant(address(principalAccount), address(delegateAccount)));
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](2);
        chain[0] = _delegation(address(delegateAccount), address(principalAccount), true);
        chain[1] = _delegation(address(principalAccount), address(delegateAccount), false);

        _redeemReverting(
            abi.encodeWithSelector(NOT_ROOT), address(delegateAccount), chain, _execution(id, 1e18, recipient)
        );
        _assertNothingSpent(id);
    }

    /// A probe after this enforcer on the principal's root: its beforeHook reads the record naming the delegate, and
    /// its afterHook, after the execution took it, reads nothing. The record is live only from the root's hook to the
    /// execution that takes it.
    function test_recordProbe_seesTheRecordAtThePrincipalsRoot() public {
        RecordProbe probe = new RecordProbe(enforcer);
        bytes32 id = _register(_grant(address(principalAccount), delegate));
        probe.watch(address(principalAccount), id, address(token), 1e18, recipient);
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](1);
        chain[0] = _delegation(delegate, address(principalAccount), true);
        MockDelegationManager.Caveat[] memory caveats = new MockDelegationManager.Caveat[](2);
        caveats[0] = chain[0].caveats[0];
        caveats[1] = MockDelegationManager.Caveat(address(probe), "", "");
        chain[0].caveats = caveats;
        _redeem(delegate, chain, SINGLE_DEFAULT, _execution(id, 1e18, recipient));
        assertEq(probe.seenBefore(), delegate, "the probe did not see the live record");
        assertEq(probe.seenAfter(), address(0), "the record outlived the execution that took it");
        (uint256 spent, uint256 calls) = registry.usage(id, address(token));
        assertEq(calls, 1);
        assertEq(spent, 1e18);
    }

    // ---------------------------------------------------------------- an id the registry does not know

    /// An id the registry does not know names no principal. Hook inputs that, for a registered grant of the same
    /// principal, write the record (its root shown by its args) or revert (no args, args that are not the hooked
    /// delegation, the caveat twice) write nothing and do not revert, for the principal's account and for a zero
    /// delegator, which a zero principal must not match. The same root with the registered id writes, so the inputs
    /// are live ones. With that record live, the principal's spend of the unknown id is NONEXISTENT (14) before any
    /// record is consulted.
    function test_redemption_unknownIdRecordsNothingAndSpendIsNonexistent() public {
        SpendGrant memory m = _grant(address(principalAccount), delegate);
        bytes32 id = _register(m);
        m.salt = 2;
        bytes32 unknown = registry.hashGrant(m);
        (address unknownPrincipal,) = registry.parties(unknown);
        assertEq(unknownPrincipal, address(0), "the unknown id is registered");
        bytes memory execution = _execution(unknown, 1e18, recipient);
        bytes memory registeredExecution = _execution(id, 1e18, recipient);

        MockDelegationManager.Delegation memory root = _delegation(delegate, address(principalAccount), true);
        root.authority = manager.ROOT_AUTHORITY();
        bytes32 rootHash = manager.getDelegationHash(root);
        MockDelegationManager.Delegation memory twice = _delegation(delegate, address(principalAccount), true);
        twice.authority = root.authority;
        twice.caveats = new MockDelegationManager.Caveat[](2);
        twice.caveats[0] = MockDelegationManager.Caveat(address(enforcer), "", "");
        twice.caveats[1] = MockDelegationManager.Caveat(address(enforcer), "", "");
        bytes32 twiceHash = manager.getDelegationHash(twice);
        MockDelegationManager.Delegation memory zeroRoot = _delegation(delegate, address(0), true);
        zeroRoot.authority = root.authority;
        bytes32 zeroRootHash = manager.getDelegationHash(zeroRoot);

        vm.startPrank(address(manager));
        enforcer.beforeHook(
            "", abi.encode(root), SINGLE_DEFAULT, execution, rootHash, address(principalAccount), delegate
        );
        enforcer.beforeHook("", "", SINGLE_DEFAULT, execution, rootHash, address(principalAccount), delegate);
        enforcer.beforeHook(
            "", abi.encode(root), SINGLE_DEFAULT, execution, keccak256("another"), address(principalAccount), delegate
        );
        enforcer.beforeHook(
            "", abi.encode(twice), SINGLE_DEFAULT, execution, twiceHash, address(principalAccount), delegate
        );
        enforcer.beforeHook("", "", SINGLE_DEFAULT, execution, bytes32(0), address(0), delegate);
        enforcer.beforeHook("", abi.encode(zeroRoot), SINGLE_DEFAULT, execution, zeroRootHash, address(0), delegate);
        enforcer.afterHook("", "", SINGLE_DEFAULT, execution, rootHash, address(principalAccount), delegate);
        vm.stopPrank();
        assertEq(enforcer.recorded(address(principalAccount), unknown, address(token), 1e18, recipient), address(0));
        assertEq(enforcer.recorded(address(0), unknown, address(token), 1e18, recipient), address(0));
        assertEq(enforcer.recorded(address(principalAccount), id, address(token), 1e18, recipient), address(0));

        // The same root for the registered id writes the principal's record; no args for it revert.
        vm.prank(address(manager));
        enforcer.beforeHook(
            "", abi.encode(root), SINGLE_DEFAULT, registeredExecution, rootHash, address(principalAccount), delegate
        );
        assertEq(enforcer.recorded(address(principalAccount), id, address(token), 1e18, recipient), delegate);
        vm.prank(address(manager));
        vm.expectRevert(SpendGrantRedemptionEnforcer.MissingDelegation.selector);
        enforcer.beforeHook("", "", SINGLE_DEFAULT, registeredExecution, rootHash, address(principalAccount), delegate);

        vm.expectCall(address(enforcer), abi.encodeWithSelector(enforcer.take.selector), 0);
        vm.expectCall(address(registry), abi.encodeWithSelector(registry.consume.selector), 0);
        vm.prank(address(principalAccount));
        vm.expectRevert(_err(14));
        executor.spend(unknown, address(token), 1e18, recipient);
    }

    /// Through the manager: the delegate redeems the principal's root, which carries the caveat, for a spend of an
    /// id the registry does not know. The hook neither records nor reverts, so the execution runs, and the whole
    /// redemption reverts with the executor's NONEXISTENT (14), not with any error of the enforcer's.
    function test_redemption_unknownIdThroughTheManagerIsNonexistent() public {
        SpendGrant memory m = _grant(address(principalAccount), delegate);
        _register(m);
        m.salt = 2;
        bytes32 unknown = registry.hashGrant(m);
        MockDelegationManager.Delegation[] memory chain = new MockDelegationManager.Delegation[](1);
        chain[0] = _delegation(delegate, address(principalAccount), true);
        _link(chain);
        bytes[] memory contexts = new bytes[](1);
        contexts[0] = abi.encode(chain);
        bytes[] memory executions = new bytes[](1);
        executions[0] = _execution(unknown, 1e18, recipient);

        vm.expectCall(address(enforcer), abi.encodeWithSelector(enforcer.take.selector), 0);
        vm.prank(delegate);
        vm.expectRevert(_err(14));
        manager.redeemDelegations(contexts, new bytes32[](1), executions);
    }

    // ---------------------------------------------------------------- the scenario matrix

    struct Matrix {
        MockDeleGator delegateAccount;
        MockDeleGator otherAccount;
        HookERC20 asset;
        MatrixThief thief;
        bytes execution;
        bytes32 grantId;
        bytes drivePrincipal;
        bytes driveDelegate;
        bytes viaCaveat;
        bytes viaCaveatNoArgs;
    }

    /// @notice Every chain shape in `_shape`, with the thief in every caveat slot or none, striking at every
    /// point with either delegation it may hold, alone and paired with every shape in one batch. Every row's outcome
    /// is exact: it reverts with the reason of its first failing entry (`_firstFailure`), or it pays, each of its
    /// entries at most once, plus one for a delegate-account call that the thief's own delegation drove, which is that
    /// account's own authorization. One test per first shape, to stay under the per-test gas limit.
    function test_matrix_S1_principalRoot() public {
        _matrixFrom(0, 0, 4, 377, 101);
    }

    function test_matrix_S1_principalRoot_pairedWithS6S7() public {
        _matrixFrom(0, 5, 8, 404, 98);
    }

    function test_matrix_S2_delegateRoot() public {
        _matrixFrom(1, 0, 4, 457, 0);
    }

    function test_matrix_S2_delegateRoot_pairedWithS6S7() public {
        _matrixFrom(1, 5, 8, 468, 0);
    }

    function test_matrix_S3_delegateRootWithOtherBetween() public {
        _matrixFrom(2, 0, 4, 537, 0);
    }

    function test_matrix_S3_delegateRootWithOtherBetween_pairedWithS6S7() public {
        _matrixFrom(2, 5, 8, 532, 0);
    }

    function test_matrix_S4_otherRoot() public {
        _matrixFrom(3, 0, 4, 457, 0);
    }

    function test_matrix_S4_otherRoot_pairedWithS6S7() public {
        _matrixFrom(3, 5, 8, 468, 0);
    }

    function test_matrix_S5_subDelegateRedeems() public {
        _matrixFrom(4, 0, 4, 154, 0);
    }

    function test_matrix_S6_principalTwiceCaveatLower() public {
        _matrixFrom(5, 0, 4, 537, 0);
    }

    function test_matrix_S6_principalTwiceCaveatLower_pairedWithS6S7() public {
        _matrixFrom(5, 5, 8, 532, 0);
    }

    function test_matrix_S6_principalTwiceCaveatAtRoot() public {
        _matrixFrom(6, 0, 4, 537, 165);
    }

    function test_matrix_S6_principalTwiceCaveatAtRoot_pairedWithS6S7() public {
        _matrixFrom(6, 5, 8, 532, 130);
    }

    function test_matrix_S6_principalTwiceCaveatAtBoth() public {
        _matrixFrom(7, 0, 4, 617, 0);
    }

    function test_matrix_S6_principalTwiceCaveatAtBoth_pairedWithS6S7() public {
        _matrixFrom(7, 5, 8, 596, 0);
    }

    function test_matrix_S7_rootCarriesTheCaveatTwice() public {
        _matrixFrom(8, 0, 4, 457, 0);
    }

    function test_matrix_S7_rootCarriesTheCaveatTwice_pairedWithS6S7() public {
        _matrixFrom(8, 5, 8, 468, 0);
    }

    /// @dev Shape `a` alone (when `bFrom` is 0) and paired with shapes `bFrom` to `bTo` in one batch; split so
    /// each test stays under the per-test gas and memory limits. `expectedCases` and `expectedStrikes` pin the
    /// test's case count and its count of strikes inside successful calls.
    function _matrixFrom(uint256 a, uint256 bFrom, uint256 bTo, uint256 expectedCases, uint256 expectedStrikes)
        internal
    {
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
        if (_canPay(a)) assertGt(struck, 0, "the thief never struck in a successful call");
        // Pinned: a change in either number means the matrix's coverage changed, and must be explained.
        assertEq(cases, expectedCases, "matrix case count changed");
        assertEq(struck, expectedStrikes, "matrix strike count changed");
    }

    function test_matrix_legitimateShapesPayOnceAndTheRestRevert() public {
        Matrix memory x = _matrix();
        // S1, and S6 with the caveat at the root only: one payment. Every other shape reverts: S2, S3, S4, and S6
        // with the caveat lower down carry it on a delegation of the principal's below the root (NotRoot), in S5 a
        // sub-delegate redeems (WrongRedeemer), and in S7 the root carries it twice (CaveatNotOnce).
        bool[9] memory pays = [true, false, false, false, false, false, true, false, false];
        for (uint256 a = 0; a < 9; a++) {
            (MockDelegationManager.Delegation[] memory chain, address redeemer) = _shape(x, a);
            _link(chain);
            x.thief.arm(0, "", "");
            uint256 snap = vm.snapshotState();
            (bool ok, uint256 calls, bytes memory ret) = _attempt(x, redeemer, _one(chain), 1);
            assertEq(ok, pays[a], "legitimate shape outcome");
            if (ok) assertEq(calls, 1, "legitimate shape pays once");
            else assertEq(ret, _cannotPayRevert(a), "legitimate shape revert");
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
                    bytes memory nested = act == 0
                        ? x.drivePrincipal
                        : act == 1 ? x.driveDelegate : act == 2 ? x.viaCaveat : x.viaCaveatNoArgs;
                    x.thief.arm(pt, nested, x.execution);
                    uint256 snap = vm.snapshotState();
                    (bool ok, uint256 calls, bytes memory ret) = _attempt(x, ra, chains, entries);
                    // Exact for every row: it pays only where no entry fails, and otherwise reverts with the reason
                    // of the first entry that fails.
                    bytes memory expected = _firstFailure(a, b, chains, pt, act, address(x.thief));
                    assertEq(ok, expected.length == 0, "a row's outcome is not the one the hook order gives");
                    if (!ok) assertEq(ret, expected, "a row reverted for another reason");
                    if (ok) {
                        uint256 allowed = entries + (act == 1 && x.thief.nestedSpent() ? 1 : 0);
                        assertLe(calls, allowed, "a redemption paid more than once");
                        if (x.thief.struck()) {
                            struck++;
                            // The thief's own moves behave as they should, so a broken nested path cannot pass
                            // for a safe one: the delegate account's call through the thief's own delegation is
                            // that account's authorization and goes through; everything else fails, each for its
                            // own reason.
                            if (act == 1) {
                                assertTrue(x.thief.nestedSpent(), "the delegate-account call failed");
                            } else {
                                assertFalse(x.thief.nestedSpent(), "a thief move without authority paid");
                                assertEq(x.thief.nestedError(), _thiefRevert(act), "a thief move failed otherwise");
                            }
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
    ) internal returns (bool ok, uint256 calls, bytes memory ret) {
        bytes[] memory contexts = new bytes[](entries);
        bytes32[] memory modes = new bytes32[](entries);
        bytes[] memory executions = new bytes[](entries);
        for (uint256 i = 0; i < entries; i++) {
            contexts[i] = abi.encode(chains[i]);
            executions[i] = x.execution;
        }
        vm.prank(redeemer);
        (ok, ret) = address(manager).call(abi.encodeCall(manager.redeemDelegations, (contexts, modes, executions)));
        (, calls) = registry.usage(x.grantId, address(x.asset));
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
        x.grantId = _register(m);
        x.execution = abi.encodePacked(
            address(executor),
            uint256(0),
            abi.encodeCall(SpendGrantExecutor.spend, (x.grantId, address(x.asset), 1e18, address(x.thief)))
        );
        MockDelegationManager.Delegation[] memory p = new MockDelegationManager.Delegation[](1);
        p[0] = _delegation(address(x.thief), address(principalAccount), false);
        _link(p);
        x.drivePrincipal = abi.encode(p);
        MockDelegationManager.Delegation[] memory d = new MockDelegationManager.Delegation[](1);
        d[0] = _delegation(address(x.thief), address(x.delegateAccount), false);
        _link(d);
        x.driveDelegate = abi.encode(d);
        // A delegation from the principal to the thief that carries the SpendGrant caveat: with its args, it names
        // the thief, not the grant's delegate, and reverts (WrongDelegate); without them, it reverts too
        // (MissingDelegation).
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

    /// @dev Whether shape `a` can pay at all: only where the caveat sits on the principal's root delegation to the
    /// delegate and on no other delegation, and the delegate redeems: S1, and S6 with the caveat at the root only.
    function _canPay(uint256 a) internal pure returns (bool) {
        return a == 0 || a == 6;
    }

    /// @dev Why shape `a`, which cannot pay, reverts: the caveat sits on a delegation of the principal's below the
    /// root (S2, S3, S4, and S6 with the caveat lower down: NotRoot); a sub-delegate redeems (S5: WrongRedeemer); the
    /// root carries the caveat twice (S7: CaveatNotOnce).
    function _cannotPayRevert(uint256 a) internal pure returns (bytes memory) {
        if (a == 8) return abi.encodeWithSelector(SpendGrantRedemptionEnforcer.CaveatNotOnce.selector);
        if (a == 4) return abi.encodeWithSelector(WRONG_REDEEMER);
        return _canPay(a) ? bytes("") : abi.encodeWithSelector(NOT_ROOT);
    }

    /// @dev The revert data a row must end with, or none when it must pay. The manager runs entry a's hooks and
    /// execution before entry b's beforeHooks, so the first entry that fails decides the row. A shape that cannot pay
    /// reverts at its own caveat (`_cannotPayRevert`), before anything in its entry could take a record. A shape that
    /// can pay fails only where the thief takes its record: driving the principal (act 0) from a beforeHook on that
    /// entry's root after this enforcer's caveat, it spends between the record's write and the execution, which then
    /// finds no record (13). Nowhere else is a record live when the thief strikes: the beforeAllHook pass and the
    /// hooks below the root run before the write, and the token callback, the afterHooks, and the afterAllHook pass
    /// after the take. Its other moves take none: the delegate's account spends without one (act 1), and the
    /// principal's delegation to the thief that carries the caveat reverts at its hook (acts 2 and 3).
    function _firstFailure(
        uint256 a,
        uint256 b,
        MockDelegationManager.Delegation[][] memory chains,
        uint8 pt,
        uint256 act,
        address thief
    ) internal view returns (bytes memory) {
        uint256[2] memory shapes = [a, b];
        for (uint256 i = 0; i < chains.length; i++) {
            if (!_canPay(shapes[i])) return _cannotPayRevert(shapes[i]);
            if (act == 0 && pt == 2 && _strikesWhileRecorded(chains[i], thief)) return _err(13);
        }
        return "";
    }

    /// @dev Whether the thief's caveat sits on the root of `c` after this enforcer's, so that its beforeHook (point 2)
    /// runs while the record is live: beforeHooks run leaf to root, each delegation's caveats in order, and the root
    /// delegator's execution follows them.
    function _strikesWhileRecorded(MockDelegationManager.Delegation[] memory c, address thief)
        internal
        view
        returns (bool)
    {
        MockDelegationManager.Caveat[] memory cv = c[c.length - 1].caveats;
        bool written;
        for (uint256 i = 0; i < cv.length; i++) {
            if (cv[i].enforcer == address(enforcer)) written = true;
            else if (cv[i].enforcer == thief) return written;
        }
        return false;
    }

    /// @dev Why the thief's nested redemption fails inside a call that succeeds: the principal's account, driven
    /// through a caveat-free delegation, finds no record (act 0: 13); the principal's delegation to the thief that
    /// carries the caveat names the thief, not the grant's delegate (act 2: WrongDelegate), and without its args it
    /// cannot show it is the root (act 3: MissingDelegation).
    function _thiefRevert(uint256 act) internal pure returns (bytes memory) {
        if (act == 0) return _err(13);
        if (act == 2) return abi.encodeWithSelector(WRONG_DELEGATE);
        return abi.encodeWithSelector(SpendGrantRedemptionEnforcer.MissingDelegation.selector);
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

    /// @dev Registers the terms from their principal's account, as `register` requires, and returns the id the
    /// registry assigned; executions and records use that id.
    function _register(SpendGrant memory m) internal returns (bytes32 id) {
        vm.prank(m.principal);
        id = registry.register(m);
    }

    /// @dev ERC-7579 single execution targeting the executor's `spend(grantId, asset, amount, recipient)`.
    function _execution(bytes32 id, uint256 amount, address to) internal view returns (bytes memory) {
        return abi.encodePacked(
            address(executor), uint256(0), abi.encodeCall(SpendGrantExecutor.spend, (id, address(token), amount, to))
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

    /// @dev Redeems `chain` as `caller` with a plain call rather than vm.expectRevert, and requires the redemption
    /// to revert with exactly `err`, so the test can go on to check that nothing moved.
    function _redeemReverting(
        bytes memory err,
        address caller,
        MockDelegationManager.Delegation[] memory chain,
        bytes memory execution
    ) internal {
        _link(chain);
        bytes[] memory contexts = new bytes[](1);
        contexts[0] = abi.encode(chain);
        bytes32[] memory modes = new bytes32[](1);
        bytes[] memory executions = new bytes[](1);
        executions[0] = execution;
        vm.prank(caller);
        (bool ok, bytes memory ret) =
            address(manager).call(abi.encodeCall(manager.redeemDelegations, (contexts, modes, executions)));
        assertFalse(ok, "the redemption did not revert");
        assertEq(ret, err, "the redemption reverted for another reason");
    }

    /// @dev Writes a record the way the manager would at a root delegation from `executingAccount`, for tests
    /// of the record alone, and checks that it was written: the hook reverts unless the registry names
    /// `executingAccount` as the grant's principal and `redeemer` as its delegate, and a test of a record that was
    /// never written passes for the wrong reason.
    function _writeRecord(bytes32 id, address executingAccount, address redeemer) internal {
        bytes memory execution = _execution(id, 1e18, recipient);
        (bytes memory args, bytes32 delegationHash) = _rootArgs(executingAccount, redeemer);
        vm.prank(address(manager));
        enforcer.beforeHook("", args, SINGLE_DEFAULT, execution, delegationHash, executingAccount, redeemer);
        assertEq(enforcer.recorded(executingAccount, id, address(token), 1e18, recipient), redeemer, "no record");
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

    function _assertNothingSpent(bytes32 id) internal view {
        (uint256 spent, uint256 calls) = registry.usage(id, address(token));
        assertEq(spent, 0);
        assertEq(calls, 0);
        assertEq(token.balanceOf(recipient), 0);
    }

    function _expect(Reason r) internal {
        vm.expectRevert(abi.encodeWithSelector(SpendGrantError.selector, r));
    }

    /// @dev `SpendGrantError(uint8)` carrying the literal reason number.
    function _err(uint8 reason) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(SPEND_GRANT_ERROR, reason);
    }
}
