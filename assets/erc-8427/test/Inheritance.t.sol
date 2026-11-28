// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AssetLimit, ISpendGrantRegistry, Reason, SpendGrant} from "../src/SpendGrantTypes.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";
import {SpendGrantExecutor} from "../src/SpendGrantExecutor.sol";
import {MockERC20} from "./MockERC20.sol";

/// @dev Proves an extension can reach the internal debit machinery: the cap and window preview, and the debit.
contract DerivedRegistry is SpendGrantRegistry {
    constructor(address executor_) SpendGrantRegistry(executor_) {}

    function previewDebit(bytes32 grantId, AssetLimit memory limit, address asset, uint256 amount)
        external
        view
        returns (Reason reason)
    {
        (reason,) = _previewDebit(grantId, limit, asset, amount);
    }

    function debitDirect(bytes32 grantId, AssetLimit memory limit, address asset, uint256 amount) external {
        _debit(grantId, limit, asset, amount);
    }
}

/// @dev Proves an extension can be built on top of SpendGrantExecutor without changing spend().
contract DerivedExecutor is SpendGrantExecutor {
    constructor(ISpendGrantRegistry registry_) SpendGrantExecutor(registry_) {}
}

contract InheritanceTest is Test {
    bytes4 internal constant SPEND_GRANT_ERROR = bytes4(keccak256("SpendGrantError(uint8)"));

    DerivedRegistry internal registry;
    DerivedExecutor internal executor;
    MockERC20 internal token;

    address internal principal;
    address internal delegate;
    address internal recipient;

    function setUp() public {
        principal = makeAddr("principal");
        delegate = makeAddr("delegate");
        recipient = vm.addr(0xC0C);

        token = new MockERC20();

        uint64 nonce = vm.getNonce(address(this));
        address predicted = vm.computeCreateAddress(address(this), nonce + 1);
        registry = new DerivedRegistry(predicted);
        executor = new DerivedExecutor(registry);
        assertEq(address(executor), predicted);

        token.mint(principal, 1e24);
        vm.prank(principal);
        token.approve(address(executor), type(uint256).max);

        vm.warp(1_700_000_000);
    }

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
        m.assets = new AssetLimit[](1);
        m.assets[0] = AssetLimit(address(token), 1e18, 10e18, 100e18);
    }

    function _register(SpendGrant memory m) internal returns (bytes32 id) {
        vm.prank(m.principal);
        id = registry.register(m);
    }

    /// `SpendGrantError(uint8)` carrying the literal reason number.
    function _err(uint8 reason) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(SPEND_GRANT_ERROR, reason);
    }

    /// `_previewDebit(grantId, limit, asset, amount)`: steps 9-12 for a registered grant, without writing.
    function test_derivedRegistry_exposesInternalPreviewDebit() public {
        SpendGrant memory m = _grant();
        bytes32 id = _register(m);
        assertEq(uint8(registry.previewDebit(id, m.assets[0], address(token), 2e18)), 8); // OVER_TX_CAP
        assertEq(uint8(registry.previewDebit(id, m.assets[0], address(token), 1e18)), 0); // OK
        (uint256 spent, uint256 calls) = registry.usage(id, address(token));
        assertEq(spent, 0);
        assertEq(calls, 0);
    }

    /// `_debit(grantId, limit, asset, amount)` takes no window: the debit counts in the registered grant's window.
    function test_derivedRegistry_exposesInternalDebit() public {
        SpendGrant memory m = _grant();
        bytes32 id = _register(m);
        registry.debitDirect(id, m.assets[0], address(token), 1e18);
        (uint256 spent, uint256 calls) = registry.usage(id, address(token));
        assertEq(spent, 1e18);
        assertEq(calls, 1);
        (uint256 windowSpent, uint256 live) = registry.rollingUsage(id, address(token));
        assertEq(windowSpent, 1e18);
        assertEq(live, 1);

        // A debit the preview rejects reverts with the preview's reason.
        vm.expectRevert(_err(8)); // OVER_TX_CAP
        registry.debitDirect(id, m.assets[0], address(token), 2e18);
    }

    function test_derivedPair_spendStillWorks() public {
        bytes32 id = _register(_grant());

        vm.prank(delegate);
        executor.spend(id, address(token), 1e18, recipient);

        (uint256 spent,) = registry.usage(id, address(token));
        assertEq(spent, 1e18);
        assertEq(token.balanceOf(recipient), 1e18);
    }
}
