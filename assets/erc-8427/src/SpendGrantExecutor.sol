// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {ISpendGrantRegistry, NATIVE, SpendGrantError, Reason} from "./SpendGrantTypes.sol";

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

    /// @notice Spends `amount` of `asset` from the principal of the registered grant `grantId` to `recipient`.
    function spend(bytes32 grantId, address asset, uint256 amount, address recipient) external {
        // Moving native currency from the principal needs an account adapter, which the spec
        // leaves out; the reference does not spend the delegate's own value.
        if (asset == NATIVE) revert NativeRequiresAccountAdapter();

        // The parties come from the registry under the id, never from the caller. A zero principal means the
        // registry does not know the id: there is no one to authenticate against and no one to move from.
        (address principal, address delegate) = REGISTRY.parties(grantId);
        if (principal == address(0)) revert SpendGrantError(Reason.NONEXISTENT);

        // Authenticate before consume. Whatever this resolves to is what consume compares with the grant's
        // delegate.
        address authorizer = _authorizer(grantId, principal, delegate, asset, amount, recipient);

        // Record the debit first so a recipient callback cannot double-spend; movement
        // still shares the transaction and reverts with consume if either step fails.
        // The recipient passes through unchanged, so the payee is the one the delegate named; in
        // recipientMode 0 the registry rejects any other address with WRONG_RECIPIENT.
        REGISTRY.consume(grantId, authorizer, asset, amount, recipient);

        // The same `amount` consume recorded is what the token is asked to move. The caps bound this
        // request, as the principal's allowance does. What the token's own code does with it (a
        // transfer fee, a rebase, share rounding) is the asset's behavior; this executor neither
        // detects it nor records anything but the request.
        _move(asset, principal, recipient, amount);
    }

    /// @dev Who authorized this spend. The arguments are the grant id, the grant's principal and delegate as
    /// the registry names them, and the spend. The base executor is called by the delegate itself, so the EVM
    /// has authenticated msg.sender. An override MUST return only an address it authenticated for this exact
    /// spend, never the delegate by assumption.
    function _authorizer(bytes32, address, address, address, uint256, address) internal virtual returns (address) {
        return msg.sender;
    }

    /// @dev Asks `token` to move `amount` raw units from `from` to `to`; a revert, a false return, a
    /// malformed return, or no return from an address without code is a failed movement. Only the first
    /// word of the return data is copied, so a token that returns a huge payload cannot push this call
    /// out of gas and swallow the reason. An override MAY check the principal's balance change and
    /// revert, but MUST still request exactly `amount`.
    function _move(address token, address from, address to, uint256 amount) internal virtual {
        bytes memory data = abi.encodeWithSelector(0x23b872dd, from, to, amount);
        bool ok;
        uint256 size;
        bytes32 word;
        assembly ("memory-safe") {
            ok := call(gas(), token, 0, add(data, 32), mload(data), 0, 32)
            size := returndatasize()
            word := mload(0)
        }
        if (!ok) revert TransferFailed();
        if (size == 0) {
            // Tokens that return nothing are fine; an address with no code is not a token.
            if (token.code.length == 0) revert TransferFailed();
        } else if (size != 32 || word != bytes32(uint256(1))) {
            revert TransferFailed();
        }
    }
}
