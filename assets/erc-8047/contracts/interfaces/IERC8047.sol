// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.8.0 <0.9.0;

/**
 * @title ERC-8047 interface
 */

import {IERC5615} from "./IERC5615.sol";

interface IERC8047 is IERC5615 {
    /**
     * @dev Structure representing a token (node) within the Forest DAG.
     */
    struct Token {
        uint256 root;
        uint256 parent;
        uint256 value;
        uint96 depth;
        address owner;
    }

    /**
     * @notice Emitted when a new token is created within a DAG.
     * @param root The root token ID of the DAG to which the new token belongs.
     * @param id The ID of the newly created token.
     * @param from The address that created/minted the token.
     */
    event TokenCreated(uint256 indexed root, uint256 id, address indexed from);

    /**
     * @notice Emitted when a token is spent or partially spent.
     * @param root The root token ID of the DAG to which the new token belongs.
     * @param id The ID of the token being spent.
     * @param value The amount of the token that was spent.
     */
    event TokenSpent(uint256 indexed root, uint256 indexed id, uint256 value);

    /**
     * @notice Emitted when multiple tokens are successfully merged into a single new token.
     * @param ids The array of original token IDs that were consumed in the merge.
     * @param id The ID of the newly created merged token.
     * @param from The address of the token owner who initiated the merge.
     * @param mergeType A flag indicating the rule set used for the merge.
     * `0` represents the default merge (all tokens from the same DAG).
     * values > 0 are reserved for custom implementations (e.g., cross dags merges).
     */
    event TokenMerged(uint256[] ids, uint256 indexed id, address indexed from, uint8 mergeType);

    /**
     * @notice Retrieves the latest (highest) depth of the DAG that a given token belongs to.
     * @param id The ID of the token.
     * @return uint256 The latest DAG depth for the token.
     */
    function latestDAGDepthOf(uint256 id) external view returns (uint256);

    /**
     * @notice Retrieves the depth of a token within its DAG.
     * @param id The ID of the token.
     * @return uint256 The depth of the token in the DAG.
     */
    function depthOf(uint256 id) external view returns (uint256);

    /**
     * @notice Retrieves the owner of a given token.
     * @param id The ID of the token.
     * @return address The address that owns the token.
     */
    function ownerOf(uint256 id) external view returns (address);

    /**
     * @notice Retrieves the parent token ID of a given token.
     * @param id The ID of the token.
     * @return uint256 The ID of the parent token. Retrieves 0 if the token is a root.
     */
    function parentOf(uint256 id) external view returns (uint256);

    /**
     * @notice Retrieves the root token ID of the DAG to which a given token belongs.
     * @param id The ID of the token.
     * @return uint256 The root token ID of the DAG.
     */
    function rootOf(uint256 id) external view returns (uint256);

    /**
     * @notice Retrieves token detail from given token id.
     * @param id The ID of the token.
     * @return Token struct containing the token's detailed properties.
     */
    function token(uint256 id) external view returns (Token memory);

    /**
     * @notice Retrieves the total value of all tokens currently in circulation.
     * Each token contributes its current `value` to the total.
     * @custom:overloading of {IERC5615.totalSupply}
     * @return uint256 The sum of all token values currently in circulation.
     */
    function totalSupply() external view returns (uint256);
}