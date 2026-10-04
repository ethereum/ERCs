/// Shared types and utilities for ERC-8262 circuits
///
/// Re-exports all modules for convenient use by circuit crates:
///   use erc8262_shared::{hash2, compute_merkle_root, compute_risk_score, ...};

pub mod constants;
pub mod hash;
pub mod merkle;
pub mod risk;
pub mod providers;
pub mod sig;
pub mod multi_sig;
pub mod validation;

// Re-export everything at the crate root for backwards compatibility.
// Circuits can use either `erc8262_shared::hash2` or `erc8262_shared::hash::hash2`.
pub use constants::{
    MAX_PROVIDERS, MERKLE_DEPTH, MAX_TRANSACTIONS,
    JURISDICTION_EU, JURISDICTION_US, JURISDICTION_UK, JURISDICTION_SG, JURISDICTION_UAE,
};
pub use hash::{hash2, hash3, hash4, hash8, hash16, hash32};
pub use merkle::{compute_merkle_root, internal_hash, leaf_hash_set, leaf_hash_subject, leaf_hash_value};
pub use risk::{MAX_WEIGHT, compute_risk_score, get_high_threshold, verify_weight_sum, weights_to_fields, compute_config_hash};
pub use providers::compute_provider_set_hash;
pub use sig::{compute_signed_payload_hash, compute_signer_pubkey_hash, verify_provider_signed_signals};
pub use multi_sig::{MAX_PROVIDERS_MULTI, DOMAIN_MULTI_SIGNED_SIGNALS, compute_slot_payload_hash, verify_slot_or_skip, assert_distinct_signers, count_active_signers};
pub use validation::{validate_timestamp, compute_tx_set_hash, validate_provider_slots};
