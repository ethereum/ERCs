use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct PaymentInstructionInput {
    // Public inputs (will be committed)
    pub root: [u8; 32],
    pub debtor_hash: [u8; 32],        // Hash of debtor data
    pub creditor_hash: [u8; 32],      // Hash of creditor data
    pub min_amount_milli: u64,
    pub max_amount_milli: u64,
    pub currency_hash: [u8; 32],
    pub expiry: u64,                  // Execution date as YYYYMMDD

    // Private inputs (for proof generation only)
    pub debtor_data: String,          // JSON string of debtor object
    pub creditor_data: String,        // JSON string of creditor object
    pub amount_value: u64,            // Amount in milli units
    pub currency: String,             // Currency code (ISO 4217)
    pub execution_date: String,       // Execution date as string

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

#[derive(Clone, Debug, Serialize)]
pub struct PaymentInstructionOutput {
    pub root: [u8; 32],
    pub debtor_hash: [u8; 32],
    pub creditor_hash: [u8; 32],
    pub min_amount_milli: u64,
    pub max_amount_milli: u64,
    pub currency_hash: [u8; 32],
    pub expiry: u64,
}

/// Canonicalize JSON string according to RFC 8785
pub fn canonicalize_json(input: &str) -> String {
    // For simplicity, we'll assume the input is already canonicalized
    // In a production implementation, you'd want proper JSON canonicalization
    input.to_string()
}

/// Compute Keccak256 hash using SHA256 as a substitute
pub fn keccak256(data: &[u8]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(data);
    let result = hasher.finalize();
    let mut output = [0u8; 32];
    output.copy_from_slice(&result);
    output
}

/// Simple Poseidon-like hash function using SHA256 for compatibility
pub fn poseidon_hash(left: &[u8; 32], right: &[u8; 32]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(left);
    hasher.update(right);
    let result = hasher.finalize();
    let mut output = [0u8; 32];
    output.copy_from_slice(&result);
    output
}

/// Verify Merkle proof
pub fn verify_merkle_proof(
    leaf: &[u8; 32],
    proof_siblings: &[[u8; 32]],
    proof_directions: &[u8],
    root: &[u8; 32],
) -> bool {
    let mut current = *leaf;
    
    for (sibling, direction) in proof_siblings.iter().zip(proof_directions.iter()) {
        current = if *direction == 0 {
            // Current is left, sibling is right
            poseidon_hash(&current, sibling)
        } else {
            // Current is right, sibling is left
            poseidon_hash(sibling, &current)
        };
    }
    
    current == *root
}

/// Compute leaf hash for a field with tag
pub fn compute_leaf_hash(preimage: &[u8], tag: u8) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(preimage);
    hasher.update(&[tag]);
    let result = hasher.finalize();
    let mut output = [0u8; 32];
    output.copy_from_slice(&result);
    output
}

/// Main verification logic (extracted for testing)
pub fn verify_payment_instruction(input: &PaymentInstructionInput) -> Result<PaymentInstructionOutput, String> {
    // 1. Verify debtor hash
    let canonical_debtor = canonicalize_json(&input.debtor_data);
    let computed_debtor_hash = keccak256(canonical_debtor.as_bytes());
    if computed_debtor_hash != input.debtor_hash {
        return Err("Debtor hash mismatch".to_string());
    }
    
    // 2. Verify creditor hash
    let canonical_creditor = canonicalize_json(&input.creditor_data);
    let computed_creditor_hash = keccak256(canonical_creditor.as_bytes());
    if computed_creditor_hash != input.creditor_hash {
        return Err("Creditor hash mismatch".to_string());
    }
    
    // 3. Verify currency hash
    let computed_currency_hash = keccak256(input.currency.as_bytes());
    if computed_currency_hash != input.currency_hash {
        return Err("Currency hash mismatch".to_string());
    }
    
    // 4. Verify amount is within bounds
    if input.amount_value < input.min_amount_milli {
        return Err("Amount below minimum".to_string());
    }
    if input.amount_value > input.max_amount_milli {
        return Err("Amount above maximum".to_string());
    }
    
    // 5. Verify expiry (convert date string to timestamp)
    let expiry_timestamp = input.execution_date.replace("-", "").parse::<u64>()
        .map_err(|_| "Invalid expiry date format".to_string())?;
    if expiry_timestamp != input.expiry {
        return Err("Expiry mismatch".to_string());
    }
    
    // 6. Compute leaf hashes and verify Merkle proofs
    let debtor_leaf = compute_leaf_hash(&computed_debtor_hash, 1);
    if !verify_merkle_proof(
        &debtor_leaf,
        &input.debtor_proof_siblings,
        &input.debtor_proof_directions,
        &input.root
    ) {
        return Err("Debtor Merkle proof verification failed".to_string());
    }
    
    let creditor_leaf = compute_leaf_hash(&computed_creditor_hash, 2);
    if !verify_merkle_proof(
        &creditor_leaf,
        &input.creditor_proof_siblings,
        &input.creditor_proof_directions,
        &input.root
    ) {
        return Err("Creditor Merkle proof verification failed".to_string());
    }
    
    let amount_bytes = input.amount_value.to_be_bytes();
    let amount_leaf = compute_leaf_hash(&amount_bytes, 3);
    if !verify_merkle_proof(
        &amount_leaf,
        &input.amount_proof_siblings,
        &input.amount_proof_directions,
        &input.root
    ) {
        return Err("Amount Merkle proof verification failed".to_string());
    }
    
    let currency_leaf = compute_leaf_hash(&computed_currency_hash, 4);
    if !verify_merkle_proof(
        &currency_leaf,
        &input.currency_proof_siblings,
        &input.currency_proof_directions,
        &input.root
    ) {
        return Err("Currency Merkle proof verification failed".to_string());
    }
    
    let expiry_bytes = expiry_timestamp.to_be_bytes();
    let expiry_leaf = compute_leaf_hash(&expiry_bytes, 5);
    if !verify_merkle_proof(
        &expiry_leaf,
        &input.expiry_proof_siblings,
        &input.expiry_proof_directions,
        &input.root
    ) {
        return Err("Expiry Merkle proof verification failed".to_string());
    }
    
    // 7. Create the output
    Ok(PaymentInstructionOutput {
        root: input.root,
        debtor_hash: input.debtor_hash,
        creditor_hash: input.creditor_hash,
        min_amount_milli: input.min_amount_milli,
        max_amount_milli: input.max_amount_milli,
        currency_hash: input.currency_hash,
        expiry: input.expiry,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_keccak256() {
        let data = b"hello world";
        let hash = keccak256(data);
        assert_eq!(hash.len(), 32);
        
        // Test deterministic
        let hash2 = keccak256(data);
        assert_eq!(hash, hash2);
    }

    #[test]
    fn test_poseidon_hash() {
        let left = [1u8; 32];
        let right = [2u8; 32];
        let hash = poseidon_hash(&left, &right);
        assert_eq!(hash.len(), 32);
        
        // Test deterministic
        let hash2 = poseidon_hash(&left, &right);
        assert_eq!(hash, hash2);
        
        // Test different order gives different result
        let hash3 = poseidon_hash(&right, &left);
        assert_ne!(hash, hash3);
    }

    #[test]
    fn test_compute_leaf_hash() {
        let preimage = b"test data";
        let tag = 1u8;
        let hash = compute_leaf_hash(preimage, tag);
        assert_eq!(hash.len(), 32);
        
        // Test different tag gives different result
        let hash2 = compute_leaf_hash(preimage, 2u8);
        assert_ne!(hash, hash2);
    }

    #[test]
    fn test_verify_merkle_proof_single_leaf() {
        let leaf = [1u8; 32];
        let root = leaf;
        let siblings = vec![];
        let directions = vec![];
        
        assert!(verify_merkle_proof(&leaf, &siblings, &directions, &root));
    }

    #[test]
    fn test_verify_merkle_proof_two_leaves() {
        let left_leaf = [1u8; 32];
        let right_leaf = [2u8; 32];
        let root = poseidon_hash(&left_leaf, &right_leaf);
        
        // Test left leaf proof
        let siblings = vec![right_leaf];
        let directions = vec![0]; // Left child
        assert!(verify_merkle_proof(&left_leaf, &siblings, &directions, &root));
        
        // Test right leaf proof
        let siblings = vec![left_leaf];
        let directions = vec![1]; // Right child
        assert!(verify_merkle_proof(&right_leaf, &siblings, &directions, &root));
    }

    #[test]
    fn test_canonicalize_json() {
        let json = r#"{"key": "value"}"#;
        let canonical = canonicalize_json(json);
        assert_eq!(canonical, json);
    }
} 