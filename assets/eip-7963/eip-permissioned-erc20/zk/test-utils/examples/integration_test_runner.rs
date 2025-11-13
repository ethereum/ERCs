use test_utils::run_all_integration_tests;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("🚀 EIP Permissioned ERC-20 Integration Test Runner");
    println!("==================================================\n");

    // Run all integration tests
    println!("Running comprehensive integration test suite...\n");
    if let Err(e) = run_all_integration_tests().await {
        println!("❌ Integration tests failed: {}", e);
        return Err(e.into());
    }

    println!("\n{}", "=".repeat(50));
    println!("🎉 All integration tests passed successfully!");
    println!("{}", "=".repeat(50));

    Ok(())
}
