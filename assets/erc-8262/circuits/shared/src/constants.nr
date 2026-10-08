/// Constants shared across ERC-8262 circuits

/// Maximum number of screening providers supported
pub global MAX_PROVIDERS: u32 = 8;

/// Merkle tree depth for membership/non-membership proofs
pub global MERKLE_DEPTH: u32 = 20;

/// Maximum number of transactions for pattern (anti-structuring) analysis
pub global MAX_TRANSACTIONS: u32 = 16;

/// Jurisdiction IDs (must match Solidity JurisdictionConfig)
pub global JURISDICTION_EU: u8 = 0;
pub global JURISDICTION_US: u8 = 1;
pub global JURISDICTION_UK: u8 = 2;
pub global JURISDICTION_SG: u8 = 3;
pub global JURISDICTION_UAE: u8 = 4;
