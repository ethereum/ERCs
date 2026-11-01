// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// @title EIP712CredentialRoot -- EIP-712 typed-data hashing for credential-root
///         publish authorizations (audit C-1 closure).
/// @notice The provider's signing key (held in HSM/KMS, separate from the
///         publisher EOA) signs a `CredentialRootPublication` struct authorizing
///         the publisher EOA to broadcast a specific (root, cid) for a given
///         provider within a time window. The Oracle verifies the signature
///         on-chain via `ecrecover` at `publishCredentialRoot` time. A
///         compromised publisher EOA alone can no longer mint credential
///         roots, since they do not hold the signing key.
///
///         The signed window (`notBefore`, `notAfter`) is independent of the
///         on-chain `CREDENTIAL_ROOT_TTL`. The window bounds replay of the
///         signature itself; the TTL bounds the lifetime of an already-published
///         root for ATTESTATION proof acceptance.
library EIP712CredentialRoot {
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /// @notice EIP-712 type hash for the credential-root publish authorization.
    /// @dev The `cidHash` field is `keccak256(bytes(cid))` so the publisher
    ///      cannot bait-and-switch tree contents under a signed root.
    bytes32 internal constant CREDENTIAL_ROOT_TYPEHASH = keccak256(
        "CredentialRootPublication(uint256 providerId,bytes32 root,bytes32 cidHash,uint64 notBefore,uint64 notAfter)"
    );

    /// @notice Compute the EIP-712 domain separator for the oracle.
    /// @dev Same domain as `EIP712Attestation` (name="ERC8262Oracle", version="1").
    ///      Uses `block.chainid` at call time so the separator stays correct
    ///      after a chain fork.
    function buildDomainSeparator(address verifyingContract) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH, keccak256("ERC8262Oracle"), keccak256("1"), block.chainid, verifyingContract
            )
        );
    }

    /// @notice Hash a `CredentialRootPublication` struct per EIP-712.
    function hashPublication(uint256 providerId, bytes32 root, bytes32 cidHash, uint64 notBefore, uint64 notAfter)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(CREDENTIAL_ROOT_TYPEHASH, providerId, root, cidHash, notBefore, notAfter));
    }

    /// @notice Compute the full EIP-712 digest for a credential-root publication.
    /// @dev Pass to `ecrecover` along with the `(v, r, s)` from the signature.
    function toTypedDataHash(
        bytes32 domainSeparator,
        uint256 providerId,
        bytes32 root,
        bytes32 cidHash,
        uint64 notBefore,
        uint64 notAfter
    ) internal pure returns (bytes32) {
        bytes32 structHash = hashPublication(providerId, root, cidHash, notBefore, notAfter);
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}
