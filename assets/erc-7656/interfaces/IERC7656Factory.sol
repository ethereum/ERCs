// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ERC7656
 * @dev Modified registry based on ERC6551Registry
 * https://github.com/erc6551/reference/blob/main/src/ERC6551Registry.sol
 *
 * The ERC165 interfaceId is 0xc6bdc908
 * @notice Manages the creation of token linked services
 */
interface IERC7656Factory {
  /**
   * @notice The registry MUST emit the Created event upon successful contract creation.
   * @param contractAddress The address of the created contract
   * @param implementation The address of the implementation contract
   * @param chainId The chain linkedId of the chain where the contract is being created
   * @param linkedContract The address of the token or contract
   * @param linkedId The optional ID (e.g., linkedId) of the linked contract, or 0 if not applicable
   * @param salt The salt is a bytes32 so save 32 bytes in the bytecode. It is converted in the function to a bytes32 to use it for the create2 operation
   * @param mode If true, the linkedId is not used, saving 32 bytes in the bytecode
   */
  event Created(
    address contractAddress,
    address indexed implementation,
    bytes32 salt,
    uint256 chainId,
    bytes12 mode,
    address indexed linkedContract,
    uint256 indexed linkedId
  );

  /**
   * The registry MUST revert with CreationFailed error if the create2 operation fails.
   */
  error CreationFailed();

  /**
   * @notice Creates a token or contract-linked service.
   * If the service has already been created, returns the service address without calling create2.
   * @param implementation The address of the implementation contract
   * @param chainId The chain linkedId of the chain where the service is being created
   * @param linkedContract The address of the token or contract
   * @param linkedId The optional ID (e.g., linkedId) of the linked contract. If mode is true, this value is ignored
   * @param salt The salt is a bytes32 so save 32 bytes in the bytecode. It is converted in the function to a bytes32 to use it for the create2 operation
   * @param mode If true, the linkedId is not used, saving 32 bytes in the bytecode
   * @return service The address of the token or contract-linked service
   */
  function create(
    address implementation,
    bytes32 salt,
    uint256 chainId,
    bytes12 mode,
    address linkedContract,
    uint256 linkedId
  ) external returns (address);

  /**
   * @notice Returns the computed token or contract-linked service address.
   * @param implementation The address of the implementation contract
   * @param salt The salt to use for the create2 operation
   * @param chainId The chain linkedId of the chain where the service is being created
   * @param linkedContract The address of the token or contract
   * @param linkedId The optional ID (e.g., linkedId) of the linked contract. If mode is true, this value is ignored
   * @param mode If true, the linkedId is not used, saving 32 bytes in the bytecode
   * @return service The address of the token or contract-linked service
   */
  function compute(
    address implementation,
    bytes32 salt,
    uint256 chainId,
    bytes12 mode,
    address linkedContract,
    uint256 linkedId
  ) external view returns (address service);
}
