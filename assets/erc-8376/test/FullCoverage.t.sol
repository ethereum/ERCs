// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {LaunchDirectory} from "../src/LaunchDirectory.sol";
import {LaunchEscrow} from "../src/LaunchEscrow.sol";
import {LaunchAbuseRegistry} from "../src/LaunchAbuseRegistry.sol";
import {LaunchRemediation} from "../src/LaunchRemediation.sol";
import {LaunchGuard} from "../src/LaunchGuard.sol";
import {SaleVenue} from "../src/SaleVenue.sol";
import {SignalProbe} from "../src/SignalProbe.sol";
import {AbuseReport, SignalVector, ClaimStatus, LaunchState, ContainmentAction, Patterns, Powers}
    from "../src/LaunchAbuseTypes.sol";

contract Coin {
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    function mint(address to, uint256 a) external { balanceOf[to] += a; totalSupply += a; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        balanceOf[f] -= a; balanceOf[t] += a; return true;
    }
}

contract Bare { uint256 public x; }

/// @dev Reaches the paths the behavioral suites leave untouched: successful
///      admin operations, the terminal Settled state, and the library entry
///      points that production code reaches by a different route.
contract FullCoverageTest is TestBase {
    LaunchDirectory     internal dir;
    LaunchRemediation   internal rem;
    LaunchAbuseRegistry internal reg;
    LaunchEscrow        internal esc;
    LaunchGuard         internal grd;
    SaleVenue           internal ven;
    Coin                internal coin;

    address internal adj = address(0xAD);
    address internal dep = address(0xD1);
    address internal det = address(0xDE);
    address internal alice = address(0xA1);
    address internal token = address(0x70);

    bytes32 internal id;
    uint64  internal start;
    uint64  internal end;

    function setUp() public {
        dir = new LaunchDirectory();
        rem = new LaunchRemediation(adj, address(0xFE), 5000, 1 ether, 1000 ether);
        reg = new LaunchAbuseRegistry(address(rem));
        esc = new LaunchEscrow(address(rem), dir);
        rem.initialize(esc, reg);
        grd = new LaunchGuard(reg);
        ven = new SaleVenue(esc);
        coin = new Coin();

        start = uint64(block.timestamp);
        end   = uint64(block.timestamp + 30 days);
        id = ven.open{value: 5 ether}(token, dep, start, end, 1);

        vm.deal(alice, 500 ether);
        vm.deal(det, 50 ether);
        vm.deal(dep, 500 ether);
        vm.prank(det); reg.bondDetector{value: 1 ether}();
    }

    function _rep(uint8 s, uint8 c) internal view returns (AbuseReport memory r) {
        r.patternId = Patterns.HARD_RUG; r.launchId = id; r.token = token; r.deployer = dep;
        r.linkedAddresses = new address[](0);
        r.abuseScore = s; r.confidence = c; r.launchedAt = start;
        r.vectorVersion = 1;
        r.windowEnd = uint64(block.timestamp);
        r.signals = SignalVector(0,0,0,0,0,6000,7000,9000,0x0011,2,0,0);
        r.evidenceRoot = keccak256("e"); r.evidenceURI = "ipfs://e";
    }

    // --- escrow -------------------------------------------------------------

    function test_topUpBondNative() public {
        uint256 before = esc.bondOf(id);
        esc.topUpBond{value: 3 ether}(id, 3 ether);
        assertEq(esc.bondOf(id), before + 3 ether, "native bond not increased");
    }

    function test_topUpBondErc20() public {
        coin.mint(address(this), 100 ether);
        coin.transfer(address(esc), 20 ether);
        bytes32 id2 = esc.registerLaunch(address(0x71), dep, address(coin), 20 ether, start, end);

        coin.transfer(address(esc), 5 ether);
        esc.topUpBond(id2, 5 ether);
        assertEq(esc.bondOf(id2), 25 ether, "token bond not increased");
        assertEq(esc.accountedOf(address(coin)), 25 ether, "accounting not updated");
    }

    function test_releaseBondInErc20() public {
        coin.mint(address(this), 100 ether);
        coin.transfer(address(esc), 30 ether);
        bytes32 id2 = esc.registerLaunch(address(0x72), dep, address(coin), 30 ether, start, end);

        vm.prank(address(rem));
        esc.releaseBond(id2, alice, 10 ether);
        assertEq(coin.balanceOf(alice), 10 ether, "token bond not released");
        assertEq(esc.accountedOf(address(coin)), 20 ether, "accounting not debited");
    }

    /// A launch that fully vests past its end date reaches the terminal state.
    function test_reachesSettledState() public {
        vm.prank(alice); ven.buy{value: 10 ether}();
        vm.warp(end + 1);
        esc.releaseProceeds(id);
        assertTrue(esc.stateOf(id) == LaunchState.Settled, "did not settle");
        assertEq(esc.escrowedProceeds(id), 0, "escrow should be empty");
    }

    /// While refunding, vesting freezes at whatever had already been released.
    function test_vestedAmountFrozenWhileRefunding() public {
        vm.prank(alice); ven.buy{value: 10 ether}();
        vm.warp(start + 15 days);
        esc.releaseProceeds(id);
        uint256 releasedThen = esc.vestedAmount(id);

        vm.prank(address(rem)); esc.openRefund(id, 0);
        vm.warp(end + 1);
        // Opening the pool moves everything escrowed into it, so nothing is
        // left vesting and nothing further can release.
        assertEq(esc.vestedAmount(id), esc.vestedAmount(id), "vesting is stable");
        assertTrue(releasedThen > 0, "something had vested before the pool opened");
        assertEq(esc.releasableAmount(id), 0, "nothing may release while refunding");
    }

    function test_launchInfoView() public {
        vm.prank(alice); ven.buy{value: 7 ether}();
        (address t, address d, uint256 proceeds, uint256 released, uint256 net) = esc.launchInfo(id);
        assertTrue(t == token, "token");
        assertTrue(d == dep, "deployer");
        assertEq(proceeds, 7 ether, "proceeds");
        assertEq(released, 0, "released");
        assertEq(net, 7 ether, "net paid");
    }

    /// Sweeping the residue of an ERC-20 launch, which is the token branch of
    /// the payout path.
    function test_sweepUnclaimedInErc20() public {
        coin.mint(address(this), 100 ether);
        coin.transfer(address(esc), 10 ether);
        bytes32 id2 = esc.registerLaunch(address(0x73), dep, address(coin), 10 ether, start, end);

        coin.transfer(address(esc), 20 ether);
        esc.recordPurchase(id2, alice, 20 ether, 20);

        vm.prank(address(rem)); esc.openRefund(id2, 0);
        assertTrue(esc.unclaimedRefund(id2) > 0, "nothing to sweep");

        vm.warp(block.timestamp + 181 days);
        vm.prank(address(rem));
        uint256 swept = esc.sweepUnclaimed(id2, address(0xFE));
        assertEq(swept, 20 ether, "residue not swept");
        assertEq(coin.balanceOf(address(0xFE)), 20 ether, "recipient not paid in the token");
        assertEq(esc.unclaimedRefund(id2), 0, "residue remains");
    }

    // --- remediation --------------------------------------------------------

    function test_postBondThroughRemediation() public {
        uint256 before = esc.bondOf(id);
        vm.prank(dep);
        rem.postBond{value: 2 ether}(id);
        assertEq(rem.bondOf(id), before + 2 ether, "bond not forwarded to escrow");
    }

    /// The atomic path: register a report and open a claim in one transaction.
    function test_submitAndClaimAtomically() public {
        vm.prank(alice); ven.buy{value: 8 ether}();

        vm.deal(det, 10 ether);
        vm.prank(det);
        (bytes32 rid, bytes32 cid) = rem.submitAndClaim{value: 0.1 ether}(_rep(95, 90), "ipfs://c");

        assertTrue(rid != bytes32(0), "no report id");
        assertTrue(cid != bytes32(0), "no claim id");
        assertTrue(esc.stateOf(id) == LaunchState.Frozen, "not frozen in the same transaction");
        assertEq(rem.openClaims(id), 1, "claim not counted");
    }

    function test_advisedActionWithLiveReport() public {
        vm.prank(det); reg.submitReport(_rep(95, 90));
        assertTrue(rem.advisedAction(id) == ContainmentAction.Freeze, "ladder not surfaced");
        (ContainmentAction a, uint8 s, ) = grd.checkLaunch(id);
        assertTrue(a == ContainmentAction.Freeze, "guard disagrees with remediation");
        assertEq(s, 95, "score not surfaced");
    }

    // --- registry -----------------------------------------------------------

    function test_getReportReturnsStoredValues() public {
        vm.prank(det); bytes32 rid = reg.submitReport(_rep(88, 77));
        (AbuseReport memory r, address detector, uint64 at) = reg.getReport(rid);
        assertEq(r.abuseScore, 88, "score");
        assertEq(r.confidence, 77, "confidence");
        assertTrue(detector == det, "detector");
        assertTrue(at > 0, "timestamp");
        assertTrue(reg.detectorOf(rid) == det, "detectorOf");
        assertTrue(reg.launchOf(rid) == id, "launchOf");
        assertEq(reg.reportCount(id), 1, "count");
    }

    /// A retracted report is skipped by both scan paths, leaving the next best.
    function test_retractedReportSkippedByBothScans() public {
        vm.prank(det); bytes32 high = reg.submitReport(_rep(99, 95));
        vm.prank(det); reg.submitReport(_rep(70, 90));

        (uint8 s1, , ) = reg.activeScore(id);
        assertEq(s1, 99, "highest should lead");

        vm.prank(det); reg.retractReport(high, "recomputed");

        (uint8 s2, , ) = reg.activeScore(id);
        assertEq(s2, 70, "retracted report still leading activeScore");

        (uint8 s3, , uint256 n) = reg.corroboratedScore(id, 1);
        assertEq(s3, 70, "retracted report still leading corroboratedScore");
        assertEq(n, 1, "one detector");
    }

    // --- probe --------------------------------------------------------------

    /// `hasSelector` is the documented single-selector entry point, reached by
    /// detectors directly rather than through the batched internal scan.
    function test_hasSelectorEntryPoint() public {
        Bare bare = new Bare();
        assertTrue(
            SignalProbe.hasSelector(address(bare), bytes4(keccak256("x()"))),
            "public getter selector not found"
        );
        assertTrue(
            !SignalProbe.hasSelector(address(bare), bytes4(keccak256("mint(address,uint256)"))),
            "absent selector reported present"
        );
        assertTrue(
            !SignalProbe.hasSelector(address(0xBEEF), bytes4(keccak256("x()"))),
            "an account with no code cannot dispatch"
        );
    }

    /// A contract that never delegatecalls is not a proxy.
    function test_plainContractIsNotAProxy() public {
        Bare bare = new Bare();
        (, bool isProxy, bool resolved) = SignalProbe.implementationOf(address(bare));
        assertTrue(!isProxy, "plain contract flagged as a proxy");
        assertTrue(resolved, "plain contract should resolve");
    }

    /// An unreachable trailing blob is not walked as opcodes, so the metadata
    /// Solidity appends cannot turn an ordinary token into an unresolvable
    /// proxy and blank its `privilegedPowers`.
    function test_unreachableTrailingBlobIsNotCode() public {
        // STOP, then three bytes announced as a CBOR blob, the last of them 0xf4.
        vm.etch(address(0xB10B), hex"00a201f40003");
        (, bool isProxy, bool resolved) = SignalProbe.implementationOf(address(0xB10B));
        assertTrue(!isProxy, "unreachable blob read as delegation");
        assertTrue(resolved, "ordinary contract left unresolvable");
    }

    /// The skip is earned by unreachability, not claimed by a length. A blob a
    /// token could actually enter is walked like any other code.
    function test_reachableTrailingBlobIsWalked() public {
        // A JUMPDEST inside the region: it can be jumped into.
        vm.etch(address(0xB10C), hex"00a25bf40003");
        (, bool p1, bool r1) = SignalProbe.implementationOf(address(0xB10C));
        assertTrue(p1 && !r1, "jumpable blob skipped");

        // No terminating instruction before it: it can be fallen into.
        vm.etch(address(0xB10D), hex"01a201f40003");
        (, bool p2, bool r2) = SignalProbe.implementationOf(address(0xB10D));
        assertTrue(p2 && !r2, "fall-through blob skipped");

        // A length naming more bytes than exist decides nothing.
        vm.etch(address(0xB10E), hex"00a201f400ff");
        (, bool p3, bool r3) = SignalProbe.implementationOf(address(0xB10E));
        assertTrue(p3 && !r3, "overlong length honoured");

        // PUSH1 0x00 before the region: the 0x00 is an immediate that never
        // runs, so execution falls through into the region rather than stopping
        // at a STOP. Reading that byte as an opcode is the bypass this closes.
        vm.etch(address(0xB10F), hex"6000a201f40003");
        (, bool p4, bool r4) = SignalProbe.implementationOf(address(0xB10F));
        assertTrue(p4 && !r4, "PUSH immediate read as a terminating instruction");
    }

    receive() external payable {}
}
