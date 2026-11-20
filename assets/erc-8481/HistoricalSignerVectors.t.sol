// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IPresignReportAnchor} from "./IPresignReportAnchor.sol";
import {PresignReportAnchor} from "./PresignReportAnchor.sol";

/// Test-only identity source. It models just the owner/wallet binding for one agent.
contract ReportSourceFixture {
    address public owner;
    address public wallet;
    address private immutable controller = msg.sender;

    function setOwner(address who) external {
        require(msg.sender == controller);
        owner = who;
    }

    function setWallet(address who) external {
        require(msg.sender == controller);
        wallet = who;
    }

    function bound(address who) external view returns (bool) {
        return who != address(0) && (who == owner || who == wallet);
    }
}

contract Rotating1271Fixture {
    address public key;

    constructor(address initialKey) {
        key = initialKey;
    }

    function rotate(address next) external {
        require(msg.sender == key && next != address(0));
        key = next;
    }

    function publish(IPresignReportAnchor anchor, bytes32 subject, bytes32 report) external {
        require(msg.sender == key);
        anchor.anchor(subject, report, "ipfs://report");
    }

    function isValidSignature(bytes32 digest, bytes calldata signature) external view returns (bytes4) {
        if (signature.length != 65) return bytes4(0xffffffff);
        bytes32 r = bytes32(signature[0:32]);
        bytes32 s = bytes32(signature[32:64]);
        uint8 v = uint8(signature[64]);
        return ecrecover(digest, v, r, s) == key ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }
}

/// Snapshot replay models an archive read at a known registry block. This is not
/// an archive RPC client or a full report verifier: hashes are fixed test inputs.
contract HistoricalSignerVectorsTest is Test {
    PresignReportAnchor anchor;
    ReportSourceFixture source;
    uint256 constant KEY = 0x82598481;
    bytes32 constant SUBJECT = keccak256("subject fixture");
    bytes32 constant CONTEXT = keccak256("context fixture");
    bytes32 constant REPORT = keccak256("report fixture");

    function setUp() public {
        vm.warp(1000);
        vm.roll(100);
        anchor = new PresignReportAnchor();
        source = new ReportSourceFixture();
    }

    function digest(uint256 registryChain) internal pure returns (bytes32) {
        bytes32 domain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId)"),
                keccak256("Agent Pre-Sign Risk Report"),
                keccak256("1"),
                registryChain
            )
        );
        bytes32 report = keccak256(
            abi.encode(
                keccak256("PresignReport(bytes32 subjectDigest,bytes32 contextDigest,bytes32 reportHash)"),
                SUBJECT,
                CONTEXT,
                REPORT
            )
        );
        return keccak256(abi.encodePacked(hex"1901", domain, report));
    }

    function signature(bytes32 d) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(KEY, d);
        return abi.encodePacked(r, s, v);
    }

    function publishEOA() internal {
        vm.prank(vm.addr(KEY));
        anchor.anchor(SUBJECT, REPORT, "ipfs://report");
    }

    function assertOriginalAnchor(address signer) internal view {
        (uint64 timestamp, uint64 number) = anchor.anchoredAt(signer, REPORT);
        assertEq(timestamp, 1000);
        assertEq(number, 100);
    }

    function test_walletClearingRejectsCurrentBindingButPreservesHistoricalBinding() public {
        address signer = vm.addr(KEY);
        source.setWallet(signer);
        publishEOA();
        uint256 historical = vm.snapshotState();
        vm.warp(1100);
        vm.roll(110);
        source.setWallet(address(0));
        assertFalse(source.bound(signer), "current pre-sign binding is revoked");
        assertOriginalAnchor(signer);
        assertTrue(vm.revertToState(historical));
        assertTrue(source.bound(signer), "binding at the anchoring still exists");
    }

    function test_ownerTransferDoesNotMoveEarlierAnchor() public {
        address signer = vm.addr(KEY);
        source.setOwner(signer);
        publishEOA();
        uint256 historical = vm.snapshotState();
        vm.warp(1100);
        vm.roll(110);
        source.setOwner(address(0xBEEF));
        publishEOA(); // permissionless publication cannot restore identity authority
        assertFalse(source.bound(signer));
        assertOriginalAnchor(signer);
        assertTrue(vm.revertToState(historical));
        assertTrue(source.bound(signer));
    }

    function test_bindingAddedLaterCannotAuthorizeAnEarlierAnchor() public {
        address signer = vm.addr(KEY);
        publishEOA();
        uint256 historical = vm.snapshotState();
        vm.warp(1100);
        source.setWallet(signer);
        assertTrue(source.bound(signer), "current binding alone would misattribute the report");
        assertTrue(vm.revertToState(historical));
        assertFalse(source.bound(signer), "not bound when the report was anchored");
    }

    function test_1271RotationNeedsHistoricalSignatureStateEvenIfBindingUnchanged() public {
        address key = vm.addr(KEY);
        Rotating1271Fixture signer = new Rotating1271Fixture(key);
        source.setWallet(address(signer));
        bytes32 d = digest(block.chainid);
        bytes memory sig = signature(d);
        vm.prank(key);
        signer.publish(anchor, SUBJECT, REPORT);
        assertEq(signer.isValidSignature(d, sig), bytes4(0x1626ba7e));
        uint256 historical = vm.snapshotState();

        vm.warp(1100);
        vm.roll(110);
        vm.prank(key);
        signer.rotate(address(0xBEEF));
        assertTrue(source.bound(address(signer)), "registry binding did not change");
        assertEq(signer.isValidSignature(d, sig), bytes4(0xffffffff), "current signature is revoked");
        assertOriginalAnchor(address(signer));

        // Reading only the historical binding while calling today's ERC-1271 state
        // still loses this report. Replay both reads in the earlier state to show why.
        assertTrue(vm.revertToState(historical));
        assertTrue(source.bound(address(signer)));
        assertEq(signer.isValidSignature(d, sig), bytes4(0x1626ba7e));
    }

    function test_signatureDomainUsesRegistryChain() public pure {
        bytes32 correctDigest = digest(1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(KEY, correctDigest);
        assertEq(ecrecover(correctDigest, v, r, s), vm.addr(KEY));
        // An anchor's different chain ID must not replace the registry's signing domain.
        assertTrue(ecrecover(digest(42161), v, r, s) != vm.addr(KEY));
    }
}
