//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.30;

function boolIsFalsyWithErr(bool value, string memory errorDescription) pure {
    require(value == false, errorDescription);
}

function boolIsTruthyWithErr(bool value, string memory errorDescription) pure {
    require(value == true, errorDescription);
}
