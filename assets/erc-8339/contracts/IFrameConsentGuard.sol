// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title IFrameConsentGuard: receiver-attested transfers inside one EIP-8141 frame transaction.
/// @notice The receiver signs an EIP-712 `TransferConsent` first. The sender's frame
///         transaction then carries it in a guard frame flagged ATOMIC_BATCH, immediately
///         followed by the SENDER frame that moves the asset. The guard reverts unless that
///         next frame is exactly the consented transfer, so a mismatch skips the transfer
///         and nothing moves. Each consent pays out at most once.
interface IFrameConsentGuard {
    enum AssetKind { Native, ERC20, ERC721, ERC1155 }

    /// @dev EIP-712 type:
    ///      TransferConsent(address sender,address receiver,uint8 kind,address token,
    ///                      uint256 tokenId,uint256 amount,bytes32 challenge,uint64 deadline)
    struct Consent {
        address   sender;    // the frame tx sender that may use this consent
        address   receiver;  // named and signed by the receiver; never typed by the sender
        AssetKind kind;
        address   token;     // MUST be address(0) for Native
        uint256   tokenId;   // ERC-721 / ERC-1155 id; MUST be 0 otherwise
        uint256   amount;    // wei / token units; MUST be 1 for ERC-721
        bytes32   challenge; // 32 random bytes from the sender, fresh per request
        uint64    deadline;  // unix seconds; unusable after this
    }

    event ConsentUsed(bytes32 indexed digest, address indexed sender, address indexed receiver);

    error NotAtomic();        // guard frame lacks ATOMIC_BATCH_FLAG: it would protect nothing
    error BadTransferFrame(); // next frame is missing, not SENDER mode, or not the consented transfer
    error WrongSender();      // frame tx sender != consent.sender
    error ConsentExpired();
    error AlreadyUsed();
    error BadConsent();       // receiver signature invalid (EOA or ERC-1271)
    error BadAsset();         // zero/self receiver, or asset fields inconsistent with kind

    /// @notice Verify the consent against the next frame, then mark it used. MUST be called
    ///         from a frame flagged ATOMIC_BATCH whose next frame is the SENDER transfer.
    function check(Consent calldata c, bytes calldata receiverSig) external;

    /// @notice EIP-712 digest the receiver signs; also the key of the used stamp.
    function consentDigest(Consent calldata c) external view returns (bytes32);

    /// @notice True once a consent with this digest has paid out.
    function isUsed(bytes32 digest) external view returns (bool);
}
