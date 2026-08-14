//! CAPV allowlist policy circuit (MVP).
//!
//! Proves, in zero knowledge, that an agent action is permitted by a policy that is
//! committed on-chain (as `policy_root`) but never revealed. The v1 policy is an
//! allowlist: the action's target must be a member of a committed Merkle tree.
//!
//! Five in-circuit obligations (mirror the ERC spec):
//!   1. decision == ALLOW (this circuit only proves ALLOW verdicts).
//!   2. policy membership: `target` is a leaf in the allowlist whose root == `policy_root`.
//!   3. action commitment: keccak over the canonical PolicyAction preimage == `action_commitment`.
//!   4. nullifier: derived from (domain, agent, commitment, nonce) == `nullifier`.
//!   5. executor binding: `executor` is a committed public input, so the proof is bound to the
//!      address permitted to consume it. The spec's Security Considerations require this to be
//!      enforced in-circuit, not only as a msg.sender check in the Guard.
//!
//! Notes for whoever runs this:
//!  - `action_commitment` is a full 256-bit keccak, so it is a public `[u8; 32]`, not a Field
//!    (a BN254 Field cannot hold 256 bits). `policy_root` and `nullifier` use pedersen (Field-sized).
//!  - The keccak preimage MUST match Solidity `PolicyAction.commit`:
//!    keccak256(abi.encode(chainId, domainId, agentId, target, value, callDataHash, actionNonce)).
//!    Each value is a 32-byte big-endian word; the order below must not change.
//!  - The allowlist Merkle tree uses pedersen for node hashing, so the off-chain tree builder
//!    must use the same. The on-chain Guard treats `policy_root` as an opaque commitment.
//!  - Version-sensitive calls (to_be_bytes / to_le_bits) are flagged; check against your nargo.

use keccak256::keccak256;

global TREE_DEPTH: u32 = 8; // allowlist up to 2^8 entries; raise as needed

fn main(
    // ---- public inputs: mirror the on-chain Verdict ----
    agent_id: pub Field,
    domain_id: pub Field,
    policy_root: pub Field, // = the allowlist Merkle root (pedersen)
    action_commitment: pub [u8; 32], // = keccak(PolicyAction), full 256 bits
    nullifier: pub Field,
    decision: pub u8, // 1 = ALLOW
    executor: pub Field, // address permitted to consume; committed so the proof binds to it
    // ---- private witness ----
    chain_id: Field,
    target: Field, // call target address as an integer
    value: Field,
    call_data_hash: [u8; 32], // keccak(callData): a full 256-bit digest, which a BN254 Field cannot hold
    action_nonce: Field,
    index: Field, // leaf index of `target` in the allowlist
    path: [Field; TREE_DEPTH], // sibling hashes bottom-to-top
) {
    // 1. ALLOW only
    assert(decision == 1);

    // 5. Executor binding: executor is a committed public input (bound to the proof). It must be a
    // real address; the verifier will only accept the proof against this exact executor value.
    assert(executor != 0);

    // 2. Policy membership: recompute the allowlist root from the leaf and assert it matches.
    let leaf = std::hash::pedersen_hash([target]);
    let computed_root = compute_merkle_root(leaf, index, path);
    assert(computed_root == policy_root);

    // 3. Action commitment: keccak over the canonical preimage, byte-for-byte vs the public value.
    let preimage = abi_encode_policy_action(
        chain_id, domain_id, agent_id, target, value, call_data_hash, action_nonce,
    );
    let commit = keccak256(preimage, 224);
    assert(commit == action_commitment);

    // 4. Nullifier = H(domain_id, agent_id, commitment_hi, commitment_lo, action_nonce)
    let (chi, clo) = bytes32_to_two_fields(commit);
    let n = std::hash::pedersen_hash([domain_id, agent_id, chi, clo, action_nonce]);
    assert(n == nullifier);
}

// Recompute a Merkle root from a leaf, its index, and its sibling path (pedersen nodes).
fn compute_merkle_root(leaf: Field, index: Field, path: [Field; TREE_DEPTH]) -> Field {
    let bits: [bool; TREE_DEPTH] = index.to_le_bits(); // low bit = level 0; true = current is right child
    let mut current = leaf;
    for i in 0..TREE_DEPTH {
        let sibling = path[i];
        let left = if bits[i] { sibling } else { current };
        let right = if bits[i] { current } else { sibling };
        current = std::hash::pedersen_hash([left, right]);
    }
    current
}

// Pack the PolicyAction fields into the 224-byte ABI-encoded preimage (7 x 32-byte words).
// Order and width must match Solidity abi.encode exactly.
fn abi_encode_policy_action(
    chain_id: Field,
    domain_id: Field,
    agent_id: Field,
    target: Field,
    value: Field,
    call_data_hash: [u8; 32],
    action_nonce: Field,
) -> [u8; 224] {
    // Words 0..5 and word 6 are Field-sized values. Word 5 (callDataHash) is a full 256-bit keccak
    // digest that routinely exceeds the BN254 field, so it enters as raw bytes and is copied verbatim.
    let field_words = [chain_id, domain_id, agent_id, target, value];
    let mut out: [u8; 224] = [0; 224];
    for w in 0..5 {
        let be: [u8; 32] = field_words[w].to_be_bytes(); // 32-byte big-endian word
        for b in 0..32 {
            out[w * 32 + b] = be[b];
        }
    }
    for b in 0..32 {
        out[5 * 32 + b] = call_data_hash[b]; // callDataHash, verbatim 32 bytes
    }
    let nonce_be: [u8; 32] = action_nonce.to_be_bytes();
    for b in 0..32 {
        out[6 * 32 + b] = nonce_be[b];
    }
    out
}

// Split a 32-byte value into two 16-byte Field limbs (hi, lo) so a full commitment binds
// into a pedersen hash without overflowing the Field.
fn bytes32_to_two_fields(b: [u8; 32]) -> (Field, Field) {
    let mut hi: Field = 0;
    let mut lo: Field = 0;
    for i in 0..16 {
        hi = hi * 256 + (b[i] as Field);
        lo = lo * 256 + (b[i + 16] as Field);
    }
    (hi, lo)
}

// Builds a fully self-consistent valid witness with the circuit's own helpers and runs main.
// If the four obligations are internally consistent, this passes.
#[test]
fn test_allow_verdict() {
    let target: Field = 0x1234;
    let index: Field = 0;
    let path: [Field; TREE_DEPTH] = [0; TREE_DEPTH];
    let leaf = std::hash::pedersen_hash([target]);
    let policy_root = compute_merkle_root(leaf, index, path);

    let chain_id: Field = 1;
    let domain_id: Field = 42;
    let agent_id: Field = 7;
    let value: Field = 0;
    let call_data_hash: [u8; 32] = [0; 32];
    let action_nonce: Field = 3;

    let commit = keccak256(
        abi_encode_policy_action(chain_id, domain_id, agent_id, target, value, call_data_hash, action_nonce),
        224,
    );
    let (chi, clo) = bytes32_to_two_fields(commit);
    let nullifier = std::hash::pedersen_hash([domain_id, agent_id, chi, clo, action_nonce]);
    let executor: Field = 0xE0; // matches ConsumeReal.t.sol executor address(0xE0)

    main(
        agent_id, domain_id, policy_root, commit, nullifier, 1, executor, chain_id, target, value,
        call_data_hash, action_nonce, index, path,
    );
}

// Prints the action commitment for fixed values so it can be cross-checked against Solidity
// PolicyAction.commit (run: nargo test test_print_commit --show-output).
#[test]
fn test_print_commit() {
    // chain_id=1, domain_id=42, agent_id=7, target=0x1234, value=0, call_data_hash=0, action_nonce=3
    let commit = keccak256(abi_encode_policy_action(1, 42, 7, 0x1234, 0, [0; 32], 3), 224);
    println(commit);
}

// Prints the derived public witness values (policy_root, nullifier) so a valid Prover.toml can
// be built for a real proof (run: nargo test test_print_witness --show-output).
#[test]
fn test_print_witness() {
    let target: Field = 0x1234;
    let leaf = std::hash::pedersen_hash([target]);
    let policy_root = compute_merkle_root(leaf, 0, [0; TREE_DEPTH]);
    let commit = keccak256(abi_encode_policy_action(1, 42, 7, target, 0, [0; 32], 3), 224);
    let (chi, clo) = bytes32_to_two_fields(commit);
    let nullifier = std::hash::pedersen_hash([42, 7, chi, clo, 3]);
    println(f"policy_root={policy_root}");
    println(f"nullifier={nullifier}");
}

// Prints the witness values for the ERC-8274 composed live-run fixture (t/28083 post #150):
// Sepolia Multicall3 aggregate3([]) call, real registered agentId, babyblue's action tuple.
// Allowlist of one entry: the Multicall3 target. (run: nargo test test_print_witness_composed --show-output)
#[test]
fn test_print_witness_composed() {
    let target: Field = 0xcA11bde05977b3631167028862bE2a173976CA11;
    let leaf = std::hash::pedersen_hash([target]);
    let policy_root = compute_merkle_root(leaf, 0, [0; TREE_DEPTH]);
    let chain_id: Field = 11155111;
    let domain_id: Field = 0x16079127bc55bd85d480837115b9bd82d26f03809c0bc4c6c80f7220836afad0;
    let agent_id: Field = 54848;
    let action_nonce: Field = 5;
    let call_data_hash: [u8; 32] = [
        0xcf, 0xac, 0xbf, 0xe2, 0x11, 0xcf, 0x3b, 0xe6, 0x7a, 0x1d, 0x64, 0xa6, 0x49, 0x9a, 0x2a, 0xf0,
        0xae, 0x47, 0x5e, 0x2c, 0x09, 0x65, 0xc2, 0xa4, 0x2f, 0x96, 0x9d, 0x24, 0x3d, 0xf2, 0xb6, 0xcd,
    ];
    let commit = keccak256(
        abi_encode_policy_action(chain_id, domain_id, agent_id, target, 0, call_data_hash, action_nonce),
        224,
    );
    let (chi, clo) = bytes32_to_two_fields(commit);
    let nullifier = std::hash::pedersen_hash([domain_id, agent_id, chi, clo, action_nonce]);
    println(f"policy_root={policy_root}");
    println(f"nullifier={nullifier}");
    println(commit);
}
