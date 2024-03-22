// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

/**
* @title ERC-7586 Interest Rate Swaps
*/
interface IERC7586 /** is ERC20, ERC165 */ {
    // events
    /**
    * @notice MUST be emitted when interest rates are swapped
    * @param _amount the interest difference to be transferred
    * @param _account the recipient account to send the interest difference to. MUST be either the `payer` or the `receiver`
    */
    event Swap(uint256 _amount, address _account);

    /**
    * @notice MUST be emitted when the swap contract is terminated
    * @param _payer the swap payer
    * @param _receiver the swap receiver
    */
    event TerminateSwap(address indexed _payer, address indexed _receiver);

    // functions
    /**
    *  @notice Returns the IRS `payer` account address. The party who agreed to pay fixed interest
    */
    function fixedInterestPayer() external view returns(address);

    /**
    *  @notice Returns the IRS `receiver` account address. The party who agreed to pay floating interest
    */
    function floatingInterestPayer() external view returns(address);

    /**
    * @notice Returns the number of decimals the swap rate and spread use - e.g. `4` means to divide the rates by `10000`
    *         To express the interest rates in basis points unit, the decimal MUST be equal to `2`. This means rates MUST be divided by `100`
    *         1 basis point = 0.01% = 0.0001
    *         ex: if interest rate = 2.5%, then swapRate() => 250 `basis points`
    */
    function ratesDecimals() external view returns(uint8);

    /**
    *  @notice Returns the fixed interest rate
    */
    function swapRate() external view returns(uint256);

    /**
    *  @notice Returns the floating rate spread, i.e. the fixed part of the floating interest rate
    *
    *          floatingRate = benchmark + spread
    */
    function spread() external view returns(uint256);

    /**
    * @notice Returns the contract address of the asset to be transferred when swapping IRS. Depending on what the two parties agreed upon, this could be a currency, etc.
    *         Example: If the two parties agreed to swap interest rates in USDC, then this function should return the USDC contract address.
    *                  This address SHOULD be used in the `swap` function to transfer the interest difference to either the `payer` or the `receiver`. Example: IERC(assetContract).transfer
    */
    function assetContract() external view returns(address);

    /**
    *  @notice Returns the notional amount in unit of asset to be transferred when swapping IRS. This amount serves as the basis for calculating the interest payments, and may not be exchanged
    *          Example: If the two parties aggreed to swap interest rates in USDC, then the notional amount may be equal to 1,000,000 USDC 
    */
    function notionalAmount() external view returns(uint256);

    /**
    *  @notice Returns the interest payment frequency
    */
    function paymentFrequency() external view returns(uint256);

    /**
    *  @notice Returns an array of specific dates on which the interest payments are exchanged. Each date MUST be a Unix timestamp like the one returned by block.timestamp
    *          The length of the array returned by this function MUST equal the total number of swaps that should be realized
    *
    *  OPTIONAL
    */
    function paymentDates() external view returns(uint256[] memory);

    /**
    *  @notice Returns the starting date of the swap contract. This is a Unix Timestamp like the one returned by block.timestamp
    */
    function startingDate() external view returns(uint256);

    /**
    *  @notice Returns the maturity date of the swap contract. This is a Unix Timestamp like the one returned by block.timestamp
    */
    function maturityDate() external view returns(uint256);

    /**
    *  @notice Returns the benchmark in basis point unit
    *          Example: value of one the following rates: CF BIRC, EURIBOR, HIBOR, SHIBOR, SOFR, SONIA, TONAR, etc.
    */
    function benchmark() external view returns(uint256);

    /**
    *  @notice Returns the oracle contract address for the benchmark rate, or the zero address when the two parties agreed to set the benchmark manually.
    *          This contract SHOULD be used to fetch real time benchmark rate
    *          Example: Contract address for `CF BIRC`
    *
    *  OPTIONAL. The two parties MAY agree to set the benchmark manually
    */
    function oracleContractForBenchmark() external view returns(address);

    /**
    *  @notice Makes swap calculation and transfers the interest difference to either the `payer` or the `receiver`
    */
    function swap() external returns(bool);

    /**
    *  @notice Terminates the swap contract before its maturity date. MUST be called by either the `payer`or the `receiver`.
    */
    function terminateSwap() external;
}
