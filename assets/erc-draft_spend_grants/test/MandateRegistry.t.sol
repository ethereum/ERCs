// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AssetLimit, IERC1271, SpendGrant, MandateError, Reason, WAD} from "../src/MandateTypes.sol";
import {MandateHash} from "../src/MandateHash.sol";
import {MandateRegistry} from "../src/MandateRegistry.sol";
import {MandateExecutor} from "../src/MandateExecutor.sol";
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

contract RejectEther {
    receive() external payable {
        revert();
    }
}

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

contract MandateRegistryTest is Test {
    uint256 internal constant PRINCIPAL_PK = 0xA11CE;
    uint256 internal constant DELEGATE_PK = 0xB0B;

    MandateRegistry internal registry;
    MandateRegistry internal execRegistry;
    MandateExecutor internal executor;
    MockERC20 internal token;

    address internal principal;
    address internal delegate;
    address internal recipient;

    event GrantRevoked(address indexed principal, bytes32 indexed mandateHash);
    event GrantConsumed(
        bytes32 indexed mandateHash, address indexed asset, uint256 amount, address indexed recipient
    );

    function setUp() public {
        principal = vm.addr(PRINCIPAL_PK);
        delegate = vm.addr(DELEGATE_PK);
        recipient = vm.addr(0xC0C);

        token = new MockERC20();
        registry = new MandateRegistry(address(this));

        uint64 nonce = vm.getNonce(address(this));
        address predicted = vm.computeCreateAddress(address(this), nonce + 1);
        execRegistry = new MandateRegistry(predicted);
        executor = new MandateExecutor(execRegistry);
        assertEq(address(executor), predicted);

        token.mint(principal, 1e24);
        vm.prank(principal);
        token.approve(address(executor), type(uint256).max);

        vm.warp(1_700_000_000);
    }

    function test_revoke_emitsOnceAndBlocksConsume() public {
        SpendGrant memory m = _andMandate();
        bytes32 h = MandateHash.digest(block.chainid, address(registry), m);

        vm.prank(address(0xBEEF));
        registry.revoke(h);
        assertTrue(registry.revoked(address(0xBEEF), h));
        assertFalse(registry.revoked(principal, h));

        _consume(m, address(0), 1 ether, recipient);

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
        _consume(m, address(0), 1 ether, recipient);
    }

    function test_unauthorizedConsume() public {
        SpendGrant memory m = _andMandate();
        vm.prank(delegate);
        _expect(Reason.UNAUTHORIZED_EXECUTOR);
        registry.consume(m, _sig(m, address(registry)), address(0), 1 ether, recipient);
    }

    function test_timeBounds() public {
        SpendGrant memory m = _andMandate();
        uint256 validAfter = uint256(m.validAfter);
        uint256 validUntil = uint256(m.validUntil);

        vm.warp(validAfter - 1);
        _expect(Reason.NOT_YET_VALID);
        _consume(m, address(0), 1, recipient);

        vm.warp(validAfter);
        _consume(m, address(0), 1, recipient);

        vm.warp(validUntil);
        _expect(Reason.EXPIRED);
        _consume(m, address(0), 1, recipient);

        vm.warp(validUntil - 1);
        _consume(m, address(0), 1, recipient);
    }

    function test_wrongAssetAndRecipient() public {
        SpendGrant memory m = _andMandate();
        _expect(Reason.WRONG_ASSET);
        _consume(m, address(0x1234), 1, recipient);

        _expect(Reason.WRONG_RECIPIENT);
        _consume(m, address(0), 1, address(0x9999));

        m.recipientMode = 1;
        m.recipient = address(0);
        _consume(m, address(0), 1, address(0x9999));
    }

    function test_perCallWindowLifetime() public {
        SpendGrant memory m = _andMandate();
        m.assets[0] = AssetLimit(address(0), 10, 25, 30);

        _expect(Reason.OVER_TX_CAP);
        _consume(m, address(0), 0, recipient);
        _expect(Reason.OVER_TX_CAP);
        _consume(m, address(0), 11, recipient);

        _consume(m, address(0), 10, recipient);
        _consume(m, address(0), 10, recipient);
        _expect(Reason.OVER_WINDOW_CAP);
        _consume(m, address(0), 10, recipient);

        uint256 t = vm.getBlockTimestamp();
        vm.warp(t + m.windowSeconds);
        _consume(m, address(0), 10, recipient);
        _expect(Reason.OVER_CUMULATIVE_CAP);
        _consume(m, address(0), 10, recipient);

        (uint256 spent, uint256 calls) = registry.usage(_hash(m), address(0));
        assertEq(spent, 30);
        assertEq(calls, 3);
    }

    function test_andIndependent() public {
        SpendGrant memory m = _andMandate();
        _consume(m, address(0), 1 ether, recipient);
        _consume(m, address(token), 1e18, recipient);

        (uint256 nativeSpent,) = registry.usage(_hash(m), address(0));
        (uint256 tokenSpent,) = registry.usage(_hash(m), address(token));
        assertEq(nativeSpent, 1 ether);
        assertEq(tokenSpent, 1e18);

        (uint256 nativeRoll,) = registry.rollingUsage(_hash(m), address(0));
        (uint256 tokenRoll,) = registry.rollingUsage(_hash(m), address(token));
        assertEq(nativeRoll, 1 ether);
        assertEq(tokenRoll, 1e18);

        (uint256 lifePie, uint256 winPie) = registry.pieUsed(_hash(m));
        assertEq(lifePie, 0);
        assertEq(winPie, 0);
    }

    function test_orPieRoundUpExhaustion() public {
        SpendGrant memory m = _orMandate();
        m.assets[0] = AssetLimit(address(0), 1, 3, 3);
        m.assets[1] = AssetLimit(address(token), 1, 3, 3);

        _consume(m, address(0), 1, recipient);
        _consume(m, address(0), 1, recipient);
        _expect(Reason.OVER_WINDOW_CAP);
        _consume(m, address(0), 1, recipient);

        (uint256 lifePie, uint256 winPie) = registry.pieUsed(_hash(m));
        uint256 one = (uint256(1) * WAD + 3 - 1) / 3;
        assertEq(winPie, one * 2);
        assertEq(lifePie, one * 2);
        assertTrue(one * 3 > WAD);
    }

    function test_orLifetimePieAfterWindowExpiry() public {
        SpendGrant memory m = _orMandate();
        m.assets[0] = AssetLimit(address(0), 1, 3, 6);

        _consume(m, address(0), 1, recipient);
        _consume(m, address(0), 1, recipient);
        _expect(Reason.OVER_WINDOW_CAP);
        _consume(m, address(0), 1, recipient);

        uint256 t = vm.getBlockTimestamp();
        vm.warp(t + m.windowSeconds);
        _consume(m, address(0), 1, recipient);
        _consume(m, address(0), 1, recipient);

        t = vm.getBlockTimestamp();
        vm.warp(t + m.windowSeconds);
        _consume(m, address(0), 1, recipient);
        _expect(Reason.OVER_CUMULATIVE_CAP);
        _consume(m, address(0), 1, recipient);

        (uint256 spent,) = registry.usage(_hash(m), address(0));
        assertEq(spent, 5);
        (uint256 lifePie,) = registry.pieUsed(_hash(m));
        uint256 lifeOne = (uint256(1) * WAD + 6 - 1) / 6;
        assertEq(lifePie, lifeOne * 5);
        assertTrue(lifeOne * 6 > WAD);
    }

    function test_nativeAndErc20_executor() public {
        SpendGrant memory m = _andMandate();
        bytes memory sig = _sig(m, address(execRegistry));

        vm.deal(delegate, 2 ether);
        vm.prank(delegate);
        executor.spend{value: 1 ether}(m, sig, address(0), 1 ether, recipient);
        assertEq(recipient.balance, 1 ether);

        uint256 before = token.balanceOf(recipient);
        vm.prank(delegate);
        executor.spend(m, sig, address(token), 1e18, recipient);
        assertEq(token.balanceOf(recipient) - before, 1e18);
        assertEq(token.balanceOf(principal), 1e24 - 1e18);

        vm.prank(principal);
        vm.expectRevert(MandateExecutor.NotDelegate.selector);
        executor.spend(m, sig, address(token), 1e18, recipient);
    }

    function test_executor_mode1_callerRecipient() public {
        SpendGrant memory m = _andMandate();
        m.recipientMode = 1;
        m.recipient = address(0);
        bytes memory sig = _sig(m, address(execRegistry));
        address other = vm.addr(0xD0D);

        vm.deal(delegate, 1 ether);
        vm.prank(delegate);
        executor.spend{value: 1 ether}(m, sig, address(0), 1 ether, other);
        assertEq(other.balance, 1 ether);
    }

    function test_executor_revertsIfTransferFails() public {
        RejectEther sink = new RejectEther();
        SpendGrant memory m = _andMandate();
        m.recipient = address(sink);
        bytes memory sig = _sig(m, address(execRegistry));

        vm.deal(delegate, 1 ether);
        vm.prank(delegate);
        vm.expectRevert(MandateExecutor.TransferFailed.selector);
        executor.spend{value: 1 ether}(m, sig, address(0), 1 ether, address(sink));

        (uint256 spent,) = execRegistry.usage(MandateHash.digest(block.chainid, address(execRegistry), m), address(0));
        assertEq(spent, 0);
    }

    function test_executor_unexpectedMsgValue() public {
        SpendGrant memory m = _andMandate();
        bytes memory sig = _sig(m, address(execRegistry));

        vm.deal(delegate, 2 ether);
        vm.prank(delegate);
        vm.expectRevert(MandateExecutor.UnexpectedMsgValue.selector);
        executor.spend{value: 2 ether}(m, sig, address(0), 1 ether, recipient);

        vm.prank(delegate);
        vm.expectRevert(MandateExecutor.UnexpectedMsgValue.selector);
        executor.spend{value: 1 ether}(m, sig, address(token), 1e18, recipient);

        (uint256 nativeSpent,) =
            execRegistry.usage(MandateHash.digest(block.chainid, address(execRegistry), m), address(0));
        (uint256 tokenSpent,) =
            execRegistry.usage(MandateHash.digest(block.chainid, address(execRegistry), m), address(token));
        assertEq(nativeSpent, 0);
        assertEq(tokenSpent, 0);
    }

    function test_executor_erc20FalseReturnRollsBack() public {
        FalseERC20 bad = new FalseERC20();
        SpendGrant memory m = _andMandate();
        m.assets[1] = AssetLimit(address(bad), 1, 1, 1);
        bytes memory sig = _sig(m, address(execRegistry));

        vm.prank(delegate);
        vm.expectRevert(MandateExecutor.TransferFailed.selector);
        executor.spend(m, sig, address(bad), 1, recipient);

        (uint256 spent,) =
            execRegistry.usage(MandateHash.digest(block.chainid, address(execRegistry), m), address(bad));
        assertEq(spent, 0);
    }

    function test_windowExpiryAtExactAge() public {
        SpendGrant memory m = _andMandate();
        m.windowSeconds = 100;
        m.assets[0] = AssetLimit(address(0), 5, 5, 100);

        uint256 t0 = vm.getBlockTimestamp();
        _consume(m, address(0), 5, recipient);

        (uint256 rolling,) = registry.rollingUsage(_hash(m), address(0));
        assertEq(rolling, 5);

        vm.warp(t0 + 99);
        (rolling,) = registry.rollingUsage(_hash(m), address(0));
        assertEq(rolling, 5);
        _expect(Reason.OVER_WINDOW_CAP);
        _consume(m, address(0), 1, recipient);

        vm.warp(t0 + 100);
        (rolling,) = registry.rollingUsage(_hash(m), address(0));
        assertEq(rolling, 0);
        _consume(m, address(0), 5, recipient);
        (rolling,) = registry.rollingUsage(_hash(m), address(0));
        assertEq(rolling, 5);
    }

    function test_windowFullAt256LiveEvents() public {
        SpendGrant memory m = _andMandate();
        m.assets[0] = AssetLimit(address(0), 1, 10_000, 10_000);
        m.windowSeconds = 365 days;

        for (uint256 i = 0; i < 256; i++) {
            _consume(m, address(0), 1, recipient);
        }
        (, uint256 calls) = registry.rollingUsage(_hash(m), address(0));
        assertEq(calls, 256);

        _expect(Reason.WINDOW_FULL);
        _consume(m, address(0), 1, recipient);

        uint256 t = vm.getBlockTimestamp();
        vm.warp(t + m.windowSeconds);
        _consume(m, address(0), 1, recipient);
        (, calls) = registry.rollingUsage(_hash(m), address(0));
        assertEq(calls, 1);
    }

    function test_badSignatureAnd1271() public {
        SpendGrant memory m = _andMandate();
        bytes memory sig = _sig(m, address(registry));
        sig[0] = bytes1(uint8(sig[0]) ^ 1);
        _expect(Reason.BAD_SIGNATURE);
        registry.consume(m, sig, address(0), 1, recipient);

        Mock1271 wallet = new Mock1271();
        m.principal = address(wallet);
        bytes32 digest_ = MandateHash.digest(block.chainid, address(registry), m);
        _expect(Reason.BAD_SIGNATURE);
        registry.consume(m, hex"11", address(0), 1, recipient);

        wallet.setAllowed(digest_);
        registry.consume(m, hex"11", address(0), 1, recipient);
    }

    function test_invalidMandate() public {
        SpendGrant memory m = _andMandate();
        m.delegate = principal;
        _expect(Reason.INVALID_MANDATE);
        _consume(m, address(0), 1, recipient);

        m = _andMandate();
        m.recipientMode = 2;
        _expect(Reason.INVALID_MANDATE);
        _consume(m, address(0), 1, recipient);

        m = _andMandate();
        m.recipientMode = 1;
        _expect(Reason.INVALID_MANDATE);
        _consume(m, address(0), 1, recipient);

        m = _andMandate();
        m.windowSeconds = 0;
        _expect(Reason.INVALID_MANDATE);
        _consume(m, address(0), 1, recipient);

        m = _andMandate();
        m.assets[1] = AssetLimit(address(0x1234), 1, 1, 1);
        _expect(Reason.INVALID_MANDATE);
        _consume(m, address(0), 1, recipient);
    }

    function test_invalidMandate_remainingStructure() public {
        SpendGrant memory m = _andMandate();
        m.principal = address(0);
        _expect(Reason.INVALID_MANDATE);
        _consume(m, address(0), 1, recipient);

        m = _andMandate();
        m.delegate = address(0);
        _expect(Reason.INVALID_MANDATE);
        _consume(m, address(0), 1, recipient);

        m = _andMandate();
        m.recipient = principal;
        _expect(Reason.INVALID_MANDATE);
        _consume(m, address(0), 1, recipient);

        m = _andMandate();
        m.recipient = address(0);
        _expect(Reason.INVALID_MANDATE);
        _consume(m, address(0), 1, recipient);

        m = _andMandate();
        m.assetCombine = 2;
        _expect(Reason.INVALID_MANDATE);
        _consume(m, address(0), 1, recipient);

        m = _andMandate();
        m.validAfter = m.validUntil;
        _expect(Reason.INVALID_MANDATE);
        _consume(m, address(0), 1, recipient);

        m = _andMandate();
        m.assets = new AssetLimit[](0);
        _expect(Reason.INVALID_MANDATE);
        _consume(m, address(0), 1, recipient);

        m = _andMandate();
        m.assets[0].maxPerCall = 0;
        _expect(Reason.INVALID_MANDATE);
        _consume(m, address(0), 1, recipient);

        m = _andMandate();
        m.assets[0] = AssetLimit(address(0), 5, 4, 10);
        _expect(Reason.INVALID_MANDATE);
        _consume(m, address(0), 1, recipient);

        m = _andMandate();
        m.assets[0] = AssetLimit(address(0), 1, 10, 9);
        _expect(Reason.INVALID_MANDATE);
        _consume(m, address(0), 1, recipient);

        m = _andMandate();
        m.assets[0] = AssetLimit(address(token), 1, 1, 1);
        m.assets[1] = AssetLimit(address(0), 1, 1, 1);
        _expect(Reason.INVALID_MANDATE);
        _consume(m, address(token), 1, recipient);

        m = _andMandate();
        m.assets[1] = AssetLimit(address(0), 1, 1, 1);
        _expect(Reason.INVALID_MANDATE);
        _consume(m, address(0), 1, recipient);
    }

    function test_assets_oneToSixteen() public {
        SpendGrant memory m = _andMandate();
        AssetLimit[] memory one = new AssetLimit[](1);
        one[0] = AssetLimit(address(0), 1, 1, 1);
        m.assets = one;
        _consume(m, address(0), 1, recipient);

        m = _andMandate();
        AssetLimit[] memory max = new AssetLimit[](16);
        max[0] = AssetLimit(address(0), 1, 1, 1);
        for (uint256 i = 1; i < 16; i++) {
            address a = address(uint160(0x1000 + i));
            vm.etch(a, hex"00");
            max[i] = AssetLimit(a, 1, 1, 1);
        }
        m.assets = max;
        m.salt = 99;
        _consume(m, address(0), 1, recipient);

        AssetLimit[] memory tooMany = new AssetLimit[](17);
        tooMany[0] = AssetLimit(address(0), 1, 1, 1);
        for (uint256 i = 1; i < 17; i++) {
            address a = address(uint160(0x1000 + i));
            vm.etch(a, hex"00");
            tooMany[i] = AssetLimit(a, 1, 1, 1);
        }
        m.assets = tooMany;
        m.salt = 100;
        _expect(Reason.INVALID_MANDATE);
        _consume(m, address(0), 1, recipient);
    }

    function test_orPie_mixedAssetsNumericExample() public {
        // ERC: 50 of A (maxPerWindow 100) then 100 of B (maxPerWindow 200) fills the pie.
        SpendGrant memory m = _orMandate();
        m.assets[0] = AssetLimit(address(0), 50, 100, 1_000);
        m.assets[1] = AssetLimit(address(token), 100, 200, 1_000);

        _consume(m, address(0), 50, recipient);
        _consume(m, address(token), 100, recipient);

        (uint256 lifePie, uint256 winPie) = registry.pieUsed(_hash(m));
        assertEq(winPie, WAD);
        assertEq(lifePie, (50 * WAD) / 1_000 + (100 * WAD) / 1_000);

        _expect(Reason.OVER_WINDOW_CAP);
        _consume(m, address(0), 1, recipient);
        _expect(Reason.OVER_WINDOW_CAP);
        _consume(m, address(token), 1, recipient);
    }

    function test_signature_rejectsHighSBadVAndLength() public {
        SpendGrant memory m = _andMandate();
        bytes memory sig = _sig(m, address(registry));

        bytes32 highS = bytes32(uint256(0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) + 1);
        assembly {
            mstore(add(sig, 64), highS)
        }
        _expect(Reason.BAD_SIGNATURE);
        registry.consume(m, sig, address(0), 1, recipient);

        sig = _sig(m, address(registry));
        sig[64] = bytes1(uint8(26));
        _expect(Reason.BAD_SIGNATURE);
        registry.consume(m, sig, address(0), 1, recipient);

        _expect(Reason.BAD_SIGNATURE);
        registry.consume(m, hex"11", address(0), 1, recipient);
    }

    function test_1271_shortReturnRevertAndNoEcdsaFallback() public {
        SpendGrant memory m = _andMandate();

        Short1271 shortWallet = new Short1271();
        m.principal = address(shortWallet);
        _expect(Reason.BAD_SIGNATURE);
        registry.consume(m, hex"11", address(0), 1, recipient);

        Reverting1271 reverting = new Reverting1271();
        m.principal = address(reverting);
        _expect(Reason.BAD_SIGNATURE);
        registry.consume(m, hex"11", address(0), 1, recipient);

        // Code-bearing principal must not fall back to ECDSA even with a 65-byte sig.
        m.principal = address(shortWallet);
        bytes memory eoaSig = _sig(m, address(registry));
        _expect(Reason.BAD_SIGNATURE);
        registry.consume(m, eoaSig, address(0), 1, recipient);
    }

    function test_window_liveIfTimestampGoesBackwards() public {
        SpendGrant memory m = _andMandate();
        m.windowSeconds = 100;
        m.assets[0] = AssetLimit(address(0), 5, 5, 100);

        uint256 t0 = vm.getBlockTimestamp() + 50;
        vm.warp(t0);
        _consume(m, address(0), 5, recipient);

        vm.warp(t0 - 1);
        (uint256 rolling,) = registry.rollingUsage(_hash(m), address(0));
        assertEq(rolling, 5);
        _expect(Reason.OVER_WINDOW_CAP);
        _consume(m, address(0), 1, recipient);
    }

    function test_consume_emitsMandateConsumed() public {
        SpendGrant memory m = _andMandate();
        bytes32 h = _hash(m);
        vm.expectEmit(true, true, true, true);
        emit GrantConsumed(h, address(0), 1 ether, recipient);
        _consume(m, address(0), 1 ether, recipient);
    }

    function testFuzz_consumeNeverExceedsCaps(uint256 amount, uint256 warpBy, uint8 nCalls) public {
        SpendGrant memory m = _andMandate();
        m.assets[0] = AssetLimit(address(0), 100, 1_000, 5_000);
        nCalls = uint8(bound(nCalls, 1, 40));
        bytes32 h = _hash(m);

        for (uint256 i = 0; i < nCalls; i++) {
            uint256 t = vm.getBlockTimestamp();
            vm.warp(t + bound(warpBy, 0, uint256(m.windowSeconds) * 2));
            if (vm.getBlockTimestamp() >= m.validUntil) break;

            uint256 amt = bound(amount, 1, m.assets[0].maxPerCall);
            (uint256 spent,) = registry.usage(h, address(0));
            (uint256 rolling,) = registry.rollingUsage(h, address(0));
            (, uint256 liveCalls) = registry.rollingUsage(h, address(0));

            if (liveCalls >= 256) {
                _expect(Reason.WINDOW_FULL);
                _consume(m, address(0), amt, recipient);
                break;
            }
            if (rolling + amt > m.assets[0].maxPerWindow) {
                _expect(Reason.OVER_WINDOW_CAP);
                _consume(m, address(0), amt, recipient);
                continue;
            }
            if (spent + amt > m.assets[0].maxTotal) {
                _expect(Reason.OVER_CUMULATIVE_CAP);
                _consume(m, address(0), amt, recipient);
                break;
            }
            _consume(m, address(0), amt, recipient);
        }

        (uint256 endSpent,) = registry.usage(h, address(0));
        (uint256 endRolling,) = registry.rollingUsage(h, address(0));
        assertLe(endSpent, m.assets[0].maxTotal);
        assertLe(endRolling, m.assets[0].maxPerWindow);
    }

    function testFuzz_orPieNeverExceedsWad(uint256 amount, uint256 warpBy, uint8 nCalls) public {
        SpendGrant memory m = _orMandate();
        m.assets[0] = AssetLimit(address(0), 50, 200, 800);
        nCalls = uint8(bound(nCalls, 1, 40));
        bytes32 h = _hash(m);

        for (uint256 i = 0; i < nCalls; i++) {
            uint256 t = vm.getBlockTimestamp();
            vm.warp(t + bound(warpBy, 0, uint256(m.windowSeconds) * 2));
            if (vm.getBlockTimestamp() >= m.validUntil) break;

            uint256 amt = bound(amount, 1, m.assets[0].maxPerCall);
            (uint256 lifePie, uint256 winPie) = registry.pieUsed(h);
            uint256 wAdd = (amt * WAD + m.assets[0].maxPerWindow - 1) / m.assets[0].maxPerWindow;
            uint256 tAdd = (amt * WAD + m.assets[0].maxTotal - 1) / m.assets[0].maxTotal;
            (, uint256 liveCalls) = registry.rollingUsage(h, address(0));
            if (liveCalls >= 256) break;
            if (winPie + wAdd > WAD) {
                _expect(Reason.OVER_WINDOW_CAP);
                _consume(m, address(0), amt, recipient);
                continue;
            }
            if (lifePie + tAdd > WAD) {
                _expect(Reason.OVER_CUMULATIVE_CAP);
                _consume(m, address(0), amt, recipient);
                break;
            }
            _consume(m, address(0), amt, recipient);
        }

        (uint256 endLife, uint256 endWin) = registry.pieUsed(h);
        assertLe(endLife, WAD);
        assertLe(endWin, WAD);
        (uint256 spent,) = registry.usage(h, address(0));
        assertLe(spent, m.assets[0].maxTotal);
        (uint256 rolling,) = registry.rollingUsage(h, address(0));
        assertLe(rolling, m.assets[0].maxPerWindow);
    }

    function _andMandate() internal view returns (SpendGrant memory m) {
        m.principal = principal;
        m.delegate = delegate;
        m.recipientMode = 0;
        m.recipient = recipient;
        m.assetCombine = 0;
        m.windowSeconds = 3600;
        m.validAfter = 1_700_000_000;
        m.validUntil = 1_800_000_000;
        m.salt = 1;
        m.renderingHash = bytes32(uint256(1));
        m.assets = new AssetLimit[](2);
        m.assets[0] = AssetLimit(address(0), 1 ether, 5 ether, 10 ether);
        m.assets[1] = AssetLimit(address(token), 1e18, 5e18, 10e18);
    }

    function _orMandate() internal view returns (SpendGrant memory m) {
        m = _andMandate();
        m.assetCombine = 1;
        m.salt = 2;
    }

    function _hash(SpendGrant memory m) internal view returns (bytes32) {
        return MandateHash.digest(block.chainid, address(registry), m);
    }

    function _sig(SpendGrant memory m, address reg) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRINCIPAL_PK, MandateHash.digest(block.chainid, reg, m));
        return abi.encodePacked(r, s, v);
    }

    function _consume(SpendGrant memory m, address asset, uint256 amount, address to) internal {
        registry.consume(m, _sig(m, address(registry)), asset, amount, to);
    }

    function _expect(Reason r) internal {
        vm.expectRevert(abi.encodeWithSelector(MandateError.selector, r));
    }
}
