// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title SIIntentLib - Secure Intent (SI-Core) EVM profile helpers
/// @notice Normalises EIP-712 hashing and signature checks for agent-to-system intents.
interface IERC1271 {
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4);
}

library SIIntentLib {
    // keccak256("IntentHeader(bytes32 dom,address agent,bytes32 kidR,uint64 nonce,uint64 ttl,bytes32 mpHash,bytes32 ctHash)")
    bytes32 internal constant INTENT_HEADER_TYPEHASH =
        0x39b63da0625663ca114633bb099c5f9c4137311a5780a132db1f03e4d11dcc3d;

    struct Header {
        bytes32 dom;        // domain id
        address agent;      // agent address (EOA or ERC-1271 contract)
        bytes32 kidR;       // recipient key id (optional; use 0x0 if not enforced)
        uint64  nonce;      // unique per (agent, kidR)
        uint64  ttl;        // absolute unix expiry in seconds
        bytes32 mpHash;     // keccak256(public metadata bytes)
        bytes32 ctHash;     // keccak256(ciphertext bytes) - treat as payload commitment
    }

    /// @dev EIP-712 struct hash for Header
    function hashHeader(Header memory h) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                INTENT_HEADER_TYPEHASH,
                h.dom,
                h.agent,
                h.kidR,
                h.nonce,
                h.ttl,
                h.mpHash,
                h.ctHash
            )
        );
    }

    /// @dev EIP-712 digest = keccak256("\x19\x01" || domainSeparator || structHash)
    function digest(bytes32 domainSeparator, Header memory h) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, hashHeader(h)));
    }

    /// @dev Validate an ECDSA or ERC-1271 signature for the given digest.
    function isValidSig(address signer, bytes32 dig, bytes calldata sig) internal view returns (bool) {
        if (signer.code.length == 0) {
            // ----- EOA path -----
            if (sig.length != 65) return false;
            bytes32 r; bytes32 s; uint8 v;
            assembly {
                r := calldataload(sig.offset)
                s := calldataload(add(sig.offset, 32))
                v := byte(0, calldataload(add(sig.offset, 64)))
            }
            if (v < 27) v += 27;
            if (v != 27 && v != 28) return false;
            // EIP-2: s must be in lower half order
            if (uint256(s) > 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0) return false;
            address rec = ecrecover(dig, v, r, s);
            return rec != address(0) && rec == signer;
        } else {
            // ----- Contract wallet path (ERC-1271) -----
            try IERC1271(signer).isValidSignature(dig, sig) returns (bytes4 magic) {
                return magic == 0x1626ba7e;
            } catch { return false; }
        }
    }
}
