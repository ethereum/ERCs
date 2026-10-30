// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import {
    AssetLimit,
    ISpendGrantRegistry,
    NATIVE,
    NotPrincipal,
    Reason,
    SpendGrant,
    SpendGrantError,
    UnknownGrant
} from "../src/SpendGrantTypes.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";
import {SpendGrantExecutor} from "../src/SpendGrantExecutor.sol";
import {MockERC20} from "./MockERC20.sol";

/// @dev A smart account that makes any call its owner or its session key asks for, bubbling the callee's revert.
/// No grant signature exists, so whatever can make it call `register` can create grants for it.
contract SessionKeyAccount {
    address internal immutable OWNER;
    address internal immutable SESSION_KEY;

    error NotAuthorized();

    constructor(address owner_, address sessionKey_) {
        OWNER = owner_;
        SESSION_KEY = sessionKey_;
    }

    function execute(address target, bytes calldata data) external returns (bytes memory ret) {
        if (msg.sender != OWNER && msg.sender != SESSION_KEY) revert NotAuthorized();
        bool ok;
        (ok, ret) = target.call(data);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(ret, 32), mload(ret))
            }
        }
    }
}

/// @dev Rules the review added: payee restrictions, event topics, the selected-asset code check, what a contract
/// principal's call policy implies, stacking grants, the live-debit bound on spendable amounts, and confirming a
/// revocation.
contract SpendGrantSemanticsTest is Test {
    uint256 internal constant PRINCIPAL_PK = 0xA11CE;
    uint256 internal constant SESSION_PK = 0x5E55;

    SpendGrantRegistry internal registry; // this test contract is its executor
    SpendGrantRegistry internal execRegistry;
    SpendGrantExecutor internal executor;
    MockERC20 internal token;

    address internal principal;
    address internal delegate;
    address internal recipient;

    // Declared here, not taken from ISpendGrantRegistry, so a change to the registry's indexing fails the tests.
    event GrantConsumed(
        bytes32 indexed grantId, address indexed principal, address asset, uint256 amount, address indexed recipient
    );

    function setUp() public {
        principal = vm.addr(PRINCIPAL_PK);
        delegate = vm.addr(0xB0B);
        recipient = vm.addr(0xC0C);

        token = new MockERC20();
        registry = new SpendGrantRegistry(address(this));

        uint64 nonce = vm.getNonce(address(this));
        execRegistry = new SpendGrantRegistry(vm.computeCreateAddress(address(this), nonce + 1));
        executor = new SpendGrantExecutor(execRegistry);
        // Asset lists are ascending; _grant lists the token before NATIVE.
        assertLt(uint160(address(token)), uint160(NATIVE));

        token.mint(principal, 1e24);
        vm.prank(principal);
        token.approve(address(executor), type(uint256).max);

        vm.warp(1_700_000_000);
    }

    // ---------------------------------------------------------------- recipient argument

    function test_recipient_mode1RejectsZeroPrincipalRegistryExecutor() public {
        SpendGrant memory m = _grant();
        m.recipientMode = 1;
        m.recipient = address(0);
        bytes32 id = _register(registry, m);

        address[4] memory bad = [address(0), principal, address(registry), address(this)];
        for (uint256 i = 0; i < bad.length; i++) {
            _assertConsumeRejects(id, NATIVE, 1, bad[i], Reason.WRONG_RECIPIENT);
        }
        registry.consume(id, delegate, NATIVE, 1, recipient);
        (uint256 spent,) = registry.usage(id, NATIVE);
        assertEq(spent, 1);
    }

    /// A fixed recipient that is the executor could never be paid, so register refuses the grant (INVALID_GRANT)
    /// instead of storing one that fails closed on every spend. The executor still never pays itself.
    function test_recipient_mode0GrantNamingTheExecutorIsRefused() public {
        SpendGrant memory m = _grant();
        m.recipient = address(executor);
        _assertRegisterRejects(execRegistry, m);
        (address p,) = execRegistry.parties(execRegistry.hashGrant(m));
        assertEq(p, address(0));

        SpendGrant memory open = _grant();
        open.recipientMode = 1;
        open.recipient = address(0);
        bytes32 openId = _register(execRegistry, open);
        _assertSpendRejects(openId, address(token), 1e18, address(executor), _err(Reason.WRONG_RECIPIENT));
        assertEq(token.balanceOf(address(executor)), 0);
    }

    function test_recipient_theSpentAssetIsNotAPayee() public {
        // Mode 1: the delegate names the token itself; the registry refuses.
        SpendGrant memory m = _grant();
        m.recipientMode = 1;
        m.recipient = address(0);
        bytes32 id = _register(execRegistry, m);
        _assertSpendRejects(id, address(token), 1e18, address(token), _err(Reason.WRONG_RECIPIENT));
        assertEq(token.balanceOf(address(token)), 0);

        // Mode 0: a grant fixing a listed asset as its recipient could never pay, so register refuses it.
        SpendGrant memory locked = _grant();
        locked.recipient = address(token);
        vm.prank(principal);
        _expect(Reason.INVALID_GRANT);
        execRegistry.register(locked);
    }

    // ---------------------------------------------------------------- event

    function test_event_indexesGrantPrincipalAndRecipient() public {
        bytes32 id = _register(execRegistry, _grant());

        vm.recordLogs();
        vm.expectEmit(true, true, true, true, address(execRegistry));
        emit GrantConsumed(id, principal, address(token), 1e18, recipient);
        vm.prank(delegate);
        executor.spend(id, address(token), 1e18, recipient);

        // The topics a log filter matches on, against the literal event signature.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(execRegistry)) continue;
            found++;
            assertEq(logs[i].topics.length, 4);
            assertEq(logs[i].topics[0], keccak256("GrantConsumed(bytes32,address,address,uint256,address)"));
            assertEq(logs[i].topics[1], id);
            assertEq(logs[i].topics[2], bytes32(uint256(uint160(principal))));
            assertEq(logs[i].topics[3], bytes32(uint256(uint160(recipient))));
            assertEq(logs[i].data, abi.encode(address(token), uint256(1e18)));
        }
        assertEq(found, 1);
    }

    // ---------------------------------------------------------------- selected-asset code check

    function test_codeCheck_appliesToTheSpentAssetOnly() public {
        address codeless = address(uint160(address(token)) - 1); // sorts before the token, has no code
        assertEq(codeless.code.length, 0);
        SpendGrant memory m = _grant();
        m.assets = new AssetLimit[](2);
        m.assets[0] = AssetLimit(codeless, 1, 1, 1);
        m.assets[1] = AssetLimit(address(token), 1e18, 10e18, 100e18);
        bytes32 id = _register(execRegistry, m);

        // The listing without code does not block the token.
        vm.prank(delegate);
        executor.spend(id, address(token), 1e18, recipient);
        assertEq(token.balanceOf(recipient), 1e18);

        // Spending the codeless listing itself is INVALID_GRANT.
        _assertSpendRejects(id, codeless, 1, recipient, _err(Reason.INVALID_GRANT));

        // Membership is checked first: an unlisted codeless address is WRONG_ASSET, not INVALID_GRANT.
        vm.prank(delegate);
        _expect(Reason.WRONG_ASSET);
        executor.spend(id, address(0xD00D), 1, recipient);
    }

    function test_codeCheck_rejectsAnEip7702AccountAsAsset() public {
        // An EOA that delegated its code is an account, not a token, whatever its code length says.
        address accountAsAsset = address(uint160(address(token)) - 1);
        vm.etch(accountAsAsset, abi.encodePacked(hex"ef0100", address(0xC0DE1E55)));
        assertEq(accountAsAsset.code.length, 23);
        SpendGrant memory m = _grant();
        m.assets = new AssetLimit[](2);
        m.assets[0] = AssetLimit(accountAsAsset, 1, 1, 1);
        m.assets[1] = AssetLimit(address(token), 1e18, 10e18, 100e18);
        bytes32 id = _register(execRegistry, m);

        // Other assets of the same grant are unaffected.
        vm.prank(delegate);
        executor.spend(id, address(token), 1e18, recipient);
        assertEq(token.balanceOf(recipient), 1e18);

        vm.prank(delegate);
        _expect(Reason.INVALID_GRANT);
        executor.spend(id, accountAsAsset, 1, recipient);
    }

    // ---------------------------------------------------------------- eviction

    function test_evict_dropsOnlyExpiredDebitsAndChangesNoView() public {
        SpendGrant memory m = _grant();
        m.assets = new AssetLimit[](1);
        m.assets[0] = AssetLimit(NATIVE, 10, 1e6, 1e6);
        m.windowSeconds = 100;
        bytes32 id = _register(registry, m);

        uint256 t0 = vm.getBlockTimestamp();
        for (uint256 i = 0; i < 6; i++) {
            vm.warp(t0 + i);
            registry.consume(id, delegate, NATIVE, 1 + i, recipient);
        }
        // Debits 0..2 expire at t0+100..t0+102; at t0+102 three are expired, three live.
        vm.warp(t0 + 102);
        (uint256 rollingBefore, uint256 liveBefore) = registry.rollingUsage(id, NATIVE);
        assertEq(liveBefore, 3);
        assertEq(rollingBefore, 4 + 5 + 6);

        // Bounded by maxCount, callable by anyone, and never touching a live debit.
        vm.prank(vm.addr(0xBAD));
        registry.evict(id, NATIVE, 2);
        (uint256 rollingMid, uint256 liveMid) = registry.rollingUsage(id, NATIVE);
        assertEq(liveMid, 3);
        assertEq(rollingMid, rollingBefore);
        registry.evict(id, NATIVE, 100);
        (uint256 rollingAfter, uint256 liveAfter) = registry.rollingUsage(id, NATIVE);
        assertEq(liveAfter, 3);
        assertEq(rollingAfter, rollingBefore);
        (uint256[] memory expiresAt, uint256[] memory amounts) = registry.liveDebits(id, NATIVE, 10);
        assertEq(expiresAt.length, 3);
        assertEq(amounts[0], 4);
        (uint256 spent, uint256 calls) = registry.usage(id, NATIVE);
        assertEq(spent, 1 + 2 + 3 + 4 + 5 + 6);
        assertEq(calls, 6);

        // Evicting again, or on an asset with nothing recorded, is a no-op.
        registry.evict(id, NATIVE, 100);
        registry.evict(id, address(token), 100);
        (uint256 rollingFinal, uint256 liveFinal) = registry.rollingUsage(id, NATIVE);
        assertEq(liveFinal, 3);
        assertEq(rollingFinal, rollingBefore);

        // The next consume behaves exactly as if nothing had been evicted.
        registry.consume(id, delegate, NATIVE, 7, recipient);
        (uint256 rollingNext, uint256 liveNext) = registry.rollingUsage(id, NATIVE);
        assertEq(liveNext, 4);
        assertEq(rollingNext, rollingBefore + 7);
    }

    // ---------------------------------------------------------------- contract principals

    /// A contract principal's grant policy is its call policy. The session key alone makes the account register a
    /// grant naming the session key as delegate with an open recipient, and pays itself; calling `register`
    /// directly it is not the account. Nothing on the spend path calls the account.
    function test_contractPrincipal_callPolicyIsItsGrantPolicy() public {
        address sessionKey = vm.addr(SESSION_PK);
        SessionKeyAccount account = new SessionKeyAccount(principal, sessionKey);
        token.mint(address(account), 1e24);
        vm.prank(address(account));
        token.approve(address(executor), type(uint256).max);

        SpendGrant memory m = _grant();
        m.principal = address(account);
        m.delegate = sessionKey;
        m.recipientMode = 1;
        m.recipient = address(0);
        bytes memory registerCall = abi.encodeCall(ISpendGrantRegistry.register, (m));

        vm.prank(sessionKey);
        (bool ok, bytes memory ret) = address(execRegistry).call(registerCall);
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(NotPrincipal.selector));

        vm.prank(sessionKey);
        bytes32 id = abi.decode(account.execute(address(execRegistry), registerCall), (bytes32));
        (address p, address d) = execRegistry.parties(id);
        assertEq(p, address(account));
        assertEq(d, sessionKey);

        vm.expectCall(address(account), bytes(""), 0);
        vm.prank(sessionKey);
        executor.spend(id, address(token), 1e18, sessionKey);
        assertEq(token.balanceOf(sessionKey), 1e18);
    }

    // ---------------------------------------------------------------- grants stack

    function test_grants_doNotSupersedeEachOther() public {
        SpendGrant memory first = _grant();
        first.assets[0] = AssetLimit(address(token), 1e18, 1e18, 1e18);
        SpendGrant memory second = _grant();
        second.assets[0] = AssetLimit(address(token), 5e17, 5e17, 5e17); // a "lowered" cap
        second.salt = 2;
        bytes32 firstId = _register(execRegistry, first);
        bytes32 secondId = _register(execRegistry, second);

        vm.startPrank(delegate);
        executor.spend(firstId, address(token), 1e18, recipient);
        executor.spend(secondId, address(token), 5e17, recipient);
        vm.stopPrank();

        // Both caps were spendable: the delegate moved the sum, not the lower cap.
        assertEq(token.balanceOf(recipient), 1.5e18);
    }

    // ---------------------------------------------------------------- spendable now near the bound

    function test_spendableNow_isBoundedByFreeDebitSlots() public {
        SpendGrant memory m = _grant();
        m.assets = new AssetLimit[](1);
        m.assets[0] = AssetLimit(NATIVE, 1, 1e6, 1e6);
        bytes32 id = _register(registry, m);

        for (uint256 i = 0; i < 1020; i++) {
            registry.consume(id, delegate, NATIVE, 1, recipient);
        }
        (uint256 rolling, uint256 live) = registry.rollingUsage(id, NATIVE);
        assertEq(live, 1020);
        // The window and lifetime remainders are both about 1e6, but only four slots are free.
        assertGt(1e6 - rolling, 4);
        for (uint256 i = 0; i < 4; i++) {
            registry.consume(id, delegate, NATIVE, 1, recipient);
        }
        _expect(Reason.WINDOW_FULL);
        registry.consume(id, delegate, NATIVE, 1, recipient);
    }

    // ---------------------------------------------------------------- confirming a revocation

    /// A mistyped id revokes nothing and cannot pass for a revocation: it reverts UnknownGrant, and the grant keeps
    /// spending. After the real revocation, simulating consume from the executor confirms it with REVOKED.
    function test_revoke_unknownIdRevertsAndLeavesTheGrantLive() public {
        bytes32 id = _register(registry, _grant());
        bytes32 wrong = keccak256("not the grant");

        vm.prank(principal);
        (bool ok, bytes memory ret) = address(registry).call(abi.encodeCall(ISpendGrantRegistry.revoke, (wrong)));
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(UnknownGrant.selector, wrong));
        assertFalse(registry.revoked(wrong));
        assertFalse(registry.revoked(id));
        registry.consume(id, delegate, NATIVE, 1, recipient);

        // The confirmation the spec recommends: simulate consume from the executor and expect REVOKED.
        vm.prank(principal);
        registry.revoke(id);
        (bool checked, Reason reason) = registry.check(id, delegate, NATIVE, 1, recipient);
        assertFalse(checked);
        assertEq(uint8(reason), uint8(Reason.REVOKED));
        (ok, ret) =
            address(registry).call(abi.encodeCall(ISpendGrantRegistry.consume, (id, delegate, NATIVE, 1, recipient)));
        assertFalse(ok);
        assertEq(ret, _err(Reason.REVOKED));
    }

    // ---------------------------------------------------------------- helpers

    function _grant() internal view returns (SpendGrant memory m) {
        m.principal = principal;
        m.delegate = delegate;
        m.recipientMode = 0;
        m.recipient = recipient;
        m.assetCombine = 0;
        m.windowSeconds = 86400;
        m.validAfter = 1_699_999_000;
        m.validUntil = 1_900_000_000;
        m.salt = 1;
        m.assets = new AssetLimit[](2);
        m.assets[0] = AssetLimit(address(token), 1e18, 10e18, 100e18);
        m.assets[1] = AssetLimit(NATIVE, 1 ether, 5 ether, 10 ether);
    }

    function _register(SpendGrantRegistry reg, SpendGrant memory m) internal returns (bytes32 id) {
        vm.prank(m.principal);
        id = reg.register(m);
    }

    /// `register` by the terms' principal fails with exactly `SpendGrantError(INVALID_GRANT)`.
    function _assertRegisterRejects(SpendGrantRegistry reg, SpendGrant memory m) internal {
        vm.prank(m.principal);
        (bool ok, bytes memory ret) = address(reg).call(abi.encodeCall(ISpendGrantRegistry.register, (m)));
        assertFalse(ok);
        assertEq(ret, _err(Reason.INVALID_GRANT));
    }

    /// `consume` on `registry` (from its executor, this contract) by the delegate fails with exactly `r`.
    function _assertConsumeRejects(bytes32 id, address asset, uint256 amount, address to, Reason r) internal {
        (bool ok, bytes memory ret) =
            address(registry).call(abi.encodeCall(ISpendGrantRegistry.consume, (id, delegate, asset, amount, to)));
        assertFalse(ok);
        assertEq(ret, _err(r));
    }

    /// `executor.spend` called by the delegate fails with exactly `expected`.
    function _assertSpendRejects(bytes32 id, address asset, uint256 amount, address to, bytes memory expected)
        internal
    {
        vm.prank(delegate);
        (bool ok, bytes memory ret) =
            address(executor).call(abi.encodeCall(SpendGrantExecutor.spend, (id, asset, amount, to)));
        assertFalse(ok);
        assertEq(ret, expected);
    }

    function _err(Reason r) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(SpendGrantError.selector, r);
    }

    function _expect(Reason r) internal {
        vm.expectRevert(_err(r));
    }
}
