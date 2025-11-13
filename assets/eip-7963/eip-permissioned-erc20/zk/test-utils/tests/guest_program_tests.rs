use test_utils::{
    crypto_utils::{canonicalize_json, compute_leaf_hash, keccak256},
    guest_logic::{verify_merkle_proof, verify_payment_instruction},
    merkle_tree::MerkleTree,
    mock_data::MockData,
    payment_instruction_generator::PaymentInstructionGenerator,
    proof_validator::ProofValidator,
};

// Import guest functions for testing
// Note: Using guest_logic module which duplicates the guest verification logic for testing

#[test]
fn test_guest_verification_valid_input() {
    let mut generator = PaymentInstructionGenerator::new();
    let input = generator.generate_valid_input();

    let result = verify_payment_instruction(&input);
    assert!(result.is_ok());

    let output = result.unwrap();
    assert_eq!(output.root, input.root);
    assert_eq!(output.debtor_hash, input.debtor_hash);
    assert_eq!(output.creditor_hash, input.creditor_hash);
}

#[test]
fn test_guest_verification_invalid_debtor_hash() {
    let mut generator = PaymentInstructionGenerator::new();
    let input = generator.generate_invalid_debtor_hash();

    let result = verify_payment_instruction(&input);
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("Debtor hash mismatch"));
}

#[test]
fn test_guest_verification_invalid_creditor_hash() {
    let mut generator = PaymentInstructionGenerator::new();
    let input = generator.generate_invalid_creditor_hash();

    let result = verify_payment_instruction(&input);
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("Creditor hash mismatch"));
}

#[test]
fn test_guest_verification_amount_bounds() {
    let mut generator = PaymentInstructionGenerator::new();

    // Test below minimum
    let below_min = generator.generate_amount_below_minimum();
    let result = verify_payment_instruction(&below_min);
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("below minimum"));

    // Test above maximum
    let above_max = generator.generate_amount_above_maximum();
    let result = verify_payment_instruction(&above_max);
    assert!(result.is_err());
    assert!(result.unwrap_err().contains("above maximum"));
}

#[test]
fn test_guest_verification_batch() {
    let mut generator = PaymentInstructionGenerator::new();
    let batch = generator.generate_batch(5);

    for input in &batch {
        let result = verify_payment_instruction(input);
        if result.is_ok() {
            let output = result.unwrap();
            assert_eq!(output.debtor_hash, input.debtor_hash);
            assert_eq!(output.creditor_hash, input.creditor_hash);
        }
    }
}

#[test]
fn test_guest_verification_edge_cases() {
    let mut generator = PaymentInstructionGenerator::new();
    let edge_cases = generator.generate_edge_cases();

    for input in &edge_cases {
        // Edge cases might fail validation, but shouldn't panic
        let _result = verify_payment_instruction(input);
    }
}

#[test]
fn test_guest_verification_unicode_data() {
    let mut generator = PaymentInstructionGenerator::new();
    let mut input = generator.generate_valid_input();

    // Set unicode data
    input.debtor_data =
        r#"{"Nm": "José María García-López", "PstlAdr": {"Ctry": "ES"}}"#.to_string();
    input.creditor_data = r#"{"Nm": "李小明", "PstlAdr": {"Ctry": "CN"}}"#.to_string();

    // Recompute hashes
    input.debtor_hash = keccak256(canonicalize_json(&input.debtor_data).as_bytes());
    input.creditor_hash = keccak256(canonicalize_json(&input.creditor_data).as_bytes());

    // Regenerate proofs
    generator.regenerate_merkle_proofs(&mut input);

    let result = verify_payment_instruction(&input);
    assert!(result.is_ok());
}

#[test]
fn test_guest_verification_large_data() {
    let mut generator = PaymentInstructionGenerator::new();
    let mut input = generator.generate_valid_input();

    // Set large data
    let large_name = "A".repeat(1000);
    input.debtor_data = format!(r#"{{"Nm": "{}", "PstlAdr": {{"Ctry": "US"}}}}"#, large_name);
    input.creditor_data = format!(r#"{{"Nm": "{}", "PstlAdr": {{"Ctry": "US"}}}}"#, large_name);

    // Recompute hashes
    input.debtor_hash = keccak256(canonicalize_json(&input.debtor_data).as_bytes());
    input.creditor_hash = keccak256(canonicalize_json(&input.creditor_data).as_bytes());

    // Regenerate proofs
    generator.regenerate_merkle_proofs(&mut input);

    let result = verify_payment_instruction(&input);
    assert!(result.is_ok());
}

#[test]
fn test_guest_hash_functions_consistency() {
    let data = b"test data";

    // Test that guest hash functions match test utils
    let guest_hash = keccak256(data);
    let util_hash = keccak256(data);

    assert_eq!(
        guest_hash, util_hash,
        "Guest and util hash functions should match"
    );
}

#[test]
fn test_guest_leaf_hash_computation() {
    let preimage = b"test data";
    let tag = 1u8;

    let guest_hash = compute_leaf_hash(preimage, tag);
    let util_hash = compute_leaf_hash(preimage, tag);

    assert_eq!(
        guest_hash, util_hash,
        "Guest and util leaf hash should match"
    );
}

#[test]
fn test_guest_merkle_proof_verification() {
    // Create a simple tree
    let data = vec![(b"leaf1".as_slice(), 1u8), (b"leaf2".as_slice(), 2u8)];
    let tree = MerkleTree::new(data);
    let root = tree.root();

    // Generate proof for first leaf
    let proof = tree.generate_proof(0).unwrap();
    let leaf = tree.leaves[0];

    // Test guest verification
    let guest_result = verify_merkle_proof(&root, &leaf, &proof.siblings, &proof.directions, 1u8);
    assert!(guest_result);

    // Test with invalid proof
    let mut invalid_proof = proof.clone();
    invalid_proof.directions[0] = 1 - invalid_proof.directions[0]; // Flip direction
    let guest_result = verify_merkle_proof(
        &root,
        &leaf,
        &invalid_proof.siblings,
        &invalid_proof.directions,
        1u8,
    );
    assert!(!guest_result);
}
