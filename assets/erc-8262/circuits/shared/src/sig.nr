/// Provider-signed-signals helpers (audit finding I-1).
///
/// The COMPLIANCE_SIGNED / RISK_SCORE_SIGNED circuits anchor the screening signals
/// to a provider-issued signature. The provider signs a Pedersen digest committing to
/// `(provider_set_hash, signals, weights, timestamp, submitter)`; the circuit verifies
/// the signature in-circuit using `std::ecdsa_secp256k1`. Without this, a user could
/// submit `signals = [0; 8]` and prove "low risk" without real screening.
///
/// Trust resolution: the circuit also exposes `signer_pubkey_hash` as a public input
/// (Pedersen commitment to the secp256k1 (x, y) pubkey). The Oracle keeps a registry
/// of authorized `signer_pubkey_hash` values; submission rejects any proof whose
/// public input is not in the registry. Rotating a provider's signing key is therefore
/// a registry update, not a circuit change.

use std::ecdsa_secp256k1;
use std::hash::pedersen_hash;

use crate::merkle::DOMAIN_SIGNED_SIGNALS;

/// Domain tag for the secp256k1-pubkey-hash commitment.
/// Pedersen hash of [tag, x_hi, x_lo, y_hi, y_lo].
pub global DOMAIN_SIGNER_PUBKEY: Field = 0x5349475f504b; // ASCII "SIG_PK"

/// Pack a 32-byte big-endian secp256k1 coordinate into two 16-byte field halves.
/// Splitting is required because BN254's scalar field (~254 bits) cannot represent
/// arbitrary 256-bit values without truncation.
pub fn coordinate_to_fields(coord: [u8; 32]) -> (Field, Field) {
    let mut hi: Field = 0;
    let mut lo: Field = 0;
    for i in 0..16 {
        hi = hi * 256 + coord[i] as Field;
        lo = lo * 256 + coord[16 + i] as Field;
    }
    (hi, lo)
}

/// Compute the public commitment to a secp256k1 signer pubkey.
/// Off-chain: providers register the same hash with `ERC8262Oracle.registerSignerPubkeyHash`.
pub fn compute_signer_pubkey_hash(pubkey_x: [u8; 32], pubkey_y: [u8; 32]) -> Field {
    let (x_hi, x_lo) = coordinate_to_fields(pubkey_x);
    let (y_hi, y_lo) = coordinate_to_fields(pubkey_y);
    pedersen_hash([DOMAIN_SIGNER_PUBKEY, x_hi, x_lo, y_hi, y_lo])
}

/// Compute the Pedersen digest the provider signs over.
///
/// Layout (22 field elements, audit F-6: chain_id + oracle_address bind the
/// signed payload to a specific deployment so a single signature cannot mint
/// attestations on multiple Oracle instances or chains):
///   [0]:    DOMAIN_SIGNED_SIGNALS
///   [1]:    chain_id
///   [2]:    oracle_address
///   [3]:    provider_set_hash
///   [4..12):  signals[0..8]
///   [12..20): weights[0..8]
///   [20]:   timestamp
///   [21]:   submitter
pub fn compute_signed_payload_hash(
    chain_id: Field,
    oracle_address: Field,
    provider_set_hash: Field,
    signals: [u32; 8],
    weights: [u32; 8],
    timestamp: Field,
    submitter: Field,
) -> Field {
    let mut input: [Field; 22] = [0; 22];
    input[0] = DOMAIN_SIGNED_SIGNALS;
    input[1] = chain_id;
    input[2] = oracle_address;
    input[3] = provider_set_hash;
    for i in 0..8 {
        input[4 + i] = signals[i] as Field;
        input[12 + i] = weights[i] as Field;
    }
    input[20] = timestamp;
    input[21] = submitter;
    pedersen_hash(input)
}

/// Verify the provider's secp256k1 ECDSA signature over the signed payload digest.
/// Aborts the circuit if the signature is invalid or if `signer_pubkey_hash` does
/// not commit to the supplied pubkey.
pub fn verify_provider_signed_signals(
    pubkey_x: [u8; 32],
    pubkey_y: [u8; 32],
    signature: [u8; 64],
    payload_hash: Field,
    expected_pubkey_hash: Field,
) {
    let computed_pubkey_hash = compute_signer_pubkey_hash(pubkey_x, pubkey_y);
    assert(computed_pubkey_hash == expected_pubkey_hash, "signer_pubkey_hash mismatch");

    let payload_bytes: [u8; 32] = payload_hash.to_be_bytes();
    let valid = ecdsa_secp256k1::verify_signature(pubkey_x, pubkey_y, signature, payload_bytes);
    assert(valid, "invalid provider signature on signals");
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[test]
fn test_coordinate_to_fields_high_zero() {
    let coord: [u8; 32] = [0; 32];
    let (hi, lo) = coordinate_to_fields(coord);
    assert(hi == 0);
    assert(lo == 0);
}

#[test]
fn test_coordinate_to_fields_pattern() {
    // First half is 0x00..0x0F, second half is 0x10..0x1F
    let mut coord: [u8; 32] = [0; 32];
    for i in 0..32 {
        coord[i] = i as u8;
    }
    let (hi, lo) = coordinate_to_fields(coord);
    // hi = 0x000102030405060708090a0b0c0d0e0f
    // lo = 0x101112131415161718191a1b1c1d1e1f
    let expected_hi: Field = 0x000102030405060708090a0b0c0d0e0f;
    let expected_lo: Field = 0x101112131415161718191a1b1c1d1e1f;
    assert(hi == expected_hi);
    assert(lo == expected_lo);
}

#[test]
fn test_signed_payload_hash_deterministic() {
    let signals: [u32; 8] = [10, 20, 30, 0, 0, 0, 0, 0];
    let weights: [u32; 8] = [50, 30, 20, 0, 0, 0, 0, 0];
    let h1 = compute_signed_payload_hash(1, 0xabcd, 0xdead, signals, weights, 1700000000, 0xcafe);
    let h2 = compute_signed_payload_hash(1, 0xabcd, 0xdead, signals, weights, 1700000000, 0xcafe);
    assert(h1 == h2);
}

#[test]
fn test_signed_payload_hash_changes_on_signal_mutation() {
    let signals_a: [u32; 8] = [10, 20, 30, 0, 0, 0, 0, 0];
    let signals_b: [u32; 8] = [11, 20, 30, 0, 0, 0, 0, 0];
    let weights: [u32; 8] = [50, 30, 20, 0, 0, 0, 0, 0];
    let h_a = compute_signed_payload_hash(1, 0xabcd, 0xdead, signals_a, weights, 1700000000, 0xcafe);
    let h_b = compute_signed_payload_hash(1, 0xabcd, 0xdead, signals_b, weights, 1700000000, 0xcafe);
    assert(h_a != h_b);
}

#[test]
fn test_signed_payload_hash_changes_on_submitter_mutation() {
    let signals: [u32; 8] = [10, 20, 30, 0, 0, 0, 0, 0];
    let weights: [u32; 8] = [50, 30, 20, 0, 0, 0, 0, 0];
    let h_a = compute_signed_payload_hash(1, 0xabcd, 0xdead, signals, weights, 1700000000, 0xcafe);
    let h_b = compute_signed_payload_hash(1, 0xabcd, 0xdead, signals, weights, 1700000000, 0xbeef);
    assert(h_a != h_b);
}

#[test]
fn test_signed_payload_hash_changes_on_chain_id_mutation() {
    let signals: [u32; 8] = [10, 20, 30, 0, 0, 0, 0, 0];
    let weights: [u32; 8] = [50, 30, 20, 0, 0, 0, 0, 0];
    let h_a = compute_signed_payload_hash(1, 0xabcd, 0xdead, signals, weights, 1700000000, 0xcafe);
    let h_b = compute_signed_payload_hash(8453, 0xabcd, 0xdead, signals, weights, 1700000000, 0xcafe);
    assert(h_a != h_b, "chain_id must alter the digest");
}

#[test]
fn test_signed_payload_hash_changes_on_oracle_address_mutation() {
    let signals: [u32; 8] = [10, 20, 30, 0, 0, 0, 0, 0];
    let weights: [u32; 8] = [50, 30, 20, 0, 0, 0, 0, 0];
    let h_a = compute_signed_payload_hash(1, 0xabcd, 0xdead, signals, weights, 1700000000, 0xcafe);
    let h_b = compute_signed_payload_hash(1, 0xfeed, 0xdead, signals, weights, 1700000000, 0xcafe);
    assert(h_a != h_b, "oracle_address must alter the digest");
}

// ---------------------------------------------------------------------------
// Off-chain parity vectors (audit I-1)
//
// These vectors are reproduced byte-for-byte in xochi-sdk's
// test/provider-pedersen.test.ts ("Noir parity vectors"). If the in-circuit
// Pedersen ever drifts from bb.js's pedersenHash, both sides MUST be updated
// together. Any provider signing daemon depends on this match -- a bad digest
// means a valid provider signature won't satisfy the in-circuit verifier.
// ---------------------------------------------------------------------------

#[test]
fn test_parity_with_sdk_signed_payload_hash() {
    // Audit F-6: digest layout extended with chain_id (1) and oracle_address
    // (0xabcd1234) committed at fixed positions. xochi-sdk's
    // test/provider-pedersen.test.ts must regenerate its expected vector with
    // the matching parameters and update the expected constant below.
    let signals: [u32; 8] = [10, 20, 30, 0, 0, 0, 0, 0];
    let weights: [u32; 8] = [50, 30, 20, 0, 0, 0, 0, 0];
    let actual = compute_signed_payload_hash(
        1,
        0xabcd1234,
        0xdead,
        signals,
        weights,
        1700000000,
        0xcafe,
    );
    // Computed via xochi-sdk's bb.js Pedersen for this exact input set after
    // the F-6 layout change. If this drifts, regenerate by running
    // `npx vitest run test/provider-pedersen.test.ts` in xochi-sdk and
    // copying the printed `[parity] signed_payload_hash` value here.
    let expected: Field = 0x161ce9164a86defd6b8c44e9923690407bea0488eb15bd91b99ce71438dae106;
    assert(actual == expected, "signed_payload_hash drifted from xochi-sdk pedersen.ts");
}

#[test]
fn test_parity_with_sdk_signer_pubkey_hash() {
    // Deterministic test pubkey pattern (NOT a real key). x = 0x00..0x1F, y = 0x40..0x5F.
    let mut pubkey_x: [u8; 32] = [0; 32];
    let mut pubkey_y: [u8; 32] = [0; 32];
    for i in 0..32 {
        pubkey_x[i] = i as u8;
        pubkey_y[i] = (0x40 + i) as u8;
    }
    let actual = compute_signer_pubkey_hash(pubkey_x, pubkey_y);
    let expected: Field = 0x058715a847c033508c9f675ad51831993ea45169b097bd064942295ee24e4f19;
    assert(actual == expected, "signer_pubkey_hash drifted from xochi-sdk pedersen.ts");
}
