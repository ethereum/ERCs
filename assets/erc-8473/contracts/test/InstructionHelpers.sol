// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IExampleExecutorToken} from 'interfaces/IExampleExecutorToken.sol';

import {Helpers} from 'contracts/test/Helpers.sol';

/**
 * @notice Builds and signs instructions for the executor tests
 * @dev The digest comes from the spelled-out EIP-712 strings, never from the contract, so a wrong type hash in the
 *      contract fails
 */
abstract contract InstructionHelpers is Helpers {
  string internal constant _TOKEN_NAME = 'Example';
  bytes32 internal constant _REF = keccak256('REF-1');

  /**
   * @notice The digest a wallet signs for an instruction on a token at this chain
   * @param _token The token
   * @param _instruction The instruction
   * @return _hash The digest
   */
  function _digest(
    address _token,
    IExampleExecutorToken.Instruction memory _instruction
  ) internal view returns (bytes32 _hash) {
    bytes32 _domain = keccak256(
      abi.encode(
        keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
        keccak256(bytes(_TOKEN_NAME)),
        keccak256('1'),
        block.chainid,
        _token
      )
    );
    bytes32 _struct = keccak256(
      abi.encode(
        keccak256(
          'Instruction(address from,address to,uint256 amount,bytes32 instructionRef,uint256 deadline,address executor)'
        ),
        _instruction.from,
        _instruction.to,
        _instruction.amount,
        _instruction.instructionRef,
        _instruction.deadline,
        _instruction.executor
      )
    );
    _hash = keccak256(abi.encodePacked(hex'1901', _domain, _struct));
  }

  /**
   * @notice Signs an instruction with an account's key
   * @param _key The signer's private key
   * @param _token The token
   * @param _instruction The instruction
   * @return _signature The signature
   */
  function _sign(
    uint256 _key,
    address _token,
    IExampleExecutorToken.Instruction memory _instruction
  ) internal view returns (bytes memory _signature) {
    (uint8 _v, bytes32 _r, bytes32 _s) = vm.sign(_key, _digest(_token, _instruction));
    _signature = abi.encodePacked(_r, _s, _v);
  }
}
