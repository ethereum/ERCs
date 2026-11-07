// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {IERC7943Fungible} from 'interfaces/IERC7943Fungible.sol';

/**
 * @notice Makes a forced transfer and then an ordinary transfer of its own tokens, within one external call
 * @dev One call keeps both movements in one transaction under every test profile, so transient state set by the first
 *      is still there for the second
 */
contract ForcedThenTransfer {
  /**
   * @param _token The token; this contract needs its enforcement role and a balance
   * @param _from The account the forced transfer takes from
   * @param _to The account the forced transfer delivers to
   * @param _forcedAmount The forced amount
   * @param _recipient The receiver of the ordinary transfer
   * @param _amount The ordinary amount, sent from this contract's own balance
   */
  function run(
    address _token,
    address _from,
    address _to,
    uint256 _forcedAmount,
    address _recipient,
    uint256 _amount
  ) external {
    IERC7943Fungible(_token).forcedTransfer(_from, _to, _forcedAmount);
    // solhint-disable-next-line custom-errors
    require(IERC20(_token).transfer(_recipient, _amount), 'transfer returned false');
  }
}
