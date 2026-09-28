import type { Express } from "express";
import { expect } from "vitest";
import request from "supertest";
import { generatePrivateKey, privateKeyToAccount, type PrivateKeyAccount } from "viem/accounts";
import type { Address } from "viem";

import { defaultConfig, type ServerConfig } from "../src/config.js";
import { createNonceStore } from "../src/nonceStore.js";
import { eoaSignatureVerifier } from "../src/verifiers.js";
import { createPassStore, type PassStore } from "../src/passStore.js";
import type { ChainReader } from "../src/chainReader.js";
import { createApp } from "../src/app.js";

/// A controllable clock so tests can move "now" forward across the transfer and
///  expiry windows the standard cares about. Its default start is the instant
///  in the spec's worked example, 2026-08-07T15:04:05Z.
export function createClock(startMs: number = Date.UTC(2026, 7, 7, 15, 4, 5)) {
  let t = startMs;
  return {
    now: () => t,
    set: (value: number) => {
      t = value;
    },
    advance: (ms: number) => {
      t += ms;
    },
  };
}

/// A fake owner map that stands in for a chain. Tests set ownership, and can
///  flip or clear it between challenge issuance and action to drive the
///  fresh-read check. An unset token reads as having no owner (null), which is
///  how the production reader reports a token that was never minted or was
///  burned. `failReads` makes every read throw, standing in for an RPC outage.
export class FakeChainReader implements ChainReader {
  private owners = new Map<string, Address>();
  private failing = false;

  failReads(failing: boolean): void {
    this.failing = failing;
  }

  setOwner(contract: Address, tokenId: string, owner: Address): void {
    this.owners.set(this.key(contract, tokenId), owner);
  }

  clearOwner(contract: Address, tokenId: string): void {
    this.owners.delete(this.key(contract, tokenId));
  }

  async ownerOf(contract: Address, tokenId: string): Promise<Address | null> {
    if (this.failing) {
      throw new Error("rpc unavailable");
    }
    return this.owners.get(this.key(contract, tokenId)) ?? null;
  }

  private key(contract: Address, tokenId: string): string {
    return `${contract.toLowerCase()}:${tokenId}`;
  }
}

/// A throwaway signing account, generated at runtime. No private key literal
///  ever appears in the source.
export function newSigner(): PrivateKeyAccount {
  return privateKeyToAccount(generatePrivateKey());
}

export interface Harness {
  app: Express;
  config: ServerConfig;
  chain: FakeChainReader;
  passStore: PassStore;
  clock: ReturnType<typeof createClock>;
}

/// Assemble the server with the test collaborators: the EOA-only verifier (so
///  no chain is needed to check signatures), a fake chain reader, and a
///  controllable clock shared by the app and its authorization logic.
export function buildHarness(configOverrides: Partial<ServerConfig> = {}): Harness {
  const config = defaultConfig(configOverrides);
  const clock = createClock();
  const chain = new FakeChainReader();
  const passStore = createPassStore(config, clock.now);
  const app = createApp({
    config,
    nonces: createNonceStore(),
    verifier: eoaSignatureVerifier(),
    chain,
    passStore,
    now: clock.now,
  });
  return { app, config, chain, passStore, clock };
}

/// Pull a capability token out of an acquisition URL of the form
///  https://issuer.example/passes/apple/<token>.
export function capabilityTokenFromUrl(url: string): string {
  const parts = url.split("/");
  return parts[parts.length - 1] ?? "";
}

/// Base64url-encode a SIWE message for transport in a request header, since a
///  header cannot carry the message's line breaks. Mirrors checkGatedProof.
export function encodeProof(message: string): string {
  return Buffer.from(message, "utf8").toString("base64url");
}

/// Fetch a token's challenge for `account` from the challenge endpoint a gated
///  401 points at (acquire by default; the rotate action on request) and sign
///  it, returning the proof a test presents in headers.
export async function signChallenge(
  h: Harness,
  account: PrivateKeyAccount,
  tokenId: string,
  action?: string,
): Promise<{ message: string; signature: string }> {
  const query = action ? `&action=${action}` : "";
  const res = await request(h.app).get(`/manifest/${tokenId}/challenge?address=${account.address}${query}`);
  expect(res.status).toBe(200);
  const message = res.body.message as string;
  const signature = await account.signMessage({ message });
  return { message, signature };
}

/// Attach a signed proof to a request in the two headers Gated acquisition
///  defines.
export function withProof(req: request.Test, message: string, signature: string): request.Test {
  return req.set("X-Wallet-Pass-Proof", encodeProof(message)).set("X-Wallet-Pass-Signature", signature);
}
