// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IVerificationGate.sol";
import "../examples/MarketGate.sol";
import "../examples/IdentityGate.sol";

contract MockDepthOracle is IDepthOracle {
    mapping(address => uint256) public depth;
    function set(address a, uint256 d) external { depth[a] = d; }
    function depthOf(address a) external view returns (uint256) { return depth[a]; }
}

/// @dev Run with: forge test -vv
contract MarketGateTest is Test {
    event ClaimRevoked(bytes32 indexed claimId, address indexed revoker,
                       bytes32 reasonHash);

    MarketGate internal gate;

    address internal arbiter  = address(0xA11CE);
    address internal server   = address(0x51);   // claimant (offerer == subject)
    address internal genesis  = address(0x61);   // seeded verifier
    address internal nobody   = address(0x71);   // no verified depth
    uint256 internal constant STAKE = 1 ether;
    uint256 internal constant THRESHOLD = 3;

    function setUp() public {
        address[] memory g = new address[](1);
        g[0] = genesis;
        gate = new MarketGate(STAKE, THRESHOLD, arbiter, g, 5);
        vm.deal(server, 10 ether);
    }

    function _offer() internal returns (bytes32 id) {
        vm.prank(server);
        id = gate.offer{value: STAKE}(server, keccak256("claim"), "");
    }

    // ── offer / stake binding ────────────────────────────────────────────

    function test_offer_binds_stake_and_emits() public {
        vm.prank(server);
        bytes32 id = gate.offer{value: STAKE}(server, keccak256("claim"), "");
        (IVerificationGate.Status s, uint256 w) = gate.statusOf(id);
        assertEq(uint8(s), uint8(IVerificationGate.Status.Offered));
        assertEq(w, 0);
        assertEq(address(gate).balance, STAKE);
    }

    function test_offer_reverts_without_required_stake() public {
        vm.prank(server);
        vm.expectRevert(
            abi.encodeWithSelector(VerificationGate.InsufficientStake.selector, STAKE, 0)
        );
        gate.offer(server, keccak256("claim"), "");
    }

    // ── verify: red lines ────────────────────────────────────────────────

    function test_self_verification_reverts() public {
        bytes32 id = _offer();
        vm.prank(server); // subject and offerer
        vm.expectRevert(
            abi.encodeWithSelector(VerificationGate.SelfVerification.selector, id, server)
        );
        gate.verify(id, keccak256("ev"));
    }

    function test_zero_weight_verifiers_never_promote() public {
        bytes32 id = _offer();
        // a Sybil swarm of fresh identities
        for (uint160 i = 1; i <= 50; i++) {
            vm.prank(address(uint160(0x1000) + i));
            gate.verify(id, keccak256("ev"));
        }
        (IVerificationGate.Status s, uint256 w) = gate.statusOf(id);
        assertEq(uint8(s), uint8(IVerificationGate.Status.Offered)); // still untrusted
        assertEq(w, 0);
    }

    function test_weighted_promotion() public {
        bytes32 id = _offer();
        vm.prank(genesis); // weight 5 >= threshold 3
        gate.verify(id, keccak256("ev"));
        (IVerificationGate.Status s, uint256 w) = gate.statusOf(id);
        assertEq(uint8(s), uint8(IVerificationGate.Status.Verified));
        assertEq(w, 5);
    }

    function test_double_verify_reverts() public {
        bytes32 id = _offer();
        vm.prank(genesis);
        gate.verify(id, keccak256("ev"));
        vm.prank(genesis);
        vm.expectRevert(
            abi.encodeWithSelector(VerificationGate.AlreadyVerified.selector, id, genesis)
        );
        gate.verify(id, keccak256("ev"));
    }

    // ── settle ───────────────────────────────────────────────────────────

    function test_settle_reverts_unless_verified() public {
        bytes32 id = _offer();
        vm.prank(server);
        vm.expectRevert(
            abi.encodeWithSelector(VerificationGate.BadStatus.selector, id,
                                   IVerificationGate.Status.Offered)
        );
        gate.settle(id);
    }

    function test_settle_releases_stake_and_deepens_subject() public {
        bytes32 id = _offer();
        vm.prank(genesis);
        gate.verify(id, keccak256("ev"));

        uint256 before = server.balance;
        assertEq(gate.weightOf(server), 0);
        vm.prank(server);
        gate.settle(id);

        (IVerificationGate.Status s, ) = gate.statusOf(id);
        assertEq(uint8(s), uint8(IVerificationGate.Status.Settled));
        assertEq(server.balance, before + STAKE);   // stake returned
        assertEq(gate.weightOf(server), 1);         // depth recursion
    }

    function test_settled_is_terminal() public {
        bytes32 id = _offer();
        vm.prank(genesis);
        gate.verify(id, keccak256("ev"));
        vm.prank(server);
        gate.settle(id);

        // no revoke after settlement — even by the arbiter
        vm.prank(arbiter);
        vm.expectRevert(
            abi.encodeWithSelector(VerificationGate.BadStatus.selector, id,
                                   IVerificationGate.Status.Settled)
        );
        gate.revoke(id, keccak256("reason"));

        // no further verification either
        vm.prank(genesis);
        vm.expectRevert();
        gate.verify(id, keccak256("ev2"));
    }

    // ── revoke ───────────────────────────────────────────────────────────

    function test_revoke_burns_stake_and_keeps_record() public {
        bytes32 id = _offer();
        uint256 burnBefore = gate.BURN().balance;

        vm.prank(arbiter);
        vm.expectEmit(true, true, false, true);
        emit ClaimRevoked(id, arbiter, keccak256("bad"));
        gate.revoke(id, keccak256("bad"));

        (IVerificationGate.Status s, ) = gate.statusOf(id);
        assertEq(uint8(s), uint8(IVerificationGate.Status.Revoked)); // queryable forever
        assertEq(gate.BURN().balance, burnBefore + STAKE);           // burned, not paid out
        assertEq(arbiter.balance, 0);                                // no bounty for the trigger

        vm.prank(arbiter);
        vm.expectRevert(); // terminal
        gate.revoke(id, keccak256("again"));
    }

    function test_revoke_only_by_arbiter() public {
        bytes32 id = _offer();
        vm.prank(nobody);
        vm.expectRevert(
            abi.encodeWithSelector(VerificationGate.NotAuthorized.selector, id, nobody)
        );
        gate.revoke(id, keccak256("reason"));
    }
}

contract IdentityGateTest is Test {
    IdentityGate internal gate;
    MockDepthOracle internal oracle;

    address internal issuer    = address(0xC0);  // offerer (verified company)
    address internal recipient = address(0xD0);  // subject
    address internal deepPeer  = address(0xE0);  // oracle depth 4
    address internal anon      = address(0xF0);  // oracle depth 0

    function setUp() public {
        oracle = new MockDepthOracle();
        oracle.set(deepPeer, 4);
        gate = new IdentityGate(oracle, 3);
    }

    function test_zero_stake_conforms() public {
        vm.prank(issuer);
        bytes32 id = gate.offer(recipient, keccak256("attestation"), "");
        (IVerificationGate.Status s, ) = gate.statusOf(id);
        assertEq(uint8(s), uint8(IVerificationGate.Status.Offered));
    }

    function test_oracle_weight_promotes_and_anon_does_not() public {
        vm.prank(issuer);
        bytes32 id = gate.offer(recipient, keccak256("attestation"), "");

        vm.prank(anon);
        gate.verify(id, keccak256("ev"));
        (IVerificationGate.Status s0, uint256 w0) = gate.statusOf(id);
        assertEq(uint8(s0), uint8(IVerificationGate.Status.Offered));
        assertEq(w0, 0);

        vm.prank(deepPeer);
        gate.verify(id, keccak256("ev"));
        (IVerificationGate.Status s1, uint256 w1) = gate.statusOf(id);
        assertEq(uint8(s1), uint8(IVerificationGate.Status.Verified));
        assertEq(w1, 4);
    }

    function test_issuer_revokes_verified_claim_with_trace() public {
        vm.prank(issuer);
        bytes32 id = gate.offer(recipient, keccak256("attestation"), "");
        vm.prank(deepPeer);
        gate.verify(id, keccak256("ev"));

        // identity-side shape: stays Verified, revocable by issuer indefinitely
        vm.prank(issuer);
        gate.revoke(id, keccak256("employment ended"));
        (IVerificationGate.Status s, uint256 w) = gate.statusOf(id);
        assertEq(uint8(s), uint8(IVerificationGate.Status.Revoked));
        assertEq(w, 4); // history preserved

        // recipient (subject) can neither verify nor revoke
        vm.prank(recipient);
        vm.expectRevert();
        gate.revoke(id, keccak256("no"));
    }

    function test_settle_is_the_point_of_no_return() public {
        vm.prank(issuer);
        bytes32 id = gate.offer(recipient, keccak256("attestation"), "");
        vm.prank(deepPeer);
        gate.verify(id, keccak256("ev"));
        vm.prank(issuer);
        gate.settle(id);

        vm.prank(issuer);
        vm.expectRevert(
            abi.encodeWithSelector(VerificationGate.BadStatus.selector, id,
                                   IVerificationGate.Status.Settled)
        );
        gate.revoke(id, keccak256("too late"));
    }
}
