use test_utils::{mock_data::MockData, payment_instruction_generator::PaymentInstructionGenerator};

fn main() {
    println!("=== PAIN.001 JSON STRUCTURES FOR PHASE 1 ===\n");

    // 1. Simple Mock Data (for quick testing)
    println!("1. SIMPLE MOCK DATA:");
    let simple_input = MockData::simple_valid_input();
    println!("Debtor JSON: {}", simple_input.debtor_data);
    println!("Creditor JSON: {}", simple_input.creditor_data);
    println!("Currency: {}", simple_input.currency);
    println!("Amount: {} milli-units", simple_input.amount_value);
    println!("Execution Date: {}", simple_input.execution_date);
    println!("Min Amount: {}", simple_input.min_amount_milli);
    println!("Max Amount: {}", simple_input.max_amount_milli);
    println!();

    // 2. Generated Valid Input (with proper Merkle proofs)
    println!("2. GENERATED VALID INPUT (with Merkle proofs):");
    let mut generator = PaymentInstructionGenerator::new();
    let generated_input = generator.generate_valid_input();
    println!("Debtor JSON: {}", generated_input.debtor_data);
    println!("Creditor JSON: {}", generated_input.creditor_data);
    println!("Currency: {}", generated_input.currency);
    println!("Amount: {} milli-units", generated_input.amount_value);
    println!("Execution Date: {}", generated_input.execution_date);
    println!("Merkle Root: {:?}", generated_input.root);
    println!("Debtor Hash: {:?}", generated_input.debtor_hash);
    println!("Creditor Hash: {:?}", generated_input.creditor_hash);
    println!();

    // 3. ISO 20022 Format (based on actual sample files)
    println!("3. ISO 20022 FORMAT (based on sample files):");
    let iso_input = generator.generate_payment_instruction_input();
    println!("Debtor JSON: {}", iso_input.debtor_data);
    println!("Creditor JSON: {}", iso_input.creditor_data);
    println!("Currency: {}", iso_input.currency);
    println!("Amount: {} milli-units", iso_input.amount_value);
    println!("Execution Date: {}", iso_input.execution_date);
    println!();

    // 4. Sample File Formats
    println!("4. SAMPLE FILE FORMATS:");
    let samples = generator.generate_all_samples();
    for (name, input) in samples {
        println!("Sample: {}", name);
        println!("  Debtor: {}", input.debtor_data);
        println!("  Creditor: {}", input.creditor_data);
        println!("  Currency: {}", input.currency);
        println!("  Amount: {} milli-units", input.amount_value);
        println!("  Date: {}", input.execution_date);
        println!();
    }

    println!("=== MERKLE TREE STRUCTURE ===");
    println!("The Merkle tree contains 5 leaves:");
    println!("1. Debtor hash (tag: 1)");
    println!("2. Creditor hash (tag: 2)");
    println!("3. Amount bytes (tag: 3)");
    println!("4. Currency hash (tag: 4)");
    println!("5. Expiry bytes (tag: 5)");
    println!();
    println!("Each leaf is computed as: poseidon_hash(keccak256(data), tag)");
    println!("The tree uses Poseidon hash for internal nodes.");
}
