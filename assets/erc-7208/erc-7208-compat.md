
# On-Chain Data Container ERC
## Backwards Compatibility Analysis

**EIP-2309 (Consecutive batch minting)**: The ODC standard doesn't interfere with the batch minting process prescribed by EIP-2309. Instead, it offers an additional layer of customization for NFTs without affecting their creation process.

**EIP-2615 (Swap Orders)**: This standard does not disrupt the atomic swap functionality introduced by EIP-2615. ODCs may be involved in swap orders, with their properties intact.

**EIP-2981 (Royalties)**: The EIP-2981 standard for royalties is preserved under this proposal. ODCs can have royalties specified as one of their properties, providing added flexibility.

**ERC-3643 (Permissioned Tokens)**: ERC-3643 proposal defines *Security Token interface* based on ERC-20 token standard with additional requirement for sender and receiver of the token to be approved by the token issuer. This interface relies on the *OnchainID* system to provide Identity information, process KYC and other credentials, providing that data on-chain for token holders for minting, burning, and recovery of assets. Compatibility with this interface can be implemented as an ODC **Property Manager**, with the added benefit of a more versatile on-chain identity management derived from alternative **Property Managers**.

**EIP-4626 (Tokenized Vaults)**: Tokenized Vaults inherit from ERC-20 and ERC-2612 for approvals via EIP-712 secp256k1 signatures. For use-cases where NFTs are involved, the current proposal for an ODC can be leveraged to separate the vault logic away from the storage.

**ERC-4885 (Fractional Ownership)**: ODCs can represent fractional ownership, offering compatibility with ERC-4885. Additional properties can define the conditions of fractional ownership.

**ERC-4886 (Provably Rare Tokens)**: The new standard doesn't disrupt the functionality of provably rare tokens, but offers an additional layer of customization by allowing the setting of specific properties.

**ERC-4907 (Shared Ownership)**: ODCs can represent shared ownership and are therefore compatible with ERC-4907. The proposed properties can provide additional controls for such tokens.

**EIP-5050 (Interactive NFTs)**: The new standard compliments EIP-5050 by adding Properties, allowing for even richer interactions with NFTs.

**EIP-5095 (Principal Tokens)**: ODCs would be fully compatible with EIP-5095, and additional properties could be implemented to further define the parameters of a loan.

**EIP-5185 (Metadata Upgradeability)**: ODCs support metadata upgradeability. Their properties could serve as mutable metadata, making them compatible with EIP-5185.

**EIP-5409 (ERC-1155 extension)**: The proposed ODC standard is compatible with the ERC-1155 extension proposed by EIP-5409 and can further enhance the utility of ERC-1155 tokens by allowing storage and modification of properties.

**EIP-5505 (Asset-Backed NFTs)**: The proposed standard doesn't conflict with asset-backed NFTs and may provide additional controls or definitions for such tokens.

**EIP-5560 (Redeemable NFTs)**: ODCs can be redeemable and therefore compatible with EIP-5560. The properties associated with ODCs can provide additional control mechanisms for redeemable tokens.

**EIP-5633 (Composable Soulbound NFTs)**: ODCs can be composable and soulbound, thus compatible with EIP-5633. Furthermore, properties can provide further configuration for these types of tokens.

**ERC-6960 (Dual Layer Token Standard)**:

**ERC-7540 (Asynchronous ERC-4626 Tokenized Vaults)**:

