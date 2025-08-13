// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SIIntentLib.sol";
import "../src/SIIntentGate.sol";
import "../src/MockERC1271.sol";

contract SIIntentGateTest is Test {
    using SIIntentLib for SIIntentLib.Header;

    SIIntentGate gate;
    bytes32 constant DOM = keccak256("SI-TEST-DOM");

    // Keys
    uint256 aliceKey = 0xA11CE;
    uint256 bobKey   = 0xB0B;
    address alice;
    address bob;

    function setUp() public {
        alice = vm.addr(aliceKey);
        bob   = vm.addr(bobKey);
        gate  = new SIIntentGate("SI-TEST", "1", bytes32(0));
    }

    function _build(bytes32 kidR, uint64 nonce, uint64 ttl, bytes32 mpHash, bytes32 ctHash, address agent)
        internal pure returns (SIIntentLib.Header memory h)
    {
        h.dom    = DOM;
        h.agent  = agent;
        h.kidR   = kidR;
        h.nonce  = nonce;
        h.ttl    = ttl;
        h.mpHash = mpHash;
        h.ctHash = ctHash;
    }

    function _sign(address agent, uint256 pk, SIIntentLib.Header memory h) internal view returns (bytes memory sig) {
        bytes32 dig = SIIntentLib.digest(gate.DOMAIN_SEPARATOR(), h);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, dig);
        return abi.encodePacked(r, s, v);
    }

    function _signWithDomain(address agent, uint256 pk, SIIntentLib.Header memory h, bytes32 domainSeparator)
        internal view returns (bytes memory sig)
    {
        bytes32 dig = SIIntentLib.digest(domainSeparator, h);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, dig);
        return abi.encodePacked(r, s, v);
    }

    function test_accept_valid_EOA() public {
        SIIntentLib.Header memory h = _build(0x0, 1, uint64(block.timestamp + 600),
                                             keccak256("mp"), keccak256("ct"), alice);
        bytes memory sig = _sign(alice, aliceKey, h);

        SIIntentGate.SubmitParams memory p = SIIntentGate.SubmitParams({ header: h, signature: sig });
        gate.acceptIntent(p); // should not revert
    }

    function test_reject_expired() public {
        SIIntentLib.Header memory h = _build(0x0, 1, uint64(block.timestamp - 1),
                                             keccak256("mp"), keccak256("ct"), alice);
        bytes memory sig = _sign(alice, aliceKey, h);
        SIIntentGate.SubmitParams memory p = SIIntentGate.SubmitParams({ header: h, signature: sig });
        vm.expectRevert("SI: expired");
        gate.acceptIntent(p);
    }

    function test_replay_protection() public {
        SIIntentLib.Header memory h = _build(0x0, 42, uint64(block.timestamp + 600),
                                             keccak256("mp"), keccak256("ct"), alice);
        bytes memory sig = _sign(alice, aliceKey, h);
        SIIntentGate.SubmitParams memory p = SIIntentGate.SubmitParams({ header: h, signature: sig });

        gate.acceptIntent(p);
        vm.expectRevert("SI: replay");
        gate.acceptIntent(p);
    }

    function test_domain_separation() public {
        // Sign for gate A
        SIIntentLib.Header memory h = _build(0x0, 7, uint64(block.timestamp + 600),
                                             keccak256("mp"), keccak256("ct"), alice);
        bytes memory sig = _sign(alice, aliceKey, h);

        // Deploy another gate with different domain, reuse same signature -> should fail
        SIIntentGate gate2 = new SIIntentGate("OTHER", "1", bytes32(0));
        SIIntentGate.SubmitParams memory p = SIIntentGate.SubmitParams({ header: h, signature: sig });
        vm.expectRevert("SI: bad sig");
        gate2.acceptIntent(p);
    }

    function test_kidR_binding() public {
        bytes32 enforced = keccak256("kidR");
        SIIntentGate gate2 = new SIIntentGate("SI-TEST", "1", enforced);

        // Header with different kidR should fail
        SIIntentLib.Header memory h = _build(bytes32(uint256(1)), 1, uint64(block.timestamp + 600),
                                             keccak256("mp"), keccak256("ct"), alice);
        bytes memory sig = _signWithDomain(alice, aliceKey, h, gate2.DOMAIN_SEPARATOR());
        SIIntentGate.SubmitParams memory p = SIIntentGate.SubmitParams({ header: h, signature: sig });
        vm.expectRevert("SI: wrong recipient");
        gate2.acceptIntent(p);

        // Matching kidR should pass
        h.kidR = enforced;
        sig = _signWithDomain(alice, aliceKey, h, gate2.DOMAIN_SEPARATOR());
        p = SIIntentGate.SubmitParams({ header: h, signature: sig });
        gate2.acceptIntent(p);
    }

    function test_nonce_scoped_per_agent() public {
        // Same nonce, two different agents: both accepted
        SIIntentLib.Header memory h1 = _build(0x0, 5, uint64(block.timestamp + 600),
                                             keccak256("mp1"), keccak256("ct1"), alice);
        bytes memory s1 = _sign(alice, aliceKey, h1);
        gate.acceptIntent(SIIntentGate.SubmitParams({ header: h1, signature: s1 }));

        SIIntentLib.Header memory h2 = _build(0x0, 5, uint64(block.timestamp + 600),
                                             keccak256("mp2"), keccak256("ct2"), bob);
        bytes memory s2 = _sign(bob, bobKey, h2);
        gate.acceptIntent(SIIntentGate.SubmitParams({ header: h2, signature: s2 }));
    }

    function test_malleable_s_rejected() public {
        SIIntentLib.Header memory h = _build(0x0, 9, uint64(block.timestamp + 600),
                                             keccak256("mp"), keccak256("ct"), alice);
        bytes32 dig = SIIntentLib.digest(gate.DOMAIN_SEPARATOR(), h);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, dig);

        // Flip to high-s: s' = n - s; v' toggled
        uint256 N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        bytes32 shigh = bytes32(N - uint256(s));
        uint8 vflip = (v == 27) ? 28 : 27;
        bytes memory sigHigh = abi.encodePacked(r, shigh, vflip);

        // ecrecover would accept, but our library must reject
        vm.expectRevert("SI: bad sig");
        gate.acceptIntent(SIIntentGate.SubmitParams({ header: h, signature: sigHigh }));
    }

    function test_mpHash_binding() public {
        SIIntentLib.Header memory h = _build(0x0, 10, uint64(block.timestamp + 600),
                                             keccak256("mpA"), keccak256("ctA"), alice);
        bytes memory sig = _sign(alice, aliceKey, h);

        // Tamper mpHash post-signature -> signature should fail
        h.mpHash = keccak256("mpB");
        vm.expectRevert("SI: bad sig");
        gate.acceptIntent(SIIntentGate.SubmitParams({ header: h, signature: sig }));
    }

    function test_erc1271_signature() public {
        MockERC1271 wallet = new MockERC1271();
        // Header signed "by" contract wallet, but approval happens inside the wallet
        SIIntentLib.Header memory h = _build(0x0, 11, uint64(block.timestamp + 600),
                                             keccak256("mp"), keccak256("ct"), address(wallet));
        bytes32 dig = SIIntentLib.digest(gate.DOMAIN_SEPARATOR(), h);

        // Provide any signature bytes; wallet decides validity
        bytes memory fakeSig = hex"aaaa";
        wallet.set(dig, fakeSig);

        SIIntentGate.SubmitParams memory p = SIIntentGate.SubmitParams({ header: h, signature: fakeSig });
        gate.acceptIntent(p);
    }
}
