import { describe, it, expect } from "vitest";
import request from "supertest";

import { buildHarness, newSigner, capabilityTokenFromUrl } from "./helpers.js";
import { createPassStore } from "../src/passStore.js";
import { defaultConfig } from "../src/config.js";

const TOKEN_ID = "412";

/// Base64url-encode a SIWE message for transport in a request header, since a
///  header cannot carry the message's line breaks. Mirrors checkGatedProof.
function encodeProof(message: string): string {
  return Buffer.from(message, "utf8").toString("base64url");
}

describe("GET /manifest/:tokenId", () => {
  it("serves the manifest to anyone in the public configuration", async () => {
    const { app, config } = buildHarness({ manifestMode: "public" });

    const res = await request(app).get(`/manifest/${TOKEN_ID}`);

    expect(res.status).toBe(200);
    expect(res.body.formats.apple).toContain(`${config.baseUrl}/passes/apple/`);
    expect(res.body.formats.google).toContain(`${config.baseUrl}/passes/google/`);
    expect(Number.isInteger(res.body.updatedAt)).toBe(true);
  });

  it("refuses a gated manifest without a control proof", async () => {
    const { app } = buildHarness({ manifestMode: "gated" });

    const res = await request(app).get(`/manifest/${TOKEN_ID}`);

    expect(res.status).toBe(401);
    expect(res.body.error).toBe("proof_required");
  });

  it("serves a gated manifest with a valid acquire proof", async () => {
    const h = buildHarness({ manifestMode: "gated" });
    const account = newSigner();
    h.chain.setOwner(h.config.contract, TOKEN_ID, account.address);

    // The proof reuses the challenge flow with the acquire action, bound to the
    // server's configured chain and contract.
    const challenge = await request(h.app).post("/challenge").send({
      account: account.address,
      chainId: h.config.chainId,
      contract: h.config.contract,
      tokenId: TOKEN_ID,
      action: h.config.acquireAction,
    });
    expect(challenge.status).toBe(200);
    const message = challenge.body.message as string;
    const signature = await account.signMessage({ message });

    const res = await request(h.app)
      .get(`/manifest/${TOKEN_ID}`)
      .set("X-Wallet-Pass-Proof", encodeProof(message))
      .set("X-Wallet-Pass-Signature", signature);

    expect(res.status).toBe(200);
    expect(res.body.formats.apple).toContain("/passes/apple/");
  });

  it("refuses a gated manifest when the proof is for a different action", async () => {
    const h = buildHarness({ manifestMode: "gated" });
    const account = newSigner();
    h.chain.setOwner(h.config.contract, TOKEN_ID, account.address);

    // A proof for "feed" cannot resolve a manifest gated behind "acquire".
    const challenge = await request(h.app).post("/challenge").send({
      account: account.address,
      chainId: h.config.chainId,
      contract: h.config.contract,
      tokenId: TOKEN_ID,
      action: "feed",
    });
    const message = challenge.body.message as string;
    const signature = await account.signMessage({ message });

    const res = await request(h.app)
      .get(`/manifest/${TOKEN_ID}`)
      .set("X-Wallet-Pass-Proof", encodeProof(message))
      .set("X-Wallet-Pass-Signature", signature);

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("binding_mismatch");
  });
});

describe("capability URL rotation", () => {
  it("invalidates the old capability tokens when a token transfers", () => {
    const config = defaultConfig();
    const store = createPassStore(config);

    const before = store.getManifest(TOKEN_ID);
    const oldApple = capabilityTokenFromUrl(before.formats.apple);
    const oldGoogle = capabilityTokenFromUrl(before.formats.google);
    expect(store.resolveCapability(oldApple)).toEqual({ tokenId: TOKEN_ID, format: "apple" });
    expect(store.resolveCapability(oldGoogle)).toEqual({ tokenId: TOKEN_ID, format: "google" });

    const after = store.rotateOnTransfer(TOKEN_ID);
    const newApple = capabilityTokenFromUrl(after.formats.apple);

    // Old URLs stop resolving; the new one resolves.
    expect(store.resolveCapability(oldApple)).toBeNull();
    expect(store.resolveCapability(oldGoogle)).toBeNull();
    expect(newApple).not.toBe(oldApple);
    expect(store.resolveCapability(newApple)).toEqual({ tokenId: TOKEN_ID, format: "apple" });
  });

  it("stops resolving a rotated capability URL over HTTP", async () => {
    const { app, passStore } = buildHarness();

    const before = passStore.getManifest(TOKEN_ID);
    const oldApple = capabilityTokenFromUrl(before.formats.apple);

    const live = await request(app).get(`/passes/apple/${oldApple}`);
    expect(live.status).toBe(200);
    expect(live.body.tokenId).toBe(TOKEN_ID);

    passStore.rotateOnTransfer(TOKEN_ID);

    const dead = await request(app).get(`/passes/apple/${oldApple}`);
    expect(dead.status).toBe(404);
    expect(dead.body.error).toBe("unknown_capability");
  });
});
