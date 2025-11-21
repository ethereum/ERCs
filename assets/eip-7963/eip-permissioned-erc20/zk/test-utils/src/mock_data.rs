use crate::crypto_utils::{canonicalize_json, keccak256};
use crate::payment_instruction_generator::{PaymentInstructionInput, PaymentInstructionOutput};
use rand::Rng;

/// Mock data for testing various scenarios
pub struct MockData;

impl MockData {
    /// Create a simple valid input for quick testing
    pub fn simple_valid_input() -> PaymentInstructionInput {
        let debtor_data = r#"{"Nm": "Alice Corp", "PstlAdr": {"Ctry": "US"}}"#.to_string();
        let creditor_data = r#"{"Nm": "Bob Ltd", "PstlAdr": {"Ctry": "US"}}"#.to_string();
        let currency = "USD".to_string();
        let execution_date = "2024-12-31".to_string();

        // Compute hashes correctly from the actual data
        let debtor_hash = keccak256(canonicalize_json(&debtor_data).as_bytes());
        let creditor_hash = keccak256(canonicalize_json(&creditor_data).as_bytes());
        let currency_hash = keccak256(currency.as_bytes());

        PaymentInstructionInput {
            root: [1u8; 32],
            debtor_hash,
            creditor_hash,
            min_amount_milli: 1000,
            max_amount_milli: 2000,
            currency_hash,
            expiry: 20241231,
            debtor_data,
            creditor_data,
            amount_value: 1500,
            currency,
            execution_date,
            debtor_proof_siblings: vec![],
            debtor_proof_directions: vec![],
            creditor_proof_siblings: vec![],
            creditor_proof_directions: vec![],
            amount_proof_siblings: vec![],
            amount_proof_directions: vec![],
            currency_proof_siblings: vec![],
            currency_proof_directions: vec![],
            expiry_proof_siblings: vec![],
            expiry_proof_directions: vec![],
        }
    }

    /// Create expected output for simple valid input
    pub fn simple_valid_output() -> PaymentInstructionOutput {
        let input = Self::simple_valid_input();
        PaymentInstructionOutput {
            root: input.root,
            debtor_hash: input.debtor_hash,
            creditor_hash: input.creditor_hash,
            min_amount_milli: input.min_amount_milli,
            max_amount_milli: input.max_amount_milli,
            currency_hash: input.currency_hash,
            expiry: input.expiry,
        }
    }

    /// Create input with malformed JSON
    pub fn malformed_json_input() -> PaymentInstructionInput {
        let mut input = Self::simple_valid_input();
        input.debtor_data = r#"{"Nm": "Alice", "PstlAdr": {"Ctry": 123"#.to_string(); // Missing closing brace
        input
    }

    /// Create input with empty strings
    pub fn empty_strings_input() -> PaymentInstructionInput {
        let mut input = Self::simple_valid_input();
        input.debtor_data = "".to_string();
        input.creditor_data = "".to_string();
        input.currency = "".to_string();
        input.execution_date = "".to_string();
        input
    }

    /// Create input with very large amounts
    pub fn large_amounts_input() -> PaymentInstructionInput {
        let mut input = Self::simple_valid_input();
        input.amount_value = u64::MAX - 1;
        input.min_amount_milli = u64::MAX - 2;
        input.max_amount_milli = u64::MAX;
        input
    }

    /// Create input with zero amounts
    pub fn zero_amounts_input() -> PaymentInstructionInput {
        let mut input = Self::simple_valid_input();
        input.amount_value = 0;
        input.min_amount_milli = 0;
        input.max_amount_milli = 0;
        input
    }

    /// Create input with special characters
    pub fn special_characters_input() -> PaymentInstructionInput {
        let mut input = Self::simple_valid_input();
        input.debtor_data =
            r#"{"Nm": "Alice!@#$%^&*()", "PstlAdr": {"Ctry": "123-456-789"}}"#.to_string();
        input.creditor_data =
            r#"{"Nm": "Bob<>?:\"{}|", "PstlAdr": {"Ctry": "987_654_321"}}"#.to_string();
        input.currency = "US$".to_string();
        input
    }

    /// Create input with unicode characters
    pub fn unicode_input() -> PaymentInstructionInput {
        let mut input = Self::simple_valid_input();
        input.debtor_data =
            r#"{"Nm": "José María García-López", "PstlAdr": {"Ctry": "ES1234567890"}}"#.to_string();
        input.creditor_data =
            r#"{"Nm": "李小明", "PstlAdr": {"Ctry": "CN9876543210"}}"#.to_string();
        input.currency = "€".to_string();
        input
    }

    /// Create input with very long strings
    pub fn long_strings_input() -> PaymentInstructionInput {
        let mut input = Self::simple_valid_input();
        let long_name = "A".repeat(1000);
        input.debtor_data = format!(r#"{{"Nm": "{}", "PstlAdr": {{"Ctry": "US"}}}}"#, long_name);
        input.creditor_data = format!(r#"{{"Nm": "{}", "PstlAdr": {{"Ctry": "US"}}}}"#, long_name);
        input
    }

    /// Create input with future expiry date
    pub fn future_expiry_input() -> PaymentInstructionInput {
        let mut input = Self::simple_valid_input();
        input.execution_date = "2099-12-31".to_string();
        input.expiry = 20991231;
        input
    }

    /// Create input with past expiry date
    pub fn past_expiry_input() -> PaymentInstructionInput {
        let mut input = Self::simple_valid_input();
        input.execution_date = "2020-01-01".to_string();
        input.expiry = 20200101;
        input
    }

    /// Create input with invalid date format
    pub fn invalid_date_format_input() -> PaymentInstructionInput {
        let mut input = Self::simple_valid_input();
        input.execution_date = "2024-12-31".to_string(); // Wrong format (should be YYYY-MM-DD)
        input
    }

    /// Create input with mismatched hashes
    pub fn mismatched_hashes_input() -> PaymentInstructionInput {
        let mut input = Self::simple_valid_input();
        input.debtor_hash = [0u8; 32]; // Wrong hash
        input.creditor_hash = [255u8; 32]; // Wrong hash
        input.currency_hash = [128u8; 32]; // Wrong hash
        input
    }

    /// Create input with corrupted Merkle proofs
    pub fn corrupted_merkle_proofs_input() -> PaymentInstructionInput {
        let mut input = Self::simple_valid_input();
        input.debtor_proof_siblings = vec![[0u8; 32], [255u8; 32]];
        input.debtor_proof_directions = vec![0, 1];
        input.creditor_proof_siblings = vec![[128u8; 32]];
        input.creditor_proof_directions = vec![1];
        input
    }

    /// Create a batch of random inputs for stress testing
    pub fn random_batch(count: usize) -> Vec<PaymentInstructionInput> {
        let mut rng = rand::thread_rng();
        (0..count)
            .map(|i| {
                let mut input = Self::simple_valid_input();
                input.debtor_data = format!(
                    r#"{{"Nm": "Debtor{}", "PstlAdr": {{"Ctry": "{}"}}}}"#,
                    i,
                    rng.gen::<u32>()
                );
                input.creditor_data = format!(
                    r#"{{"Nm": "Creditor{}", "PstlAdr": {{"Ctry": "{}"}}}}"#,
                    i,
                    rng.gen::<u32>()
                );
                input.amount_value = rng.gen_range(1..1000000);
                input.min_amount_milli = input.amount_value.saturating_sub(100);
                input.max_amount_milli = input.amount_value + 100;
                input.expiry = rng.gen_range(20240101..20991231);
                input.execution_date = input.expiry.to_string();

                // Randomize root and hashes
                rng.fill(&mut input.root);
                rng.fill(&mut input.debtor_hash);
                rng.fill(&mut input.creditor_hash);
                rng.fill(&mut input.currency_hash);

                input
            })
            .collect()
    }

    /// Create inputs that should trigger different error conditions
    pub fn error_cases() -> Vec<(&'static str, PaymentInstructionInput)> {
        vec![
            ("malformed_json", Self::malformed_json_input()),
            ("empty_strings", Self::empty_strings_input()),
            ("zero_amounts", Self::zero_amounts_input()),
            ("invalid_date_format", Self::invalid_date_format_input()),
            ("mismatched_hashes", Self::mismatched_hashes_input()),
            (
                "corrupted_merkle_proofs",
                Self::corrupted_merkle_proofs_input(),
            ),
        ]
    }

    /// Create inputs for boundary testing
    pub fn boundary_cases() -> Vec<(&'static str, PaymentInstructionInput)> {
        vec![
            ("large_amounts", Self::large_amounts_input()),
            ("long_strings", Self::long_strings_input()),
            ("future_expiry", Self::future_expiry_input()),
            ("past_expiry", Self::past_expiry_input()),
            ("special_characters", Self::special_characters_input()),
            ("unicode", Self::unicode_input()),
        ]
    }

    /// Create a comprehensive test suite
    pub fn comprehensive_test_suite() -> Vec<(&'static str, PaymentInstructionInput)> {
        let mut suite = vec![("simple_valid", Self::simple_valid_input())];
        suite.extend(Self::error_cases());
        suite.extend(Self::boundary_cases());
        suite
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_simple_valid_input() {
        let input = MockData::simple_valid_input();
        assert!(!input.debtor_data.is_empty());
        assert!(!input.creditor_data.is_empty());
        assert!(!input.currency.is_empty());
        assert!(input.amount_value >= input.min_amount_milli);
        assert!(input.amount_value <= input.max_amount_milli);
    }

    #[test]
    fn test_simple_valid_output() {
        let output = MockData::simple_valid_output();
        let input = MockData::simple_valid_input();
        assert_eq!(output.root, input.root);
        assert_eq!(output.debtor_hash, input.debtor_hash);
        assert_eq!(output.creditor_hash, input.creditor_hash);
    }

    #[test]
    fn test_error_cases() {
        let cases = MockData::error_cases();
        assert!(!cases.is_empty());

        for (name, input) in cases {
            match name {
                "empty_strings" => {
                    assert!(input.debtor_data.is_empty());
                    assert!(input.creditor_data.is_empty());
                    assert!(input.currency.is_empty());
                }
                "zero_amounts" => {
                    assert_eq!(input.amount_value, 0);
                    assert_eq!(input.min_amount_milli, 0);
                    assert_eq!(input.max_amount_milli, 0);
                }
                "mismatched_hashes" => {
                    assert_eq!(input.debtor_hash, [0u8; 32]);
                    assert_eq!(input.creditor_hash, [255u8; 32]);
                    assert_eq!(input.currency_hash, [128u8; 32]);
                }
                _ => {} // Other cases are valid for this test
            }
        }
    }

    #[test]
    fn test_boundary_cases() {
        let cases = MockData::boundary_cases();
        assert!(!cases.is_empty());

        for (name, input) in cases {
            match name {
                "large_amounts" => {
                    assert!(input.amount_value > 1000000);
                }
                "long_strings" => {
                    assert!(input.debtor_data.len() > 500);
                    assert!(input.creditor_data.len() > 500);
                }
                "unicode" => {
                    assert!(input.debtor_data.contains("José"));
                    assert!(input.creditor_data.contains("李"));
                    assert_eq!(input.currency, "€");
                }
                _ => {} // Other cases are valid for this test
            }
        }
    }

    #[test]
    fn test_random_batch() {
        let batch = MockData::random_batch(10);
        assert_eq!(batch.len(), 10);

        // Verify all inputs are different
        for i in 0..batch.len() {
            for j in i + 1..batch.len() {
                assert_ne!(batch[i].debtor_data, batch[j].debtor_data);
                assert_ne!(batch[i].creditor_data, batch[j].creditor_data);
            }
        }
    }

    #[test]
    fn test_comprehensive_test_suite() {
        let suite = MockData::comprehensive_test_suite();
        assert!(suite.len() > 10); // Should have many test cases

        // Verify we have the expected categories
        let names: Vec<&str> = suite.iter().map(|(name, _)| *name).collect();
        assert!(names.contains(&"simple_valid"));
        assert!(names.contains(&"malformed_json"));
        assert!(names.contains(&"unicode"));
        assert!(names.contains(&"large_amounts"));
    }
}
