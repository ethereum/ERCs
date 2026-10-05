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

/// @dev Returns nothing from transferFrom, like USDT; moves funds unless told to revert.
contract NoReturnERC20 is MockERC20 {
    bool public shouldRevert;

    function setRevert(bool v) external {
        shouldRevert = v;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        if (shouldRevert) revert("no");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        assembly {
            return(0, 0)
        }
    }
}

/// @dev Moves funds, then returns whatever shape it was told to: a word, a short blob, or a megabyte.
contract OddReturnERC20 is MockERC20 {
    uint256 public returnLength;
    bytes32 public returnWord;

    function configure(uint256 length, bytes32 word) external {
        returnLength = length;
        returnWord = word;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        bytes32 word = returnWord;
        uint256 length = returnLength;
        assembly {
            mstore(0, word)
            return(0, length)
        }
    }
}

/// @dev Exposes the movement hook so it can be aimed at an address the registry would never let through.
contract MoveHarness is SpendGrantExecutor {
    constructor(ISpendGrantRegistry registry_) SpendGrantExecutor(registry_) {}

    function move(address token, address from, address to, uint256 amount) external {
        _move(token, from, to, amount);
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
        vm.warp(vm.getBlockTimestamp() + 86401);
        vm.prank(delegate);
        vm.expectRevert(abi.encodeWithSelector(SpendGrantError.selector, Reason.OVER_CUMULATIVE_CAP));
        executor.spend(m, sig, address(senderFee), 1, recipient);
    }

    // ---------------------------------------------------------------- what the token returns

    function test_noReturnToken_isAcceptedWhenItMoves() public {
        NoReturnERC20 usdtLike = new NoReturnERC20();
        _fund(usdtLike);
        SpendGrant memory m = _grant(address(usdtLike));
        bytes memory sig = _sign(m, registry);

        vm.prank(delegate);
        executor.spend(m, sig, address(usdtLike), 1e18, recipient);
        assertEq(usdtLike.balanceOf(recipient), 1e18);
        (uint256 spent,) = registry.usage(_hash(m, registry), address(usdtLike));
        assertEq(spent, 1e18);

        // The same token reverting is a failed movement with no debit left behind.
        usdtLike.setRevert(true);
        vm.prank(delegate);
        vm.expectRevert(SpendGrantExecutor.TransferFailed.selector);
        executor.spend(m, sig, address(usdtLike), 1e18, recipient);
        (uint256 spentAfter,) = registry.usage(_hash(m, registry), address(usdtLike));
        assertEq(spentAfter, 1e18);
    }

    function test_malformedReturns_areFailedMovements() public {
        OddReturnERC20 odd = new OddReturnERC20();
        _fund(odd);
        SpendGrant memory m = _grant(address(odd));
        bytes memory sig = _sign(m, registry);
        bytes32 h = _hash(m, registry);

        uint256[4] memory lengths = [uint256(1), 31, 64, 32];
        bytes32[4] memory words = [bytes32(uint256(1)), bytes32(uint256(1)), bytes32(uint256(1)), bytes32(uint256(2))];
        for (uint256 i = 0; i < 4; i++) {
            odd.configure(lengths[i], words[i]);
            vm.prank(delegate);
            vm.expectRevert(SpendGrantExecutor.TransferFailed.selector);
            executor.spend(m, sig, address(odd), 1e18, recipient);
        }
        (uint256 spent,) = registry.usage(h, address(odd));
        assertEq(spent, 0);
        assertEq(odd.balanceOf(recipient), 0);

        // Exactly one word equal to true is the well-formed success.
        odd.configure(32, bytes32(uint256(1)));
        vm.prank(delegate);
        executor.spend(m, sig, address(odd), 1e18, recipient);
        assertEq(odd.balanceOf(recipient), 1e18);
    }

    function test_returnBomb_isAFailedMovementWithAReason() public {
        OddReturnERC20 bomb = new OddReturnERC20();
        _fund(bomb);
        bomb.configure(0x100000, bytes32(uint256(1)));
        SpendGrant memory m = _grant(address(bomb));
        bytes memory sig = _sign(m, registry);

        vm.prank(delegate);
        (bool ok, bytes memory ret) = address(executor).call{gas: 500_000}(
            abi.encodeCall(executor.spend, (m, sig, address(bomb), 1e18, recipient))
        );
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(SpendGrantExecutor.TransferFailed.selector));
    }

    function test_move_emptyReturnFromAnAddressWithoutCodeFails() public {
        uint64 nonce = vm.getNonce(address(this));
        SpendGrantRegistry harnessRegistry = new SpendGrantRegistry(vm.computeCreateAddress(address(this), nonce + 1));
        MoveHarness harness = new MoveHarness(harnessRegistry);

        // A call to an address without code succeeds with no return data; the hook refuses to count it.
        vm.expectRevert(SpendGrantExecutor.TransferFailed.selector);
        harness.move(address(0xD00D), principal, recipient, 1);
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
