// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title Forest Model Library
 * @notice Library containing data structures and functions for managing token within a forest-like structure.
 * @author Sirawit Techavanitch (sirawit_tec@live4.utcc.ac.th)
 */

import {IERC8047} from "../interfaces/IERC8047.sol";

library Forest {
    /**
     * @dev Structure representing a DAG.
     */
    struct DAG {
        mapping(address => uint256) nonces;
        mapping(uint256 => uint96) hierarchy;
        mapping(uint256 => IERC8047.Token) tokens;
    }

    /**
     * @dev See {IERC8047.TokenCreated}
     * @notice Expect 'duplicate definition - TokenCreated(uint256,uint256,address)' when test.
     */
    event TokenCreated(uint256 indexed root, uint256 id, address indexed from);

    /**
     * @dev See {IERC8047.TokenSpent}
     * @notice Expect 'duplicate definition - TokenSpent(uint256,uint256,uint256)' when test.
     */
    event TokenSpent(uint256 indexed root, uint256 indexed id, uint256 value);

    /**
     * @dev See {IERC8047.TokenMerged}
     * @notice Expect 'duplicate definition - TokenMerged(uint256,uint256,address,uint8)' when test.
     */
    event TokenMerged(uint256[] ids, uint256 indexed id, address indexed from, uint8 mergeType);

    /**
     * @notice Error thrown when a transaction is unauthorized.
     */
    error TokenUnauthorized();

    /**
     * @notice Error thrown when trying to create a transaction with zero value.
     */
    error TokenZeroValue();

    /**
     * @notice Error thrown when a token is assigned or transferred to an invalid receiver address (e.g., the zero address).
     * @param receiver The invalid address that was provided.
     */
    error TokenInvalidReceiver(address receiver);

    /**
     * @notice Error thrown when attempting to merge fewer than two tokens.
     */
    error TokenMergeLength();

    /**
     * @notice Error thrown when attempting to merge tokens that belong to different roots (DAGs), violating the default single-DAG merge rule.
     */
    error TokenRootMismatch();

    /**
     * @notice Error thrown when the spending value exceeds the transaction value.
     * @param value The value of the transaction.
     * @param spend The amount being spent.
     */
    error TokenInsufficient(uint256 value, uint256 spend);

    /** @custom:function-private */
    /**
     * @notice Internal function to create a new token in the DAG.
     * @dev If `newToken.root` is zero, the new token is treated as a root token and its `root` is set to its own `id`.
     * The `TokenCreated` event emits with `root` equal to zero when minting a new root token,
     * enabling off-chain indexers to identify and enumerate all DAG origins by filtering on `root` equal to zero.
     * @param self The DAG storage reference.
     * @param newToken The Token struct containing the properties of the token to be created.
     * @param spender The address initiating the token creation.
     * @return newId The ID of the newly created token.
     */
    function _createToken(
        DAG storage self,
        IERC8047.Token memory newToken,
        address spender
    ) private returns (uint256 newId) {
        newId = calcTokenHash(spender, self.nonces[spender]);
        uint256 rootId = (newToken.root == 0) ? newId : newToken.root;
        
        // FIX: Changed "newTokenz" typo to "newToken.depth"
        self.tokens[newId] = IERC8047.Token(rootId, newToken.parent, newToken.value, newToken.depth, newToken.owner);
        unchecked {
            self.nonces[spender]++;
        }

        emit TokenCreated(newToken.root, newId, spender);
    }

    /** @custom:function-internal */
    /**
     * @notice Checks whether a token exists in the DAG.
     * @dev A token is considered to exist if its `root` is not zero. Checking `value` MUST NOT be used
     * as an existence check, as a burned token retains its `id` in the DAG with a `value` of zero.
     * @param self The DAG storage reference.
     * @param id The token ID to check.
     * @return True if the token exists, false otherwise.
     */
    function contains(DAG storage self, uint256 id) internal view returns (bool) {
        return self.tokens[id].root != uint256(0);
    }

    /**
     * @notice Calculates a deterministic token hash using the account and nonce.
     * @param account The address for which to calculate the token hash.
     * @param nonce A unique counter for the account to ensure uniqueness.
     * @return A uint256 hash representing the token ID.
     */
    function calcTokenHash(address account, uint256 nonce) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.chainid, account, nonce)));
    }

    /**
     * @notice Retrieves a token from the DAG by its ID.
     * @param self The DAG storage reference.
     * @param id The token ID to retrieve.
     * @return The Token struct corresponding to the given ID.
     */
    function getToken(DAG storage self, uint256 id) internal view returns (IERC8047.Token memory) {
        return self.tokens[id];
    }

    /**
     * @notice Retrieves the depth of a token within its DAG hierarchy.
     * @param self The DAG storage reference.
     * @param id The token ID.
     * @return The hierarchy depth of the token.
     */
    function getTokenDepth(DAG storage self, uint256 id) internal view returns (uint256) {
        return self.tokens[id].depth;
    }

    /**
     * @notice Retrieves the parent token ID of a given token.
     * @param self The DAG storage reference.
     * @param id The token ID.
     * @return The ID of the parent token. Returns zero if the token is a root.
     */
    function getTokenParent(DAG storage self, uint256 id) internal view returns (uint256) {
        return self.tokens[id].parent;
    }

    /**
     * @notice Retrieves the root token ID of a given token.
     * @param self The DAG storage reference.
     * @param id The token ID.
     * @return The root token ID.
     */
    function getTokenRoot(DAG storage self, uint256 id) internal view returns (uint256) {
        return self.tokens[id].root;
    }

    /**
     * @notice Retrieves the current value of a token.
     * @param self The DAG storage reference.
     * @param id The token ID.
     * @return The token's value.
     */
    function getTokenValue(DAG storage self, uint256 id) internal view returns (uint256) {
        return self.tokens[id].value;
    }

    /**
     * @notice Retrieves the number of tokens issued to a given account.
     * @param self The DAG storage reference.
     * @param account The address to query.
     * @return The count of tokens associated with the account.
     */
    function getTokenCount(DAG storage self, address account) internal view returns (uint256) {
        return self.nonces[account];
    }

    /**
     * @notice Retrieves the hierarchy information for a given token.
     * @param self The DAG storage reference.
     * @param id The token ID.
     * @return The hierarchy depth or identifier of the token in the DAG.
     */
    function getTokenHierarchy(DAG storage self, uint256 id) internal view returns (uint256) {
        IERC8047.Token storage ptr = self.tokens[id];
        if (ptr.parent != 0) {
            return self.hierarchy[ptr.root];
        }
        return self.hierarchy[id];
    }

    /**
     * @notice Retrieves the owner of a token.
     * @param self The DAG storage reference.
     * @param id The token ID.
     * @return The address of the token owner.
     */
    function getTokenOwner(DAG storage self, uint256 id) internal view returns (address) {
        return self.tokens[id].owner;
    }

    /**
     * @notice Creates a new token in the DAG.
     * @param self The DAG storage reference.
     * @param newToken The Token struct containing token properties.
     * @param spender The address initiating the creation of the token.
     * @return The newly created token's ID.
     * @dev Reverts if the token value is zero or the owner is the zero address.
     */
    function createToken(DAG storage self, IERC8047.Token memory newToken, address spender) internal returns (uint256) {
        if (newToken.value == 0) revert TokenZeroValue();
        if (newToken.owner == address(0)) revert TokenInvalidReceiver(address(0));
        return _createToken(self, newToken, spender);
    }

    /**
     * @notice Spends a specified value from an existing token, creating a new child token for the recipient.
     * @param self The DAG storage reference containing all tokens and hierarchy.
     * @param id The ID of the token to spend from.
     * @param spender The address initiating the spend operation. Must be the owner of the token.
     * @param to The recipient address for the new child token. If zero address, no new token is minted.
     * @param value The amount of the token to spend. Must be greater than zero and less than or equal to the current token's value.
     * @return newId The ID of the newly created child token. Returns zero if no new token is minted (i.e., `to` is zero address).
     */
    function spendToken(
        DAG storage self,
        uint256 id,
        address spender,
        address to,
        uint256 value
    ) internal returns (uint256 newId) {
        IERC8047.Token storage ptr = self.tokens[id];
        if (spender != ptr.owner) revert TokenUnauthorized();
        uint256 currentValue = ptr.value;
        if (value == 0 || value > currentValue) revert TokenInsufficient(currentValue, value);
        uint256 currentRoot = ptr.root;
        unchecked {
            ptr.value = currentValue - value;
            uint96 newDepth = (ptr.depth + 1);
            if (to != address(0)) {
                newId = _createToken(self, IERC8047.Token(currentRoot, id, value, newDepth, to), spender);
                if (newDepth > self.hierarchy[currentRoot]) {
                    self.hierarchy[currentRoot] = newDepth;
                }
            }
        }

        emit TokenSpent(currentRoot, id, value);
    }

    /**
     * @notice Merges multiple tokens within the same DAG into a single new token.
     * @dev Enforces the default merge rule: all `ids` MUST share the same `root`.
     * The resulting token's depth will be `k + 1`, where `k` is the highest depth among the merged tokens.
     * @param self The DAG storage reference.
     * @param ids An array of token IDs to be merged. `ids[0]` establishes the expected `root` for all subsequent tokens.
     * @param spender The address initiating the merge. Must be the owner of all tokens being merged.
     * @return newId The ID of the newly created merged token.
     */
    function defaultMerge(DAG storage self, uint256[] memory ids, address spender) internal returns (uint256 newId) {
        if (ids.length < 2) revert TokenMergeLength();
        // process the primary token index zero outside the loop.
        uint256 mainId = ids[0];
        IERC8047.Token storage mainPtr = self.tokens[mainId];

        if (mainPtr.owner != spender) revert TokenUnauthorized();
        if (mainPtr.value == 0) revert TokenInsufficient(0, 1);

        uint256 expectedRoot = mainPtr.root;
        uint256 totalValue = mainPtr.value;
        uint96 maxDepth = mainPtr.depth;

        // spend the primary token.
        mainPtr.value = 0;

        // loop through the remaining tokens starting at index 1.
        for (uint256 i = 1; i < ids.length; i++) {
            uint256 currentId = ids[i];
            IERC8047.Token storage ptr = self.tokens[currentId];

            // prevent unauthorized, empty, or duplicated token ids.
            if (ptr.owner != spender) revert TokenUnauthorized();
            if (ptr.value == 0) revert TokenInsufficient(0, 1);

            // default merge rule enforce all tokens belong to the same root.
            if (ptr.root != expectedRoot) revert TokenRootMismatch();

            // accumulate value and find the highest depth (k).
            totalValue += ptr.value;
            if (ptr.depth > maxDepth) {
                mainId = ids[i];
                maxDepth = ptr.depth;
            }

            // spend the token entirely to clear its state.
            ptr.value = 0;
        }

        unchecked {
            // new depth is k + 1.
            uint96 newDepth = maxDepth + 1;

            if (newDepth > self.hierarchy[expectedRoot]) {
                self.hierarchy[expectedRoot] = newDepth;
            }

            // create the new merged token.
            newId = _createToken(
                self,
                IERC8047.Token({
                    root: expectedRoot,
                    parent: mainId,
                    value: totalValue,
                    depth: newDepth,
                    owner: spender
                }),
                spender
            );

            emit TokenMerged(ids, newId, spender, 0);
        }
    }
}