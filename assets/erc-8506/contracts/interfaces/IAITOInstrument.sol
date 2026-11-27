// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SeriesTerms, Outcome} from "./AITOTypes.sol";

/// @title Series of AI inference entitlements and their home ledger
interface IAITOInstrument {
    event SeriesCreated(
        uint256 indexed seriesId,
        address indexed issuer,
        address indexed responsibleParty,
        bytes32 termsHash,
        string termsURI
    );
    event ResponsibilityAccepted(uint256 indexed seriesId, address indexed responsibleParty);
    event FulfillerSet(uint256 indexed seriesId, address indexed fulfiller, bool allowed);
    event Issued(uint256 indexed seriesId, address indexed to, uint256 amount, bytes32 basisRef);
    event Retired(uint256 indexed seriesId, address indexed holder, uint256 amount);
    event Lapsed(uint256 indexed seriesId, address indexed holder, uint256 amount);

    /// @notice Create a series. The caller MUST be `terms.issuer`.
    /// @return seriesId `uint256(keccak256(abi.encode(terms)))`.
    function createSeries(SeriesTerms calldata terms, string calldata termsURI) external returns (uint256 seriesId);

    /// @notice The identifier a series with these terms has.
    function seriesIdOf(SeriesTerms calldata terms) external pure returns (uint256);

    /// @notice Called by the responsible party to take on the supply obligation of the series.
    function acceptResponsibility(uint256 seriesId) external;

    /// @notice Called by the responsible party to allow or disallow a fulfiller.
    function setFulfiller(uint256 seriesId, address fulfiller, bool allowed) external;

    /// @notice Issue units. `basisRef` cites an issuance basis declared in the Source record.
    function issue(uint256 seriesId, address to, uint256 amount, bytes32 basisRef) external;

    /// @notice Give up the caller's own units without consuming them.
    function retire(uint256 seriesId, uint256 amount) external;

    /// @notice Remove the unconsumed units of `holder` after the series has expired.
    function lapse(uint256 seriesId, address holder) external;

    function seriesOf(uint256 seriesId) external view returns (SeriesTerms memory);
    function termsURI(uint256 seriesId) external view returns (string memory);
    function responsibilityAccepted(uint256 seriesId) external view returns (bool);
    function isFulfiller(uint256 seriesId, address account) external view returns (bool);

    /// @notice Whether this ledger implements `extension`.
    function supportsExtension(bytes32 extension) external view returns (bool);

    /// @notice The deduction, in denomination units, that the series schedule gives for `usage` and `outcome`.
    function quoteCharge(uint256 seriesId, uint256[] calldata usage, Outcome outcome)
        external
        view
        returns (uint256);

    // Accounting. For every series:
    // issuedOf == consumedOf + retiredOf + lapsedOf + heldOf + sum of availableOf over all holders.
    function issuedOf(uint256 seriesId) external view returns (uint256);
    function consumedOf(uint256 seriesId) external view returns (uint256);
    function retiredOf(uint256 seriesId) external view returns (uint256);
    function lapsedOf(uint256 seriesId) external view returns (uint256);

    /// @notice Units of the series currently reserved by holds.
    function heldOf(uint256 seriesId) external view returns (uint256);

    /// @notice Units of `holder` currently reserved by holds.
    function heldBy(uint256 seriesId, address holder) external view returns (uint256);

    /// @notice Units of `holder` that are neither reserved nor consumed.
    function availableOf(uint256 seriesId, address holder) external view returns (uint256);

    /// @notice `availableOf` while the series can be consumed, otherwise zero.
    function consumableOf(uint256 seriesId, address holder) external view returns (uint256);
}
