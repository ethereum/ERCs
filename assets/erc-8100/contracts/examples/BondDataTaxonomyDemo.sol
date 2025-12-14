// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.19;

import {
IXMLRepresentableStateVersionedHashed,
IXMLRepresentableState, IRepresentableStateVersioned, IRepresentableStateHashed     // needed for @inheritdoc
} from "../IRepresentableState.sol";

/**
 * @title BondDataTaxonomyDemo
 * @notice Minimal example of an ICMA Bond Data Taxonomy (BDT)-inspired bond state
 *         exposed via IRepresentableState.sol. Intended for demo / testing of XML
 *         renderers and tooling.
 *
 *         This is not an official ICMA implementation. It mimics a small subset of
 *         typical BDT fields (identifiers, parties, economic terms, dates).
 * @author Christian Fries
 */
contract BondDataTaxonomyDemo is IXMLRepresentableStateVersionedHashed {

    // --- Core parties and identifiers ---

    address public immutable owner;

    string public issuerName;
    string public issuerLei;

    string public isin;
    string public instrumentName;

    // --- Key dates (UNIX timestamps, seconds since epoch, UTC) ---

    uint256 public issueDate;
    uint256 public maturityDate;

    // --- Economic terms ---

    uint256 public notionalAmount;               // e.g. 500_000_000_00 for 500,000,000.00 (scale 2)
    string  public currency;                     // e.g. "EUR"

    int256  public couponRateBP;                 // fixed rate in bp * 1e2, 2.5000% => 25000 (scale 4)
    string  public dayCountFraction;             // e.g. "30E/360"
    uint256 public couponFrequencyMonths;        // e.g. 12 for annual, 6 for semi-annual

    // --- Legal / status ---

    string  public governingLaw;                 // e.g. "DE"
    string  public status;                       // e.g. "Issued", "Matured", ...

    // --- Versioning for XML state ---

    uint256 private _stateVersion;

    // --- Events ---

    event CouponUpdated(int256 newCouponRateBP);
    event StatusUpdated(string newStatus);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    /**
     * @notice Demo constructor.
     * @dev For a real-world integration, most of these parameters should be constructor arguments.
     *      Here we hard-code example values to keep deployment simple.
     */
    constructor(address _owner) {
        owner = _owner;

        // Example issuer and instrument identifiers
        issuerName  = "Example Issuer SA";
        issuerLei   = "5493001KJTIIGC8Y1R12";
        isin        = "XS1234567890";
        instrumentName = "Example 2.50% 2030";

        // Example dates (approximate UTC midnights)
        issueDate      = 1736899200;   // ~ 2025-01-15T00:00:00Z
        maturityDate   = 1894838400;   // ~ 2030-01-15T00:00:00Z

        // Economic terms
        notionalAmount       = 500_000_000_00; // 500,000,000.00
        currency             = "EUR";
        couponRateBP         = 25000;         // 2.5000%
        dayCountFraction     = "30E/360";
        couponFrequencyMonths= 12;            // annual

        // Legal / status
        governingLaw         = "DE";
        status               = "Issued";

        _stateVersion     = 1;
    }

    // --- Mutations for demo purposes ---

    function updateCouponRate(int256 newCouponRateBP) external onlyOwner {
        couponRateBP = newCouponRateBP;
        _stateVersion += 1;
        emit CouponUpdated(newCouponRateBP);
    }

    function updateStatus(string calldata newStatus) external onlyOwner {
        status = newStatus;
        _stateVersion += 1;
        emit StatusUpdated(newStatus);
    }

    // --- IRepresentableState.sol ---

    /// @inheritdoc IXMLRepresentableState
    function stateXmlTemplate() external pure override returns (string memory) {
        // BDT-inspired XML structure.
        return
                    "<Contract xmlns='urn:example:contract'"
                    " xmlns:evmstate='urn:evm:state:1.0'"
                    " evmstate:chain-id=''"
                    " evmstate:contract-address=''"
                    " evmstate:block-number=''>"
                    "<BondData xmlns='urn:icma:bdt:1.0'>"

                    "<Security>"
                    "<Identifier>"
                    "<ISIN evmstate:call='isin()(string)'/>"
                    "</Identifier>"
                    "<Name evmstate:call='instrumentName()(string)'/>"
                    "<Status evmstate:call='status()(string)'/>"
                    "</Security>"

                    "<Issuer>"
                    "<Name evmstate:call='issuerName()(string)'/>"
                    "<LEI evmstate:call='issuerLei()(string)'/>"
                    "</Issuer>"

                    "<EconomicTerms>"

                    "<Notional>"
                    "<Amount evmstate:call='notionalAmount()(uint256)' evmstate:format='decimal' evmstate:scale='2'/>"
                    "<Currency evmstate:call='currency()(string)'/>"
                    "</Notional>"

                    "<IssueDate>"
                    "<UnadjustedDate evmstate:call='issueDate()(uint256)' evmstate:format='iso8601-date'/>"
                    "</IssueDate>"

                    "<MaturityDate>"
                    "<UnadjustedDate evmstate:call='maturityDate()(uint256)' evmstate:format='iso8601-date'/>"
                    "</MaturityDate>"

                    "<Coupon>"
                    "<Type>Fixed</Type>"
                    "<Rate evmstate:call='couponRateBP()(int256)' evmstate:format='decimal' evmstate:scale='4'/>"
                    "<DayCountFraction evmstate:call='dayCountFraction()(string)'/>"
                    "<Frequency>"
                    "<PeriodMultiplier evmstate:call='couponFrequencyMonths()(uint256)' evmstate:format='integer'/>"
                    "<Period>M</Period>"
                    "</Frequency>"
                    "</Coupon>"

                    "</EconomicTerms>"

                    "<GoverningLaw evmstate:call='governingLaw()(string)'/>"

                    "</BondData>"
                    "</Contract>";
    }

    /// @inheritdoc IRepresentableStateVersioned
    function stateVersion() external view override returns (uint256) {
        return _stateVersion;
    }

    /// @inheritdoc IRepresentableStateHashed
    function stateHash() external view override returns (bytes32) {
        return keccak256(
            abi.encode(
                owner,
                issuerName,
                issuerLei,
                isin,
                instrumentName,
                issueDate,
                maturityDate,
                notionalAmount,
                currency,
                couponRateBP,
                dayCountFraction,
                couponFrequencyMonths,
                governingLaw,
                status
            )
        );
    }
}
