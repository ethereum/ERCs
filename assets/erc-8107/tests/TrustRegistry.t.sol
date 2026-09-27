// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {TrustRegistry, IENS, INameWrapper, IAddrResolver} from "../contracts/TrustRegistry.sol";
import {
    ITrustRegistry,
    ITrustRegistryExtended,
    TrustLevel,
    TrustAttestation,
    ValidationParams,
    TrustPath,
    SelfTrustProhibited,
    NonceTooLow,
    AttestationExpired,
    InvalidSignature,
    NotAuthorized,
    ENSNameNotFound,
    GateNotFound,
    InvalidAttestationLevel,
    InvalidMaxPathLength,
    InvalidMinEdgeTrust,
    TooManyRequiredAnchors,
    BatchTrustorMismatch,
    BatchNonceNotIncreasing,
    EmptyScopeList
} from "../contracts/ITrustRegistry.sol";

/// @notice Mock ENS registry
contract MockENS is IENS {
    mapping(bytes32 => address) private _owners;
    mapping(bytes32 => address) private _resolvers;
    mapping(address => mapping(address => bool)) private _operators;

    function setOwner(bytes32 node, address newOwner) external {
        _owners[node] = newOwner;
    }

    function setResolver(bytes32 node, address resolver_) external {
        _resolvers[node] = resolver_;
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operators[msg.sender][operator] = approved;
    }

    function owner(bytes32 node) external view override returns (address) {
        return _owners[node];
    }

    function resolver(bytes32 node) external view override returns (address) {
        return _resolvers[node];
    }

    function isApprovedForAll(address owner_, address operator) external view override returns (bool) {
        return _operators[owner_][operator];
    }
}

/// @notice Mock ENS NameWrapper (ERC-1155 semantics)
contract MockNameWrapper is INameWrapper {
    mapping(uint256 => address) private _owners;
    mapping(address => mapping(address => bool)) private _operators;

    function setWrappedOwner(bytes32 node, address newOwner) external {
        _owners[uint256(node)] = newOwner;
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operators[msg.sender][operator] = approved;
    }

    function ownerOf(uint256 id) external view override returns (address) {
        return _owners[id];
    }

    function isApprovedForAll(address owner_, address operator) external view override returns (bool) {
        return _operators[owner_][operator];
    }
}

/// @notice Mock ERC-137 forward resolver
contract MockResolver is IAddrResolver {
    mapping(bytes32 => address) private _addrs;

    function setAddr(bytes32 node, address a) external {
        _addrs[node] = a;
    }

    function addr(bytes32 node) external view override returns (address payable) {
        return payable(_addrs[node]);
    }
}

/// @notice Resolver that always reverts, standing in for a CCIP-Read resolver
contract RevertingResolver is IAddrResolver {
    function addr(bytes32) external pure override returns (address payable) {
        revert("OffchainLookup");
    }
}

/// @notice Contract owner that accepts one designated signer via EIP-1271
contract MockSmartWallet is IERC1271 {
    address public signer;

    constructor(address signer_) {
        signer = signer_;
    }

    function isValidSignature(bytes32 digest, bytes memory signature) external view override returns (bytes4) {
        if (signature.length != 65) return bytes4(0xffffffff);
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
        return ecrecover(digest, v, r, s) == signer ? IERC1271.isValidSignature.selector : bytes4(0xffffffff);
    }
}

contract TrustRegistryTest is Test {
    TrustRegistry internal registry;
    MockENS internal ens;
    MockNameWrapper internal wrapper;
    MockResolver internal resolver;

    /// @dev The ERC-8001 coordinator that owns the gate namespace under test
    address internal coordinator = address(0xC00D);
    address internal otherCoordinator = address(0xDEAD);

    uint256 internal aliceKey = 0xA11CE;
    uint256 internal bobKey = 0xB0B;
    uint256 internal carolKey = 0xCA201;
    uint256 internal daveKey = 0xDA7E;
    uint256 internal malloryKey = 0x4A110C;

    address internal alice;
    address internal bob;
    address internal carol;
    address internal dave;
    address internal mallory;

    bytes32 internal constant ALICE = keccak256("alice.agents.eth");
    bytes32 internal constant BOB = keccak256("bob.agents.eth");
    bytes32 internal constant CAROL = keccak256("carol.agents.eth");
    bytes32 internal constant DAVE = keccak256("dave.agents.eth");
    bytes32 internal constant ANCHOR = keccak256("dao.agents.eth");
    bytes32 internal constant GHOST = keccak256("ghost.agents.eth");

    bytes32 internal constant UNIVERSAL = bytes32(0);
    bytes32 internal constant DEFI = keccak256("DEFI");
    bytes32 internal constant GAMING = keccak256("GAMING");
    bytes32 internal constant MEV_COORDINATION = keccak256("MEV_COORDINATION");

    function setUp() public {
        alice = vm.addr(aliceKey);
        bob = vm.addr(bobKey);
        carol = vm.addr(carolKey);
        dave = vm.addr(daveKey);
        mallory = vm.addr(malloryKey);

        ens = new MockENS();
        wrapper = new MockNameWrapper();
        resolver = new MockResolver();
        registry = new TrustRegistry(address(ens), address(wrapper));

        ens.setOwner(ALICE, alice);
        ens.setOwner(BOB, bob);
        ens.setOwner(CAROL, carol);
        ens.setOwner(DAVE, dave);

        vm.warp(1_700_000_000);
    }

    // ───────────────────────────────────────────────────────────────────────────
    // Helpers
    // ───────────────────────────────────────────────────────────────────────────

    function _att(bytes32 trustor, bytes32 trustee, TrustLevel level, bytes32 scope, uint64 expiry, uint64 nonce)
        internal
        pure
        returns (TrustAttestation memory)
    {
        return TrustAttestation({
            trustorNode: trustor,
            trusteeNode: trustee,
            level: level,
            scope: scope,
            expiry: expiry,
            nonce: nonce
        });
    }

    function _sign(uint256 key, TrustAttestation memory att) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, registry.hashAttestation(att));
        return abi.encodePacked(r, s, v);
    }

    function _grant(uint256 key, bytes32 trustor, bytes32 trustee, TrustLevel level, bytes32 scope, uint64 nonce)
        internal
    {
        TrustAttestation memory att = _att(trustor, trustee, level, scope, 0, nonce);
        registry.setTrust(att, _sign(key, att));
    }

    function _params(uint8 maxLen, TrustLevel minEdge, bytes32 scope, bool enforceExpiry, bytes32[] memory anchors)
        internal
        pure
        returns (ValidationParams memory)
    {
        return ValidationParams({
            maxPathLength: maxLen,
            minEdgeTrust: minEdge,
            scope: scope,
            enforceExpiry: enforceExpiry,
            requiredAnchors: anchors
        });
    }

    function _defaultParams() internal pure returns (ValidationParams memory) {
        return _params(5, TrustLevel.Marginal, UNIVERSAL, true, new bytes32[](0));
    }

    function _anchored() internal pure returns (ValidationParams memory) {
        bytes32[] memory anchors = new bytes32[](1);
        anchors[0] = ANCHOR;
        return _params(5, TrustLevel.Marginal, UNIVERSAL, true, anchors);
    }

    function _path(bytes32[] memory nodes) internal pure returns (TrustPath memory) {
        return TrustPath({nodes: nodes});
    }

    function _nodes2(bytes32 a, bytes32 b) internal pure returns (bytes32[] memory n) {
        n = new bytes32[](2);
        (n[0], n[1]) = (a, b);
    }

    function _nodes3(bytes32 a, bytes32 b, bytes32 c) internal pure returns (bytes32[] memory n) {
        n = new bytes32[](3);
        (n[0], n[1], n[2]) = (a, b, c);
    }

    function _nodes4(bytes32 a, bytes32 b, bytes32 c, bytes32 d) internal pure returns (bytes32[] memory n) {
        n = new bytes32[](4);
        (n[0], n[1], n[2], n[3]) = (a, b, c, d);
    }

    function _signWith(TrustRegistry r, uint256 key, TrustAttestation memory att)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 rr, bytes32 ss) = vm.sign(key, r.hashAttestation(att));
        return abi.encodePacked(rr, ss, v);
    }

    /// @dev Put `node` under the NameWrapper with `controller_` as the ERC-1155 holder
    function _wrapName(bytes32 node, address controller_) internal {
        ens.setOwner(node, address(wrapper));
        wrapper.setWrappedOwner(node, controller_);
    }

    /// @dev Publish an ERC-137 forward address record for `node`
    function _bindAddr(bytes32 node, address a) internal {
        ens.setResolver(node, address(resolver));
        resolver.setAddr(node, a);
    }

    /// @dev Give ANCHOR a smart-wallet owner so it can attest, signed by `daveKey`
    function _anchorAttests(bytes32 trustee, uint64 nonce) internal {
        MockSmartWallet wallet = new MockSmartWallet(dave);
        ens.setOwner(ANCHOR, address(wallet));
        TrustAttestation memory att = _att(ANCHOR, trustee, TrustLevel.Full, UNIVERSAL, 0, nonce);
        registry.setTrust(att, _sign(daveKey, att));
    }

    // ───────────────────────────────────────────────────────────────────────────
    // setTrust
    // ───────────────────────────────────────────────────────────────────────────

    function test_SetTrust_StoresRecordAndBumpsNonce() public {
        TrustAttestation memory att = _att(ALICE, BOB, TrustLevel.Full, UNIVERSAL, 0, 1);

        vm.expectEmit(true, true, true, true);
        emit ITrustRegistry.TrustSet(ALICE, BOB, TrustLevel.Full, UNIVERSAL, 0);
        registry.setTrust(att, _sign(aliceKey, att));

        (TrustLevel level, uint64 expiry) = registry.getTrust(ALICE, BOB, UNIVERSAL);
        assertEq(uint8(level), uint8(TrustLevel.Full));
        assertEq(expiry, 0);
        assertEq(registry.getNonce(ALICE), 1);
    }

    function test_SetTrust_AnyoneMaySubmitAValidSignature() public {
        TrustAttestation memory att = _att(ALICE, BOB, TrustLevel.Full, UNIVERSAL, 0, 1);
        bytes memory sig = _sign(aliceKey, att);

        vm.prank(mallory); // untrusted relayer
        registry.setTrust(att, sig);

        (TrustLevel level,) = registry.getTrust(ALICE, BOB, UNIVERSAL);
        assertEq(uint8(level), uint8(TrustLevel.Full));
    }

    function test_SetTrust_RevertsOnSelfTrust() public {
        TrustAttestation memory att = _att(ALICE, ALICE, TrustLevel.Full, UNIVERSAL, 0, 1);
        bytes memory sig = _sign(aliceKey, att);

        vm.expectRevert(SelfTrustProhibited.selector);
        registry.setTrust(att, sig);
    }

    function test_SetTrust_RevertsOnStaleNonce() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 5);

        TrustAttestation memory att = _att(ALICE, CAROL, TrustLevel.Full, UNIVERSAL, 0, 5);
        bytes memory sig = _sign(aliceKey, att);

        vm.expectRevert(abi.encodeWithSelector(NonceTooLow.selector, uint64(5), uint64(6)));
        registry.setTrust(att, sig);
    }

    function test_SetTrust_RevertsOnExpiredAttestation() public {
        uint64 past = uint64(block.timestamp - 1);
        TrustAttestation memory att = _att(ALICE, BOB, TrustLevel.Full, UNIVERSAL, past, 1);
        bytes memory sig = _sign(aliceKey, att);

        vm.expectRevert(abi.encodeWithSelector(AttestationExpired.selector, past, uint64(block.timestamp)));
        registry.setTrust(att, sig);
    }

    function test_SetTrust_RevertsWhenENSNameMissing() public {
        TrustAttestation memory att = _att(GHOST, BOB, TrustLevel.Full, UNIVERSAL, 0, 1);
        bytes memory sig = _sign(aliceKey, att);

        vm.expectRevert(abi.encodeWithSelector(ENSNameNotFound.selector, GHOST));
        registry.setTrust(att, sig);
    }

    function test_SetTrust_RevertsOnWrongSigner() public {
        TrustAttestation memory att = _att(ALICE, BOB, TrustLevel.Full, UNIVERSAL, 0, 1);
        bytes memory sig = _sign(malloryKey, att);

        vm.expectRevert(InvalidSignature.selector);
        registry.setTrust(att, sig);
    }

    function test_SetTrust_RevertsOnMalformedSignature() public {
        TrustAttestation memory att = _att(ALICE, BOB, TrustLevel.Full, UNIVERSAL, 0, 1);
        vm.expectRevert(InvalidSignature.selector);
        registry.setTrust(att, hex"dead");
    }

    /// @dev ENS approvals grant submission rights, never signing authority
    function test_SetTrust_ApprovedOperatorCannotForgeSignature() public {
        vm.prank(alice);
        ens.setApprovalForAll(mallory, true);

        TrustAttestation memory att = _att(ALICE, BOB, TrustLevel.Full, UNIVERSAL, 0, 1);
        bytes memory sig = _sign(malloryKey, att);

        vm.prank(mallory);
        vm.expectRevert(InvalidSignature.selector);
        registry.setTrust(att, sig);
    }

    function test_SetTrust_ContractOwnerViaERC1271() public {
        MockSmartWallet wallet = new MockSmartWallet(bob);
        bytes32 node = keccak256("wallet.agents.eth");
        ens.setOwner(node, address(wallet));

        TrustAttestation memory att = _att(node, CAROL, TrustLevel.Full, UNIVERSAL, 0, 1);
        registry.setTrust(att, _sign(bobKey, att));

        (TrustLevel level,) = registry.getTrust(node, CAROL, UNIVERSAL);
        assertEq(uint8(level), uint8(TrustLevel.Full));
    }

    function test_SetTrust_ContractOwnerRejectsUnknownSigner() public {
        MockSmartWallet wallet = new MockSmartWallet(bob);
        bytes32 node = keccak256("wallet.agents.eth");
        ens.setOwner(node, address(wallet));

        TrustAttestation memory att = _att(node, CAROL, TrustLevel.Full, UNIVERSAL, 0, 1);
        bytes memory sig = _sign(malloryKey, att);

        vm.expectRevert(InvalidSignature.selector);
        registry.setTrust(att, sig);
    }

    /// @dev Scope is part of the storage key, so levels are independent per scope
    function test_SetTrust_ScopeIsPartOfTheKey() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, DEFI, 1);
        _grant(aliceKey, ALICE, BOB, TrustLevel.Marginal, GAMING, 2);

        (TrustLevel defi,) = registry.getTrust(ALICE, BOB, DEFI);
        (TrustLevel gaming,) = registry.getTrust(ALICE, BOB, GAMING);
        (TrustLevel universal,) = registry.getTrust(ALICE, BOB, UNIVERSAL);

        assertEq(uint8(defi), uint8(TrustLevel.Full));
        assertEq(uint8(gaming), uint8(TrustLevel.Marginal));
        assertEq(uint8(universal), uint8(TrustLevel.Unknown));
    }

    /// @dev Distrust is expressed by revokeTrust, never by an attestation. This keeps
    ///      one path, one event, and one authorisation rule per level.
    function test_SetTrust_RejectsNoneLevel() public {
        TrustAttestation memory att = _att(ALICE, BOB, TrustLevel.None, UNIVERSAL, 0, 1);
        bytes memory sig = _sign(aliceKey, att);

        vm.expectRevert(abi.encodeWithSelector(InvalidAttestationLevel.selector, TrustLevel.None));
        registry.setTrust(att, sig);
    }

    /// @dev Unknown is the default; an attestation must not be able to reassign it
    function test_SetTrust_RejectsUnknownLevel() public {
        TrustAttestation memory att = _att(ALICE, BOB, TrustLevel.Unknown, UNIVERSAL, 0, 1);
        bytes memory sig = _sign(aliceKey, att);

        vm.expectRevert(abi.encodeWithSelector(InvalidAttestationLevel.selector, TrustLevel.Unknown));
        registry.setTrust(att, sig);
    }

    /// @dev Revocation is not permanent: a later attestation restores trust
    function test_SetTrust_RestoresTrustAfterRevocation() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);

        vm.prank(alice);
        registry.revokeTrust(ALICE, BOB, UNIVERSAL, keccak256("MISBEHAVIOR"));

        _grant(aliceKey, ALICE, BOB, TrustLevel.Marginal, UNIVERSAL, 2);

        (TrustLevel level,) = registry.getTrust(ALICE, BOB, UNIVERSAL);
        assertEq(uint8(level), uint8(TrustLevel.Marginal));
    }

    // ───────────────────────────────────────────────────────────────────────────
    // setTrustBatch
    // ───────────────────────────────────────────────────────────────────────────

    function test_SetTrustBatch_AppliesAll() public {
        TrustAttestation[] memory atts = new TrustAttestation[](3);
        bytes[] memory sigs = new bytes[](3);
        atts[0] = _att(ALICE, BOB, TrustLevel.Full, UNIVERSAL, 0, 1);
        atts[1] = _att(ALICE, CAROL, TrustLevel.Marginal, UNIVERSAL, 0, 2);
        atts[2] = _att(ALICE, DAVE, TrustLevel.Full, DEFI, 0, 3);
        for (uint256 i = 0; i < 3; i++) {
            sigs[i] = _sign(aliceKey, atts[i]);
        }

        registry.setTrustBatch(atts, sigs);

        assertEq(registry.getNonce(ALICE), 3);
        (TrustLevel l0,) = registry.getTrust(ALICE, BOB, UNIVERSAL);
        (TrustLevel l2,) = registry.getTrust(ALICE, DAVE, DEFI);
        assertEq(uint8(l0), uint8(TrustLevel.Full));
        assertEq(uint8(l2), uint8(TrustLevel.Full));
    }

    function test_SetTrustBatch_RevertsOnLengthMismatch() public {
        TrustAttestation[] memory atts = new TrustAttestation[](2);
        bytes[] memory sigs = new bytes[](1);
        atts[0] = _att(ALICE, BOB, TrustLevel.Full, UNIVERSAL, 0, 1);
        atts[1] = _att(ALICE, CAROL, TrustLevel.Full, UNIVERSAL, 0, 2);
        sigs[0] = _sign(aliceKey, atts[0]);

        vm.expectRevert(BatchTrustorMismatch.selector);
        registry.setTrustBatch(atts, sigs);
    }

    function test_SetTrustBatch_RevertsOnMixedTrustors() public {
        TrustAttestation[] memory atts = new TrustAttestation[](2);
        bytes[] memory sigs = new bytes[](2);
        atts[0] = _att(ALICE, CAROL, TrustLevel.Full, UNIVERSAL, 0, 1);
        atts[1] = _att(BOB, CAROL, TrustLevel.Full, UNIVERSAL, 0, 2);
        sigs[0] = _sign(aliceKey, atts[0]);
        sigs[1] = _sign(bobKey, atts[1]);

        vm.expectRevert(BatchTrustorMismatch.selector);
        registry.setTrustBatch(atts, sigs);
    }

    function test_SetTrustBatch_RevertsOnNonIncreasingNonces() public {
        TrustAttestation[] memory atts = new TrustAttestation[](2);
        bytes[] memory sigs = new bytes[](2);
        atts[0] = _att(ALICE, BOB, TrustLevel.Full, UNIVERSAL, 0, 2);
        atts[1] = _att(ALICE, CAROL, TrustLevel.Full, UNIVERSAL, 0, 2);
        sigs[0] = _sign(aliceKey, atts[0]);
        sigs[1] = _sign(aliceKey, atts[1]);

        vm.expectRevert(BatchNonceNotIncreasing.selector);
        registry.setTrustBatch(atts, sigs);
    }

    // ───────────────────────────────────────────────────────────────────────────
    // revokeTrust
    // ───────────────────────────────────────────────────────────────────────────

    function test_RevokeTrust_SetsNoneAndRetainsRecord() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);

        bytes32 reason = keccak256("MISBEHAVIOR");
        vm.expectEmit(true, true, true, true);
        emit ITrustRegistry.TrustRevoked(ALICE, BOB, UNIVERSAL, reason);
        vm.prank(alice);
        registry.revokeTrust(ALICE, BOB, UNIVERSAL, reason);

        (TrustLevel level,) = registry.getTrust(ALICE, BOB, UNIVERSAL);
        assertEq(uint8(level), uint8(TrustLevel.None), "explicit distrust must be retained, not deleted");
    }

    function test_RevokeTrust_ApprovedOperatorMaySubmit() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);

        vm.prank(alice);
        ens.setApprovalForAll(mallory, true);

        vm.prank(mallory);
        registry.revokeTrust(ALICE, BOB, UNIVERSAL, bytes32(0));

        (TrustLevel level,) = registry.getTrust(ALICE, BOB, UNIVERSAL);
        assertEq(uint8(level), uint8(TrustLevel.None));
    }

    function test_RevokeTrust_RevertsForStranger() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);

        vm.prank(mallory);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, ALICE, mallory));
        registry.revokeTrust(ALICE, BOB, UNIVERSAL, bytes32(0));
    }

    /// @dev Preemptive distrust: no prior trust relationship is required
    function test_RevokeTrust_WorksWithoutPriorTrust() public {
        (TrustLevel before,) = registry.getTrust(ALICE, BOB, UNIVERSAL);
        assertEq(uint8(before), uint8(TrustLevel.Unknown));

        vm.prank(alice);
        registry.revokeTrust(ALICE, BOB, UNIVERSAL, keccak256("MISBEHAVIOR"));

        (TrustLevel level,) = registry.getTrust(ALICE, BOB, UNIVERSAL);
        assertEq(uint8(level), uint8(TrustLevel.None));
    }

    /// @dev Preemptive distrust is useful: it blocks paths routing through that edge
    function test_RevokeTrust_PreemptiveDistrustBlocksPath() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);
        _grant(bobKey, BOB, CAROL, TrustLevel.Full, UNIVERSAL, 1);
        assertTrue(registry.verifyPath(_path(_nodes3(ALICE, BOB, CAROL)), _defaultParams()));

        // Bob never trusted Carol in DEFI, but distrusts her preemptively there
        vm.prank(bob);
        registry.revokeTrust(BOB, CAROL, DEFI, keccak256("MISBEHAVIOR"));

        ValidationParams memory defi = _params(5, TrustLevel.Marginal, DEFI, true, new bytes32[](0));
        assertFalse(
            registry.verifyPath(_path(_nodes3(ALICE, BOB, CAROL)), defi),
            "scoped distrust must block the universal fallback"
        );
    }

    /// @dev Revocation is per-scope: revoking universal leaves scoped grants intact
    function test_RevokeTrust_IsScopeSpecific() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, DEFI, 2);

        vm.prank(alice);
        registry.revokeTrust(ALICE, BOB, UNIVERSAL, bytes32(0));

        (TrustLevel universal,) = registry.getTrust(ALICE, BOB, UNIVERSAL);
        (TrustLevel defi,) = registry.getTrust(ALICE, BOB, DEFI);
        assertEq(uint8(universal), uint8(TrustLevel.None));
        assertEq(uint8(defi), uint8(TrustLevel.Full));
    }

    // ───────────────────────────────────────────────────────────────────────────
    // verifyPath
    // ───────────────────────────────────────────────────────────────────────────

    function test_VerifyPath_DirectEdge() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);
        assertTrue(registry.verifyPath(_path(_nodes2(ALICE, BOB)), _defaultParams()));
    }

    function test_VerifyPath_TransitiveChain() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);
        _grant(bobKey, BOB, CAROL, TrustLevel.Marginal, UNIVERSAL, 1);
        _grant(carolKey, CAROL, DAVE, TrustLevel.Full, UNIVERSAL, 1);

        assertTrue(registry.verifyPath(_path(_nodes4(ALICE, BOB, CAROL, DAVE)), _defaultParams()));
    }

    function test_VerifyPath_RejectsMissingEdge() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);
        assertFalse(registry.verifyPath(_path(_nodes3(ALICE, BOB, CAROL)), _defaultParams()));
    }

    function test_VerifyPath_RejectsPathShorterThanTwoNodes() public view {
        bytes32[] memory one = new bytes32[](1);
        one[0] = ALICE;
        assertFalse(registry.verifyPath(_path(one), _defaultParams()));
    }

    function test_VerifyPath_RejectsPathLongerThanMax() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);
        _grant(bobKey, BOB, CAROL, TrustLevel.Full, UNIVERSAL, 1);

        ValidationParams memory p = _params(1, TrustLevel.Marginal, UNIVERSAL, true, new bytes32[](0));
        assertFalse(registry.verifyPath(_path(_nodes3(ALICE, BOB, CAROL)), p), "2 edges must fail maxPathLength 1");
        assertTrue(registry.verifyPath(_path(_nodes2(ALICE, BOB)), p), "1 edge must pass maxPathLength 1");
    }

    function test_VerifyPath_RejectsMarginalWhenFullRequired() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Marginal, UNIVERSAL, 1);

        assertTrue(registry.verifyPath(_path(_nodes2(ALICE, BOB)), _defaultParams()));
        ValidationParams memory strict = _params(5, TrustLevel.Full, UNIVERSAL, true, new bytes32[](0));
        assertFalse(registry.verifyPath(_path(_nodes2(ALICE, BOB)), strict));
    }

    function test_VerifyPath_RevokedEdgeVoidsPath() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);
        _grant(bobKey, BOB, CAROL, TrustLevel.Full, UNIVERSAL, 1);
        assertTrue(registry.verifyPath(_path(_nodes3(ALICE, BOB, CAROL)), _defaultParams()));

        vm.prank(bob);
        registry.revokeTrust(BOB, CAROL, UNIVERSAL, keccak256("COMPROMISED"));

        assertFalse(registry.verifyPath(_path(_nodes3(ALICE, BOB, CAROL)), _defaultParams()));
    }

    function test_VerifyPath_ExpiryEnforcement() public {
        uint64 expiry = uint64(block.timestamp + 100);
        TrustAttestation memory att = _att(ALICE, BOB, TrustLevel.Full, UNIVERSAL, expiry, 1);
        registry.setTrust(att, _sign(aliceKey, att));

        assertTrue(registry.verifyPath(_path(_nodes2(ALICE, BOB)), _defaultParams()));

        vm.warp(block.timestamp + 101);
        assertFalse(registry.verifyPath(_path(_nodes2(ALICE, BOB)), _defaultParams()));

        ValidationParams memory lax = _params(5, TrustLevel.Marginal, UNIVERSAL, false, new bytes32[](0));
        assertTrue(registry.verifyPath(_path(_nodes2(ALICE, BOB)), lax), "expired edge passes when enforceExpiry off");
    }

    function test_VerifyPath_ScopeFallsBackToUniversal() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);

        ValidationParams memory defi = _params(5, TrustLevel.Marginal, DEFI, true, new bytes32[](0));
        assertTrue(registry.verifyPath(_path(_nodes2(ALICE, BOB)), defi), "universal trust must apply to all scopes");
    }

    function test_VerifyPath_ScopedTrustTakesPrecedenceOverUniversal() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);
        _grant(aliceKey, ALICE, BOB, TrustLevel.Marginal, DEFI, 2);

        ValidationParams memory strictDefi = _params(5, TrustLevel.Full, DEFI, true, new bytes32[](0));
        assertFalse(
            registry.verifyPath(_path(_nodes2(ALICE, BOB)), strictDefi),
            "scoped Marginal must be used, not universal Full"
        );
    }

    function test_VerifyPath_ScopedRevocationOverridesUniversalTrust() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, DEFI, 2);

        vm.prank(alice);
        registry.revokeTrust(ALICE, BOB, DEFI, keccak256("MISBEHAVIOR"));

        ValidationParams memory defi = _params(5, TrustLevel.Marginal, DEFI, true, new bytes32[](0));
        assertFalse(registry.verifyPath(_path(_nodes2(ALICE, BOB)), defi));
        assertTrue(registry.verifyPath(_path(_nodes2(ALICE, BOB)), _defaultParams()), "universal scope unaffected");
    }

    function test_VerifyPath_RevertsOnInvalidParams() public {
        bytes32[] memory none = new bytes32[](0);
        TrustPath memory p = _path(_nodes2(ALICE, BOB));

        vm.expectRevert(abi.encodeWithSelector(InvalidMaxPathLength.selector, uint8(0)));
        registry.verifyPath(p, _params(0, TrustLevel.Marginal, UNIVERSAL, true, none));

        vm.expectRevert(abi.encodeWithSelector(InvalidMaxPathLength.selector, uint8(11)));
        registry.verifyPath(p, _params(11, TrustLevel.Marginal, UNIVERSAL, true, none));

        vm.expectRevert(abi.encodeWithSelector(InvalidMinEdgeTrust.selector, TrustLevel.Unknown));
        registry.verifyPath(p, _params(5, TrustLevel.Unknown, UNIVERSAL, true, none));

        vm.expectRevert(abi.encodeWithSelector(InvalidMinEdgeTrust.selector, TrustLevel.None));
        registry.verifyPath(p, _params(5, TrustLevel.None, UNIVERSAL, true, none));

        vm.expectRevert(abi.encodeWithSelector(TooManyRequiredAnchors.selector, uint256(11)));
        registry.verifyPath(p, _params(5, TrustLevel.Marginal, UNIVERSAL, true, new bytes32[](11)));
    }

    /// @dev Repeated nodes cannot manufacture trust, but they inflate path length and
    ///      serve no purpose, so they are rejected outright
    function test_VerifyPath_RejectsRepeatedNodes() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);
        _grant(bobKey, BOB, ALICE, TrustLevel.Full, UNIVERSAL, 1);
        _grant(aliceKey, ALICE, CAROL, TrustLevel.Full, UNIVERSAL, 2);

        // Every edge of [ALICE, BOB, ALICE, CAROL] exists...
        assertTrue(registry.verifyPath(_path(_nodes2(ALICE, BOB)), _defaultParams()));
        assertTrue(registry.verifyPath(_path(_nodes2(BOB, ALICE)), _defaultParams()));
        assertTrue(registry.verifyPath(_path(_nodes2(ALICE, CAROL)), _defaultParams()));

        // ...but ALICE appears twice, so the path is rejected
        assertFalse(registry.verifyPath(_path(_nodes4(ALICE, BOB, ALICE, CAROL)), _defaultParams()));
    }

    function test_VerifyPath_RejectsAdjacentDuplicate() public view {
        assertFalse(registry.verifyPath(_path(_nodes2(ALICE, ALICE)), _defaultParams()));
    }

    /// @dev Acceptance for parameter validation. `minEdgeTrust == Unknown` makes the
    ///      per-edge test `level < minEdgeTrust` vacuously false, so without validation
    ///      a path with no trust whatsoever would verify as true.
    function test_VerifyPath_InvalidMinEdgeTrustCannotForceTrue() public {
        (TrustLevel level,) = registry.getTrust(ALICE, BOB, UNIVERSAL);
        assertEq(uint8(level), uint8(TrustLevel.Unknown), "no trust exists");

        ValidationParams memory bad = _params(5, TrustLevel.Unknown, UNIVERSAL, true, new bytes32[](0));

        vm.expectRevert(abi.encodeWithSelector(InvalidMinEdgeTrust.selector, TrustLevel.Unknown));
        registry.verifyPath(_path(_nodes2(ALICE, BOB)), bad);
    }

    /// @dev The same routine guards setIdentityGate, so a gate can never store the
    ///      parameters that would make the above bypass reachable
    function test_SetIdentityGate_RejectsSameInvalidParamsAsVerifyPath() public {
        ValidationParams memory bad = _params(5, TrustLevel.Unknown, UNIVERSAL, true, new bytes32[](0));

        vm.prank(coordinator);
        vm.expectRevert(abi.encodeWithSelector(InvalidMinEdgeTrust.selector, TrustLevel.Unknown));
        registry.setIdentityGate(MEV_COORDINATION, ALICE, bad);
    }

    // ───────────────────────────────────────────────────────────────────────────
    // verifyPath - required anchors
    // Regression: anchors are part of the verdict, not a second advisory return
    // ───────────────────────────────────────────────────────────────────────────

    /// @dev A path whose edges all verify but which misses every required anchor
    ///      MUST report invalid.
    function test_VerifyPath_AnchorMissIsInvalidNotPartialSuccess() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);
        _grant(bobKey, BOB, CAROL, TrustLevel.Full, UNIVERSAL, 1);

        assertTrue(registry.verifyPath(_path(_nodes3(ALICE, BOB, CAROL)), _defaultParams()), "edges are sound");
        assertFalse(registry.verifyPath(_path(_nodes3(ALICE, BOB, CAROL)), _anchored()), "but the anchor is missing");
    }

    function test_VerifyPath_AnchorAsIntermediarySucceeds() public {
        _grant(aliceKey, ALICE, ANCHOR, TrustLevel.Full, UNIVERSAL, 1);
        _anchorAttests(CAROL, 1);

        assertTrue(registry.verifyPath(_path(_nodes3(ALICE, ANCHOR, CAROL)), _anchored()));
    }

    /// @dev The validator itself is not an intermediary and cannot satisfy anchors
    function test_VerifyPath_ValidatorCannotSatisfyAnchor() public {
        _anchorAttests(BOB, 1);
        assertFalse(registry.verifyPath(_path(_nodes2(ANCHOR, BOB)), _anchored()));
    }

    /// @dev The target is not an intermediary either
    function test_VerifyPath_TargetCannotSatisfyAnchor() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);
        _grant(bobKey, BOB, ANCHOR, TrustLevel.Full, UNIVERSAL, 1);

        assertFalse(registry.verifyPath(_path(_nodes3(ALICE, BOB, ANCHOR)), _anchored()));
    }

    // ───────────────────────────────────────────────────────────────────────────
    // Identity gates
    // ───────────────────────────────────────────────────────────────────────────

    function _setGate(ValidationParams memory p) internal {
        vm.prank(coordinator);
        registry.setIdentityGate(MEV_COORDINATION, ALICE, p);
    }

    function test_SetIdentityGate_StoresConfiguration() public {
        vm.expectEmit(true, true, true, true);
        emit ITrustRegistry.IdentityGateSet(
            coordinator, MEV_COORDINATION, ALICE, 5, TrustLevel.Marginal, UNIVERSAL, true, new bytes32[](0)
        );
        _setGate(_defaultParams());

        (bytes32 gatekeeper, ValidationParams memory p, bool enabled) = registry.getIdentityGate(coordinator, MEV_COORDINATION);
        assertEq(gatekeeper, ALICE);
        assertEq(p.maxPathLength, 5);
        assertTrue(enabled);
    }

    /// @dev Gates are keyed by caller, so the same coordination type held by two
    ///      coordinators is two independent gates. Well-known constants cannot be
    ///      squatted.
    function test_SetIdentityGate_NamespacedByCaller() public {
        _setGate(_defaultParams());

        vm.prank(otherCoordinator);
        registry.setIdentityGate(MEV_COORDINATION, BOB, _defaultParams());

        (bytes32 mine,, bool mineEnabled) = registry.getIdentityGate(coordinator, MEV_COORDINATION);
        (bytes32 theirs,, bool theirsEnabled) = registry.getIdentityGate(otherCoordinator, MEV_COORDINATION);

        assertEq(mine, ALICE);
        assertEq(theirs, BOB);
        assertTrue(mineEnabled);
        assertTrue(theirsEnabled);
    }

    /// @dev One coordinator cannot delete another's gate; it only clears its own slot
    function test_RemoveIdentityGate_CannotAffectAnotherCoordinator() public {
        _setGate(_defaultParams());

        vm.prank(otherCoordinator);
        vm.expectRevert(abi.encodeWithSelector(GateNotFound.selector, MEV_COORDINATION));
        registry.removeIdentityGate(MEV_COORDINATION);

        (,, bool stillEnabled) = registry.getIdentityGate(coordinator, MEV_COORDINATION);
        assertTrue(stillEnabled, "another coordinator must not affect this gate");
    }

    /// @dev Naming a gatekeeper only reads that agent's public attestations, so it
    ///      deliberately does not require controlling the name
    function test_SetIdentityGate_DoesNotRequireControlOfGatekeeper() public {
        vm.prank(mallory);
        registry.setIdentityGate(MEV_COORDINATION, ALICE, _defaultParams());

        (bytes32 gatekeeper,, bool enabled) = registry.getIdentityGate(mallory, MEV_COORDINATION);
        assertEq(gatekeeper, ALICE);
        assertTrue(enabled);
    }

    /// @dev Reading a gate under the wrong coordinator yields an unconfigured gate,
    ///      and an unconfigured gate is OPEN
    function test_UnknownCoordinatorGateIsOpen() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);
        _setGate(_anchored()); // this gate would reject the path below

        assertFalse(
            registry.validateParticipantWithPath(coordinator, MEV_COORDINATION, BOB, _path(_nodes2(ALICE, BOB))),
            "the configured gate rejects"
        );
        assertTrue(
            registry.validateParticipantWithPath(otherCoordinator, MEV_COORDINATION, BOB, _path(_nodes2(ALICE, BOB))),
            "an unconfigured coordinator namespace is open"
        );
    }

    function test_SetIdentityGate_RevertsOnInvalidParams() public {
        vm.prank(coordinator);
        vm.expectRevert(abi.encodeWithSelector(InvalidMaxPathLength.selector, uint8(0)));
        registry.setIdentityGate(
            MEV_COORDINATION, ALICE, _params(0, TrustLevel.Marginal, UNIVERSAL, true, new bytes32[](0))
        );
    }

    function test_RemoveIdentityGate() public {
        _setGate(_defaultParams());

        vm.expectEmit(true, true, true, true);
        emit ITrustRegistry.IdentityGateRemoved(coordinator, MEV_COORDINATION);
        vm.prank(coordinator);
        registry.removeIdentityGate(MEV_COORDINATION);

        (,, bool enabled) = registry.getIdentityGate(coordinator, MEV_COORDINATION);
        assertFalse(enabled);
    }

    function test_RemoveIdentityGate_RevertsWhenAbsent() public {
        vm.prank(coordinator);
        vm.expectRevert(abi.encodeWithSelector(GateNotFound.selector, MEV_COORDINATION));
        registry.removeIdentityGate(MEV_COORDINATION);
    }

    // ───────────────────────────────────────────────────────────────────────────
    // validateParticipantWithPath
    // Regression: the verdict is bound to participantNode
    // ───────────────────────────────────────────────────────────────────────────

    function test_ValidateParticipant_OpenWhenNoGate() public view {
        assertTrue(registry.validateParticipantWithPath(coordinator, MEV_COORDINATION, DAVE, _path(_nodes2(ALICE, DAVE))));
    }

    function test_ValidateParticipant_AcceptsGatedPath() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);
        _grant(bobKey, BOB, CAROL, TrustLevel.Full, UNIVERSAL, 1);
        _setGate(_defaultParams());

        assertTrue(registry.validateParticipantWithPath(coordinator, MEV_COORDINATION, CAROL, _path(_nodes3(ALICE, BOB, CAROL))));
    }

    function test_ValidateParticipant_RejectsPathNotStartingAtGatekeeper() public {
        _grant(bobKey, BOB, CAROL, TrustLevel.Full, UNIVERSAL, 1);
        _setGate(_defaultParams());

        assertFalse(registry.validateParticipantWithPath(coordinator, MEV_COORDINATION, CAROL, _path(_nodes2(BOB, CAROL))));
    }

    /// @dev Core regression. A sound path from the gatekeeper to CAROL says nothing
    ///      about DAVE, and MUST NOT admit DAVE to the coordination.
    function test_ValidateParticipant_RejectsPathEndingAtSomeoneElse() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);
        _grant(bobKey, BOB, CAROL, TrustLevel.Full, UNIVERSAL, 1);
        _setGate(_defaultParams());

        TrustPath memory soundPath = _path(_nodes3(ALICE, BOB, CAROL));

        assertTrue(registry.validateParticipantWithPath(coordinator, MEV_COORDINATION, CAROL, soundPath), "valid for CAROL");
        assertFalse(
            registry.validateParticipantWithPath(coordinator, MEV_COORDINATION, DAVE, soundPath),
            "the same path must not admit DAVE"
        );
    }

    function test_ValidateParticipant_RejectsWhenGateAnchorMissing() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);
        _grant(bobKey, BOB, CAROL, TrustLevel.Full, UNIVERSAL, 1);
        _setGate(_anchored());

        assertFalse(registry.validateParticipantWithPath(coordinator, MEV_COORDINATION, CAROL, _path(_nodes3(ALICE, BOB, CAROL))));
    }

    function test_ValidateParticipant_RejectsRevokedParticipant() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);
        _grant(bobKey, BOB, CAROL, TrustLevel.Full, UNIVERSAL, 1);
        _setGate(_defaultParams());

        vm.prank(bob);
        registry.revokeTrust(BOB, CAROL, UNIVERSAL, keccak256("MISBEHAVIOR"));

        assertFalse(registry.validateParticipantWithPath(coordinator, MEV_COORDINATION, CAROL, _path(_nodes3(ALICE, BOB, CAROL))));
    }

    // ───────────────────────────────────────────────────────────────────────────
    // revokeTrustBatch
    // ───────────────────────────────────────────────────────────────────────────

    function _scopes3() internal pure returns (bytes32[] memory sc) {
        sc = new bytes32[](3);
        (sc[0], sc[1], sc[2]) = (UNIVERSAL, DEFI, GAMING);
    }

    function _grantThreeScopes() internal {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, DEFI, 2);
        _grant(aliceKey, ALICE, BOB, TrustLevel.Marginal, GAMING, 3);
    }

    function test_RevokeTrustBatch_RevokesEveryListedScope() public {
        _grantThreeScopes();

        vm.prank(alice);
        registry.revokeTrustBatch(ALICE, BOB, _scopes3(), keccak256("COMPROMISED"));

        (TrustLevel u,) = registry.getTrust(ALICE, BOB, UNIVERSAL);
        (TrustLevel d,) = registry.getTrust(ALICE, BOB, DEFI);
        (TrustLevel g,) = registry.getTrust(ALICE, BOB, GAMING);
        assertEq(uint8(u), uint8(TrustLevel.None));
        assertEq(uint8(d), uint8(TrustLevel.None));
        assertEq(uint8(g), uint8(TrustLevel.None));
    }

    function test_RevokeTrustBatch_LeavesUnlistedScopesIntact() public {
        _grantThreeScopes();

        bytes32[] memory only = new bytes32[](1);
        only[0] = DEFI;

        vm.prank(alice);
        registry.revokeTrustBatch(ALICE, BOB, only, bytes32(0));

        (TrustLevel d,) = registry.getTrust(ALICE, BOB, DEFI);
        (TrustLevel g,) = registry.getTrust(ALICE, BOB, GAMING);
        assertEq(uint8(d), uint8(TrustLevel.None));
        assertEq(uint8(g), uint8(TrustLevel.Marginal), "unlisted scopes are untouched");
    }

    function test_RevokeTrustBatch_ApprovedOperatorMaySubmit() public {
        _grantThreeScopes();

        vm.prank(alice);
        ens.setApprovalForAll(mallory, true);

        vm.prank(mallory);
        registry.revokeTrustBatch(ALICE, BOB, _scopes3(), bytes32(0));

        (TrustLevel u,) = registry.getTrust(ALICE, BOB, UNIVERSAL);
        assertEq(uint8(u), uint8(TrustLevel.None));
    }

    function test_RevokeTrustBatch_RevertsForStranger() public {
        _grantThreeScopes();

        vm.prank(mallory);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, ALICE, mallory));
        registry.revokeTrustBatch(ALICE, BOB, _scopes3(), bytes32(0));
    }

    function test_RevokeTrustBatch_RevertsOnEmptyScopeList() public {
        _grantThreeScopes();

        vm.prank(alice);
        vm.expectRevert(EmptyScopeList.selector);
        registry.revokeTrustBatch(ALICE, BOB, new bytes32[](0), bytes32(0));
    }

    /// @dev One TrustRevoked per listed scope, including never-granted ones
    function test_RevokeTrustBatch_EmitsOneEventPerScope() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);
        // DEFI and GAMING were never granted; they are distrusted preemptively

        vm.recordLogs();
        vm.prank(alice);
        registry.revokeTrustBatch(ALICE, BOB, _scopes3(), keccak256("COMPROMISED"));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("TrustRevoked(bytes32,bytes32,bytes32,bytes32)");
        uint256 count;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == topic) count++;
        }
        assertEq(count, 3, "one TrustRevoked per listed scope");
    }

    /// @dev A batch may mix withdrawing trust with preemptive distrust
    function test_RevokeTrustBatch_CoversNeverGrantedScopes() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);

        bytes32[] memory sc = new bytes32[](2);
        (sc[0], sc[1]) = (UNIVERSAL, DEFI); // DEFI was never granted

        vm.prank(alice);
        registry.revokeTrustBatch(ALICE, BOB, sc, keccak256("COMPROMISED"));

        (TrustLevel u,) = registry.getTrust(ALICE, BOB, UNIVERSAL);
        (TrustLevel d,) = registry.getTrust(ALICE, BOB, DEFI);
        assertEq(uint8(u), uint8(TrustLevel.None));
        assertEq(uint8(d), uint8(TrustLevel.None), "never-granted scopes are distrusted too");
    }

    // ───────────────────────────────────────────────────────────────────────────
    // invalidateNonces
    // ───────────────────────────────────────────────────────────────────────────

    function test_InvalidateNonces_RaisesFloor() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);

        vm.expectEmit(true, true, true, true);
        emit ITrustRegistry.NoncesInvalidated(ALICE, 100);
        vm.prank(alice);
        registry.invalidateNonces(ALICE, 100);

        assertEq(registry.getNonce(ALICE), 100);
    }

    function test_InvalidateNonces_RevertsOnNonIncreasing() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 5);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NonceTooLow.selector, uint64(5), uint64(6)));
        registry.invalidateNonces(ALICE, 5);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NonceTooLow.selector, uint64(4), uint64(6)));
        registry.invalidateNonces(ALICE, 4);
    }

    function test_InvalidateNonces_RevertsForStranger() public {
        vm.prank(mallory);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, ALICE, mallory));
        registry.invalidateNonces(ALICE, 100);
    }

    /// @dev Controller-only. An approved operator may revoke relationships, whose effect
    ///      is bounded to one trustee, but MUST NOT void the trustor's entire
    ///      outstanding attestation set.
    function test_InvalidateNonces_RejectsApprovedOperator() public {
        vm.prank(alice);
        ens.setApprovalForAll(mallory, true);

        // The same operator CAN revoke a relationship...
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);
        vm.prank(mallory);
        registry.revokeTrust(ALICE, BOB, UNIVERSAL, bytes32(0));

        // ...but MUST NOT invalidate nonces trustor-wide
        vm.prank(mallory);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, ALICE, mallory));
        registry.invalidateNonces(ALICE, 42);

        assertEq(registry.getNonce(ALICE), 1, "floor unchanged");
    }

    function test_InvalidateNonces_ControllerMaySubmit() public {
        vm.prank(alice);
        registry.invalidateNonces(ALICE, 42);
        assertEq(registry.getNonce(ALICE), 42);
    }

    /// @dev For a wrapped name the controller is the NameWrapper holder, not the
    ///      registry owner, and operators approved on the wrapper are still rejected
    function test_InvalidateNonces_WrappedNameControllerOnly() public {
        _wrapName(WRAPPED, alice);

        vm.prank(alice);
        wrapper.setApprovalForAll(mallory, true);

        vm.prank(mallory);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, WRAPPED, mallory));
        registry.invalidateNonces(WRAPPED, 42);

        vm.prank(alice);
        registry.invalidateNonces(WRAPPED, 42);
        assertEq(registry.getNonce(WRAPPED), 42);
    }

    /// @dev Documents the hazard in Security Considerations: an attestation signed
    ///      before a revocation stays submittable and restores trust afterwards.
    function test_PreSignedAttestationSurvivesRevocationAlone() public {
        TrustAttestation memory pending = _att(ALICE, BOB, TrustLevel.Full, UNIVERSAL, 0, 10);
        bytes memory pendingSig = _sign(aliceKey, pending);

        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);

        vm.prank(alice);
        registry.revokeTrust(ALICE, BOB, UNIVERSAL, keccak256("COMPROMISED"));
        (TrustLevel revoked,) = registry.getTrust(ALICE, BOB, UNIVERSAL);
        assertEq(uint8(revoked), uint8(TrustLevel.None));

        // Revocation did not retract the earlier signature
        registry.setTrust(pending, pendingSig);
        (TrustLevel restored,) = registry.getTrust(ALICE, BOB, UNIVERSAL);
        assertEq(uint8(restored), uint8(TrustLevel.Full), "revocation alone is not enough");
    }

    /// @dev The fix: raising the nonce floor above every signed nonce closes it
    function test_InvalidateNonces_PreventsPostRevocationRestore() public {
        TrustAttestation memory pending = _att(ALICE, BOB, TrustLevel.Full, UNIVERSAL, 0, 10);
        bytes memory pendingSig = _sign(aliceKey, pending);

        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);

        vm.startPrank(alice);
        registry.revokeTrust(ALICE, BOB, UNIVERSAL, keccak256("COMPROMISED"));
        registry.invalidateNonces(ALICE, 10);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(NonceTooLow.selector, uint64(10), uint64(11)));
        registry.setTrust(pending, pendingSig);

        (TrustLevel level,) = registry.getTrust(ALICE, BOB, UNIVERSAL);
        assertEq(uint8(level), uint8(TrustLevel.None), "distrust holds");
    }

    /// @dev The floor is trustor-wide, not per trustee or scope
    function test_InvalidateNonces_IsTrustorWide() public {
        TrustAttestation memory forCarol = _att(ALICE, CAROL, TrustLevel.Full, DEFI, 0, 7);
        bytes memory sig = _sign(aliceKey, forCarol);

        vm.prank(alice);
        registry.invalidateNonces(ALICE, 20);

        vm.expectRevert(abi.encodeWithSelector(NonceTooLow.selector, uint64(7), uint64(21)));
        registry.setTrust(forCarol, sig);
    }

    /// @dev Attestations above the new floor still work, so the trustor can re-grant
    function test_InvalidateNonces_AllowsFreshAttestationsAbove() public {
        vm.prank(alice);
        registry.invalidateNonces(ALICE, 50);

        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 51);

        (TrustLevel level,) = registry.getTrust(ALICE, BOB, UNIVERSAL);
        assertEq(uint8(level), uint8(TrustLevel.Full));
        assertEq(registry.getNonce(ALICE), 51);
    }

    // ───────────────────────────────────────────────────────────────────────────
    // NameWrapper
    // ───────────────────────────────────────────────────────────────────────────

    bytes32 internal constant WRAPPED = keccak256("wrapped.agents.eth");

    /// @dev Core fix. `ens.owner` returns the NameWrapper for wrapped names, and
    ///      NameWrapper has no EIP-1271, so without unwrapping this would revert.
    function test_NameWrapper_WrappedNameCanAttest() public {
        _wrapName(WRAPPED, alice);

        TrustAttestation memory att = _att(WRAPPED, BOB, TrustLevel.Full, UNIVERSAL, 0, 1);
        registry.setTrust(att, _sign(aliceKey, att));

        (TrustLevel level,) = registry.getTrust(WRAPPED, BOB, UNIVERSAL);
        assertEq(uint8(level), uint8(TrustLevel.Full));
    }

    /// @dev EIP-1271 still applies after unwrapping, when the holder is a contract
    function test_NameWrapper_UnwrappedControllerMayBeAContract() public {
        MockSmartWallet holder = new MockSmartWallet(bob);
        _wrapName(WRAPPED, address(holder));

        TrustAttestation memory att = _att(WRAPPED, CAROL, TrustLevel.Full, UNIVERSAL, 0, 1);
        registry.setTrust(att, _sign(bobKey, att));

        (TrustLevel level,) = registry.getTrust(WRAPPED, CAROL, UNIVERSAL);
        assertEq(uint8(level), uint8(TrustLevel.Full));
    }

    /// @dev NameWrapper returns address(0) for an expired wrapped name
    function test_NameWrapper_ExpiredNameHasNoAuthority() public {
        _wrapName(WRAPPED, address(0));

        TrustAttestation memory att = _att(WRAPPED, BOB, TrustLevel.Full, UNIVERSAL, 0, 1);
        bytes memory sig = _sign(aliceKey, att);

        vm.expectRevert(abi.encodeWithSelector(ENSNameNotFound.selector, WRAPPED));
        registry.setTrust(att, sig);
    }

    /// @dev Operator approvals for a wrapped name live on the NameWrapper
    function test_NameWrapper_ApprovalsRouteThroughWrapper() public {
        _wrapName(WRAPPED, alice);
        TrustAttestation memory att = _att(WRAPPED, BOB, TrustLevel.Full, UNIVERSAL, 0, 1);
        registry.setTrust(att, _sign(aliceKey, att));

        vm.prank(alice);
        wrapper.setApprovalForAll(mallory, true);

        vm.prank(mallory);
        registry.revokeTrust(WRAPPED, BOB, UNIVERSAL, keccak256("MISBEHAVIOR"));

        (TrustLevel level,) = registry.getTrust(WRAPPED, BOB, UNIVERSAL);
        assertEq(uint8(level), uint8(TrustLevel.None));
    }

    /// @dev A registry-level approval must NOT authorise a wrapped name
    function test_NameWrapper_RegistryApprovalDoesNotAuthoriseWrappedName() public {
        _wrapName(WRAPPED, alice);
        TrustAttestation memory att = _att(WRAPPED, BOB, TrustLevel.Full, UNIVERSAL, 0, 1);
        registry.setTrust(att, _sign(aliceKey, att));

        vm.prank(alice);
        ens.setApprovalForAll(mallory, true); // wrong contract for a wrapped name

        vm.prank(mallory);
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector, WRAPPED, mallory));
        registry.revokeTrust(WRAPPED, BOB, UNIVERSAL, bytes32(0));
    }

    /// @dev Networks with no NameWrapper deployment pass address(0) and never unwrap
    function test_NameWrapper_DisabledWhenZero() public {
        TrustRegistry plain = new TrustRegistry(address(ens), address(0));
        _wrapName(WRAPPED, alice);

        TrustAttestation memory att = _att(WRAPPED, BOB, TrustLevel.Full, UNIVERSAL, 0, 1);
        bytes memory sig = _signWith(plain, aliceKey, att);

        // Controller stays the NameWrapper contract, which has no EIP-1271
        vm.expectRevert(InvalidSignature.selector);
        plain.setTrust(att, sig);
    }

    // ───────────────────────────────────────────────────────────────────────────
    // Agent address resolution
    // ───────────────────────────────────────────────────────────────────────────

    function test_ResolveAgent_ZeroWithoutResolver() public view {
        assertEq(registry.resolveAgent(CAROL), address(0));
    }

    function test_ResolveAgent_ReturnsAddrRecord() public {
        _bindAddr(CAROL, carol);
        assertEq(registry.resolveAgent(CAROL), carol);
    }

    /// @dev An off-chain (CCIP-Read) resolver reverts on-chain; resolution fails closed
    function test_ResolveAgent_ZeroWhenResolverReverts() public {
        ens.setResolver(CAROL, address(new RevertingResolver()));
        assertEq(registry.resolveAgent(CAROL), address(0));
    }

    // ───────────────────────────────────────────────────────────────────────────
    // validateParticipantAddress - the ERC-8001 hook
    // ───────────────────────────────────────────────────────────────────────────

    /// @dev Trust chain ALICE -> BOB -> CAROL, with CAROL bound to the carol address
    function _gatedChainToCarol() internal {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);
        _grant(bobKey, BOB, CAROL, TrustLevel.Full, UNIVERSAL, 1);
        _bindAddr(CAROL, carol);
        _setGate(_defaultParams());
    }

    function test_ValidateParticipantAddress_AcceptsBoundParticipant() public {
        _gatedChainToCarol();

        assertTrue(
            registry.validateParticipantAddress(coordinator, MEV_COORDINATION, carol, _path(_nodes3(ALICE, BOB, CAROL)))
        );
    }

    /// @dev The path proves something about CAROL's node, not about dave's address
    function test_ValidateParticipantAddress_RejectsUnboundAddress() public {
        _gatedChainToCarol();

        assertFalse(
            registry.validateParticipantAddress(coordinator, MEV_COORDINATION, dave, _path(_nodes3(ALICE, BOB, CAROL)))
        );
    }

    function test_ValidateParticipantAddress_RejectsZeroParticipant() public {
        _gatedChainToCarol();

        assertFalse(
            registry.validateParticipantAddress(
                coordinator, MEV_COORDINATION, address(0), _path(_nodes3(ALICE, BOB, CAROL))
            )
        );
    }

    /// @dev A node with no addr record resolves to address(0); it must not match a
    ///      zero participant address either, which the explicit zero check prevents
    function test_ValidateParticipantAddress_RejectsNodeWithNoAddrRecord() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);
        _grant(bobKey, BOB, CAROL, TrustLevel.Full, UNIVERSAL, 1);
        _setGate(_defaultParams()); // CAROL deliberately left unbound

        assertFalse(
            registry.validateParticipantAddress(coordinator, MEV_COORDINATION, carol, _path(_nodes3(ALICE, BOB, CAROL)))
        );
        assertFalse(
            registry.validateParticipantAddress(
                coordinator, MEV_COORDINATION, address(0), _path(_nodes3(ALICE, BOB, CAROL))
            )
        );
    }

    function test_ValidateParticipantAddress_RejectsPathNotStartingAtGatekeeper() public {
        _gatedChainToCarol();

        assertFalse(
            registry.validateParticipantAddress(coordinator, MEV_COORDINATION, carol, _path(_nodes2(BOB, CAROL)))
        );
    }

    function test_ValidateParticipantAddress_RejectsBrokenTrustChain() public {
        _gatedChainToCarol();

        vm.prank(bob);
        registry.revokeTrust(BOB, CAROL, UNIVERSAL, keccak256("MISBEHAVIOR"));

        assertFalse(
            registry.validateParticipantAddress(coordinator, MEV_COORDINATION, carol, _path(_nodes3(ALICE, BOB, CAROL)))
        );
    }

    /// @dev An agent behind a CCIP-Read resolver cannot pass an on-chain gate
    function test_ValidateParticipantAddress_RejectsOffchainResolver() public {
        _grant(aliceKey, ALICE, BOB, TrustLevel.Full, UNIVERSAL, 1);
        _grant(bobKey, BOB, CAROL, TrustLevel.Full, UNIVERSAL, 1);
        ens.setResolver(CAROL, address(new RevertingResolver()));
        _setGate(_defaultParams());

        assertFalse(
            registry.validateParticipantAddress(coordinator, MEV_COORDINATION, carol, _path(_nodes3(ALICE, BOB, CAROL)))
        );
    }

    function test_ValidateParticipantAddress_OpenWhenNoGate() public {
        _bindAddr(CAROL, carol);

        assertTrue(
            registry.validateParticipantAddress(
                otherCoordinator, MEV_COORDINATION, carol, _path(_nodes3(ALICE, BOB, CAROL))
            )
        );
    }

    // ───────────────────────────────────────────────────────────────────────────
    // ERC-165 interface detection
    // ───────────────────────────────────────────────────────────────────────────

    function test_ERC165_SupportsRequiredInterfaces() public view {
        assertTrue(registry.supportsInterface(type(IERC165).interfaceId), "IERC165");
        assertTrue(registry.supportsInterface(type(ITrustRegistry).interfaceId), "ITrustRegistry");
    }

    /// @dev The published constants MUST match what Solidity computes, since the spec
    ///      states them as literals implementers may hard-code
    function test_ERC165_PublishedIdentifiersAreStable() public pure {
        assertEq(type(IERC165).interfaceId, bytes4(0x01ffc9a7), "IERC165 id");
        assertEq(type(ITrustRegistry).interfaceId, bytes4(0x42b46ef5), "ITrustRegistry id");
        assertEq(type(ITrustRegistryExtended).interfaceId, bytes4(0x93e686a3), "ITrustRegistryExtended id");
    }

    /// @dev This implementation does not provide on-chain graph search, so it MUST NOT
    ///      advertise the extension
    function test_ERC165_DoesNotAdvertiseUnimplementedExtension() public view {
        assertFalse(registry.supportsInterface(type(ITrustRegistryExtended).interfaceId));
    }

    /// @dev Required by ERC-165
    function test_ERC165_RejectsInvalidSentinel() public view {
        assertFalse(registry.supportsInterface(bytes4(0xffffffff)));
    }

    function test_ERC165_RejectsUnrelatedInterface() public view {
        assertFalse(registry.supportsInterface(type(IERC1271).interfaceId));
        assertFalse(registry.supportsInterface(bytes4(0xdeadbeef)));
    }

    /// @dev ERC-165 caps supportsInterface at 30,000 gas
    function test_ERC165_GasWithinBudget() public view {
        uint256 before = gasleft();
        registry.supportsInterface(type(ITrustRegistry).interfaceId);
        uint256 used = before - gasleft();
        assertLt(used, 30_000, "supportsInterface must stay under the ERC-165 budget");
    }

    // ───────────────────────────────────────────────────────────────────────────
    // EIP-712 / EIP-5267
    // ───────────────────────────────────────────────────────────────────────────

    function test_EIP5267_DomainMatchesSpecification() public view {
        (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            registry.eip712Domain();
        assertEq(name, "TrustRegistry");
        assertEq(version, "1");
        assertEq(chainId, block.chainid);
        assertEq(verifyingContract, address(registry));
    }

    function test_Typehash() public view {
        assertEq(
            registry.TRUST_ATTESTATION_TYPEHASH(),
            keccak256(
                "TrustAttestation(bytes32 trustorNode,bytes32 trusteeNode,uint8 level,bytes32 scope,uint64 expiry,uint64 nonce)"
            )
        );
    }

    /// @dev Domain separation prevents replaying an attestation on another registry
    function test_SignatureDoesNotReplayAcrossRegistries() public {
        TrustRegistry other = new TrustRegistry(address(ens), address(wrapper));
        TrustAttestation memory att = _att(ALICE, BOB, TrustLevel.Full, UNIVERSAL, 0, 1);
        bytes memory sig = _sign(aliceKey, att);

        registry.setTrust(att, sig);

        vm.expectRevert(InvalidSignature.selector);
        other.setTrust(att, sig);
    }
}
