// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

interface IERC7092ESG {
     /**
    * @notice Returns the number of decimals used by the bond. For example, if it returns `10`, it means that the token amount MUST be multiplied by 10000000000 to get the standard representation.
    *
    * OPTIONAL - interfaces and other contracts MUST NOT expect these values to be present. The method is used to improve usability.
    */
    function decimals() external view returns(uint8);

    /**
    * @notice Rreturns the coupon currency, which is represented by the contract address of the token used to pay coupons. It can be the same as the one used for the principal
    *
    * OPTIONAL - interfaces and other contracts MUST NOT expect these values to be present. The method is used to improve usability.
    */
    function currencyOfCoupon() external view returns(address);

    /**
    * @notice Returns the coupon type
    *         For example, 0 can denote Zero coupon, 1 can denote Fixed Rate, 2 can denote Floating Rate, and so on
    *
    * OPTIONAL - interfaces and other contracts MUST NOT expect these values to be present. The method is used to improve usability.
    */
    function couponType() external view returns(uint8);

    /**
    * @notice Returns the coupon frequency, i.e. the number of times coupons are paid in a year.
    *
    * OPTIONAL - interfaces and other contracts MUST NOT expect these values to be present. The method is used to improve usability.
    */
    function couponFrequency() external view returns(uint256);

    /**
    * @notice Returns the day count basis
    *         For example, 0 can denote actual/actual, 1 can denote actual/360, and so on
    *
    * OPTIONAL - interfaces and other contracts MUST NOT expect these values to be present. The method is used to improve usability.
    */
    function dayCountBasis() external view returns(uint8);
}
