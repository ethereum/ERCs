// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {ISpendGrantRegistry, NATIVE, SpendGrant, SpendGrantError, Reason} from "./SpendGrantTypes.sol";

/// @notice Minimal conformant executor: the delegate calls `spend` itself, and the executor asks the
/// ERC-20 to move exactly `amount` from the principal in the same transaction as `consume`.
/// @dev Two hooks are virtual so an extension can authenticate the delegate another way (see
/// SpendGrantRedemptionExecutor) or add a check around the movement, without changing `spend`.
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

        // Authenticate first. Whatever this resolves to is what consume compares with grant.delegate.
        address authorizer = _authorizer(grant, asset, amount, recipient);

        // Record the debit first so a recipient callback cannot double-spend; movement
        // still shares the transaction and reverts with consume if either step fails.
        // The recipient passes through unchanged, so the payee is the one the delegate named; in
        // recipientMode 0 the registry rejects any other address with WRONG_RECIPIENT.
        REGISTRY.consume(grant, grantSignature, authorizer, asset, amount, recipient);

        // The same `amount` consume recorded is what the token is asked to move. The caps bound this
        // request, as the principal's allowance does. What the token's own code does with it (a
        // transfer fee, a rebase, share rounding) is the asset's behavior; this executor neither
        // detects it nor records anything but the request.
        _move(asset, grant.principal, recipient, amount);
    }

    /// @dev Who authorized this spend. The base executor is called by the delegate itself, so the EVM
    /// has authenticated msg.sender. An override MUST return only an address it authenticated for
    /// this exact spend, never grant.delegate by assumption.
    function _authorizer(SpendGrant calldata, address, uint256, address) internal virtual returns (address) {
        return msg.sender;
    }

    /// @dev Asks `token` to move `amount` raw units from `from` to `to`; a revert, a false return, or a
    /// malformed return is a failed movement. An override MAY check the principal's balance change and
    /// revert, but MUST still request exactly `amount`.
    function _move(address token, address from, address to, uint256 amount) internal virtual {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, amount));
        if (!ok) revert TransferFailed();
        if (data.length != 0) {
            if (data.length != 32 || !abi.decode(data, (bool))) revert TransferFailed();
        }
    }
}
