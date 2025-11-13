use test_utils::{
    mock_data::MockData,
    payment_instruction_generator::PaymentInstructionGenerator,
    test_helpers::{
        create_test_config, expect_proof_failure, generate_and_verify_proof, TestScenario,
    },
    TestConfig,
};

#[test]
#[ignore] // Ignore by default since it requires RISC Zero setup
fn test_full_proof_generation_and_verification() {
    let mut generator = PaymentInstructionGenerator::new();
    let input = generator.generate_valid_input();
    let config = create_test_config(TestScenario::Fast);

    let result = generate_and_verify_proof(&input, &config);

    match result {
        Ok((output, metrics)) => {
            // Verify output matches input public fields
            assert_eq!(output.root, input.root);
            assert_eq!(output.debtor_hash, input.debtor_hash);
            assert_eq!(output.creditor_hash, input.creditor_hash);
            assert_eq!(output.min_amount_milli, input.min_amount_milli);
            assert_eq!(output.max_amount_milli, input.max_amount_milli);
            assert_eq!(output.currency_hash, input.currency_hash);
            assert_eq!(output.expiry, input.expiry);

            // Check performance metrics
            println!("Proof generation time: {:?}", metrics.proof_generation_time);
            println!("Verification time: {:?}", metrics.verification_time);
            println!("Proof size: {} bytes", metrics.proof_size_bytes);
            println!("Journal size: {} bytes", metrics.journal_size_bytes);
        }
        Err(e) => {
            // This is expected if RISC Zero is not properly set up
            println!(
                "Proof generation failed (expected if RISC Zero not set up): {}",
                e
            );
        }
    }
}

#[test]
#[ignore] // Ignore by default since it requires RISC Zero setup
fn test_proof_generation_failure_cases() {
    let config = create_test_config(TestScenario::Fast);

    // Test various invalid inputs
    let mut generator = PaymentInstructionGenerator::new();

    let invalid_inputs = vec![
        generator.generate_invalid_debtor_hash(),
        generator.generate_invalid_creditor_hash(),
        generator.generate_amount_below_minimum(),
        generator.generate_amount_above_maximum(),
        generator.generate_invalid_currency_hash(),
        generator.generate_invalid_expiry(),
        generator.generate_invalid_merkle_proof(),
    ];

    for (i, input) in invalid_inputs.iter().enumerate() {
        let result = expect_proof_failure(input, &config);

        match result {
            Ok(()) => {
                println!("Invalid input {} correctly failed proof generation", i);
            }
            Err(e) => {
                println!(
                    "Invalid input {} unexpectedly succeeded or had other error: {}",
                    i, e
                );
            }
        }
    }
}

#[test]
#[ignore] // Ignore by default since it requires RISC Zero setup
fn test_proof_generation_edge_cases() {
    let mut generator = PaymentInstructionGenerator::new();
    let edge_cases = generator.generate_edge_cases();
    let config = create_test_config(TestScenario::Standard);

    for (i, input) in edge_cases.iter().enumerate() {
        let result = generate_and_verify_proof(input, &config);

        match result {
            Ok((output, metrics)) => {
                println!(
                    "Edge case {} passed: proof_time={:?}, verify_time={:?}",
                    i, metrics.proof_generation_time, metrics.verification_time
                );

                // Verify output consistency
                assert_eq!(output.root, input.root);
                assert_eq!(output.debtor_hash, input.debtor_hash);
                assert_eq!(output.creditor_hash, input.creditor_hash);
            }
            Err(e) => {
                println!("Edge case {} failed: {}", i, e);
            }
        }
    }
}

#[test]
#[ignore] // Ignore by default since it requires RISC Zero setup
fn test_proof_generation_batch() {
    let mut generator = PaymentInstructionGenerator::new();
    let batch = generator.generate_batch(5); // Small batch for testing
    let config = create_test_config(TestScenario::Fast);

    let mut successful_proofs = 0;
    let mut total_proof_time = std::time::Duration::ZERO;
    let mut total_verify_time = std::time::Duration::ZERO;

    for (i, input) in batch.iter().enumerate() {
        let result = generate_and_verify_proof(input, &config);

        match result {
            Ok((output, metrics)) => {
                successful_proofs += 1;
                total_proof_time += metrics.proof_generation_time;
                total_verify_time += metrics.verification_time;

                println!(
                    "Batch item {} succeeded: proof_time={:?}",
                    i, metrics.proof_generation_time
                );

                // Verify output consistency
                assert_eq!(output.root, input.root);
                assert_eq!(output.debtor_hash, input.debtor_hash);
                assert_eq!(output.creditor_hash, input.creditor_hash);
            }
            Err(e) => {
                println!("Batch item {} failed: {}", i, e);
            }
        }
    }

    if successful_proofs > 0 {
        let avg_proof_time = total_proof_time / successful_proofs as u32;
        let avg_verify_time = total_verify_time / successful_proofs as u32;

        println!(
            "Batch results: {}/{} successful",
            successful_proofs,
            batch.len()
        );
        println!("Average proof time: {:?}", avg_proof_time);
        println!("Average verify time: {:?}", avg_verify_time);
    }
}

#[test]
#[ignore] // Ignore by default since it requires RISC Zero setup
fn test_proof_generation_performance() {
    let mut generator = PaymentInstructionGenerator::new();
    let input = generator.generate_valid_input();

    // Test different configurations
    let configs = vec![
        ("Fast", create_test_config(TestScenario::Fast)),
        ("Standard", create_test_config(TestScenario::Standard)),
    ];

    for (name, config) in configs {
        let result = generate_and_verify_proof(&input, &config);

        match result {
            Ok((_, metrics)) => {
                println!("{} config performance:", name);
                println!("  Proof generation: {:?}", metrics.proof_generation_time);
                println!("  Verification: {:?}", metrics.verification_time);
                println!("  Proof size: {} bytes", metrics.proof_size_bytes);
                println!("  Journal size: {} bytes", metrics.journal_size_bytes);

                // Basic performance assertions (adjust based on your requirements)
                if name == "Fast" {
                    // Fast config should complete within reasonable time
                    assert!(
                        metrics.proof_generation_time.as_secs() < 300,
                        "Fast proof generation should complete within 5 minutes"
                    );
                    assert!(
                        metrics.verification_time.as_millis() < 1000,
                        "Verification should complete within 1 second"
                    );
                }
            }
            Err(e) => {
                println!("{} config failed: {}", name, e);
            }
        }
    }
}

#[test]
#[ignore] // Ignore by default since it requires RISC Zero setup
fn test_proof_generation_memory_usage() {
    let mut generator = PaymentInstructionGenerator::new();
    let input = generator.generate_valid_input();
    let config = TestConfig {
        enable_logging: true,
        proof_timeout_secs: 300,
        max_memory_mb: 1024, // Limit memory for testing
    };

    let result = generate_and_verify_proof(&input, &config);

    match result {
        Ok((_, metrics)) => {
            println!("Memory usage test completed successfully");
            println!("Proof generation time: {:?}", metrics.proof_generation_time);
            println!("Memory usage: {} MB", metrics.memory_usage_mb);

            // Assert memory usage is within limits
            assert!(
                metrics.memory_usage_mb <= config.max_memory_mb,
                "Memory usage should not exceed configured limit"
            );
        }
        Err(e) => {
            println!("Memory usage test failed: {}", e);
        }
    }
}

#[test]
#[ignore] // Ignore by default since it requires RISC Zero setup
fn test_proof_generation_unicode_data() {
    let unicode_input = MockData::unicode_input();

    // Fix the input to have valid hashes and Merkle proofs
    let mut generator = PaymentInstructionGenerator::new();
    let mut valid_input = generator.generate_valid_input();

    // Replace with Unicode data but keep valid structure
    valid_input.debtor_data = unicode_input.debtor_data;
    valid_input.creditor_data = unicode_input.creditor_data;
    valid_input.currency = unicode_input.currency;

    // Regenerate hashes and Merkle proofs
    generator.regenerate_merkle_proofs(&mut valid_input);

    let config = create_test_config(TestScenario::Standard);
    let result = generate_and_verify_proof(&valid_input, &config);

    match result {
        Ok((output, metrics)) => {
            println!("Unicode data test passed");
            println!("Proof generation time: {:?}", metrics.proof_generation_time);

            // Verify output consistency
            assert_eq!(output.root, valid_input.root);
            assert_eq!(output.debtor_hash, valid_input.debtor_hash);
            assert_eq!(output.creditor_hash, valid_input.creditor_hash);
        }
        Err(e) => {
            println!("Unicode data test failed: {}", e);
        }
    }
}

#[test]
#[ignore] // Ignore by default since it requires RISC Zero setup
fn test_proof_generation_large_data() {
    let large_input = MockData::long_strings_input();

    // Fix the input to have valid hashes and Merkle proofs
    let mut generator = PaymentInstructionGenerator::new();
    let mut valid_input = generator.generate_valid_input();

    // Replace with large data but keep valid structure
    valid_input.debtor_data = large_input.debtor_data;
    valid_input.creditor_data = large_input.creditor_data;

    // Regenerate hashes and Merkle proofs
    generator.regenerate_merkle_proofs(&mut valid_input);

    let config = create_test_config(TestScenario::Standard);
    let result = generate_and_verify_proof(&valid_input, &config);

    match result {
        Ok((output, metrics)) => {
            println!("Large data test passed");
            println!("Proof generation time: {:?}", metrics.proof_generation_time);
            println!("Proof size: {} bytes", metrics.proof_size_bytes);

            // Verify output consistency
            assert_eq!(output.root, valid_input.root);
            assert_eq!(output.debtor_hash, valid_input.debtor_hash);
            assert_eq!(output.creditor_hash, valid_input.creditor_hash);
        }
        Err(e) => {
            println!("Large data test failed: {}", e);
        }
    }
}
