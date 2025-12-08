// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.23;

import {
    IXMLRepresentableStateVersionedHashed,
    IXMLRepresentableState, IRepresentableStateVersioned, IRepresentableStateHashed     // needed for @inheritdoc
} from "../IRepresentableState.sol";

contract InterestRateSwapSettleToMarket is IXMLRepresentableStateVersionedHashed {

    address public immutable owner;

    string public partyALEI;
    string public partyBLEI;

    uint256 public immutable tradeDate;
    uint256 public immutable effectiveDate;
    uint256 public immutable terminationDate;

    uint256 public immutable notional;
    string  public currency;
    int256  public immutable fixedRateBP;
    int256  public immutable floatSpreadBP;

    uint256 public lastSettlementTime;
    int256  public lastSettlementValue;
    uint256 public settlementCount;

    uint256 private _stateVersion;

    event SettlementPerformed(uint256 time, int256 value);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address _owner) {
        owner = _owner;

        // These demo parameters should be passed upon construction - hardcoded here for simplicity
        notional = 10_000_000_00;        // 10,000,000.00
        currency = "EUR";
        fixedRateBP = 25000;             // 2.5000 %
        floatSpreadBP = 0;               // 0.0000 %

        tradeDate       = 1735776000;    // ~ 2025-01-02
        effectiveDate   = 1735948800;    // ~ 2025-01-04
        terminationDate = 1799020800;    // ~ 2027-01-04

        partyALEI = "LEI-of-Party-A (taken from contract)";
        partyBLEI = "LEI-of-Party-B (taken from contract)";

        // This will be updaten upon "performSettlement" call.
        settlementCount = 0;
        lastSettlementTime = 0;
        lastSettlementValue = 0;

        _stateVersion = 1;
    }

    function performSettlement(uint256 time, int256 value) external onlyOwner {
        settlementCount++;
        lastSettlementTime = time;
        lastSettlementValue = value;
        _stateVersion += 1;
        emit SettlementPerformed(time, value);
    }

    // --- IRepresentableState.sol ---

    /// @inheritdoc IXMLRepresentableState
    function xmlTemplate() external pure override returns (string memory) {
        // keine """-Strings – wir bauen das XML über abi.encodePacked und
        return
            "<?xml version='1.0' encoding='UTF-8'?>"
            "<fpml:dataDocument"
            "    xmlns:fpml='http://www.fpml.org/FpML-5/confirmation'"
            "    xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance'"
            "    xmlns:evmstate='urn:evm:state:1.0'>"
            ""
            "    <fpml:trade id='IRS-STM-EXAMPLE-0001'>"
            "        <fpml:tradeHeader>"
            "            <fpml:partyTradeIdentifier>"
            "                <fpml:partyReference href='PartyA'/>"
            "                <fpml:tradeId tradeIdScheme='http://example.com/trade-id'>IRS-STM-EXAMPLE-0001</fpml:tradeId>"
            "            </fpml:partyTradeIdentifier>"
            "            <fpml:tradeDate evmstate:call='tradeDate()(uint256)' evmstate:format='iso8601-date'/>"
            "        </fpml:tradeHeader>"
            ""
            "        <fpml:party id='PartyA'>"
            "            <fpml:partyId evmstate:call='partyALEI()(string)'/>"
            "        </fpml:party>"
            "        <fpml:party id='PartyB'>"
            "            <fpml:partyId evmstate:call='partyBLEI()(string)'/>"
            "        </fpml:party>"
            ""
            "        <fpml:swap>"
            "            <!-- FIXED LEG -->"
            "            <fpml:swapStream id='fixedLeg'>"
            "                <fpml:payerPartyReference href='PartyA'/>"
            "                <fpml:receiverPartyReference href='PartyB'/>"
            "                <fpml:calculationAmount>"
            "                    <fpml:currency evmstate:call='currency()(string)'/>"
            "                    <fpml:amount evmstate:call='notional()(uint256)' evmstate:format='decimal' evmstate:scale='2'/>"
            "                </fpml:calculationAmount>"
            "                <fpml:calculationPeriodDates>"
            "                    <fpml:effectiveDate>"
            "                        <fpml:unadjustedDate evmstate:call='effectiveDate()(uint256)' evmstate:format='iso8601-date'/>"
            "                    </fpml:effectiveDate>"
            "                    <fpml:terminationDate>"
            "                        <fpml:unadjustedDate evmstate:call='terminationDate()(uint256)' evmstate:format='iso8601-date'/>"
            "                    </fpml:terminationDate>"
            "                </fpml:calculationPeriodDates>"
            "                <fpml:calculationPeriodAmount>"
            "                    <fpml:calculation>"
            "                        <fpml:dayCountFraction>30E/360</fpml:dayCountFraction>"
            "                        <fpml:fixedRateSchedule>"
            "                            <fpml:initialValue evmstate:call='fixedRateBP()(int256)' evmstate:format='decimal' evmstate:scale='4'/>"
            "                        </fpml:fixedRateSchedule>"
            "                    </fpml:calculation>"
            "                </fpml:calculationPeriodAmount>"
            "            </fpml:swapStream>"
            ""
            "            <!-- FLOATING LEG -->"
            "            <fpml:swapStream id='floatLeg'>"
            "                <fpml:payerPartyReference href='PartyB'/>"
            "                <fpml:receiverPartyReference href='PartyA'/>"
            "                <fpml:calculationAmount>"
            "                    <fpml:currency evmstate:call='currency()(string)'/>"
            "                    <fpml:amount evmstate:call='notional()(uint256)' evmstate:format='decimal' evmstate:scale='2'/>"
            "                </fpml:calculationAmount>"
            "                <fpml:calculationPeriodAmount>"
            "                    <fpml:calculation>"
            "                        <fpml:dayCountFraction>ACT/360</fpml:dayCountFraction>"
            "                        <fpml:floatingRateCalculation>"
            "                            <fpml:floatingRateIndex>EUR-EURIBOR-Reuters</fpml:floatingRateIndex>"
            "                            <fpml:indexTenor>"
            "                                <fpml:periodMultiplier>3</fpml:periodMultiplier>"
            "                                <fpml:period>M</fpml:period>"
            "                            </fpml:indexTenor>"
            "                            <fpml:spreadSchedule>"
            "                                <fpml:initialValue evmstate:call='floatSpreadBP()(int256)' evmstate:format='decimal' evmstate:scale='4'/>"
            "                            </fpml:spreadSchedule>"
            "                        </fpml:floatingRateCalculation>"
            "                    </fpml:calculation>"
            "                </fpml:calculationPeriodAmount>"
            "            </fpml:swapStream>"
            "        </fpml:swap>"
            ""
            "        <!-- last settlement (SDC-like) -->"
            "        <lastSettlement>"
            "            <time  evmstate:call='lastSettlementTime()(uint256)' evmstate:format='iso8601-datetime'/>"
            "            <value evmstate:call='lastSettlementValue()(int256)' evmstate:format='decimal' evmstate:scale='2'/>"
            "            <count evmstate:call='settlementCount()(uint256)' evmstate:format='integer'/>"
            "        </lastSettlement>"
            ""
            "    </fpml:trade>"
            "</fpml:dataDocument>";
    }

    /// @inheritdoc IRepresentableStateVersioned
    function stateVersion() external view override returns (uint256) {
        return _stateVersion;
    }

    /// @inheritdoc IRepresentableStateHashed
    function stateHash() external view override returns (bytes32) {
        return keccak256(abi.encode(
            owner,
            notional,
            fixedRateBP,
            floatSpreadBP,
            effectiveDate,
            terminationDate,
            lastSettlementTime,
            lastSettlementValue
        ));
    }
}

