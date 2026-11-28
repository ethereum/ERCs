// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;
import {IInstitutionAccount, AccountState} from "../IInstitutionAccount.sol";

/// @notice Test callers derive available capacity without changing the standard getter.
function readAccount(IInstitutionAccount ledger, address account, address institution)
    view
    returns (AccountState memory state, uint96 available)
{
    state = ledger.accountState(account, institution);
    uint256 total = uint256(state.limit) + state.credit;
    require(total >= state.debit);
    uint256 value = total - state.debit;
    require(value <= type(uint96).max);
    // forge-lint: disable-next-line(unsafe-typecast)
    available = uint96(value);
}
