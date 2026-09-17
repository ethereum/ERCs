// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {ISpendGrantRegistry, SpendGrant, SpendGrantError, Reason} from "./SpendGrantTypes.sol";

contract SpendGrantExecutor {
    error NotDelegate();
    error UnexpectedMsgValue();
    error TransferFailed();

    ISpendGrantRegistry public immutable registry;

    constructor(ISpendGrantRegistry registry_) {
        registry = registry_;
        if (registry_.executor() != address(this)) revert SpendGrantError(Reason.UNAUTHORIZED_EXECUTOR);
    }

    function spend(
        SpendGrant calldata grant,
        bytes calldata grantSignature,
        address asset,
        uint256 amount,
        address recipient
    ) external payable {
        if (msg.sender != grant.delegate) revert NotDelegate();

        address to = grant.recipientMode == 0 ? grant.recipient : recipient;

        // Record the debit first so a recipient callback cannot double-spend; movement
        // still shares the transaction and reverts with consume if either step fails.
        registry.consume(grant, grantSignature, asset, amount, to);

        if (asset == address(0)) {
            // Reference limitation: native value is supplied by the delegate
            // (`msg.value`), not pulled from the principal. Debiting the
            // principal's native balance needs an account adapter.
            if (msg.value != amount) revert UnexpectedMsgValue();
            (bool ok,) = payable(to).call{value: amount}("");
            if (!ok) revert TransferFailed();
        } else {
            if (msg.value != 0) revert UnexpectedMsgValue();
            _safeTransferFrom(asset, grant.principal, to, amount);
        }
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, amount));
        if (!ok) revert TransferFailed();
        if (data.length != 0) {
            if (data.length != 32 || !abi.decode(data, (bool))) revert TransferFailed();
        }
    }
}
