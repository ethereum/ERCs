// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AssetLimit, ISpendGrantRegistry, SpendGrant} from "../src/SpendGrantTypes.sol";
import {SpendGrantHash} from "../src/SpendGrantHash.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";
import {SpendGrantExecutor} from "../src/SpendGrantExecutor.sol";
import {MockERC20} from "./MockERC20.sol";

/// @dev Proves an extension can reach the internal signature-check and debit machinery.
contract DerivedRegistry is SpendGrantRegistry {
    constructor(address executor_) SpendGrantRegistry(executor_) {}

    function checkSignature(address principal, bytes32 digest, bytes calldata sig) external view returns (bool) {
        return _validSignature(principal, digest, sig);
    }

    function debitDirect(
        bytes32 grantHash,
        uint64 windowSeconds,
        AssetLimit memory limit,
        address asset,
        uint256 amount,
        address recipient
    ) external {
        _debit(grantHash, windowSeconds, limit, asset, amount, recipient);
    }
}

/// @dev Proves an extension can be built on top of SpendGrantExecutor without changing spend().
contract DerivedExecutor is SpendGrantExecutor {
    constructor(ISpendGrantRegistry registry_) SpendGrantExecutor(registry_) {}
}

contract InheritanceTest is Test {
    uint256 internal constant PRINCIPAL_PK = 0xA11CE;
    uint256 internal constant DELEGATE_PK = 0xB0B;

    DerivedRegistry internal registry;
    DerivedExecutor internal executor;
    MockERC20 internal token;

    address internal principal;
    address internal delegate;
    address internal recipient;

    function setUp() public {
        principal = vm.addr(PRINCIPAL_PK);
        delegate = vm.addr(DELEGATE_PK);
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

    function _sign(SpendGrant memory m) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(PRINCIPAL_PK, SpendGrantHash.digest(block.chainid, address(registry), m));
        return abi.encodePacked(r, s, v);
    }

    function test_derivedRegistry_exposesInternalSignatureCheck() public view {
        SpendGrant memory m = _grant();
        bytes32 digest = SpendGrantHash.digest(block.chainid, address(registry), m);
        bytes memory sig = _sign(m);
        assertTrue(registry.checkSignature(principal, digest, sig));
    }

    function test_derivedRegistry_exposesInternalDebit() public {
        SpendGrant memory m = _grant();
        bytes32 h = SpendGrantHash.digest(block.chainid, address(registry), m);
        registry.debitDirect(h, m.windowSeconds, m.assets[0], address(token), 1e18, recipient);
        (uint256 spent, uint256 calls) = registry.usage(h, address(token));
        assertEq(spent, 1e18);
        assertEq(calls, 1);
    }

    function test_derivedPair_spendStillWorks() public {
        SpendGrant memory m = _grant();
        bytes memory sig = _sign(m);
        bytes32 h = SpendGrantHash.digest(block.chainid, address(registry), m);

        vm.prank(delegate);
        executor.spend(m, sig, address(token), 1e18, recipient);

        (uint256 spent,) = registry.usage(h, address(token));
        assertEq(spent, 1e18);
        assertEq(token.balanceOf(recipient), 1e18);
    }
}
