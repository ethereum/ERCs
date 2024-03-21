// SPDX-License-Identifier: Apache License 2.0
 
pragma solidity ^0.8.20;

contract CDaoDivisionErrorinfo {
    mapping(uint256 => string) private errorMessage;

    ///  unint coOwnerNum ， 权利共有人的数量；
    constructor() {
        initErrorMessage();
    }

    function initErrorMessage() private {
        errorMessage[0] = "success";
        errorMessage[1] = "Valuation has not yet begun!";
        errorMessage[2] = "Valuation has ended!";
        errorMessage[3] = "Reveal has not yet begun!";
        errorMessage[4] = "Reveal has ended!";

        errorMessage[6] = "Reveal error!";

        errorMessage[11] = "error info  is not definite";
        errorMessage[12] = "error info  is not definite";
    }

    function getErrorInfo(uint256 errorNo) public view returns (string memory) {
        string memory errorInfo = errorMessage[errorNo];

        if (bytes(errorInfo).length == 0) {
            return "error info  is not definite";
        }
        return errorInfo;
    }
}