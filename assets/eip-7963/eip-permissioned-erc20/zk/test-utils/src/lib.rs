pub mod crypto_utils;
pub mod guest_logic;
pub mod integration;
pub mod merkle_tree;
pub mod mock_data;
pub mod payment_instruction_generator;
pub mod proof_validator;
pub mod test_helpers; // Simplified integration module

use anyhow;

// Re-export commonly used types
pub use methods::{METHOD_ELF, METHOD_ID};
pub use risc0_zkvm::{default_prover, ExecutorEnv, Receipt};

// Re-export integration functions
pub use integration::{
    run_all_integration_tests, test_crypto_integration, test_data_generation_integration,
    test_merkle_integration, test_proof_pipeline_integration,
};

// Common test result type
pub type TestResult<T> = Result<T, anyhow::Error>;

// Test configuration
#[derive(Debug, Clone)]
pub struct TestConfig {
    pub enable_logging: bool,
    pub proof_timeout_secs: u64,
    pub max_memory_mb: u64,
}

impl Default for TestConfig {
    fn default() -> Self {
        Self {
            enable_logging: false,
            proof_timeout_secs: 300, // 5 minutes
            max_memory_mb: 2048,     // 2GB
        }
    }
}

// Initialize test environment
pub fn init_test_env(config: TestConfig) {
    if config.enable_logging {
        tracing_subscriber::fmt().init();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_default() {
        let config = TestConfig::default();
        assert_eq!(config.proof_timeout_secs, 300);
        assert_eq!(config.max_memory_mb, 2048);
        assert!(!config.enable_logging);
    }
}
