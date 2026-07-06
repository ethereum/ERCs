// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  UriFilterLib — Prefix-based filtering over a stored URI list
/// @notice Attach via 'using UriFilterLib for string[]'.
library UriFilterLib {
    /// @dev Copies the URIs matching at least one of 'allowedPrefixes' into a memory
    ///      array. An empty prefix list disables filtering. A rejected URI is never fully
    ///      loaded from storage and never reaches the return data: the cost of discarding
    ///      it is bounded by the prefix lengths, not by the URI's own length.
    function filter(string[] storage uris, string[] calldata allowedPrefixes)
        internal view returns (string[] memory filtered)
    {
        if (allowedPrefixes.length == 0) {
            return uris; // unfiltered: implicit storage-to-memory copy
        }

        uint256 matchingUriCount = _countMatching(uris, allowedPrefixes);
        filtered = new string[](matchingUriCount);
        _collectMatching(uris, allowedPrefixes, filtered);
    }

    /// @dev Counts how many URIs in storage match at least one allowed prefix.
    function _countMatching(string[] storage uris, string[] calldata allowedPrefixes)
        private view returns (uint256 matchingUriCount)
    {
        uint256 uriCount = uris.length;
        for (uint256 uriIndex = 0; uriIndex < uriCount; uriIndex++) {
            if (_matchesAnyPrefix(uris[uriIndex], allowedPrefixes)) {
                ++matchingUriCount;
            }
        }
    }

    /// @dev Copies every URI in storage that matches at least one allowed prefix into 'filtered'.
    function _collectMatching(
        string[] storage uris,
        string[] calldata allowedPrefixes,
        string[] memory filtered
    ) private view {
        uint256 uriCount = uris.length;
        uint256 filteredIndex;
        for (uint256 uriIndex = 0; uriIndex < uriCount; uriIndex++) {
            if (_matchesAnyPrefix(uris[uriIndex], allowedPrefixes)) {
                filtered[filteredIndex++] = uris[uriIndex];
            }
        }
    }

    /// @dev Whether 'uri' starts with at least one of 'allowedPrefixes'.
    function _matchesAnyPrefix(string storage uri, string[] calldata allowedPrefixes)
        private view returns (bool)
    {
        uint256 prefixCount = allowedPrefixes.length;
        for (uint256 prefixIndex = 0; prefixIndex < prefixCount; prefixIndex++) {
            if (_hasPrefix(uri, allowedPrefixes[prefixIndex])) {
                return true;
            }
        }
        return false;
    }

    /// @dev Whether 'uri' starts with 'prefix', comparing byte by byte.
    ///      Note: In production, optimize this by reading the first 32 bytes from storage
    ///      in one go (handling both short and long string packing) to avoid O(N) sloads
    ///      for short prefixes like "ipfs:".
    function _hasPrefix(string storage uri, string calldata prefix) private view returns (bool) {
        bytes storage uriBytes = bytes(uri);
        bytes calldata prefixBytes = bytes(prefix);
        uint256 prefixLength = prefixBytes.length;
        if (prefixLength > uriBytes.length) {
            return false;
        }

        for (uint256 byteIndex = 0; byteIndex < prefixLength; byteIndex++) {
            if (uriBytes[byteIndex] != prefixBytes[byteIndex]) {
                return false;
            }
        }
        return true;
    }
}
