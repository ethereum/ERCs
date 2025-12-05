use test_utils::{
    run_all_integration_tests,
    test_crypto_integration,
    test_merkle_integration,
    test_data_generation_integration,
    test_proof_pipeline_integration,
};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("🚀 EIP Permissioned ERC-20 Integration Test Runner");
    println!("==================================================\n");

    // Option 1: Run all integration tests
    println!("Running comprehensive integration test suite...\n");
    if let Err(e) = run_all_integration_tests().await {
        println!("❌ Integration tests failed: {}", e);
        return Err(e.into());
    }

    println!("\n" + "=".repeat(50));
    println!("🎉 All integration tests passed successfully!");
    println!("=".repeat(50));

    // Option 2: Run individual test categories (commented out to avoid duplication)
    /*
    println!("\n📝 Running individual test categories...\n");
    
    // Test 1: Cryptographic utilities
    if let Err(e) = test_crypto_integration() {
        println!("❌ Crypto integration test failed: {}", e);
        return Err(e.into());
    }

    // Test 2: Merkle tree functionality
    if let Err(e) = test_merkle_integration() {
        println!("❌ Merkle tree integration test failed: {}", e);
        return Err(e.into());
    }

    // Test 3: Data generation
    if let Err(e) = test_data_generation_integration() {
        println!("❌ Data generation integration test failed: {}", e);
        return Err(e.into());
    }

    // Test 4: Full proof pipeline
    if let Err(e) = test_proof_pipeline_integration().await {
        println!("❌ Proof pipeline integration test failed: {}", e);
        return Err(e.into());
    }

    println!("✅ All individual tests passed!");
    */

    Ok(())
} 