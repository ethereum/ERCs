// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {LaunchDirectory} from "../src/LaunchDirectory.sol";
import {LaunchEscrow} from "../src/LaunchEscrow.sol";

/// @dev A buyer that can pull its own refund, since `claimRefund` is keyed on
///      `msg.sender` and the handler cannot claim on anyone's behalf.
contract Buyer {
    function claim(LaunchEscrow e, bytes32 id) external returns (uint256) {
        return e.claimRefund(id);
    }
    receive() external payable {}
}

/// @notice Drives the escrow through random but well-formed sequences while
///         keeping ghost accounts of everything that entered and left each
///         launch. Acts as both venue and remediation so every guarded path is
///         reachable.
contract Handler {
    LaunchEscrow public immutable escrow;
    bytes32[2] public ids;
    Buyer[3] public buyers;

    mapping(bytes32 => uint256) public tookIn;
    mapping(bytes32 => uint256) public paidOut;

    constructor(LaunchEscrow e) payable {
        escrow = e;
        for (uint256 i = 0; i < 3; ++i) buyers[i] = new Buyer();
    }

    function open(uint64 start, uint64 span) external {
        for (uint256 i = 0; i < 2; ++i) {
            if (ids[i] != bytes32(0)) continue;
            uint256 bond = 1 ether;
            ids[i] = escrow.registerLaunchNative{value: bond}(
                address(uint160(0x1000 + i)), address(uint160(0x2000 + i)), start, start + span
            );
            tookIn[ids[i]] += bond;
        }
    }

    function _id(uint256 s) internal view returns (bytes32) { return ids[s % 2]; }
    function _buyer(uint256 s) internal view returns (Buyer) { return buyers[s % 3]; }

    function buy(uint256 idSeed, uint256 buyerSeed, uint96 amount) external {
        bytes32 id = _id(idSeed);
        uint256 amt = uint256(amount) % 20 ether + 1;
        if (address(this).balance < amt) return;
        try escrow.recordPurchase{value: amt}(id, address(_buyer(buyerSeed)), amt, amt) {
            tookIn[id] += amt;
        } catch {}
    }

    function sell(uint256 idSeed, uint256 buyerSeed, uint96 amount) external {
        try escrow.recordSale(_id(idSeed), address(_buyer(buyerSeed)), uint256(amount) % 20 ether) {}
        catch {}
    }

    function release(uint256 idSeed) external {
        bytes32 id = _id(idSeed);
        try escrow.releaseProceeds(id) returns (uint256 amt) { paidOut[id] += amt; } catch {}
    }

    function markLinked(uint256 idSeed, uint256 buyerSeed) external {
        try escrow.markLinked(_id(idSeed), address(_buyer(buyerSeed))) {} catch {}
    }

    function freeze(uint256 idSeed) external {
        try escrow.freezeLaunch(_id(idSeed), bytes32(uint256(1))) {} catch {}
    }

    function unfreeze(uint256 idSeed) external {
        try escrow.unfreeze(_id(idSeed)) {} catch {}
    }

    function openRefund(uint256 idSeed, uint96 fromBond) external {
        bytes32 id = _id(idSeed);
        try escrow.openRefund(id, uint256(fromBond) % 2 ether) {} catch {}
    }

    function augmentRefund(uint256 idSeed, uint96 fromBond) external {
        try escrow.augmentRefund(_id(idSeed), uint256(fromBond) % 2 ether) {} catch {}
    }

    function claim(uint256 idSeed, uint256 buyerSeed) external {
        bytes32 id = _id(idSeed);
        try _buyer(buyerSeed).claim(escrow, id) returns (uint256 amt) { paidOut[id] += amt; }
        catch {}
    }

    function releaseBond(uint256 idSeed, uint96 amount) external {
        bytes32 id = _id(idSeed);
        uint256 amt = uint256(amount) % 1 ether;
        try escrow.releaseBond(id, address(this), amt) { paidOut[id] += amt; } catch {}
    }

    receive() external payable {}
}

/// @dev Fund-conservation invariants. Both fund-loss bugs found by hand review
///      violate these, so this is the check that should have caught them.
contract InvariantTest is TestBase {
    LaunchDirectory internal directory;
    LaunchEscrow    internal escrow;
    Handler         internal handler;

    address[] internal _targets;

    function setUp() public {
        directory = new LaunchDirectory();
        handler   = Handler(payable(address(0)));

        // The handler is both venue and remediation, so it can reach every path.
        address predicted = computeCreate(address(this), 3);
        escrow = new LaunchEscrow(predicted, directory);
        handler = new Handler{value: 500 ether}(escrow);
        require(address(handler) == predicted, "handler address mismatch");

        handler.open(uint64(block.timestamp), 30 days);

        _targets.push(address(handler));
    }

    /// @dev Foundry reads this to bound the fuzzer to the handler.
    function targetContracts() public view returns (address[] memory) {
        return _targets;
    }

    /// A launch must never pay out more than it took in. Violating this means
    /// one launch is spending another launch's escrowed funds.
    function invariant_launchNeverPaysOutMoreThanItTookIn() public view {
        for (uint256 i = 0; i < 2; ++i) {
            bytes32 id = handler.ids(i);
            if (id == bytes32(0)) continue;
            assertLe(
                handler.paidOut(id),
                handler.tookIn(id),
                "launch paid out more than it received"
            );
        }
    }

    /// The escrow must still hold everything it owes across all launches.
    function invariant_escrowRemainsSolvent() public view {
        uint256 owed;
        for (uint256 i = 0; i < 2; ++i) {
            bytes32 id = handler.ids(i);
            if (id == bytes32(0)) continue;
            owed += handler.tookIn(id) - handler.paidOut(id);
        }
        assertLe(owed, address(escrow).balance, "escrow is insolvent");
    }

    /// Released proceeds can never exceed what buyers actually paid.
    function invariant_releasedNeverExceedsProceeds() public view {
        for (uint256 i = 0; i < 2; ++i) {
            bytes32 id = handler.ids(i);
            if (id == bytes32(0)) continue;
            (, , uint256 proceeds, uint256 released, ) = escrow.launchInfo(id);
            assertLe(released, proceeds, "released more than was paid in");
        }
    }

    function computeCreate(address deployer, uint8 nonce) internal pure returns (address) {
        bytes memory data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), deployer, bytes1(nonce));
        return address(uint160(uint256(keccak256(data))));
    }
}
