/// Pedersen hash wrappers for ERC-8262 circuits
///
/// All circuits use Pedersen hash (efficient in ZK circuits, publicly available in Noir stdlib).
/// Field elements correspond to BN254 scalar field (~254 bits).
///
/// Note: Poseidon2 is preferred for ZK efficiency but its high-level API is private
/// in Noir 1.0.0-beta. When Noir stabilizes, swap pedersen_hash for Poseidon2::hash.
///
/// SECURITY NOTE on Pedersen hash:
/// Pedersen commitments are additively homomorphic: H(a) + H(b) = H(a+b) for the
/// underlying elliptic curve points. We rely on Pedersen preimage resistance only;
/// observations:
///   1. We never expose raw hash outputs to user-controlled arithmetic.
///   2. All hashes are used as opaque commitments compared via equality (e.g., to a
///      registered merkle_root or to a recomputed value over the same inputs).
///   3. No circuit composes hashes in a way that allows the prover to exploit linearity
///      (e.g., no circuit checks H(x) + H(y) == H(z)).
///
/// LIMITATION (no implicit domain separation by arity):
/// Standard Pedersen hash without an explicit length tag satisfies
///   hashN([a, b, ..., 0, 0]) == hashM([a, b, ...]) when M < N
/// because the trailing-zero generators contribute the identity. Different arities
/// therefore do NOT automatically separate domains. We currently rely on the fact
/// that contexts using each arity are structurally distinct (no preimage of a hashN
/// can be confused with a preimage of a hashM in our codebase) plus Pedersen preimage
/// resistance, but this is fragile. A future refactor should add an explicit domain
/// tag, e.g. `pedersen_hash([DOMAIN_TAG, ...inputs])`, especially for merkle leaves
/// vs internal nodes (audit finding L-2).
///
/// When Poseidon2 becomes available, migrate to it for stronger random-oracle properties.

use std::hash::pedersen_hash;

/// Hash two field elements
pub fn hash2(a: Field, b: Field) -> Field {
    pedersen_hash([a, b])
}

/// Hash three field elements
pub fn hash3(a: Field, b: Field, c: Field) -> Field {
    pedersen_hash([a, b, c])
}

/// Hash four field elements
pub fn hash4(a: Field, b: Field, c: Field, d: Field) -> Field {
    pedersen_hash([a, b, c, d])
}

/// Hash an 8-element field array
pub fn hash8(input: [Field; 8]) -> Field {
    pedersen_hash(input)
}

/// Hash a 16-element field array
pub fn hash16(input: [Field; 16]) -> Field {
    pedersen_hash(input)
}

/// Hash a 32-element field array
pub fn hash32(input: [Field; 32]) -> Field {
    pedersen_hash(input)
}

#[test]
fn test_hash2_deterministic() {
    let h1 = hash2(1, 2);
    let h2 = hash2(1, 2);
    assert(h1 == h2);
}

#[test]
fn test_hash2_different_inputs() {
    let h1 = hash2(1, 2);
    let h2 = hash2(2, 1);
    assert(h1 != h2);
}
