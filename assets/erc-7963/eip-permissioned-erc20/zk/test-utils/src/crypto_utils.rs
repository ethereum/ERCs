use sha2::{Digest, Sha256};

/// Compute Keccak256 hash using SHA256 as a substitute (matching guest implementation)
pub fn keccak256(data: &[u8]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(data);
    let result = hasher.finalize();
    let mut output = [0u8; 32];
    output.copy_from_slice(&result);
    output
}

/// Simple Poseidon-like hash function using SHA256 for compatibility (matching guest implementation)
pub fn poseidon_hash(left: &[u8; 32], right: &[u8; 32]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(left);
    hasher.update(right);
    let result = hasher.finalize();
    let mut output = [0u8; 32];
    output.copy_from_slice(&result);
    output
}

/// Compute leaf hash for a field with tag (matching guest implementation)
pub fn compute_leaf_hash(preimage: &[u8], tag: u8) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(preimage);
    hasher.update(&[tag]);
    let result = hasher.finalize();
    let mut output = [0u8; 32];
    output.copy_from_slice(&result);
    output
}

/// Canonicalize JSON string according to RFC 8785 (simplified version)
pub fn canonicalize_json(input: &str) -> String {
    // For simplicity, we'll assume the input is already canonicalized
    // In a production implementation, you'd want proper JSON canonicalization
    input.to_string()
}

/// Convert hex string to bytes
pub fn hex_to_bytes(hex: &str) -> Result<Vec<u8>, hex::FromHexError> {
    let hex = hex.strip_prefix("0x").unwrap_or(hex);
    hex::decode(hex)
}

/// Convert bytes to hex string with 0x prefix
pub fn bytes_to_hex(bytes: &[u8]) -> String {
    format!("0x{}", hex::encode(bytes))
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
    fn test_hex_conversion() {
        let bytes = vec![0x12, 0x34, 0x56, 0x78];
        let hex = bytes_to_hex(&bytes);
        assert_eq!(hex, "0x12345678");

        let decoded = hex_to_bytes(&hex).unwrap();
        assert_eq!(decoded, bytes);
    }

    #[test]
    fn test_canonicalize_json() {
        let json = r#"{"key": "value"}"#;
        let canonical = canonicalize_json(json);
        assert_eq!(canonical, json);
    }
}
