// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./EXPCurves.sol";

/**
 * @title Valocracy
 * @dev This contract implements a voting power system that decays over time
 * using EXP curves. The balanceOf function resembles a token balance in
 * ERC20Votes for Governance usage, but it decays over time based on the user's
 * voting power and the curvature factor.
 */
contract Valocracy is EXPCurves {
  struct User {
    uint256 votingPower;
    uint32 lastUpdate;
  }

  bool public ascending = false;
  int8 public curvature;
  uint32 public vacationPeriod;

  mapping(address => User) public votingPower;

  function balanceOf(
    address account
  ) public view returns (int256 _adjustedPower) {
    uint32 _lastUpdate = votingPower[account].lastUpdate;
    uint256 _votingPower = votingPower[account].votingPower;

    int256 decay = expcurve(
      uint32(block.timestamp),
      _lastUpdate,
      _lastUpdate + vacationPeriod,
      curvature,
      ascending
    );

    _adjustedPower = (int(_votingPower) * decay) / 100 / 1e18;
  }

  function contribute(address _account, uint256 _votingPower) public {
    votingPower[_account].votingPower = _votingPower;
    votingPower[_account].lastUpdate = uint32(block.timestamp);
  }

  function setCurvature(int8 _curvature) public {
    curvature = _curvature;
  }

  function setVacationPeriod(uint32 _vacationPeriod) public {
    vacationPeriod = _vacationPeriod;
  }
}
