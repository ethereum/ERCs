// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EIP712} from '@openzeppelin/contracts/utils/cryptography/EIP712.sol';
import {SignatureChecker} from '@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol';

import {IERC8473Policy, TRANSFER_OK} from 'interfaces/IERC8473Policy.sol';
import {IExampleExecutorToken} from 'interfaces/IExampleExecutorToken.sol';

import {ExampleToken} from 'contracts/example/ExampleToken.sol';

/**
 * @title ExampleExecutorToken
 * @notice `ExampleToken` with a settlement channel for signed instructions, as specified in `IExampleExecutorToken`
 * @dev Non-normative and not audited. Shows the EXECUTED path of ERC-8473: the token verifies the holder's instruction
 *      itself, only accounts it granted the role can carry it out, the movement takes the same `_move` as every other
 *      kind, and the pre-flight builds the context the execution builds
 */
contract ExampleExecutorToken is ExampleToken, EIP712, IExampleExecutorToken {
  /// @inheritdoc IExampleExecutorToken
  bytes32 public constant EXECUTOR_ROLE = keccak256('EXECUTOR_ROLE');
  /// @inheritdoc IExampleExecutorToken
  bytes32 public constant INSTRUCTION_TYPEHASH =
    keccak256('Instruction(address from,address to,uint256 amount,bytes32 instructionRef,uint256 deadline)');

  /// @notice Instruction-side reason: the receiver is the zero address
  bytes32 private constant _ZERO_RECEIVER = keccak256('ZERO_RECEIVER');
  /// @notice Instruction-side reason: the deadline has passed
  bytes32 private constant _EXPIRED = keccak256('EXPIRED');
  /// @notice Instruction-side reason: the holder's reference was already used
  bytes32 private constant _USED = keccak256('USED');
  /// @notice Instruction-side reason: the signature is not the holder's for this instruction
  bytes32 private constant _BAD_SIGNATURE = keccak256('BAD_SIGNATURE');

  /// @inheritdoc IExampleExecutorToken
  mapping(address _holder => mapping(bytes32 _instructionRef => bool _used)) public instructionUsed;

  /**
   * @param _name The token name, which is also the EIP-712 domain's name
   * @param _symbol The token symbol
   * @param _admin The DEFAULT_ADMIN_ROLE holder, who installs the first policy and grants the roles
   */
  constructor(
    string memory _name,
    string memory _symbol,
    address _admin
  ) ExampleToken(_name, _symbol, _admin) EIP712(_name, '1') {}

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @inheritdoc IExampleExecutorToken
   * @dev Has no guard of its own, because `_move`'s would then revert. The signature check, the only external call
   *      before `_move`, is a static call and finishes before the policy is asked
   */
  function executeInstruction(
    Instruction calldata _instruction,
    bytes calldata _signature
  ) external onlyRole(EXECUTOR_ROLE) {
    bytes32 _reason = _instructionCheck(_instruction, _signature);
    if (_reason == _ZERO_RECEIVER) revert ERC20InvalidReceiver(address(0));
    if (_reason == _EXPIRED) revert ExampleExecutorToken_InstructionExpired(_instruction.deadline);
    if (_reason == _USED) revert ExampleExecutorToken_InstructionUsed(_instruction.from, _instruction.instructionRef);
    if (_reason == _BAD_SIGNATURE) revert ExampleExecutorToken_InvalidSignature(_instruction.from);

    instructionUsed[_instruction.from][_instruction.instructionRef] = true;
    emit InstructionExecuted(_instruction.from, _instruction.instructionRef, _msgSender());
    _move(
      _instruction.from,
      _instruction.to,
      _instruction.amount,
      IERC8473Policy.TransferKind.EXECUTED,
      _instructionData(_instruction)
    );
  }

  /*///////////////////////////////////////////////////////////////
                            VIEW
  //////////////////////////////////////////////////////////////*/

  /**
   * @inheritdoc IExampleExecutorToken
   * @dev Unlike `canTransfer`, which ERC-7943 leaves blind to the balance, this answer includes it: nothing asks this
   *      view to leave it out
   */
  function canExecute(
    Instruction calldata _instruction,
    bytes calldata _signature,
    address _executor
  ) external view returns (bool _allowed) {
    if (!hasRole(EXECUTOR_ROLE, _executor)) return false;
    if (_instructionCheck(_instruction, _signature) != TRANSFER_OK) return false;
    if (_instruction.amount > balanceOf(_instruction.from)) return false;
    IERC8473Policy.TransferKind _kind = IERC8473Policy.TransferKind.EXECUTED;
    if (_tokenCheck(_instruction.from, _instruction.amount, _kind) != TRANSFER_OK) return false;
    _allowed = _permits(
      abi.encodeCall(
        IERC8473Policy.checkTransfer,
        (_context(
            _instruction.from, _instruction.to, _instruction.amount, _executor, _kind, _instructionData(_instruction)
          ))
      )
    );
  }

  /*///////////////////////////////////////////////////////////////
                            INTERNAL
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice The checks on the instruction itself, shared by `executeInstruction` and `canExecute`
   * @dev A zero `from` fails the signature check, so an instruction can never be a mint. A zero `to` is refused here
   *      because `_move` does not have the check `_transfer` would have made, and the movement would burn
   * @param _instruction The instruction
   * @param _signature The holder's signature
   * @return _reason TRANSFER_OK, `_ZERO_RECEIVER`, `_EXPIRED`, `_USED` or `_BAD_SIGNATURE`
   */
  function _instructionCheck(
    Instruction calldata _instruction,
    bytes calldata _signature
  ) internal view returns (bytes32 _reason) {
    if (_instruction.to == address(0)) return _ZERO_RECEIVER;
    if (block.timestamp > _instruction.deadline) return _EXPIRED;
    if (instructionUsed[_instruction.from][_instruction.instructionRef]) return _USED;
    bytes32 _digest = _hashTypedDataV4(
      keccak256(
        abi.encode(
          INSTRUCTION_TYPEHASH,
          _instruction.from,
          _instruction.to,
          _instruction.amount,
          _instruction.instructionRef,
          _instruction.deadline
        )
      )
    );
    if (!SignatureChecker.isValidSignatureNowCalldata(_instruction.from, _digest, _signature)) return _BAD_SIGNATURE;
    _reason = TRANSFER_OK;
  }

  /**
   * @notice The context's `data` for an instruction, shared by the execution and the pre-flight
   * @param _instruction The instruction
   * @return _data `abi.encode(bytes32 instructionRef, uint256 deadline)`
   */
  function _instructionData(
    Instruction calldata _instruction
  ) internal pure returns (bytes memory _data) {
    _data = abi.encode(_instruction.instructionRef, _instruction.deadline);
  }
}
