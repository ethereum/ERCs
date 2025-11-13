use crate::crypto_utils::{canonicalize_json, compute_leaf_hash, keccak256};
use crate::merkle_tree::{MerkleProof, MerkleTree};
use crate::payment_instruction_generator::{PaymentInstructionInput, PaymentInstructionOutput};

/// Main verification logic (duplicated from guest for testing)
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

    // 4. Verify amount bounds
    if input.amount_value < input.min_amount_milli {
        return Err("Amount below minimum".to_string());
    }
    if input.amount_value > input.max_amount_milli {
        return Err("Amount above maximum".to_string());
    }

    // 5. Verify expiry
    let expiry_timestamp = input
        .execution_date
        .replace("-", "")
        .parse::<u64>()
        .map_err(|_| "Invalid expiry date format".to_string())?;
    if expiry_timestamp != input.expiry {
        return Err("Expiry mismatch".to_string());
    }

    // 6. Verify Merkle proofs
    let debtor_leaf = compute_leaf_hash(&input.debtor_hash, 1u8);
    let debtor_proof = MerkleProof {
        siblings: input.debtor_proof_siblings.clone(),
        directions: input.debtor_proof_directions.clone(),
    };
    if !MerkleTree::verify_proof(&debtor_leaf, &debtor_proof, &input.root) {
        return Err("Invalid debtor Merkle proof".to_string());
    }

    let creditor_leaf = compute_leaf_hash(&input.creditor_hash, 2u8);
    let creditor_proof = MerkleProof {
        siblings: input.creditor_proof_siblings.clone(),
        directions: input.creditor_proof_directions.clone(),
    };
    if !MerkleTree::verify_proof(&creditor_leaf, &creditor_proof, &input.root) {
        return Err("Invalid creditor Merkle proof".to_string());
    }

    let amount_bytes = input.amount_value.to_be_bytes();
    let amount_leaf = compute_leaf_hash(&amount_bytes, 3u8);
    let amount_proof = MerkleProof {
        siblings: input.amount_proof_siblings.clone(),
        directions: input.amount_proof_directions.clone(),
    };
    if !MerkleTree::verify_proof(&amount_leaf, &amount_proof, &input.root) {
        return Err("Invalid amount Merkle proof".to_string());
    }

    let currency_leaf = compute_leaf_hash(&input.currency_hash, 4u8);
    let currency_proof = MerkleProof {
        siblings: input.currency_proof_siblings.clone(),
        directions: input.currency_proof_directions.clone(),
    };
    if !MerkleTree::verify_proof(&currency_leaf, &currency_proof, &input.root) {
        return Err("Invalid currency Merkle proof".to_string());
    }

    let expiry_bytes = input.expiry.to_be_bytes();
    let expiry_leaf = compute_leaf_hash(&expiry_bytes, 5u8);
    let expiry_proof = MerkleProof {
        siblings: input.expiry_proof_siblings.clone(),
        directions: input.expiry_proof_directions.clone(),
    };
    if !MerkleTree::verify_proof(&expiry_leaf, &expiry_proof, &input.root) {
        return Err("Invalid expiry Merkle proof".to_string());
    }

    // All verifications passed
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

/// Verify a Merkle proof (wrapper for compatibility)
pub fn verify_merkle_proof(
    root: &[u8; 32],
    leaf: &[u8; 32],
    siblings: &[[u8; 32]],
    directions: &[u8],
    _tag: u8,
) -> bool {
    let proof = MerkleProof {
        siblings: siblings.to_vec(),
        directions: directions.to_vec(),
    };
    MerkleTree::verify_proof(leaf, &proof, root)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::payment_instruction_generator::PaymentInstructionGenerator;

    #[test]
    fn test_verify_payment_instruction_valid() {
        let mut generator = PaymentInstructionGenerator::new();
        let input = generator.generate_valid_input();

        let result = verify_payment_instruction(&input);
        assert!(result.is_ok(), "Valid input should pass verification");

        let output = result.unwrap();
        assert_eq!(output.root, input.root);
        assert_eq!(output.debtor_hash, input.debtor_hash);
        assert_eq!(output.creditor_hash, input.creditor_hash);
    }

    #[test]
    fn test_verify_merkle_proof_simple() {
        let leaf = [1u8; 32];
        let root = leaf;
        let siblings = vec![];
        let directions = vec![];

        assert!(verify_merkle_proof(
            &root,
            &leaf,
            &siblings,
            &directions,
            1u8
        ));
    }
}
