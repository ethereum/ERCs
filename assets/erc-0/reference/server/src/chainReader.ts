import { getAddress, type Address, type PublicClient } from "viem";

/// Reads current on-chain ownership.
///
///  The standard requires "a fresh on-chain read of ownership ... at the time
///  of the request, not at pass issuance and not at URL minting". Isolating
///  that read behind an interface keeps the authorization logic honest: it can
///  only ever ask for ownership now, and tests can flip the answer between
///  challenge issuance and action to exercise the transfer window.
export interface ChainReader {
  ownerOf(contract: Address, tokenId: string): Promise<Address>;
}

const OWNER_OF_ABI = [
  {
    type: "function",
    name: "ownerOf",
    stateMutability: "view",
    inputs: [{ name: "tokenId", type: "uint256" }],
    outputs: [{ name: "owner", type: "address" }],
  },
] as const;

/// Production reader: call ERC-721 `ownerOf` through a viem public client.
///
///  A real deployment SHOULD point the client at its best view of the latest
///  safe chain head (see the standard's Security Considerations on read
///  freshness and reorganizations); that is a client configuration concern and
///  is left to the operator.
export function publicClientChainReader(client: PublicClient): ChainReader {
  return {
    async ownerOf(contract, tokenId) {
      const owner = await client.readContract({
        address: contract,
        abi: OWNER_OF_ABI,
        functionName: "ownerOf",
        args: [BigInt(tokenId)],
      });
      return getAddress(owner);
    },
  };
}
