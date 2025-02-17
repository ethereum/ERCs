// SPDX-License-Identifier: MIT

// This implementation is a variation of https://github.com/erc6551/reference/blob/main/src/ERC6551Registry.sol
// Original authors: Jayden Windle @jaydenwindle and Vectorized @vectorized
// Adapted by: Francesco Sullo @sullof

contract ERC7656Registry is IERC7656Registry {
  function create(
    address implementation,
    bytes32 salt,
    uint256 /* chainId */,
    address tokenContract,
    uint256 tokenId
  ) external override returns (address) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
    // Memory Layout:
    // ----
    // 0x00   0xff                           (1 byte)
    // 0x01   registry (address)             (20 bytes)
    // 0x15   salt (bytes32)                 (32 bytes)
    // 0x35   Bytecode Hash (bytes32)        (32 bytes)
    // ----
    // 0x55   ERC-1167 Constructor + Header  (20 bytes)
    // 0x69   implementation (address)       (20 bytes)
    // 0x5D   ERC-1167 Footer                (15 bytes)
    // 0x8C   salt (uint256)                 (32 bytes)
    // 0xAC   chainId (uint256)              (32 bytes)
    // 0xCC   tokenContract (address)        (32 bytes)
    // 0xEC   tokenId (uint256)              (32 bytes)

    // Copy bytecode + constant data to memory
      calldatacopy(0x8c, 0x24, 0x80) // salt, chainId, tokenContract, tokenId
      mstore(0x6c, 0x5af43d82803e903d91602b57fd5bf3) // ERC-1167 footer
      mstore(0x5d, implementation) // implementation
      mstore(0x49, 0x3d60ad80600a3d3981f3363d3d373d3d3d363d73) // ERC-1167 constructor + header

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

      // Emit the Created event
        log4(
          0x6c,
          0x60,
          0xc6989e4f290074742210cbd6491de7ded9cfe2cd247932a53d31005007a6341a,
          implementation,
          tokenContract,
          tokenId
        )

      // Return the service address
        return(0x6c, 0x20)
      }

    // Otherwise, return the computed service address
      mstore(0x00, shr(96, shl(96, computed)))
      return(0x00, 0x20)
    }
  }

  function compute(
    address implementation,
    bytes32 salt,
    uint256 /* chainId */,
    address /* tokenContract */,
    uint256 /* tokenId */
  ) external view override returns (address) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
    // Copy bytecode + constant data to memory
      calldatacopy(0x8c, 0x24, 0x80) // salt, chainId, tokenContract, tokenId
      mstore(0x6c, 0x5af43d82803e903d91602b57fd5bf3) // ERC-1167 footer
      mstore(0x5d, implementation) // implementation
      mstore(0x49, 0x3d60ad80600a3d3981f3363d3d373d3d3d363d73) // ERC-1167 constructor + header

    // Copy create2 computation data to memory
      mstore8(0x00, 0xff) // 0xFF
      mstore(0x35, keccak256(0x55, 0xb7)) // keccak256(bytecode)
      mstore(0x01, shl(96, address())) // registry address
      mstore(0x15, salt) // salt

    // Store computed service address in memory
      mstore(0x00, shr(96, shl(96, keccak256(0x00, 0x55))))

    // Return computed service address
      return(0x00, 0x20)
    }
  }

  /// @dev Returns true if interfaceId is IERC7656Registry's interfaceId
  /// This contract does not explicitly extend IERC165 to keep the bytecode as small as possible
  function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
    return interfaceId == 0xc6bdc908;
  }
}

