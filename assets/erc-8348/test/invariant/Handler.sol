// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {FinancialLease} from "../../src/FinancialLease.sol";
import {IFinancialLease} from "../../src/IFinancialLease.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USD", "mUSD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Handler for invariant testing. Calls the protocol with
///      bounded sequences of actions and keeps ghost variables for
///      the two properties derived from S3-01/S4-02.
///      There is no "classic solvency" handler: the contract never
///      holds funds (pay() transfers payer -> lessor position holder directly), so
///      that universal invariant does not apply to this protocol.
contract Handler is Test {
    FinancialLease public lease;
    MockERC20 public token;

    uint256 internal constant UNIT = 1e18;

    address[] public actors;
    uint256[] public leaseIds;

    // INV-LESSEE: true if any leaseId had its lessee changed
    // by someone who was NOT the outgoing lessee at that moment.
    mapping(uint256 => bool) public ghost_lesseeHijacked;

    // Auxiliary sanity invariant: once an absorbing
    // status is reached (see _isAbsorbing), the lease
    // should never report a different status afterwards.
    mapping(uint256 => IFinancialLease.LeaseStatus) public ghost_lastStatus;
    bool public ghost_anyTerminalRegression;

    constructor(FinancialLease lease_, MockERC20 token_) {
        lease = lease_;
        token = token_;

        actors.push(makeAddr("actor0-lessor"));
        actors.push(makeAddr("actor1-lessee"));
        actors.push(makeAddr("actor2-declarer"));
        actors.push(makeAddr("actor3-outsider"));

        for (uint256 i = 0; i < actors.length; i++) {
            token.mint(actors[i], 10_000_000 * UNIT);
            vm.prank(actors[i]);
            token.approve(address(lease), type(uint256).max);
        }
    }

    function leaseIdsLength() external view returns (uint256) {
        return leaseIds.length;
    }

    function leaseIdAt(uint256 i) external view returns (uint256) {
        return leaseIds[i];
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[bound(seed, 0, actors.length - 1)];
    }

    /// @dev Of the 3 terminal values the handler can reach, Completed is NOT
    ///      absorbing in practice: exercisePurchaseOption() legitimately moves it
    ///      to PurchaseExercised (see purchaseOption():
    ///      exercisable = status == Completed). Terminated is terminal
    ///      (fix S6-01) but this handler does not call the termination
    ///      functions; its freeze is covered by T66/T67. The only absorbing
    ///      status checked here is
    ///      PurchaseExercised: no function has an exit path
    ///      (pay/declareDefault revert outside non-terminal statuses;
    ///      exercisePurchaseOption reverts because exercisable requires
    ///      status == Completed).
    function _isAbsorbing(IFinancialLease.LeaseStatus s) internal pure returns (bool) {
        return s == IFinancialLease.LeaseStatus.PurchaseExercised;
    }

    function _trackStatus(uint256 leaseId) internal {
        IFinancialLease.LeaseStatus prev = ghost_lastStatus[leaseId];
        IFinancialLease.LeaseStatus cur = lease.status(leaseId);
        if (_isAbsorbing(prev) && cur != prev) {
            ghost_anyTerminalRegression = true;
        }
        ghost_lastStatus[leaseId] = cur;
    }

    // ─── actions ───────────────────────────────────────────────

    function createLease(uint256 lessorSeed, uint256 lesseeSeed, uint256 declarerSeed, uint256 nInstallments, uint256 amountSeed, uint256 bpsSeed)
        external
    {
        address lessor_ = _actor(lessorSeed);
        address lessee_ = _actor(lesseeSeed);

        // declarerSeed also explores the p.defaultDeclarer == 0 branch
        // (after fix S4-01: no override -> resolved dynamically
        // against ownerOf(leaseId) on every call, NO LONGER frozen at
        // msg.sender at origination — see _declarer() in FinancialLease.sol).
        address declarer_ = declarerSeed % 5 == 0 ? address(0) : _actor(declarerSeed);

        uint256 n = bound(nInstallments, 1, 3);
        uint64[] memory dueDates = new uint64[](n);
        uint256[] memory unitAmounts = new uint256[](n);
        uint256 amountEach = bound(amountSeed, 1, 1000) * UNIT;
        for (uint256 i = 0; i < n; i++) {
            dueDates[i] = uint64(block.timestamp) + uint64((i + 1) * 30 days);
            unitAmounts[i] = amountEach;
        }

        FinancialLease.CreateLeaseParams memory p = FinancialLease.CreateLeaseParams({
            lessee: lessee_,
            jurisdiction: bytes2("AR"),
            governingLaw: "Buenos Aires",
            agreementHash: keccak256(abi.encode(lessorSeed, lesseeSeed, block.timestamp)),
            assetRef: "asset://x",
            paymentAsset: address(token),
            denomSymbol: "USD",
            oracle: address(0),
            maxStaleness: 0,
            dueDates: dueDates,
            unitAmounts: unitAmounts,
            purchasePriceUnits: amountEach,
            penaltyBpsPerDay: uint16(bound(bpsSeed, 0, 500)),
            defaultDeclarer: declarer_,
            terminationDelay: 7 days,
            anchorChainId: 0,
            anchorRegistry: address(0),
            anchorId: bytes32(0),
            servicer: address(0),
            servicingInputs: new bytes32[](0),
            servicingMaxStaleness: new uint64[](0)
        });

        vm.prank(lessor_);
        uint256 id = lease.createLease(p);
        leaseIds.push(id);
        ghost_lastStatus[id] = IFinancialLease.LeaseStatus.Active;
    }

    function pay(uint256 leaseIdSeed, uint256 payerSeed, uint256 assetsSeed) external {
        if (leaseIds.length == 0) return;
        uint256 id = leaseIds[bound(leaseIdSeed, 0, leaseIds.length - 1)];
        address payer = _actor(payerSeed);
        uint256 assets = bound(assetsSeed, 0, 2000 * UNIT);

        vm.prank(payer);
        try lease.pay(id, assets) {
            _trackStatus(id);
        } catch {}
    }

    function warp(uint256 daysSeed) external {
        vm.warp(block.timestamp + bound(daysSeed, 0, 30 days));
    }

    function declareDefault(uint256 leaseIdSeed, uint256 callerSeed) external {
        if (leaseIds.length == 0) return;
        uint256 id = leaseIds[bound(leaseIdSeed, 0, leaseIds.length - 1)];
        address caller = _actor(callerSeed);

        vm.prank(caller);
        try lease.declareDefault(id) {
            _trackStatus(id);
        } catch {}
    }

    /// @dev The heart of the INV-LESSEE fuzz: the caller is an
    ///      arbitrary actor, not necessarily the outgoing lessee.
    function assignLessee(uint256 leaseIdSeed, uint256 callerSeed, uint256 newLesseeSeed) external {
        if (leaseIds.length == 0) return;
        uint256 id = leaseIds[bound(leaseIdSeed, 0, leaseIds.length - 1)];
        address caller = _actor(callerSeed);
        address newLessee = _actor(newLesseeSeed);
        address oldLessee = lease.lessee(id);

        vm.prank(caller);
        try lease.assignLessee(id, newLessee) {
            if (caller != oldLessee) {
                ghost_lesseeHijacked[id] = true;
            }
        } catch {}
    }

    function exercisePurchaseOption(uint256 leaseIdSeed) external {
        if (leaseIds.length == 0) return;
        uint256 id = leaseIds[bound(leaseIdSeed, 0, leaseIds.length - 1)];
        address lessee_ = lease.lessee(id);

        vm.prank(lessee_);
        try lease.exercisePurchaseOption(id) {
            _trackStatus(id);
        } catch {}
    }
}
