// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

abstract contract EIP712Domain {
    /**
     * @dev EIP712 Domain Separator
     */
    bytes32 public DOMAIN_SEPARATOR;
}