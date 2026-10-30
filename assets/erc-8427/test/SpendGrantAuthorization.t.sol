// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AssetLimit, IERC1271, Reason, SpendGrant} from "../src/SpendGrantTypes.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";
import {SpendGrantExecutor} from "../src/SpendGrantExecutor.sol";
import {SpendGrantAuthorizationExecutor} from "../src/SpendGrantAuthorizationExecutor.sol";
import {SpendGrantSignature} from "../src/SpendGrantSignature.sol";
import {MockERC20} from "./MockERC20.sol";

/// @dev A contract delegate whose ERC-1271 accepts one digest at a time.
contract Allowlist1271 {
    bytes32 public allowed;

    function allow(bytes32 digest) external {
        allowed = digest;
    }

    function isValidSignature(bytes32 digest, bytes calldata) external view returns (bytes4) {
        return digest == allowed ? IERC1271.isValidSignature.selector : bytes4(0xffffffff);
    }
}

/// @dev ERC-1271 code that rejects everything; the target of a 7702 designator in the tests.
contract Rejecting1271 {
    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return 0xffffffff;
    }
}

/// @dev ERC-1271 code that reverts with exactly the left-aligned magic value as its revert data.
contract RevertMagic1271 {
    fallback() external {
        assembly {
            mstore(0, 0x1626ba7e00000000000000000000000000000000000000000000000000000000)
            revert(0, 32)
        }
    }
}

/// @dev ERC-1271 code that returns 64 bytes: the left-aligned magic value, then a zero word.
contract LongMagic1271 {
    fallback() external {
        assembly {
            mstore(0, 0x1626ba7e00000000000000000000000000000000000000000000000000000000)
            mstore(32, 0)
            return(0, 64)
        }
    }
}

/// @dev ERC-1271 code that returns the magic value as four raw bytes.
contract RawMagic1271 {
    fallback() external {
        assembly {
            mstore(0, 0x1626ba7e00000000000000000000000000000000000000000000000000000000)
            return(0, 4)
        }
    }
}

/// @dev Lets a test apply the library's recovery rule to calldata.
contract SignatureHarness {
    function recover(bytes32 digest, bytes calldata sig) external pure returns (address) {
        return SpendGrantSignature.recover(digest, sig);
    }
}

/// @dev A token whose transferFrom replays the authorization that is paying out through it.
contract ReenteringERC20 is MockERC20 {
    SpendGrantAuthorizationExecutor internal executor;
    bytes internal replay;

    function arm(SpendGrantAuthorizationExecutor executor_, bytes calldata replay_) external {
        executor = executor_;
        replay = replay_;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        if (replay.length != 0) {
            bytes memory call = replay;
            replay = "";
            (bool ok, bytes memory ret) = address(executor).call(call);
            if (!ok) {
                assembly {
                    revert(add(ret, 32), mload(ret))
                }
            }
        }
        return true;
    }
}

/// @dev Grants are registered by the principal and spent by id; the delegate signs a `SpendAuthorization` naming
/// the id, and a relayer submits it.
contract SpendGrantAuthorizationTest is Test {
    bytes4 internal constant SPEND_GRANT_ERROR = bytes4(keccak256("SpendGrantError(uint8)"));
    uint256 internal constant DELEGATE_PK = 0xB0B;
    uint256 internal constant STRANGER_PK = 0xBAD;

    SpendGrantRegistry internal registry;
    SpendGrantAuthorizationExecutor internal executor;
    MockERC20 internal token;

    address internal principal;
    address internal delegate;
    address internal recipient;
    address internal relayer;

    event AuthorizationUsed(address indexed authorizer, uint256 indexed nonce);

    function setUp() public {
        principal = makeAddr("principal");
        delegate = vm.addr(DELEGATE_PK);
        recipient = vm.addr(0xC0C);
        relayer = vm.addr(0x5E1A);

        token = new MockERC20();
        uint64 nonce = vm.getNonce(address(this));
        registry = new SpendGrantRegistry(vm.computeCreateAddress(address(this), nonce + 1));
        executor = new SpendGrantAuthorizationExecutor(registry);

        token.mint(principal, 1e24);
        vm.prank(principal);
        token.approve(address(executor), type(uint256).max);

        vm.warp(1_700_000_000);
    }

    // ---------------------------------------------------------------- happy path and replay

    function test_relayerSubmitsDelegateAuthorization() public {
        bytes32 id = _register(_grant(delegate));
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory auth = _authorize(DELEGATE_PK, id, 1e18, recipient, 7, deadline);

        vm.expectEmit(true, true, false, false, address(executor));
        emit AuthorizationUsed(delegate, 7);
        vm.prank(relayer);
        executor.spendWithAuthorization(id, address(token), 1e18, recipient, 7, deadline, auth);

        assertEq(token.balanceOf(recipient), 1e18);
        (uint256 spent, uint256 calls) = registry.usage(id, address(token));
        assertEq(spent, 1e18);
        assertEq(calls, 1);
        assertTrue(executor.nonceUsed(delegate, 7));
    }

    function test_authorizationSucceedsAtMostOnce() public {
        bytes32 id = _register(_grant(delegate));
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory auth = _authorize(DELEGATE_PK, id, 1e18, recipient, 7, deadline);
        bytes memory again = _spendCall(id, address(token), 1e18, 7, deadline, auth);

        vm.prank(relayer);
        executor.spendWithAuthorization(id, address(token), 1e18, recipient, 7, deadline, auth);

        // Same bytes, any submitter, any time: the nonce is gone.
        vm.prank(vm.addr(0x0DD));
        (bool ok, bytes memory ret) = address(executor).call(again);
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(SpendGrantAuthorizationExecutor.NonceAlreadyUsed.selector));
        assertEq(token.balanceOf(recipient), 1e18);
    }

    function test_replayFromInsideTheTransferFails() public {
        ReenteringERC20 hooked = new ReenteringERC20();
        hooked.mint(principal, 1e24);
        vm.prank(principal);
        hooked.approve(address(executor), type(uint256).max);

        SpendGrant memory m = _grant(delegate);
        m.assets[0] = AssetLimit(address(hooked), 1e18, 10e18, 100e18);
        bytes32 id = _register(m);
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory auth = _authorizeFor(DELEGATE_PK, id, address(hooked), 1e18, recipient, 7, deadline);
        bytes memory call = _spendCall(id, address(hooked), 1e18, 7, deadline, auth);
        hooked.arm(executor, call);

        // The nonce was recorded before the movement, so the hook's replay fails and the transfer with it.
        vm.prank(relayer);
        (bool ok, bytes memory ret) = address(executor).call(call);
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(SpendGrantExecutor.TransferFailed.selector));
        assertEq(hooked.balanceOf(recipient), 0);
        (uint256 spent,) = registry.usage(id, address(hooked));
        assertEq(spent, 0);
    }

    // ---------------------------------------------------------------- what the signature binds

    function test_strangerSignatureIsNotTheDelegate() public {
        bytes32 id = _register(_grant(delegate));
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory auth = _authorize(STRANGER_PK, id, 1e18, recipient, 1, deadline);
        bytes memory call = _spendCall(id, address(token), 1e18, 1, deadline, auth);

        // The recovered signer is passed as authorizer and the registry rejects it; nothing is recorded.
        vm.prank(relayer);
        (bool ok, bytes memory ret) = address(executor).call(call);
        assertFalse(ok);
        assertEq(ret, _err(13)); // UNAUTHORIZED_DELEGATE
        assertFalse(executor.nonceUsed(vm.addr(STRANGER_PK), 1));
    }

    function test_tamperedAmountRecoversSomeoneElse() public {
        bytes32 id = _register(_grant(delegate));
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory auth = _authorize(DELEGATE_PK, id, 1e17, recipient, 1, deadline);

        vm.prank(relayer);
        vm.expectRevert(_err(13)); // UNAUTHORIZED_DELEGATE
        executor.spendWithAuthorization(id, address(token), 1e18, recipient, 1, deadline, auth);
    }

    /// Two grants with the same principal and delegate: the digest names the grant id, so an authorization signed
    /// for A recovers someone else when submitted under B and spends nothing; the same bytes then spend A.
    function test_authorizationIsBoundToTheGrantId() public {
        SpendGrant memory a = _grant(delegate);
        SpendGrant memory b = _grant(delegate);
        b.salt = 2;
        bytes32 idA = _register(a);
        bytes32 idB = _register(b);
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory authForA = _authorize(DELEGATE_PK, idA, 1e18, recipient, 1, deadline);
        bytes memory underB = _spendCall(idB, address(token), 1e18, 1, deadline, authForA);

        vm.prank(relayer);
        (bool ok, bytes memory ret) = address(executor).call(underB);
        assertFalse(ok);
        assertEq(ret, _err(13)); // UNAUTHORIZED_DELEGATE
        assertFalse(executor.nonceUsed(delegate, 1));
        (uint256 spentA,) = registry.usage(idA, address(token));
        (uint256 spentB,) = registry.usage(idB, address(token));
        assertEq(spentA, 0);
        assertEq(spentB, 0);

        vm.prank(relayer);
        executor.spendWithAuthorization(idA, address(token), 1e18, recipient, 1, deadline, authForA);
        (spentA,) = registry.usage(idA, address(token));
        (spentB,) = registry.usage(idB, address(token));
        assertEq(spentA, 1e18);
        assertEq(spentB, 0);
        assertEq(token.balanceOf(recipient), 1e18);
    }

    function test_deadlineIsExclusive() public {
        bytes32 id = _register(_grant(delegate));
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory auth = _authorize(DELEGATE_PK, id, 1e18, recipient, 1, deadline);

        // One second before the deadline it is accepted.
        vm.warp(deadline - 1);
        vm.prank(relayer);
        executor.spendWithAuthorization(id, address(token), 1e18, recipient, 1, deadline, auth);

        // At the deadline it is rejected, and that check comes before the nonce is even looked at.
        vm.warp(deadline);
        vm.prank(relayer);
        vm.expectRevert(SpendGrantAuthorizationExecutor.AuthorizationExpired.selector);
        executor.spendWithAuthorization(id, address(token), 1e18, recipient, 1, deadline, auth);
    }

    function test_malformedSignatureIsRejectedOutright() public {
        bytes32 id = _register(_grant(delegate));
        uint256 deadline = vm.getBlockTimestamp() + 600;

        vm.prank(relayer);
        vm.expectRevert(SpendGrantAuthorizationExecutor.BadAuthorization.selector);
        executor.spendWithAuthorization(id, address(token), 1e18, recipient, 1, deadline, hex"1234");
    }

    function test_delegateCancelsAnUnusedNonce() public {
        bytes32 id = _register(_grant(delegate));
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory auth = _authorize(DELEGATE_PK, id, 1e18, recipient, 9, deadline);

        vm.prank(delegate);
        executor.cancelNonce(9);

        vm.prank(relayer);
        vm.expectRevert(SpendGrantAuthorizationExecutor.NonceAlreadyUsed.selector);
        executor.spendWithAuthorization(id, address(token), 1e18, recipient, 9, deadline, auth);
    }

    // ---------------------------------------------------------------- an authorization names the id, not a version

    /// The principal raises the per-call cap after the delegate signed: the authorization that failed OVER_TX_CAP
    /// succeeds unchanged, because the terms in force when it is submitted decide and it fits them.
    function test_update_raisedCapLetsAnEarlierAuthorizationSucceed() public {
        SpendGrant memory m = _grant(delegate);
        bytes32 id = _register(m);
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory auth = _authorize(DELEGATE_PK, id, 2e18, recipient, 1, deadline);
        bytes memory call = _spendCall(id, address(token), 2e18, 1, deadline, auth);

        vm.prank(relayer);
        (bool ok, bytes memory ret) = address(executor).call(call);
        assertFalse(ok);
        assertEq(ret, _err(8)); // OVER_TX_CAP: 2e18 is over the per-call cap of 1e18
        assertFalse(executor.nonceUsed(delegate, 1));

        m.assets[0].maxPerCall = 2e18;
        vm.prank(principal);
        registry.update(id, 1, m);

        vm.prank(relayer);
        executor.spendWithAuthorization(id, address(token), 2e18, recipient, 1, deadline, auth);
        assertEq(token.balanceOf(recipient), 2e18);
        (uint256 spent, uint256 calls) = registry.usage(id, address(token));
        assertEq(spent, 2e18);
        assertEq(calls, 1);
        assertTrue(executor.nonceUsed(delegate, 1));
        (, uint256 version,,,) = registry.getGrant(id);
        assertEq(version, 2);
    }

    /// The principal removes an asset after the delegate signed for it: the authorization fails WRONG_ASSET. That
    /// step comes after the delegate check, so the signature itself still authenticated the delegate.
    function test_update_removedAssetRejectsAnEarlierAuthorization() public {
        MockERC20 other = new MockERC20();
        other.mint(principal, 1e24);
        vm.prank(principal);
        other.approve(address(executor), type(uint256).max);

        SpendGrant memory m = _grant(delegate);
        AssetLimit memory kept = AssetLimit(address(token), 1e18, 10e18, 100e18);
        AssetLimit memory removed = AssetLimit(address(other), 1e18, 10e18, 100e18);
        m.assets = new AssetLimit[](2);
        if (address(token) < address(other)) {
            (m.assets[0], m.assets[1]) = (kept, removed);
        } else {
            (m.assets[0], m.assets[1]) = (removed, kept);
        }
        bytes32 id = _register(m);
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory auth = _authorizeFor(DELEGATE_PK, id, address(other), 1e18, recipient, 1, deadline);

        // Before the update the registry accepts exactly this spend.
        (bool okBefore, Reason before) = registry.check(id, delegate, address(other), 1e18, recipient);
        assertTrue(okBefore);
        assertEq(uint8(before), 0);

        m.assets = new AssetLimit[](1);
        m.assets[0] = kept;
        vm.prank(principal);
        registry.update(id, 1, m);

        vm.prank(relayer);
        vm.expectRevert(_err(6)); // WRONG_ASSET
        executor.spendWithAuthorization(id, address(other), 1e18, recipient, 1, deadline, auth);
    }

    // ---------------------------------------------------------------- delegates with code

    function test_erc1271Delegate_isTheAuthorizer() public {
        Allowlist1271 wallet = new Allowlist1271();
        bytes32 id = _register(_grant(address(wallet)));
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes32 digest = executor.authorizationDigest(id, address(token), 1e18, recipient, 1, deadline);
        bytes memory call = _spendCall(id, address(token), 1e18, 1, deadline, hex"00");

        vm.prank(relayer);
        (bool ok, bytes memory ret) = address(executor).call(call);
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(SpendGrantAuthorizationExecutor.BadAuthorization.selector));

        wallet.allow(digest);
        vm.prank(relayer);
        executor.spendWithAuthorization(id, address(token), 1e18, recipient, 1, deadline, hex"00");
        assertTrue(executor.nonceUsed(address(wallet), 1));
        assertEq(token.balanceOf(recipient), 1e18);
    }

    function test_7702Delegate_ownKeyFirstThenErc1271() public {
        Rejecting1271 impl = new Rejecting1271();
        vm.etch(delegate, abi.encodePacked(hex"ef0100", address(impl)));
        bytes32 id = _register(_grant(delegate));
        uint256 deadline = vm.getBlockTimestamp() + 600;

        // The account's own key authorizes even though the delegated code rejects everything.
        bytes memory auth = _authorize(DELEGATE_PK, id, 1e18, recipient, 1, deadline);
        vm.prank(relayer);
        executor.spendWithAuthorization(id, address(token), 1e18, recipient, 1, deadline, auth);
        assertEq(token.balanceOf(recipient), 1e18);

        // Another key is not the account, so validation falls through to the rejecting ERC-1271.
        bytes memory other = _authorize(STRANGER_PK, id, 1e18, recipient, 2, deadline);
        vm.prank(relayer);
        vm.expectRevert(SpendGrantAuthorizationExecutor.BadAuthorization.selector);
        executor.spendWithAuthorization(id, address(token), 1e18, recipient, 2, deadline, other);
    }

    function test_7702Delegate_delegatedCodeDecidesWhenItsKeyDidNotSign() public {
        // Rule (b): the account's own key is silent, so the delegated code's ERC-1271 is asked.
        Allowlist1271 impl = new Allowlist1271();
        vm.etch(delegate, abi.encodePacked(hex"ef0100", address(impl)));
        bytes32 id = _register(_grant(delegate));
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes32 digest = executor.authorizationDigest(id, address(token), 1e18, recipient, 1, deadline);

        // The allowlist lives in the account's own storage, where the designated code runs.
        Allowlist1271(delegate).allow(digest);
        vm.prank(relayer);
        executor.spendWithAuthorization(id, address(token), 1e18, recipient, 1, deadline, hex"00");
        assertEq(token.balanceOf(recipient), 1e18);
        assertTrue(executor.nonceUsed(delegate, 1));
    }

    /// The delegate's ERC-1271 answer must be exactly 32 bytes equal to the left-aligned magic value. A validator that
    /// reverts with that word, returns 64 bytes starting with it, or returns its raw four bytes authenticates nobody:
    /// BadAuthorization, with nothing spent and the nonce unused.
    function test_erc1271Delegate_answerMustBeExactlyTheMagicWord() public {
        address[3] memory validators =
            [address(new RevertMagic1271()), address(new LongMagic1271()), address(new RawMagic1271())];
        uint256 deadline = vm.getBlockTimestamp() + 600;
        for (uint256 i = 0; i < validators.length; i++) {
            bytes32 id = _register(_grant(validators[i]));
            bytes memory call = _spendCall(id, address(token), 1e18, 1, deadline, hex"00");
            vm.prank(relayer);
            (bool ok, bytes memory ret) = address(executor).call(call);
            assertFalse(ok);
            assertEq(ret, abi.encodeWithSelector(SpendGrantAuthorizationExecutor.BadAuthorization.selector));
            assertFalse(executor.nonceUsed(validators[i], 1));
            (uint256 spent,) = registry.usage(id, address(token));
            assertEq(spent, 0);
        }
        assertEq(token.balanceOf(recipient), 0);
    }

    /// The authorization is exactly 65 bytes `r || s || v`: the delegate's valid signature with one trailing byte is
    /// BadAuthorization and spends nothing, and the same 65 bytes alone then spend.
    function test_signatureWithATrailingByteIsBadAuthorization() public {
        bytes32 id = _register(_grant(delegate));
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory auth = _authorize(DELEGATE_PK, id, 1e18, recipient, 1, deadline);
        bytes memory padded = _spendCall(id, address(token), 1e18, 1, deadline, abi.encodePacked(auth, uint8(0)));

        vm.prank(relayer);
        (bool ok, bytes memory ret) = address(executor).call(padded);
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(SpendGrantAuthorizationExecutor.BadAuthorization.selector));
        assertFalse(executor.nonceUsed(delegate, 1));
        assertEq(token.balanceOf(recipient), 0);

        vm.prank(relayer);
        executor.spendWithAuthorization(id, address(token), 1e18, recipient, 1, deadline, auth);
        assertEq(token.balanceOf(recipient), 1e18);
    }

    /// When authentication produces nothing, the executor reverts rather than pass a placeholder. A grant may name
    /// address(1), which no key controls, as its delegate; a signature whose v is the raw recovery id (0 or 1) instead
    /// of 27 or 28 recovers nobody, so it is BadAuthorization, not a spend authorized by address(1).
    function test_badVIsBadAuthorizationForADelegateAtAddressOne() public {
        bytes32 id = _register(_grant(address(1)));
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes32 digest = executor.authorizationDigest(id, address(token), 1e18, recipient, 1, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATE_PK, digest);
        bytes memory badV = abi.encodePacked(r, s, v - 27);

        vm.prank(relayer);
        vm.expectRevert(SpendGrantAuthorizationExecutor.BadAuthorization.selector);
        executor.spendWithAuthorization(id, address(token), 1e18, recipient, 1, deadline, badV);
    }

    function test_malleatedTwinIsNotAnAuthorization() public {
        bytes32 id = _register(_grant(delegate));
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes32 digest = executor.authorizationDigest(id, address(token), 1e18, recipient, 1, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATE_PK, digest);
        bytes32 twinS = bytes32(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - uint256(s));
        uint8 twinV = v == 27 ? 28 : 27;
        assertEq(ecrecover(digest, twinV, r, twinS), delegate);
        bytes memory twin = abi.encodePacked(r, twinS, twinV);

        vm.prank(relayer);
        vm.expectRevert(SpendGrantAuthorizationExecutor.BadAuthorization.selector);
        executor.spendWithAuthorization(id, address(token), 1e18, recipient, 1, deadline, twin);
    }

    function test_usedNonce_isRejectedBeforeTheDelegateIsAsked() public {
        Allowlist1271 wallet = new Allowlist1271();
        bytes32 id = _register(_grant(address(wallet)));
        uint256 deadline = vm.getBlockTimestamp() + 600;
        wallet.allow(executor.authorizationDigest(id, address(token), 1e18, recipient, 1, deadline));
        vm.prank(relayer);
        executor.spendWithAuthorization(id, address(token), 1e18, recipient, 1, deadline, hex"00");

        // A submitter that lost the race pays for a storage read, not for the delegate's validation.
        vm.expectCall(address(wallet), abi.encodeWithSelector(IERC1271.isValidSignature.selector), 0);
        vm.prank(relayer);
        vm.expectRevert(SpendGrantAuthorizationExecutor.NonceAlreadyUsed.selector);
        executor.spendWithAuthorization(id, address(token), 1e18, recipient, 1, deadline, hex"00");
    }

    function test_cancelNonce_rejectsANonceThatRanOrWasCancelled() public {
        bytes32 id = _register(_grant(delegate));
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory auth = _authorize(DELEGATE_PK, id, 1e18, recipient, 7, deadline);
        bytes memory cancelRan = abi.encodeCall(SpendGrantAuthorizationExecutor.cancelNonce, (7));
        vm.prank(relayer);
        executor.spendWithAuthorization(id, address(token), 1e18, recipient, 7, deadline, auth);

        // A cancel that succeeds proves the authorization never ran; this one ran, so it fails.
        vm.prank(delegate);
        (bool ok, bytes memory ret) = address(executor).call(cancelRan);
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(SpendGrantAuthorizationExecutor.NonceAlreadyUsed.selector));

        vm.prank(delegate);
        executor.cancelNonce(8);
        vm.prank(delegate);
        vm.expectRevert(SpendGrantAuthorizationExecutor.NonceAlreadyUsed.selector);
        executor.cancelNonce(8);
    }

    function test_goldenAuthorizationVector() public {
        string memory json = vm.readFile("assets/erc-8427/vectors/authorization-v1.json");
        assertTrue(vm.keyExistsJson(json, ".vectors[0]"));
        assertFalse(vm.keyExistsJson(json, ".vectors[1]"));
        string memory p = ".vectors[0]";

        // The encodeType in the file is what the contract hashes, and both give the pinned type hash.
        assertEq(keccak256(bytes(vm.parseJsonString(json, ".encodeType"))), executor.authorizationTypehash());
        assertEq(executor.authorizationTypehash(), 0xbdf12719d33aac7ffdc784c8ba01d876726bb83eb404f021efe2df09f1077b4d);

        uint256 chainId = vm.parseJsonUint(json, string.concat(p, ".chainId"));
        address vectorExecutor = vm.parseJsonAddress(json, string.concat(p, ".executor"));
        bytes32 grantId = vm.parseJsonBytes32(json, string.concat(p, ".authorization.grantId"));
        address asset = vm.parseJsonAddress(json, string.concat(p, ".authorization.asset"));
        uint256 amount = vm.parseJsonUint(json, string.concat(p, ".authorization.amount"));
        address to = vm.parseJsonAddress(json, string.concat(p, ".authorization.recipient"));
        uint256 nonce = vm.parseJsonUint(json, string.concat(p, ".authorization.nonce"));
        uint256 deadline = vm.parseJsonUint(json, string.concat(p, ".authorization.deadline"));
        bytes32 domain = vm.parseJsonBytes32(json, string.concat(p, ".domainSeparator"));
        bytes32 structHash = vm.parseJsonBytes32(json, string.concat(p, ".structHash"));
        bytes32 digest = vm.parseJsonBytes32(json, string.concat(p, ".digest"));
        bytes memory signature = vm.parseJsonBytes(json, string.concat(p, ".signature"));
        address signer = vm.parseJsonAddress(json, string.concat(p, ".signer"));
        assertEq(digest, 0xeb253f5ace2110b314f67f617b91e0e58485cc86acba49196162c34688c18251);

        // Rebuilt from the ERC's words alone, with the names the file states.
        bytes32 expectedDomain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(vm.parseJsonString(json, ".domain.name"))),
                keccak256(bytes(vm.parseJsonString(json, ".domain.version"))),
                chainId,
                vectorExecutor
            )
        );
        assertEq(expectedDomain, domain);
        assertEq(
            keccak256(abi.encode(executor.authorizationTypehash(), grantId, asset, amount, to, nonce, deadline)),
            structHash
        );
        assertEq(keccak256(abi.encodePacked(hex"1901", domain, structHash)), digest);

        // The deployed code, placed at the vector's address on the vector's chain, reproduces the digest.
        vm.chainId(chainId);
        vm.etch(vectorExecutor, address(executor).code);
        assertEq(
            SpendGrantAuthorizationExecutor(vectorExecutor).authorizationDigest(
                grantId, asset, amount, to, nonce, deadline
            ),
            digest
        );

        // And the signature a wallet produced recovers the signer under the Signatures rules.
        SignatureHarness harness = new SignatureHarness();
        assertEq(signature.length, 65);
        assertEq(harness.recover(digest, signature), signer);
    }

    // ---------------------------------------------------------------- the direct path still exists

    function test_directSpendStillWorks() public {
        bytes32 id = _register(_grant(delegate));
        vm.prank(delegate);
        executor.spend(id, address(token), 1e18, recipient);
        assertEq(token.balanceOf(recipient), 1e18);
    }

    // ---------------------------------------------------------------- helpers

    function _grant(address delegate_) internal view returns (SpendGrant memory m) {
        m.principal = principal;
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

    /// The principal registers the terms; the id is all the delegate needs.
    function _register(SpendGrant memory m) internal returns (bytes32 id) {
        vm.prank(m.principal);
        id = registry.register(m);
    }

    function _authorize(uint256 pk, bytes32 grantId, uint256 amount, address to, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        return _authorizeFor(pk, grantId, address(token), amount, to, nonce, deadline);
    }

    function _authorizeFor(
        uint256 pk,
        bytes32 grantId,
        address asset,
        uint256 amount,
        address to,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 digest = executor.authorizationDigest(grantId, asset, amount, to, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    /// Calldata for `spendWithAuthorization` to `recipient`, for tests that check state after a rejected call.
    function _spendCall(
        bytes32 grantId,
        address asset,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes memory auth
    ) internal view returns (bytes memory) {
        return abi.encodeCall(
            SpendGrantAuthorizationExecutor.spendWithAuthorization,
            (grantId, asset, amount, recipient, nonce, deadline, auth)
        );
    }

    /// `SpendGrantError(uint8)` carrying the literal reason number.
    function _err(uint8 reason) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(SPEND_GRANT_ERROR, reason);
    }
}
