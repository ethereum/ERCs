This standard introduces an interface for creating fixed-supply collections of ERC-8004 Agent NFTs with mint number tracking and onchain collection metadata.

github.com/ethereum/ERCs/pull/1237

While ERC-8004 provides an unlimited mint registry for AI Agent identities, many use cases require limited collections (e.g., "Genesis 100", "Season 1"). ERC-8041 addresses this need by defining a standard interface for fixed-supply collections that leverage ERC-8004's existing onchain metadata capabilities.

The ERC defines:

- `getAgentMintNumber(tokenId)` - Returns an agent's permanent position in the collection (e.g., "#5 of 1000")
- `getCollectionDetails()` - Returns max supply, current supply, start block, and collection status
- Collection metadata stored via ERC-8004's onchain metadata using the `"agent-collection"` key
- Required events: `CollectionCreated` and `AgentMinted`

**Note on Direction Change:**
This ERC represents a strategic pivot. Originally planned as a standalone metadata standard interface, we've shifted to focus on a specific application (fixed-supply agent collections) that leverages existing onchain metadata functionality in ERC-8004. This allows immediate adoption while a future ERC will standardize the underlying Onchain Metadata interface itself.

I hope this proposal sparks discussion on fixed-supply agent collections, and I'd love feedback from anyone working on NFT infrastructure, AI agent registries, or collection management systems.

