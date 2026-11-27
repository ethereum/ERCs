/// Multi-provider signed-signals helpers for the COMPLIANCE_MULTI_SIGNED proof type.
///
/// The single-signer `sig.nr` primitives anchor a screening attestation to ONE provider.
/// `multi_sig.nr` extends this to M-of-N: the circuit verifies up to `MAX_PROVIDERS_MULTI`
/// independent provider signatures, asserts at least `threshold_m` are active and that
/// each active slot's risk score is below the jurisdiction floor, and rejects duplicates.
///
/// A slot is "active" iff its public `signer_pubkey_hash` is non-zero. Inactive slots
/// still emit all constraints (verify + risk score) but the assertions are gated so
/// arbitrary witness is accepted. Total verify cost is roughly base * (1 + 0.3 * N_MAX),
/// independent of runtime M -- callers pay for the protection, not for fewer signers.
///
/// Each slot's signature commits to a slot-specific Pedersen digest with domain tag
/// DOMAIN_MULTI_SIGNED_SIGNALS and an embedded `slot_index`. This prevents:
///   - a single-signer (0x07) proof from being replayed as one slot of a multi-signer proof
///   - the same provider's signature from being copied across two slots of the same proof
///   - cross-chain / cross-deployment replay (chain_id + oracle_address bound, audit F-6)

use std::ecdsa_secp256k1;
use std::hash::pedersen_hash;

use crate::sig::compute_signer_pubkey_hash;

/// Compile-time bound on the number of provider slots in the multi-signed circuit.
/// Runtime threshold M satisfies 1 <= M <= MAX_PROVIDERS_MULTI.
pub global MAX_PROVIDERS_MULTI: u32 = 5;

/// Domain tag for the multi-provider signed payload Pedersen digest.
/// Distinct from DOMAIN_SIGNED_SIGNALS so a 0x07 signature cannot satisfy a 0x09 slot.
pub global DOMAIN_MULTI_SIGNED_SIGNALS: Field = 0x4d554c54495f5349; // ASCII "MULTI_SI"

/// Compute the per-slot Pedersen digest the i-th provider signs over.
///
/// Layout (25 field elements):
///   [0]:    DOMAIN_MULTI_SIGNED_SIGNALS
///   [1]:    slot_index
///   [2]:    chain_id                (audit F-6: cross-chain binding)
///   [3]:    oracle_address          (audit F-6: cross-Oracle binding)
///   [4]:    jurisdiction_id
///   [5]:    provider_set_hash       (shared across slots)
///   [6]:    config_hash             (shared across slots)
///   [7..15):  signals[0..8]
///   [15..23): weights[0..8]
///   [23]:   timestamp
///   [24]:   submitter
pub fn compute_slot_payload_hash(
    slot_index: u32,
    chain_id: Field,
    oracle_address: Field,
    jurisdiction_id: u8,
    provider_set_hash: Field,
    config_hash: Field,
    signals: [u32; 8],
    weights: [u32; 8],
    timestamp: Field,
    submitter: Field,
) -> Field {
    let mut input: [Field; 25] = [0; 25];
    input[0] = DOMAIN_MULTI_SIGNED_SIGNALS;
    input[1] = slot_index as Field;
    input[2] = chain_id;
    input[3] = oracle_address;
    input[4] = jurisdiction_id as Field;
    input[5] = provider_set_hash;
    input[6] = config_hash;
    for i in 0..8 {
        input[7 + i] = signals[i] as Field;
        input[15 + i] = weights[i] as Field;
    }
    input[23] = timestamp;
    input[24] = submitter;
    pedersen_hash(input)
}

/// Verify a single slot's provider signature, gated on `active`.
///
/// Active (signer_pubkey_hash != 0):
///   - computed Pedersen of (pubkey_x, pubkey_y) must equal expected_pubkey_hash
///   - secp256k1 ECDSA signature over `payload_hash` must verify
///
/// Inactive: arbitrary witness for (pubkey_x, pubkey_y, signature) is accepted.
/// The constraints are still emitted (ECDSA cost is paid) but the assertions are bypassed.
pub fn verify_slot_or_skip(
    active: bool,
    pubkey_x: [u8; 32],
    pubkey_y: [u8; 32],
    signature: [u8; 64],
    payload_hash: Field,
    expected_pubkey_hash: Field,
) {
    let computed_pubkey_hash = compute_signer_pubkey_hash(pubkey_x, pubkey_y);
    let pubkey_ok = computed_pubkey_hash == expected_pubkey_hash;
    assert((!active) | pubkey_ok, "active slot: signer_pubkey_hash mismatch");

    let payload_bytes: [u8; 32] = payload_hash.to_be_bytes();
    let sig_valid = ecdsa_secp256k1::verify_signature(pubkey_x, pubkey_y, signature, payload_bytes);
    assert((!active) | sig_valid, "active slot: invalid provider signature");
}

/// Assert that no two active slots share the same signer_pubkey_hash.
/// Inactive slots all have hash == 0; this is allowed (duplicate zeros do not fail).
/// O(N^2) pairwise comparison; N = MAX_PROVIDERS_MULTI = 5 makes this 10 comparisons.
pub fn assert_distinct_signers(hashes: [Field; 5]) {
    for i in 0..5 {
        for j in (i + 1)..5 {
            let both_active = (hashes[i] != 0) & (hashes[j] != 0);
            let distinct = hashes[i] != hashes[j];
            assert((!both_active) | distinct, "duplicate signer across active slots");
        }
    }
}

/// Count the number of active (non-zero) signer_pubkey_hash slots.
pub fn count_active_signers(hashes: [Field; 5]) -> u32 {
    let mut count: u32 = 0;
    for i in 0..5 {
        if hashes[i] != 0 {
            count += 1;
        }
    }
    count
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[test]
fn test_slot_payload_hash_deterministic() {
    let signals: [u32; 8] = [10, 20, 30, 0, 0, 0, 0, 0];
    let weights: [u32; 8] = [50, 30, 20, 0, 0, 0, 0, 0];
    let h1 = compute_slot_payload_hash(
        0, 1, 0xabcd1234, 0, 0xdead, 0xbeef, signals, weights, 1700000000, 0xcafe,
    );
    let h2 = compute_slot_payload_hash(
        0, 1, 0xabcd1234, 0, 0xdead, 0xbeef, signals, weights, 1700000000, 0xcafe,
    );
    assert(h1 == h2);
}

#[test]
fn test_slot_payload_hash_changes_on_slot_index() {
    let signals: [u32; 8] = [10, 20, 30, 0, 0, 0, 0, 0];
    let weights: [u32; 8] = [50, 30, 20, 0, 0, 0, 0, 0];
    let h_a = compute_slot_payload_hash(
        0, 1, 0xabcd1234, 0, 0xdead, 0xbeef, signals, weights, 1700000000, 0xcafe,
    );
    let h_b = compute_slot_payload_hash(
        1, 1, 0xabcd1234, 0, 0xdead, 0xbeef, signals, weights, 1700000000, 0xcafe,
    );
    assert(h_a != h_b, "slot_index must alter the digest");
}

#[test]
fn test_slot_payload_hash_changes_on_chain_id() {
    let signals: [u32; 8] = [10, 20, 30, 0, 0, 0, 0, 0];
    let weights: [u32; 8] = [50, 30, 20, 0, 0, 0, 0, 0];
    let h_a = compute_slot_payload_hash(
        0, 1, 0xabcd1234, 0, 0xdead, 0xbeef, signals, weights, 1700000000, 0xcafe,
    );
    let h_b = compute_slot_payload_hash(
        0, 8453, 0xabcd1234, 0, 0xdead, 0xbeef, signals, weights, 1700000000, 0xcafe,
    );
    assert(h_a != h_b, "chain_id must alter the digest");
}

#[test]
fn test_slot_payload_hash_changes_on_jurisdiction() {
    let signals: [u32; 8] = [10, 20, 30, 0, 0, 0, 0, 0];
    let weights: [u32; 8] = [50, 30, 20, 0, 0, 0, 0, 0];
    let h_a = compute_slot_payload_hash(
        0, 1, 0xabcd1234, 0, 0xdead, 0xbeef, signals, weights, 1700000000, 0xcafe,
    );
    let h_b = compute_slot_payload_hash(
        0, 1, 0xabcd1234, 1, 0xdead, 0xbeef, signals, weights, 1700000000, 0xcafe,
    );
    assert(h_a != h_b, "jurisdiction must alter the digest");
}

#[test]
fn test_distinct_signers_all_zero() {
    let hashes: [Field; 5] = [0, 0, 0, 0, 0];
    assert_distinct_signers(hashes);
}

#[test]
fn test_distinct_signers_unique_active() {
    let hashes: [Field; 5] = [0x11, 0x22, 0, 0x33, 0];
    assert_distinct_signers(hashes);
}

#[test(should_fail_with = "duplicate signer across active slots")]
fn test_distinct_signers_duplicate_active() {
    let hashes: [Field; 5] = [0x11, 0x22, 0x11, 0, 0];
    assert_distinct_signers(hashes);
}

#[test]
fn test_count_active_signers_none() {
    let hashes: [Field; 5] = [0, 0, 0, 0, 0];
    assert(count_active_signers(hashes) == 0);
}

#[test]
fn test_count_active_signers_three_of_five() {
    let hashes: [Field; 5] = [0x11, 0, 0x22, 0x33, 0];
    assert(count_active_signers(hashes) == 3);
}

#[test]
fn test_count_active_signers_all() {
    let hashes: [Field; 5] = [0x11, 0x22, 0x33, 0x44, 0x55];
    assert(count_active_signers(hashes) == 5);
}

// ---------------------------------------------------------------------------
// Off-chain parity vector (mirrors xochi-sdk's test/provider-pedersen.test.ts
// "slot payload hash for fixture inputs (multi-signed)").
//
// If the in-circuit Pedersen layout drifts from bb.js, both sides must update
// together. The SDK prints this digest via `npx vitest run
// test/provider-pedersen.test.ts --reporter=verbose`; the value below is what
// it printed for the fixture inputs (slot=0, chain=1, oracle=0xabcd1234,
// jurisdiction=0, provider_set=0xdead, config=0xbeef, signals=[10,20,30,0..],
// weights=[50,30,20,0..], timestamp=1700000000, submitter=0xcafe).
// ---------------------------------------------------------------------------

#[test]
fn test_parity_with_sdk_slot_payload_hash() {
    let signals: [u32; 8] = [10, 20, 30, 0, 0, 0, 0, 0];
    let weights: [u32; 8] = [50, 30, 20, 0, 0, 0, 0, 0];
    let actual = compute_slot_payload_hash(
        0,
        1,
        0xabcd1234,
        0,
        0xdead,
        0xbeef,
        signals,
        weights,
        1700000000,
        0xcafe,
    );
    let expected: Field = 0x2fb6d465edad72085a6d9cdd0fa2bba97c6f946e55762c0d53d96abe5d8e547f;
    assert(actual == expected, "slot_payload_hash drifted from xochi-sdk pedersen.ts");
}
