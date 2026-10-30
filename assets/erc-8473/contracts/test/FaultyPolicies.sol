// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ERC165} from '@openzeppelin/contracts/utils/introspection/ERC165.sol';
import {IERC165} from '@openzeppelin/contracts/utils/introspection/IERC165.sol';

import {IERC8473} from 'interfaces/IERC8473.sol';
import {IERC8473Policy, TRANSFER_OK} from 'interfaces/IERC8473Policy.sol';
import {IExampleExecutorToken} from 'interfaces/IExampleExecutorToken.sol';
import {IExampleToken} from 'interfaces/IExampleToken.sol';

/// @notice Permits everything; the base of the faulty policies below
abstract contract PermissivePolicy is ERC165, IERC8473Policy {
  function afterTransfer(
    TransferContext calldata
  ) external virtual {}

  function onInstall(
    address,
    address,
    bytes calldata
  ) external virtual {}

  function checkReceive(
    address,
    address
  ) external view virtual returns (bytes32 _reason) {
    _reason = TRANSFER_OK;
  }

  function checkSend(
    address,
    address
  ) external view virtual returns (bytes32 _reason) {
    _reason = TRANSFER_OK;
  }

  function checkTransfer(
    TransferContext calldata
  ) external view virtual returns (bytes32 _reason) {
    _reason = TRANSFER_OK;
  }

  function wantsAfterTransfer() external view virtual returns (bool _wantsAfter) {
    _wantsAfter = false;
  }

  function supportsInterface(
    bytes4 _interfaceId
  ) public view override(ERC165, IERC165) returns (bool _supported) {
    _supported = _interfaceId == type(IERC8473Policy).interfaceId || super.supportsInterface(_interfaceId);
  }
}

/// @notice Its author handled TRANSFER and forgot every other kind: the unassigned return value is zero
contract ForgetfulPolicy is PermissivePolicy {
  function checkTransfer(
    TransferContext calldata _context
  ) external pure override returns (bytes32 _reason) {
    if (_context.kind == TransferKind.TRANSFER) _reason = TRANSFER_OK;
  }
}

/// @notice Reverts on every movement check
contract RevertingPolicy is PermissivePolicy {
  error RevertingPolicy_Failure();

  function checkTransfer(
    TransferContext calldata
  ) external pure override returns (bytes32) {
    revert RevertingPolicy_Failure();
  }
}

/// @notice Runs out of gas in every check, however much it is given
contract GasBurningPolicy is PermissivePolicy {
  function checkReceive(
    address,
    address
  ) external pure override returns (bytes32 _reason) {
    _reason = _burnGas();
  }

  function checkSend(
    address,
    address
  ) external pure override returns (bytes32 _reason) {
    _reason = _burnGas();
  }

  function checkTransfer(
    TransferContext calldata
  ) external pure override returns (bytes32 _reason) {
    _reason = _burnGas();
  }

  function _burnGas() private pure returns (bytes32 _reason) {
    while (_reason == 0) {}
  }
}

/// @notice Answers the movement check with 31 bytes: too short to decode as a bytes32
contract ShortReturnPolicy is PermissivePolicy {
  function checkTransfer(
    TransferContext calldata
  ) external pure override returns (bytes32) {
    assembly {
      mstore(0x00, 0x2a5b6d0c00000000000000000000000000000000000000000000000000000000)
      return(0x00, 31)
    }
  }
}

/// @notice Answers `wantsAfterTransfer` with the word 2, which is not a valid bool
contract BadBoolPolicy is PermissivePolicy {
  function wantsAfterTransfer() external pure override returns (bool) {
    assembly {
      mstore(0x00, 2)
      return(0x00, 0x20)
    }
  }
}

/// @notice Answers `wantsAfterTransfer` with 31 bytes
contract ShortBoolPolicy is PermissivePolicy {
  function wantsAfterTransfer() external pure override returns (bool) {
    assembly {
      mstore(0x00, 0)
      return(0x00, 31)
    }
  }
}

/// @notice Tries to start a second movement from inside `afterTransfer`
contract ReentrantPolicy is PermissivePolicy {
  function wantsAfterTransfer() external pure override returns (bool _wantsAfter) {
    _wantsAfter = true;
  }

  function afterTransfer(
    TransferContext calldata _context
  ) external override {
    // solhint-disable-next-line custom-errors
    require(IERC20(_context.token).transfer(address(0xBEEF), 1), 'unreachable');
  }
}

/// @notice Reverts when installed
contract RevertingInstallPolicy is PermissivePolicy {
  error RevertingInstallPolicy_Failure();

  function onInstall(
    address,
    address,
    bytes calldata
  ) external pure override {
    revert RevertingInstallPolicy_Failure();
  }
}

/// @notice When installed, tries to move tokens or, given a next policy and the admin role, to install it
contract ReentrantInstallPolicy is PermissivePolicy {
  address public immutable NEXT;

  constructor(
    address _next
  ) {
    NEXT = _next;
  }

  function onInstall(
    address _token,
    address,
    bytes calldata
  ) external override {
    if (NEXT == address(0)) {
      // solhint-disable-next-line custom-errors
      require(IERC20(_token).transfer(address(0xBEEF), 0), 'unreachable');
    } else {
      IExampleToken(_token).setPolicy(NEXT, '');
    }
  }
}

/// @notice Once given an instruction, tries to carry it out from inside `onInstall` and `afterTransfer`; needs the role
contract ReentrantExecutorPolicy is PermissivePolicy {
  IExampleExecutorToken.Instruction internal _instruction;
  bytes internal _signature;

  function arm(
    IExampleExecutorToken.Instruction calldata _newInstruction,
    bytes calldata _newSignature
  ) external {
    _instruction = _newInstruction;
    _signature = _newSignature;
  }

  function wantsAfterTransfer() external pure override returns (bool _wantsAfter) {
    _wantsAfter = true;
  }

  function afterTransfer(
    TransferContext calldata _context
  ) external override {
    _reenter(_context.token);
  }

  function onInstall(
    address _token,
    address,
    bytes calldata
  ) external override {
    _reenter(_token);
  }

  function _reenter(
    address _token
  ) private {
    if (_signature.length > 0) IExampleExecutorToken(_token).executeInstruction(_instruction, _signature);
  }
}

/// @notice Records what it sees inside `onInstall`
contract InstallRecorderPolicy is PermissivePolicy {
  address public seenPolicy;
  address public seenPrevious;
  bytes public seenData;

  function onInstall(
    address _token,
    address _previousPolicy,
    bytes calldata _data
  ) external override {
    seenPolicy = IERC8473(_token).policy();
    seenPrevious = _previousPolicy;
    seenData = _data;
  }
}

/// @notice Answers every call with its own calldata
contract EchoContract {
  fallback() external {
    assembly {
      calldatacopy(0x00, 0x00, calldatasize())
      return(0x00, calldatasize())
    }
  }
}

/// @notice The policy ABI with the kind as a raw uint8, to send a value outside the enumeration
interface IRawPolicy {
  struct RawContext {
    address token;
    address from;
    address to;
    uint256 tokenId;
    uint256 amount;
    address operator;
    uint8 kind;
    bytes data;
  }

  function checkTransfer(
    RawContext calldata _context
  ) external view returns (bytes32 _reason);
}
