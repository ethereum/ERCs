// SPDX-License-Identifier: MIT

// This implementation is a variation of https://github.com/erc6551/reference/blob/main/src/ERC6551Registry.sol
// Original authors: Jayden Windle @jaydenwindle and Vectorized @vectorized
// Adapted by: Francesco Sullo @sullof

interface IERC165 {
  function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC7656Registry {
  event Created(
    address contractAddress,
    address indexed implementation,
    bytes32 salt,
    uint256 chainId,
    address indexed linkedContract,
    bool mode,
    uint256 indexed id
  );

  /**
   * The registry MUST revert with CreationFailed error if the create2 operation fails.
   */
  error CreationFailed();

  function create(
    address implementation,
    bytes32 salt,
    uint256 chainId,
    address linkedContract,
    bytes1 mode,
    uint256 id
  ) external returns (address service);

  function compute(
    address implementation,
    bytes32 salt,
    uint256 chainId,
    address linkedContract,
    bytes1 mode,
    uint256 id
  ) external view returns (address service);
}

contract ERC7656Registry is IERC165, IERC7656Registry {

  function create(
    address implementation,
    bytes32 salt,
    uint256 chainId,
    address linkedContract,
    bytes1 noId,
    uint256 id
  ) external returns (address service) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
    // --- Build the appended constant data for the proxy ---
    // Copy salt (32 bytes) from calldata offset 0x24 to memory offset 0x8c.
      calldatacopy(0x8c, 0x24, 0x20)   // 0x20 = 32 bytes
    // Copy chainId (32 bytes) from calldata offset 0x44 to memory offset 0xAC.
      calldatacopy(0xAC, 0x44, 0x20)

    // For the noId flag:
    // The noId parameter is at calldata offset 0x84.
    // Extract the lowest (rightmost) byte and store it at memory offset 0xCC.
    // (ABI-encoded bytes1 is right-aligned in its 32-byte slot.)
      let rawNoId := calldataload(0x84)
    // Extract the last byte (masking with 0xFF)
      mstore8(0xCC, and(rawNoId, 0xFF))
    // The next 11 bytes (0xCD to 0xD7) remain zero (reserved for future use).

    // Copy linkedContract (32 bytes, but only the lower 20 bytes are relevant)
    // from calldata offset 0x64 to memory offset 0xD8.
    // (ABI encoding left-pads addresses, so the lower 20 bytes are the address.)
      calldatacopy(0xD8, 0x64, 0x20)

    // Copy tokenId (32 bytes) from calldata offset 0xA4 to memory offset 0xEC.
      calldatacopy(0xEC, 0xA4, 0x20)

    // --- Set up the minimal proxy “pre-append” part ---
    // Write ERC-1167 constructor + header (10 bytes) at offset 0x49.
      mstore(0x49, 0x3d60ad80600a3d3981f3363d3d373d3d3d363d73)
    // Write implementation address (20 bytes) at offset 0x5d.
      mstore(0x5d, implementation)
    // Write ERC-1167 footer (15 bytes) at offset 0x6c.
      mstore(0x6c, 0x5af43d82803e903d91602b57fd5bf3)

    // --- Compute CREATE2 address ---
    // Layout for CREATE2 hash:
    //   0x00: 0xff (1 byte)
    //   0x01: registry address (this contract’s address, 20 bytes)
    //   0x15: salt (32 bytes)
    //   0x35: keccak256(proxy code) (32 bytes)
      mstore8(0x00, 0xff)
      mstore(0x01, shl(96, address()))
      mstore(0x15, salt)

    // Total appended constant data length is 128 bytes.
    // Pre-append part is 45 bytes.
      let proxyCodeLength := add(45, 128) // = 173 bytes

    // Compute the hash of the complete proxy code.
    // (Assume that the proxy code is laid out in memory starting at offset 0x55.)
      let codeHash := keccak256(0x55, proxyCodeLength)
      mstore(0x35, codeHash)

    // Compute the CREATE2 address (hash over 0x00..0x55, i.e. 85 bytes).
      let computed := keccak256(0x00, 0x55)

    // --- Deploy the proxy if not already deployed ---
      if iszero(extcodesize(computed)) {
        let deployed := create2(0, 0x55, proxyCodeLength, salt)
        if iszero(deployed) {
          mstore(0x00, 0xd786d393) // Error signature for CreationFailed()
          revert(0x1c, 0x04)
        }
      // Store deployed address in memory at 0x6c for return.
        mstore(0x6c, deployed)

      // --- Emit the appropriate event ---
      // We assume that there are two events:
      // If noId == 0x01 then the tokenId is not applicable and we emit the event without tokenId.
      // Otherwise, we emit the event including tokenId.
      // For clarity, assume:
      //    Event with tokenId signature: 0xc6bdc908f7e52c2b7c3d8d5d7e8f3a1b4c2d6e9f0a3b5c7d8e9f0a1b2c3d4e5f6
      //    Event without tokenId signature: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
      // Check the noId flag (the stored byte at 0xCC)
        switch eq(and(rawNoId, 0xFF), 0x01)
        case 1 {
        // Emit event without tokenId.
          log4(
            0x6c, // memory offset where deployed address is stored
            0x60, // assume 96 bytes of log data (contractAddress, salt, chainId, linkedContract)
            0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925,
            implementation,
            linkedContract
          )
        }
        default {
        // Emit event with tokenId.
          log4(
            0x6c,
            0x60,
            0xc6bdc908f7e52c2b7c3d8d5d7e8f3a1b4c2d6e9f0a3b5c7d8e9f0a1b2c3d4e5f6,
            implementation,
            linkedContract,
            id
          )
        }

      // Return the deployed proxy address.
        return(0x6c, 0x20)
      }
    // If already deployed, return the computed address.
      mstore(0x00, shr(96, shl(96, computed)))
      return(0x00, 0x20)
    }
  }


  function compute(
    address implementation,
    bytes32 salt,
    uint256 chainId,
    address linkedContract,
    bytes1 noId,
    uint256 tokenId
  ) external view override returns (address service) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
    // --- Copy appended constant data into memory ---
    // Using the same offsets as in the create function.
    // Parameters are ABI-encoded in 32-byte slots in the following order:
    // 0: function selector
    // 4: implementation (we'll use this separately)
    // 36: salt
    // 68: chainId
    // 100: linkedContract
    // 132: noId (only lower byte is relevant)
    // 164: tokenId

    // Copy salt (32 bytes) from calldata offset 0x24 into memory at 0x8c.
      calldatacopy(0x8c, 0x24, 0x20)
    // Copy chainId (32 bytes) from calldata offset 0x44 into memory at 0xAC.
      calldatacopy(0xAC, 0x44, 0x20)
    // Copy linkedContract (32 bytes) from calldata offset 0x64 into memory at 0xD8.
    // Note: Although a full 32-byte word is copied, only the lower 20 bytes are meaningful.
      calldatacopy(0xD8, 0x64, 0x20)
    // Copy tokenId (32 bytes) from calldata offset 0xA4 into memory at 0xEC.
      calldatacopy(0xEC, 0xA4, 0x20)
    // Load the noId parameter from calldata offset 0x84.
      let rawNoId := calldataload(0x84)
    // Store only the lowest byte of noId at memory offset 0xCC.
      mstore8(0xCC, and(rawNoId, 0xFF))
    // The next 11 bytes (0xCD–0xD7) remain zero (reserved for future use).

    // --- Write the minimal proxy “pre-append” part ---
    // Write the ERC-1167 constructor + header (10 bytes) at offset 0x49.
      mstore(0x49, 0x3d60ad80600a3d3981f3363d3d373d3d3d363d73)
    // Write the implementation address (20 bytes) at offset 0x5d.
      mstore(0x5d, implementation)
    // Write the ERC-1167 footer (15 bytes) at offset 0x6c.
      mstore(0x6c, 0x5af43d82803e903d91602b57fd5bf3)

    // --- Compute the proxy code hash for CREATE2 ---
    // Total proxy code length = pre-append (45 bytes) + appended constant data (128 bytes) = 173 bytes.
      let proxyCodeLength := add(45, 128) // 173 bytes

    // Setup the CREATE2 computation inputs:
    // At memory offset 0x00, store 0xff (1 byte)
      mstore8(0x00, 0xff)
    // At offset 0x01, store the registry address (this contract's address), left-padded.
      mstore(0x01, shl(96, address()))
    // At offset 0x15, store the salt.
      mstore(0x15, salt)

    // Compute keccak256 of the proxy code.
    // Assume that the proxy code is laid out in memory starting at offset 0x55.
      let codeHash := keccak256(0x55, proxyCodeLength)
      mstore(0x35, codeHash)

    // Compute the final CREATE2 hash over memory from offset 0x00 with length 0x55 (85 bytes).
      let computed := keccak256(0x00, 0x55)

    // Return the computed address.
    // Addresses are the lower 20 bytes of the computed hash.
      mstore(0x00, shr(96, shl(96, computed)))
      return(0x00, 0x20)
    }
  }

  /// @dev Returns true if interfaceId is IERC7656Registry's interfaceId
  function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
    return interfaceId == type(IERC7656Registry).interfaceId || interfaceId == type(IERC165).interfaceId;
  }
}

