import { describe, it, expect } from "vitest";
import request from "supertest";
import type { Express } from "express";
import type { PrivateKeyAccount } from "viem/accounts";

import { buildChallengeMessage, generateSiweNonce } from "../src/siwe.js";
import { getAddress, isAddressEqual, recoverMessageAddress, type Address, type Hex } from "viem";
import { createApp } from "../src/app.js";
import { defaultConfig } from "../src/config.js";
import { createNonceStore } from "../src/nonceStore.js";
import { createPassStore } from "../src/passStore.js";
import { eoaSignatureVerifier, type SignatureVerifier } from "../src/verifiers.js";
import { buildHarness, createClock, encodeProof, FakeChainReader, newSigner, type Harness } from "./helpers.js";

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

    // Inside the repeat window an identical request is answered with the first
    // outcome (see repeat.test.ts); the replay check is on the nonce itself,
    // which the first request spent.
    h.clock.advance(h.config.repeatWindowSeconds * 1000);
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

  it("refuses an oversized message before parsing it (quadratic SIWE parse)", async () => {
    const h = buildHarness();
    // Repeated "URI: " with no newline is the worst case for the SIWE parser
    // (quadratic); 90 KB of it, under the old 100 KB body default, parsed for over a second.
    const message = "URI: ".repeat(18_000);
    const t0 = performance.now();
    const res = await submitAction(h.app, message, `0x${"ab".repeat(65)}`, h.config.contract);
    const elapsed = performance.now() - t0;
    expect([400, 413]).toContain(res.status);
    expect(elapsed).toBeLessThan(500);
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

  it("rejects a proof whose resources carry the action out of position", async () => {
    const h = buildHarness();
    const account = newSigner();
    h.chain.setOwner(h.config.contract, TOKEN_ID, account.address);

    // A feed challenge, re-serialized with the acquire URN pushed in as the
    // second resource and feed demoted to third. Both URNs are still present;
    // by the fixed places the spec gives them (the token first, the action
    // second) this is an acquire proof, and an acquire proof cannot run feed.
    const issued = await issueChallenge(h.app, account, h.config.contract);
    const message = issued.replace("Resources:\n", `Resources:\n- urn:wallet-pass:action:${h.config.acquireAction}\n`);
    expect(message).not.toBe(issued);
    const signature = await account.signMessage({ message });

    const res = await submitAction(h.app, message, signature, h.config.contract);
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("binding_mismatch");
    expect(res.body.executed).toBeUndefined();
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

  it("refuses a token with no owner as not_owner, and a failed read as retryable", async () => {
    const h = buildHarness();
    const account = newSigner();
    h.chain.setOwner(h.config.contract, TOKEN_ID, account.address);

    // Burned (or never minted) between challenge and action: the fresh read
    // answers "no owner", and the claimant is refused as not the owner.
    const burned = await issueChallenge(h.app, account, h.config.contract);
    const burnedSignature = await account.signMessage({ message: burned });
    h.chain.clearOwner(h.config.contract, TOKEN_ID);
    const gone = await submitAction(h.app, burned, burnedSignature, h.config.contract);
    expect(gone.status).toBe(403);
    expect(gone.body.error).toBe("not_owner");

    // The read could not be taken at all: fail closed, but as retryable, and
    // never as a verdict on ownership. The 403 stays reserved for entitlement.
    h.chain.setOwner(h.config.contract, TOKEN_ID, account.address);
    const message = await issueChallenge(h.app, account, h.config.contract);
    const signature = await account.signMessage({ message });
    h.chain.failReads(true);
    const outage = await submitAction(h.app, message, signature, h.config.contract);
    expect(outage.status).toBe(503);
    expect(outage.body.error).toBe("read_failed");
    expect(outage.headers["retry-after"]).toBe("5");
    expect(outage.body.executed).toBeUndefined();
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

/// A contract account (ERC-1271) as a verifier sees it: the account has no
///  key of its own, and its `isValidSignature` accepts a signature made by its
///  keyholder, wrapped with a trailing 32-byte marker so it is longer than an
///  EOA signature. The injected verifier stands in for the chain call that the
///  production verifier makes, and falls through to EOA recovery otherwise.
function contractAccountVerifier(contractAccount: Address, keyholder: Address): SignatureVerifier {
  const eoa = eoaSignatureVerifier();
  const marker = "c0".repeat(32);
  return {
    async verify({ address, message, signature }) {
      if (!isAddressEqual(address, contractAccount)) {
        return eoa.verify({ address, message, signature });
      }
      if (signature.length !== 2 + 130 + 64 || !signature.endsWith(marker)) {
        return false;
      }
      const inner = signature.slice(0, 2 + 130) as Hex;
      return isAddressEqual(await recoverMessageAddress({ message, signature: inner }), keyholder);
    },
  };
}

describe("contract-account signatures (ERC-1271)", () => {
  it("authorizes an action for a contract account through an injected verifier, and refuses a wrong signature", async () => {
    const config = defaultConfig({ manifestMode: "gated" });
    const clock = createClock();
    const chain = new FakeChainReader();
    const keyholder = newSigner();
    const intruder = newSigner();
    const contractAccount = getAddress("0x00000000000000000000000000000000c0ffee01");
    const app = createApp({
      config,
      nonces: createNonceStore(),
      verifier: contractAccountVerifier(contractAccount, keyholder.address),
      chain,
      passStore: createPassStore(config, clock.now),
      now: clock.now,
    });
    chain.setOwner(config.contract, TOKEN_ID, contractAccount);
    const wrap1271 = (sig: Hex) => `${sig}${"c0".repeat(32)}`;

    const challengeFor = async () => {
      const res = await request(app)
        .post("/challenge")
        .send({ account: contractAccount, chainId: 1, contract: config.contract, tokenId: TOKEN_ID, action: ACTION });
      expect(res.status).toBe(200);
      return res.body.message as string;
    };

    // The keyholder signs for the contract account: the proof verifies, the
    // fresh read names the contract account, and the action runs for it.
    const message = await challengeFor();
    const ok = await submitAction(app, message, wrap1271(await keyholder.signMessage({ message })), config.contract);
    expect(ok.status).toBe(200);
    expect(ok.body.executed).toBe(true);
    expect(ok.body.account).toBe(contractAccount);

    // Someone else's key, wrapped the same way, is not the account's signature.
    const second = await challengeFor();
    const bad = await submitAction(app, second, wrap1271(await intruder.signMessage({ message: second })), config.contract);
    expect(bad.status).toBe(401);
    expect(bad.body.error).toBe("signature_invalid");

    // The gated manifest path takes the same verifier.
    const acquire = await request(app).get(`/manifest/${TOKEN_ID}/challenge?address=${contractAccount}`);
    expect(acquire.status).toBe(200);
    const acquireMessage = acquire.body.message as string;
    const manifest = await request(app)
      .get(`/manifest/${TOKEN_ID}`)
      .set("Wallet-Pass-Proof", encodeProof(acquireMessage))
      .set("Wallet-Pass-Signature", wrap1271(await keyholder.signMessage({ message: acquireMessage })));
    expect(manifest.status).toBe(200);
    expect(manifest.body.formats.apple).toContain("/passes/apple/");
  });
});
