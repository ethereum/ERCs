// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.0 <0.9.0;

import "../abstracts/ERC8047.sol";
import "../policies/FreezeAddress.sol";
import "../policies/FreezePartialTokens.sol";
import "../policies/TPEn.sol";

contract MockERC8047 is ERC8047, FreezeAddress, FreezePartialTokens, AbstractTokenPolicyEnforcement {
    constructor(string memory uri_) ERC8047(uri_) {}

    // -----------------------------------------------------------------------
    // Advanced Forensic Freezing Rules (Examples)
    // -----------------------------------------------------------------------
    // The following patterns demonstrate how sophisticated enforcement logic
    // can be layered on top of the base ERC8047 DAG structure:
    // 1. checkFrozenTokenAreInRange(root, id)
    //    Prevents transfers if the token's level falls within a specific range [x, y].
    // 2. checkFrozenTokenLevelAfter(root, id)
    //    Prevents transfers for any token that exists deeper than level {x}.
    // 3. checkFrozenTokenLevelBefore(root, id)
    //    Prevents transfers for any token that exists above level {x}.
    // Note: Ideally, these checks should be implemented with toggle switches
    // (active/inactive states) to provide operational flexibility for compliance teams.

    function setURI(string memory uri) public {
        _setURI(uri);
    }

    function mint(address account, uint256 value) public {
        _mint(account, value, "");
    }

    function burn(address account, uint256 id, uint256 value) public {
        _burn(account, id, value);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 value,
        bytes memory data
    )
        public
        override
        checkFrozenAddress(from, to)
        checkFrozenBalance(from, balanceOf(from, id))
    {
        // revert if parent token frozen.
        (bool frozen,) = isTokenFrozen(rootOf(id),id,depthOf(id));
        if (frozen) {
            revert TokenFrozen();
        }
        super.safeTransferFrom(from, to, id, value, data);
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    )
        public
        override
        checkFrozenAddress(from, to)
    {
        uint256 frozenBalance = frozenBalanceOf(from);
        uint256 spend;
        for (uint256 i = 0; i < ids.length; i++) {
            (bool frozen, ) = isTokenFrozen(rootOf(ids[i]), ids[i], depthOf(ids[i]));
            spend += balanceOf(from, ids[i]);
            if (frozen) {
                revert TokenFrozen();
            }
        }
        if (frozenBalance >= spend) {
            revert FreezePartialTokens.BalanceFrozen(spend,frozenBalance);
        }
        
        super.safeBatchTransferFrom(from, to, ids, values, data);
    }
}
