// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {LaunchDirectory} from "../src/LaunchDirectory.sol";
import {LaunchEscrow} from "../src/LaunchEscrow.sol";
import {IERC20} from "../src/IERC20.sol";

contract Tok {
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

contract TokBuyer {
    function claim(LaunchEscrow e, bytes32 id) external returns (uint256) { return e.claimRefund(id); }
}

/// @dev Drives the ERC-20 push-then-account path. The handler is venue and
///      remediation, and deliberately sometimes under-delivers before recording.
contract TokHandler {
    LaunchEscrow public immutable escrow;
    Tok public immutable tok;
    bytes32 public id;
    TokBuyer[3] public buyers;

    constructor(LaunchEscrow e, Tok t) {
        escrow = e; tok = t;
        for (uint256 i = 0; i < 3; ++i) buyers[i] = new TokBuyer();
    }

    function open(uint64 s, uint64 span) external {
        if (id != bytes32(0)) return;
        tok.transfer(address(escrow), 10 ether);
        id = escrow.registerLaunch(address(0x11), address(0xD1), address(tok), 10 ether, s, s + span);
    }

    function _b(uint256 s) internal view returns (TokBuyer) { return buyers[s % 3]; }

    /// @dev `deliver` is intentionally allowed to differ from `amount`: a venue
    ///      that under-delivers must be rejected, never silently credited.
    function buy(uint256 seed, uint96 amount, uint96 deliver) external {
        uint256 amt = uint256(amount) % 20 ether + 1;
        uint256 del = uint256(deliver) % 25 ether;
        if (tok.balanceOf(address(this)) < del) return;
        tok.transfer(address(escrow), del);
        try escrow.recordPurchase(id, address(_b(seed)), amt, amt) {} catch {}
    }

    function release() external { try escrow.releaseProceeds(id) {} catch {} }
    function openRefund(uint96 b) external { try escrow.openRefund(id, uint256(b) % 5 ether) {} catch {} }
    function claim(uint256 seed) external { try _b(seed).claim(escrow, id) {} catch {} }
    function releaseBond(uint96 a) external {
        try escrow.releaseBond(id, address(this), uint256(a) % 5 ether) {} catch {}
    }
    function sale(uint256 seed, uint96 a) external {
        try escrow.recordSale(id, address(_b(seed)), uint256(a) % 10 ether) {} catch {}
    }
}

contract Erc20InvariantTest is TestBase {
    LaunchEscrow internal escrow;
    Tok internal tok;
    TokHandler internal h;
    address[] internal _t;

    function setUp() public {
        LaunchDirectory d = new LaunchDirectory();
        address predicted = _create(address(this), 4);
        escrow = new LaunchEscrow(predicted, d);
        tok = new Tok();
        h = new TokHandler(escrow, tok);
        require(address(h) == predicted, "handler mismatch");
        tok.mint(address(h), 1_000 ether);
        h.open(uint64(block.timestamp), 30 days);
        _t.push(address(h));
    }

    function targetContracts() public view returns (address[] memory) { return _t; }

    /// The escrow must always hold at least what it has taken responsibility for.
    function invariant_accountedNeverExceedsBalance() public view {
        assertLe(
            escrow.accountedOf(address(tok)),
            IERC20(address(tok)).balanceOf(address(escrow)),
            "escrow promised more tokens than it holds"
        );
    }

    function _create(address d, uint8 n) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), d, bytes1(n))))));
    }
}
