// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IERC173 } from "../interfaces/IERC173.sol";
import { LibCento } from "../libraries/LibCento.sol";

/// @title Ownership
/// @notice Facet implementing the `IERC173` ownership standard.
contract Ownership is IERC173{

    /// @inheritdoc IERC173
    function owner() external override view returns (address owner_) {
        owner_ = LibCento.contractOwner();
    }

    /// @inheritdoc IERC173
    function transferOwnership(address _newOwner) external override {
        LibCento.enforceIsContractOwner();
        LibCento.setContractOwner(_newOwner);
    }
}