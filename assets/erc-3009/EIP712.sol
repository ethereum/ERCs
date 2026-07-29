// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import { ECRecover } from "./ECRecover.sol";

/**
 * @title EIP712
 * @notice A library that provides EIP712 helper functions
 */
library EIP712 {
    // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
    bytes32
        public constant EIP712_DOMAIN_TYPEHASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    /**
     * @notice Make EIP712 domain separator
     * @param name      Contract name
     * @param version   Contract version
     * @return Domain separator
     */
    function makeDomainSeparator(string memory name, string memory version)
        internal
        view
        returns (bytes32)
    {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        return
            keccak256(
                abi.encode(
                    EIP712_DOMAIN_TYPEHASH,
                    keccak256(bytes(name)),
                    keccak256(bytes(version)),
                    chainId,
                    address(this)
                )
            );
    }

    /**
     * @notice Recover signer's address from a EIP712 signature
     * @param domainSeparator   Domain separator
     * @param v                 v of the signature
     * @param r                 r of the signature
     * @param s                 s of the signature
     * @param typeHashAndData   Type hash concatenated with data
     * @return Signer's address
     */
    function recover(
        bytes32 domainSeparator,
        uint8 v,
        bytes32 r,
        bytes32 s,
        bytes memory typeHashAndData
    ) internal pure returns (address) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(typeHashAndData)
            )
        );
        return ECRecover.recover(digest, v, r, s);
    }
}