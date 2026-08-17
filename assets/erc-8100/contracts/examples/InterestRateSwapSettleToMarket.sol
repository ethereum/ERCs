// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.19;

import {
IXMLRepresentableStateVersionedHashed,
IXMLRepresentableState, IRepresentableStateVersioned, IRepresentableStateHashed     // needed for @inheritdoc
} from "../IRepresentableState.sol";

contract InterestRateSwapSettleToMarket is IXMLRepresentableStateVersionedHashed {

    // Simple demo part-id for "settlement context"
    uint256 public constant XML_PART_SETTLEMENT_CTX = 1;

    /// @dev Single settlement entry in the history.
    struct Settlement {
        uint256 time;   // Unix timestamp (seconds since epoch)
        int256  value;  // scaled by 1e2 (scale=2) for XML rendering
    }

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

    // Last settlement (convenience + SDC-like view)
    uint256 public lastSettlementTime;
    int256  public lastSettlementValue;
    uint256 public settlementCount;

    // Full settlement history
    Settlement[] private _settlements;

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

        settlementCount = 0;
        lastSettlementTime = 0;
        lastSettlementValue = 0;

        _stateVersion = 1;
    }

    /**
     * Record a new settlement.
     *
     * For the demo we just store whatever (time, value) the owner passes.
     */
    function performSettlement(uint256 time, int256 value) external onlyOwner {
        // store in history
        _settlements.push(Settlement({ time: time, value: value }));

        // update aggregates / convenience fields
        settlementCount = _settlements.length;
        lastSettlementTime = time;
        lastSettlementValue = value;

        _stateVersion += 1;
        emit SettlementPerformed(time, value);
    }

    // --- Settlement history accessors for array bindings --------------------

    /**
     * Length of the settlement history.
     * (You already have settlementCount, but this is sometimes nice as a
     * dedicated semantic getter if you want it.)
     */
    function settlementsLength() external view returns (uint256) {
        return _settlements.length;
    }

    /**
     * Single element access:
     *   settlements(i) -> (time, value)
     *
     * Useful if your array binding pattern is "call per index".
     */
    function settlements(uint256 index) external view returns (uint256 time, int256 value) {
        require(index < _settlements.length, "index out of bounds");
        Settlement storage s = _settlements[index];
        return (s.time, s.value);
    }

    /**
     * Bulk access:
     *   settlementHistory() -> Settlement[]  (ABI: tuple(uint256,int256)[])
     *
     * Used by the XML renderer's array-of-struct binding.
     */
    function settlementHistory() external view returns (Settlement[] memory) {
        return _settlements;
    }

    // --- IRepresentableState.sol -------------------------------------------

    /// @inheritdoc IXMLRepresentableState
    function stateXmlTemplate() external pure override returns (string memory) {
        // We use abi.encodePacked to inject the shared settlements fragment.
        return string(
            abi.encodePacked(
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
                "        <Settlements>",
                // --- shared settlements fragment (last + history) -------------
                _settlementsFragment(),
                // ----------------------------------------------------------------
                "        </Settlements>",
                ""
                "    </fpml:trade>"
                "</fpml:dataDocument>"
            )
        );
    }

    function _settlementsFragment() internal pure returns (string memory) {
        return
                    "    <LastSettlement>"
                    "        <time  evmstate:call='lastSettlementTime()(uint256)' evmstate:format='iso8601-datetime'/>"
                    "        <value evmstate:call='lastSettlementValue()(int256)' evmstate:format='decimal' evmstate:scale='2'/>"
                    "        <count evmstate:call='settlementCount()(uint256)' evmstate:format='integer'/>"
                    "    </LastSettlement>"
                    ""
                    "    <History"
                    "        evmstate:call='settlementHistory()(tuple(uint256,int256)[])'"
                    "        evmstate:item-element='Settlement'>"
                    "        <Settlement>"
                    "            <time"
                    "                evmstate:item-field='0'"
                    "                evmstate:format='iso8601-datetime'/>"
                    "            <value"
                    "                evmstate:item-field='1'"
                    "                evmstate:format='decimal'"
                    "                evmstate:scale='2'/>"
                    "        </Settlement>"
                    "    </History>";
    }

    /**
     * Template for partial state views:
     *
     * XML_PART_SETTLEMENT_CTX: settlement context (last + history)
     */
    function statePartXmlTemplate(uint256 partId) external pure returns (string memory) {
        if (partId == XML_PART_SETTLEMENT_CTX) {
            return string(
                abi.encodePacked(
                    "<?xml version='1.0' encoding='UTF-8'?>",
                    "<Settlements"
                    " xmlns='urn:example:settlement-context'"
                    " xmlns:evmstate='urn:evm:state:1.0'"
                    " evmstate:chain-id=''"
                    " evmstate:contract-address=''"
                    " evmstate:block-number=''>",
                    _settlementsFragment(),
                    "</Settlements>"
                )
            );
        }
        revert("unsupported partId");
    }

    /// @inheritdoc IRepresentableStateVersioned
    function stateVersion() external view override returns (uint256) {
        return _stateVersion;
    }

    /// @inheritdoc IRepresentableStateHashed
    function stateHash() external view override returns (bytes32) {
        // For the demo, we hash core trade params and a summary of settlements.
        return keccak256(abi.encode(
            owner,
            notional,
            fixedRateBP,
            floatSpreadBP,
            effectiveDate,
            terminationDate,
            lastSettlementTime,
            lastSettlementValue,
            settlementCount
        ));
    }
}
