// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.19;

import {
IXMLRepresentableStateVersionedHashed,
IXMLRepresentableState,         // needed for @inheritdoc
IRepresentableStateVersioned,   // needed for @inheritdoc
IRepresentableStateHashed       // needed for @inheritdoc
} from "../IRepresentableState.sol";

/**
 * @title TestContract
 * @notice Contract to demonstrate and test data types, formats and array bindings
 *         for IRepresentableState.sol renderers.
 *
 * Fields are initialized with demo values in the constructor so that an off-chain renderer
 * can immediately exercise different type/format combinations without any prior updates.
 */
contract TestContract is IXMLRepresentableStateVersionedHashed {

    address public immutable owner;

    // Unsigned integers
    uint256 public valueUint;           // e.g. 123456789
    uint256 public valueMoney;          // e.g. 123456 (scale 2 -> 1234.56)
    uint256 public valueRateBP;         // e.g. 25000 (scale 4 -> 2.5000%)
    uint256 public valueHex;            // e.g. 0xdeadbeef
    uint256 public timestampDate;       // UNIX ts -> iso8601-date
    uint256 public timestampDateTime;   // UNIX ts -> iso8601-datetime

    // Signed integers
    int256  public valueIntPos;         // +123456
    int256  public valueIntNeg;         // -123456

    // Address
    address public exampleAddress;

    // Bool
    bool    public flagTrue;
    bool    public flagFalse;

    // String
    string  public textPlain;

    // Bytes
    bytes   public dataBytes;

    // Currency for multi-binding
    string  public currency;

    // --- Arrays for array binding profile (Mode B) ---------------------------------------------

    // e.g. coupon amounts (scale 2 -> 1000.00, 2500.00, ...)
    int256[] public couponAmounts;

    // matching labels for the coupons
    string[] public couponLabels;

    // XML state version (for versioned extension)
    uint256 private _stateVersion;

    constructor(address _owner) {
        owner = _owner;

        // Unsigned ints
        valueUint          = 123_456_789;
        valueMoney         = 123_456;        // 1234.56 with scale=2
        valueRateBP        = 25_000;         // 2.5000% with scale=4
        valueHex           = 0xDEADBEEF;
        timestampDate      = 1735689600;     // 2025-01-01T00:00:00Z
        timestampDateTime  = 1735776000;     // 2025-01-02T00:00:00Z

        // Signed ints
        valueIntPos        = 123_456;
        valueIntNeg        = -123_456;

        // Address
        exampleAddress     = _owner;

        // Bools
        flagTrue           = true;
        flagFalse          = false;

        // String
        textPlain          = "Hello, XML & EVM!";

        // Bytes
        dataBytes          = hex"0102030405DEADBEEF0102030405DEADBEEF0102030405DEADBEEF";

        // Currency for multi-binding
        currency           = "EUR";

        // Arrays for array binding demo
        couponAmounts.push(100_000);   // 1000.00 with scale 2
        couponAmounts.push(250_000);   // 2500.00 with scale 2
        couponAmounts.push(175_500);   // 1755.00 with scale 2

        couponLabels.push("Coupon 1");
        couponLabels.push("Coupon 2");
        couponLabels.push("Coupon 3");

        _stateVersion   = 1;
    }

    // --- IRepresentableState.sol ---

    /// @inheritdoc IXMLRepresentableState
    function stateXmlTemplate() external pure override returns (string memory) {
        // Note: single quotes in XML to allow double quotes in solidity for a single string-block.
        return
                    "<Contract xmlns='urn:example:contract'"
                    " xmlns:evmstate='urn:evm:state:1.0'"
                    " evmstate:chain-id=''"
                    " evmstate:contract-address=''"
                    " evmstate:block-number=''>"

                    "<TestContract xmlns='urn:example:format-showcase'>"

                    // ---- Unsigned Integers ----
                    "<UintRaw evmstate:call='valueUint()(uint256)' evmstate:format='integer'/>"
                    "<UintDecimal2 evmstate:call='valueMoney()(uint256)' evmstate:format='decimal' evmstate:scale='2'/>"
                    "<UintHex evmstate:call='valueHex()(uint256)' evmstate:format='hex'/>"

                    // Date/Datetime from UNIX timestamps (seconds since epoch)
                    "<Date evmstate:call='timestampDate()(uint256)' evmstate:format='iso8601-date'/>"
                    "<DateTime evmstate:call='timestampDateTime()(uint256)' evmstate:format='iso8601-datetime'/>"

                    // ---- Signed Integers ----
                    "<IntPos evmstate:call='valueIntPos()(int256)' evmstate:format='decimal'/>"
                    "<IntNeg evmstate:call='valueIntNeg()(int256)' evmstate:format='decimal'/>"

                    // ---- Address ----
                    "<ExampleAddress evmstate:call='exampleAddress()(address)' evmstate:format='address'/>"

                    // ---- Booleans ----
                    "<FlagTrue evmstate:call='flagTrue()(bool)' evmstate:format='boolean'/>"
                    "<FlagFalse evmstate:call='flagFalse()(bool)' evmstate:format='boolean'/>"

                    // ---- String ----
                    "<TextPlain evmstate:call='textPlain()(string)' evmstate:format='string'/>"

                    // ---- Bytes (hex + base64) ----
                    "<BytesHex evmstate:call='dataBytes()(bytes)' evmstate:format='hex'/>"
                    "<BytesBase64 evmstate:call='dataBytes()(bytes)' evmstate:format='base64'/>"

                    // ---- Multi-binding: amount as text, currency as attribute ----
                    "<Money"
                    " evmstate:calls='valueMoney()(uint256);currency()(string)'"
                    " evmstate:formats='decimal;string'"
                    " evmstate:scales='2;'"        // 2 decimals for amount, no scaling for currency
                    " evmstate:targets=';currency'/>"

                    // ---- Array binding profile (Mode B): scalar arrays -> repeated rows ----
                    "<ArrayExamples>"

                    // int256[] -> repeated <Coupon> with decimal+scale
                    "<Coupons"
                    " evmstate:call='couponAmounts()(int256[])'"
                    " evmstate:item-element='Coupon'>"
                    "<Coupon"
                    " evmstate:item-field='0'"
                    " evmstate:format='decimal'"
                    " evmstate:scale='2'/>"
                    "</Coupons>"

                    // string[] -> repeated <Label> with plain string
                    "<CouponLabels"
                    " evmstate:call='couponLabels()(string[])'"
                    " evmstate:item-element='Label'>"
                    "<Label"
                    " evmstate:item-field='0'"
                    " evmstate:format='string'/>"
                    "</CouponLabels>"

                    "</ArrayExamples>"

                    "</TestContract>"
                    "</Contract>";
    }

    /// @inheritdoc IRepresentableStateVersioned
    function stateVersion() external view override returns (uint256) {
        return _stateVersion;
    }

    /// @inheritdoc IRepresentableStateHashed
    function stateHash() external view override returns (bytes32) {
        // Einfach alle relevanten Felder in die Hash-Basis aufnehmen
        return keccak256(
            abi.encode(
                owner,
                valueUint,
                valueMoney,
                valueRateBP,
                valueHex,
                timestampDate,
                timestampDateTime,
                valueIntPos,
                valueIntNeg,
                exampleAddress,
                flagTrue,
                flagFalse,
                textPlain,
                dataBytes,
                currency,
                couponAmounts,
                couponLabels
            )
        );
    }
}
