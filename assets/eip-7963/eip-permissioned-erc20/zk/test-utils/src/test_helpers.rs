use crate::payment_instruction_generator::{PaymentInstructionInput, PaymentInstructionOutput};
use crate::{TestConfig, TestResult, METHOD_ELF, METHOD_ID};
use anyhow;
use risc0_zkvm::{default_prover, ExecutorEnv, Receipt};
use std::fs;
use std::time::{Duration, Instant};
use tempfile::NamedTempFile;

/// Test metrics for performance analysis
#[derive(Debug, Clone)]
pub struct TestMetrics {
    pub proof_generation_time: Duration,
    pub verification_time: Duration,
    pub memory_usage_mb: u64,
    pub proof_size_bytes: usize,
    pub journal_size_bytes: usize,
}

/// Generate a RISC Zero proof for Pain001 input
pub fn generate_proof(
    input: &PaymentInstructionInput,
    _config: &TestConfig,
) -> TestResult<(Receipt, TestMetrics)> {
    // Start timing
    let start_time = Instant::now();

    // Create the execution environment
    let env = ExecutorEnv::builder().write(input)?.build()?;

    // Generate the proof
    let prover = default_prover();
    let prove_info = prover.prove(env, METHOD_ELF)?;
    let receipt = prove_info.receipt;

    let proof_generation_time = start_time.elapsed();

    // Time verification
    let verify_start = Instant::now();
    receipt.verify(METHOD_ID)?;
    let verification_time = verify_start.elapsed();

    // Calculate metrics
    let proof_size_bytes = format!("{:?}", receipt.inner).len(); // Approximation
    let journal_size_bytes = receipt.journal.bytes.len();

    // Estimate memory usage based on proof size and execution complexity
    let memory_usage_mb = estimate_memory_usage(&receipt, proof_generation_time);

    let metrics = TestMetrics {
        proof_generation_time,
        verification_time,
        memory_usage_mb,
        proof_size_bytes,
        journal_size_bytes,
    };

    Ok((receipt, metrics))
}

/// Estimate memory usage based on proof characteristics
fn estimate_memory_usage(receipt: &Receipt, generation_time: Duration) -> u64 {
    // Base memory for RISC Zero runtime
    let base_memory_mb = 256;

    // Additional memory based on proof complexity
    let proof_complexity_factor = receipt.journal.bytes.len() as f64 / 1000.0; // KB to complexity factor
    let time_factor = generation_time.as_secs() as f64 / 10.0; // Longer time suggests more memory usage

    // Estimate memory usage (rough approximation)
    let estimated_additional_mb = (proof_complexity_factor * 10.0) + (time_factor * 5.0);

    base_memory_mb + estimated_additional_mb as u64
}

/// Verify a RISC Zero receipt
pub fn verify_receipt(receipt: &Receipt) -> TestResult<PaymentInstructionOutput> {
    receipt.verify(METHOD_ID)?;
    let output: PaymentInstructionOutput = receipt.journal.decode()?;
    Ok(output)
}

/// Generate proof and verify it's valid
pub fn generate_and_verify_proof(
    input: &PaymentInstructionInput,
    config: &TestConfig,
) -> TestResult<(PaymentInstructionOutput, TestMetrics)> {
    let (receipt, metrics) = generate_proof(input, config)?;
    let output = verify_receipt(&receipt)?;
    Ok((output, metrics))
}

/// Test that proof generation fails for invalid input
pub fn expect_proof_failure(input: &PaymentInstructionInput, config: &TestConfig) -> TestResult<()> {
    match generate_proof(input, config) {
        Ok(_) => Err(anyhow::anyhow!(
            "Expected proof generation to fail, but it succeeded"
        )),
        Err(_) => Ok(()),
    }
}

/// Save input to temporary file for CLI testing
pub fn save_input_to_temp_file(input: &PaymentInstructionInput) -> TestResult<NamedTempFile> {
    let temp_file = NamedTempFile::new()?;
    let json = serde_json::to_string_pretty(input)?;
    fs::write(temp_file.path(), json)?;
    Ok(temp_file)
}

/// Load input from file
pub fn load_input_from_file(path: &str) -> TestResult<PaymentInstructionInput> {
    let content = fs::read_to_string(path)?;
    let input: PaymentInstructionInput = serde_json::from_str(&content)?;
    Ok(input)
}

/// Compare two PaymentInstructionOutput structs for equality
pub fn assert_outputs_equal(expected: &PaymentInstructionOutput, actual: &PaymentInstructionOutput) {
    assert_eq!(expected.root, actual.root, "Root mismatch");
    assert_eq!(
        expected.debtor_hash, actual.debtor_hash,
        "Debtor hash mismatch"
    );
    assert_eq!(
        expected.creditor_hash, actual.creditor_hash,
        "Creditor hash mismatch"
    );
    assert_eq!(
        expected.min_amount_milli, actual.min_amount_milli,
        "Min amount mismatch"
    );
    assert_eq!(
        expected.max_amount_milli, actual.max_amount_milli,
        "Max amount mismatch"
    );
    assert_eq!(
        expected.currency_hash, actual.currency_hash,
        "Currency hash mismatch"
    );
    assert_eq!(expected.expiry, actual.expiry, "Expiry mismatch");
}

/// Benchmark proof generation for multiple inputs
pub fn benchmark_proof_generation(
    inputs: &[PaymentInstructionInput],
    config: &TestConfig,
) -> TestResult<Vec<TestMetrics>> {
    let mut metrics = Vec::new();

    for input in inputs {
        let (_, metric) = generate_proof(input, config)?;
        metrics.push(metric);
    }

    Ok(metrics)
}

/// Calculate statistics from test metrics
pub fn calculate_metrics_stats(metrics: &[TestMetrics]) -> MetricsStats {
    if metrics.is_empty() {
        return MetricsStats::default();
    }

    let proof_times: Vec<Duration> = metrics.iter().map(|m| m.proof_generation_time).collect();
    let verify_times: Vec<Duration> = metrics.iter().map(|m| m.verification_time).collect();
    let proof_sizes: Vec<usize> = metrics.iter().map(|m| m.proof_size_bytes).collect();

    MetricsStats {
        avg_proof_time: avg_duration(&proof_times),
        min_proof_time: *proof_times.iter().min().unwrap(),
        max_proof_time: *proof_times.iter().max().unwrap(),
        avg_verify_time: avg_duration(&verify_times),
        min_verify_time: *verify_times.iter().min().unwrap(),
        max_verify_time: *verify_times.iter().max().unwrap(),
        avg_proof_size: proof_sizes.iter().sum::<usize>() / proof_sizes.len(),
        min_proof_size: *proof_sizes.iter().min().unwrap(),
        max_proof_size: *proof_sizes.iter().max().unwrap(),
    }
}

#[derive(Debug, Clone, Default)]
pub struct MetricsStats {
    pub avg_proof_time: Duration,
    pub min_proof_time: Duration,
    pub max_proof_time: Duration,
    pub avg_verify_time: Duration,
    pub min_verify_time: Duration,
    pub max_verify_time: Duration,
    pub avg_proof_size: usize,
    pub min_proof_size: usize,
    pub max_proof_size: usize,
}

fn avg_duration(durations: &[Duration]) -> Duration {
    let total_nanos: u128 = durations.iter().map(|d| d.as_nanos()).sum();
    Duration::from_nanos((total_nanos / durations.len() as u128) as u64)
}

/// Create a test configuration for different scenarios
pub fn create_test_config(scenario: TestScenario) -> TestConfig {
    match scenario {
        TestScenario::Fast => TestConfig {
            enable_logging: false,
            proof_timeout_secs: 60,
            max_memory_mb: 1024,
        },
        TestScenario::Standard => TestConfig::default(),
        TestScenario::Stress => TestConfig {
            enable_logging: true,
            proof_timeout_secs: 600,
            max_memory_mb: 4096,
        },
    }
}

#[derive(Debug, Clone, Copy)]
pub enum TestScenario {
    Fast,
    Standard,
    Stress,
}

/// Assert that metrics meet performance requirements
pub fn assert_performance_requirements(
    metrics: &TestMetrics,
    requirements: &PerformanceRequirements,
) {
    assert!(
        metrics.proof_generation_time <= requirements.max_proof_time,
        "Proof generation took {:?}, expected <= {:?}",
        metrics.proof_generation_time,
        requirements.max_proof_time
    );

    assert!(
        metrics.verification_time <= requirements.max_verify_time,
        "Verification took {:?}, expected <= {:?}",
        metrics.verification_time,
        requirements.max_verify_time
    );

    assert!(
        metrics.proof_size_bytes <= requirements.max_proof_size,
        "Proof size was {} bytes, expected <= {} bytes",
        metrics.proof_size_bytes,
        requirements.max_proof_size
    );
}

#[derive(Debug, Clone)]
pub struct PerformanceRequirements {
    pub max_proof_time: Duration,
    pub max_verify_time: Duration,
    pub max_proof_size: usize,
    pub max_memory_mb: u64,
}

impl Default for PerformanceRequirements {
    fn default() -> Self {
        Self {
            max_proof_time: Duration::from_secs(90),
            max_verify_time: Duration::from_millis(100),
            max_proof_size: 2 * 1024 * 1024,
            max_memory_mb: 2048,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::payment_instruction_generator::PaymentInstructionGenerator;

    #[test]
    fn test_create_test_config() {
        let fast_config = create_test_config(TestScenario::Fast);
        assert_eq!(fast_config.proof_timeout_secs, 60);
        assert_eq!(fast_config.max_memory_mb, 1024);

        let stress_config = create_test_config(TestScenario::Stress);
        assert_eq!(stress_config.proof_timeout_secs, 600);
        assert_eq!(stress_config.max_memory_mb, 4096);
    }

    #[test]
    fn test_save_and_load_input() {
        let mut generator = PaymentInstructionGenerator::new();
        let input = generator.generate_valid_input();

        let temp_file = save_input_to_temp_file(&input).unwrap();
        let loaded_input = load_input_from_file(temp_file.path().to_str().unwrap()).unwrap();

        assert_eq!(input.debtor_data, loaded_input.debtor_data);
        assert_eq!(input.creditor_data, loaded_input.creditor_data);
        assert_eq!(input.amount_value, loaded_input.amount_value);
    }

    #[test]
    fn test_metrics_stats_calculation() {
        let metrics = vec![
            TestMetrics {
                proof_generation_time: Duration::from_millis(100),
                verification_time: Duration::from_millis(10),
                memory_usage_mb: 100,
                proof_size_bytes: 1000,
                journal_size_bytes: 100,
            },
            TestMetrics {
                proof_generation_time: Duration::from_millis(200),
                verification_time: Duration::from_millis(20),
                memory_usage_mb: 200,
                proof_size_bytes: 2000,
                journal_size_bytes: 200,
            },
        ];

        let stats = calculate_metrics_stats(&metrics);
        assert_eq!(stats.avg_proof_time, Duration::from_millis(150));
        assert_eq!(stats.min_proof_time, Duration::from_millis(100));
        assert_eq!(stats.max_proof_time, Duration::from_millis(200));
        assert_eq!(stats.avg_proof_size, 1500);
    }

    #[test]
    fn test_performance_requirements() {
        let metrics = TestMetrics {
            proof_generation_time: Duration::from_millis(50),
            verification_time: Duration::from_millis(5),
            memory_usage_mb: 100,
            proof_size_bytes: 500,
            journal_size_bytes: 50,
        };

        let requirements = PerformanceRequirements::default();
        assert_performance_requirements(&metrics, &requirements);
    }
}
