import { describe, it, expect } from "vitest";
import request from "supertest";
import type { Express } from "express";
import type { PrivateKeyAccount } from "viem/accounts";

import { createRepeatStore, requestKey } from "../src/repeatStore.js";
import { buildHarness, newSigner, signChallenge, withProof, type Harness } from "./helpers.js";

const TOKEN_ID = "412";
const ACTION = "feed";

async function issueChallenge(app: Express, account: PrivateKeyAccount, contract: string) {
  const res = await request(app).post("/challenge").send({
    account: account.address,
    chainId: 1,
    contract,
    tokenId: TOKEN_ID,
    action: ACTION,
  });
  expect(res.status).toBe(200);
  return res.body.message as string;
}

function submitAction(app: Express, message: string, signature: string, contract: string, action = ACTION) {
  return request(app).post("/action").send({ message, signature, chainId: 1, contract, tokenId: TOKEN_ID, action });
}

async function primed(h: Harness) {
  const account = newSigner();
  h.chain.setOwner(h.config.contract, TOKEN_ID, account.address);
  const message = await issueChallenge(h.app, account, h.config.contract);
  const signature = await account.signMessage({ message });
  return { account, message, signature };
}

async function issuePassTo(h: Harness, owner: PrivateKeyAccount): Promise<Record<string, string>> {
  h.chain.setOwner(h.config.contract, TOKEN_ID, owner.address);
  const { message, signature } = await signChallenge(h, owner, TOKEN_ID);
  const res = await withProof(request(h.app).get(`/manifest/${TOKEN_ID}`), message, signature);
  expect(res.status).toBe(200);
  const links: Record<string, string> = {};
  for (const [action, url] of Object.entries(h.passStore.actionLinks(TOKEN_ID))) {
    links[action] = new URL(url).pathname;
  }
  return links;
}

describe("a repeat of an identical request is not a replay (Authorization of pass-reachable actions)", () => {
  it("runs the handler once for identical requests that arrive together", async () => {
    const store = createRepeatStore(30_000);
    let runs = 0;
    const handler = async () => {
      runs += 1;
      await new Promise((resolve) => setTimeout(resolve, 5));
      return { status: 200, body: { ok: true, run: runs } };
    };
    const key = requestKey("action", "same", "same");
    const [a, b, c] = await Promise.all([store.join(key, 0, handler), store.join(key, 0, handler), store.join(key, 0, handler)]);
    expect(runs).toBe(1);
    expect(a).toEqual(b);
    expect(b).toEqual(c);
  });

  it("returns the recorded outcome inside the window and runs afresh after it", async () => {
    const store = createRepeatStore(30_000);
    let runs = 0;
    const handler = async () => ({ status: 200, body: { run: ++runs } });
    const key = requestKey("capability", "cap", "");
    expect((await store.join(key, 0, handler)).body.run).toBe(1);
    expect((await store.join(key, 29_999, handler)).body.run).toBe(1);
    expect((await store.join(key, 30_000, handler)).body.run).toBe(2);
    expect(runs).toBe(2);
  });

  it("keys requests by every part, so one differing field is a different request", () => {
    expect(requestKey("a", "bc")).not.toBe(requestKey("ab", "c"));
    expect(requestKey("x", "y")).not.toBe(requestKey("x", "z"));
    expect(requestKey("x", "y")).toBe(requestKey("x", "y"));
  });

  it("answers an identical signed repeat with the first outcome instead of nonce_invalid", async () => {
    const h = buildHarness();
    const { message, signature } = await primed(h);

    const first = await submitAction(h.app, message, signature, h.config.contract);
    expect(first.status).toBe(200);
    expect(first.body.executed).toBe(true);

    // The device abandoned its POST and sent it again a moment later.
    h.clock.advance(2_000);
    const again = await submitAction(h.app, message, signature, h.config.contract);
    expect(again.status).toBe(200);
    expect(again.body).toEqual(first.body);
  });

  it("executes a signed action once when two identical POSTs arrive together", async () => {
    const h = buildHarness();
    const { message, signature } = await primed(h);

    const [a, b] = await Promise.all([
      submitAction(h.app, message, signature, h.config.contract),
      submitAction(h.app, message, signature, h.config.contract),
    ]);
    expect(a.status).toBe(200);
    expect(b.status).toBe(200);
    expect(a.body).toEqual(b.body);

    // The nonce was consumed exactly once: past the window the same proof is a
    // replay again, and the nonce store refuses it.
    h.clock.advance(h.config.repeatWindowSeconds * 1000);
    const late = await submitAction(h.app, message, signature, h.config.contract);
    expect(late.status).toBe(401);
    expect(late.body.error).toBe("nonce_invalid");
  });

  it("still refuses a spent nonce presented in a request that differs", async () => {
    const h = buildHarness();
    const { message, signature } = await primed(h);

    const first = await submitAction(h.app, message, signature, h.config.contract);
    expect(first.status).toBe(200);

    // Same proof, different declared target: not the same request. The proof
    // does not authorize this action anyway, and its nonce is spent.
    const differing = await submitAction(h.app, message, signature, h.config.contract, "water");
    expect(differing.status).toBe(401);
    expect(differing.body.error).toBe("nonce_invalid");
  });

  it("answers a repeated refusal with the same refusal", async () => {
    const h = buildHarness();
    const { message, signature } = await primed(h);
    // Ownership moves before the action is presented: the fresh read refuses.
    h.chain.setOwner(h.config.contract, TOKEN_ID, newSigner().address);

    const first = await submitAction(h.app, message, signature, h.config.contract);
    expect(first.status).toBe(403);
    expect(first.body.error).toBe("not_owner");

    // Without the repeat store this identical repeat would read as a replay
    // (the nonce was spent by the first); it is the same request and gets the
    // same answer.
    const again = await submitAction(h.app, message, signature, h.config.contract);
    expect(again.status).toBe(403);
    expect(again.body.error).toBe("not_owner");
  });

  it("performs a capability link's action once for two identical POSTs on one tap", async () => {
    const h = buildHarness({ manifestMode: "gated" });
    const owner = newSigner();
    const links = await issuePassTo(h, owner);

    const [a, b] = await Promise.all([request(h.app).post(links.feed!), request(h.app).post(links.feed!)]);
    expect(a.status).toBe(200);
    expect(b.status).toBe(200);
    expect(a.body).toEqual(b.body);

    // A sequential repeat inside the window is the same request too.
    h.clock.advance(3_000);
    const again = await request(h.app).post(links.feed!);
    expect(again.status).toBe(200);
    expect(again.body).toEqual(a.body);
  });

  it("treats a capability POST with a different body as a different request", async () => {
    const h = buildHarness({ manifestMode: "gated" });
    const owner = newSigner();
    const links = await issuePassTo(h, owner);

    const bare = await request(h.app).post(links.feed!);
    expect(bare.status).toBe(200);

    // Naming another action is a different request and meets the binding check
    // on its own rather than inheriting the first outcome.
    const other = await request(h.app).post(links.feed!).send({ action: "water" });
    expect(other.status).toBe(400);
    expect(other.body.error).toBe("binding_mismatch");
  });
});
