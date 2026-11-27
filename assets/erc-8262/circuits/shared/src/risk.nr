/// Risk score computation for ERC-8262 circuits

use crate::constants::{JURISDICTION_EU, JURISDICTION_US, JURISDICTION_UK, JURISDICTION_SG, JURISDICTION_UAE};
use crate::hash::hash8;

/// Maximum weight per provider (prevents u32 overflow in risk score computation).
/// With N=8 providers, max signal=100: worst case = 8 * 100 * MAX_WEIGHT = 8 * 100 * 10000
/// = 8,000,000. Then * 100 = 800,000,000, well within u32 max (4,294,967,295).
pub global MAX_WEIGHT: u32 = 10000;

/// Compute a weighted risk score from provider signals and weights
/// Signals are 0-100 (percentage risk from each provider)
/// Weights are importance factors that sum to weight_sum (each <= MAX_WEIGHT)
/// Returns the score as a u32 in basis points (0-10000, i.e. 0.00%-100.00%)
///
/// NOTE: Integer division truncates remainders (max error < 1 bps).
/// The Solidity JurisdictionConfig uses percentage scale (0-100); a threshold
/// of 71 there corresponds to 7100 bps here.
pub fn compute_risk_score<let N: u32>(
    signals: [u32; N],
    weights: [u32; N],
    weight_sum: u32,
) -> u32 {
    let mut weighted_sum: u32 = 0;
    for i in 0..N {
        assert(weights[i] <= MAX_WEIGHT, "Weight exceeds maximum");
        weighted_sum += signals[i] * weights[i];
    }
    // signals are 0-100, so multiply by 100 to get basis points
    // score_bps = sum(signal_i * weight_i) * 100 / weight_sum
    // Overflow safe: max weighted_sum = 8 * 100 * 10000 = 8M, * 100 = 800M < u32::MAX
    (weighted_sum * 100) / weight_sum
}

/// Get the high-risk threshold for a jurisdiction (in basis points)
/// Must match Solidity JurisdictionConfig thresholds
pub fn get_high_threshold(jurisdiction_id: u8) -> u32 {
    assert(jurisdiction_id <= JURISDICTION_UAE, "Invalid jurisdiction");
    if jurisdiction_id == JURISDICTION_EU {
        7100 // 71%
    } else if jurisdiction_id == JURISDICTION_US {
        6600 // 66%
    } else if jurisdiction_id == JURISDICTION_UK {
        7100 // 71%
    } else if jurisdiction_id == JURISDICTION_SG {
        7600 // 76%
    } else {
        7100 // 71% (JURISDICTION_UAE, guarded by assert above)
    }
}

/// Verify that the provided weight_sum matches the actual sum of weights.
/// Prevents the prover from passing an arbitrary denominator to inflate/deflate scores.
pub fn verify_weight_sum(weights: [u32; 8], weight_sum: u32) {
    let mut computed: u32 = 0;
    for i in 0..8 {
        computed += weights[i];
    }
    assert(computed == weight_sum, "Weight sum mismatch");
}

/// Convert u32 weights to Field elements for hashing.
/// Used to compute config_hash = hash8(weights_as_fields).
pub fn weights_to_fields(weights: [u32; 8]) -> [Field; 8] {
    let mut result: [Field; 8] = [0; 8];
    for i in 0..8 {
        result[i] = weights[i] as Field;
    }
    result
}

/// Compute the config hash from a weight array.
/// Convenience wrapper: converts weights to fields and hashes them.
pub fn compute_config_hash(weights: [u32; 8]) -> Field {
    hash8(weights_to_fields(weights))
}

#[test]
fn test_verify_weight_sum() {
    verify_weight_sum([50, 30, 20, 0, 0, 0, 0, 0], 100);
}

#[test]
fn test_weights_to_fields() {
    let fields = weights_to_fields([100, 0, 0, 0, 0, 0, 0, 0]);
    assert(fields[0] == 100);
    assert(fields[1] == 0);
}

#[test]
fn test_risk_score_basic() {
    let score = compute_risk_score([50], [100], 100);
    assert(score == 5000);
}

#[test]
fn test_risk_score_multi_provider() {
    let score = compute_risk_score([30, 70], [60, 40], 100);
    assert(score == 4600);
}

#[test]
fn test_high_threshold_eu() {
    assert(get_high_threshold(JURISDICTION_EU) == 7100);
}

#[test]
fn test_high_threshold_us() {
    assert(get_high_threshold(JURISDICTION_US) == 6600);
}

#[test]
fn test_threshold_cross_validation_all() {
    // Cross-validation: these MUST match Solidity JurisdictionConfig.getHighRiskThreshold() * 100
    // See: src/libraries/JurisdictionConfig.sol (EU=71, US=66, UK=71, SG=76, UAE=71 percentage scale)
    assert(get_high_threshold(JURISDICTION_EU) == 7100);
    assert(get_high_threshold(JURISDICTION_US) == 6600);
    assert(get_high_threshold(JURISDICTION_UK) == 7100);
    assert(get_high_threshold(JURISDICTION_SG) == 7600);
    assert(get_high_threshold(JURISDICTION_UAE) == 7100);
}
