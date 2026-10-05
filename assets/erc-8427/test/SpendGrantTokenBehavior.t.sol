// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AssetLimit, ISpendGrantRegistry, SpendGrant, SpendGrantError, Reason} from "../src/SpendGrantTypes.sol";
import {SpendGrantHash} from "../src/SpendGrantHash.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";
import {SpendGrantExecutor} from "../src/SpendGrantExecutor.sol";
import {MockERC20} from "./MockERC20.sol";

/// @dev Debits the sender the requested amount plus a fee on top; the recipient receives the request.
contract SenderFeeERC20 is MockERC20 {
    uint256 public constant FEE_BPS = 500;
    uint256 public lastRequested;

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        lastRequested = amount;
        uint256 fee = amount * FEE_BPS / 10_000;
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount + fee;
        balanceOf[to] += amount;
        return true;
    }
}

/// @dev Debits the sender exactly the request and delivers the request minus a fee: the common pattern.
contract RecipientFeeERC20 is MockERC20 {
    uint256 public constant FEE_BPS = 500;
    uint256 public lastRequested;

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        lastRequested = amount;
        uint256 fee = amount * FEE_BPS / 10_000;
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount - fee;
        return true;
    }
}

interface IBalance {
    function balanceOf(address) external view returns (uint256);
}

/// @dev The optional check the spec allows: still requests exactly `amount`, and reverts, rather than
/// recording anything else, when the principal's balance fell by more than that.
contract DeltaCheckedExecutor is SpendGrantExecutor {
    error PrincipalOvercharged(uint256 requested, uint256 debited);

    constructor(ISpendGrantRegistry registry_) SpendGrantExecutor(registry_) {}

    function _move(address token, address from, address to, uint256 amount) internal override {
        uint256 before = IBalance(token).balanceOf(from);
        super._move(token, from, to, amount);
        uint256 after_ = IBalance(token).balanceOf(from);
        if (after_ < before && before - after_ > amount) revert PrincipalOvercharged(amount, before - after_);
    }
}

/// @dev What a cap bounds when the token does not move exactly what was requested.
contract SpendGrantTokenBehaviorTest is Test {
    uint256 internal constant PRINCIPAL_PK = 0xA11CE;

    SpendGrantRegistry internal registry;
    SpendGrantExecutor internal executor;
    SpendGrantRegistry internal checkedRegistry;
    DeltaCheckedExecutor internal checkedExecutor;

    MockERC20 internal exact;
    SenderFeeERC20 internal senderFee;
    RecipientFeeERC20 internal recipientFee;

    address internal principal;
    address internal delegate;
    address internal recipient;

    function setUp() public {
        principal = vm.addr(PRINCIPAL_PK);
        delegate = vm.addr(0xB0B);
        recipient = vm.addr(0xC0C);

        exact = new MockERC20();
        senderFee = new SenderFeeERC20();
        recipientFee = new RecipientFeeERC20();

        uint64 nonce = vm.getNonce(address(this));
        registry = new SpendGrantRegistry(vm.computeCreateAddress(address(this), nonce + 1));
        executor = new SpendGrantExecutor(registry);
        checkedRegistry = new SpendGrantRegistry(vm.computeCreateAddress(address(this), nonce + 3));
        checkedExecutor = new DeltaCheckedExecutor(checkedRegistry);

        _fund(exact);
        _fund(senderFee);
        _fund(recipientFee);

        vm.warp(1_700_000_000);
    }

    // ---------------------------------------------------------------- the default executor records the request

    function test_senderFee_capBoundsTheRequestNotTheDebit() public {
        SpendGrant memory m = _grant(address(senderFee));
        bytes memory sig = _sign(m, registry);
        uint256 before = senderFee.balanceOf(principal);

        vm.prank(delegate);
        executor.spend(m, sig, address(senderFee), 1e18, recipient);

        // The executor asked for exactly what consume recorded; the token took more from the principal.
        assertEq(senderFee.lastRequested(), 1e18);
        (uint256 spent, uint256 calls) = registry.usage(_hash(m, registry), address(senderFee));
        assertEq(spent, 1e18);
        assertEq(calls, 1);
        assertEq(before - senderFee.balanceOf(principal), 1.05e18);
        assertEq(senderFee.balanceOf(recipient), 1e18);
    }

    function test_recipientFee_principalDebitedTheRequest() public {
        SpendGrant memory m = _grant(address(recipientFee));
        bytes memory sig = _sign(m, registry);
        uint256 before = recipientFee.balanceOf(principal);

        vm.prank(delegate);
        executor.spend(m, sig, address(recipientFee), 1e18, recipient);

        assertEq(recipientFee.lastRequested(), 1e18);
        (uint256 spent,) = registry.usage(_hash(m, registry), address(recipientFee));
        assertEq(spent, 1e18);
        assertEq(before - recipientFee.balanceOf(principal), 1e18);
        assertEq(recipientFee.balanceOf(recipient), 0.95e18);
    }

    function test_senderFee_lifetimeCapCountsRequests() public {
        SpendGrant memory m = _grant(address(senderFee));
        bytes memory sig = _sign(m, registry);

        // maxTotal is 3e18; three requests of 1e18 exhaust it while the principal paid 3.15e18.
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(delegate);
            executor.spend(m, sig, address(senderFee), 1e18, recipient);
        }
        assertEq(1e24 - senderFee.balanceOf(principal), 3.15e18);

        // Once the window clears, the lifetime cap still counts the three requests.
        vm.warp(block.timestamp + 86401);
        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(SpendGrantError.selector, Reason.OVER_CUMULATIVE_CAP));
        executor.spend(m, sig, address(senderFee), 1, recipient);
    }

    // ---------------------------------------------------------------- the optional balance check

    function test_deltaChecked_rejectsSenderFee() public {
        SpendGrant memory m = _grant(address(senderFee));
        bytes memory sig = _sign(m, checkedRegistry);
        uint256 before = senderFee.balanceOf(principal);

        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(DeltaCheckedExecutor.PrincipalOvercharged.selector, 1e18, 1.05e18));
        checkedExecutor.spend(m, sig, address(senderFee), 1e18, recipient);

        // Reverted rather than recorded: the registry and both balances are untouched.
        (uint256 spent, uint256 calls) = checkedRegistry.usage(_hash(m, checkedRegistry), address(senderFee));
        assertEq(spent, 0);
        assertEq(calls, 0);
        assertEq(senderFee.balanceOf(principal), before);
        assertEq(senderFee.balanceOf(recipient), 0);
    }

    function test_deltaChecked_acceptsRecipientFee() public {
        SpendGrant memory m = _grant(address(recipientFee));
        bytes memory sig = _sign(m, checkedRegistry);

        vm.prank(delegate);
        checkedExecutor.spend(m, sig, address(recipientFee), 1e18, recipient);

        (uint256 spent,) = checkedRegistry.usage(_hash(m, checkedRegistry), address(recipientFee));
        assertEq(spent, 1e18);
        assertEq(recipientFee.balanceOf(recipient), 0.95e18);
    }

    function test_deltaChecked_acceptsExactToken() public {
        SpendGrant memory m = _grant(address(exact));
        bytes memory sig = _sign(m, checkedRegistry);

        vm.prank(delegate);
        checkedExecutor.spend(m, sig, address(exact), 1e18, recipient);

        (uint256 spent,) = checkedRegistry.usage(_hash(m, checkedRegistry), address(exact));
        assertEq(spent, 1e18);
        assertEq(exact.balanceOf(recipient), 1e18);
    }

    // ---------------------------------------------------------------- helpers

    function _fund(MockERC20 token) internal {
        token.mint(principal, 1e24);
        vm.startPrank(principal);
        token.approve(address(executor), type(uint256).max);
        token.approve(address(checkedExecutor), type(uint256).max);
        vm.stopPrank();
    }

    function _grant(address asset) internal view returns (SpendGrant memory m) {
        m.principal = principal;
        m.delegate = delegate;
        m.recipientMode = 0;
        m.recipient = recipient;
        m.assetCombine = 0;
        m.windowSeconds = 86400;
        m.validAfter = 1_699_999_000;
        m.validUntil = 1_900_000_000;
        m.salt = 1;
        m.assets = new AssetLimit[](1);
        m.assets[0] = AssetLimit(asset, 1e18, 3e18, 3e18);
    }

    function _hash(SpendGrant memory m, SpendGrantRegistry reg) internal view returns (bytes32) {
        return SpendGrantHash.digest(block.chainid, address(reg), m);
    }

    function _sign(SpendGrant memory m, SpendGrantRegistry reg) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRINCIPAL_PK, _hash(m, reg));
        return abi.encodePacked(r, s, v);
    }
}
