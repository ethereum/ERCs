// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AssetLimit, SpendGrant, Reason} from "../src/SpendGrantTypes.sol";
import {SpendGrantRegistry} from "../src/SpendGrantRegistry.sol";
import {SpendGrantAuthorizationExecutor} from "../src/SpendGrantAuthorizationExecutor.sol";
import {MockERC20} from "./MockERC20.sol";

/// @notice A delegate's signed SpendAuthorization runs only on the chain and executor it was signed for: not
/// after a chain split that copies the state, and not on a second registry/executor pair with the same terms.
/// Adopted from the final money-path review's proof-of-concept tests.
contract SpendGrantAuthReplayTest is Test {
    uint256 internal constant DELEGATE_PK = 0xB0B;
    address internal principal = vm.addr(0xA11CE);
    address internal delegate = vm.addr(DELEGATE_PK);
    address internal recipient = vm.addr(0xC0C);

    function _err(Reason r) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(bytes4(keccak256("SpendGrantError(uint8)")), uint8(r));
    }

    function _deploy(MockERC20 token) internal returns (SpendGrantRegistry reg, SpendGrantAuthorizationExecutor ex) {
        uint64 n = vm.getNonce(address(this));
        reg = new SpendGrantRegistry(vm.computeCreateAddress(address(this), n + 1));
        ex = new SpendGrantAuthorizationExecutor(reg);
        vm.prank(principal);
        token.approve(address(ex), type(uint256).max);
    }

    function _terms(address token) internal view returns (SpendGrant memory m) {
        m.principal = principal;
        m.delegate = delegate;
        m.recipientMode = 1;
        m.windowSeconds = 86400;
        m.validAfter = 1_699_999_000;
        m.validUntil = 1_900_000_000;
        m.salt = 1;
        m.assets = new AssetLimit[](1);
        m.assets[0] = AssetLimit(token, 1e18, 10e18, 100e18);
    }

    function _sign(SpendGrantAuthorizationExecutor ex, bytes32 id, address token, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = ex.authorizationDigest(id, token, 1e18, recipient, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATE_PK, digest);
        return abi.encodePacked(r, s, v);
    }

    /// State copied by a chain split: same registry, same grant, same executor, nonce unused on the new chain.
    /// The control runs first from a snapshot so that the test ends on the expected revert.
    function test_authorizationSignedBeforeAChainSplit_doesNotRunAfterIt() public {
        vm.warp(1_700_000_000);
        MockERC20 token = new MockERC20();
        token.mint(principal, 1e24);
        (SpendGrantRegistry reg, SpendGrantAuthorizationExecutor ex) = _deploy(token);
        vm.prank(principal);
        bytes32 id = reg.register(_terms(address(token)));
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory auth = _sign(ex, id, address(token), 7, deadline);

        // Control: on the chain it was signed for, the authorization runs.
        uint256 snap = vm.snapshotState();
        ex.spendWithAuthorization(id, address(token), 1e18, recipient, 7, deadline, auth);
        assertEq(token.balanceOf(recipient), 1e18);

        // The split: the same state (nonce 7 unused again) under the next chain id.
        vm.revertToState(snap);
        vm.chainId(block.chainid + 1);
        vm.expectRevert(_err(Reason.UNAUTHORIZED_DELEGATE));
        ex.spendWithAuthorization(id, address(token), 1e18, recipient, 7, deadline, auth);
    }

    /// Same principal, delegate and terms on a second registry/executor pair: the id differs (domain names the
    /// registry), and the signature for the first executor recovers someone else under the second. Both attempts
    /// are low-level calls with exact revert data, so the final balance check follows no expected-revert call.
    function test_authorizationForOneExecutor_doesNotRunOnAnother() public {
        vm.warp(1_700_000_000);
        MockERC20 token = new MockERC20();
        token.mint(principal, 1e24);
        (SpendGrantRegistry reg1, SpendGrantAuthorizationExecutor ex1) = _deploy(token);
        (SpendGrantRegistry reg2, SpendGrantAuthorizationExecutor ex2) = _deploy(token);
        vm.startPrank(principal);
        bytes32 id1 = reg1.register(_terms(address(token)));
        bytes32 id2 = reg2.register(_terms(address(token)));
        vm.stopPrank();
        assertTrue(id1 != id2);
        uint256 deadline = vm.getBlockTimestamp() + 600;
        bytes memory auth = _sign(ex1, id1, address(token), 7, deadline);

        (bool ok, bytes memory ret) = address(ex2).call(
            abi.encodeCall(
                SpendGrantAuthorizationExecutor.spendWithAuthorization,
                (id1, address(token), 1e18, recipient, 7, deadline, auth)
            )
        );
        assertFalse(ok);
        assertEq(ret, _err(Reason.NONEXISTENT));
        (ok, ret) = address(ex2).call(
            abi.encodeCall(
                SpendGrantAuthorizationExecutor.spendWithAuthorization,
                (id2, address(token), 1e18, recipient, 7, deadline, auth)
            )
        );
        assertFalse(ok);
        assertEq(ret, _err(Reason.UNAUTHORIZED_DELEGATE));
        assertEq(token.balanceOf(recipient), 0);
    }
}
