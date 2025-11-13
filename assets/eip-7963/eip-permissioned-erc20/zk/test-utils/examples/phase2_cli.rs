use std::env;
use std::time::Instant;
use test_utils::{
    payment_instruction_generator::PaymentInstructionGenerator,
    proof_validator::ProofValidator,
    test_helpers::{
        create_test_config, generate_and_verify_proof, load_input_from_file,
        save_input_to_temp_file, TestScenario,
    },
};

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        print_usage();
        return;
    }

    match args[1].as_str() {
        "basic" => run_basic_test(),
        "samples" => run_sample_tests(),
        "stress" => run_stress_test(),
        "batch" => {
            let count = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(3);
            run_batch_test(count);
        }
        "file" => {
            if args.len() < 3 {
                println!("Usage: cargo run --example phase2_cli file <input.json>");
                return;
            }
            run_file_test(&args[2]);
        }
        "generate" => {
            let default_file = "generated_input.json".to_string();
            let output_file = args.get(2).unwrap_or(&default_file);
            generate_input_file(output_file);
        }
        "validate" => {
            if args.len() < 3 {
                println!("Usage: cargo run --example phase2_cli validate <input.json>");
                return;
            }
            validate_input_file(&args[2]);
        }
        _ => {
            println!("Unknown command: {}", args[1]);
            print_usage();
        }
    }
}

fn print_usage() {
    println!("Phase 2 CLI - RISC Zero Proof Generation and Verification");
    println!();
    println!("USAGE:");
    println!("  cargo run --example phase2_cli <COMMAND> [OPTIONS]");
    println!();
    println!("COMMANDS:");
    println!("  basic                    Run basic proof generation test");
    println!("  samples                  Test all sample file formats");
    println!("  stress                   Run performance stress test");
    println!("  batch <count>            Generate batch of proofs (default: 3)");
    println!("  file <input.json>        Generate proof from JSON file");
    println!("  generate [output.json]   Generate sample input file");
    println!("  validate <input.json>    Validate input file without proof");
    println!();
    println!("EXAMPLES:");
    println!("  cargo run --example phase2_cli basic");
    println!("  cargo run --example phase2_cli batch 5");
    println!("  cargo run --example phase2_cli generate my_input.json");
    println!("  cargo run --example phase2_cli file my_input.json");
}

fn run_basic_test() {
    println!("🚀 Phase 2: Basic Proof Generation Test");
    println!("========================================");

    let mut generator = PaymentInstructionGenerator::new();
    let input = generator.generate_payment_instruction_input();
    let config = create_test_config(TestScenario::Fast);

    println!("\n📋 Input Details:");
    println!("  Debtor: {}", extract_name(&input.debtor_data));
    println!("  Creditor: {}", extract_name(&input.creditor_data));
    println!(
        "  Amount: {} {} (milli-units)",
        input.amount_value, input.currency
    );
    println!("  Execution Date: {}", input.execution_date);

    // Validate input
    print!("\n🔍 Validating input... ");
    match ProofValidator::validate_input_consistency(&input) {
        Ok(()) => println!("✅ Valid"),
        Err(e) => {
            println!("❌ Invalid: {}", e);
            return;
        }
    }

    // Generate proof
    println!("\n⚡ Generating RISC Zero proof...");
    let start_time = Instant::now();

    match generate_and_verify_proof(&input, &config) {
        Ok((output, metrics)) => {
            let total_time = start_time.elapsed();

            println!("✅ Proof generation successful!");
            println!("\n📊 Performance Metrics:");
            println!("  Total time: {:?}", total_time);
            println!("  Proof generation: {:?}", metrics.proof_generation_time);
            println!("  Verification: {:?}", metrics.verification_time);
            println!("  Proof size: {} bytes", metrics.proof_size_bytes);
            println!("  Journal size: {} bytes", metrics.journal_size_bytes);

            // Verify output
            match ProofValidator::validate_output_consistency(&input, &output) {
                Ok(()) => println!("✅ Output validation passed"),
                Err(e) => println!("❌ Output validation failed: {}", e),
            }
        }
        Err(e) => {
            println!("❌ Proof generation failed: {}", e);
            println!("\nThis is expected if RISC Zero is not properly set up.");
            println!("To run this test, ensure RISC Zero toolchain is installed.");
        }
    }
}

fn run_sample_tests() {
    println!("🚀 Phase 2: Sample File Tests");
    println!("==============================");

    let mut generator = PaymentInstructionGenerator::new();
    let samples = generator.generate_all_samples();
    let config = create_test_config(TestScenario::Standard);

    println!("\n📋 Testing {} sample formats...", samples.len());

    for (i, (sample_name, input)) in samples.iter().enumerate() {
        println!("\n{}. Testing sample: {}", i + 1, sample_name);
        println!(
            "   Currency: {}, Amount: {} milli-units",
            input.currency, input.amount_value
        );

        // Validate input
        if let Err(e) = ProofValidator::validate_input_consistency(input) {
            println!("   ❌ Input validation failed: {}", e);
            continue;
        }

        // Generate proof
        print!("   ⚡ Generating proof... ");
        match generate_and_verify_proof(input, &config) {
            Ok((output, metrics)) => {
                println!("✅ Success!");
                println!("     Proof time: {:?}", metrics.proof_generation_time);
                println!("     Verify time: {:?}", metrics.verification_time);

                // Verify output
                if let Err(e) = ProofValidator::validate_output_consistency(input, &output) {
                    println!("     ❌ Output validation failed: {}", e);
                }
            }
            Err(e) => {
                println!("❌ Failed: {}", e);
            }
        }
    }
}

fn run_stress_test() {
    println!("🚀 Phase 2: Performance Stress Test");
    println!("====================================");

    let mut generator = PaymentInstructionGenerator::new();
    let input = generator.generate_payment_instruction_input();
    let config = create_test_config(TestScenario::Stress);

    println!("\n⚠️  Running stress test with strict performance requirements...");
    println!("   Max proof time: 3 minutes");
    println!("   Max verify time: 500ms");
    println!("   Max memory: 2GB");

    let start_time = Instant::now();

    match generate_and_verify_proof(&input, &config) {
        Ok((output, metrics)) => {
            let total_time = start_time.elapsed();

            println!("\n✅ Stress test completed!");
            println!("\n📊 Detailed Performance Metrics:");
            println!("  Total time: {:?}", total_time);
            println!("  Proof generation: {:?}", metrics.proof_generation_time);
            println!("  Verification: {:?}", metrics.verification_time);
            println!("  Memory usage: {} MB", metrics.memory_usage_mb);
            println!("  Proof size: {} bytes", metrics.proof_size_bytes);
            println!("  Journal size: {} bytes", metrics.journal_size_bytes);

            // Check performance requirements
            if metrics.proof_generation_time.as_secs() <= 180 {
                println!("✅ Proof generation time requirement met");
            } else {
                println!("❌ Proof generation time exceeded 3 minutes");
            }

            if metrics.verification_time.as_millis() <= 500 {
                println!("✅ Verification time requirement met");
            } else {
                println!("❌ Verification time exceeded 500ms");
            }

            // Verify output
            match ProofValidator::validate_output_consistency(&input, &output) {
                Ok(()) => println!("✅ Output validation passed"),
                Err(e) => println!("❌ Output validation failed: {}", e),
            }
        }
        Err(e) => {
            println!("❌ Stress test failed: {}", e);
        }
    }
}

fn run_batch_test(count: usize) {
    println!("🚀 Phase 2: Batch Proof Generation");
    println!("===================================");

    let mut generator = PaymentInstructionGenerator::new();
    let batch = generator.generate_batch(count);
    let config = create_test_config(TestScenario::Fast);

    println!("\n📋 Generating {} proofs in batch...", count);

    let mut successful_proofs = 0;
    let mut total_proof_time = std::time::Duration::ZERO;
    let mut total_verify_time = std::time::Duration::ZERO;

    let start_time = Instant::now();

    for (i, input) in batch.iter().enumerate() {
        print!("   {}/{}: ", i + 1, count);

        match generate_and_verify_proof(input, &config) {
            Ok((output, metrics)) => {
                successful_proofs += 1;
                total_proof_time += metrics.proof_generation_time;
                total_verify_time += metrics.verification_time;

                println!("✅ Success ({:?})", metrics.proof_generation_time);

                // Verify output
                if let Err(e) = ProofValidator::validate_output_consistency(input, &output) {
                    println!("      ❌ Output validation failed: {}", e);
                }
            }
            Err(e) => {
                println!("❌ Failed: {}", e);
            }
        }
    }

    let total_time = start_time.elapsed();

    println!("\n📊 Batch Results:");
    println!("  Total time: {:?}", total_time);
    println!(
        "  Success rate: {}/{} ({:.1}%)",
        successful_proofs,
        count,
        (successful_proofs as f64 / count as f64) * 100.0
    );

    if successful_proofs > 0 {
        let avg_proof_time = total_proof_time / successful_proofs as u32;
        let avg_verify_time = total_verify_time / successful_proofs as u32;

        println!("  Average proof time: {:?}", avg_proof_time);
        println!("  Average verify time: {:?}", avg_verify_time);
    }
}

fn run_file_test(file_path: &str) {
    println!("🚀 Phase 2: File-based Proof Generation");
    println!("========================================");

    println!("\n📂 Loading input from: {}", file_path);

    let input = match load_input_from_file(file_path) {
        Ok(input) => {
            println!("✅ File loaded successfully");
            input
        }
        Err(e) => {
            println!("❌ Failed to load file: {}", e);
            return;
        }
    };

    println!("\n📋 Input Details:");
    println!("  Debtor: {}", extract_name(&input.debtor_data));
    println!("  Creditor: {}", extract_name(&input.creditor_data));
    println!(
        "  Amount: {} {} (milli-units)",
        input.amount_value, input.currency
    );

    // Validate input
    print!("\n🔍 Validating input... ");
    match ProofValidator::validate_input_consistency(&input) {
        Ok(()) => println!("✅ Valid"),
        Err(e) => {
            println!("❌ Invalid: {}", e);
            return;
        }
    }

    // Generate proof
    println!("\n⚡ Generating RISC Zero proof...");
    let config = create_test_config(TestScenario::Standard);

    match generate_and_verify_proof(&input, &config) {
        Ok((output, metrics)) => {
            println!("✅ Proof generation successful!");
            println!("\n📊 Performance Metrics:");
            println!("  Proof generation: {:?}", metrics.proof_generation_time);
            println!("  Verification: {:?}", metrics.verification_time);
            println!("  Proof size: {} bytes", metrics.proof_size_bytes);

            // Verify output
            match ProofValidator::validate_output_consistency(&input, &output) {
                Ok(()) => println!("✅ Output validation passed"),
                Err(e) => println!("❌ Output validation failed: {}", e),
            }
        }
        Err(e) => {
            println!("❌ Proof generation failed: {}", e);
        }
    }
}

fn generate_input_file(output_file: &str) {
    println!("🚀 Phase 2: Generate Input File");
    println!("================================");

    let mut generator = PaymentInstructionGenerator::new();
    let input = generator.generate_payment_instruction_input();

    println!("\n📋 Generated Input:");
    println!("  Debtor: {}", extract_name(&input.debtor_data));
    println!("  Creditor: {}", extract_name(&input.creditor_data));
    println!(
        "  Amount: {} {} (milli-units)",
        input.amount_value, input.currency
    );

    match save_input_to_temp_file(&input) {
        Ok(temp_file) => {
            // Copy temp file to desired location
            match std::fs::copy(temp_file.path(), output_file) {
                Ok(_) => {
                    println!("\n✅ Input file saved to: {}", output_file);
                    println!("\nYou can now test it with:");
                    println!("  cargo run --example phase2_cli file {}", output_file);
                }
                Err(e) => {
                    println!("❌ Failed to save file: {}", e);
                }
            }
        }
        Err(e) => {
            println!("❌ Failed to generate file: {}", e);
        }
    }
}

fn validate_input_file(file_path: &str) {
    println!("🚀 Phase 2: Validate Input File");
    println!("================================");

    println!("\n📂 Loading input from: {}", file_path);

    let input = match load_input_from_file(file_path) {
        Ok(input) => {
            println!("✅ File loaded successfully");
            input
        }
        Err(e) => {
            println!("❌ Failed to load file: {}", e);
            return;
        }
    };

    println!("\n📋 Input Details:");
    println!("  Debtor: {}", extract_name(&input.debtor_data));
    println!("  Creditor: {}", extract_name(&input.creditor_data));
    println!(
        "  Amount: {} {} (milli-units)",
        input.amount_value, input.currency
    );
    println!("  Execution Date: {}", input.execution_date);

    // Comprehensive validation
    println!("\n🔍 Running validation checks...");

    match ProofValidator::validate_input_consistency(&input) {
        Ok(()) => {
            println!("✅ All validation checks passed!");
            println!("\n📊 Validation Summary:");
            println!("  ✅ Debtor hash matches data");
            println!("  ✅ Creditor hash matches data");
            println!("  ✅ Currency hash matches data");
            println!("  ✅ Amount within bounds");
            println!("  ✅ Expiry date format valid");
            println!("  ✅ Merkle proofs structure valid");

            println!("\nThis input is ready for proof generation!");
        }
        Err(e) => {
            println!("❌ Validation failed: {}", e);
            println!("\nPlease fix the input before generating proofs.");
        }
    }
}

fn extract_name(json_data: &str) -> String {
    // Simple JSON parsing to extract name
    if let Ok(value) = serde_json::from_str::<serde_json::Value>(json_data) {
        if let Some(name) = value.get("Nm").and_then(|n| n.as_str()) {
            return name.to_string();
        }
    }
    "Unknown".to_string()
}
