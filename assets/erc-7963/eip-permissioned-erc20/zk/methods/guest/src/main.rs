use risc0_zkvm::guest::env;
use method::{PaymentInstructionInput, verify_payment_instruction};

fn main() {
    // Read the input from the host
    let input: PaymentInstructionInput = env::read();
    
    // Verify the payment instruction message
    match verify_payment_instruction(&input) {
        Ok(output) => {
            // Commit the public outputs
            env::commit(&output);
        }
        Err(error) => {
            // In RISC Zero, we panic on verification failure
            panic!("Verification failed: {}", error);
        }
    }
}
