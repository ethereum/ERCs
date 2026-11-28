// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;
import {readAccount} from "./AccountRead.sol";
import {InstitutionAccount} from "../InstitutionAccount.sol";
import {AccountState, IInstitutionAccount} from "../IInstitutionAccount.sol";

interface Vm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }
    function prank(address) external;
    function expectRevert() external;
    function expectRevert(bytes4 revertData) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
    function store(address, bytes32, bytes32) external;
}

/// @notice Reference implementation tests for amounts, replay protection, account periods, and boundaries.
contract InstitutionAccountTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant issuer = address(0x100);
    address private constant otherIssuer = address(0x200);
    address private constant account = address(0xaaa);
    address private constant writer = address(0xbbb);
    InstitutionAccount private ledger;
    uint256 private nextId = 1;

    function setUp() public {
        ledger = new InstitutionAccount("USD", 6);
    }

    function id() private returns (bytes32) {
        return bytes32(nextId++);
    }

    function grant(uint96 amount) private {
        bytes32 op = id();
        vm.prank(issuer);
        ledger.addLimit(account, issuer, op, amount);
    }

    function consume(uint96 amount) private {
        bytes32 op = id();
        vm.prank(issuer);
        ledger.debit(account, issuer, op, amount);
    }

    function inflow(uint96 amount) private {
        bytes32 op = id();
        vm.prank(issuer);
        ledger.credit(account, issuer, op, amount);
    }

    function release(uint96 amount) private {
        bytes32 op = id();
        vm.prank(issuer);
        ledger.subLimit(account, issuer, op, amount);
    }

    function seal(uint32 period) private {
        vm.prank(issuer);
        ledger.rollup(account, issuer, period);
    }

    function read() private view returns (AccountState memory, uint96) {
        return readAccount(ledger, account, issuer);
    }

    function testZeroAmountsNeedNoInitializationFlag() public {
        (AccountState memory state, uint96 available) = read();
        require(state.limit == 0 && state.debit == 0 && state.credit == 0 && state.statementId == 0 && available == 0);
        vm.prank(issuer);
        vm.expectRevert();
        ledger.debit(account, issuer, id(), 1);
    }

    function testCreditCanStartZeroAccount() public {
        inflow(5);
        consume(5);
        (, uint96 available) = read();
        require(available == 0);
    }

    function testInstitutionAndAccountIsolation() public {
        grant(100);
        vm.prank(otherIssuer);
        ledger.addLimit(account, otherIssuer, id(), 25);
        vm.prank(issuer);
        ledger.addLimit(address(0xaab), issuer, id(), 50);
        (, uint96 first) = read();
        (, uint96 second) = readAccount(ledger, account, otherIssuer);
        (, uint96 third) = readAccount(ledger, address(0xaab), issuer);
        require(first == 100 && second == 25 && third == 50);
    }

    function testAdjustmentsKeepGross() public {
        grant(100);
        consume(30);
        inflow(5);
        release(70);
        (AccountState memory s, uint96 available) = read();
        require(s.limit == 30 && s.debit == 30 && s.credit == 5 && available == 5 && s.statementId == 0);
    }

    function testCompleteRollupPreservesCapacity() public {
        grant(100);
        consume(30);
        inflow(5);
        seal(0);
        (AccountState memory s, uint96 a) = read();
        require(s.limit == 75 && s.debit == 0 && s.credit == 0 && a == 75 && s.statementId == 1);
    }

    function testNetCreditRequiresRollupToReleaseAll() public {
        grant(100);
        consume(5);
        inflow(30);
        release(125);
        (AccountState memory s, uint96 a) = read();
        require(s.limit == 0 && s.debit == 5 && s.credit == 30 && a == 25);
        seal(0);
        release(25);
        (s, a) = read();
        require(s.limit == 0 && a == 0 && s.statementId == 1);
    }

    function testNonemptyNetZeroCanRollup() public {
        inflow(30);
        consume(30);
        seal(0);
        (AccountState memory s,) = read();
        require(s.statementId == 1);
    }

    function testEmptyPeriodRejected() public {
        vm.prank(issuer);
        vm.expectRevert();
        ledger.rollup(account, issuer, 0);
    }

    function testLateCreditRestoresNumericalCapacity() public {
        grant(100);
        consume(30);
        release(70);
        seal(0);
        inflow(5);
        (, uint96 available) = read();
        require(available == 5);
        consume(5); // There is no permanent closure flag; institutions validate task authorization.
        (, available) = read();
        require(available == 0);
    }

    function testLateCreditCanBeReleased() public {
        inflow(5);
        seal(0);
        release(5);
        (, uint96 available) = read();
        require(available == 0);
    }

    function testStaleFullReleaseCannotOverdraw() public {
        grant(100);
        consume(30);
        vm.prank(issuer);
        vm.expectRevert();
        ledger.subLimit(account, issuer, id(), 100);
        (, uint96 available) = read();
        require(available == 70);
    }

    function testFixedReleaseKeepsSubsequentCredit() public {
        grant(100);
        inflow(5);
        release(100);
        (, uint96 available) = read();
        require(available == 5);
    }

    function testCurrentPeriodIncludesInterveningWrites() public {
        grant(100);
        consume(20);
        inflow(5);
        seal(0);
        (AccountState memory s, uint96 a) = read();
        require(s.limit == 85 && a == 85);
    }

    function testOldStatementCannotSealNewPeriod() public {
        inflow(10);
        seal(0);
        consume(2);
        vm.prank(issuer);
        vm.expectRevert();
        ledger.rollup(account, issuer, 0);
        (AccountState memory s,) = read();
        require(s.statementId == 1 && s.debit == 2);
    }

    function testReplayCannotMoveBetweenAccountsOrWriters() public {
        bytes32 op = id();
        vm.prank(issuer);
        ledger.addLimit(account, issuer, op, 10);
        vm.prank(issuer);
        vm.expectRevert();
        ledger.addLimit(address(0xaab), issuer, op, 10);
        vm.prank(issuer);
        ledger.setWriter(writer, true);
        vm.prank(writer);
        vm.expectRevert();
        ledger.credit(account, issuer, op, 2);
        vm.prank(issuer);
        vm.expectRevert();
        ledger.credit(address(0xaab), issuer, op, 2);
    }

    function testRejectedInstructionCanRetryStableId() public {
        bytes32 op = id();
        vm.prank(issuer);
        vm.expectRevert();
        ledger.debit(account, issuer, op, 5);
        grant(10);
        vm.prank(issuer);
        ledger.debit(account, issuer, op, 5);
        (, uint96 a) = read();
        require(a == 5);
    }

    function testReplaySurvivesRollup() public {
        bytes32 op = id();
        vm.prank(issuer);
        ledger.credit(account, issuer, op, 5);
        seal(0);
        vm.prank(issuer);
        vm.expectRevert();
        ledger.credit(account, issuer, op, 5);
    }

    function testManagementAndWriterScopes() public {
        vm.prank(writer);
        vm.expectRevert();
        ledger.addLimit(account, issuer, id(), 10);
        vm.prank(issuer);
        ledger.setWriter(writer, true);
        vm.prank(writer);
        ledger.credit(account, issuer, id(), 10);
        vm.prank(writer);
        vm.expectRevert();
        ledger.credit(account, otherIssuer, id(), 1);
        vm.prank(writer);
        vm.expectRevert();
        ledger.rollup(account, issuer, 0);
        vm.prank(issuer);
        ledger.setWriter(writer, false);
        vm.prank(writer);
        vm.expectRevert();
        ledger.credit(account, issuer, id(), 1);
    }

    function testNonzeroArguments() public {
        vm.prank(issuer);
        vm.expectRevert();
        ledger.addLimit(address(0), issuer, id(), 1);
        vm.prank(issuer);
        vm.expectRevert();
        ledger.addLimit(account, issuer, 0, 1);
        vm.prank(issuer);
        vm.expectRevert();
        ledger.addLimit(account, issuer, id(), 0);
        vm.prank(address(0));
        vm.expectRevert();
        ledger.addLimit(account, address(0), id(), 1);
    }

    function testAvailableUpperBoundSurvivesRollup() public {
        grant(type(uint96).max);
        vm.prank(issuer);
        vm.expectRevert();
        ledger.credit(account, issuer, id(), 1);
        consume(1);
        inflow(1);
        seal(0);
        vm.prank(issuer);
        vm.expectRevert();
        ledger.credit(account, issuer, id(), 1);
    }

    function testGrossCounterLimitAndRecovery() public {
        grant(type(uint96).max);
        consume(type(uint96).max);
        inflow(1);
        bytes32 op = id();
        vm.prank(issuer);
        vm.expectRevert();
        ledger.debit(account, issuer, op, 1);
        seal(0);
        vm.prank(issuer);
        ledger.debit(account, issuer, op, 1);
        (, uint96 a) = read();
        require(a == 0);
    }

    function testCreditCounterLimitAndRecovery() public {
        inflow(type(uint96).max);
        consume(type(uint96).max);
        bytes32 op = id();
        vm.prank(issuer);
        vm.expectRevert();
        ledger.credit(account, issuer, op, 1);
        (AccountState memory s, uint96 available) = read();
        require(s.credit == type(uint96).max && available == 0 && s.statementId == 0);
        seal(0);
        vm.prank(issuer);
        ledger.credit(account, issuer, op, 1);
        (s, available) = read();
        require(s.credit == 1 && available == 1 && s.statementId == 1);
    }

    function testZeroLimitAndNetCreditRollupEvent() public {
        inflow(type(uint96).max);
        (AccountState memory s, uint96 available) = read();
        require(s.limit == 0 && available == type(uint96).max);
        vm.recordLogs();
        seal(0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length == 1);
        uint32 period = uint32(uint256(logs[0].topics[3]));
        (uint96 oldLimit, uint96 debit, uint96 credit, uint96 newLimit) =
            abi.decode(logs[0].data, (uint96, uint96, uint96, uint96));
        require(
            period == 0 && oldLimit == 0 && debit == 0 && credit == type(uint96).max && newLimit == type(uint96).max
        );
        (s, available) = read();
        require(
            s.limit == type(uint96).max && s.debit == 0 && s.credit == 0 && s.statementId == 1
                && available == type(uint96).max
        );
    }

    function testLimitOverflowRevertsEvenWhenCapacityHasRoom() public {
        grant(type(uint96).max);
        consume(type(uint96).max);
        bytes32 op = id();
        vm.prank(issuer);
        vm.expectRevert(InstitutionAccount.AmountRange.selector);
        ledger.addLimit(account, issuer, op, 1);
        (AccountState memory s, uint96 a) = read();
        require(s.limit == type(uint96).max && s.debit == type(uint96).max && a == 0);
        seal(0);
        vm.prank(issuer);
        ledger.addLimit(account, issuer, op, 1);
        (s, a) = read();
        require(s.limit == 1 && a == 1);
    }

    function testRollupEventGrossAndPeriod() public {
        grant(100);
        consume(30);
        inflow(5);
        vm.recordLogs();
        seal(0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        require(
            logs.length == 1
                && logs[0].topics[0] == keccak256("RolledUp(address,address,uint32,uint96,uint96,uint96,uint96)")
        );
        uint32 period = uint32(uint256(logs[0].topics[3]));
        (uint96 oldLimit, uint96 debit, uint96 credit, uint96 newLimit) =
            abi.decode(logs[0].data, (uint96, uint96, uint96, uint96));
        require(period == 0 && oldLimit == 100 && debit == 30 && credit == 5 && newLimit == 75);
    }

    function testStatementCounterCannotWrap() public {
        inflow(1); // Reference layout: _states is at slot 1; statementId starts at bit 96 of the second state slot.
        bytes32 root = keccak256(abi.encode(account, keccak256(abi.encode(issuer, uint256(1)))));
        vm.store(address(ledger), bytes32(uint256(root) + 1), bytes32(uint256(1) | (uint256(type(uint32).max) << 96)));
        vm.prank(issuer);
        vm.expectRevert();
        ledger.rollup(account, issuer, type(uint32).max);
        (AccountState memory s,) = read();
        require(s.statementId == type(uint32).max && s.credit == 1);
    }

    function testFuzzRollup(uint96 initial, uint96 spent, uint96 credited) public {
        if (initial == 0) return;
        spent = uint96(uint256(spent) % (uint256(initial) + 1));
        credited = uint96(uint256(credited) % (uint256(type(uint96).max) - initial + spent + 1));
        grant(initial);
        if (spent > 0) consume(spent);
        if (credited > 0) inflow(credited);
        if (spent == 0 && credited == 0) return;
        (, uint96 beforeAvailable) = read();
        seal(0);
        (AccountState memory s, uint96 afterAvailable) = read();
        require(beforeAvailable == afterAvailable && s.limit == afterAvailable && s.debit == 0 && s.credit == 0);
    }

    function testFuzzMixedOperations(uint256 seed) public {
        uint256 limit;
        uint256 debit;
        uint256 credit;
        uint32 statementId;
        for (uint256 step; step < 48; ++step) {
            seed = uint256(keccak256(abi.encode(seed, step)));
            uint256 action = seed % 5;
            uint96 amount = uint96(seed % 40 + 1);
            uint256 available = limit + credit - debit;
            if (action == 0) {
                grant(amount);
                limit += amount;
            } else if (action == 1) {
                uint256 nextLimit = amount < limit ? limit - amount : 0;
                if (nextLimit + credit < debit) {
                    vm.expectRevert(InstitutionAccount.AmountRange.selector);
                    release(amount);
                } else {
                    release(amount);
                    limit = nextLimit;
                }
            } else if (action == 2) {
                if (available == 0) continue;
                amount = uint96(uint256(amount) % available + 1);
                consume(amount);
                debit += amount;
            } else if (action == 3) {
                inflow(amount);
                credit += amount;
            } else {
                if (debit == 0 && credit == 0) continue;
                seal(statementId);
                limit = available;
                debit = 0;
                credit = 0;
                statementId++;
            }
            (AccountState memory s, uint96 actual) = read();
            require(s.limit == limit && s.debit == debit && s.credit == credit && s.statementId == statementId);
            require(actual == limit + credit - debit);
        }
    }

    function testClampedReleaseEventReportsActualAmount() public {
        grant(10);
        inflow(5);
        vm.recordLogs();
        release(100);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length == 1);
        require(logs[0].topics[0] == keccak256("LimitSubtracted(address,address,bytes32,uint96,uint96)"));
        (uint96 actualAmount, uint96 newLimit) = abi.decode(logs[0].data, (uint96, uint96));
        require(actualAmount == 10 && newLimit == 0);
        (AccountState memory s, uint96 a) = read();
        require(s.limit == 0 && s.credit == 5 && a == 5);
    }

    function testZeroBaselineReleaseStillConsumesId() public {
        inflow(5);
        bytes32 op = id();
        vm.recordLogs();
        vm.prank(issuer);
        ledger.subLimit(account, issuer, op, 1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length == 1);
        (uint96 actualAmount, uint96 newLimit) = abi.decode(logs[0].data, (uint96, uint96));
        require(actualAmount == 0 && newLimit == 0);
        vm.prank(issuer);
        vm.expectRevert(InstitutionAccount.ReusedOperation.selector);
        ledger.addLimit(account, issuer, op, 1);
        (, uint96 a) = read();
        require(a == 5);
    }

    function testRejectedNegativeCapacityLeavesStateAndId() public {
        grant(100);
        consume(90);
        bytes32 op = id();
        vm.recordLogs();
        vm.prank(issuer);
        vm.expectRevert(InstitutionAccount.AmountRange.selector);
        ledger.subLimit(account, issuer, op, 20);
        require(vm.getRecordedLogs().length == 0);
        (AccountState memory s, uint96 a) = read();
        require(s.limit == 100 && s.debit == 90 && s.credit == 0 && a == 10);
        inflow(10);
        vm.prank(issuer);
        ledger.subLimit(account, issuer, op, 20);
        (s, a) = read();
        require(s.limit == 80 && s.debit == 90 && s.credit == 10 && a == 0);
    }

    function testRefundBeforeOrAfterRollupPreservesCapacity() public {
        for (uint256 order; order < 2; ++order) {
            InstitutionAccount isolated = new InstitutionAccount("USD", 6);
            vm.prank(issuer);
            isolated.addLimit(account, issuer, bytes32(uint256(1)), 100);
            vm.prank(issuer);
            isolated.debit(account, issuer, bytes32(uint256(2)), 90);
            vm.prank(issuer);
            isolated.subLimit(account, issuer, bytes32(uint256(3)), 10);
            if (order == 0) {
                vm.prank(issuer);
                isolated.credit(account, issuer, bytes32(uint256(4)), 5);
                vm.prank(issuer);
                isolated.rollup(account, issuer, 0);
            } else {
                vm.prank(issuer);
                isolated.rollup(account, issuer, 0);
                vm.prank(issuer);
                isolated.credit(account, issuer, bytes32(uint256(4)), 5);
            }
            (, uint96 a) = readAccount(isolated, account, issuer);
            require(a == 5);
        }
    }

    function testWideIntermediateDoesNotRejectValidResult() public {
        grant(type(uint96).max);
        consume(type(uint96).max);
        inflow(type(uint96).max);
        (, uint96 a) = read();
        require(a == type(uint96).max);
        seal(0);
        (AccountState memory s,) = read();
        require(s.limit == type(uint96).max && s.debit == 0 && s.credit == 0);
    }

    function testGasFirstGrant() public {
        grant(100);
    }

    function testConsumedIdCannotSwitchAnyIncrementFunction() public {
        bytes4[4] memory methods = [
            IInstitutionAccount.addLimit.selector,
            IInstitutionAccount.subLimit.selector,
            IInstitutionAccount.debit.selector,
            IInstitutionAccount.credit.selector
        ];
        for (uint256 first; first < 4; ++first) {
            InstitutionAccount isolated = new InstitutionAccount("USD", 6);
            vm.prank(issuer);
            isolated.addLimit(account, issuer, bytes32(uint256(1)), 100);
            vm.prank(issuer);
            (bool accepted,) = address(isolated)
                .call(abi.encodeWithSelector(methods[first], account, issuer, bytes32(uint256(99)), uint96(5)));
            require(accepted);
            bytes32 beforeState = keccak256(abi.encode(isolated.accountState(account, issuer)));
            for (uint256 retry; retry < 4; ++retry) {
                vm.prank(issuer);
                (bool replayed,) = address(isolated)
                    .call(abi.encodeWithSelector(methods[retry], account, issuer, bytes32(uint256(99)), uint96(7)));
                require(!replayed);
            }
            require(beforeState == keccak256(abi.encode(isolated.accountState(account, issuer))));
        }
    }

    function testSameIdAllowedForDifferentInstitution() public {
        vm.prank(issuer);
        ledger.credit(account, issuer, bytes32(uint256(99)), 10);
        vm.prank(otherIssuer);
        ledger.addLimit(account, otherIssuer, bytes32(uint256(99)), 20);
        require(ledger.accountState(account, issuer).credit == 10);
        require(ledger.accountState(account, otherIssuer).limit == 20);
    }

    function testRollupDoesNotConsumeAnIncrementId() public {
        inflow(10);
        seal(0);
        vm.prank(issuer);
        ledger.addLimit(account, issuer, bytes32(uint256(2)), 5);
        require(ledger.accountState(account, issuer).limit == 15);
    }

    function testRejectedAvailableOverflowDoesNotConsumeId() public {
        grant(type(uint96).max);
        bytes32 op = id();
        vm.prank(issuer);
        vm.expectRevert();
        ledger.credit(account, issuer, op, 1);
        consume(1);
        vm.prank(issuer);
        ledger.credit(account, issuer, op, 1);
        (, uint96 available) = read();
        require(available == type(uint96).max);
    }

    function testGasDebitCreditRollup() public {
        grant(100);
        consume(30);
        inflow(5);
        seal(0);
    }
}
