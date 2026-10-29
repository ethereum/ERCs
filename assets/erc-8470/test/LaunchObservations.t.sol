// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {LaunchObservations} from "../contracts/LaunchObservations.sol";
import {ILaunchObservations} from "../contracts/ILaunchObservations.sol";
import {
    Vm, MockDirectory, MockIdentityRegistry, MockPlainRegistry, MockArbSys, MockBlockHistory
} from "./Mocks.sol";

contract LaunchObservationsTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    // Copies of the interface events, for expectEmit.
    event ObservationRecorded(
        uint256 indexed observationId,
        bytes32 indexed launchKey,
        address indexed detector,
        ILaunchObservations.KeyKind kind,
        uint256 chainId,
        address token,
        bytes32 declarationId,
        uint64 observedBlock,
        bytes32 observedBlockHash,
        bool hashChecked,
        uint256 supersedes,
        ILaunchObservations.Tally tally,
        bytes32 reportHash,
        string reportURI,
        bytes32 evidenceRoot
    );
    event FindingObserved(
        uint256 indexed observationId, bytes32 indexed kind, uint256 value, uint64 param, ILaunchObservations.Lean lean
    );
    event DetectorIdentitySet(address indexed detector, address indexed identityRegistry, uint256 indexed agentId);

    LaunchObservations reg;
    MockDirectory dir;
    MockIdentityRegistry ids;

    address constant DETECTOR_A = address(0xA11CE);
    address constant DETECTOR_B = address(0xB0B);
    address constant TOKEN = address(0x7011);
    uint256 constant RH_CHAIN = 4663;
    bytes32 constant LAUNCH_ID = keccak256("launch-1");
    bytes32 constant FIRST_BLOCK_SHARE = keccak256("erc.launch-observations.first-block-share");
    bytes32 constant EARLY_BUYER_SHARE = keccak256("erc.launch-observations.early-buyer-share");
    bytes32 constant CREATOR_PRIOR_LAUNCHES = keccak256("erc.launch-observations.creator-prior-launches");
    bytes32 constant FUNDING_LINKED_SHARE = keccak256("erc.launch-observations.funding-linked-share");
    bytes32 constant DEPLOYER_SELL_RATIO = keccak256("erc.launch-observations.signal.deployerSellRatio");
    bytes32 constant LP_LOCK_REMAINING = keccak256("erc.launch-observations.signal.lpLockRemaining");
    bytes32 constant PRIVILEGED_POWERS = keccak256("erc.launch-observations.signal.privilegedPowers");
    bytes32 constant PRODUCT_LABEL = keccak256("erc.launch-observations.product-label");
    uint256 constant LABEL_PARTLY_FOUND = 2;
    address constant ARB_SYS = address(100);
    address constant HISTORY = 0x0000F90827F1C53a10cb7A02335B175320002935;
    uint64 constant L2_NOW = 99_930_810; // Robinhood Chain's own block while block.number reads the parent chain's

    function setUp() public {
        dir = new MockDirectory();
        ids = new MockIdentityRegistry();
        reg = new LaunchObservations(address(dir));
        dir.list(LAUNCH_ID, TOKEN);
        vm.roll(1_000);
        vm.warp(1_800_000_000);
    }

    // ---------------------------------------------------------------- helpers

    function _eq(uint256 a, uint256 b, string memory m) internal pure {
        require(a == b, m);
    }

    function _eq(bytes32 a, bytes32 b, string memory m) internal pure {
        require(a == b, m);
    }

    function _eq(address a, address b, string memory m) internal pure {
        require(a == b, m);
    }

    /// The hash a detector would read: the real one where blockhash reaches, else a stand-in for another chain's block.
    function _bh(uint64 observedBlock) internal view returns (bytes32 h) {
        h = blockhash(observedBlock);
        if (h == bytes32(0)) h = keccak256(abi.encode("block", observedBlock));
    }

    function _tokenInput(uint64 observedBlock) internal view returns (ILaunchObservations.ObservationInput memory i) {
        i.kind = ILaunchObservations.KeyKind.Token;
        i.chainId = RH_CHAIN;
        i.token = TOKEN;
        i.observedBlock = observedBlock;
        i.observedBlockHash = _bh(observedBlock);
        i.tally = ILaunchObservations.Tally(2, 1, 3);
        i.reportHash = keccak256("report");
        i.reportURI = "https://t0ll.xyz/r/0x7011";
    }

    function _findings() internal pure returns (ILaunchObservations.Finding[] memory f) {
        f = new ILaunchObservations.Finding[](6);
        f[0] = ILaunchObservations.Finding(FIRST_BLOCK_SHARE, 3_400, 0, ILaunchObservations.Lean.Against);
        f[1] = ILaunchObservations.Finding(EARLY_BUYER_SHARE, 5_100, 30, ILaunchObservations.Lean.Against);
        f[2] = ILaunchObservations.Finding(CREATOR_PRIOR_LAUNCHES, 12, 0, ILaunchObservations.Lean.Careful);
        f[3] = ILaunchObservations.Finding(FUNDING_LINKED_SHARE, 0, 2, ILaunchObservations.Lean.Clear);
        f[4] = ILaunchObservations.Finding(DEPLOYER_SELL_RATIO, 9_000, 0, ILaunchObservations.Lean.Clear);
        f[5] = ILaunchObservations.Finding(PRODUCT_LABEL, LABEL_PARTLY_FOUND, 0, ILaunchObservations.Lean.Clear);
    }

    function _none() internal pure returns (ILaunchObservations.Finding[] memory f) {
        f = new ILaunchObservations.Finding[](0);
    }

    function _record(address detector, uint64 observedBlock) internal returns (uint256 id, bytes32 key) {
        ILaunchObservations.ObservationInput memory i = _tokenInput(observedBlock);
        ILaunchObservations.Finding[] memory f = _findings();
        vm.prank(detector);
        (id, key) = reg.recordObservation(i, f);
    }

    // ---------------------------------------------------------------- record and read

    function test_RecordTokenScopedAndRead() public {
        (uint256 id, bytes32 key) = _record(DETECTOR_A, 900);
        _eq(id, 1, "id");
        _eq(key, reg.tokenKey(RH_CHAIN, TOKEN), "key");
        _eq(key, keccak256(abi.encode(keccak256("erc.launch-observations.token-scoped"), RH_CHAIN, TOKEN)), "key derivation");

        (ILaunchObservations.Observation memory o, ILaunchObservations.Finding[] memory f) = reg.getObservation(id);
        require(o.kind == ILaunchObservations.KeyKind.Token, "kind");
        _eq(o.launchKey, key, "launchKey");
        _eq(o.chainId, RH_CHAIN, "chainId");
        _eq(o.token, TOKEN, "token");
        _eq(o.detector, DETECTOR_A, "detector");
        _eq(o.observedBlock, 900, "observedBlock");
        _eq(o.recordedAt, 1_800_000_000, "recordedAt");
        _eq(o.supersedes, 0, "supersedes");
        _eq(o.tally.against, 2, "against");
        _eq(o.tally.careful, 1, "careful");
        _eq(o.tally.clear, 3, "clear");
        _eq(o.reportHash, keccak256("report"), "reportHash");
        require(keccak256(bytes(o.reportURI)) == keccak256("https://t0ll.xyz/r/0x7011"), "uri");
        _eq(f.length, 6, "findings");
        _eq(f[1].kind, EARLY_BUYER_SHARE, "finding kind");
        _eq(f[1].param, 30, "finding param");
        _eq(f[1].value, 5_100, "finding value");

        _eq(reg.latestOf(key, DETECTOR_A), id, "latest");
        _eq(reg.latestOf(key, DETECTOR_B), 0, "latest of other");
        uint256[] memory all = reg.observationsOf(key, 0, 10);
        _eq(all.length, 1, "all");
        address[] memory ds = reg.detectorsOf(key, 0, 10);
        _eq(ds.length, 1, "detectors");
        _eq(ds[0], DETECTOR_A, "detector listed");
    }

    function test_RecordErc8376KeyReadsTokenFromDirectory() public {
        ILaunchObservations.ObservationInput memory i = _tokenInput(900);
        i.kind = ILaunchObservations.KeyKind.Erc8376;
        i.launchId = LAUNCH_ID;
        i.chainId = 0;
        i.token = address(0);
        vm.prank(DETECTOR_A);
        (uint256 id, bytes32 key) = reg.recordObservation(i, _findings());
        _eq(key, LAUNCH_ID, "key is launchId");
        (ILaunchObservations.Observation memory o,) = reg.getObservation(id);
        require(o.kind == ILaunchObservations.KeyKind.Erc8376, "kind");
        _eq(o.token, TOKEN, "token from directory");
        _eq(o.chainId, block.chainid, "this chain");
    }

    function test_Erc8376UnlistedOrMalformedReverts() public {
        ILaunchObservations.ObservationInput memory i = _tokenInput(900);
        i.kind = ILaunchObservations.KeyKind.Erc8376;
        i.launchId = keccak256("never listed");
        i.chainId = 0;
        i.token = address(0);
        vm.prank(DETECTOR_A);
        vm.expectRevert(LaunchObservations.LaunchNotListed.selector);
        reg.recordObservation(i, _findings());

        i.launchId = LAUNCH_ID;
        i.token = TOKEN; // must be left zero; the token comes from the directory
        vm.prank(DETECTOR_A);
        vm.expectRevert(LaunchObservations.InvalidKey.selector);
        reg.recordObservation(i, _findings());

        LaunchObservations noDir = new LaunchObservations(address(0));
        i.token = address(0);
        vm.prank(DETECTOR_A);
        vm.expectRevert(LaunchObservations.InvalidKey.selector);
        noDir.recordObservation(i, _findings());
    }

    function test_TokenKeyMalformedReverts() public {
        ILaunchObservations.ObservationInput memory i = _tokenInput(900);
        i.launchId = LAUNCH_ID;
        vm.expectRevert(LaunchObservations.InvalidKey.selector);
        reg.recordObservation(i, _findings());

        i = _tokenInput(900);
        i.chainId = 0;
        vm.expectRevert(LaunchObservations.InvalidKey.selector);
        reg.recordObservation(i, _findings());

        i = _tokenInput(900);
        i.token = address(0);
        vm.expectRevert(LaunchObservations.InvalidKey.selector);
        reg.recordObservation(i, _findings());

        i = _tokenInput(900);
        i.kind = ILaunchObservations.KeyKind.None;
        vm.expectRevert(LaunchObservations.InvalidKey.selector);
        reg.recordObservation(i, _findings());
    }

    function test_UnknownObservationReadsEmpty() public view {
        (ILaunchObservations.Observation memory o, ILaunchObservations.Finding[] memory f) = reg.getObservation(42);
        require(o.kind == ILaunchObservations.KeyKind.None, "kind none");
        _eq(o.detector, address(0), "no detector");
        _eq(f.length, 0, "no findings");
        _eq(reg.observationsOf(keccak256("x"), 0, 10).length, 0, "empty list");
    }

    // ---------------------------------------------------------------- append-only and supersession

    function test_AppendOnlyNoEditPath() public {
        (uint256 id,) = _record(DETECTOR_A, 900);
        (ILaunchObservations.Observation memory before,) = reg.getObservation(id);

        // The registry has no function that changes or removes an observation:
        // an unknown selector (no fallback) reverts.
        (bool ok,) = address(reg).call(abi.encodeWithSignature("editObservation(uint256,bytes32)", id, bytes32(0)));
        require(!ok, "edit path exists");
        (ok,) = address(reg).call(abi.encodeWithSignature("deleteObservation(uint256)", id));
        require(!ok, "delete path exists");

        // Recording again by another detector does not touch the first observation.
        _record(DETECTOR_B, 950);
        (ILaunchObservations.Observation memory afterwards, ILaunchObservations.Finding[] memory f) =
            reg.getObservation(id);
        _eq(afterwards.observedBlock, before.observedBlock, "unchanged block");
        _eq(afterwards.reportHash, before.reportHash, "unchanged hash");
        _eq(afterwards.detector, DETECTOR_A, "unchanged detector");
        _eq(f.length, 6, "unchanged findings");
    }

    function test_SupersedeKeepsHistory() public {
        (uint256 first, bytes32 key) = _record(DETECTOR_A, 900);
        _record(DETECTOR_B, 905);

        ILaunchObservations.ObservationInput memory i = _tokenInput(990);
        i.reportHash = keccak256("report v2");
        vm.prank(DETECTOR_A);
        (uint256 second,) = reg.recordObservation(i, _none());

        (ILaunchObservations.Observation memory o2,) = reg.getObservation(second);
        _eq(o2.supersedes, first, "points at the earlier one");
        _eq(reg.latestOf(key, DETECTOR_A), second, "latest moved");
        _eq(reg.latestOf(key, DETECTOR_B), 2, "other detector untouched");

        (ILaunchObservations.Observation memory o1, ILaunchObservations.Finding[] memory f1) = reg.getObservation(first);
        _eq(o1.reportHash, keccak256("report"), "first still readable");
        _eq(f1.length, 6, "first findings kept");

        uint256[] memory hist = reg.observationsBy(key, DETECTOR_A, 0, 10);
        _eq(hist.length, 2, "history");
        _eq(hist[0], first, "oldest first");
        _eq(hist[1], second, "newest last");
        _eq(reg.observationsOf(key, 0, 10).length, 3, "all three");
        _eq(reg.detectorsOf(key, 0, 10).length, 2, "two detectors, listed once each");
    }

    function test_SameBlockCorrectionAllowedOlderBlockReverts() public {
        (uint256 first, bytes32 key) = _record(DETECTOR_A, 900);
        (uint256 again,) = _record(DETECTOR_A, 900);
        (ILaunchObservations.Observation memory o,) = reg.getObservation(again);
        _eq(o.supersedes, first, "same-block correction supersedes");

        vm.prank(DETECTOR_A);
        vm.expectRevert(abi.encodeWithSelector(LaunchObservations.StaleObservedBlock.selector, uint64(900)));
        reg.recordObservation(_tokenInput(899), _findings());
        _eq(reg.latestOf(key, DETECTOR_A), again, "latest unchanged");
    }

    // ---------------------------------------------------------------- events

    function test_EventsEmitted() public {
        bytes32 key = reg.tokenKey(RH_CHAIN, TOKEN);
        ILaunchObservations.Finding[] memory f = _findings();
        vm.expectEmit(true, true, true, true, address(reg));
        emit ObservationRecorded(
            1,
            key,
            DETECTOR_A,
            ILaunchObservations.KeyKind.Token,
            RH_CHAIN,
            TOKEN,
            bytes32(0),
            900,
            _bh(900),
            false,
            0,
            ILaunchObservations.Tally(2, 1, 3),
            keccak256("report"),
            "https://t0ll.xyz/r/0x7011",
            bytes32(0)
        );
        for (uint256 k = 0; k < f.length; k++) {
            vm.expectEmit(true, true, true, true, address(reg));
            emit FindingObserved(1, f[k].kind, f[k].value, f[k].param, f[k].lean);
        }
        _record(DETECTOR_A, 900);
    }

    // ---------------------------------------------------------------- bounds and validation

    function test_FindingsBound() public {
        ILaunchObservations.Finding[] memory f = new ILaunchObservations.Finding[](32);
        for (uint256 k = 0; k < 32; k++) {
            f[k] = ILaunchObservations.Finding(keccak256(abi.encode("com.example.kind", k)), k, 0, ILaunchObservations.Lean.None);
        }
        vm.prank(DETECTOR_A);
        reg.recordObservation(_tokenInput(900), f); // 32 is accepted

        ILaunchObservations.Finding[] memory g = new ILaunchObservations.Finding[](33);
        for (uint256 k = 0; k < 33; k++) {
            g[k] = ILaunchObservations.Finding(keccak256(abi.encode("com.example.kind", k)), k, 0, ILaunchObservations.Lean.None);
        }
        vm.prank(DETECTOR_A);
        vm.expectRevert(LaunchObservations.TooManyFindings.selector);
        reg.recordObservation(_tokenInput(901), g);
    }

    function test_ReportBounds() public {
        ILaunchObservations.ObservationInput memory i = _tokenInput(900);
        i.reportURI = string(new bytes(512));
        reg.recordObservation(i, _none()); // 512 bytes is accepted

        i.reportURI = string(new bytes(513));
        vm.expectRevert(LaunchObservations.InvalidReport.selector);
        reg.recordObservation(i, _none());

        i.reportURI = "";
        vm.expectRevert(LaunchObservations.InvalidReport.selector);
        reg.recordObservation(i, _none());

        i = _tokenInput(900);
        i.reportHash = bytes32(0);
        vm.expectRevert(LaunchObservations.InvalidReport.selector);
        reg.recordObservation(i, _none());
    }

    function test_CoreFindingDomains() public {
        ILaunchObservations.Finding[] memory f = new ILaunchObservations.Finding[](1);
        ILaunchObservations.ObservationInput memory i = _tokenInput(900);

        f[0] = ILaunchObservations.Finding(FIRST_BLOCK_SHARE, 10_001, 0, ILaunchObservations.Lean.None);
        vm.expectRevert(abi.encodeWithSelector(LaunchObservations.InvalidFinding.selector, 0));
        reg.recordObservation(i, f);

        f[0] = ILaunchObservations.Finding(EARLY_BUYER_SHARE, 100, 0, ILaunchObservations.Lean.None); // N missing
        vm.expectRevert(abi.encodeWithSelector(LaunchObservations.InvalidFinding.selector, 0));
        reg.recordObservation(i, f);

        f[0] = ILaunchObservations.Finding(PRODUCT_LABEL, 0, 0, ILaunchObservations.Lean.None);
        vm.expectRevert(abi.encodeWithSelector(LaunchObservations.InvalidFinding.selector, 0));
        reg.recordObservation(i, f);

        f[0] = ILaunchObservations.Finding(PRODUCT_LABEL, 4, 0, ILaunchObservations.Lean.None);
        vm.expectRevert(abi.encodeWithSelector(LaunchObservations.InvalidFinding.selector, 0));
        reg.recordObservation(i, f);

        f[0] = ILaunchObservations.Finding(bytes32(0), 1, 0, ILaunchObservations.Lean.None);
        vm.expectRevert(abi.encodeWithSelector(LaunchObservations.InvalidFinding.selector, 0));
        reg.recordObservation(i, f);

        // "Not read" is the sentinel, never zero.
        f[0] = ILaunchObservations.Finding(PRODUCT_LABEL, type(uint256).max, 0, ILaunchObservations.Lean.None);
        reg.recordObservation(i, f);
        f[0] = ILaunchObservations.Finding(FIRST_BLOCK_SHARE, type(uint256).max, 0, ILaunchObservations.Lean.None);
        reg.recordObservation(i, f);
    }

    function test_DuplicateFindingReverts() public {
        ILaunchObservations.Finding[] memory f = new ILaunchObservations.Finding[](3);
        f[0] = ILaunchObservations.Finding(EARLY_BUYER_SHARE, 100, 30, ILaunchObservations.Lean.None);
        f[1] = ILaunchObservations.Finding(EARLY_BUYER_SHARE, 200, 60, ILaunchObservations.Lean.None); // other N: fine
        f[2] = ILaunchObservations.Finding(EARLY_BUYER_SHARE, 300, 30, ILaunchObservations.Lean.None);
        vm.expectRevert(abi.encodeWithSelector(LaunchObservations.DuplicateFinding.selector, 2));
        reg.recordObservation(_tokenInput(900), f);
    }

    function test_TallyMustCoverTypedFindings() public {
        ILaunchObservations.ObservationInput memory i = _tokenInput(900);
        i.tally = ILaunchObservations.Tally(1, 1, 3); // findings carry 2 "against"
        vm.expectRevert(LaunchObservations.TallyBelowFindings.selector);
        reg.recordObservation(i, _findings());
    }

    function test_ObservedBlockRules() public {
        // Same chain: the block must already exist.
        ILaunchObservations.ObservationInput memory i = _tokenInput(uint64(block.number));
        i.chainId = block.chainid;
        vm.expectRevert(LaunchObservations.InvalidObservedBlock.selector);
        reg.recordObservation(i, _none());

        i.observedBlock = 0;
        vm.expectRevert(LaunchObservations.InvalidObservedBlock.selector);
        reg.recordObservation(i, _none());

        // Another chain: its block numbers are not comparable with ours.
        i = _tokenInput(5_000_000);
        reg.recordObservation(i, _none());
    }

    function test_OwnChainBlockHashCheckedWithin256() public {
        vm.chainId(RH_CHAIN); // the token's chain is now the registry's chain
        ILaunchObservations.ObservationInput memory i = _tokenInput(900);
        require(blockhash(900) != bytes32(0), "fixture: block 900 is within reach");

        i.observedBlockHash = keccak256("a reorged-out block");
        vm.expectRevert(LaunchObservations.InvalidObservedBlockHash.selector);
        reg.recordObservation(i, _none());

        // The oldest block blockhash reaches (256 back) is still checked.
        i = _tokenInput(uint64(block.number - 256));
        i.observedBlockHash = keccak256("a reorged-out block");
        vm.expectRevert(LaunchObservations.InvalidObservedBlockHash.selector);
        reg.recordObservation(i, _none());

        // The right hash is accepted and emitted, not stored.
        i = _tokenInput(900);
        vm.recordLogs();
        reg.recordObservation(i, _none());
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // data head: kind, chainId, token, declarationId, observedBlock, observedBlockHash (word 5), hashChecked (word 6)
        _eq(_word(logs[0].data, 5), blockhash(900), "hash emitted");
        require(_word(logs[0].data, 6) == bytes32(uint256(1)), "hashChecked emitted true: blockhash read it");
        require(_checked(1), "hashChecked stored true");
    }

    function test_OwnChainBlockHashOlderThan256NotChecked() public {
        vm.chainId(RH_CHAIN);
        ILaunchObservations.ObservationInput memory i = _tokenInput(uint64(block.number - 257));
        i.observedBlockHash = keccak256("cannot be checked on chain");
        reg.recordObservation(i, _none()); // accepted: readers compare it with the canonical chain
        require(!_checked(1), "hashChecked false past blockhash's reach: a strict reader rejects it");
    }

    function test_ZeroBlockHashOnlyForOtherChains() public {
        // Same chain: the hash is required, inside or outside blockhash's reach.
        vm.chainId(RH_CHAIN);
        ILaunchObservations.ObservationInput memory i = _tokenInput(900);
        i.observedBlockHash = bytes32(0);
        vm.expectRevert(LaunchObservations.InvalidObservedBlockHash.selector);
        reg.recordObservation(i, _none());
        i.observedBlock = uint64(block.number - 300);
        vm.expectRevert(LaunchObservations.InvalidObservedBlockHash.selector);
        reg.recordObservation(i, _none());

        // ERC-8376 keys are always on the registry's chain.
        i = _erc8376Input(900);
        i.observedBlockHash = bytes32(0);
        vm.expectRevert(LaunchObservations.InvalidObservedBlockHash.selector);
        reg.recordObservation(i, _none());

        // Another chain: zero is allowed, and a given hash is not checked.
        vm.chainId(1);
        i = _tokenInput(900);
        i.observedBlockHash = bytes32(0);
        reg.recordObservation(i, _none());
        i.observedBlockHash = keccak256("any");
        reg.recordObservation(i, _none());
    }

    function test_PagingBounds() public {
        bytes32 key;
        for (uint256 k = 0; k < 5; k++) {
            (, key) = _record(address(uint160(0x1000 + k)), uint64(900 + k));
        }
        uint256[] memory p = reg.observationsOf(key, 1, 2);
        _eq(p.length, 2, "page size");
        _eq(p[0], 2, "second");
        _eq(p[1], 3, "third");
        _eq(reg.observationsOf(key, 5, 10).length, 0, "past the end");
        _eq(reg.observationsOf(key, 1, type(uint256).max).length, 4, "rest");
        _eq(reg.detectorsOf(key, 3, 10).length, 2, "detectors page");
        _eq(reg.observationsBy(key, address(0x1000), 1, 10).length, 0, "history page past end");
    }

    // ---------------------------------------------------------------- ERC-8004 identity

    function test_DetectorIdentityOwnerAndWallet() public {
        ids.mint(7, DETECTOR_A);
        vm.expectEmit(true, true, true, true, address(reg));
        emit DetectorIdentitySet(DETECTOR_A, address(ids), 7);
        vm.prank(DETECTOR_A);
        reg.setDetectorIdentity(address(ids), 7);
        (address r, uint256 a) = reg.detectorIdentity(DETECTOR_A);
        _eq(r, address(ids), "registry");
        _eq(a, 7, "agent");

        // The agent wallet the owner set may link too.
        ids.setAgentWallet(7, DETECTOR_B);
        vm.prank(DETECTOR_B);
        reg.setDetectorIdentity(address(ids), 7);

        // Someone else may not.
        vm.prank(address(0xBAD));
        vm.expectRevert(LaunchObservations.InvalidIdentity.selector);
        reg.setDetectorIdentity(address(ids), 7);

        // A registry without code, or a zero registry with an id, is refused.
        vm.prank(DETECTOR_A);
        vm.expectRevert(LaunchObservations.InvalidIdentity.selector);
        reg.setDetectorIdentity(address(0x1234), 7);
        vm.prank(DETECTOR_A);
        vm.expectRevert(LaunchObservations.InvalidIdentity.selector);
        reg.setDetectorIdentity(address(0), 7);

        // A plain ERC-721 registry is read through ownerOf alone.
        MockPlainRegistry plain = new MockPlainRegistry();
        plain.mint(3, DETECTOR_A);
        vm.prank(DETECTOR_A);
        reg.setDetectorIdentity(address(plain), 3);
    }

    function test_IdentityIsSnapshotPerObservation() public {
        ids.mint(7, DETECTOR_A);
        vm.prank(DETECTOR_A);
        reg.setDetectorIdentity(address(ids), 7);
        (uint256 first,) = _record(DETECTOR_A, 900);

        vm.prank(DETECTOR_A);
        reg.setDetectorIdentity(address(0), 0); // unlink
        (uint256 second,) = _record(DETECTOR_A, 901);

        (ILaunchObservations.Observation memory o1,) = reg.getObservation(first);
        (ILaunchObservations.Observation memory o2,) = reg.getObservation(second);
        _eq(o1.agentId, 7, "first keeps the identity it was recorded under");
        _eq(o1.identityRegistry, address(ids), "first registry");
        _eq(o2.agentId, 0, "second has none");
    }

    function test_Erc8376SignalDomains() public {
        ILaunchObservations.Finding[] memory f = new ILaunchObservations.Finding[](1);
        ILaunchObservations.ObservationInput memory i = _tokenInput(900);

        f[0] = ILaunchObservations.Finding(DEPLOYER_SELL_RATIO, 10_000, 0, ILaunchObservations.Lean.None);
        reg.recordObservation(i, f);
        f[0] = ILaunchObservations.Finding(DEPLOYER_SELL_RATIO, 10_001, 0, ILaunchObservations.Lean.None);
        vm.expectRevert(abi.encodeWithSelector(LaunchObservations.InvalidFinding.selector, 0));
        reg.recordObservation(i, f);
        f[0] = ILaunchObservations.Finding(DEPLOYER_SELL_RATIO, 100, 1, ILaunchObservations.Lean.None); // param must be 0
        vm.expectRevert(abi.encodeWithSelector(LaunchObservations.InvalidFinding.selector, 0));
        reg.recordObservation(i, f);

        // seconds, up to ERC-8376's uint32 range; its own sentinel is not a value here
        f[0] = ILaunchObservations.Finding(LP_LOCK_REMAINING, 30 days, 0, ILaunchObservations.Lean.None);
        reg.recordObservation(i, f);
        f[0] = ILaunchObservations.Finding(LP_LOCK_REMAINING, type(uint32).max, 0, ILaunchObservations.Lean.None);
        vm.expectRevert(abi.encodeWithSelector(LaunchObservations.InvalidFinding.selector, 0));
        reg.recordObservation(i, f);

        // the bitmask has eight assigned bits; zero (no powers) is a reading
        f[0] = ILaunchObservations.Finding(PRIVILEGED_POWERS, 0, 0, ILaunchObservations.Lean.None);
        reg.recordObservation(i, f);
        f[0] = ILaunchObservations.Finding(PRIVILEGED_POWERS, 0x100, 0, ILaunchObservations.Lean.None);
        vm.expectRevert(abi.encodeWithSelector(LaunchObservations.InvalidFinding.selector, 0));
        reg.recordObservation(i, f);

        f[0] = ILaunchObservations.Finding(LP_LOCK_REMAINING, type(uint256).max, 0, ILaunchObservations.Lean.None);
        reg.recordObservation(i, f); // not read
    }

    function test_GasTypicalObservation() public {
        uint256 before = gasleft();
        _record(DETECTOR_A, 900);
        uint256 used = before - gasleft();
        require(used < 850_000, "a first six-finding observation stays under 850k gas");
    }

    // ---------------------------------------------------------------- reading by token

    function _erc8376Input(uint64 observedBlock) internal view returns (ILaunchObservations.ObservationInput memory i) {
        i = _tokenInput(observedBlock);
        i.kind = ILaunchObservations.KeyKind.Erc8376;
        i.launchId = LAUNCH_ID;
        i.chainId = 0;
        i.token = address(0);
    }

    function test_LatestByTokenAcrossKeyKinds() public {
        vm.chainId(RH_CHAIN);
        _eq(reg.latestByToken(RH_CHAIN, TOKEN, DETECTOR_A), 0, "none yet");

        (uint256 first,) = _record(DETECTOR_A, 900); // token key
        _eq(reg.latestByToken(RH_CHAIN, TOKEN, DETECTOR_A), first, "token key");

        vm.prank(DETECTOR_A);
        (uint256 second,) = reg.recordObservation(_erc8376Input(950), _findings()); // ERC-8376 key, same token
        _eq(reg.latestByToken(RH_CHAIN, TOKEN, DETECTOR_A), second, "higher block under the 8376 key");

        // A lower observed block under the other key is recorded but does not become the latest by token.
        (uint256 third,) = _record(DETECTOR_A, 920);
        _eq(reg.latestOf(reg.tokenKey(RH_CHAIN, TOKEN), DETECTOR_A), third, "latest of the token key");
        _eq(reg.latestByToken(RH_CHAIN, TOKEN, DETECTOR_A), second, "lower block does not win");

        // A tie goes to the one recorded last.
        (uint256 fourth,) = _record(DETECTOR_A, 950);
        _eq(reg.latestByToken(RH_CHAIN, TOKEN, DETECTOR_A), fourth, "tie: recorded last");

        _eq(reg.latestByToken(RH_CHAIN, TOKEN, DETECTOR_B), 0, "other detector");
        _eq(reg.latestByToken(56, TOKEN, DETECTOR_A), 0, "other chain");
    }

    // ---------------------------------------------------------------- ERC-8462 venue-scoped keys

    address constant VENUE = address(0x7E9E);
    address constant CREATOR = address(0xC0FFEE);

    /// An ERC-8462 venue-scoped declaration id, derived as ERC-8462 specifies.
    function _venueDeclarationId(uint256 chainId, uint256 nonce) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(keccak256("erc.launch-declarations.venue-scoped"), chainId, VENUE, TOKEN, CREATOR, nonce)
        );
    }

    function _venueInput(uint64 observedBlock, bytes32 declarationId)
        internal
        view
        returns (ILaunchObservations.ObservationInput memory i)
    {
        i = _tokenInput(observedBlock);
        i.kind = ILaunchObservations.KeyKind.Erc8462Venue;
        i.launchId = declarationId;
    }

    function test_Erc8462VenueKeyDerivationAndRecord() public {
        bytes32 declarationId = _venueDeclarationId(RH_CHAIN, 0);
        bytes32 expected =
            keccak256(abi.encode(keccak256("erc.launch-observations.venue-declared"), RH_CHAIN, declarationId));
        _eq(reg.declarationKey(RH_CHAIN, declarationId), expected, "derivation");

        vm.prank(DETECTOR_A);
        (uint256 id, bytes32 key) = reg.recordObservation(_venueInput(900, declarationId), _findings());
        _eq(key, expected, "key");
        (ILaunchObservations.Observation memory o, ILaunchObservations.Finding[] memory f) = reg.getObservation(id);
        require(o.kind == ILaunchObservations.KeyKind.Erc8462Venue, "kind");
        _eq(o.launchKey, key, "launchKey");
        _eq(o.declarationId, declarationId, "declaration id kept for the join");
        _eq(o.chainId, RH_CHAIN, "chain");
        _eq(o.token, TOKEN, "token");
        _eq(f.length, 6, "findings");
        _eq(reg.latestOf(key, DETECTOR_A), id, "latestOf");
        _eq(reg.observationsOf(key, 0, 10).length, 1, "observationsOf");

        // The other key kinds carry no declaration id.
        (uint256 tokenId,) = _record(DETECTOR_B, 900);
        (o,) = reg.getObservation(tokenId);
        _eq(o.declarationId, bytes32(0), "token key: none");
    }

    function test_Erc8462VenueEventCarriesDeclarationId() public {
        bytes32 declarationId = _venueDeclarationId(RH_CHAIN, 0);
        bytes32 key = reg.declarationKey(RH_CHAIN, declarationId);
        vm.expectEmit(true, true, true, true, address(reg));
        emit ObservationRecorded(
            1,
            key,
            DETECTOR_A,
            ILaunchObservations.KeyKind.Erc8462Venue,
            RH_CHAIN,
            TOKEN,
            declarationId,
            900,
            _bh(900),
            false,
            0,
            ILaunchObservations.Tally(2, 1, 3),
            keccak256("report"),
            "https://t0ll.xyz/r/0x7011",
            bytes32(0)
        );
        vm.prank(DETECTOR_A);
        reg.recordObservation(_venueInput(900, declarationId), _none());
    }

    function test_Erc8462VenueMalformedReverts() public {
        bytes32 declarationId = _venueDeclarationId(RH_CHAIN, 0);
        ILaunchObservations.ObservationInput memory i = _venueInput(900, bytes32(0));
        vm.expectRevert(LaunchObservations.InvalidKey.selector);
        reg.recordObservation(i, _none());

        i = _venueInput(900, declarationId);
        i.chainId = 0;
        vm.expectRevert(LaunchObservations.InvalidKey.selector);
        reg.recordObservation(i, _none());

        i = _venueInput(900, declarationId);
        i.token = address(0);
        vm.expectRevert(LaunchObservations.InvalidKey.selector);
        reg.recordObservation(i, _none());

        // A registry without a directory still takes venue-scoped keys.
        LaunchObservations noDir = new LaunchObservations(address(0));
        noDir.recordObservation(_venueInput(900, declarationId), _none());
    }

    function test_Erc8462VenueKeyNeverCollides() public {
        // Fed the same 32 bytes, each kind lands under its own key.
        bytes32 venueKey = reg.declarationKey(RH_CHAIN, LAUNCH_ID);
        require(venueKey != LAUNCH_ID, "not an ERC-8376 launchId");
        require(venueKey != reg.tokenKey(RH_CHAIN, TOKEN), "not a token key");
        require(venueKey != reg.declarationKey(56, LAUNCH_ID), "chain is part of the key");
        require(
            reg.declarationKey(RH_CHAIN, _venueDeclarationId(RH_CHAIN, 0))
                != reg.declarationKey(RH_CHAIN, _venueDeclarationId(RH_CHAIN, 1)),
            "each relaunch has its own key"
        );
        // The token address fed as a declaration id does not reproduce the token key: the tags differ.
        require(
            reg.declarationKey(RH_CHAIN, bytes32(uint256(uint160(TOKEN)))) != reg.tokenKey(RH_CHAIN, TOKEN), "tag"
        );

        // Recording a listed launchId as a venue declaration id does not join the ERC-8376 key's lists.
        vm.prank(DETECTOR_A);
        (, bytes32 k8376) = reg.recordObservation(_erc8376Input(900), _none());
        vm.prank(DETECTOR_B);
        (, bytes32 kVenue) = reg.recordObservation(_venueInput(900, LAUNCH_ID), _none());
        require(k8376 != kVenue, "distinct keys");
        _eq(reg.observationsOf(LAUNCH_ID, 0, 10).length, 1, "8376 list untouched");
        _eq(reg.latestOf(LAUNCH_ID, DETECTOR_B), 0, "venue record not under the launchId");
    }

    function test_LatestByTokenIncludesErc8462Venue() public {
        bytes32 declarationId = _venueDeclarationId(RH_CHAIN, 0);
        _record(DETECTOR_A, 900); // token key
        vm.prank(DETECTOR_A);
        (uint256 second,) = reg.recordObservation(_venueInput(950, declarationId), _findings());
        _eq(reg.latestByToken(RH_CHAIN, TOKEN, DETECTOR_A), second, "higher block under the venue key");
        _record(DETECTOR_A, 920);
        _eq(reg.latestByToken(RH_CHAIN, TOKEN, DETECTOR_A), second, "lower block does not win");

        (uint256 oid, uint64 at,, uint256 value, ILaunchObservations.Lean lean) =
            reg.latestFinding(RH_CHAIN, TOKEN, DETECTOR_A, EARLY_BUYER_SHARE, 30);
        _eq(oid, second, "latestFinding reads the venue-keyed observation");
        _eq(at, 950, "its block");
        _eq(value, 5_100, "its value");
        require(lean == ILaunchObservations.Lean.Against, "its lean");

        address[] memory list = new address[](2);
        list[0] = DETECTOR_B;
        list[1] = DETECTOR_A;
        (address d, uint256 fid,,,,) = reg.latestFindingFrom(RH_CHAIN, TOKEN, list, EARLY_BUYER_SHARE, 30);
        _eq(d, DETECTOR_A, "latestFindingFrom finds it");
        _eq(fid, second, "same observation");
        _eq(reg.latestByToken(56, TOKEN, DETECTOR_A), 0, "other chain");
    }

    function test_LatestFindingReturnsValueAndBlock() public {
        (uint256 id,) = _record(DETECTOR_A, 900);
        (uint256 oid, uint64 at, uint64 rec, uint256 value, ILaunchObservations.Lean lean) =
            reg.latestFinding(RH_CHAIN, TOKEN, DETECTOR_A, EARLY_BUYER_SHARE, 30);
        _eq(oid, id, "id");
        _eq(at, 900, "observed block");
        _eq(rec, 1_800_000_000, "recordedAt");
        _eq(value, 5_100, "value");
        require(lean == ILaunchObservations.Lean.Against, "lean");

        (,,, value, lean) = reg.latestFinding(RH_CHAIN, TOKEN, DETECTOR_A, FUNDING_LINKED_SHARE, 2);
        _eq(value, 0, "a measured zero stays zero");
        require(lean == ILaunchObservations.Lean.Clear, "clear lean");
    }

    function test_LatestFindingMissingIsNotRead() public {
        // No observation at all.
        (uint256 oid, uint64 at, uint64 rec, uint256 value, ILaunchObservations.Lean lean) =
            reg.latestFinding(RH_CHAIN, TOKEN, DETECTOR_A, FIRST_BLOCK_SHARE, 0);
        _eq(oid, 0, "no id");
        _eq(at, 0, "no block");
        _eq(rec, 0, "no time");
        _eq(value, type(uint256).max, "not read");
        require(lean == ILaunchObservations.Lean.None, "no lean");

        // An observation without that kind, or with that kind under another param.
        (uint256 id,) = _record(DETECTOR_A, 900);
        (oid, at,, value, lean) = reg.latestFinding(RH_CHAIN, TOKEN, DETECTOR_A, LP_LOCK_REMAINING, 0);
        _eq(oid, id, "id still given");
        _eq(at, 900, "block still given");
        _eq(value, type(uint256).max, "missing kind is not read");
        require(lean == ILaunchObservations.Lean.None, "missing kind has no lean");

        (,,, value, lean) = reg.latestFinding(RH_CHAIN, TOKEN, DETECTOR_A, EARLY_BUYER_SHARE, 60);
        _eq(value, type(uint256).max, "other param is not read");
        require(lean == ILaunchObservations.Lean.None, "other param has no lean");
    }

    function test_LatestFindingFollowsSupersede() public {
        _record(DETECTOR_A, 900);
        ILaunchObservations.Finding[] memory f = _findings();
        f[0] = ILaunchObservations.Finding(FIRST_BLOCK_SHARE, type(uint256).max, 0, ILaunchObservations.Lean.None);
        vm.prank(DETECTOR_A);
        (uint256 second,) = reg.recordObservation(_tokenInput(905), f);
        (uint256 oid, uint64 at,, uint256 value,) = reg.latestFinding(RH_CHAIN, TOKEN, DETECTOR_A, FIRST_BLOCK_SHARE, 0);
        _eq(oid, second, "newest");
        _eq(at, 905, "newest block");
        _eq(value, type(uint256).max, "a later not read is not replaced by the earlier value");
    }

    function test_GuardExample() public {
        vm.chainId(RH_CHAIN);
        uint64 maxAge = 300;
        _record(DETECTOR_A, 900);
        vm.roll(1_100);
        (uint256 id, uint64 at,, uint256 linked,) = reg.latestFinding(block.chainid, TOKEN, DETECTOR_A, FUNDING_LINKED_SHARE, 2);
        uint256 current = _chainBlock();
        require(id != 0 && at <= current && current - at <= maxAge, "no fresh observation");
        require(linked != type(uint256).max && linked <= 1500, "funding-linked share");
        (,,, uint256 first,) = reg.latestFinding(block.chainid, TOKEN, DETECTOR_A, FIRST_BLOCK_SHARE, 0);
        require(first != type(uint256).max, "first-block share read");
        require(first > 2000, "the example fixture is a heavy first block, so a 20% guard refuses it");

        vm.roll(1_201);
        (, at,,,) = reg.latestFinding(block.chainid, TOKEN, DETECTOR_A, FUNDING_LINKED_SHARE, 2);
        require(_chainBlock() - at > maxAge, "stale after the bound");
    }

    /// The guard's block source, as the spec's example reads it.
    function _chainBlock() internal view returns (uint256) {
        if (ARB_SYS.code.length != 0) return MockArbSys(ARB_SYS).arbBlockNumber();
        return block.number;
    }

    function test_GuardExampleOnArbitrum() public {
        vm.chainId(RH_CHAIN);
        _etchArbSys(L2_NOW);
        _record(DETECTOR_A, L2_NOW - 50);
        (uint256 id, uint64 at,,,) = reg.latestFinding(block.chainid, TOKEN, DETECTOR_A, FUNDING_LINKED_SHARE, 2);
        uint256 current = _chainBlock();
        require(at > block.number, "fixture: the L2 block is far above the parent block number");
        require(id != 0 && at <= current && current - at <= 300, "fresh in the chain's own numbers");
    }

    function test_GasLatestFindingRead() public {
        _record(DETECTOR_A, 900);
        uint256 before = gasleft();
        reg.latestFinding(RH_CHAIN, TOKEN, DETECTOR_A, PRODUCT_LABEL, 0); // last of six: the worst case here
        uint256 used = before - gasleft();
        require(used < 40_000, "one-call read of the last of six findings stays under 40k gas");
    }

    // ---------------------------------------------------------------- Arbitrum block numbers and EIP-2935

    function _etchArbSys(uint256 number) internal {
        vm.etch(ARB_SYS, address(new MockArbSys()).code);
        MockArbSys(ARB_SYS).setArbBlockNumber(number);
        // Foundry answers ArbSys itself on chain ids it knows as Arbitrum (with block.number); pin the mock's answer.
        vm.mockCall(ARB_SYS, abi.encodeWithSignature("arbBlockNumber()"), abi.encode(number));
    }

    function _etchHistory() internal {
        vm.etch(HISTORY, address(new MockBlockHistory()).code);
    }

    function _ownChainInput(uint64 observedBlock, bytes32 hash)
        internal
        view
        returns (ILaunchObservations.ObservationInput memory i)
    {
        i = _tokenInput(observedBlock);
        i.observedBlockHash = hash;
    }

    function test_ArbitrumOwnChainRecordUsesL2Number() public {
        vm.chainId(RH_CHAIN);
        require(ARB_SYS.code.length == 0 && HISTORY.code.length == 0, "fixture: plain EVM to start");
        // Without ArbSys, an L2 block number is in the future of block.number.
        vm.expectRevert(LaunchObservations.InvalidObservedBlock.selector);
        reg.recordObservation(_ownChainInput(L2_NOW - 100, keccak256("l2 block")), _none());

        _etchArbSys(L2_NOW);
        (uint256 id,) = reg.recordObservation(_ownChainInput(L2_NOW - 100, keccak256("l2 block")), _none());
        (ILaunchObservations.Observation memory o,) = reg.getObservation(id);
        _eq(o.observedBlock, L2_NOW - 100, "L2 block recorded");
        // No history contract and no usable blockhash on Arbitrum: the hash is emitted unchecked.
    }

    function test_ArbitrumFutureBlockRejected() public {
        vm.chainId(RH_CHAIN);
        _etchArbSys(L2_NOW);
        vm.expectRevert(LaunchObservations.InvalidObservedBlock.selector);
        reg.recordObservation(_ownChainInput(L2_NOW, keccak256("x")), _none());
        vm.expectRevert(LaunchObservations.InvalidObservedBlock.selector);
        reg.recordObservation(_ownChainInput(L2_NOW + 1_000, keccak256("x")), _none());
        // Zero hash still reverts on the registry's own chain.
        vm.expectRevert(LaunchObservations.InvalidObservedBlockHash.selector);
        reg.recordObservation(_ownChainInput(L2_NOW - 1, bytes32(0)), _none());
    }

    /// word `i` of an event's data head
    function _word(bytes memory data, uint256 i) internal pure returns (bytes32 w) {
        assembly {
            w := mload(add(data, add(32, mul(i, 32))))
        }
    }

    /// hashChecked of a stored observation
    function _checked(uint256 id) internal view returns (bool) {
        (ILaunchObservations.Observation memory o,) = reg.getObservation(id);
        return o.hashChecked;
    }

    function test_HashCheckedFalseForAnotherChain() public {
        // the token is on RH_CHAIN, the registry is not: nothing is checked, even a right-looking hash
        reg.recordObservation(_tokenInput(900), _none());
        require(!_checked(1), "another chain: hashChecked false");
    }

    function test_ArbitrumHashCheckedThroughHistory() public {
        vm.chainId(RH_CHAIN);
        _etchArbSys(L2_NOW);
        _etchHistory();
        bytes32 real = keccak256("real L2 block");
        MockBlockHistory(payable(HISTORY)).setHash(L2_NOW - 100, real);
        MockBlockHistory(payable(HISTORY)).setHash(L2_NOW - 8_191, real);

        vm.expectRevert(LaunchObservations.InvalidObservedBlockHash.selector);
        reg.recordObservation(_ownChainInput(L2_NOW - 100, keccak256("reorged out")), _none());
        // The edge of the window is still checked.
        vm.expectRevert(LaunchObservations.InvalidObservedBlockHash.selector);
        reg.recordObservation(_ownChainInput(L2_NOW - 8_191, keccak256("reorged out")), _none());

        reg.recordObservation(_ownChainInput(L2_NOW - 100, real), _none());
        require(_checked(1), "hashChecked true through EIP-2935");
    }

    function test_ArbitrumHashOutOfWindowNotChecked() public {
        vm.chainId(RH_CHAIN);
        _etchArbSys(L2_NOW);
        _etchHistory();
        // Past the 8191-block window the history is not asked, even if it would answer.
        MockBlockHistory(payable(HISTORY)).setHash(L2_NOW - 8_192, keccak256("real"));
        reg.recordObservation(_ownChainInput(L2_NOW - 8_192, keccak256("unchecked")), _none());
        // Inside the window, a block the history has no hash for (it reverts) is not checked, and Arbitrum
        // gets no blockhash fallback.
        reg.recordObservation(_ownChainInput(L2_NOW - 10, keccak256("unchecked")), _none());
        require(!_checked(1) && !_checked(2), "hashChecked false out of the window and with no history hash");
    }

    function test_PlainEvmHistoryExtendsWindow() public {
        vm.chainId(RH_CHAIN);
        vm.roll(10_000);
        _etchHistory();
        bytes32 real = keccak256("real block 9000");
        MockBlockHistory(payable(HISTORY)).setHash(9_000, real); // 1000 old: past blockhash, inside 2935
        vm.expectRevert(LaunchObservations.InvalidObservedBlockHash.selector);
        reg.recordObservation(_ownChainInput(9_000, keccak256("wrong")), _none());
        reg.recordObservation(_ownChainInput(9_000, real), _none());
        require(_checked(1), "hashChecked true through EIP-2935 past blockhash's reach");

        // The history has nothing for 9900: blockhash is the fallback on a plain EVM chain.
        vm.expectRevert(LaunchObservations.InvalidObservedBlockHash.selector);
        reg.recordObservation(_ownChainInput(9_900, keccak256("wrong")), _none());
        reg.recordObservation(_ownChainInput(9_900, blockhash(9_900)), _none());
    }

    // ---------------------------------------------------------------- identity rechecked at record time

    function test_TransferredIdentityNotClaimed() public {
        ids.mint(7, DETECTOR_A);
        vm.prank(DETECTOR_A);
        reg.setDetectorIdentity(address(ids), 7);
        (uint256 first,) = _record(DETECTOR_A, 900);

        ids.transfer(7, DETECTOR_B); // owner and agent wallet are no longer the detector
        (uint256 second,) = _record(DETECTOR_A, 901);

        (ILaunchObservations.Observation memory o1,) = reg.getObservation(first);
        (ILaunchObservations.Observation memory o2,) = reg.getObservation(second);
        _eq(o1.agentId, 7, "first keeps its identity");
        _eq(o2.agentId, 0, "no agentId once the link no longer holds");
        _eq(o2.identityRegistry, address(0), "no registry either");

        // An agent wallet still pointing at the detector keeps the link.
        ids.setAgentWallet(7, DETECTOR_A);
        (uint256 third,) = _record(DETECTOR_A, 902);
        (ILaunchObservations.Observation memory o3,) = reg.getObservation(third);
        _eq(o3.agentId, 7, "agent wallet holds the link");
    }

    // ---------------------------------------------------------------- latestFindingFrom

    function test_LatestFindingFromOrderAndNotRead() public {
        address[] memory list = new address[](3);
        list[0] = DETECTOR_B;
        list[1] = address(0xC0C);
        list[2] = DETECTOR_A;

        // Nobody has observed the token: not read.
        (address d, uint256 oid, uint64 at, uint64 rec, uint256 value, ILaunchObservations.Lean lean) =
            reg.latestFindingFrom(RH_CHAIN, TOKEN, list, FIRST_BLOCK_SHARE, 0);
        _eq(d, address(0), "no detector");
        _eq(oid, 0, "no id");
        _eq(at, 0, "no block");
        _eq(rec, 0, "no time");
        _eq(value, type(uint256).max, "not read");
        require(lean == ILaunchObservations.Lean.None, "no lean");

        // Only the last detector in the list has it.
        (uint256 idA,) = _record(DETECTOR_A, 900);
        (d, oid, at,, value,) = reg.latestFindingFrom(RH_CHAIN, TOKEN, list, FIRST_BLOCK_SHARE, 0);
        _eq(d, DETECTOR_A, "falls through to A");
        _eq(oid, idA, "A's id");
        _eq(at, 900, "A's block");
        _eq(value, 3_400, "A's value");

        // B, first in the list, records the finding as not read: skipped.
        ILaunchObservations.Finding[] memory f = _findings();
        f[0] = ILaunchObservations.Finding(FIRST_BLOCK_SHARE, type(uint256).max, 0, ILaunchObservations.Lean.None);
        vm.prank(DETECTOR_B);
        reg.recordObservation(_tokenInput(905), f);
        (d,,,, value,) = reg.latestFindingFrom(RH_CHAIN, TOKEN, list, FIRST_BLOCK_SHARE, 0);
        _eq(d, DETECTOR_A, "a not-read finding does not stop the search");

        // B reads it: B wins by list order, even with A observing a later block.
        f[0] = ILaunchObservations.Finding(FIRST_BLOCK_SHARE, 1_000, 0, ILaunchObservations.Lean.Against);
        vm.prank(DETECTOR_B);
        (uint256 idB,) = reg.recordObservation(_tokenInput(906), f);
        _record(DETECTOR_A, 950);
        (d, oid, at,, value, lean) = reg.latestFindingFrom(RH_CHAIN, TOKEN, list, FIRST_BLOCK_SHARE, 0);
        _eq(d, DETECTOR_B, "list order wins");
        _eq(oid, idB, "B's id");
        _eq(at, 906, "B's block");
        _eq(value, 1_000, "B's value");
        require(lean == ILaunchObservations.Lean.Against, "B's lean");

        // A kind nobody holds, an empty list, another chain: not read.
        (d,,,, value,) = reg.latestFindingFrom(RH_CHAIN, TOKEN, list, LP_LOCK_REMAINING, 0);
        _eq(d, address(0), "missing kind");
        _eq(value, type(uint256).max, "missing kind not read");
        (d,,,, value,) = reg.latestFindingFrom(RH_CHAIN, TOKEN, new address[](0), FIRST_BLOCK_SHARE, 0);
        _eq(value, type(uint256).max, "empty list not read");
        (d,,,, value,) = reg.latestFindingFrom(56, TOKEN, list, FIRST_BLOCK_SHARE, 0);
        _eq(value, type(uint256).max, "other chain not read");
    }

    function test_GasOwnChainObservation() public {
        vm.chainId(RH_CHAIN);
        uint256 before = gasleft();
        _record(DETECTOR_A, 900);
        uint256 used = before - gasleft();
        require(used < 850_000, "a first six-finding same-chain observation stays under 850k gas");
    }

    // ---------------------------------------------------------------- ERC-165

    function test_SupportsInterface() public view {
        require(reg.supportsInterface(type(ILaunchObservations).interfaceId), "ILaunchObservations");
        require(reg.supportsInterface(0x01ffc9a7), "ERC-165");
        require(!reg.supportsInterface(0xffffffff), "0xffffffff");
    }

    function test_InterfaceIdMatchesSpec() public pure {
        require(type(ILaunchObservations).interfaceId == bytes4(0x125ee299), "interface id");
    }
}
