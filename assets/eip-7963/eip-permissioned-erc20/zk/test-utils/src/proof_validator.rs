use crate::crypto_utils::{canonicalize_json, keccak256};
use crate::payment_instruction_generator::{PaymentInstructionInput, PaymentInstructionOutput};
use anyhow::{anyhow, Result};

/// Comprehensive proof validator for payment instruction inputs and outputs
pub struct ProofValidator;

impl ProofValidator {
    /// Validate that an input is internally consistent
    pub fn validate_input_consistency(input: &PaymentInstructionInput) -> Result<()> {
        // 1. Validate debtor hash
        let computed_debtor_hash = keccak256(canonicalize_json(&input.debtor_data).as_bytes());
        if computed_debtor_hash != input.debtor_hash {
            return Err(anyhow!(
                "Debtor hash mismatch: computed {:?}, expected {:?}",
                computed_debtor_hash,
                input.debtor_hash
            ));
        }

        // 2. Validate creditor hash
        let computed_creditor_hash = keccak256(canonicalize_json(&input.creditor_data).as_bytes());
        if computed_creditor_hash != input.creditor_hash {
            return Err(anyhow!(
                "Creditor hash mismatch: computed {:?}, expected {:?}",
                computed_creditor_hash,
                input.creditor_hash
            ));
        }

        // 3. Validate currency hash
        let computed_currency_hash = keccak256(input.currency.as_bytes());
        if computed_currency_hash != input.currency_hash {
            return Err(anyhow!(
                "Currency hash mismatch: computed {:?}, expected {:?}",
                computed_currency_hash,
                input.currency_hash
            ));
        }

        // 4. Validate amount bounds
        if input.amount_value < input.min_amount_milli {
            return Err(anyhow!(
                "Amount {} is below minimum {}",
                input.amount_value,
                input.min_amount_milli
            ));
        }
        if input.amount_value > input.max_amount_milli {
            return Err(anyhow!(
                "Amount {} is above maximum {}",
                input.amount_value,
                input.max_amount_milli
            ));
        }

        // 5. Validate expiry format and consistency
        let parsed_expiry = input
            .execution_date
            .replace("-", "")
            .parse::<u64>()
            .map_err(|_| anyhow!("Invalid execution date format: {}", input.execution_date))?;
        if parsed_expiry != input.expiry {
            return Err(anyhow!(
                "Expiry mismatch: parsed {}, expected {}",
                parsed_expiry,
                input.expiry
            ));
        }

        Ok(())
    }

    /// Validate that output matches input public fields
    pub fn validate_output_consistency(input: &PaymentInstructionInput, output: &PaymentInstructionOutput) -> Result<()> {
        if output.root != input.root {
            return Err(anyhow!("Root mismatch in output"));
        }
        if output.debtor_hash != input.debtor_hash {
            return Err(anyhow!("Debtor hash mismatch in output"));
        }
        if output.creditor_hash != input.creditor_hash {
            return Err(anyhow!("Creditor hash mismatch in output"));
        }
        if output.min_amount_milli != input.min_amount_milli {
            return Err(anyhow!("Min amount mismatch in output"));
        }
        if output.max_amount_milli != input.max_amount_milli {
            return Err(anyhow!("Max amount mismatch in output"));
        }
        if output.currency_hash != input.currency_hash {
            return Err(anyhow!("Currency hash mismatch in output"));
        }
        if output.expiry != input.expiry {
            return Err(anyhow!("Expiry mismatch in output"));
        }

        Ok(())
    }

    /// Validate JSON format and structure
    pub fn validate_json_format(json_str: &str) -> Result<()> {
        serde_json::from_str::<serde_json::Value>(json_str)
            .map_err(|e| anyhow!("Invalid JSON format: {}", e))?;
        Ok(())
    }

    /// Validate date format (YYYYMMDD)
    pub fn validate_date_format(date_str: &str) -> Result<u64> {
        if date_str.len() != 8 {
            return Err(anyhow!(
                "Date must be 8 characters (YYYYMMDD), got: {}",
                date_str
            ));
        }

        let year: u32 = date_str[0..4]
            .parse()
            .map_err(|_| anyhow!("Invalid year in date: {}", date_str))?;
        let month: u32 = date_str[4..6]
            .parse()
            .map_err(|_| anyhow!("Invalid month in date: {}", date_str))?;
        let day: u32 = date_str[6..8]
            .parse()
            .map_err(|_| anyhow!("Invalid day in date: {}", date_str))?;

        if year < 1900 || year > 2100 {
            return Err(anyhow!("Year out of range: {}", year));
        }
        if month < 1 || month > 12 {
            return Err(anyhow!("Month out of range: {}", month));
        }
        if day < 1 || day > 31 {
            return Err(anyhow!("Day out of range: {}", day));
        }

        date_str
            .parse::<u64>()
            .map_err(|_| anyhow!("Failed to parse date as number: {}", date_str))
    }

    /// Validate amount ranges
    pub fn validate_amount_ranges(amount: u64, min_amount: u64, max_amount: u64) -> Result<()> {
        if min_amount > max_amount {
            return Err(anyhow!(
                "Min amount {} is greater than max amount {}",
                min_amount,
                max_amount
            ));
        }
        if amount < min_amount {
            return Err(anyhow!("Amount {} is below minimum {}", amount, min_amount));
        }
        if amount > max_amount {
            return Err(anyhow!("Amount {} is above maximum {}", amount, max_amount));
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mock_data::MockData;

    #[test]
    fn test_validate_invalid_sender_hash() {
        let mut input = MockData::simple_valid_input();
        input.debtor_hash = [0u8; 32]; // Wrong hash

        let result = ProofValidator::validate_input_consistency(&input);
        assert!(result.is_err());
        assert!(result
            .unwrap_err()
            .to_string()
            .contains("Debtor hash mismatch"));
    }

    #[test]
    fn test_validate_invalid_amount() {
        let mut input = MockData::simple_valid_input();
        input.amount_value = input.min_amount_milli - 1; // Below minimum

        let result = ProofValidator::validate_input_consistency(&input);
        assert!(result.is_err());
        let error_msg = result.unwrap_err().to_string();
        assert!(error_msg.contains("below minimum"));
    }

    #[test]
    fn test_validate_json_format() {
        assert!(ProofValidator::validate_json_format(r#"{"valid": "json"}"#).is_ok());
        assert!(ProofValidator::validate_json_format(r#"{"invalid": json}"#).is_err());
        assert!(ProofValidator::validate_json_format("not json at all").is_err());
    }

    #[test]
    fn test_validate_date_format() {
        assert!(ProofValidator::validate_date_format("20241231").is_ok());
        assert!(ProofValidator::validate_date_format("2024-12-31").is_err());
        assert!(ProofValidator::validate_date_format("20241301").is_err()); // Invalid month
        assert!(ProofValidator::validate_date_format("20241232").is_err()); // Invalid day
        assert!(ProofValidator::validate_date_format("1899").is_err()); // Too short
    }

    #[test]
    fn test_validate_amount_ranges() {
        assert!(ProofValidator::validate_amount_ranges(1500, 1000, 2000).is_ok());
        assert!(ProofValidator::validate_amount_ranges(500, 1000, 2000).is_err()); // Below min
        assert!(ProofValidator::validate_amount_ranges(2500, 1000, 2000).is_err()); // Above max
        assert!(ProofValidator::validate_amount_ranges(1500, 2000, 1000).is_err());
        // Min > max
    }

    #[test]
    fn test_validate_output_consistency() {
        let input = MockData::simple_valid_input();
        let output = MockData::simple_valid_output();

        let result = ProofValidator::validate_output_consistency(&input, &output);
        assert!(result.is_ok());

        // Test with mismatched output
        let mut bad_output = output;
        bad_output.root = [0u8; 32];
        let result = ProofValidator::validate_output_consistency(&input, &bad_output);
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("Root mismatch"));
    }
}
