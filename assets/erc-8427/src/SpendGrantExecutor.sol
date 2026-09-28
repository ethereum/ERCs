// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {ISpendGrantRegistry, NATIVE, SpendGrant, SpendGrantError, Reason} from "./SpendGrantTypes.sol";

contract SpendGrantExecutor {
    error NativeRequiresAccountAdapter();
    error TransferFailed();

    ISpendGrantRegistry internal immutable REGISTRY;

    constructor(ISpendGrantRegistry registry_) {
        REGISTRY = registry_;
        if (registry_.executor() != address(this)) revert SpendGrantError(Reason.UNAUTHORIZED_EXECUTOR);
    }

    function registry() external view returns (ISpendGrantRegistry) {
        return REGISTRY;
    }

    function spend(
        SpendGrant calldata grant,
        bytes calldata grantSignature,
        address asset,
        uint256 amount,
        address recipient
    ) external {
        // Moving native currency from the principal needs an account adapter, which the spec
        // leaves out; the reference does not spend the delegate's own value.
        if (asset == NATIVE) revert NativeRequiresAccountAdapter();

        // Record the debit first so a recipient callback cannot double-spend; movement
        // still shares the transaction and reverts with consume if either step fails.
        // msg.sender is the caller the EVM authenticated, so it is the authorizer this executor passes.
        // The recipient passes through unchanged, so the payee is the one the delegate named; in
        // recipientMode 0 the registry rejects any other address with WRONG_RECIPIENT.
        REGISTRY.consume(grant, grantSignature, msg.sender, asset, amount, recipient);

        _safeTransferFrom(asset, grant.principal, recipient, amount);
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, amount));
        if (!ok) revert TransferFailed();
        if (data.length != 0) {
            if (data.length != 32 || !abi.decode(data, (bool))) revert TransferFailed();
        }
    }
}
