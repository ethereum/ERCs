import {
  ContractFunctionExecutionError,
  ContractFunctionRevertedError,
  getAddress,
  type Address,
  type PublicClient,
} from "viem";

/// Reads current on-chain ownership.
///
///  The standard requires "a fresh on-chain read of ownership ... at the time
///  of the request, not at pass issuance and not at URL minting". Isolating
///  that read behind an interface keeps the authorization logic honest: it can
///  only ever ask for ownership now, and tests can flip the answer between
///  challenge issuance and action to exercise the transfer window.
export interface ChainReader {
  /// The current owner, or null when the token has no owner (never minted, or
  ///  burned). A reader MUST throw only when it could not obtain an answer (an
  ///  RPC failure), so that the verifier can tell "not entitled" from "unknown".
  ownerOf(contract: Address, tokenId: string): Promise<Address | null>;
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
      try {
        const owner = await client.readContract({
          address: contract,
          abi: OWNER_OF_ABI,
          functionName: "ownerOf",
          args: [BigInt(tokenId)],
        });
        return getAddress(owner);
      } catch (error) {
        // ERC-721 `ownerOf` reverts for a token that does not exist: that is
        // an answer (no owner), not a failed read. Anything else (transport,
        // timeout, a node that could not serve the call) is rethrown so the
        // verifier refuses as retryable rather than as "not the owner".
        if (error instanceof ContractFunctionExecutionError && error.cause instanceof ContractFunctionRevertedError) {
          return null;
        }
        throw error;
      }
    },
  };
}
