// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title FreezeAddress
 * @notice This contract allows freezing and unfreezing of addresses. It does not include access control mechanisms.
 * inspired from: ERC-3643 T-REX
 * @author Sirawit Techavanitch (sirawit_tec@live4.utcc.ac.th)
 */

abstract contract FreezeAddress {
    /** @custom:storage */
    mapping(address => bool) private _frozen;

    /** @custom:errors */
    error SenderAddressFrozen(address sender);
    error ReceiverAddressFrozen(address receiver);

    /** @custom:events */
    /**
     * @dev See {IERC3643.AddressFrozen}
     * @custom:reference {https://github.com/ERC-3643/ERC-3643/blob/main/contracts/token/IToken.sol}.
     */
    event AddressFrozen(address indexed userAddress, bool indexed isFrozen, address indexed owner);

    /** @custom:modifier */
    modifier checkFrozenAddress(address from, address to) {
        if (isFrozen(from)) {
            revert SenderAddressFrozen(from);
        }
        if (isFrozen(to)) {
            revert ReceiverAddressFrozen(to);
        }
        _;
    }

    /** @custom:function-internal */
    /**
     * @notice Internal function to update the frozen status of an address.
     * @param account The address to update.
     * @param auth The new frozen status. True to freeze the address, false to unfreeze.
     */
    function _updateFreezeAddress(address account, bool auth, address initiator) internal {
        _frozen[account] = auth;

        emit AddressFrozen(account, auth, initiator);
    }

    /**
     * @dev See {IERC3643.setAddressFrozen}
     * @custom:reference
     * {https://eips.ethereum.org/EIPS/eip-3643}.
     * {https://docs.erc3643.org/erc-3643/smart-contracts-library/permissioned-tokens/tokens-interface}.
     */
    function setAddressFrozen(address userAddress, bool freeze) public virtual {
        _updateFreezeAddress(userAddress, freeze, msg.sender);
    }

    /**
     * @dev See {IERC3643.isFrozen}
     * @custom:reference
     * {https://eips.ethereum.org/EIPS/eip-3643}.
     * {https://docs.erc3643.org/erc-3643/smart-contracts-library/permissioned-tokens/tokens-interface}.
     */
    function isFrozen(address userAddress) public view returns (bool) {
        return _frozen[userAddress];
    }
}
