use crate::crypto_utils::{compute_leaf_hash, poseidon_hash};

#[derive(Debug, Clone)]
pub struct MerkleProof {
    pub siblings: Vec<[u8; 32]>,
    pub directions: Vec<u8>, // 0 = left, 1 = right
}

#[derive(Debug, Clone)]
pub struct MerkleTree {
    pub leaves: Vec<[u8; 32]>,
    pub tree: Vec<Vec<[u8; 32]>>,
}

impl MerkleTree {
    /// Create a new Merkle tree from leaf data
    pub fn new(leaf_data: Vec<(&[u8], u8)>) -> Self {
        let leaves: Vec<[u8; 32]> = leaf_data
            .iter()
            .map(|(data, tag)| compute_leaf_hash(data, *tag))
            .collect();

        let mut tree = vec![leaves.clone()];
        let mut current_level = leaves.clone();

        // Build tree bottom-up
        while current_level.len() > 1 {
            let mut next_level = Vec::new();

            for chunk in current_level.chunks(2) {
                let hash = if chunk.len() == 2 {
                    poseidon_hash(&chunk[0], &chunk[1])
                } else {
                    // Odd number of nodes, duplicate the last one
                    poseidon_hash(&chunk[0], &chunk[0])
                };
                next_level.push(hash);
            }

            tree.push(next_level.clone());
            current_level = next_level;
        }

        Self { leaves, tree }
    }

    /// Get the root hash
    pub fn root(&self) -> [u8; 32] {
        self.tree.last().unwrap()[0]
    }

    /// Generate a Merkle proof for a leaf at the given index
    pub fn generate_proof(&self, leaf_index: usize) -> Result<MerkleProof, String> {
        if leaf_index >= self.leaves.len() {
            return Err("Leaf index out of bounds".to_string());
        }

        let mut siblings = Vec::new();
        let mut directions = Vec::new();
        let mut current_index = leaf_index;

        // Traverse from leaf to root
        for level in 0..self.tree.len() - 1 {
            let level_size = self.tree[level].len();
            let sibling_index = if current_index % 2 == 0 {
                // Current node is left child
                if current_index + 1 < level_size {
                    current_index + 1
                } else {
                    current_index // Duplicate for odd number of nodes
                }
            } else {
                // Current node is right child
                current_index - 1
            };

            siblings.push(self.tree[level][sibling_index]);
            directions.push(if current_index % 2 == 0 { 0 } else { 1 });

            current_index /= 2;
        }

        Ok(MerkleProof {
            siblings,
            directions,
        })
    }

    /// Verify a Merkle proof
    pub fn verify_proof(leaf: &[u8; 32], proof: &MerkleProof, root: &[u8; 32]) -> bool {
        let mut current = *leaf;

        for (sibling, direction) in proof.siblings.iter().zip(proof.directions.iter()) {
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
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_merkle_tree_single_leaf() {
        let data = vec![(b"test".as_slice(), 1u8)];
        let tree = MerkleTree::new(data);

        assert_eq!(tree.leaves.len(), 1);
        assert_eq!(tree.tree.len(), 1);

        let proof = tree.generate_proof(0).unwrap();
        assert!(proof.siblings.is_empty());
        assert!(proof.directions.is_empty());

        let leaf = compute_leaf_hash(b"test", 1u8);
        assert!(MerkleTree::verify_proof(&leaf, &proof, &tree.root()));
    }

    #[test]
    fn test_merkle_tree_two_leaves() {
        let data = vec![(b"leaf1".as_slice(), 1u8), (b"leaf2".as_slice(), 2u8)];
        let tree = MerkleTree::new(data);

        assert_eq!(tree.leaves.len(), 2);
        assert_eq!(tree.tree.len(), 2);

        // Test proof for first leaf
        let proof0 = tree.generate_proof(0).unwrap();
        assert_eq!(proof0.siblings.len(), 1);
        assert_eq!(proof0.directions.len(), 1);
        assert_eq!(proof0.directions[0], 0); // Left child

        let leaf0 = compute_leaf_hash(b"leaf1", 1u8);
        assert!(MerkleTree::verify_proof(&leaf0, &proof0, &tree.root()));

        // Test proof for second leaf
        let proof1 = tree.generate_proof(1).unwrap();
        assert_eq!(proof1.siblings.len(), 1);
        assert_eq!(proof1.directions.len(), 1);
        assert_eq!(proof1.directions[0], 1); // Right child

        let leaf1 = compute_leaf_hash(b"leaf2", 2u8);
        assert!(MerkleTree::verify_proof(&leaf1, &proof1, &tree.root()));
    }

    #[test]
    fn test_merkle_tree_four_leaves() {
        let data = vec![
            (b"leaf1".as_slice(), 1u8),
            (b"leaf2".as_slice(), 2u8),
            (b"leaf3".as_slice(), 3u8),
            (b"leaf4".as_slice(), 4u8),
        ];
        let tree = MerkleTree::new(data);

        assert_eq!(tree.leaves.len(), 4);
        assert_eq!(tree.tree.len(), 3); // 4 leaves -> 2 nodes -> 1 root

        // Test all proofs
        for i in 0..4 {
            let proof = tree.generate_proof(i).unwrap();
            assert_eq!(proof.siblings.len(), 2);
            assert_eq!(proof.directions.len(), 2);

            let leaf = tree.leaves[i];
            assert!(MerkleTree::verify_proof(&leaf, &proof, &tree.root()));
        }
    }

    #[test]
    fn test_merkle_tree_odd_leaves() {
        let data = vec![
            (b"leaf1".as_slice(), 1u8),
            (b"leaf2".as_slice(), 2u8),
            (b"leaf3".as_slice(), 3u8),
        ];
        let tree = MerkleTree::new(data);

        assert_eq!(tree.leaves.len(), 3);

        // Test all proofs
        for i in 0..3 {
            let proof = tree.generate_proof(i).unwrap();
            let leaf = tree.leaves[i];
            assert!(MerkleTree::verify_proof(&leaf, &proof, &tree.root()));
        }
    }

    #[test]
    fn test_invalid_proof() {
        let data = vec![(b"leaf1".as_slice(), 1u8), (b"leaf2".as_slice(), 2u8)];
        let tree = MerkleTree::new(data);

        let mut proof = tree.generate_proof(0).unwrap();
        proof.directions[0] = 1; // Flip direction

        let leaf = tree.leaves[0];
        assert!(!MerkleTree::verify_proof(&leaf, &proof, &tree.root()));
    }

    #[test]
    fn test_proof_out_of_bounds() {
        let data = vec![(b"leaf1".as_slice(), 1u8)];
        let tree = MerkleTree::new(data);

        let result = tree.generate_proof(1);
        assert!(result.is_err());
    }
}
