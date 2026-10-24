import { describe, it, expect } from "vitest";
import request from "supertest";
import type { PrivateKeyAccount } from "viem/accounts";

import {
  buildHarness,
  createClock,
  newSigner,
  capabilityTokenFromUrl,
  encodeProof,
  signChallenge,
  withProof,
  type Harness,
} from "./helpers.js";
import { createPassStore } from "../src/passStore.js";
import { defaultConfig } from "../src/config.js";

const TOKEN_ID = "412";

/// The full gated acquisition round trip for one account: fetch an acquire
///  challenge from the token's challenge endpoint, sign it, and present it.
///  Returns the proof alongside the response so a test can re-present it.
async function claimManifest(h: Harness, account: PrivateKeyAccount) {
  const challenge = await request(h.app).get(`/manifest/${TOKEN_ID}/challenge?address=${account.address}`);
  expect(challenge.status).toBe(200);
  const message = challenge.body.message as string;
  const signature = await account.signMessage({ message });
  const res = await presentProof(h, message, signature);
  return { message, signature, res };
}

/// Present an already-signed proof to the gated manifest endpoint.
function presentProof(h: Harness, message: string, signature: string) {
  return request(h.app)
    .get(`/manifest/${TOKEN_ID}`)
    .set("Wallet-Pass-Proof", encodeProof(message))
    .set("Wallet-Pass-Signature", signature);
}

describe("GET /manifest/:tokenId", () => {
  it("serves the manifest to anyone in the public configuration", async () => {
    const { app, config } = buildHarness({ manifestMode: "public" });

    const res = await request(app).get(`/manifest/${TOKEN_ID}`);

    expect(res.status).toBe(200);
    // Pass manifest: served as application/json, version 1 for this shape.
    expect(res.headers["content-type"]).toMatch(/^application\/json\b/);
    expect(res.body.version).toBe(1);
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

  it("points a refused gated fetch at the challenge endpoint, whose acquire challenge resolves the manifest", async () => {
    const h = buildHarness({ manifestMode: "gated" });
    const account = newSigner();
    h.chain.setOwner(h.config.contract, TOKEN_ID, account.address);

    const refused = await request(h.app).get(`/manifest/${TOKEN_ID}`);
    expect(refused.status).toBe(401);
    expect(refused.body.error).toBe("proof_required");
    expect(refused.body.challenge).toBe(`${h.config.baseUrl}/manifest/${TOKEN_ID}/challenge`);
    expect(refused.body.formats).toBeUndefined();

    const path = new URL(refused.body.challenge as string).pathname;
    const challenge = await request(h.app).get(`${path}?address=${account.address}`);
    expect(challenge.status).toBe(200);
    const message = challenge.body.message as string;
    expect(message).toContain("urn:wallet-pass:action:acquire");
    expect(message).toContain(`/${TOKEN_ID}`);

    const signature = await account.signMessage({ message });
    const res = await request(h.app)
      .get(`/manifest/${TOKEN_ID}`)
      .set("Wallet-Pass-Proof", encodeProof(message))
      .set("Wallet-Pass-Signature", signature);
    expect(res.status).toBe(200);
    expect(res.headers["cache-control"]).toBe("no-store");
    expect(res.body.formats.apple).toContain("/passes/apple/");
  });

  it("still accepts the X-prefixed proof header names earlier drafts used, preferring the unprefixed ones", async () => {
    const h = buildHarness({ manifestMode: "gated" });
    const account = newSigner();
    h.chain.setOwner(h.config.contract, TOKEN_ID, account.address);

    const first = await claimManifest(h, account);
    expect(first.res.status).toBe(200);

    // Legacy names alone resolve (the spec says a Pass Issuer MAY accept them).
    const { message, signature } = await signChallenge(h, account, TOKEN_ID, h.config.acquireAction);
    const legacy = await request(h.app)
      .get(`/manifest/${TOKEN_ID}`)
      .set("X-Wallet-Pass-Proof", encodeProof(message))
      .set("X-Wallet-Pass-Signature", signature);
    expect(legacy.status).toBe(200);
    expect(legacy.body.formats.apple).toContain("/passes/apple/");

    // Both forms present: the unprefixed one is used. A garbage legacy value
    // next to a good unprefixed proof must not break the request.
    const fresh = await signChallenge(h, account, TOKEN_ID, h.config.acquireAction);
    const both = await request(h.app)
      .get(`/manifest/${TOKEN_ID}`)
      .set("Wallet-Pass-Proof", encodeProof(fresh.message))
      .set("Wallet-Pass-Signature", fresh.signature)
      .set("X-Wallet-Pass-Proof", "not-a-proof")
      .set("X-Wallet-Pass-Signature", "0xdead");
    expect(both.status).toBe(200);
  });

  it("refuses a mixed pair of proof header names as invalid_request, in either direction", async () => {
    const h = buildHarness({ manifestMode: "gated" });
    const account = newSigner();
    h.chain.setOwner(h.config.contract, TOKEN_ID, account.address);

    const a = await signChallenge(h, account, TOKEN_ID);
    const plainProofLegacySig = await request(h.app)
      .get(`/manifest/${TOKEN_ID}`)
      .set("Wallet-Pass-Proof", encodeProof(a.message))
      .set("X-Wallet-Pass-Signature", a.signature);
    expect(plainProofLegacySig.status).toBe(400);
    expect(plainProofLegacySig.body.error).toBe("invalid_request");

    const b = await signChallenge(h, account, TOKEN_ID);
    const legacyProofPlainSig = await request(h.app)
      .get(`/manifest/${TOKEN_ID}`)
      .set("X-Wallet-Pass-Proof", encodeProof(b.message))
      .set("Wallet-Pass-Signature", b.signature);
    expect(legacyProofPlainSig.status).toBe(400);
    expect(legacyProofPlainSig.body.error).toBe("invalid_request");

    // The rotation route reads the same pair rule.
    const c = await signChallenge(h, account, TOKEN_ID, h.config.rotateAction);
    const rotateMixed = await request(h.app)
      .post(`/manifest/${TOKEN_ID}/rotate`)
      .set("Wallet-Pass-Proof", encodeProof(c.message))
      .set("X-Wallet-Pass-Signature", c.signature);
    expect(rotateMixed.status).toBe(400);
    expect(rotateMixed.body.error).toBe("invalid_request");

    // One header alone is still a missing proof, not a mixed pair.
    const half = await request(h.app).get(`/manifest/${TOKEN_ID}`).set("Wallet-Pass-Proof", encodeProof(a.message));
    expect(half.status).toBe(401);
    expect(half.body.error).toBe("proof_required");
  });

  it("re-mints action links bound to the owner at the first claim, so links minted before any claim never refuse the owner", async () => {
    const h = buildHarness({ manifestMode: "gated" });
    const owner = newSigner();
    h.chain.setOwner(h.config.contract, TOKEN_ID, owner.address);

    // A pass generator ran before any claim: its links were issued to no one.
    const early = new URL(h.passStore.actionLinks(TOKEN_ID).feed!).pathname;

    const claim = await claimManifest(h, owner);
    expect(claim.res.status).toBe(200);

    const current = new URL(h.passStore.actionLinks(TOKEN_ID).feed!).pathname;
    expect(current).not.toBe(early);
    expect((await request(h.app).post(early)).status).toBe(404);

    const tap = await request(h.app).post(current);
    expect(tap.status).toBe(200);
    expect(tap.body.executed).toBe(true);
    expect(tap.body.account).toBe(owner.address);
  });

  it("refuses the challenge endpoint without a valid claimed address", async () => {
    const { app } = buildHarness({ manifestMode: "gated" });
    const res = await request(app).get(`/manifest/${TOKEN_ID}/challenge`);
    expect(res.status).toBe(400);
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
      .set("Wallet-Pass-Proof", encodeProof(message))
      .set("Wallet-Pass-Signature", signature);

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
      .set("Wallet-Pass-Proof", encodeProof(message))
      .set("Wallet-Pass-Signature", signature);

    expect(res.status).toBe(400);
    expect(res.body.error).toBe("binding_mismatch");

    // The same refusal when the acquire URN is present but not in the
    // action's place: an acquire challenge with feed pushed in as the second
    // resource is a feed proof by position, and "a proof for any other action
    // MUST NOT resolve the manifest".
    const acquire = await request(h.app).get(`/manifest/${TOKEN_ID}/challenge?address=${account.address}`);
    const shuffled = (acquire.body.message as string).replace("Resources:\n", "Resources:\n- urn:wallet-pass:action:feed\n");
    expect(shuffled).not.toBe(acquire.body.message);
    const shuffledSignature = await account.signMessage({ message: shuffled });
    const out = await presentProof(h, shuffled, shuffledSignature);
    expect(out.status).toBe(400);
    expect(out.body.error).toBe("binding_mismatch");
    expect(out.body.formats).toBeUndefined();
  });

  it("carries the challenge URI on every 401 from the gated path", async () => {
    const h = buildHarness({ manifestMode: "gated" });
    const account = newSigner();
    h.chain.setOwner(h.config.contract, TOKEN_ID, account.address);
    const challengeUri = `${h.config.baseUrl}/manifest/${TOKEN_ID}/challenge`;

    // Replayed: the proof resolved once, so its nonce is spent.
    const first = await claimManifest(h, account);
    expect(first.res.status).toBe(200);
    const replay = await presentProof(h, first.message, first.signature);
    expect(replay.status).toBe(401);
    expect(replay.body.error).toBe("nonce_invalid");
    expect(replay.body.challenge).toBe(challengeUri);
    expect(replay.body.formats).toBeUndefined();

    // Badly signed: a hex string that is not a signature for the account.
    const fresh = await request(h.app).get(`/manifest/${TOKEN_ID}/challenge?address=${account.address}`);
    const badlySigned = await presentProof(h, fresh.body.message as string, "0xdeadbeef");
    expect(badlySigned.status).toBe(401);
    expect(badlySigned.body.error).toBe("signature_invalid");
    expect(badlySigned.body.challenge).toBe(challengeUri);

    // Expired: past the 300s challenge lifetime, within the 600s nonce retention.
    const stale = await request(h.app).get(`/manifest/${TOKEN_ID}/challenge?address=${account.address}`);
    const staleMessage = stale.body.message as string;
    const staleSignature = await account.signMessage({ message: staleMessage });
    h.clock.advance(301_000);
    const expired = await presentProof(h, staleMessage, staleSignature);
    expect(expired.status).toBe(401);
    expect(expired.body.error).toBe("challenge_expired");
    expect(expired.body.challenge).toBe(challengeUri);
  });

  it("refuses a malformed signature on the gated path without crashing", async () => {
    const h = buildHarness({ manifestMode: "gated" });
    const account = newSigner();
    h.chain.setOwner(h.config.contract, TOKEN_ID, account.address);

    const challenge = await request(h.app).get(`/manifest/${TOKEN_ID}/challenge?address=${account.address}`);
    const message = challenge.body.message as string;

    const truncated = await presentProof(h, message, "0xdeadbeef");
    expect(truncated.status).toBe(401);
    expect(truncated.body.error).toBe("signature_invalid");

    const notHex = await presentProof(h, message, "nothex");
    expect(notHex.status).toBe(400);
    expect(notHex.body.error).toBe("invalid_request");
  });

  it("answers a failed ownership read on the gated path as retryable, not as a refusal", async () => {
    const h = buildHarness({ manifestMode: "gated" });
    const account = newSigner();
    h.chain.setOwner(h.config.contract, TOKEN_ID, account.address);

    const challenge = await request(h.app).get(`/manifest/${TOKEN_ID}/challenge?address=${account.address}`);
    const message = challenge.body.message as string;
    const signature = await account.signMessage({ message });

    h.chain.failReads(true);
    const res = await presentProof(h, message, signature);
    expect(res.status).toBe(503);
    expect(res.body.error).toBe("read_failed");
    expect(res.headers["retry-after"]).toBe("5");
    expect(res.body.formats).toBeUndefined();
  });

  it("rotates acquisition URLs on a new owner's first claim, not on a repeat claim", async () => {
    const h = buildHarness({ manifestMode: "gated" });
    const seller = newSigner();
    const buyer = newSigner();
    h.chain.setOwner(h.config.contract, TOKEN_ID, seller.address);

    // The seller's first claim issues the URLs; a second claim by the same
    // account is not a first claim and leaves them alone.
    const sellerFirst = await claimManifest(h, seller);
    expect(sellerFirst.res.status).toBe(200);
    const sellerApple = sellerFirst.res.body.formats.apple as string;
    const sellerAgain = await claimManifest(h, seller);
    expect(sellerAgain.res.status).toBe(200);
    expect(sellerAgain.res.body.formats.apple).toBe(sellerApple);
    expect(sellerAgain.res.body.formats.google).toBe(sellerFirst.res.body.formats.google);

    const sellerToken = capabilityTokenFromUrl(sellerApple);
    expect((await request(h.app).get(`/passes/apple/${sellerToken}`)).status).toBe(200);

    // Sold. The buyer is a proven account that is not the account passes were
    // last issued to, so the URLs rotate before the manifest is returned.
    h.chain.setOwner(h.config.contract, TOKEN_ID, buyer.address);
    const buyerFirst = await claimManifest(h, buyer);
    expect(buyerFirst.res.status).toBe(200);
    const buyerApple = buyerFirst.res.body.formats.apple as string;
    expect(buyerApple).not.toBe(sellerApple);
    expect(buyerFirst.res.body.formats.google).not.toBe(sellerFirst.res.body.formats.google);

    const dead = await request(h.app).get(`/passes/apple/${sellerToken}`);
    expect(dead.status).toBe(404);
    expect(dead.body.error).toBe("unknown_capability");

    const live = await request(h.app).get(`/passes/apple/${capabilityTokenFromUrl(buyerApple)}`);
    expect(live.status).toBe(200);
    expect(live.body.tokenId).toBe(TOKEN_ID);

    // Rotation retires URLs; it is not a content change.
    expect(buyerFirst.res.body.updatedAt).toBe(sellerFirst.res.body.updatedAt);
  });

  it("treats every spelling of a token id as one token, so rotation reaches links issued under another spelling", async () => {
    const h = buildHarness({ manifestMode: "gated" });
    const seller = newSigner();
    const buyer = newSigner();
    const padded = `0${TOKEN_ID}`;
    // Ownership is recorded under the canonical id only: a claim through the
    // padded spelling must read the chain, and key the store, as `412`.
    h.chain.setOwner(h.config.contract, TOKEN_ID, seller.address);

    const claimAs = async (account: PrivateKeyAccount, spelling: string) => {
      const challenge = await request(h.app).get(`/manifest/${spelling}/challenge?address=${account.address}`);
      expect(challenge.status).toBe(200);
      const message = challenge.body.message as string;
      const signature = await account.signMessage({ message });
      return withProof(request(h.app).get(`/manifest/${spelling}`), message, signature);
    };

    // The seller acquires through the padded spelling. The URLs it gets name
    // the token canonically and work.
    const sellerRes = await claimAs(seller, padded);
    expect(sellerRes.status).toBe(200);
    const sellerApple = new URL(sellerRes.body.formats.apple as string).pathname;
    const sellerFeed = new URL(h.passStore.actionLinks(padded).feed!).pathname;
    const download = await request(h.app).get(sellerApple);
    expect(download.status).toBe(200);
    expect(download.body.tokenId).toBe(TOKEN_ID);
    expect((await request(h.app).post(sellerFeed)).status).toBe(200);

    // Sold. The buyer's first claim comes through the canonical spelling and
    // must rotate the seller's URLs, whichever spelling issued them.
    h.chain.setOwner(h.config.contract, TOKEN_ID, buyer.address);
    const buyerRes = await claimAs(buyer, TOKEN_ID);
    expect(buyerRes.status).toBe(200);
    expect((await request(h.app).get(sellerApple)).status).toBe(404);
    expect((await request(h.app).post(sellerFeed)).status).toBe(404);

    // A repeat claim by the buyer under the other spelling is not a first
    // claim, so nothing rotates; an owner rotation under one spelling then
    // retires the URLs obtained under the other.
    const buyerAgain = await claimAs(buyer, padded);
    expect(buyerAgain.status).toBe(200);
    expect(buyerAgain.body.formats.apple).toBe(buyerRes.body.formats.apple);
    const buyerApple = new URL(buyerRes.body.formats.apple as string).pathname;
    const rotate = await signChallenge(h, buyer, TOKEN_ID, "rotate");
    const rotated = await withProof(request(h.app).post(`/manifest/${TOKEN_ID}/rotate`), rotate.message, rotate.signature);
    expect(rotated.status).toBe(200);
    expect((await request(h.app).get(buyerApple)).status).toBe(404);

    // The canonical form is bounded to uint256, as `ownerOf` is: the largest
    // id is a token (refused here only for want of a proof), one past it is
    // not an id at all.
    const max = (1n << 256n) - 1n;
    expect((await request(h.app).get(`/manifest/${max}`)).status).toBe(401);
    const tooBig = await request(h.app).get(`/manifest/${max + 1n}`);
    expect(tooBig.status).toBe(400);
    expect(tooBig.body.error).toBe("invalid_request");
  });
});

describe("capability URL rotation", () => {
  it("invalidates the old capability tokens when a token transfers", () => {
    const config = defaultConfig();
    const clock = createClock();
    const store = createPassStore(config, clock.now);

    const before = store.getManifest(TOKEN_ID);
    const oldApple = capabilityTokenFromUrl(before.formats.apple);
    const oldGoogle = capabilityTokenFromUrl(before.formats.google);
    expect(store.resolveCapability(oldApple)).toEqual({ tokenId: TOKEN_ID, format: "apple" });
    expect(store.resolveCapability(oldGoogle)).toEqual({ tokenId: TOKEN_ID, format: "google" });

    clock.advance(3_600_000);
    const after = store.rotateOnTransfer(TOKEN_ID);
    const newApple = capabilityTokenFromUrl(after.formats.apple);

    // Old URLs stop resolving; the new one resolves.
    expect(store.resolveCapability(oldApple)).toBeNull();
    expect(store.resolveCapability(oldGoogle)).toBeNull();
    expect(newApple).not.toBe(oldApple);
    expect(store.resolveCapability(newApple)).toEqual({ tokenId: TOKEN_ID, format: "apple" });

    // `updatedAt` reflects content freshness only and says nothing about
    // acquisition URL validity, so rotation leaves it untouched.
    expect(after.updatedAt).toBe(before.updatedAt);
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
