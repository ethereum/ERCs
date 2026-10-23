/// Compliance proof circuit
///
/// Proves that a user's risk score (computed from screening provider signals)
/// is below the jurisdiction's high-risk threshold, without revealing:
/// - Individual provider signals
/// - The exact risk score
/// - Transaction amounts or counterparty details
///
/// Public inputs (visible to verifier):
///   - jurisdiction_id: which jurisdiction's thresholds to use
///   - provider_set_hash: commitment to which providers were used
///   - config_hash: hash of the published weight configuration
///   - timestamp: block timestamp binding the proof
///   - meets_threshold: boolean result (1 = compliant, 0 = not)
///   - submitter: address of the authorized proof submitter (anti-frontrun)
///
/// Private inputs (known only to prover):
///   - signals: risk scores from each screening provider (0-100)
///   - weights: published weights for each provider
///   - weight_sum: sum of all weights (for normalization)
///   - provider_ids: identifiers for each provider

use erc8262_shared::{
    compute_risk_score,
    get_high_threshold,
    compute_provider_set_hash,
    verify_weight_sum,
    compute_config_hash,
    validate_timestamp,
    validate_provider_slots,
};

fn main(
    // --- Private inputs ---
    signals: [u32; 8],           // per-provider risk signals (0-100 each)
    weights: [u32; 8],           // per-provider weights (published, but hidden in proof)
    weight_sum: u32,             // sum of active weights
    provider_ids: [Field; 8],    // provider identifiers
    num_providers: u32,          // how many providers are active (1-8)

    // --- Public inputs ---
    jurisdiction_id: pub u8,     // 0=EU, 1=US, 2=UK, 3=SG
    provider_set_hash: pub Field, // commitment to providers used
    config_hash: pub Field,      // hash of the weight config version
    timestamp: pub Field,        // block.timestamp for temporal binding
    meets_threshold: pub bool,   // the compliance result
    submitter: pub Field,        // authorized submitter address (oracle enforces == msg.sender)
) {
    // 1. Validate weight_sum is positive
    assert(weight_sum > 0, "Weight sum must be positive");

    // 2. Validate provider count + slot invariants (active vs inactive layout)
    validate_provider_slots(signals, weights, provider_ids, num_providers);

    // 4. Verify weight_sum matches active weights
    verify_weight_sum(weights, weight_sum);

    // 5. Compute the risk score
    let score = compute_risk_score(signals, weights, weight_sum);

    // 6. Get the jurisdiction threshold
    let threshold = get_high_threshold(jurisdiction_id);

    // 7. Verify the meets_threshold claim
    let computed_meets = score < threshold;
    assert(computed_meets == meets_threshold, "Threshold result mismatch");

    // 8. Verify provider set hash matches the committed set
    let computed_provider_hash = compute_provider_set_hash(provider_ids, weights);
    assert(computed_provider_hash == provider_set_hash, "Provider set hash mismatch");

    // 9. Verify config hash commits to the weight configuration
    let computed_config_hash = compute_config_hash(weights);
    assert(computed_config_hash == config_hash, "Config hash mismatch");

    // 10. Timestamp must be within reasonable bounds
    validate_timestamp(timestamp);

    // 11. Anchor submitter as a public input (oracle enforces submitter == msg.sender).
    // Non-zero check prevents the compiler from stripping this public input.
    assert(submitter != 0, "submitter must be non-zero");
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[test]
fn test_compliant_single_provider() {
    // Single provider, 20% risk signal, weight=100, weight_sum=100
    // score = 20*100*100/100 = 2000 bps (20%), EU threshold = 7100
    let signals = [20, 0, 0, 0, 0, 0, 0, 0];
    let weights: [u32; 8] = [100, 0, 0, 0, 0, 0, 0, 0];

    let score = compute_risk_score(signals, weights, 100);
    let threshold = get_high_threshold(0); // EU: 7100 bps
    assert(score == 2000);
    assert(score < threshold);
}

#[test]
fn test_non_compliant_high_risk() {
    // Single provider, 80% risk signal
    // score = 80*100*100/100 = 8000 bps (80%), EU threshold = 7100
    let signals = [80, 0, 0, 0, 0, 0, 0, 0];
    let weights: [u32; 8] = [100, 0, 0, 0, 0, 0, 0, 0];

    let score = compute_risk_score(signals, weights, 100);
    assert(score == 8000);
    assert(score >= get_high_threshold(0)); // above EU threshold
}

#[test]
fn test_multi_provider_compliance() {
    // Three providers: signals=[10,30,20], weights=[50,30,20], weight_sum=100
    // weighted_sum = 10*50 + 30*30 + 20*20 = 500+900+400 = 1800
    // score = 1800*100/100 = 1800 bps (18%), well below any threshold
    let signals = [10, 30, 20, 0, 0, 0, 0, 0];
    let weights: [u32; 8] = [50, 30, 20, 0, 0, 0, 0, 0];

    let score = compute_risk_score(signals, weights, 100);
    assert(score == 1800);
    assert(score < get_high_threshold(0)); // below EU threshold
}

#[test]
fn test_main_compliant_single_provider() {
    // Full main() test with valid witness for single-provider compliance
    let signals = [20, 0, 0, 0, 0, 0, 0, 0];
    let weights: [u32; 8] = [100, 0, 0, 0, 0, 0, 0, 0];
    let weight_sum: u32 = 100;
    let provider_ids: [Field; 8] = [1, 0, 0, 0, 0, 0, 0, 0];
    let num_providers: u32 = 1;

    // Compute expected public inputs
    let provider_set_hash = compute_provider_set_hash(provider_ids, weights);
    let config_hash = compute_config_hash(weights);

    // score = 20*100*100/100 = 2000 bps, EU threshold = 7100 -> meets
    main(
        signals, weights, weight_sum, provider_ids, num_providers,
        0, // EU
        provider_set_hash,
        config_hash,
        1700000000, // timestamp
        true, // meets_threshold
        0xdead, // submitter (no circuit constraint, oracle enforces)
    );
}

#[test]
fn test_main_non_compliant_high_risk() {
    // Full main() test for non-compliant result (score above threshold)
    let signals = [80, 0, 0, 0, 0, 0, 0, 0];
    let weights: [u32; 8] = [100, 0, 0, 0, 0, 0, 0, 0];
    let weight_sum: u32 = 100;
    let provider_ids: [Field; 8] = [1, 0, 0, 0, 0, 0, 0, 0];

    let provider_set_hash = compute_provider_set_hash(provider_ids, weights);
    let config_hash = compute_config_hash(weights);

    // score = 8000 bps, EU threshold = 7100 -> does NOT meet
    main(
        signals, weights, weight_sum, provider_ids, 1,
        0, // EU
        provider_set_hash,
        config_hash,
        1700000000,
        false, // does not meet threshold
        0xdead,
    );
}

#[test]
fn test_main_multi_provider_all_jurisdictions() {
    // 3 providers, test all 4 jurisdictions
    let signals = [30, 40, 20, 0, 0, 0, 0, 0];
    let weights: [u32; 8] = [50, 30, 20, 0, 0, 0, 0, 0];
    let weight_sum: u32 = 100;
    let provider_ids: [Field; 8] = [10, 20, 30, 0, 0, 0, 0, 0];

    let provider_set_hash = compute_provider_set_hash(provider_ids, weights);
    let config_hash = compute_config_hash(weights);

    // weighted_sum = 30*50 + 40*30 + 20*20 = 1500+1200+400 = 3100
    // score = 3100*100/100 = 3100 bps (31%), below all thresholds
    for j in 0..4 {
        main(
            signals, weights, weight_sum, provider_ids, 3,
            j as u8,
            provider_set_hash,
            config_hash,
            1700000000,
            true,
            0xdead,
        );
    }
}

#[test]
fn test_score_at_exact_threshold_boundary() {
    // score = 71*100*100/100 = 7100 bps, EU threshold = 7100
    // score < threshold is false, so meets_threshold = false
    let signals = [71, 0, 0, 0, 0, 0, 0, 0];
    let weights: [u32; 8] = [100, 0, 0, 0, 0, 0, 0, 0];
    let weight_sum: u32 = 100;
    let provider_ids: [Field; 8] = [1, 0, 0, 0, 0, 0, 0, 0];

    let provider_set_hash = compute_provider_set_hash(provider_ids, weights);
    let config_hash = compute_config_hash(weights);

    main(
        signals, weights, weight_sum, provider_ids, 1,
        0, // EU
        provider_set_hash,
        config_hash,
        1700000000,
        false,
        0xdead,
    );
}

#[test]
fn test_score_just_below_threshold() {
    // score = 70*100*100/100 = 7000 bps, EU threshold = 7100
    // score < threshold is true, so meets_threshold = true
    let signals = [70, 0, 0, 0, 0, 0, 0, 0];
    let weights: [u32; 8] = [100, 0, 0, 0, 0, 0, 0, 0];
    let weight_sum: u32 = 100;
    let provider_ids: [Field; 8] = [1, 0, 0, 0, 0, 0, 0, 0];

    let provider_set_hash = compute_provider_set_hash(provider_ids, weights);
    let config_hash = compute_config_hash(weights);

    main(
        signals, weights, weight_sum, provider_ids, 1,
        0, // EU
        provider_set_hash,
        config_hash,
        1700000000,
        true,
        0xdead,
    );
}

#[test]
fn test_score_one_bps_below_threshold_eu() {
    // Two providers producing exactly 7099 bps (1 bps below EU threshold of 7100)
    // weighted_sum = 71*99 + 70*1 = 7029 + 70 = 7099
    // score = 7099 * 100 / 100 = 7099 bps
    let signals = [71, 70, 0, 0, 0, 0, 0, 0];
    let weights: [u32; 8] = [99, 1, 0, 0, 0, 0, 0, 0];
    let weight_sum: u32 = 100;
    let provider_ids: [Field; 8] = [1, 2, 0, 0, 0, 0, 0, 0];

    let score = compute_risk_score(signals, weights, weight_sum);
    assert(score == 7099);

    let threshold = get_high_threshold(0); // EU: 7100
    assert(score < threshold);

    let provider_set_hash = compute_provider_set_hash(provider_ids, weights);
    let config_hash = compute_config_hash(weights);

    main(
        signals, weights, weight_sum, provider_ids, 2,
        0, // EU
        provider_set_hash,
        config_hash,
        1700000000,
        true, // 7099 < 7100
        0xdead,
    );
}

#[test]
fn test_score_one_bps_below_threshold_us() {
    // Two providers producing exactly 6599 bps (1 bps below US threshold of 6600)
    // weighted_sum = 66*99 + 65*1 = 6534 + 65 = 6599
    // score = 6599 * 100 / 100 = 6599 bps
    let signals = [66, 65, 0, 0, 0, 0, 0, 0];
    let weights: [u32; 8] = [99, 1, 0, 0, 0, 0, 0, 0];
    let weight_sum: u32 = 100;
    let provider_ids: [Field; 8] = [1, 2, 0, 0, 0, 0, 0, 0];

    let score = compute_risk_score(signals, weights, weight_sum);
    assert(score == 6599);

    let provider_set_hash = compute_provider_set_hash(provider_ids, weights);
    let config_hash = compute_config_hash(weights);

    main(
        signals, weights, weight_sum, provider_ids, 2,
        1, // US
        provider_set_hash,
        config_hash,
        1700000000,
        true, // 6599 < 6600
        0xdead,
    );
}
