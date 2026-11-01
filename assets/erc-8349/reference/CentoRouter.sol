// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IObservability } from "./interfaces/IObservability.sol";
import { IFacetManager } from "./interfaces/IFacetManager.sol";
import { LibCento as lc } from "./libraries/LibCento.sol";
import { IERC173 } from "./interfaces/IERC173.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { CentoStorage as CS } from "./structs/CentoStorage.sol";
import { bitmap256 } from "./libraries/LibBitmap.sol";

/// @title Cento Router
/// @notice Entry point for the Cento Proxy protocol.
/// @dev Routes calls to installed facets using one of two dispatch strategies:
/// - Appended-index routing for protocol functions.
/// - Selector-based routing for compatibility standards and small protocols.
/// @dev The router itself is immutable after deployment. Protocol functionality is
/// provided entirely by delegatecalls into installed facets.
contract CentoRouter { 

    /// @dev Selector of error `FacetNotFound(uint8)`.
    bytes4  private constant ERR_FACET_NOT_FOUND = 0xca05c783;
    /// @dev ERC-7201 namespace backing the shared `CentoStorage` layout.
    bytes32 private constant BASE_SLOT    = 0x69f90de95fb99742e875407e8b95a22f11141a7a0ca101bc562658f163a85b00;
    /// @dev Routing index of the facet that supports ERC-173.
    uint8   private constant ERC173_INDEX = 1;
    /// @dev Routing index of the facet that supports ERC-165.
    uint8   private constant ERC165_INDEX = 2;

    /// @notice Deploys a new `CentoRouter`.
    /// @param _contractOwner Initial protocol owner.
    /// @param facetAddresses Addresses of the core protocol facets.
    /// @dev Expects the following facet order:
    /// - index 0: FacetManager
    /// - index 1: Ownership *(with ERC-173)*
    /// - index 2: Observability *(with ERC-165)*
    /// @dev Additional facets are installed later through the  `FacetManager`.
    constructor (address _contractOwner, address[3] memory facetAddresses) payable {
        CS storage cs = lc._cs();
        cs.contractOwner = _contractOwner; 
        emit lc.OwnershipTransferred(address(0), _contractOwner);
        cs.facets[0] = facetAddresses[0];
        cs.facets[1] = facetAddresses[1];
        cs.facets[2] = facetAddresses[2];
        cs.indexBitmap = bitmap256.wrap(7); // 0b000000...00000111
        cs.supportedInterfaces[type(IERC165).interfaceId] = true; 
        cs.supportedInterfaces[type(IERC173).interfaceId] = true; 
        cs.supportedInterfaces[type(IFacetManager).interfaceId] = true; 
        cs.supportedInterfaces[type(IObservability).interfaceId] = true;
    }

    /// @notice Dispatches incoming function calls to the appropriate facet.
    /// @dev Uses two routing modes:
    /// - **Protocol routing**\
    ///   Functions whose calldata ends with a facet index are\
    ///   dispatched directly using the appended index.
    /// - **Compatibility routing**\
    ///   Selectors of compatibility standards are dispatched through\
    ///   the stage-2 routing, preserving standard external APIs.
    /// @dev All calls execute via `delegatecall`, preserving the `CentoRouter` storage
    /// context and propagating returndata or reverts unchanged.
    fallback() external payable {
        assembly {
            let cds := calldatasize()
            if and(cds, 1) {
                // inlining logic for the hot path saves 23 gas per call at the cost of 67 bytes of additional bytecode
                let idx := byte(0, calldataload(sub(cds, 1)))
                let facet := sload(add(BASE_SLOT, idx))
                if iszero(facet) { 
                    mstore(0x00, ERR_FACET_NOT_FOUND)
                    mstore(0x04, idx)
                    revert(0x00, 0x24)
                }
                calldatacopy(0, 0, cds)
                let ok := delegatecall(gas(), facet, 0, sub(cds, 1), 0, 0)
                returndatacopy(0, 0, returndatasize())
                switch ok
                case 0  { revert(0, returndatasize()) }
                default { return(0, returndatasize()) }
            } 
            // If you have more than 6 selectors, use optimized BST
            switch shr(224, calldataload(0))
            case 0x01ffc9a7 { executeFacet(ERC165_INDEX, cds, 0) }
            case 0x8da5cb5b { executeFacet(ERC173_INDEX, cds, 0) }
            case 0xf2fde38b { executeFacet(ERC173_INDEX, cds, 0) }
            executeFacet(byte(0, calldataload(sub(cds, 1))), cds, 1)

            //  These commenst are not a part of forge doc
            /// @dev Executes a delegatecall to the resolved facet address.
            /// @param idx The index of the facet layout in storage.
            /// @param totalSize Total calldata length available.
            /// @param stripLen Bytes to strip from the end of calldata (0 or 1)
            /// @notice inline functions are impossible to cover in the eyes of `forge coverage`
            function executeFacet(idx, totalSize, stripLen) {
                let facet := sload(add(BASE_SLOT, idx))
                if iszero(facet) { 
                    mstore(0x00, ERR_FACET_NOT_FOUND)
                    mstore(0x04, idx)
                    revert(0x00, 0x24)
                }
                let size := sub(totalSize, stripLen)
                calldatacopy(0, 0, size)
                let ok := delegatecall(gas(), facet, 0, size, 0, 0)
                returndatacopy(0, 0, returndatasize())
                switch ok
                case 0  { revert(0, returndatasize()) }
                default { return(0, returndatasize()) }
            }
        }
    }
    
    /// @notice Accepts plain ETH transfers.
    receive() external payable {}
}
