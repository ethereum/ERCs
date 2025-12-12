use crate::crypto_utils::{canonicalize_json, keccak256};
use crate::merkle_tree::MerkleTree;
use rand::Rng;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct PaymentInstructionInput {
    // Public inputs (will be committed)
    pub root: [u8; 32],
    pub debtor_hash: [u8; 32],   // Hash of Dbtr object
    pub creditor_hash: [u8; 32], // Hash of Cdtr object
    pub min_amount_milli: u64,
    pub max_amount_milli: u64,
    pub currency_hash: [u8; 32],
    pub expiry: u64, // ReqdExctnDt as YYYYMMDD

    // Private inputs (for proof generation only)
    pub debtor_data: String,    // JSON string of Dbtr object
    pub creditor_data: String,  // JSON string of Cdtr object
    pub amount_value: u64,      // InstdAmt.Value in milli units
    pub currency: String,       // InstdAmt.Ccy
    pub execution_date: String, // ReqdExctnDt as string

    // Merkle proof data
    pub debtor_proof_siblings: Vec<[u8; 32]>,
    pub debtor_proof_directions: Vec<u8>,
    pub creditor_proof_siblings: Vec<[u8; 32]>,
    pub creditor_proof_directions: Vec<u8>,
    pub amount_proof_siblings: Vec<[u8; 32]>,
    pub amount_proof_directions: Vec<u8>,
    pub currency_proof_siblings: Vec<[u8; 32]>,
    pub currency_proof_directions: Vec<u8>,
    pub expiry_proof_siblings: Vec<[u8; 32]>,
    pub expiry_proof_directions: Vec<u8>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct PaymentInstructionOutput {
    pub root: [u8; 32],
    pub debtor_hash: [u8; 32],
    pub creditor_hash: [u8; 32],
    pub min_amount_milli: u64,
    pub max_amount_milli: u64,
    pub currency_hash: [u8; 32],
    pub expiry: u64,
}

pub struct PaymentInstructionGenerator {
    rng: rand::rngs::ThreadRng,
}

impl PaymentInstructionGenerator {
    pub fn new() -> Self {
        Self {
            rng: rand::thread_rng(),
        }
    }

    /// Generate a valid payment instruction input with proper Merkle proofs
    pub fn generate_valid_input(&mut self) -> PaymentInstructionInput {
        // Generate test data
        let debtor_data = format!(
            r#"{{"name": "Alice Smith", "account": "{}"}}"#,
            self.rng.gen::<u32>()
        );
        let creditor_data = format!(
            r#"{{"name": "Bob Jones", "account": "{}"}}"#,
            self.rng.gen::<u32>()
        );
        let currency = "USD".to_string();
        let amount_value: u64 = self.rng.gen_range(1000..10000);
        let min_amount_milli = amount_value - 100;
        let max_amount_milli = amount_value + 100;
        let execution_date = "20241231".to_string();
        let expiry = execution_date.parse::<u64>().unwrap();

        // Compute hashes
        let debtor_hash = keccak256(canonicalize_json(&debtor_data).as_bytes());
        let creditor_hash = keccak256(canonicalize_json(&creditor_data).as_bytes());
        let currency_hash = keccak256(currency.as_bytes());

        // Create Merkle tree with all fields
        let amount_bytes = amount_value.to_be_bytes();
        let expiry_bytes = expiry.to_be_bytes();

        let tree_data = vec![
            (debtor_hash.as_slice(), 1u8),
            (creditor_hash.as_slice(), 2u8),
            (amount_bytes.as_slice(), 3u8),
            (currency_hash.as_slice(), 4u8),
            (expiry_bytes.as_slice(), 5u8),
        ];

        let tree = MerkleTree::new(tree_data);
        let root = tree.root();

        // Generate proofs for each field
        let debtor_proof = tree.generate_proof(0).unwrap();
        let creditor_proof = tree.generate_proof(1).unwrap();
        let amount_proof = tree.generate_proof(2).unwrap();
        let currency_proof = tree.generate_proof(3).unwrap();
        let expiry_proof = tree.generate_proof(4).unwrap();

        PaymentInstructionInput {
            root,
            debtor_hash,
            creditor_hash,
            min_amount_milli,
            max_amount_milli,
            currency_hash,
            expiry,
            debtor_data,
            creditor_data,
            amount_value,
            currency,
            execution_date,
            debtor_proof_siblings: debtor_proof.siblings,
            debtor_proof_directions: debtor_proof.directions,
            creditor_proof_siblings: creditor_proof.siblings,
            creditor_proof_directions: creditor_proof.directions,
            amount_proof_siblings: amount_proof.siblings,
            amount_proof_directions: amount_proof.directions,
            currency_proof_siblings: currency_proof.siblings,
            currency_proof_directions: currency_proof.directions,
            expiry_proof_siblings: expiry_proof.siblings,
            expiry_proof_directions: expiry_proof.directions,
        }
    }

    /// Generate an invalid input with wrong debtor hash
    pub fn generate_invalid_debtor_hash(&mut self) -> PaymentInstructionInput {
        let mut input = self.generate_valid_input();
        input.debtor_hash = [0u8; 32]; // Wrong hash
        input
    }

    /// Generate an invalid input with wrong creditor hash
    pub fn generate_invalid_creditor_hash(&mut self) -> PaymentInstructionInput {
        let mut input = self.generate_valid_input();
        input.creditor_hash = [0u8; 32]; // Wrong hash
        input
    }

    /// Generate an invalid input with amount below minimum
    pub fn generate_amount_below_minimum(&mut self) -> PaymentInstructionInput {
        let mut input = self.generate_valid_input();
        input.amount_value = input.min_amount_milli - 1;
        input
    }

    /// Generate an invalid input with amount above maximum
    pub fn generate_amount_above_maximum(&mut self) -> PaymentInstructionInput {
        let mut input = self.generate_valid_input();
        input.amount_value = input.max_amount_milli + 1;
        input
    }

    /// Generate an invalid input with wrong currency hash
    pub fn generate_invalid_currency_hash(&mut self) -> PaymentInstructionInput {
        let mut input = self.generate_valid_input();
        input.currency_hash = [0u8; 32]; // Wrong hash
        input
    }

    /// Generate an invalid input with wrong expiry
    pub fn generate_invalid_expiry(&mut self) -> PaymentInstructionInput {
        let mut input = self.generate_valid_input();
        input.expiry = 12345678; // Wrong expiry
        input
    }

    /// Generate an invalid input with corrupted Merkle proof
    pub fn generate_invalid_merkle_proof(&mut self) -> PaymentInstructionInput {
        let mut input = self.generate_valid_input();
        if !input.debtor_proof_siblings.is_empty() {
            input.debtor_proof_siblings[0] = [0u8; 32]; // Corrupt proof
        }
        input
    }

    /// Generate a batch of test inputs for property-based testing
    pub fn generate_batch(&mut self, count: usize) -> Vec<PaymentInstructionInput> {
        (0..count).map(|_| self.generate_valid_input()).collect()
    }

    /// Generate edge case inputs
    pub fn generate_edge_cases(&mut self) -> Vec<PaymentInstructionInput> {
        vec![
            self.generate_minimal_amount(),
            self.generate_maximal_amount(),
            self.generate_single_character_data(),
            self.generate_large_data(),
            self.generate_unicode_data(),
        ]
    }

    fn generate_minimal_amount(&mut self) -> PaymentInstructionInput {
        let mut input = self.generate_valid_input();
        input.amount_value = 1;
        input.min_amount_milli = 1;
        input.max_amount_milli = 1;
        self.regenerate_merkle_proofs(&mut input);
        input
    }

    fn generate_maximal_amount(&mut self) -> PaymentInstructionInput {
        let mut input = self.generate_valid_input();
        input.amount_value = u64::MAX - 1000;
        input.min_amount_milli = u64::MAX - 1000;
        input.max_amount_milli = u64::MAX - 1000;
        self.regenerate_merkle_proofs(&mut input);
        input
    }

    fn generate_single_character_data(&mut self) -> PaymentInstructionInput {
        let mut input = self.generate_valid_input();
        input.debtor_data = r#"{"n":"A"}"#.to_string();
        input.creditor_data = r#"{"n":"B"}"#.to_string();
        input.currency = "X".to_string();
        self.regenerate_merkle_proofs(&mut input);
        input
    }

    fn generate_large_data(&mut self) -> PaymentInstructionInput {
        let mut input = self.generate_valid_input();
        let large_string = "A".repeat(1000);
        input.debtor_data = format!(r#"{{"name": "{}"}}"#, large_string);
        input.creditor_data = format!(r#"{{"name": "{}"}}"#, large_string);
        self.regenerate_merkle_proofs(&mut input);
        input
    }

    fn generate_unicode_data(&mut self) -> PaymentInstructionInput {
        let mut input = self.generate_valid_input();
        input.debtor_data =
            r#"{"name": "José María García-López", "account": "ES1234567890"}"#.to_string();
        input.creditor_data = r#"{"name": "李小明", "account": "CN9876543210"}"#.to_string();
        input.currency = "€".to_string();
        self.regenerate_merkle_proofs(&mut input);
        input
    }

    pub fn regenerate_merkle_proofs(&mut self, input: &mut PaymentInstructionInput) {
        // Recompute hashes
        input.debtor_hash = keccak256(canonicalize_json(&input.debtor_data).as_bytes());
        input.creditor_hash = keccak256(canonicalize_json(&input.creditor_data).as_bytes());
        input.currency_hash = keccak256(input.currency.as_bytes());

        // Recreate Merkle tree
        let amount_bytes = input.amount_value.to_be_bytes();
        let expiry_bytes = input.expiry.to_be_bytes();

        let tree_data = vec![
            (input.debtor_hash.as_slice(), 1u8),
            (input.creditor_hash.as_slice(), 2u8),
            (amount_bytes.as_slice(), 3u8),
            (input.currency_hash.as_slice(), 4u8),
            (expiry_bytes.as_slice(), 5u8),
        ];

        let tree = MerkleTree::new(tree_data);
        input.root = tree.root();

        // Regenerate proofs
        let debtor_proof = tree.generate_proof(0).unwrap();
        let creditor_proof = tree.generate_proof(1).unwrap();
        let amount_proof = tree.generate_proof(2).unwrap();
        let currency_proof = tree.generate_proof(3).unwrap();
        let expiry_proof = tree.generate_proof(4).unwrap();

        input.debtor_proof_siblings = debtor_proof.siblings;
        input.debtor_proof_directions = debtor_proof.directions;
        input.creditor_proof_siblings = creditor_proof.siblings;
        input.creditor_proof_directions = creditor_proof.directions;
        input.amount_proof_siblings = amount_proof.siblings;
        input.amount_proof_directions = amount_proof.directions;
        input.currency_proof_siblings = currency_proof.siblings;
        input.currency_proof_directions = currency_proof.directions;
        input.expiry_proof_siblings = expiry_proof.siblings;
        input.expiry_proof_directions = expiry_proof.directions;
    }

    /// Generate a valid payment instruction input using proper ISO 20022 format
    pub fn generate_payment_instruction_input(&mut self) -> PaymentInstructionInput {
        // Generate realistic payment instruction data based on sample files
        let debtor_data = r#"{
            "Nm": "Acme Corporation",
            "PstlAdr": {
                "Ctry": "US",
                "AdrLine": ["1 Acme Way", "Metropolis, NY 10001"]
            }
        }"#
        .to_string();

        let creditor_data = r#"{
            "Nm": "Bob's Supplies",
            "PstlAdr": {
                "Ctry": "US",
                "AdrLine": ["500 Supplier Road", "Gotham, NY 10002"]
            }
        }"#
        .to_string();

        let currency = "USD".to_string();
        let amount_value: u64 = 125075; // 1250.75 in milli units
        let min_amount_milli = 100000; // 1000.00 minimum
        let max_amount_milli = 200000; // 2000.00 maximum
        let execution_date = "2025-04-30".to_string();
        let expiry = 20250430u64; // Convert to YYYYMMDD format

        // Compute hashes
        let debtor_hash = keccak256(canonicalize_json(&debtor_data).as_bytes());
        let creditor_hash = keccak256(canonicalize_json(&creditor_data).as_bytes());
        let currency_hash = keccak256(currency.as_bytes());

        // Create Merkle tree with all fields
        let amount_bytes = amount_value.to_be_bytes();
        let expiry_bytes = expiry.to_be_bytes();

        let tree_data = vec![
            (debtor_hash.as_slice(), 1u8),
            (creditor_hash.as_slice(), 2u8),
            (amount_bytes.as_slice(), 3u8),
            (currency_hash.as_slice(), 4u8),
            (expiry_bytes.as_slice(), 5u8),
        ];

        let tree = MerkleTree::new(tree_data);
        let root = tree.root();

        // Generate proofs for each field
        let debtor_proof = tree.generate_proof(0).unwrap();
        let creditor_proof = tree.generate_proof(1).unwrap();
        let amount_proof = tree.generate_proof(2).unwrap();
        let currency_proof = tree.generate_proof(3).unwrap();
        let expiry_proof = tree.generate_proof(4).unwrap();

        PaymentInstructionInput {
            root,
            debtor_hash,
            creditor_hash,
            min_amount_milli,
            max_amount_milli,
            currency_hash,
            expiry,
            debtor_data,
            creditor_data,
            amount_value,
            currency,
            execution_date,
            debtor_proof_siblings: debtor_proof.siblings,
            debtor_proof_directions: debtor_proof.directions,
            creditor_proof_siblings: creditor_proof.siblings,
            creditor_proof_directions: creditor_proof.directions,
            amount_proof_siblings: amount_proof.siblings,
            amount_proof_directions: amount_proof.directions,
            currency_proof_siblings: currency_proof.siblings,
            currency_proof_directions: currency_proof.directions,
            expiry_proof_siblings: expiry_proof.siblings,
            expiry_proof_directions: expiry_proof.directions,
        }
    }

    /// Generate inputs from the actual sample files
    pub fn generate_all_samples(&mut self) -> Vec<(&'static str, PaymentInstructionInput)> {
        vec![
            ("usd_small", self.generate_usd_small_sample()),
            ("eur_large", self.generate_eur_large_sample()),
            ("sgd_mid", self.generate_sgd_mid_sample()),
        ]
    }

    /// Generate input from specific currency sample
    pub fn generate_from_samples(&mut self, currency: &str) -> Result<PaymentInstructionInput, String> {
        match currency {
            "USD" => Ok(self.generate_usd_small_sample()),
            "EUR" => Ok(self.generate_eur_large_sample()),
            "SGD" => Ok(self.generate_sgd_mid_sample()),
            _ => Err(format!("Unsupported currency: {}", currency)),
        }
    }

    fn generate_usd_small_sample(&mut self) -> PaymentInstructionInput {
        let debtor_data = r#"{
            "Nm": "Acme Corporation",
            "PstlAdr": {
                "Ctry": "US",
                "AdrLine": ["1 Acme Way", "Metropolis, NY 10001"]
            }
        }"#
        .to_string();

        let creditor_data = r#"{
            "Nm": "Bob's Supplies",
            "PstlAdr": {
                "Ctry": "US",
                "AdrLine": ["500 Supplier Road", "Gotham, NY 10002"]
            }
        }"#
        .to_string();

        self.create_payment_instruction_input(debtor_data, creditor_data, 125075, "USD", "2025-04-30")
    }

    fn generate_eur_large_sample(&mut self) -> PaymentInstructionInput {
        let debtor_data = r#"{
            "Nm": "Mega Industrie GmbH",
            "PstlAdr": {
                "Ctry": "DE",
                "AdrLine": ["Werkstraße 10", "10115 Berlin"]
            }
        }"#
        .to_string();

        let creditor_data = r#"{
            "Nm": "Alpine Components SA",
            "PstlAdr": {
                "Ctry": "FR",
                "AdrLine": ["1 Rue des Alpes", "74000 Annecy"]
            }
        }"#
        .to_string();

        self.create_payment_instruction_input(debtor_data, creditor_data, 5000000, "EUR", "2025-05-02")
    }

    fn generate_sgd_mid_sample(&mut self) -> PaymentInstructionInput {
        let debtor_data = r#"{
            "Nm": "Lion City Trading Pte Ltd",
            "PstlAdr": {
                "Ctry": "SG",
                "AdrLine": ["10 Marina Boulevard", "Unit 35-01"]
            }
        }"#
        .to_string();

        let creditor_data = r#"{
            "Nm": "Sunny Isles Imports",
            "PstlAdr": {
                "Ctry": "SG",
                "AdrLine": ["25 Changi South Ave 2", "Unit 03-00"]
            }
        }"#
        .to_string();

        self.create_payment_instruction_input(debtor_data, creditor_data, 123456, "SGD", "2025-04-29")
    }

    fn create_payment_instruction_input(
        &mut self,
        debtor_data: String,
        creditor_data: String,
        amount_milli: u64,
        currency: &str,
        exec_date: &str,
    ) -> PaymentInstructionInput {
        let currency = currency.to_string();
        let execution_date = exec_date.to_string();
        let min_amount_milli = amount_milli.saturating_sub(10000);
        let max_amount_milli = amount_milli + 10000;

        // Convert execution date to YYYYMMDD format
        let expiry = exec_date.replace("-", "").parse::<u64>().unwrap();

        // Compute hashes
        let debtor_hash = keccak256(canonicalize_json(&debtor_data).as_bytes());
        let creditor_hash = keccak256(canonicalize_json(&creditor_data).as_bytes());
        let currency_hash = keccak256(currency.as_bytes());

        // Create Merkle tree
        let amount_bytes = amount_milli.to_be_bytes();
        let expiry_bytes = expiry.to_be_bytes();

        let tree_data = vec![
            (debtor_hash.as_slice(), 1u8),
            (creditor_hash.as_slice(), 2u8),
            (amount_bytes.as_slice(), 3u8),
            (currency_hash.as_slice(), 4u8),
            (expiry_bytes.as_slice(), 5u8),
        ];

        let tree = MerkleTree::new(tree_data);
        let root = tree.root();

        // Generate proofs
        let debtor_proof = tree.generate_proof(0).unwrap();
        let creditor_proof = tree.generate_proof(1).unwrap();
        let amount_proof = tree.generate_proof(2).unwrap();
        let currency_proof = tree.generate_proof(3).unwrap();
        let expiry_proof = tree.generate_proof(4).unwrap();

        PaymentInstructionInput {
            root,
            debtor_hash,
            creditor_hash,
            min_amount_milli,
            max_amount_milli,
            currency_hash,
            expiry,
            debtor_data,
            creditor_data,
            amount_value: amount_milli,
            currency,
            execution_date,
            debtor_proof_siblings: debtor_proof.siblings,
            debtor_proof_directions: debtor_proof.directions,
            creditor_proof_siblings: creditor_proof.siblings,
            creditor_proof_directions: creditor_proof.directions,
            amount_proof_siblings: amount_proof.siblings,
            amount_proof_directions: amount_proof.directions,
            currency_proof_siblings: currency_proof.siblings,
            currency_proof_directions: currency_proof.directions,
            expiry_proof_siblings: expiry_proof.siblings,
            expiry_proof_directions: expiry_proof.directions,
        }
    }
}

impl Default for PaymentInstructionGenerator {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_valid_input() {
        let mut generator = PaymentInstructionGenerator::new();
        let input = generator.generate_valid_input();

        // Verify basic structure
        assert!(!input.debtor_data.is_empty());
        assert!(!input.creditor_data.is_empty());
        assert!(!input.currency.is_empty());
        assert!(input.amount_value >= input.min_amount_milli);
        assert!(input.amount_value <= input.max_amount_milli);

        // Verify hashes are computed correctly
        let expected_debtor_hash = keccak256(canonicalize_json(&input.debtor_data).as_bytes());
        assert_eq!(input.debtor_hash, expected_debtor_hash);

        let expected_creditor_hash = keccak256(canonicalize_json(&input.creditor_data).as_bytes());
        assert_eq!(input.creditor_hash, expected_creditor_hash);

        let expected_currency_hash = keccak256(input.currency.as_bytes());
        assert_eq!(input.currency_hash, expected_currency_hash);
    }

    #[test]
    fn test_generate_invalid_inputs() {
        let mut generator = PaymentInstructionGenerator::new();

        let invalid_debtor = generator.generate_invalid_debtor_hash();
        assert_eq!(invalid_debtor.debtor_hash, [0u8; 32]);

        let invalid_creditor = generator.generate_invalid_creditor_hash();
        assert_eq!(invalid_creditor.creditor_hash, [0u8; 32]);

        let below_min = generator.generate_amount_below_minimum();
        assert!(below_min.amount_value < below_min.min_amount_milli);

        let above_max = generator.generate_amount_above_maximum();
        assert!(above_max.amount_value > above_max.max_amount_milli);
    }

    #[test]
    fn test_generate_batch() {
        let mut generator = PaymentInstructionGenerator::new();
        let batch = generator.generate_batch(5);

        assert_eq!(batch.len(), 5);

        // Verify all inputs are different
        for i in 0..batch.len() {
            for j in i + 1..batch.len() {
                assert_ne!(batch[i].debtor_data, batch[j].debtor_data);
            }
        }
    }

    #[test]
    fn test_generate_edge_cases() {
        let mut generator = PaymentInstructionGenerator::new();
        let edge_cases = generator.generate_edge_cases();

        assert_eq!(edge_cases.len(), 5);

        // Test minimal amount case
        assert_eq!(edge_cases[0].amount_value, 1);
        assert_eq!(edge_cases[0].min_amount_milli, 1);
        assert_eq!(edge_cases[0].max_amount_milli, 1);

        // Test maximal amount case
        assert!(edge_cases[1].amount_value > 1000000);

        // Test single character data
        assert!(edge_cases[2].debtor_data.len() < 20);
        assert!(edge_cases[2].currency.len() == 1);

        // Test large data
        assert!(edge_cases[3].debtor_data.len() > 500);

        // Test unicode data
        assert!(edge_cases[4].debtor_data.contains("José"));
        assert!(edge_cases[4].creditor_data.contains("李"));
    }
}
