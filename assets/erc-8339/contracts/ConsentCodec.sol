// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.24;

import { IFrameConsentGuard } from "./IFrameConsentGuard.sol";

/// @title ConsentCodec: canonical bytes for the two off-chain consent messages.
/// @notice The ERC fixes payloads, not transports. These bytes travel over whatever private,
///         censorship-resistant messenger the two people already share (Waku, XMTP, Nostr,
///         Status, ...). Nothing here is secret: a response is useless except for its one send.
///
///         Layout: [0] version (0x01) | [1] type (0x01 request, 0x02 response) | [2..] body
///         body = abi.encode(field1, field2, ...) over the struct's fields in order (flat, no
///         outer tuple offset). For the all-static request this equals abi.encode(struct).
///
///         ConsentRequest  (sender -> receiver) has NO receiver field. The receiver names their
///         own address in the signed ConsentResponse, so a typed address never enters the flow.
library ConsentCodec {
    bytes1 internal constant VERSION = 0x01;
    bytes1 internal constant TYPE_REQUEST = 0x01;
    bytes1 internal constant TYPE_RESPONSE = 0x02;

    struct ConsentRequest {
        uint256 chainId;
        address guard;
        address sender;
        IFrameConsentGuard.AssetKind kind;
        address token;
        uint256 tokenId;
        uint256 amount;
        bytes32 challenge;
        uint64 deadline;
    }

    struct ConsentResponse {
        address receiver;
        bytes sig; // EIP-712 TransferConsent signature by `receiver`
    }

    error BadVersion();
    error BadType();

    function encodeRequest(ConsentRequest memory r) internal pure returns (bytes memory) {
        return abi.encodePacked(VERSION, TYPE_REQUEST, abi.encode(r));
    }

    function decodeRequest(bytes calldata b) internal pure returns (ConsentRequest memory) {
        return abi.decode(_body(b, TYPE_REQUEST), (ConsentRequest));
    }

    function encodeResponse(ConsentResponse memory r) internal pure returns (bytes memory) {
        // Flat fields (not the struct) so the bytes are exactly abi.encode(receiver, sig).
        return abi.encodePacked(VERSION, TYPE_RESPONSE, abi.encode(r.receiver, r.sig));
    }

    function decodeResponse(bytes calldata b) internal pure returns (ConsentResponse memory) {
        (address receiver, bytes memory sig) = abi.decode(_body(b, TYPE_RESPONSE), (address, bytes));
        return ConsentResponse({ receiver: receiver, sig: sig });
    }

    /// @notice The Consent the receiver signs and the guard checks: request + named receiver.
    function toConsent(ConsentRequest memory r, address receiver)
        internal
        pure
        returns (IFrameConsentGuard.Consent memory)
    {
        return IFrameConsentGuard.Consent({
            sender: r.sender,
            receiver: receiver,
            kind: r.kind,
            token: r.token,
            tokenId: r.tokenId,
            amount: r.amount,
            challenge: r.challenge,
            deadline: r.deadline
        });
    }

    function _body(bytes calldata b, bytes1 expectedType) private pure returns (bytes calldata) {
        if (b.length < 2 || b[0] != VERSION) revert BadVersion();
        if (b[1] != expectedType) revert BadType();
        return b[2:];
    }
}
