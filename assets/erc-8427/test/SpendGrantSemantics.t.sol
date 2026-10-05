// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AssetLimit, IERC1271, NATIVE, SpendGrant, SpendGrantError, Reason} from "../src/SpendGrantTypes.sol";
import {SpendGrantHash} from "../src/SpendGrantHash.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";
import {SpendGrantExecutor} from "../src/SpendGrantExecutor.sol";
import {MockERC20} from "./MockERC20.sol";

/// @dev A smart account whose ERC-1271 accepts its owner and a session key. Whatever it accepts can sign grants.
contract SessionKeyAccount {
    address internal immutable OWNER;
    address internal immutable SESSION_KEY;

    constructor(address owner_, address sessionKey_) {
        OWNER = owner_;
        SESSION_KEY = sessionKey_;
    }

    function isValidSignature(bytes32 hash_, bytes calldata sig) external view returns (bytes4) {
        if (sig.length != 65) return 0xffffffff;
        address signer = ecrecover(hash_, uint8(sig[64]), bytes32(sig[:32]), bytes32(sig[32:64]));
        return signer == OWNER || signer == SESSION_KEY ? IERC1271.isValidSignature.selector : bytes4(0xffffffff);
    }
}

/// @dev An ERC-1271 validator that writes state, which only a CALL could allow.
contract Writing1271 {
    uint256 public hits;

    function isValidSignature(bytes32, bytes calldata) external returns (bytes4) {
        hits++;
        return IERC1271.isValidSignature.selector;
    }
}

/// @dev Rules the review added: payee restrictions, event topics, the selected-asset code check, what an
/// ERC-1271 principal's policy implies, stacking grants, the live-debit bound on spendable amounts, the
/// static ERC-1271 call, and confirming a revocation.
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

    event GrantConsumed(
        bytes32 indexed grantHash, address indexed principal, address asset, uint256 amount, address indexed recipient
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

        token.mint(principal, 1e24);
        vm.prank(principal);
        token.approve(address(executor), type(uint256).max);

        vm.warp(1_700_000_000);
    }

    // ---------------------------------------------------------------- recipient argument

    function test_recipient_mode1RejectsZeroPrincipalRegistryExecutor() public {
        SpendGrant memory m = _grant(address(registry));
        m.recipientMode = 1;
        m.recipient = address(0);
        bytes memory sig = _sign(PRINCIPAL_PK, m, address(registry));

        address[4] memory bad = [address(0), principal, address(registry), address(this)];
        for (uint256 i = 0; i < bad.length; i++) {
            _expect(Reason.WRONG_RECIPIENT);
            registry.consume(m, sig, delegate, NATIVE, 1, bad[i]);
        }
        registry.consume(m, sig, delegate, NATIVE, 1, recipient);
        (uint256 spent,) = registry.usage(_hash(m, address(registry)), NATIVE);
        assertEq(spent, 1);
    }

    function test_recipient_mode0GrantNamingTheExecutorFailsClosed() public {
        // Structurally valid (nonzero, not the principal), but every consume is WRONG_RECIPIENT.
        SpendGrant memory m = _grant(address(execRegistry));
        m.recipient = address(executor);
        bytes memory sig = _sign(PRINCIPAL_PK, m, address(execRegistry));

        vm.prank(delegate);
        _expect(Reason.WRONG_RECIPIENT);
        executor.spend(m, sig, address(token), 1e18, address(executor));
        assertEq(token.balanceOf(address(executor)), 0);
    }

    // ---------------------------------------------------------------- event

    function test_event_indexesGrantPrincipalAndRecipient() public {
        SpendGrant memory m = _grant(address(execRegistry));
        bytes memory sig = _sign(PRINCIPAL_PK, m, address(execRegistry));
        bytes32 h = _hash(m, address(execRegistry));

        vm.expectEmit(true, true, true, true, address(execRegistry));
        emit GrantConsumed(h, principal, address(token), 1e18, recipient);
        vm.prank(delegate);
        executor.spend(m, sig, address(token), 1e18, recipient);
    }

    // ---------------------------------------------------------------- selected-asset code check

    function test_codeCheck_appliesToTheSpentAssetOnly() public {
        address codeless = address(uint160(address(token)) - 1); // sorts before the token, has no code
        SpendGrant memory m = _grant(address(execRegistry));
        m.assets = new AssetLimit[](2);
        m.assets[0] = AssetLimit(codeless, 1, 1, 1);
        m.assets[1] = AssetLimit(address(token), 1e18, 10e18, 100e18);
        bytes memory sig = _sign(PRINCIPAL_PK, m, address(execRegistry));

        // The listing without code does not block the token.
        vm.prank(delegate);
        executor.spend(m, sig, address(token), 1e18, recipient);
        assertEq(token.balanceOf(recipient), 1e18);

        // Spending the codeless listing itself is INVALID_GRANT.
        vm.prank(delegate);
        _expect(Reason.INVALID_GRANT);
        executor.spend(m, sig, codeless, 1, recipient);

        // Membership is checked first: an unlisted codeless address is WRONG_ASSET, not INVALID_GRANT.
        vm.prank(delegate);
        _expect(Reason.WRONG_ASSET);
        executor.spend(m, sig, address(0xD00D), 1, recipient);
    }

    // ---------------------------------------------------------------- ERC-1271 principals

    function test_erc1271_everyAcceptedSignerCanMintGrants() public {
        address sessionKey = vm.addr(SESSION_PK);
        SessionKeyAccount account = new SessionKeyAccount(principal, sessionKey);
        token.mint(address(account), 1e24);
        vm.prank(address(account));
        token.approve(address(executor), type(uint256).max);

        // The session key alone signs a grant naming itself delegate, mode 1, and pays itself.
        SpendGrant memory m = _grant(address(execRegistry));
        m.principal = address(account);
        m.delegate = sessionKey;
        m.recipientMode = 1;
        m.recipient = address(0);
        bytes memory sig = _sign(SESSION_PK, m, address(execRegistry));

        vm.prank(sessionKey);
        executor.spend(m, sig, address(token), 1e18, sessionKey);
        assertEq(token.balanceOf(sessionKey), 1e18);
    }

    function test_erc1271_callIsStatic() public {
        Writing1271 p = new Writing1271();
        SpendGrant memory m = _grant(address(registry));
        m.principal = address(p);

        _expect(Reason.BAD_SIGNATURE);
        registry.consume(m, hex"00", delegate, NATIVE, 1, recipient);
        assertEq(p.hits(), 0);
    }

    // ---------------------------------------------------------------- grants stack

    function test_grants_doNotSupersedeEachOther() public {
        SpendGrant memory first = _grant(address(execRegistry));
        first.assets[0] = AssetLimit(address(token), 1e18, 1e18, 1e18);
        SpendGrant memory second = _grant(address(execRegistry));
        second.assets[0] = AssetLimit(address(token), 5e17, 5e17, 5e17); // a "lowered" cap
        second.salt = 2;

        vm.startPrank(delegate);
        executor.spend(first, _sign(PRINCIPAL_PK, first, address(execRegistry)), address(token), 1e18, recipient);
        executor.spend(second, _sign(PRINCIPAL_PK, second, address(execRegistry)), address(token), 5e17, recipient);
        vm.stopPrank();

        // Both caps were spendable: the delegate moved the sum, not the lower cap.
        assertEq(token.balanceOf(recipient), 1.5e18);
    }

    // ---------------------------------------------------------------- spendable now near the bound

    function test_spendableNow_isBoundedByFreeDebitSlots() public {
        SpendGrant memory m = _grant(address(registry));
        m.assets = new AssetLimit[](1);
        m.assets[0] = AssetLimit(NATIVE, 1, 1e6, 1e6);
        bytes memory sig = _sign(PRINCIPAL_PK, m, address(registry));
        bytes32 h = _hash(m, address(registry));

        for (uint256 i = 0; i < 1020; i++) {
            registry.consume(m, sig, delegate, NATIVE, 1, recipient);
        }
        (uint256 rolling, uint256 live) = registry.rollingUsage(h, NATIVE);
        assertEq(live, 1020);
        // The window and lifetime remainders are both about 1e6, but only four slots are free.
        assertGt(1e6 - rolling, 4);
        for (uint256 i = 0; i < 4; i++) {
            registry.consume(m, sig, delegate, NATIVE, 1, recipient);
        }
        _expect(Reason.WINDOW_FULL);
        registry.consume(m, sig, delegate, NATIVE, 1, recipient);
    }

    // ---------------------------------------------------------------- confirming a revocation

    function test_revoke_wrongHashEmitsButRevokesNothing() public {
        SpendGrant memory m = _grant(address(registry));
        bytes memory sig = _sign(PRINCIPAL_PK, m, address(registry));
        bytes32 h = _hash(m, address(registry));
        bytes32 wrong = keccak256("not the grant");

        vm.prank(principal);
        registry.revoke(wrong);
        assertTrue(registry.revoked(principal, wrong));
        // The grant is still live, so a wallet that trusts the event is wrong.
        registry.consume(m, sig, delegate, NATIVE, 1, recipient);

        // The confirmation the spec recommends: simulate consume from the executor and expect REVOKED.
        vm.prank(principal);
        registry.revoke(h);
        (bool ok, bytes memory ret) =
            address(registry).call(abi.encodeCall(registry.consume, (m, sig, delegate, NATIVE, 1, recipient)));
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(SpendGrantError.selector, Reason.REVOKED));
    }

    // ---------------------------------------------------------------- helpers

    function _grant(address) internal view returns (SpendGrant memory m) {
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

    function _hash(SpendGrant memory m, address reg) internal view returns (bytes32) {
        return SpendGrantHash.digest(block.chainid, reg, m);
    }

    function _sign(uint256 pk, SpendGrant memory m, address reg) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _hash(m, reg));
        return abi.encodePacked(r, s, v);
    }

    function _expect(Reason r) internal {
        vm.expectRevert(abi.encodeWithSelector(SpendGrantError.selector, r));
    }
}
