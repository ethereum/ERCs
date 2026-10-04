/// Common validation utilities for ERC-8262 circuits

use crate::constants::MAX_PROVIDERS;
use crate::hash::hash32;

/// Validate that a timestamp is within reasonable bounds.
/// Lower bound: 2021-01-01 (1609459200). Upper bound: 2^40 (~year 36812).
pub fn validate_timestamp(timestamp: Field) {
    assert(timestamp as u64 > 1609459200, "Timestamp before 2021");
    assert(timestamp as u64 < 1099511627776, "Timestamp unreasonably far future"); // 2^40
}

/// Validate the per-provider slot invariants for circuits that accept screening
/// signals as a flat 8-slot array with a `num_providers` count.
///
/// Active slots (`i < num_providers`):
///   - signal in [0, 100]
///   - weight > 0
///   - provider_id != 0 (so an active slot cannot be confused with an inactive one in the hash)
///
/// Inactive slots: signal, weight, and provider_id must all be zero.
pub fn validate_provider_slots(
    signals: [u32; 8],
    weights: [u32; 8],
    provider_ids: [Field; 8],
    num_providers: u32,
) {
    assert(num_providers >= 1, "At least one provider required");
    assert(num_providers <= MAX_PROVIDERS, "Too many providers");
    for i in 0..8 {
        if (i as u32) < num_providers {
            assert(signals[i] <= 100, "Signal must be 0-100");
            assert(weights[i] > 0, "Active provider weight must be positive");
            assert(provider_ids[i] != 0, "Active provider ID must be non-zero");
        } else {
            assert(signals[i] == 0, "Inactive signal must be zero");
            assert(weights[i] == 0, "Inactive weight must be zero");
            assert(provider_ids[i] == 0, "Inactive provider ID must be zero");
        }
    }
}

/// Compute a commitment to a transaction set (amounts + timestamps interleaved).
/// Layout: [amount_0, timestamp_0, amount_1, timestamp_1, ..., amount_15, timestamp_15]
pub fn compute_tx_set_hash(amounts: [u64; 16], timestamps: [u64; 16]) -> Field {
    let mut hash_inputs: [Field; 32] = [0; 32];
    for i in 0..16 {
        hash_inputs[i * 2] = amounts[i] as Field;
        hash_inputs[i * 2 + 1] = timestamps[i] as Field;
    }
    hash32(hash_inputs)
}

#[test]
fn test_validate_timestamp_valid() {
    validate_timestamp(1700000000); // 2023
}

#[test(should_fail_with = "Timestamp before 2021")]
fn test_validate_timestamp_too_early() {
    validate_timestamp(1000000000); // 2001
}

#[test]
fn test_compute_tx_set_hash_deterministic() {
    let amounts: [u64; 16] = [100, 200, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    let timestamps: [u64; 16] = [1000, 2000, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    let h1 = compute_tx_set_hash(amounts, timestamps);
    let h2 = compute_tx_set_hash(amounts, timestamps);
    assert(h1 == h2);
}
