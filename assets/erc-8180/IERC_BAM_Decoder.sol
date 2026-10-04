// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title IERC_BAM_Decoder
/// @notice Interface for decoding message payloads in Blob Authenticated Messaging
/// @dev Decoders are untrusted, user-deployed contracts. A buggy or malicious decoder cannot
///      cause impersonation — it can only produce wrong messages whose hashes fail verification
///      against the trusted signature registry. Decoders MUST NOT perform signature verification.
interface IERC_BAM_Decoder {
    /// @notice A decoded message.
    struct Message {
        address sender;
        uint64 nonce;
        bytes contents;
    }

    /// @notice Decodes all messages and extracts signature data from the payload.
    /// @param payload Raw message batch bytes.
    /// @return messages      Array of decoded messages (sender + nonce + contents).
    /// @return signatureData Opaque signature bytes (e.g., aggregated BLS signature,
    ///                       concatenated ECDSA signatures). Format depends on the
    ///                       signature scheme; length is derivable from
    ///                       signatureRegistry.signatureSize() and message count.
    function decode(bytes calldata payload)
        external
        view
        returns (Message[] memory messages, bytes memory signatureData);
}
