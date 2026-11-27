// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

// Vectors for erc.presign.address.delegate-single-caller and erc.presign.address.delegate-unbounded-outflow.
//
// Each case gives an EIP-7702 account the code 0xef0100 || delegate and 100 ether. Every candidate caller then
// tries to move 1 wei, and the whole balance to each of two recipients. The account itself, and a caller that
// carries a signature of the account, are not outside callers and are not counted.
//
//   single-caller = exactly one candidate succeeds, and it is a fixed (non-random) address
//   unbounded     = some candidate moves the whole balance to both recipients, each in one call
//
// The harness is told which fixed callers to try. Finding them in bytecode and storage is the hard part of a real
// source and is not done here, so `false` means only "no outside caller found among those tried" (see x2).
//
// V7 is a stand-in with the shape of a sweeper delegate seen on Ethereum: four value-moving functions, all limited
// to one hard-coded caller. It is written for this test; it is not any deployed contract's code.

// ---------------------------------------------------------------- delegates

contract Echo {
    function self() external view returns (address) {
        return address(this);
    }
}

/// V1: only the account itself may call.
contract V1SelfOnly {
    function execute(address to, uint256 amount, bytes calldata data) external {
        require(msg.sender == address(this), "self only");
        (bool ok,) = to.call{value: amount}(data);
        require(ok, "call failed");
    }
}

/// V2: anyone may call, but only with a signature of the account.
contract V2SignedOnly {
    uint256 public nonce;

    function executeSigned(address to, uint256 amount, bytes calldata sig) external {
        require(sig.length == 65, "no signature");
        bytes32 digest = keccak256(abi.encode(block.chainid, address(this), to, amount, nonce));
        (bytes32 r, bytes32 s) = (bytes32(sig[0:32]), bytes32(sig[32:64]));
        require(ecrecover(digest, uint8(sig[64]), r, s) == address(this), "bad signature");
        nonce++;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "call failed");
    }
}

/// Base for the withdrawETH-shaped delegates V3 to V6 and x2.
abstract contract Withdrawer {
    function _allowed(address caller) internal view virtual returns (bool);

    function _cap() internal pure virtual returns (uint256) {
        return type(uint256).max;
    }

    function withdrawETH(address to, uint256 amount) external {
        require(_allowed(msg.sender), "not allowed");
        require(amount <= _cap(), "over cap");
        (bool ok,) = to.call{value: amount}("");
        require(ok, "call failed");
    }
}

address constant FIXED_A = address(0xC0FFEE);
address constant FIXED_B = address(0xD00D);
address constant HIDDEN = address(0xABCDEF);

/// V3: one hard-coded caller, no limit.
contract V3Fixed is Withdrawer {
    function _allowed(address c) internal pure override returns (bool) {
        return c == FIXED_A;
    }
}

/// V4: V3 plus a path for the account itself.
contract V4FixedOrSelf is Withdrawer {
    function _allowed(address c) internal view override returns (bool) {
        return c == FIXED_A || c == address(this);
    }
}

/// V5: V3 with a cap of 1 ether per call.
contract V5FixedCapped is Withdrawer {
    function _allowed(address c) internal pure override returns (bool) {
        return c == FIXED_A;
    }

    function _cap() internal pure override returns (uint256) {
        return 1 ether;
    }
}

/// V6: two hard-coded callers, no limit.
contract V6TwoFixed is Withdrawer {
    function _allowed(address c) internal pure override returns (bool) {
        return c == FIXED_A || c == FIXED_B;
    }
}

/// x2: one hard-coded caller that the harness does not try.
contract X2Hidden is Withdrawer {
    function _allowed(address c) internal pure override returns (bool) {
        return c == HIDDEN;
    }
}

interface IBalance {
    function transfer(address to, uint256 amount) external returns (bool);
}

/// V7: stand-in sweeper, four value-moving functions behind one hard-coded caller.
contract V7SweeperStandIn {
    address public constant authorizedCaller = address(0x5EEEE7);

    modifier onlyCaller() {
        require(msg.sender == authorizedCaller, "not authorized");
        _;
    }

    /// Moves the whole balance of each listed token, address(0) being the native asset.
    function sweep(address to, address[] calldata tokens) external onlyCaller {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0)) {
                (bool ok,) = to.call{value: address(this).balance}("");
                require(ok, "eth failed");
            } else {
                uint256 bal = TestToken(tokens[i]).balanceOf(address(this));
                require(IBalance(tokens[i]).transfer(to, bal), "token failed");
            }
        }
    }

    function withdrawETH(address to, uint256 amount) external onlyCaller {
        (bool ok,) = to.call{value: amount}("");
        require(ok, "eth failed");
    }

    function withdrawToken(address token, address to, uint256 amount) external onlyCaller {
        require(IBalance(token).transfer(to, amount), "token failed");
    }

    /// Calls `execute(to, value, data)` on `target`, sending `value` with it.
    function callExecute(address target, address to, uint256 value, bytes calldata data) external onlyCaller {
        (bool ok,) = target.call{value: value}(abi.encodeWithSignature("execute(address,uint256,bytes)", to, value, data));
        require(ok, "execute failed");
    }
}

contract TestToken {
    mapping(address => uint256) public balanceOf;

    function set(address who, uint256 amount) external {
        balanceOf[who] = amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// Forwards what it receives to `to`.
contract Forwarder {
    function execute(address to, uint256, bytes calldata) external payable {
        (bool ok,) = to.call{value: msg.value}("");
        require(ok, "forward failed");
    }
}

// ---------------------------------------------------------------- harness

contract PreSignDelegateVectorsTest is Test {
    uint256 internal constant ACCOUNT_KEY = 0xA11CE;
    address internal constant TO_A = address(0xBEEF01);
    address internal constant TO_B = address(0xBEEF02);
    address internal constant RANDOM_1 = address(0x1111111111111111111111111111111111111111);
    address internal constant RANDOM_2 = address(0x2222222222222222222222222222222222222222);

    enum Shape {
        Execute,
        ExecuteSigned,
        WithdrawETH
    }

    address internal account;

    function setUp() public {
        account = vm.addr(ACCOUNT_KEY);
    }

    function _delegateTo(address delegate) internal {
        vm.etch(account, abi.encodePacked(hex"ef0100", delegate));
        vm.deal(account, 100 ether);
    }

    function _calldata(Shape shape, address to, uint256 amount) internal pure returns (bytes memory) {
        if (shape == Shape.Execute) {
            return abi.encodeWithSignature("execute(address,uint256,bytes)", to, amount, bytes(""));
        }
        if (shape == Shape.ExecuteSigned) {
            return abi.encodeWithSignature("executeSigned(address,uint256,bytes)", to, amount, bytes(""));
        }
        return abi.encodeWithSignature("withdrawETH(address,uint256)", to, amount);
    }

    function _attempt(address caller, bytes memory data) internal returns (bool ok) {
        vm.deal(account, 100 ether);
        vm.prank(caller);
        (ok,) = account.call(data);
    }

    /// Returns (delegate-single-caller, delegate-unbounded-outflow) over the given candidates.
    function _classify(Shape shape, address[] memory candidates) internal returns (bool single, bool unbounded) {
        uint256 succeeded;
        uint256 succeededFixed;
        for (uint256 i = 0; i < candidates.length; i++) {
            address c = candidates[i];
            bool small = _attempt(c, _calldata(shape, TO_A, 1));
            bool allToA = _attempt(c, _calldata(shape, TO_A, 100 ether));
            bool allToB = _attempt(c, _calldata(shape, TO_B, 100 ether));
            if (small || allToA) {
                succeeded++;
                if (c != RANDOM_1 && c != RANDOM_2) succeededFixed++;
            }
            if (allToA && allToB) unbounded = true;
        }
        single = succeeded == 1 && succeededFixed == 1;
    }

    function _candidates(address extra1, address extra2) internal pure returns (address[] memory list) {
        list = new address[](extra2 == address(0) ? 3 : 4);
        list[0] = RANDOM_1;
        list[1] = RANDOM_2;
        list[2] = extra1;
        if (extra2 != address(0)) list[3] = extra2;
    }

    // ------------------------------------------------------------ V1 to V7

    function test_sanity_delegated_code_runs_as_the_account() public {
        _delegateTo(address(new Echo()));
        (bool ok, bytes memory ret) = account.call(abi.encodeWithSignature("self()"));
        assertTrue(ok);
        assertEq(abi.decode(ret, (address)), account);
    }

    function test_V1_self_only() public {
        _delegateTo(address(new V1SelfOnly()));
        (bool single, bool unbounded) = _classify(Shape.Execute, _candidates(FIXED_A, address(0)));
        assertFalse(single);
        assertFalse(unbounded);
        assertTrue(_attempt(account, _calldata(Shape.Execute, TO_A, 1)), "the account itself can call");
    }

    function test_V2_signature_of_the_account_only() public {
        _delegateTo(address(new V2SignedOnly()));
        (bool single, bool unbounded) = _classify(Shape.ExecuteSigned, _candidates(FIXED_A, address(0)));
        assertFalse(single);
        assertFalse(unbounded);

        // Any caller bringing the account's signature succeeds; that path is excluded by definition.
        bytes32 digest = keccak256(abi.encode(block.chainid, account, TO_A, uint256(1), uint256(0)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ACCOUNT_KEY, digest);
        bytes memory data =
            abi.encodeWithSignature("executeSigned(address,uint256,bytes)", TO_A, uint256(1), abi.encodePacked(r, s, v));
        assertTrue(_attempt(RANDOM_1, data));
    }

    function test_V3_one_fixed_caller() public {
        _delegateTo(address(new V3Fixed()));
        (bool single, bool unbounded) = _classify(Shape.WithdrawETH, _candidates(FIXED_A, address(0)));
        assertTrue(single);
        assertTrue(unbounded);
    }

    function test_V4_fixed_caller_plus_self_path() public {
        _delegateTo(address(new V4FixedOrSelf()));
        (bool single, bool unbounded) = _classify(Shape.WithdrawETH, _candidates(FIXED_A, address(0)));
        assertTrue(single);
        assertTrue(unbounded);
    }

    function test_V5_fixed_caller_with_per_call_cap() public {
        _delegateTo(address(new V5FixedCapped()));
        (bool single, bool unbounded) = _classify(Shape.WithdrawETH, _candidates(FIXED_A, address(0)));
        assertTrue(single);
        assertFalse(unbounded);
    }

    function test_V6_two_fixed_callers() public {
        _delegateTo(address(new V6TwoFixed()));
        (bool single, bool unbounded) = _classify(Shape.WithdrawETH, _candidates(FIXED_A, FIXED_B));
        assertFalse(single);
        assertTrue(unbounded);
    }

    function test_V7_stand_in_sweeper() public {
        V7SweeperStandIn d = new V7SweeperStandIn();
        _delegateTo(address(d));
        (bool single, bool unbounded) = _classify(Shape.WithdrawETH, _candidates(d.authorizedCaller(), address(0)));
        assertTrue(single);
        assertTrue(unbounded);
    }

    // V7, every value-moving function: only the hard-coded caller succeeds.

    function _v7Call(uint256 fn, address caller, TestToken token, address forwarder) internal returns (bool ok) {
        vm.deal(account, 100 ether);
        token.set(account, 1000);
        bytes memory data;
        if (fn == 0) {
            address[] memory tokens = new address[](2);
            tokens[0] = address(token);
            tokens[1] = address(0);
            data = abi.encodeWithSignature("sweep(address,address[])", TO_A, tokens);
        } else if (fn == 1) {
            data = abi.encodeWithSignature("withdrawETH(address,uint256)", TO_A, 100 ether);
        } else if (fn == 2) {
            data = abi.encodeWithSignature("withdrawToken(address,address,uint256)", address(token), TO_A, 1000);
        } else {
            data = abi.encodeWithSignature(
                "callExecute(address,address,uint256,bytes)", forwarder, TO_A, 100 ether, bytes("")
            );
        }
        vm.prank(caller);
        (ok,) = account.call(data);
    }

    function test_V7_all_four_functions() public {
        V7SweeperStandIn d = new V7SweeperStandIn();
        _delegateTo(address(d));
        TestToken token = new TestToken();
        address forwarder = address(new Forwarder());
        for (uint256 fn = 0; fn < 4; fn++) {
            assertFalse(_v7Call(fn, RANDOM_1, token, forwarder));
            assertFalse(_v7Call(fn, RANDOM_2, token, forwarder));
            assertTrue(_v7Call(fn, d.authorizedCaller(), token, forwarder));
        }
    }

    // ------------------------------------------------------------ checks on the harness

    /// x1: the native EIP-7702 path installs the same code as vm.etch, and behaves the same.
    function test_x1_native_7702_matches_etch() public {
        address d = address(new V3Fixed());
        VmSafe.SignedDelegation memory sd = vm.signDelegation(d, ACCOUNT_KEY);
        vm.attachDelegation(sd);
        vm.deal(account, 100 ether);
        vm.prank(FIXED_A);
        (bool okFixed,) = account.call(_calldata(Shape.WithdrawETH, TO_A, 100 ether));
        assertEq(account.code, abi.encodePacked(hex"ef0100", d));
        assertTrue(okFixed);
        vm.deal(account, 100 ether);
        vm.prank(RANDOM_1);
        (bool okRandom,) = account.call(_calldata(Shape.WithdrawETH, TO_A, 1));
        assertFalse(okRandom);
    }

    /// x2: a fixed caller outside the tried set reads false for both kinds, yet can take the whole balance.
    function test_x2_untried_fixed_caller_reads_false() public {
        _delegateTo(address(new X2Hidden()));
        (bool single, bool unbounded) = _classify(Shape.WithdrawETH, _candidates(FIXED_A, address(0)));
        assertFalse(single);
        assertFalse(unbounded);
        assertTrue(_attempt(HIDDEN, _calldata(Shape.WithdrawETH, TO_A, 100 ether)));
    }

    /// x3: delegate-unbounded-outflow is per call: a 1 ether cap reads false, and 100 calls still empty the account.
    function test_x3_per_call_cap_does_not_bound_total_outflow() public {
        _delegateTo(address(new V5FixedCapped()));
        for (uint256 i = 0; i < 100; i++) {
            vm.prank(FIXED_A);
            (bool ok,) = account.call(_calldata(Shape.WithdrawETH, TO_A, 1 ether));
            assertTrue(ok);
        }
        assertEq(account.balance, 0);
        assertEq(TO_A.balance, 100 ether);
    }

    /// x4: on the V7 stand-in, every caller other than the hard-coded one reverts, on every function.
    function testFuzz_x4_only_the_hard_coded_caller(address caller, uint8 fn) public {
        V7SweeperStandIn d = new V7SweeperStandIn();
        vm.assume(caller != d.authorizedCaller() && caller != account && caller != address(vm));
        vm.assume(caller.code.length == 0);
        _delegateTo(address(d));
        TestToken token = new TestToken();
        address forwarder = address(new Forwarder());
        assertFalse(_v7Call(uint256(fn) % 4, caller, token, forwarder));
    }
}
