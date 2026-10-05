// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AssetLimit, IERC1271, SpendGrant, SpendGrantError, Reason} from "../src/SpendGrantTypes.sol";
import {SpendGrantHash} from "../src/SpendGrantHash.sol";
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

contract SpendGrantAuthorizationTest is Test {
    uint256 internal constant PRINCIPAL_PK = 0xA11CE;
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
        principal = vm.addr(PRINCIPAL_PK);
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
        SpendGrant memory m = _grant(delegate);
        bytes memory sig = _sign(m);
        bytes32 h = _hash(m);
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory auth = _authorize(DELEGATE_PK, h, 1e18, recipient, 7, deadline);

        vm.expectEmit(true, true, false, false, address(executor));
        emit AuthorizationUsed(delegate, 7);
        vm.prank(relayer);
        executor.spendWithAuthorization(m, sig, address(token), 1e18, recipient, 7, deadline, auth);

        assertEq(token.balanceOf(recipient), 1e18);
        (uint256 spent, uint256 calls) = registry.usage(h, address(token));
        assertEq(spent, 1e18);
        assertEq(calls, 1);
        assertTrue(executor.nonceUsed(delegate, 7));
    }

    function test_authorizationSucceedsAtMostOnce() public {
        SpendGrant memory m = _grant(delegate);
        bytes memory sig = _sign(m);
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory auth = _authorize(DELEGATE_PK, _hash(m), 1e18, recipient, 7, deadline);

        vm.prank(relayer);
        executor.spendWithAuthorization(m, sig, address(token), 1e18, recipient, 7, deadline, auth);

        // Same bytes, any submitter, any time: the nonce is gone.
        vm.prank(vm.addr(0x0DD));
        vm.expectRevert(SpendGrantAuthorizationExecutor.NonceAlreadyUsed.selector);
        executor.spendWithAuthorization(m, sig, address(token), 1e18, recipient, 7, deadline, auth);
        assertEq(token.balanceOf(recipient), 1e18);
    }

    function test_replayFromInsideTheTransferFails() public {
        ReenteringERC20 hooked = new ReenteringERC20();
        hooked.mint(principal, 1e24);
        vm.prank(principal);
        hooked.approve(address(executor), type(uint256).max);

        SpendGrant memory m = _grant(delegate);
        m.assets[0] = AssetLimit(address(hooked), 1e18, 10e18, 100e18);
        bytes memory sig = _sign(m);
        uint256 deadline = vm.getBlockTimestamp() + 600;
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(DELEGATE_PK, executor.authorizationDigest(_hash(m), address(hooked), 1e18, recipient, 7, deadline));
        bytes memory auth = abi.encodePacked(r, s, v);
        bytes memory call = abi.encodeCall(
            executor.spendWithAuthorization, (m, sig, address(hooked), 1e18, recipient, 7, deadline, auth)
        );
        hooked.arm(executor, call);

        // The nonce was recorded before the movement, so the hook's replay fails and the transfer with it.
        vm.prank(relayer);
        vm.expectRevert(SpendGrantExecutor.TransferFailed.selector);
        executor.spendWithAuthorization(m, sig, address(hooked), 1e18, recipient, 7, deadline, auth);
        assertEq(hooked.balanceOf(recipient), 0);
        (uint256 spent,) = registry.usage(_hash(m), address(hooked));
        assertEq(spent, 0);
    }

    // ---------------------------------------------------------------- what the signature binds

    function test_strangerSignatureIsNotTheDelegate() public {
        SpendGrant memory m = _grant(delegate);
        bytes memory sig = _sign(m);
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory auth = _authorize(STRANGER_PK, _hash(m), 1e18, recipient, 1, deadline);

        // The recovered signer is passed as authorizer and the registry rejects it; nothing is recorded.
        vm.prank(relayer);
        _expect(Reason.UNAUTHORIZED_DELEGATE);
        executor.spendWithAuthorization(m, sig, address(token), 1e18, recipient, 1, deadline, auth);
        assertFalse(executor.nonceUsed(vm.addr(STRANGER_PK), 1));
    }

    function test_tamperedAmountRecoversSomeoneElse() public {
        SpendGrant memory m = _grant(delegate);
        bytes memory sig = _sign(m);
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory auth = _authorize(DELEGATE_PK, _hash(m), 1e17, recipient, 1, deadline);

        vm.prank(relayer);
        _expect(Reason.UNAUTHORIZED_DELEGATE);
        executor.spendWithAuthorization(m, sig, address(token), 1e18, recipient, 1, deadline, auth);
    }

    function test_authorizationIsBoundToTheGrantHash() public {
        SpendGrant memory a = _grant(delegate);
        SpendGrant memory b = _grant(delegate);
        b.salt = 2;
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory authForA = _authorize(DELEGATE_PK, _hash(a), 1e18, recipient, 1, deadline);

        // The executor hashes the grant it is given, so an authorization for A does not fit B.
        vm.prank(relayer);
        _expect(Reason.UNAUTHORIZED_DELEGATE);
        executor.spendWithAuthorization(b, _sign(b), address(token), 1e18, recipient, 1, deadline, authForA);
    }

    function test_deadlineIsExclusive() public {
        SpendGrant memory m = _grant(delegate);
        bytes memory sig = _sign(m);
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory auth = _authorize(DELEGATE_PK, _hash(m), 1e18, recipient, 1, deadline);

        // One second before the deadline it is accepted.
        vm.warp(deadline - 1);
        vm.prank(relayer);
        executor.spendWithAuthorization(m, sig, address(token), 1e18, recipient, 1, deadline, auth);

        // At the deadline it is rejected, and that check comes before the nonce is even looked at.
        vm.warp(deadline);
        vm.prank(relayer);
        vm.expectRevert(SpendGrantAuthorizationExecutor.AuthorizationExpired.selector);
        executor.spendWithAuthorization(m, sig, address(token), 1e18, recipient, 1, deadline, auth);
    }

    function test_malformedSignatureIsRejectedOutright() public {
        SpendGrant memory m = _grant(delegate);
        bytes memory sig = _sign(m);
        uint256 deadline = vm.getBlockTimestamp() + 600;

        vm.prank(relayer);
        vm.expectRevert(SpendGrantAuthorizationExecutor.BadAuthorization.selector);
        executor.spendWithAuthorization(m, sig, address(token), 1e18, recipient, 1, deadline, hex"1234");
    }

    function test_delegateCancelsAnUnusedNonce() public {
        SpendGrant memory m = _grant(delegate);
        bytes memory sig = _sign(m);
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory auth = _authorize(DELEGATE_PK, _hash(m), 1e18, recipient, 9, deadline);

        vm.prank(delegate);
        executor.cancelNonce(9);

        vm.prank(relayer);
        vm.expectRevert(SpendGrantAuthorizationExecutor.NonceAlreadyUsed.selector);
        executor.spendWithAuthorization(m, sig, address(token), 1e18, recipient, 9, deadline, auth);
    }

    // ---------------------------------------------------------------- delegates with code

    function test_erc1271Delegate_isTheAuthorizer() public {
        Allowlist1271 wallet = new Allowlist1271();
        SpendGrant memory m = _grant(address(wallet));
        bytes memory sig = _sign(m);
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes32 digest = executor.authorizationDigest(_hash(m), address(token), 1e18, recipient, 1, deadline);

        vm.prank(relayer);
        vm.expectRevert(SpendGrantAuthorizationExecutor.BadAuthorization.selector);
        executor.spendWithAuthorization(m, sig, address(token), 1e18, recipient, 1, deadline, hex"00");

        wallet.allow(digest);
        vm.prank(relayer);
        executor.spendWithAuthorization(m, sig, address(token), 1e18, recipient, 1, deadline, hex"00");
        assertTrue(executor.nonceUsed(address(wallet), 1));
        assertEq(token.balanceOf(recipient), 1e18);
    }

    function test_7702Delegate_ownKeyFirstThenErc1271() public {
        Rejecting1271 impl = new Rejecting1271();
        vm.etch(delegate, abi.encodePacked(hex"ef0100", address(impl)));
        SpendGrant memory m = _grant(delegate);
        bytes memory sig = _sign(m);
        uint256 deadline = vm.getBlockTimestamp() + 600;

        // The account's own key authorizes even though the delegated code rejects everything.
        bytes memory auth = _authorize(DELEGATE_PK, _hash(m), 1e18, recipient, 1, deadline);
        vm.prank(relayer);
        executor.spendWithAuthorization(m, sig, address(token), 1e18, recipient, 1, deadline, auth);
        assertEq(token.balanceOf(recipient), 1e18);

        // Another key is not the account, so validation falls through to the rejecting ERC-1271.
        bytes memory other = _authorize(STRANGER_PK, _hash(m), 1e18, recipient, 2, deadline);
        vm.prank(relayer);
        vm.expectRevert(SpendGrantAuthorizationExecutor.BadAuthorization.selector);
        executor.spendWithAuthorization(m, sig, address(token), 1e18, recipient, 2, deadline, other);
    }

    function test_7702Delegate_delegatedCodeDecidesWhenItsKeyDidNotSign() public {
        // Rule (b): the account's own key is silent, so the delegated code's ERC-1271 is asked.
        Allowlist1271 impl = new Allowlist1271();
        vm.etch(delegate, abi.encodePacked(hex"ef0100", address(impl)));
        SpendGrant memory m = _grant(delegate);
        bytes memory sig = _sign(m);
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes32 digest = executor.authorizationDigest(_hash(m), address(token), 1e18, recipient, 1, deadline);

        // The allowlist lives in the account's own storage, where the designated code runs.
        Allowlist1271(delegate).allow(digest);
        vm.prank(relayer);
        executor.spendWithAuthorization(m, sig, address(token), 1e18, recipient, 1, deadline, hex"00");
        assertEq(token.balanceOf(recipient), 1e18);
        assertTrue(executor.nonceUsed(delegate, 1));
    }

    function test_malleatedTwinIsNotAnAuthorization() public {
        SpendGrant memory m = _grant(delegate);
        bytes memory sig = _sign(m);
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes32 digest = executor.authorizationDigest(_hash(m), address(token), 1e18, recipient, 1, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATE_PK, digest);
        bytes32 twinS = bytes32(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - uint256(s));
        uint8 twinV = v == 27 ? 28 : 27;
        assertEq(ecrecover(digest, twinV, r, twinS), delegate);

        vm.prank(relayer);
        vm.expectRevert(SpendGrantAuthorizationExecutor.BadAuthorization.selector);
        executor.spendWithAuthorization(
            m, sig, address(token), 1e18, recipient, 1, deadline, abi.encodePacked(r, twinS, twinV)
        );
    }

    function test_usedNonce_isRejectedBeforeTheDelegateIsAsked() public {
        Allowlist1271 wallet = new Allowlist1271();
        SpendGrant memory m = _grant(address(wallet));
        bytes memory sig = _sign(m);
        uint256 deadline = vm.getBlockTimestamp() + 600;
        wallet.allow(executor.authorizationDigest(_hash(m), address(token), 1e18, recipient, 1, deadline));
        vm.prank(relayer);
        executor.spendWithAuthorization(m, sig, address(token), 1e18, recipient, 1, deadline, hex"00");

        // A submitter that lost the race pays for a storage read, not for the delegate's validation.
        vm.expectCall(address(wallet), abi.encodeWithSelector(IERC1271.isValidSignature.selector), 0);
        vm.prank(relayer);
        vm.expectRevert(SpendGrantAuthorizationExecutor.NonceAlreadyUsed.selector);
        executor.spendWithAuthorization(m, sig, address(token), 1e18, recipient, 1, deadline, hex"00");
    }

    function test_cancelNonce_rejectsANonceThatRanOrWasCancelled() public {
        SpendGrant memory m = _grant(delegate);
        bytes memory sig = _sign(m);
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory auth = _authorize(DELEGATE_PK, _hash(m), 1e18, recipient, 7, deadline);
        vm.prank(relayer);
        executor.spendWithAuthorization(m, sig, address(token), 1e18, recipient, 7, deadline, auth);

        // A cancel that succeeds proves the authorization never ran; this one ran, so it fails.
        vm.prank(delegate);
        vm.expectRevert(SpendGrantAuthorizationExecutor.NonceAlreadyUsed.selector);
        executor.cancelNonce(7);

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

        // The encodeType in the file is what the contract hashes.
        assertEq(keccak256(bytes(vm.parseJsonString(json, ".encodeType"))), executor.authorizationTypehash());

        uint256 chainId = vm.parseJsonUint(json, string.concat(p, ".chainId"));
        address vectorExecutor = vm.parseJsonAddress(json, string.concat(p, ".executor"));
        bytes32 grantHash = vm.parseJsonBytes32(json, string.concat(p, ".authorization.grantHash"));
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
            keccak256(abi.encode(executor.authorizationTypehash(), grantHash, asset, amount, to, nonce, deadline)),
            structHash
        );
        assertEq(keccak256(abi.encodePacked(hex"1901", domain, structHash)), digest);

        // The deployed code, placed at the vector's address on the vector's chain, reproduces the digest.
        vm.chainId(chainId);
        vm.etch(vectorExecutor, address(executor).code);
        assertEq(
            SpendGrantAuthorizationExecutor(vectorExecutor).authorizationDigest(
                grantHash, asset, amount, to, nonce, deadline
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
        SpendGrant memory m = _grant(delegate);
        vm.prank(delegate);
        executor.spend(m, _sign(m), address(token), 1e18, recipient);
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

    function _hash(SpendGrant memory m) internal view returns (bytes32) {
        return SpendGrantHash.digest(block.chainid, address(registry), m);
    }

    function _sign(SpendGrant memory m) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRINCIPAL_PK, _hash(m));
        return abi.encodePacked(r, s, v);
    }

    function _authorize(uint256 pk, bytes32 grantHash, uint256 amount, address to, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = executor.authorizationDigest(grantHash, address(token), amount, to, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _expect(Reason r) internal {
        vm.expectRevert(abi.encodeWithSelector(SpendGrantError.selector, r));
    }
}
