// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "./SIIntentLib.sol";

/// @title SIIntentGate - Minimal on-chain verifier for SI-Core envelopes
/// @notice Enforces TTL, replay-protection, optional recipient binding, and signature validity.
contract SIIntentGate {
    using SIIntentLib for SIIntentLib.Header;

    // EIP-712 Domain
    // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
    bytes32 public constant DOMAIN_TYPEHASH =
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public immutable KIDR_ALLOWED; // 0x0 if not enforced

    // Replay protection: (agent => nonce => used)
    mapping(address => mapping(uint64 => bool)) public usedNonce;

    event IntentAccepted(address indexed agent, uint64 nonce, bytes32 ctHash);

    constructor(string memory name, string memory version, bytes32 kidRAllowed) {
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            DOMAIN_TYPEHASH,
            keccak256(bytes(name)),
            keccak256(bytes(version)),
            block.chainid,
            address(this)
        ));
        KIDR_ALLOWED = kidRAllowed;
    }

    struct SubmitParams {
        SIIntentLib.Header header;
        bytes signature; // EIP-712 signature by header.agent
    }

    function acceptIntent(SubmitParams calldata p) external {
        // 1) TTL
        require(block.timestamp <= p.header.ttl, "SI: expired");

        // 2) Optional recipient binding
        if (KIDR_ALLOWED != bytes32(0)) {
            require(p.header.kidR == KIDR_ALLOWED, "SI: wrong recipient");
        }

        // 3) Replay protection
        require(!usedNonce[p.header.agent][p.header.nonce], "SI: replay");
        usedNonce[p.header.agent][p.header.nonce] = true;

        // 4) Signature check
        bytes32 dig = SIIntentLib.digest(DOMAIN_SEPARATOR, p.header);
        require(SIIntentLib.isValidSig(p.header.agent, dig, p.signature), "SI: bad sig");

        emit IntentAccepted(p.header.agent, p.header.nonce, p.header.ctHash);
    }
}
