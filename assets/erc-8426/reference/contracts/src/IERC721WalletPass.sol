// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

/// @title ERC-721 Wallet Pass Extension
/// @dev The ERC-165 identifier for this interface is 0xef5f1e71.
interface IERC721WalletPass {
    /// @notice Emitted when the wallet pass content bound to a token has
    ///  changed. Pass distributors SHOULD regenerate the pass and, where the
    ///  platform supports it, push the update to installed passes.
    event PassUpdate(uint256 indexed tokenId);

    /// @notice Emitted when the wallet pass content for a consecutive range
    ///  of tokens has changed.
    event BatchPassUpdate(uint256 fromTokenId, uint256 toTokenId);

    /// @notice Get the pass endpoint URI for a token.
    /// @dev Throws if `tokenId` is not a valid token. The returned URI MUST
    ///  resolve to a pass manifest as defined in this standard.
    /// @param tokenId The token whose pass endpoint is requested.
    /// @return The pass endpoint URI.
    function passURI(uint256 tokenId) external view returns (string memory);
}
