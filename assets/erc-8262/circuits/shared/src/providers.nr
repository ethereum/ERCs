/// Provider set commitment for ERC-8262 circuits

use crate::constants::MAX_PROVIDERS;
use crate::hash::hash16;

/// Compute a commitment to the set of providers and weights used.
/// N must be <= MAX_PROVIDERS (8), since the hash uses a fixed 16-slot array
/// (2 slots per provider: id + weight).
pub fn compute_provider_set_hash<let N: u32>(
    provider_ids: [Field; N],
    weights: [u32; N],
) -> Field {
    assert(N <= MAX_PROVIDERS, "Provider count exceeds MAX_PROVIDERS");
    let mut hash_inputs: [Field; 16] = [0; 16];
    for i in 0..N {
        hash_inputs[i * 2] = provider_ids[i];
        hash_inputs[i * 2 + 1] = weights[i] as Field;
    }
    hash16(hash_inputs)
}
