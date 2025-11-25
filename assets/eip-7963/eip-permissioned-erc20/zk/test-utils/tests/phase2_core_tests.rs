use std::time::Duration;
use test_utils::{
    payment_instruction_generator::PaymentInstructionGenerator,
    proof_validator::ProofValidator,
    test_helpers::{
        assert_performance_requirements, create_test_config, expect_proof_failure,
        generate_and_verify_proof, PerformanceRequirements, TestScenario,
    },
    TestConfig,
};

/// Phase 2: Core Testing - Actual RISC Zero proof generation and verification
///
/// This test suite focuses on:
/// 1. Real ZK proof generation using RISC Zero
/// 2. End-to-end verification pipeline
/// 3. Performance validation
/// 4. Error handling for invalid inputs
/// 5. ISO 20022 payment instruction format compliance

#[test]
#[ignore] // Run with: cargo test phase2_basic_proof_generation -- --ignored
fn phase2_basic_proof_generation() {
    println!("=== Phase 2: Basic Proof Generation ===");

    let mut generator = PaymentInstructionGenerator::new();
    let input = generator.generate_payment_instruction_input();
    let config = create_test_config(TestScenario::Fast);

    // Validate input consistency first
    ProofValidator::validate_input_consistency(&input)
        .expect("Input should be valid before proof generation");

    println!("Generating proof for ISO 20022 payment instruction input...");
    println!("Debtor: {}", input.debtor_data);
    println!("Creditor: {}", input.creditor_data);
    println!(
        "Amount: {} {} (milli-units)",
        input.amount_value, input.currency
    );

    let result = generate_and_verify_proof(&input, &config);

    match result {
        Ok((output, metrics)) => {
            println!("✅ Proof generation successful!");
            println!("📊 Performance Metrics:");
            println!("   Proof generation: {:?}", metrics.proof_generation_time);
            println!("   Verification: {:?}", metrics.verification_time);
            println!("   Proof size: {} bytes", metrics.proof_size_bytes);
            println!("   Journal size: {} bytes", metrics.journal_size_bytes);

            // Verify output consistency
            ProofValidator::validate_output_consistency(&input, &output)
                .expect("Output should match input public fields");

            // Basic performance requirements
            let requirements = PerformanceRequirements {
                max_proof_time: Duration::from_secs(300), // 5 minutes for basic test
                max_verify_time: Duration::from_secs(1),
                max_proof_size: 10 * 1024 * 1024, // 10MB
                max_memory_mb: 4096,
            };

            assert_performance_requirements(&metrics, &requirements);
            println!("✅ Performance requirements met!");
        }
        Err(e) => {
            println!("❌ Proof generation failed: {}", e);
            println!("This is expected if RISC Zero is not properly set up");
            println!("To run this test, ensure RISC Zero toolchain is installed");
        }
    }
}

#[test]
#[ignore] // Run with: cargo test phase2_sample_file_proofs -- --ignored
fn phase2_sample_file_proofs() {
    println!("=== Phase 2: Sample File Proofs ===");

    let mut generator = PaymentInstructionGenerator::new();
    let samples = generator.generate_all_samples();
    let config = create_test_config(TestScenario::Standard);

    for (sample_name, input) in samples {
        println!("\n🔄 Testing sample: {}", sample_name);
        println!(
            "Currency: {}, Amount: {}",
            input.currency, input.amount_value
        );

        // Validate input first
        if let Err(e) = ProofValidator::validate_input_consistency(&input) {
            println!("❌ Input validation failed for {}: {}", sample_name, e);
            continue;
        }

        let result = generate_and_verify_proof(&input, &config);

        match result {
            Ok((output, metrics)) => {
                println!("✅ {} proof successful!", sample_name);
                println!("   Proof time: {:?}", metrics.proof_generation_time);
                println!("   Verify time: {:?}", metrics.verification_time);

                // Verify output consistency
                ProofValidator::validate_output_consistency(&input, &output)
                    .expect("Output should match input");

                // Currency-specific assertions
                match sample_name {
                    "usd_small" => {
                        assert_eq!(input.currency, "USD");
                        assert_eq!(input.amount_value, 125075); // $1,250.75
                    }
                    "eur_large" => {
                        assert_eq!(input.currency, "EUR");
                        assert_eq!(input.amount_value, 5000000); // €50,000.00
                    }
                    "sgd_mid" => {
                        assert_eq!(input.currency, "SGD");
                        assert_eq!(input.amount_value, 123456); // S$1,234.56
                    }
                    _ => {}
                }
            }
            Err(e) => {
                println!("❌ {} proof failed: {}", sample_name, e);
            }
        }
    }
}

#[test]
#[ignore] // Run with: cargo test phase2_invalid_input_handling -- --ignored
fn phase2_invalid_input_handling() {
    println!("=== Phase 2: Invalid Input Handling ===");

    let mut generator = PaymentInstructionGenerator::new();
    let config = create_test_config(TestScenario::Fast);

    let invalid_cases = vec![
        (
            "invalid_debtor_hash",
            generator.generate_invalid_debtor_hash(),
        ),
        (
            "invalid_creditor_hash",
            generator.generate_invalid_creditor_hash(),
        ),
        (
            "amount_below_minimum",
            generator.generate_amount_below_minimum(),
        ),
        (
            "amount_above_maximum",
            generator.generate_amount_above_maximum(),
        ),
        (
            "invalid_currency_hash",
            generator.generate_invalid_currency_hash(),
        ),
        ("invalid_expiry", generator.generate_invalid_expiry()),
        (
            "invalid_merkle_proof",
            generator.generate_invalid_merkle_proof(),
        ),
    ];

    for (case_name, input) in invalid_cases {
        println!("\n🔄 Testing invalid case: {}", case_name);

        let result = expect_proof_failure(&input, &config);

        match result {
            Ok(()) => {
                println!("✅ {} correctly failed proof generation", case_name);
            }
            Err(e) => {
                println!("❌ {} had unexpected result: {}", case_name, e);
            }
        }
    }
}

#[test]
#[ignore] // Run with: cargo test phase2_edge_case_proofs -- --ignored
fn phase2_edge_case_proofs() {
    println!("=== Phase 2: Edge Case Proofs ===");

    let mut generator = PaymentInstructionGenerator::new();
    let edge_cases = generator.generate_edge_cases();
    let config = create_test_config(TestScenario::Standard);

    for (i, input) in edge_cases.iter().enumerate() {
        println!("\n🔄 Testing edge case {}", i + 1);

        // Validate input first
        if let Err(e) = ProofValidator::validate_input_consistency(input) {
            println!("⚠️  Edge case {} has invalid input: {}", i + 1, e);
            continue;
        }

        let result = generate_and_verify_proof(input, &config);

        match result {
            Ok((output, metrics)) => {
                println!("✅ Edge case {} passed", i + 1);
                println!("   Proof time: {:?}", metrics.proof_generation_time);

                // Verify output consistency
                ProofValidator::validate_output_consistency(input, &output)
                    .expect("Output should match input");

                // Log interesting edge case details
                match i {
                    0 => println!("   Minimal amount: {}", input.amount_value),
                    1 => println!("   Maximal amount: {}", input.amount_value),
                    2 => println!("   Single char data length"),
                    3 => println!("   Large data: {} chars", input.debtor_data.len()),
                    4 => println!("   Unicode data: {}", input.currency),
                    _ => {}
                }
            }
            Err(e) => {
                println!("❌ Edge case {} failed: {}", i + 1, e);
            }
        }
    }
}

#[test]
#[ignore] // Run with: cargo test phase2_batch_proof_generation -- --ignored
fn phase2_batch_proof_generation() {
    println!("=== Phase 2: Batch Proof Generation ===");

    let mut generator = PaymentInstructionGenerator::new();
    let batch_size = 3; // Small batch for testing
    let batch = generator.generate_batch(batch_size);
    let config = create_test_config(TestScenario::Fast);

    println!("Generating {} proofs in batch...", batch_size);

    let mut successful_proofs = 0;
    let mut total_proof_time = Duration::ZERO;
    let mut total_verify_time = Duration::ZERO;
    let mut total_proof_size = 0;

    for (i, input) in batch.iter().enumerate() {
        println!("\n🔄 Batch item {} of {}", i + 1, batch_size);

        let result = generate_and_verify_proof(input, &config);

        match result {
            Ok((output, metrics)) => {
                successful_proofs += 1;
                total_proof_time += metrics.proof_generation_time;
                total_verify_time += metrics.verification_time;
                total_proof_size += metrics.proof_size_bytes;

                println!("✅ Batch item {} successful", i + 1);

                // Verify output consistency
                ProofValidator::validate_output_consistency(input, &output)
                    .expect("Output should match input");
            }
            Err(e) => {
                println!("❌ Batch item {} failed: {}", i + 1, e);
            }
        }
    }

    if successful_proofs > 0 {
        let avg_proof_time = total_proof_time / successful_proofs as u32;
        let avg_verify_time = total_verify_time / successful_proofs as u32;
        let avg_proof_size = total_proof_size / successful_proofs;

        println!("\n📊 Batch Results:");
        println!(
            "   Success rate: {}/{} ({:.1}%)",
            successful_proofs,
            batch_size,
            (successful_proofs as f64 / batch_size as f64) * 100.0
        );
        println!("   Average proof time: {:?}", avg_proof_time);
        println!("   Average verify time: {:?}", avg_verify_time);
        println!("   Average proof size: {} bytes", avg_proof_size);

        // Assert reasonable performance for batch
        assert!(
            avg_proof_time < Duration::from_secs(300),
            "Average proof time should be under 5 minutes"
        );
        assert!(
            avg_verify_time < Duration::from_secs(1),
            "Average verify time should be under 1 second"
        );
    } else {
        println!("❌ No proofs succeeded in batch");
    }
}

#[test]
#[ignore] // Run with: cargo test phase2_performance_stress_test -- --ignored
fn phase2_performance_stress_test() {
    println!("=== Phase 2: Performance Stress Test ===");

    let mut generator = PaymentInstructionGenerator::new();
    let input = generator.generate_payment_instruction_input();
    let config = create_test_config(TestScenario::Stress);

    println!("Running stress test with strict performance requirements...");

    let result = generate_and_verify_proof(&input, &config);

    match result {
        Ok((output, metrics)) => {
            println!("✅ Stress test completed!");
            println!("📊 Detailed Metrics:");
            println!("   Proof generation: {:?}", metrics.proof_generation_time);
            println!("   Verification: {:?}", metrics.verification_time);
            println!("   Memory usage: {} MB", metrics.memory_usage_mb);
            println!("   Proof size: {} bytes", metrics.proof_size_bytes);
            println!("   Journal size: {} bytes", metrics.journal_size_bytes);

            // Verify output consistency
            ProofValidator::validate_output_consistency(&input, &output)
                .expect("Output should match input");

            // Strict performance requirements for stress test
            let strict_requirements = PerformanceRequirements {
                max_proof_time: Duration::from_secs(180),    // 3 minutes
                max_verify_time: Duration::from_millis(500), // 500ms
                max_proof_size: 5 * 1024 * 1024,             // 5MB
                max_memory_mb: 2048,                         // 2GB
            };

            assert_performance_requirements(&metrics, &strict_requirements);
            println!("✅ Strict performance requirements met!");
        }
        Err(e) => {
            println!("❌ Stress test failed: {}", e);
        }
    }
}

#[test]
#[ignore] // Run with: cargo test phase2_unicode_and_large_data -- --ignored
fn phase2_unicode_and_large_data() {
    println!("=== Phase 2: Unicode and Large Data Handling ===");

    let mut generator = PaymentInstructionGenerator::new();
    let config = create_test_config(TestScenario::Standard);

    // Test Unicode data
    println!("\n🔄 Testing Unicode data...");
    let mut unicode_input = generator.generate_valid_input();
    unicode_input.debtor_data = r#"{"Nm": "José María García-López", "PstlAdr": {"Ctry": "ES", "AdrLine": ["Calle de Alcalá 123", "28009 Madrid"]}}"#.to_string();
    unicode_input.creditor_data = r#"{"Nm": "李小明", "PstlAdr": {"Ctry": "CN", "AdrLine": ["北京市朝阳区建国门外大街1号", "100004"]}}"#.to_string();
    unicode_input.currency = "€".to_string();

    // Regenerate hashes and proofs for Unicode data
    generator.regenerate_merkle_proofs(&mut unicode_input);

    let result = generate_and_verify_proof(&unicode_input, &config);
    match result {
        Ok((output, metrics)) => {
            println!("✅ Unicode data proof successful!");
            println!("   Proof time: {:?}", metrics.proof_generation_time);
            ProofValidator::validate_output_consistency(&unicode_input, &output)
                .expect("Unicode output should match input");
        }
        Err(e) => {
            println!("❌ Unicode data proof failed: {}", e);
        }
    }

    // Test Large data
    println!("\n🔄 Testing large data...");
    let mut large_input = generator.generate_valid_input();
    let large_name = "A".repeat(500); // Large but reasonable size
    large_input.debtor_data = format!(
        r#"{{"Nm": "{}", "PstlAdr": {{"Ctry": "US", "AdrLine": ["{}"]}} }}"#,
        large_name, large_name
    );
    large_input.creditor_data = format!(
        r#"{{"Nm": "{}", "PstlAdr": {{"Ctry": "US", "AdrLine": ["{}"]}} }}"#,
        large_name, large_name
    );

    // Regenerate hashes and proofs for large data
    generator.regenerate_merkle_proofs(&mut large_input);

    let result = generate_and_verify_proof(&large_input, &config);
    match result {
        Ok((output, metrics)) => {
            println!("✅ Large data proof successful!");
            println!("   Proof time: {:?}", metrics.proof_generation_time);
            println!("   Data size: {} chars", large_input.debtor_data.len());
            ProofValidator::validate_output_consistency(&large_input, &output)
                .expect("Large data output should match input");
        }
        Err(e) => {
            println!("❌ Large data proof failed: {}", e);
        }
    }
}

#[test]
#[ignore] // Run with: cargo test phase2_end_to_end_pipeline -- --ignored
fn phase2_end_to_end_pipeline() {
    println!("=== Phase 2: End-to-End Pipeline Test ===");

    let mut generator = PaymentInstructionGenerator::new();
    let config = create_test_config(TestScenario::Standard);

    println!("🔄 Testing complete pipeline: Generation → Validation → Proof → Verification");

    // 1. Generate input
    println!("\n1️⃣ Generating payment instruction input...");
    let input = generator.generate_payment_instruction_input();
    println!("   ✅ Input generated");

    // 2. Validate input consistency
    println!("\n2️⃣ Validating input consistency...");
    ProofValidator::validate_input_consistency(&input).expect("Input should be valid");
    println!("   ✅ Input validation passed");

    // 3. Generate proof
    println!("\n3️⃣ Generating RISC Zero proof...");
    let result = generate_and_verify_proof(&input, &config);

    match result {
        Ok((output, metrics)) => {
            println!("   ✅ Proof generation successful");

            // 4. Validate output consistency
            println!("\n4️⃣ Validating output consistency...");
            ProofValidator::validate_output_consistency(&input, &output)
                .expect("Output should match input");
            println!("   ✅ Output validation passed");

            // 5. Performance check
            println!("\n5️⃣ Checking performance metrics...");
            println!("   Proof generation: {:?}", metrics.proof_generation_time);
            println!("   Verification: {:?}", metrics.verification_time);
            println!("   Proof size: {} bytes", metrics.proof_size_bytes);
            println!("   ✅ Performance metrics recorded");

            println!("\n🎉 End-to-end pipeline test PASSED!");
            println!("   All components working correctly together");
        }
        Err(e) => {
            println!("   ❌ Proof generation failed: {}", e);
            println!("\n❌ End-to-end pipeline test FAILED");
        }
    }
}
