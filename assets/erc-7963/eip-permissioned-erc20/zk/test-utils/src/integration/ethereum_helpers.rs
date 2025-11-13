use ethers::{
    prelude::*,
    providers::{Http, Provider},
    signers::{LocalWallet, Signer},
    types::{Address, U256, Bytes, TransactionReceipt, Log, H256, TransactionRequest},
    contract::Contract,
    abi::{Abi, Tokenize},
    middleware::SignerMiddleware,
};
use std::sync::Arc;
use std::time::Duration;
use anyhow::{Result, anyhow};

/// Configuration for Ethereum connection
#[derive(Debug, Clone)]
pub struct EthereumConfig {
    pub rpc_url: String,
    pub chain_id: u64,
    pub private_key: String,
    pub gas_limit: u64,
    pub gas_price: Option<U256>,
}

impl Default for EthereumConfig {
    fn default() -> Self {
        Self {
            rpc_url: "http://localhost:8545".to_string(), // Anvil default
            chain_id: 31337, // Anvil default chain ID
            private_key: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80".to_string(), // Anvil default key
            gas_limit: 3_000_000,
            gas_price: None, // Use network default
        }
    }
}

/// Ethereum client wrapper for contract interactions
pub struct EthereumClient {
    pub provider: Arc<Provider<Http>>,
    pub wallet: LocalWallet,
    pub signer: Arc<SignerMiddleware<Arc<Provider<Http>>, LocalWallet>>,
    pub config: EthereumConfig,
}

impl EthereumClient {
    /// Create a new Ethereum client
    pub async fn new(config: EthereumConfig) -> Result<Self> {
        let provider = Provider::<Http>::try_from(&config.rpc_url)?
            .interval(Duration::from_millis(100));
        
        let wallet = config.private_key.parse::<LocalWallet>()?
            .with_chain_id(config.chain_id);
        
        let provider = Arc::new(provider);
        let signer = Arc::new(SignerMiddleware::new(provider.clone(), wallet.clone()));
        
        Ok(Self {
            provider,
            wallet,
            signer,
            config,
        })
    }
    
    /// Get the client's address
    pub fn address(&self) -> Address {
        self.wallet.address()
    }
    
    /// Get current block number
    pub async fn block_number(&self) -> Result<U256> {
        let block_num = self.provider.get_block_number().await?;
        Ok(U256::from(block_num.as_u64()))
    }
    
    /// Get balance of an address
    pub async fn balance(&self, address: Address) -> Result<U256> {
        Ok(self.provider.get_balance(address, None).await?)
    }
    
    /// Deploy a contract
    pub async fn deploy_contract(
        &self,
        bytecode: Bytes,
        constructor_args: Option<Bytes>,
    ) -> Result<Address> {
        let mut deployment_tx = TransactionRequest::new()
            .data(bytecode)
            .gas(self.config.gas_limit);
        
        if let Some(args) = constructor_args {
            deployment_tx = deployment_tx.data(args);
        }
        
        if let Some(gas_price) = self.config.gas_price {
            deployment_tx = deployment_tx.gas_price(gas_price);
        }
        
        let pending_tx = self.signer.send_transaction(deployment_tx, None).await?;
        let receipt = pending_tx.await?.ok_or_else(|| anyhow!("Transaction failed"))?;
        
        receipt.contract_address.ok_or_else(|| anyhow!("No contract address in receipt"))
    }
    
    /// Create a contract instance
    pub fn contract<T: Tokenize>(&self, address: Address, abi: Abi) -> Contract<Arc<SignerMiddleware<Arc<Provider<Http>>, LocalWallet>>> {
        Contract::new(address, abi, self.signer.clone())
    }
    
    /// Wait for transaction confirmation
    pub async fn wait_for_confirmation(&self, tx_hash: H256) -> Result<TransactionReceipt> {
        let receipt = self.provider
            .get_transaction_receipt(tx_hash)
            .await?
            .ok_or_else(|| anyhow!("Transaction not found"))?;
        Ok(receipt)
    }
    
    /// Estimate gas for a transaction
    pub async fn estimate_gas(&self, tx: &TransactionRequest) -> Result<U256> {
        // Convert TransactionRequest to TypedTransaction for estimate_gas
        let typed_tx = tx.clone().into();
        Ok(self.provider.estimate_gas(&typed_tx, None).await?)
    }
}

/// Contract deployment helper
pub struct ContractDeployer {
    client: Arc<EthereumClient>,
}

impl ContractDeployer {
    pub fn new(client: Arc<EthereumClient>) -> Self {
        Self { client }
    }
    
    /// Deploy RiscZeroVerifier contract
    pub async fn deploy_risc_zero_verifier(&self) -> Result<Address> {
        // This would contain the actual bytecode for RiscZeroVerifier
        // For now, we'll use a placeholder
        let bytecode = Bytes::from_static(&[0x60, 0x80, 0x60, 0x40]); // Placeholder
        self.client.deploy_contract(bytecode, None).await
    }
    
    /// Deploy TransferOracle contract
    pub async fn deploy_transfer_oracle(
        &self,
        verifier_address: Address,
        token_address: Address,
        issuer_address: Address,
    ) -> Result<Address> {
        // This would contain the actual bytecode and constructor encoding
        let bytecode = Bytes::from_static(&[0x60, 0x80, 0x60, 0x40]); // Placeholder
        let constructor_args = ethers::abi::encode(&[
            ethers::abi::Token::Address(verifier_address),
            ethers::abi::Token::Address(token_address),
            ethers::abi::Token::Address(issuer_address),
        ]);
        
        self.client.deploy_contract(bytecode, Some(Bytes::from(constructor_args))).await
    }
    
    /// Deploy PermissionedERC20 contract
    pub async fn deploy_permissioned_erc20(
        &self,
        name: String,
        symbol: String,
        oracle_address: Address,
        owner_address: Address,
    ) -> Result<Address> {
        // This would contain the actual bytecode and constructor encoding
        let bytecode = Bytes::from_static(&[0x60, 0x80, 0x60, 0x40]); // Placeholder
        let constructor_args = ethers::abi::encode(&[
            ethers::abi::Token::String(name),
            ethers::abi::Token::String(symbol),
            ethers::abi::Token::Address(oracle_address),
            ethers::abi::Token::Address(owner_address),
        ]);
        
        self.client.deploy_contract(bytecode, Some(Bytes::from(constructor_args))).await
    }
}

/// Transaction helper utilities
pub struct TransactionHelper {
    client: Arc<EthereumClient>,
}

impl TransactionHelper {
    pub fn new(client: Arc<EthereumClient>) -> Self {
        Self { client }
    }
    
    /// Send a transaction and wait for confirmation
    pub async fn send_and_confirm(&self, tx: TransactionRequest) -> Result<TransactionReceipt> {
        let pending_tx = self.client.signer.send_transaction(tx, None).await?;
        let receipt = pending_tx.await?.ok_or_else(|| anyhow!("Transaction failed"))?;
        Ok(receipt)
    }
    
    /// Get transaction gas usage
    pub fn get_gas_used(receipt: &TransactionReceipt) -> U256 {
        receipt.gas_used.unwrap_or_default()
    }
    
    /// Calculate transaction cost
    pub fn calculate_cost(receipt: &TransactionReceipt, gas_price: U256) -> U256 {
        Self::get_gas_used(receipt) * gas_price
    }
}

/// Event monitoring utilities
pub struct EventMonitor {
    client: Arc<EthereumClient>,
}

impl EventMonitor {
    pub fn new(client: Arc<EthereumClient>) -> Self {
        Self { client }
    }
    
    /// Monitor for TransferApproved events
    pub async fn wait_for_transfer_approved(
        &self,
        contract_address: Address,
        from_block: Option<U256>,
    ) -> Result<Vec<Log>> {
        // This would implement actual event filtering
        // For now, return empty vector
        Ok(vec![])
    }
    
    /// Monitor for ApprovalConsumed events
    pub async fn wait_for_approval_consumed(
        &self,
        contract_address: Address,
        from_block: Option<U256>,
    ) -> Result<Vec<Log>> {
        // This would implement actual event filtering
        // For now, return empty vector
        Ok(vec![])
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[tokio::test]
    async fn test_ethereum_config_default() {
        let config = EthereumConfig::default();
        assert_eq!(config.rpc_url, "http://localhost:8545");
        assert_eq!(config.chain_id, 31337);
        assert_eq!(config.gas_limit, 3_000_000);
    }
    
    #[tokio::test]
    #[ignore] // Requires running Ethereum node
    async fn test_ethereum_client_creation() {
        let config = EthereumConfig::default();
        let result = EthereumClient::new(config).await;
        
        // This test would pass if Anvil is running
        match result {
            Ok(client) => {
                assert_eq!(client.config.chain_id, 31337);
            }
            Err(_) => {
                // Expected if no Ethereum node is running
                println!("Ethereum node not available for testing");
            }
        }
    }
} 