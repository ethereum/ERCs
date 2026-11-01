// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAgentMandate} from "../interfaces/IAgentMandate.sol";
import {RamsGated} from "../RamsGated.sol";
import {uRWA20} from "./uRWA20.sol";

/// @title RamsGatedURWA20
/// @notice An ERC-7943 asset gated by RAMS. Each function an agent performs for a holder carries its own
///         action label. mint, burn, forcedTransfer and setFrozenTokens stay ungated: the token's own roles
///         authorize them.
contract RamsGatedURWA20 is uRWA20, RamsGated {
    constructor(string memory name, string memory symbol, address initialAdmin, IAgentMandate rams_)
        uRWA20(name, symbol, initialAdmin)
        RamsGated(rams_)
    {}

    /// @notice Transfers `value` from `from`, requiring a mandate when the caller is not `from`.
    function transferFrom(address from, address to, uint256 value)
        public
        override
        gatedByMandate(IERC20.transferFrom.selector, from, value)
        returns (bool)
    {
        return super.transferFrom(from, to, value);
    }

    /// @notice Sets `holder`'s allowance for `spender`, requiring a mandate when the caller is not `holder`.
    /// @dev Moves no tokens, so it shows cumulativeUsed tracking recorded authority rather than transfers.
    function approveFor(address holder, address spender, uint256 value)
        public
        gatedByMandate(this.approveFor.selector, holder, value)
        returns (bool)
    {
        _approve(holder, spender, value);
        return true;
    }

    /// @notice Mints `amount` to `holder` on a subscription the agent placed for it.
    /// @dev Needs both authorities: MINTER_ROLE from the issuer and a mandate from the holder.
    function mintFor(address holder, uint256 amount)
        public
        onlyRole(MINTER_ROLE)
        gatedByMandate(this.mintFor.selector, holder, amount)
    {
        _mint(holder, amount);
    }
}
