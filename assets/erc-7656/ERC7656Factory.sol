// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC7656Factory} from "./interfaces/IERC7656Factory.sol";
import {IERC165} from "./interfaces/IERC165.sol";

import {ERC7656BytecodeLib} from "./lib/ERC7656BytecodeLib.sol";

// Mutated from https://github.com/erc6551/reference
// Original authors: Jayden Windle @jaydenwindle, @vectorized
// Adapted by: Francesco Sullo @sullof

contract ERC7656Factory is IERC165, IERC7656Factory {
  function create(
    address implementation,
    bytes32 salt,
    uint256 /* chainId */,
    bytes12 mode,
    address linkedContract,
    uint256 linkedId
  ) external override returns (address) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
    // Copy bytecode + constant data to memory
      calldatacopy(0x8c, 0x24, 0x40) // salt, chainId

      mstore(0x6c, 0x5af43d82803e903d91602b57fd5bf3) // ERC-1167 footer
      mstore(0x5d, implementation) // implementation
      mstore(0x49, 0x3d60ad80600a3d3981f3363d3d373d3d3d363d73) // ERC-1167 constructor + header
      mstore(0xcc, or(mode, linkedContract)) // mode
      mstore(0xec, linkedId) // linkedId

    // Copy create2 computation data to memory
      mstore8(0x00, 0xff) // 0xFF
      mstore(0x35, keccak256(0x55, 0xb7)) // keccak256(bytecode)
      mstore(0x01, shl(96, address())) // registry address
      mstore(0x15, salt) // salt

    // Compute service address
      let computed := keccak256(0x00, 0x55)

    // If the service has not yet been deployed
      if iszero(extcodesize(computed)) {
      // Deploy service contract
        let deployed := create2(0, 0x55, 0xb7, salt)

      // Revert if the deployment fails
        if iszero(deployed) {
          mstore(0x00, 0xd786d393) // `CreationFailed()`
          revert(0x1c, 0x04)
        }

      // Store service address in memory before salt and chainId
        mstore(0x6c, deployed)
        mstore(0xcc, mode)

      // Emit the Created event
        log4(
          0x6c, // pointer to start of data (contractAddress)
          0x80, // size of data (contractAddress + salt + chainId + mode)
          0x5d6f1b27222bf34d576ad575c1c8749e981db502da9cd2e96e6e525893809905, // event signature hash
          implementation, // indexed implementation
          linkedContract, // indexed linkedContract
          linkedId // indexed linkedId
        )

      // Return the service address
        return(0x6c, 0x20)
      }

    // Otherwise, return the computed service address
      mstore(0x00, shr(96, shl(96, computed)))
      return(0x00, 0x20)
    }
  }

  /**
   * @dev Computes the address where the proxy will be deployed
   */
  function compute(
    address implementation,
    bytes32 salt,
    uint256 /* chainId */,
    bytes12 mode,
    address linkedContract,
    uint256 linkedId
  ) external view returns (address) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
    // Copy bytecode + constant data to memory
      calldatacopy(0x8c, 0x24, 0x40) // salt, chainId

      mstore(0x6c, 0x5af43d82803e903d91602b57fd5bf3) // ERC-1167 footer
      mstore(0x5d, implementation) // implementation
      mstore(0x49, 0x3d60ad80600a3d3981f3363d3d373d3d3d363d73) // ERC-1167 constructor + header
      mstore(0xcc, or(mode, linkedContract)) // mode
      mstore(0xec, linkedId) // linkedId

    // Copy create2 computation data to memory
      mstore8(0x00, 0xff) // 0xFF
      mstore(0x35, keccak256(0x55, 0xb7)) // keccak256(bytecode)
      mstore(0x01, shl(96, address())) // registry address
      mstore(0x15, salt) // salt

    // Compute service address
      let computed := keccak256(0x00, 0x55)

      mstore(0x00, shr(96, shl(96, computed)))
      return(0x00, 0x20)
    }
  }

  /// @dev Returns true if interfaceId is IERC7656Factory.sol's interfaceId
  function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
    return interfaceId == type(IERC7656Factory).interfaceId || interfaceId == type(IERC165).interfaceId;
  }
}
