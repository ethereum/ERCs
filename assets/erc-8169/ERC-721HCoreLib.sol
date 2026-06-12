// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC721HStorageLib} from "./ERC721HStorageLib.sol";

/**
 * @title ERC721HCoreLib — High-Level Query Operations for ERC-721H
 * @author Emiliano Solazzi — 2026
 * @notice Composes ERC721HStorageLib primitives into domain-specific queries:
 *         provenance reports, early-adopter detection, transfer counting.
 * @dev All functions are `internal` and inlined at compile time — zero runtime gas overhead.
 *      Operates on the same HistoryStorage struct as ERC721HStorageLib.
 * @custom:version 2.0.0
 */
library ERC721HCoreLib {
    /// @notice Assembles a complete provenance report for `tokenId` in one call.
    /// @param self         The HistoryStorage struct in storage
    /// @param tokenId      The token to report on
    /// @param currentOwner The current Layer 3 owner (passed in by caller)
    function buildProvenanceReport(
        ERC721HStorageLib.HistoryStorage storage self,
        uint256 tokenId,
        address currentOwner
    ) internal view returns (
        address creator,
        uint256 creationBlock,
        address currentOwnerAddr,
        uint256 totalTransfers,
        address[] memory allOwners,
        uint256[] memory transferTimestamps
    ) {
        return (
            self.originalCreator[tokenId],
            self.mintBlock[tokenId],
            currentOwner,
            self.ownershipHistory[tokenId].length - 1,
            self.ownershipHistory[tokenId],
            self.ownershipTimestamps[tokenId]
        );
    }

    /// @notice Returns the number of transfers for `tokenId` (excludes mint).
    function getTransferCount(
        ERC721HStorageLib.HistoryStorage storage self,
        uint256 tokenId
    ) internal view returns (uint256) {
        return self.ownershipHistory[tokenId].length - 1;
    }

    /// @notice Returns true if `account` minted any token at or before `blockThreshold`.
    /// @dev WARNING: O(n) where n = number of tokens created by `account`.
    ///      Safe for off-chain / view calls. Avoid inside state-changing TX for prolific minters.
    function isEarlyAdopter(
        ERC721HStorageLib.HistoryStorage storage self,
        address account,
        uint256 blockThreshold
    ) internal view returns (bool) {
        uint256[] memory tokens = self.createdTokens[account];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (self.mintBlock[tokens[i]] <= blockThreshold) {
                return true;
            }
        }
        return false;
    }
}
