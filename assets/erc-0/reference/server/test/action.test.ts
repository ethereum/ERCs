import { describe, it, expect } from "vitest";
import request from "supertest";
import type { Express } from "express";
import type { PrivateKeyAccount } from "viem/accounts";

import { buildChallengeMessage, generateSiweNonce } from "../src/siwe.js";
import { buildHarness, newSigner, type Harness } from "./helpers.js";

const TOKEN_ID = "412";
const ACTION = "feed";

/// Issue a challenge for the given token and action through the real endpoint.
async function issueChallenge(
  app: Express,
  account: PrivateKeyAccount,
  contract: string,
  tokenId = TOKEN_ID,
  action = ACTION,
  chainId = 1,
) {
  const res = await request(app).post("/challenge").send({
    account: account.address,
    chainId,
    contract,
    tokenId,
    action,
  });
  expect(res.status).toBe(200);
  return res.body.message as string;
}

/// Submit a signed message to /action for an explicitly declared target.
async function submitAction(
  app: Express,
  message: string,
  signature: string,
  contract: string,
  tokenId = TOKEN_ID,
  action = ACTION,
  chainId = 1,
) {
  return request(app).post("/action").send({
    message,
    signature,
    chainId,
    contract,
    tokenId,
    action,
  });
}

/// The happy path as reusable setup: mint ownership to the signer, issue,
///  sign, and return everything a test needs to submit.
async function primed(h: Harness) {
  const account = newSigner();
  h.chain.setOwner(h.config.contract, TOKEN_ID, account.address);
  const message = await issueChallenge(h.app, account, h.config.contract);
  const signature = await account.signMessage({ message });
  return { account, message, signature };
}

describe("POST /action", () => {
  it("succeeds end to end: runtime key signs a real challenge and the action runs", async () => {
    const h = buildHarness();
    const { account, message, signature } = await primed(h);

    const res = await submitAction(h.app, message, signature, h.config.contract);

    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.action).toBe(ACTION);
    expect(res.body.tokenId).toBe(TOKEN_ID);
    expect(res.body.account.toLowerCase()).toBe(account.address.toLowerCase());
    expect(res.body.executed).toBe(true);
  });

  it("rejects a replayed nonce (single use)", async () => {
    const h = buildHarness();
    const { message, signature } = await primed(h);

    const first = await submitAction(h.app, message, signature, h.config.contract);
    expect(first.status).toBe(200);

    const replay = await submitAction(h.app, message, signature, h.config.contract);
    expect(replay.status).toBe(401);
    expect(replay.body.error).toBe("nonce_invalid");
  });

  it("rejects an expired challenge", async () => {
    const h = buildHarness();
    const { message, signature } = await primed(h);

    // Move past the 300s challenge lifetime but stay within the 600s nonce
    // retention, so the message-expiry check fires rather than the nonce check.
    h.clock.advance(301_000);

    const res = await submitAction(h.app, message, signature, h.config.contract);
    expect(res.status).toBe(401);
    expect(res.body.error).toBe("challenge_expired");
  });

  it("rejects a message whose domain is a different verifier", async () => {
    const h = buildHarness();
    const account = newSigner();
    h.chain.setOwner(h.config.contract, TOKEN_ID, account.address);

    // A challenge that names a different issuer. Domain is checked before the
    // nonce, so this is refused even though the nonce was never issued here.
    const message = buildChallengeMessage({
      domain: "evil.example",
      uri: "https://evil.example/wallet-pass/actions",
      account: account.address,
      chainId: 1,
      contract: h.config.contract,
      tokenId: TOKEN_ID,
      action: ACTION,
      nonce: generateSiweNonce(),
      issuedAt: new Date(h.clock.now()),
      expirationTime: new Date(h.clock.now() + 300_000),
    });
    const signature = await account.signMessage({ message });

    const res = await submitAction(h.app, message, signature, h.config.contract);
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("domain_mismatch");
  });

  it("rejects a proof for action A redeemed for action B", async () => {
    const h = buildHarness();
    const account = newSigner();
    h.chain.setOwner(h.config.contract, TOKEN_ID, account.address);

    const message = await issueChallenge(h.app, account, h.config.contract, TOKEN_ID, "feed");
    const signature = await account.signMessage({ message });

    // Signed for "feed", redeemed for "water".
    const res = await submitAction(h.app, message, signature, h.config.contract, TOKEN_ID, "water");
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("binding_mismatch");
  });

  it("rejects a proof for token X redeemed for token Y", async () => {
    const h = buildHarness();
    const account = newSigner();
    h.chain.setOwner(h.config.contract, "412", account.address);
    h.chain.setOwner(h.config.contract, "999", account.address);

    const message = await issueChallenge(h.app, account, h.config.contract, "412", ACTION);
    const signature = await account.signMessage({ message });

    // Signed for token 412, redeemed for token 999.
    const res = await submitAction(h.app, message, signature, h.config.contract, "999", ACTION);
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("binding_mismatch");
  });

  it("rejects when ownership flips between challenge and action (transfer window)", async () => {
    const h = buildHarness();
    const account = newSigner();
    const buyer = newSigner();
    h.chain.setOwner(h.config.contract, TOKEN_ID, account.address);

    const message = await issueChallenge(h.app, account, h.config.contract);
    const signature = await account.signMessage({ message });

    // Token sold after the challenge was issued. The fresh read sees the buyer.
    h.chain.setOwner(h.config.contract, TOKEN_ID, buyer.address);

    const res = await submitAction(h.app, message, signature, h.config.contract);
    expect(res.status).toBe(403);
    expect(res.body.error).toBe("not_owner");
  });

  it("rejects a signature from the wrong account", async () => {
    const h = buildHarness();
    const account = newSigner();
    const impostor = newSigner();
    h.chain.setOwner(h.config.contract, TOKEN_ID, account.address);

    const message = await issueChallenge(h.app, account, h.config.contract);
    // The challenge claims `account`, but a different key signs it.
    const signature = await impostor.signMessage({ message });

    const res = await submitAction(h.app, message, signature, h.config.contract);
    expect(res.status).toBe(401);
    expect(res.body.error).toBe("signature_invalid");
  });

  it("rejects a message that does not parse as SIWE", async () => {
    const h = buildHarness();
    const account = newSigner();
    const message = "this is not a sign-in with ethereum message";
    const signature = await account.signMessage({ message });

    const res = await submitAction(h.app, message, signature, h.config.contract);
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("invalid_message");
  });

  it("refuses a challenge issued and signed for a different chain id", async () => {
    const h = buildHarness();
    const account = newSigner();
    h.chain.setOwner(h.config.contract, TOKEN_ID, account.address);

    // Message and target agree with each other on chain 137, so the binding
    // check alone would pass. The chain id is checked against the server's
    // configuration, not the request, and the ownership read only answers for
    // the configured chain.
    const message = await issueChallenge(h.app, account, h.config.contract, TOKEN_ID, ACTION, 137);
    const signature = await account.signMessage({ message });

    const res = await submitAction(h.app, message, signature, h.config.contract, TOKEN_ID, ACTION, 137);
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("invalid_request");
  });

  it("refuses a challenge issued and signed for a different contract", async () => {
    const h = buildHarness();
    const account = newSigner();
    const otherContract = newSigner().address;
    // The signer owns the token on the other contract too, so only the
    // configuration check can refuse this.
    h.chain.setOwner(h.config.contract, TOKEN_ID, account.address);
    h.chain.setOwner(otherContract, TOKEN_ID, account.address);

    const message = await issueChallenge(h.app, account, otherContract);
    const signature = await account.signMessage({ message });

    const res = await submitAction(h.app, message, signature, otherContract);
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("invalid_request");
  });

  it("refuses an acquire proof presented as an action", async () => {
    const h = buildHarness();
    const account = newSigner();
    h.chain.setOwner(h.config.contract, TOKEN_ID, account.address);

    // A valid acquire proof for the owner. "An acquire proof MUST NOT
    // authorize any other action", and here it is refused as an action at all.
    const acquire = h.config.acquireAction;
    const message = await issueChallenge(h.app, account, h.config.contract, TOKEN_ID, acquire);
    const signature = await account.signMessage({ message });

    const res = await submitAction(h.app, message, signature, h.config.contract, TOKEN_ID, acquire);
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("invalid_request");
    expect(res.body.executed).toBeUndefined();
  });

  it("refuses a malformed signature without crashing", async () => {
    const h = buildHarness();

    // Hex, but not a signature: the verifier throws and that is a bad
    // signature, not a server error.
    const truncated = await primed(h);
    const short = await submitAction(h.app, truncated.message, "0xdeadbeef", h.config.contract);
    expect(short.status).toBe(401);
    expect(short.body.error).toBe("signature_invalid");

    // Not hex at all: refused before any verifier sees it.
    const garbage = await primed(h);
    const notHex = await submitAction(h.app, garbage.message, "nothex", h.config.contract);
    expect(notHex.status).toBe(400);
    expect(notHex.body.error).toBe("invalid_request");
  });
});
