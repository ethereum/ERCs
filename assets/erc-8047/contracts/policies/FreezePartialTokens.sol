// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title FreezePartialTokens
 * @dev Abstract contract for managing frozen balances, not implementing access control.
 * @notice This contract allows freezing and unfreezing of account balances. It does not include access control mechanisms.
 * inspired from: ERC-3643 T-REX
 * @author Sirawit Techavanitch (sirawit_tec@live4.utcc.ac.th)
 */

abstract contract FreezePartialTokens {
    /** @custom:storage */
    enum OPERATION_TYPES {
        DECREMENT,
        INCREMENT
    }

    mapping(address => uint256) private _frozenTokens;

    /**  @custom:errors */
    error BalanceOverflow();
    error BalanceFrozen(uint256 balance, uint256 frozenBalance);

    /**  @custom:events */
    /**
     * @dev See {IERC3643.TokensFrozen}.
     * @custom:reference {https://github.com/ERC-3643/ERC-3643/blob/main/contracts/token/IToken.sol}
     */
    event TokensFrozen(address indexed userAddress, uint256 value);

    /**
     * @dev See {IERC3643.TokensUnFrozen}.
     * @custom:reference {https://github.com/ERC-3643/ERC-3643/blob/main/contracts/token/IToken.sol}
     */
    event TokensUnFrozen(address indexed userAddress, uint256 value);

    /** @custom:modifier */
    /**
     * @notice Modifier to check if an account's balance can be spent, considering the frozen balance.
     * @param account The address of the account.
     * @param balance The total balance of the account.
     */
    modifier checkFrozenBalance(address account, uint256 balance) {
        uint256 frozenTokens = _frozenTokens[account];
        if (frozenTokens >= balance) {
            revert BalanceFrozen(balance, frozenTokens);
        }
        _;
    }

    /** @custom:function-internal */
    /** @dev */
    function _updateFreezePartialTokens(address userAddress, uint256 value, OPERATION_TYPES op) internal {
        if (op == OPERATION_TYPES.INCREMENT) {
            _frozenTokens[userAddress] += value;

            emit TokensFrozen(userAddress, value);
        } else {
            if (_frozenTokens[userAddress] < value) {
                //@TODO reasonable custom error.
                revert();
            }
            unchecked {
                _frozenTokens[userAddress] -= value;
            }

            emit TokensUnFrozen(userAddress, value);
        }
    }

    /** @custom:function-public */
    /**
     * @dev See {IERC3643.freezePartialTokens}
     * @custom:reference
     * {https://eips.ethereum.org/EIPS/eip-3643}.
     * {https://docs.erc3643.org/erc-3643/smart-contracts-library/permissioned-tokens/tokens-interface}.
     */
    function freezePartialTokens(address userAddress, uint256 value) public virtual {
        _updateFreezePartialTokens(userAddress, value, OPERATION_TYPES.INCREMENT);
    }

    /**
     * @dev See {IERC3643.unfreezePartialTokens}
     * @custom:reference
     * {https://eips.ethereum.org/EIPS/eip-3643}.
     * {https://docs.erc3643.org/erc-3643/smart-contracts-library/permissioned-tokens/tokens-interface}.
     */
    function unfreezePartialTokens(address userAddress, uint256 value) public virtual {
        _updateFreezePartialTokens(userAddress, value, OPERATION_TYPES.DECREMENT);
    }

    /**
     * @notice Gets the frozen balance of an account.
     * @param account The address of the account.
     * @return The frozen balance of the account.
     */
    function frozenBalanceOf(address account) public view returns (uint256) {
        return _frozenTokens[account];
    }
}
