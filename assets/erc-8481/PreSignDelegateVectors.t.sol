// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

// Test vectors for the delegate-* finding kinds of the Agent Pre-Sign Risk Report
// (delegate-single-caller, delegate-unbounded-outflow). Foundry, EVM prague.
// An account is simulated as code = 0xef0100 || delegate address (EIP-7702) with 100 ETH on it.
// For every delegate, each candidate caller tries: 1 wei, and the whole balance to each of two recipients.
// The account itself, and a caller that brings a signature of the account, are not counted as outside callers.
// V1 to V6 are small contracts written for this test. V7 is the deployed runtime code of a real delegate
// (0x63e842B054Bd624a465454D533C33F573e9c6fAe, 1674 bytes, read from Ethereum mainnet), embedded below so that
// the test runs without an RPC. The harness is handed the fixed caller; finding such addresses in bytecode and
// storage is the hard part and is not done here: a false only means "no outside caller found among those tried".
// Tests x1 to x5 are checks on the test itself (native 7702 path vs vm.etch, a fixed caller outside the candidate list,
// per-call cap vs total outflow, fuzzing the real delegate's callers, and its ETH sweep branch).

// ---- delegates (what a 7702 account's code points at) ----
contract Who { function who() external view returns (address) { return address(this); } }

// ordinary smart-account style: only the account itself may call
contract SelfOnly {
    function execute(address to, uint256 v, bytes calldata d) external {
        require(msg.sender == address(this), "NotSelf");
        (bool ok,) = to.call{value: v}(d); require(ok, "fail");
    }
}
// anyone may call, but only with a signature of the account
contract SigOnly {
    uint256 public nonce;
    function executeSigned(address to, uint256 v, bytes calldata sig) external {
        require(sig.length == 65, "NoSig");
        bytes32 h = keccak256(abi.encode(block.chainid, address(this), to, v, nonce));
        bytes32 r = bytes32(sig[0:32]); bytes32 s = bytes32(sig[32:64]); uint8 vv = uint8(sig[64]);
        require(ecrecover(h, vv, r, s) == address(this), "BadSig");
        nonce++;
        (bool ok,) = to.call{value: v}(""); require(ok, "fail");
    }
}
// sweeper shape: one hard-coded caller, no limits
contract FixedCaller {
    address constant C = address(0xC0FFEE);
    function withdrawETH(address to, uint256 amt) external {
        require(msg.sender == C, "NotAuthorized");
        (bool ok,) = to.call{value: amt}(""); require(ok, "fail");
    }
}
// same sweeper plus an extra path for the account itself (the evasion case)
contract FixedCallerOrSelf {
    address constant C = address(0xC0FFEE);
    function withdrawETH(address to, uint256 amt) external {
        require(msg.sender == C || msg.sender == address(this), "NotAuthorized");
        (bool ok,) = to.call{value: amt}(""); require(ok, "fail");
    }
}
// one fixed caller, but a per-call cap of 1 ether
contract CappedFixed {
    address constant C = address(0xC0FFEE);
    function withdrawETH(address to, uint256 amt) external {
        require(msg.sender == C, "NotAuthorized");
        require(amt <= 1 ether, "Cap");
        (bool ok,) = to.call{value: amt}(""); require(ok, "fail");
    }
}
// two fixed callers, no limits
contract TwoCallers {
    address constant C = address(0xC0FFEE);
    address constant D = address(0xD00D);
    function withdrawETH(address to, uint256 amt) external {
        require(msg.sender == C || msg.sender == D, "NotAuthorized");
        (bool ok,) = to.call{value: amt}(""); require(ok, "fail");
    }
}

// ---- helpers for the V7b probe ----
contract MockTok {
    mapping(address => uint256) public balanceOf;
    function mint(address a, uint256 v) external { balanceOf[a] = v; }
    function transfer(address to, uint256 v) external returns (bool) { balanceOf[msg.sender] -= v; balanceOf[to] += v; return true; }
}
contract Exec { function execute(address, uint256, bytes calldata) external payable {} }


struct VmSignedDelegation { uint8 v; bytes32 r; bytes32 s; uint64 nonce; address implementation; }
// fixed caller that is not in the harness's candidate list
contract HiddenCaller {
    address constant C = address(0xABCDEF);
    function withdrawETH(address to, uint256 amt) external {
        require(msg.sender == C, "NotAuthorized");
        (bool ok,) = to.call{value: amt}(""); require(ok, "fail");
    }
}

struct caller_t { address a; bool isSelf; }

contract PreSignDelegateVectorsTest is Test {
    uint256 constant PK = 0xA11CE;
    address acct;
    address constant REC1 = address(0xBEEF01);
    address constant REC2 = address(0xBEEF02);
    address constant RAND1 = address(0x1111111111111111111111111111111111111111);
    address constant RAND2 = address(0x2222222222222222222222222222222222222222);
    address constant FIX1 = address(0xC0FFEE);
    address constant FIX2 = address(0xD00D);
    // the one hard-coded caller inside the real delegate's code (it also answers authorizedCaller())
    address constant CASE_CALLER = 0x7C8601d4645b93cea45F71e118A729332e6B5CA0;
    address constant REAL_DELEGATE = 0x63e842B054Bd624a465454D533C33F573e9c6fAe;
    // deployed runtime code of REAL_DELEGATE, Ethereum mainnet, 1674 bytes
    bytes constant REAL_DELEGATE_CODE = hex"6080604052600436101561001a575b3615610018575f80fd5b005b5f3560e01c806301e336671461049f578063043ff9d2146103375780634782f779146102f65780638a179be414610087576397dc97cb0361000e5734610083575f366003190112610083576020604051737c8601d4645b93cea45f71e118a729332e6b5ca08152f35b5f80fd5b34610083576040366003190112610083576100a06104e9565b60243567ffffffffffffffff811161008357366023820112156100835780600401359067ffffffffffffffff8211610083573660248360051b8301011161008357737c8601d4645b93cea45f71e118a729332e6b5ca033036102e7575f5b82811015610018576024600582901b830101356001600160a01b038116919082810361008357826101be57504791670de0b6b3a76400008311610148575b50600191505b016100fe565b670de0b6b3a763ffff1983019283116101aa575f808080600196878060a01b038b165af161017461056f565b5061013c577f394e1e4ba4d16d4e4c835649c554cd62437474ccefbb493591e6af3ce7c6c479602060405160038152a28561013c565b634e487b7160e01b5f52601160045260245ffd5b915f8060405160208101906370a0823160e01b8252306024820152602481526101e8604482610539565b5190865afa926101f661056f565b931580156102dc575b6102a857602084805181010312610083576020600194015180610225575b505050610142565b5f91829182604051602081019263a9059cbb60e01b8452898060a01b038d16602483015260448201526044815261025d606482610539565b51925af161026961056f565b5015610277575b808061021d565b7f394e1e4ba4d16d4e4c835649c554cd62437474ccefbb493591e6af3ce7c6c479602060405160028152a285610270565b50600192507f394e1e4ba4d16d4e4c835649c554cd62437474ccefbb493591e6af3ce7c6c4796020604051858152a2610142565b5060208451106101ff565b63ea8e4eb560e01b5f5260045ffd5b346100835760403660031901126100835761030f6104e9565b737c8601d4645b93cea45f71e118a729332e6b5ca033036102e7576100189060243590610618565b60803660031901126100835761034b6104e9565b6103536104ff565b60643567ffffffffffffffff811161008357366023820112156100835780600401359167ffffffffffffffff831161008357366024848401011161008357737c8601d4645b93cea45f71e118a729332e6b5ca033036102e757833b1561048157602461041a60a45f95948587966040519586936020850198635b0e93fb60e11b8a5260018060a01b031682860152604435604486015260606064860152826084860152018484013786838284010152601f801991011681010301601f198101835282610539565b519034855af19061042961056f565b9115610449576040516020808252819061044590820185610515565b0390f35b604080516373c78f0360e11b81526001600160a01b039092166004830152602482015290819061047d906044830190610515565b0390fd5b63ca05110160e01b5f9081526001600160a01b038516600452602490fd5b34610083576060366003190112610083576104b86104e9565b6104c06104ff565b90737c8601d4645b93cea45f71e118a729332e6b5ca033036102e75761001891604435916105ae565b600435906001600160a01b038216820361008357565b602435906001600160a01b038216820361008357565b805180835260209291819084018484015e5f828201840152601f01601f1916010190565b90601f8019910116810190811067ffffffffffffffff82111761055b57604052565b634e487b7160e01b5f52604160045260245ffd5b3d156105a9573d9067ffffffffffffffff821161055b576040519161059e601f8201601f191660200184610539565b82523d5f602084013e565b606090565b9190918115610613575f9283809360405190602082019363a9059cbb60e01b855260018060a01b031660248301526044820152604481526105f0606482610539565b51925af16105fc61056f565b501561060457565b63022e258160e11b5f5260045ffd5b505050565b8115610650575f918291829182916001600160a01b03165af161063961056f565b501561064157565b63b12d13eb60e01b5f5260045ffd5b505056fea2646970667358221220344569a8498384617633b23a4eac46a7f371fa5f36b3cda0cfc3f8bc3855085564736f6c634300081c0033";

    function setUp() public { acct = vm.addr(PK); }

    function _signNative(address d) internal returns (VmSignedDelegation memory out) {
        VmSafe.SignedDelegation memory sd = vm.signDelegation(d, PK);
        out = VmSignedDelegation(sd.v, sd.r, sd.s, sd.nonce, sd.implementation);
    }

    function _delegate(address d) internal { vm.etch(acct, abi.encodePacked(hex"ef0100", d)); vm.deal(acct, 100 ether); }

    function _cd(uint8 k, address to, uint256 amt) internal pure returns (bytes memory) {
        if (k == 0) return abi.encodeWithSignature("execute(address,uint256,bytes)", to, amt, bytes(""));
        if (k == 1) return abi.encodeWithSignature("executeSigned(address,uint256,bytes)", to, amt, bytes(""));
        return abi.encodeWithSignature("withdrawETH(address,uint256)", to, amt);
    }

    function _try(address caller, uint8 k, address to, uint256 amt) internal returns (bool ok) {
        vm.deal(acct, 100 ether);
        vm.prank(caller);
        (ok,) = acct.call(_cd(k, to, amt));
    }

    // returns (singleCaller, unboundedOutflow); logs every probe
    function _classify(string memory name, uint8 k, address[] memory cands) internal returns (bool single, bool outflow) {
        bool selfOk = _try(acct, k, REC1, 1);
        uint256 working; uint256 workingFixed; bool fullToBoth = false;
        for (uint256 i = 0; i < cands.length; i++) {
            bool tiny = _try(cands[i], k, REC1, 1);
            bool full1 = _try(cands[i], k, REC1, 100 ether);
            bool full2 = _try(cands[i], k, REC2, 100 ether);
            console2.log(string.concat("PROBE ", name, " caller=", vm.toString(cands[i]), " 1wei=", tiny ? "ok" : "revert", " full->A=", full1 ? "ok" : "revert", " full->B=", full2 ? "ok" : "revert"));
            if (tiny || full1) { working++; if (cands[i] != RAND1 && cands[i] != RAND2) workingFixed++; }
            if (full1 && full2) fullToBoth = true;
        }
        single = (working == 1 && workingFixed == 1);
        outflow = fullToBoth;
        console2.log(string.concat("PROBE ", name, " caller=account-itself 1wei=", selfOk ? "ok" : "revert", " (not counted)"));
        console2.log(string.concat("VECTOR ", name, ": delegate-single-caller=", single ? "true" : "false", " delegate-unbounded-outflow=", outflow ? "true" : "false"));
    }

    function _c(bool withSecond) internal pure returns (address[] memory a) {
        a = new address[](withSecond ? 4 : 3);
        a[0] = RAND1; a[1] = RAND2; a[2] = FIX1;
        if (withSecond) a[3] = FIX2;
    }

    function test_00_sanity_delegation_runs_as_account() public {
        address w = address(new Who()); _delegate(w);
        (bool ok, bytes memory r) = acct.call(abi.encodeWithSignature("who()"));
        console2.log(string.concat("SANITY delegated call ok=", ok ? "true" : "false", " returned=", ok ? vm.toString(abi.decode(r, (address))) : "-", " account=", vm.toString(acct)));
        assertTrue(ok);
        assertEq(abi.decode(r, (address)), acct);
    }

    function test_v1_self_only_ordinary_smart_account() public {
        _delegate(address(new SelfOnly()));
        (bool s, bool o) = _classify("V1 self-only delegate", 0, _c(false));
        assertTrue(!s && !o);
    }

    function test_v2_signature_of_account_only() public {
        _delegate(address(new SigOnly()));
        (bool s, bool o) = _classify("V2 signature-of-account delegate", 1, _c(false));
        // a random caller WITH the account's signature succeeds, and is excluded by definition
        bytes32 h = keccak256(abi.encode(block.chainid, acct, REC1, uint256(1), uint256(0)));
        (uint8 v, bytes32 r, bytes32 ss) = vm.sign(PK, h);
        vm.deal(acct, 100 ether);
        vm.prank(RAND1);
        (bool ok,) = acct.call(abi.encodeWithSignature("executeSigned(address,uint256,bytes)", REC1, uint256(1), abi.encodePacked(r, ss, v)));
        console2.log(string.concat("PROBE V2 random caller WITH account signature 1wei=", ok ? "ok" : "revert", " (excluded: authorized by a signature of the account)"));
        assertTrue(ok);
        assertTrue(!s && !o);
    }

    function test_v3_fixed_caller_sweeper() public {
        _delegate(address(new FixedCaller()));
        (bool s, bool o) = _classify("V3 fixed-caller sweeper", 2, _c(false));
        assertTrue(s && o);
    }

    function test_v4_fixed_caller_plus_self_path_evasion() public {
        _delegate(address(new FixedCallerOrSelf()));
        (bool s, bool o) = _classify("V4 fixed caller + account self path", 2, _c(false));
        assertTrue(s && o);
    }

    function test_v5_fixed_caller_with_cap() public {
        _delegate(address(new CappedFixed()));
        (bool s, bool o) = _classify("V5 fixed caller, 1 ether cap per call", 2, _c(false));
        assertTrue(s && !o);
    }

    function test_v6_two_callers() public {
        _delegate(address(new TwoCallers()));
        (bool s, bool o) = _classify("V6 two fixed callers", 2, _c(true));
        assertTrue(!s && o);
    }

    function test_v7_real_delegate_runtime_code() public {
        vm.etch(REAL_DELEGATE, REAL_DELEGATE_CODE);
        _delegate(REAL_DELEGATE);
        address[] memory a = new address[](3);
        a[0] = RAND1; a[1] = RAND2; a[2] = CASE_CALLER;
        console2.log(string.concat("V7 code length=", vm.toString(REAL_DELEGATE_CODE.length)));
        (bool s, bool o) = _classify("V7 real delegate 0x63e8...6fae (deployed runtime code)", 2, a);
        assertTrue(s && o);
    }

    // V7b: every value-moving function of the real delegate, native and token, all callers
    function _nm(uint256 f) internal pure returns (string memory) {
        if (f == 0) return "sweep(to,[token])";
        if (f == 1) return "withdrawETH(to,100 ether)";
        if (f == 2) return "withdrawToken(token,to,1000)";
        return "callExecute(exec,to,1,0x)";
    }

    function _v7bCall(uint256 f, MockTok tok, address exec, caller_t memory who) internal returns (bool ok) {
        vm.deal(acct, 100 ether); tok.mint(acct, 1000); vm.deal(REC1, 0); tok.mint(REC1, 0);
        bytes memory cd;
        if (f == 0) {
            address[] memory toks = new address[](1); toks[0] = address(tok);
            cd = abi.encodeWithSignature("sweep(address,address[])", REC1, toks);
        } else if (f == 1) {
            cd = abi.encodeWithSignature("withdrawETH(address,uint256)", REC1, 100 ether);
        } else if (f == 2) {
            cd = abi.encodeWithSignature("withdrawToken(address,address,uint256)", address(tok), REC1, 1000);
        } else {
            cd = abi.encodeWithSignature("callExecute(address,address,uint256,bytes)", exec, REC1, 1, bytes(""));
        }
        vm.prank(who.a);
        (ok,) = acct.call(cd);
        string memory label = who.isSelf ? "account-itself" : vm.toString(who.a);
        console2.log(string.concat("PROBE V7b ", _nm(f), " caller=", label, " ", ok ? "ok" : "revert", " recipientEth=", vm.toString(REC1.balance), " recipientTok=", vm.toString(tok.balanceOf(REC1))));
    }

    function test_v7b_all_functions_real_delegate() public {
        vm.etch(REAL_DELEGATE, REAL_DELEGATE_CODE);
        _delegate(REAL_DELEGATE);
        MockTok tok = new MockTok();
        address exec = address(new Exec());
        uint256 outsideOk = 0; uint256 caseOk = 0;
        for (uint256 f = 0; f < 4; f++) {
            if (_v7bCall(f, tok, exec, caller_t(RAND1, false))) outsideOk++;
            if (_v7bCall(f, tok, exec, caller_t(RAND2, false))) outsideOk++;
            _v7bCall(f, tok, exec, caller_t(acct, true));
            if (_v7bCall(f, tok, exec, caller_t(CASE_CALLER, false))) caseOk++;
        }
        console2.log(string.concat("VECTOR V7b real delegate: random outside callers that succeeded=", vm.toString(outsideOk), " ; hard-coded caller successes (of 4 functions)=", vm.toString(caseOk)));
        assertEq(outsideOk, 0);
        assertGe(caseOk, 3);
    }

    // ---------- extra checks (attacks on the test itself) ----------

    // The vectors use vm.etch(0xef0100 || delegate). Cross-check against Foundry's native EIP-7702 path:
    // the account signs a delegation, it is attached to a transaction, and the resulting code is used.
    function test_x1_native_7702_matches_etch() public {
        address d = address(new FixedCaller());
        VmSignedDelegation memory sd = _signNative(d);
        vm.attachDelegation(VmSafe.SignedDelegation(sd.v, sd.r, sd.s, sd.nonce, sd.implementation));
        vm.deal(acct, 100 ether);
        vm.prank(FIX1);
        (bool okFixed,) = acct.call(_cd(2, REC1, 100 ether));
        console2.log(string.concat("X1 native 7702: code=", vm.toString(acct.code), " fixed caller ok=", okFixed ? "true" : "false"));
        assertEq(acct.code, abi.encodePacked(hex"ef0100", d));
        assertTrue(okFixed);
        vm.deal(acct, 100 ether);
        vm.prank(RAND1);
        (bool okRand,) = acct.call(_cd(2, REC1, 1));
        assertTrue(!okRand);
    }

    // A delegate whose fixed caller is NOT among the candidates reads false/false: a false is "not found", not "safe".
    function test_x2_fixed_caller_outside_candidate_list_reads_false() public {
        _delegate(address(new HiddenCaller()));
        (bool s, bool o) = _classify("X2 fixed caller not among candidates", 2, _c(false));
        assertTrue(!s && !o);
        // and it really is drainable by that caller:
        vm.deal(acct, 100 ether);
        vm.prank(address(0xABCDEF));
        (bool ok,) = acct.call(_cd(2, REC1, 100 ether));
        assertTrue(ok);
    }

    // delegate-unbounded-outflow is per call by definition: a per-call cap reads false, yet repeated calls drain everything.
    function test_x3_per_call_cap_does_not_bound_total_outflow() public {
        _delegate(address(new CappedFixed()));
        vm.deal(acct, 100 ether);
        for (uint256 i = 0; i < 100; i++) {
            vm.prank(FIX1);
            (bool ok,) = acct.call(_cd(2, REC1, 1 ether));
            require(ok, "cap call failed");
        }
        console2.log(string.concat("X3 after 100 calls of 1 ether: account balance=", vm.toString(acct.balance), " recipient=", vm.toString(REC1.balance)));
        assertEq(acct.balance, 0);
        assertEq(REC1.balance, 100 ether);
    }

    // Real delegate: any caller other than the hard-coded one reverts, on every value-moving function.
    function testFuzz_x4_real_delegate_only_hardcoded_caller(address caller, uint8 f) public {
        vm.assume(caller != CASE_CALLER && caller != acct && caller != address(vm) && caller.code.length == 0);
        vm.etch(REAL_DELEGATE, REAL_DELEGATE_CODE);
        _delegate(REAL_DELEGATE);
        MockTok tok = new MockTok();
        address exec = address(new Exec());
        bool ok = _v7bCall(uint256(f % 4), tok, exec, caller_t(caller, false));
        assertTrue(!ok);
    }

    // Real delegate: authorizedCaller() getter, and what the ETH branch of sweep (token = address(0)) moves.
    function test_x5_real_delegate_getter_and_eth_sweep() public {
        vm.etch(REAL_DELEGATE, REAL_DELEGATE_CODE);
        _delegate(REAL_DELEGATE);
        (bool g, bytes memory r) = acct.staticcall(abi.encodeWithSignature("authorizedCaller()"));
        assertTrue(g);
        assertEq(abi.decode(r, (address)), CASE_CALLER);
        address[] memory toks = new address[](1); toks[0] = address(0);
        vm.deal(REC1, 0);
        vm.prank(CASE_CALLER);
        (bool ok,) = acct.call(abi.encodeWithSignature("sweep(address,address[])", REC1, toks));
        console2.log(string.concat("X5 sweep ETH branch ok=", ok ? "true" : "false", " recipient=", vm.toString(REC1.balance), " left on account=", vm.toString(acct.balance)));
        assertTrue(ok);
    }
}
