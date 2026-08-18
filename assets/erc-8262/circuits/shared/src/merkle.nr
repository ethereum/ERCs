/// Merkle tree utilities for ERC-8262 circuits.
///
/// Internal nodes are domain-separated from leaves via an explicit tag. This prevents
/// the classic second-preimage attack where an attacker crafts a leaf whose hash
/// equals an internal node, allowing them to "skip" levels in the proof. The tag
/// also protects against trailing-zero collisions in standard Pedersen hash (see
/// shared/src/hash.nr LIMITATION note).
///
/// Tree publishers MUST use the same `leaf_hash_*` helpers below when building their
/// trees off-chain. Using `hash2` directly produces a different, incompatible root.

use std::hash::pedersen_hash;

/// Domain tag for internal merkle node hashes.
pub global DOMAIN_INTERNAL: Field = 0x4d4b4c5f494e54; // ASCII "MKL_INT"

/// Domain tag for set-style leaves: H(tag, element, set_id).
/// Used by membership / non_membership / sanctions trees.
pub global DOMAIN_LEAF_SET: Field = 0x4d4b4c5f4c5354; // ASCII "MKL_LST"

/// Domain tag for value-style leaves: H(tag, value).
/// Used when the leaf is a single hash (e.g. credential_hash in attestation).
pub global DOMAIN_LEAF_VALUE: Field = 0x4d4b4c5f56414c; // ASCII "MKL_VAL"

/// Domain tag for subject-bound leaves: H(tag, submitter, set_id, subject_salt).
/// Used by membership / non_membership trees that bind to a specific submitter
/// (audit finding H-3). The `subject_salt` is a per-user private value chosen by
/// the tree publisher to prevent tree-enumeration when subjects are public addresses;
/// pass 0 when tree privacy is not required (e.g. published sanctions lists).
pub global DOMAIN_LEAF_SUBJECT: Field = 0x4d4b4c5f535542; // ASCII "MKL_SUB"

/// Domain tag for the provider-signed-signals payload hash:
/// H(tag, provider_set_hash, signals[..], weights[..], timestamp, submitter).
/// Used by the COMPLIANCE_SIGNED / RISK_SCORE_SIGNED circuits (audit finding I-1).
/// The hash is the message that the provider's authorized signer signs over via
/// secp256k1 ECDSA; the circuit verifies the signature in-circuit so the signals
/// the prover discloses privately are anchored to a real provider attestation.
pub global DOMAIN_SIGNED_SIGNALS: Field = 0x5349475f53494753; // ASCII "SIG_SIGS"

/// Hash two siblings under the internal-node domain.
pub fn internal_hash(left: Field, right: Field) -> Field {
    pedersen_hash([DOMAIN_INTERNAL, left, right])
}

/// Compute a set-style leaf hash binding `element` to a `set_id`.
pub fn leaf_hash_set(element: Field, set_id: Field) -> Field {
    pedersen_hash([DOMAIN_LEAF_SET, element, set_id])
}

/// Compute a value-style leaf hash for a single committed value.
pub fn leaf_hash_value(value: Field) -> Field {
    pedersen_hash([DOMAIN_LEAF_VALUE, value])
}

/// Compute a subject-bound leaf hash for membership / non_membership trees.
/// `subject_salt` is per-user; pass 0 when the tree contents are public
/// (e.g. a sanctions list).
pub fn leaf_hash_subject(submitter: Field, set_id: Field, subject_salt: Field) -> Field {
    pedersen_hash([DOMAIN_LEAF_SUBJECT, submitter, set_id, subject_salt])
}

/// Compute the Merkle root from a leaf, index, and sibling path using Pedersen.
///
/// The leaf's position in the tree is encoded as `index` in little-endian bits.
/// At each level `i`, bit `i` of `index` determines the node's position:
///   - bit = 0: current node is the LEFT child, sibling is right
///   - bit = 1: current node is the RIGHT child, sibling is left
///
/// Internal nodes are hashed with `internal_hash` (domain-tagged); leaves are hashed
/// by the caller using one of the `leaf_hash_*` helpers above.
pub fn compute_merkle_root<let DEPTH: u32>(
    leaf: Field,
    index: Field,
    hash_path: [Field; DEPTH],
) -> Field {
    let index_bits: [bool; DEPTH] = index.to_le_bits();
    let mut current = leaf;
    for i in 0..DEPTH {
        let sibling = hash_path[i];
        let (left, right) = if !index_bits[i] {
            (current, sibling)
        } else {
            (sibling, current)
        };
        current = internal_hash(left, right);
    }
    current
}
