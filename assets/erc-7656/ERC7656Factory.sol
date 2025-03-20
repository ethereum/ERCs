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
    bytes1 mode,
    address indexed linkedContract,
    uint256 indexed linkedId
  );

  /**
   * The registry MUST revert with CreationFailed error if the create2 operation fails.
   */
  error CreationFailed();

  function create(
    address implementation,
    bytes32 salt,
    uint256 chainId,
    bytes1 mode,
    address linkedContract,
    uint256 linkedId
  ) external returns (address service);

  function compute(
    address implementation,
    bytes32 salt,
    uint256 chainId,
    address linkedContract,
    bytes1 mode,
    uint256 linkedId
  ) external view returns (address service);
}

contract ERC7656Factory is IERC165, IERC7656Registry {
  // Constants at contract level
  bytes private constant _ERC1167_HEADER = hex"3d602d80600a3d3981f3363d3d373d3d3d363d73";
  bytes private constant _ERC1167_FOOTER = hex"5af43d82803e903d91602b57fd5bf3";

  /**
   * @dev Creates a proxy contract using the provided parameters
   * If the proxy already exists, returns its address without attempting creation
   */
  function create(
    address implementation,
    bytes32 salt,
    uint256 chainId,
    bytes1 mode,
    address linkedContract,
    uint256 linkedId
  ) external returns (address service) {
    // Generate the initialization code
    bytes memory initCode = _generateInitCode(implementation, salt, chainId, mode, linkedContract, linkedId);

    // Calculate the expected address
    address expectedAddress = _computeAddress(initCode, salt);

    // Check if contract already exists at the expected address
    uint256 codeSize;
    assembly {
      codeSize := extcodesize(expectedAddress)
    }

    // If the contract already exists, return its address without emitting an event
    if (codeSize > 0) {
      return expectedAddress;
    }

    // Deploy the contract using create2
    assembly {
    // Get pointers to the initialization code in memory
      let ptr := add(initCode, 32)
      let size := mload(initCode)

    // Deploy contract using create2
      service := create2(0, ptr, size, salt)

    // Check if deployment was successful
      if iszero(extcodesize(service)) {
      // Revert with CreationFailed error
        mstore(0, 0x4a9ab1d6) // CreationFailed() error selector
        revert(0, 4)
      }
    }

    // Emit the Created event using YUL
    assembly {
    // Store the non-indexed parameters to memory
      mstore(0, service)            // contractAddress
      mstore(32, salt)              // salt
      mstore(64, chainId)           // chainId

    // Store mode as a full 32-byte word
    // Clear the memory slot first
      mstore(96, 0)
    // Store mode in the most significant byte position
      mstore8(96, shr(248, shl(248, mode)))

    // Get the event signature
      let signature := 0x4d22bc5fbebe9264a7c91a137a2181826b5fba62011e4f344d4315977a9c260e

    // Emit the event
      log4(
        0,                    // memory start
        128,                  // memory length
        signature,            // event signature
        implementation,       // indexed parameter 1
        linkedContract,       // indexed parameter 2
        linkedId              // indexed parameter 3
      )
    }

    return service;
  }

  /**
   * @dev Computes the address where the proxy will be deployed
   */
  function compute(
    address implementation,
    bytes32 salt,
    uint256 chainId,
    bytes1 mode,
    address linkedContract,
    uint256 linkedId
  ) external view returns (address) {
    // Generate the initialization code
    bytes memory initCode = _generateInitCode(implementation, salt, chainId, mode, linkedContract, linkedId);

    // Compute the address
    return _computeAddress(initCode, salt);
  }

  /**
   * @dev Internal function to compute the address using CREATE2 formula
   */
  function _computeAddress(bytes memory initCode, bytes32 salt) internal view returns (address) {
    bytes32 initCodeHash = keccak256(initCode);
    bytes32 rawAddress = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash));

    return address(uint160(uint256(rawAddress)));
  }

  /**
   * @dev Generates the initialization code for the proxy
   */
  function _generateInitCode(
    address implementation,
    bytes32 salt,
    uint256 chainId,
    bytes1 mode,
    address linkedContract,
    uint256 linkedId
  ) internal pure returns (bytes memory) {
    // Get the bytecode constants
    bytes memory header = _ERC1167_HEADER;
    bytes memory footer = _ERC1167_FOOTER;

    // Calculate sizes
    uint256 headerSize = header.length;
    uint256 footerSize = footer.length;

    // Determine total size based on mode
    uint256 totalSize;
    if (mode == 0x00) {
      totalSize = headerSize + 20 + footerSize + 32 + 32 + 12 + 20 + 32; // With ID
    } else if (mode == 0x01) {
      totalSize = headerSize + 20 + footerSize + 32 + 32 + 12 + 20; // Without ID
    } else {
      revert("Invalid mode");
    }

    // Allocate memory for the creation code
    bytes memory initCode = new bytes(totalSize);

    // Copy the header
    uint256 destOffset = 0;
    for (uint256 i = 0; i < headerSize; i++) {
      initCode[destOffset++] = header[i];
    }

    // Copy implementation address
    bytes20 implBytes = bytes20(implementation);
    for (uint256 i = 0; i < 20; i++) {
      initCode[destOffset++] = implBytes[i];
    }

    // Copy the footer
    for (uint256 i = 0; i < footerSize; i++) {
      initCode[destOffset++] = footer[i];
    }

    // Copy salt (bytes32)
    for (uint256 i = 0; i < 32; i++) {
      initCode[destOffset++] = salt[i];
    }

    // Copy chainId (uint256 as bytes32)
    bytes32 chainIdBytes = bytes32(chainId);
    for (uint256 i = 0; i < 32; i++) {
      initCode[destOffset++] = chainIdBytes[i];
    }

    // Copy mode (bytes1)
    initCode[destOffset++] = mode;

    // Zero out reserved bytes (11 bytes)
    for (uint256 i = 0; i < 11; i++) {
      initCode[destOffset++] = 0;
    }

    // Copy linkedContract address (address as bytes20)
    bytes20 linkedBytes = bytes20(linkedContract);
    for (uint256 i = 0; i < 20; i++) {
      initCode[destOffset++] = linkedBytes[i];
    }

    // Copy linkedId if mode is 0x00 (with ID)
    if (mode == 0x00) {
      bytes32 linkedIdBytes = bytes32(linkedId);
      for (uint256 i = 0; i < 32; i++) {
        initCode[destOffset++] = linkedIdBytes[i];
      }
    }

    return initCode;
  }

  /// @dev Returns true if interfaceId is IERC7656Registry's interfaceId
  function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
    return interfaceId == type(IERC7656Registry).interfaceId || interfaceId == type(IERC165).interfaceId;
  }
}
