import { createPublicClient, http, getAddress } from "viem";

import { defaultConfig, type ManifestMode } from "./config.js";
import { createNonceStore } from "./nonceStore.js";
import { publicClientSignatureVerifier, type SignatureVerifier } from "./verifiers.js";
import { publicClientChainReader, type ChainReader } from "./chainReader.js";
import { createPassStore } from "./passStore.js";
import { createApp } from "./app.js";

/// Bootstrap for running the reference server locally. It wires the production
///  collaborators: a viem public client provides both the ERC-1271-capable
///  signature verifier and the fresh `ownerOf` reader. Configuration comes from
///  the environment, falling back to the values in the spec's worked example.
///
///  Set RPC_URL to a node for the configured chain so that ownership reads and
///  contract-account signature checks resolve. Without it, challenge issuance
///  and public manifests still work; action authorization and gated manifests
///  fail only when they reach the chain, with a message saying to set RPC_URL.
function main(): void {
  const config = defaultConfig({
    domain: process.env.DOMAIN ?? undefined,
    chainId: process.env.CHAIN_ID ? Number(process.env.CHAIN_ID) : undefined,
    contract: process.env.CONTRACT ? getAddress(process.env.CONTRACT) : undefined,
    manifestMode: (process.env.MANIFEST_MODE as ManifestMode | undefined) ?? undefined,
    capabilityActions: process.env.CAPABILITY_ACTIONS ? process.env.CAPABILITY_ACTIONS.split(",") : undefined,
  });

  let verifier: SignatureVerifier;
  let chain: ChainReader;
  if (process.env.RPC_URL) {
    const client = createPublicClient({ transport: http(process.env.RPC_URL) });
    verifier = publicClientSignatureVerifier(client);
    chain = publicClientChainReader(client);
  } else {
    console.warn("RPC_URL is not set: action authorization and gated manifests will fail until it is.");
    verifier = { verify: () => rpcRequired() };
    chain = { ownerOf: () => rpcRequired() };
  }

  const app = createApp({
    config,
    nonces: createNonceStore(),
    verifier,
    chain,
    passStore: createPassStore(config),
  });

  const port = Number(process.env.PORT ?? 8787);
  app.listen(port, () => {
    console.log(`wallet-pass reference server listening on :${port}`);
    console.log(`  domain=${config.domain} chainId=${config.chainId} manifestMode=${config.manifestMode}`);
  });
}

/// Fail an on-chain operation with a clear reason when no node is configured.
function rpcRequired(): never {
  throw new Error("RPC_URL is required for on-chain reads and contract-account signature checks");
}

main();
