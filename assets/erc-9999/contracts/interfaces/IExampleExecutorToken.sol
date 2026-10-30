// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IExampleToken} from 'interfaces/IExampleToken.sol';

/**
 * @title IExampleExecutorToken
 * @notice `IExampleToken` with a settlement channel: an account with EXECUTOR_ROLE carries out a holder's signed EIP-712
 *         instruction as an EXECUTED movement
 * @dev Non-normative and not audited. The context's `data` for an EXECUTED movement is
 *      `abi.encode(bytes32 instructionRef, uint256 deadline)`, and the holder's signature covers both. The other kinds
 *      pass empty `data`. An instruction cannot be cancelled: its deadline is the holder's limit
 */
interface IExampleExecutorToken is IExampleToken {
  /*///////////////////////////////////////////////////////////////
                            STRUCTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice A holder's signed instruction to move tokens
   * @param from The holder, who must have signed
   * @param to The receiver
   * @param amount The amount
   * @param instructionRef The holder's reference. It can be used once per holder, in any order
   * @param deadline The last timestamp at which the instruction can be carried out
   */
  struct Instruction {
    address from;
    address to;
    uint256 amount;
    bytes32 instructionRef;
    uint256 deadline;
  }

  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Emitted when an instruction is carried out, before its transfer event
   * @param _holder The holder who signed
   * @param _instructionRef The instruction's reference
   * @param _executor The account that carried it out
   */
  event InstructionExecuted(address indexed _holder, bytes32 indexed _instructionRef, address indexed _executor);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Thrown when an instruction's deadline has passed
   * @param _deadline The deadline
   */
  error ExampleExecutorToken_InstructionExpired(uint256 _deadline);

  /**
   * @notice Thrown when the holder's reference was already used
   * @param _holder The holder
   * @param _instructionRef The reference
   */
  error ExampleExecutorToken_InstructionUsed(address _holder, bytes32 _instructionRef);

  /**
   * @notice Thrown when the signature is not the holder's for this instruction
   * @param _holder The holder
   */
  error ExampleExecutorToken_InvalidSignature(address _holder);

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Carries out a holder's signed instruction as an EXECUTED movement
   * @dev Only EXECUTOR_ROLE, so the holder and the payee cannot submit it unless they hold the role. A zero `to` reverts
   *      with `ERC20InvalidReceiver`. A rejected movement reverts the record of the reference too, so the instruction
   *      stays usable until its deadline
   * @param _instruction The instruction
   * @param _signature The holder's signature: ECDSA for an account without code, ERC-1271 for one with code
   */
  function executeInstruction(
    Instruction calldata _instruction,
    bytes calldata _signature
  ) external;

  /*///////////////////////////////////////////////////////////////
                            VIEW
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice The pre-flight for `executeInstruction`
   * @dev True if and only if that call by `_executor` would succeed at this state, apart from a failure in
   *      `wantsAfterTransfer` or `afterTransfer`, which it does not call. Does not depend on the caller, and does not
   *      revert when the policy call fails
   * @param _instruction The instruction
   * @param _signature The holder's signature
   * @param _executor The account that would carry it out, which is the context's `operator`
   * @return _allowed True if the call would succeed
   */
  function canExecute(
    Instruction calldata _instruction,
    bytes calldata _signature,
    address _executor
  ) external view returns (bool _allowed);

  /**
   * @notice Whether a holder's reference was used
   * @param _holder The holder
   * @param _instructionRef The reference
   * @return _used True if an instruction with this reference was carried out
   */
  function instructionUsed(
    address _holder,
    bytes32 _instructionRef
  ) external view returns (bool _used);

  /**
   * @notice The role allowed to carry out instructions
   * @return _role keccak256('EXECUTOR_ROLE')
   */
  // getter of an UPPER_SNAKE constant
  // solhint-disable-next-line style-guide-casing
  function EXECUTOR_ROLE() external view returns (bytes32 _role);

  /**
   * @notice The EIP-712 type hash of an instruction
   * @return _typehash keccak256('Instruction(address from,address to,uint256 amount,bytes32 instructionRef,uint256 deadline)')
   */
  // getter of an UPPER_SNAKE constant
  // solhint-disable-next-line style-guide-casing
  function INSTRUCTION_TYPEHASH() external view returns (bytes32 _typehash);
}
