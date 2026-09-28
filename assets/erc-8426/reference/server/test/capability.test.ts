import { describe, it, expect } from "vitest";
import request from "supertest";
import type { PrivateKeyAccount } from "viem/accounts";

import { buildHarness, newSigner, signChallenge, withProof, type Harness } from "./helpers.js";

const TOKEN_ID = "412";

/// Make `owner` the token's owner on the fake chain and take it through the
///  gated acquisition round trip, which is what issues the pass (and so the
///  action links) to that account. Returns the links a pass generator would
///  embed, keyed by action, as paths on the app.
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

/// Follow a link the way an installed pass does: a POST carrying no signature
///  and, unless a test says otherwise, no body.
function follow(h: Harness, path: string, body?: Record<string, unknown>) {
  const req = request(h.app).post(path);
  return body ? req.send(body) : req;
}

describe("capability action links (The capability configuration)", () => {
  it("performs the bound action for the issued owner with no signature", async () => {
    const h = buildHarness({ manifestMode: "gated" });
    const owner = newSigner();
    const links = await issuePassTo(h, owner);
    expect(Object.keys(links).sort()).toEqual([...h.config.capabilityActions].sort());

    const res = await follow(h, links.feed!);
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.executed).toBe(true);
    expect(res.body.action).toBe("feed");
    expect(res.body.tokenId).toBe(TOKEN_ID);
    expect(res.body.account.toLowerCase()).toBe(owner.address.toLowerCase());

    // Naming the action the link is bound to is fine; the link still decides.
    const named = await follow(h, links.feed!, { action: "feed" });
    expect(named.status).toBe(200);
    expect(named.body.executed).toBe(true);
  });

  it("refuses a link bound to one action when the request names another", async () => {
    const h = buildHarness({ manifestMode: "gated" });
    const links = await issuePassTo(h, newSigner());

    // Condition (3): "the URL is bound to the specific token and action it
    // reaches". The feed link cannot be bent into a water action.
    const res = await follow(h, links.feed!, { action: "water" });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("binding_mismatch");
    expect(res.body.executed).toBeUndefined();
  });

  it("refuses a link that rotated on transfer", async () => {
    const h = buildHarness({ manifestMode: "gated" });
    const owner = newSigner();
    const links = await issuePassTo(h, owner);

    // Condition (4): "the URL rotates on transfer". Here the implementation
    // observes the transfer (a transfer watcher in production) before any
    // claim; the old link is gone and a fresh one is issued.
    h.passStore.rotateOnTransfer(TOKEN_ID);
    const dead = await follow(h, links.feed!);
    expect(dead.status).toBe(404);
    expect(dead.body.error).toBe("unknown_capability");

    const fresh = new URL(h.passStore.actionLinks(TOKEN_ID).feed!).pathname;
    expect(fresh).not.toBe(links.feed);
    expect((await follow(h, fresh)).status).toBe(200);
  });

  it("refuses a link that rotated on the owner's request, made through the signed route", async () => {
    const h = buildHarness({ manifestMode: "gated" });
    const owner = newSigner();
    const stranger = newSigner();
    const links = await issuePassTo(h, owner);
    const rotatePath = `/manifest/${TOKEN_ID}/rotate`;

    // No proof: the 401 points at the challenge endpoint for the rotate action.
    const unsigned = await request(h.app).post(rotatePath);
    expect(unsigned.status).toBe(401);
    expect(unsigned.body.error).toBe("proof_required");
    expect(unsigned.body.challenge).toBe(`${h.config.baseUrl}/manifest/${TOKEN_ID}/challenge?action=rotate`);

    // An acquire proof cannot rotate: "an acquire proof MUST NOT authorize any
    // other action".
    const acquire = await signChallenge(h, owner, TOKEN_ID);
    const wrongAction = await withProof(request(h.app).post(rotatePath), acquire.message, acquire.signature);
    expect(wrongAction.status).toBe(400);
    expect(wrongAction.body.error).toBe("binding_mismatch");

    // A rotate proof from an account that is not the owner is refused by the
    // fresh read, so only the current owner can retire the links.
    const notOwner = await signChallenge(h, stranger, TOKEN_ID, "rotate");
    const refused = await withProof(request(h.app).post(rotatePath), notOwner.message, notOwner.signature);
    expect(refused.status).toBe(403);
    expect(refused.body.error).toBe("not_owner");
    expect((await follow(h, links.feed!)).status).toBe(200);

    // The owner's rotate proof retires every link and download URL.
    const before = await request(h.app).get(`/manifest/${TOKEN_ID}`);
    const rotate = await signChallenge(h, owner, TOKEN_ID, "rotate");
    const rotated = await withProof(request(h.app).post(rotatePath), rotate.message, rotate.signature);
    expect(rotated.status).toBe(200);
    expect(rotated.body.rotated).toBe(true);
    expect(rotated.body.formats.apple).toContain("/passes/apple/");
    expect(rotated.body.formats.apple).not.toBe(before.body.formats?.apple);

    const dead = await follow(h, links.feed!);
    expect(dead.status).toBe(404);
    expect(dead.body.error).toBe("unknown_capability");

    // The fresh links are issued to the owner who rotated.
    const fresh = new URL(h.passStore.actionLinks(TOKEN_ID).feed!).pathname;
    expect((await follow(h, fresh)).status).toBe(200);
  });

  it("refuses the rotate action on the signed action route", async () => {
    const h = buildHarness({ manifestMode: "gated" });
    const owner = newSigner();
    h.chain.setOwner(h.config.contract, TOKEN_ID, owner.address);

    // Like acquire, rotate is reserved for its own route and never reaches
    // executeAction.
    const { message, signature } = await signChallenge(h, owner, TOKEN_ID, "rotate");
    const res = await request(h.app).post("/action").send({
      message,
      signature,
      chainId: h.config.chainId,
      contract: h.config.contract,
      tokenId: TOKEN_ID,
      action: "rotate",
    });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("invalid_request");
  });

  it("refuses a sold token behind a still-live link (the fresh read)", async () => {
    const h = buildHarness({ manifestMode: "gated" });
    const seller = newSigner();
    const buyer = newSigner();
    const links = await issuePassTo(h, seller);

    // Sold, and neither a watcher nor the buyer's first claim has rotated yet:
    // the seller's link is still cryptographically valid. Condition (5),
    // "check (2), the fresh entitlement read, remains in force
    // unconditionally", is what refuses it.
    h.chain.setOwner(h.config.contract, TOKEN_ID, buyer.address);
    const res = await follow(h, links.feed!);
    expect(res.status).toBe(403);
    expect(res.body.error).toBe("not_owner");
    expect(res.body.executed).toBeUndefined();
  });

  it("lets a forwarded link act under an unchanged owner (the disclosed residual)", async () => {
    const h = buildHarness({ manifestMode: "gated" });
    const owner = newSigner();
    const links = await issuePassTo(h, owner);

    // A second client that never signed anything follows the same link. This
    // passes on purpose: "Any party holding the capability URL can trigger
    // the bound action while ownership is unchanged." The configuration
    // accepts this residual, which is why it is sound only for actions whose
    // worst-case impact under forwarding the implementation can tolerate, and
    // why rotation on owner request exists.
    const holder = await follow(h, links.feed!);
    expect(holder.status).toBe(200);
    const forwarded = await follow(h, links.feed!);
    expect(forwarded.status).toBe(200);
    expect(forwarded.body.executed).toBe(true);
  });

  it("describes a link on GET without performing it", async () => {
    const h = buildHarness({ manifestMode: "gated" });
    const links = await issuePassTo(h, newSigner());

    // Crawlers and previewers prefetch links embedded in a pass, so GET MUST
    // be side-effect free. The body says what POST would do and that nothing
    // ran.
    const res = await request(h.app).get(links.water!);
    expect(res.status).toBe(200);
    expect(res.headers["cache-control"]).toBe("no-store");
    expect(res.body).toEqual({ tokenId: TOKEN_ID, action: "water", method: "POST", executed: false });

    // A GET on an unknown or rotated link is a plain 404 as well.
    expect((await request(h.app).get("/links/not-a-capability")).status).toBe(404);
  });

  it("has no action links in the public configuration", async () => {
    const h = buildHarness({ manifestMode: "public" });
    h.chain.setOwner(h.config.contract, TOKEN_ID, newSigner().address);

    // Condition (1): "the deployment operates the gated configuration". The
    // public manifest is one chain read from anyone, so nothing derived from
    // it can carry the possession role; whatever the store minted, the route
    // does not exist here.
    expect((await request(h.app).get(`/manifest/${TOKEN_ID}`)).status).toBe(200);
    const link = new URL(h.passStore.actionLinks(TOKEN_ID).feed!).pathname;
    const get = await request(h.app).get(link);
    expect(get.status).toBe(404);
    expect(get.body.error).toBe("unknown_capability");
    const post = await follow(h, link);
    expect(post.status).toBe(404);
    expect(post.body.error).toBe("unknown_capability");
  });

  it("answers a failed ownership read as retryable, never as a verdict", async () => {
    const h = buildHarness({ manifestMode: "gated" });
    const links = await issuePassTo(h, newSigner());

    // The read could not be taken. No cached owner stands in: the link is
    // refused as retryable, with the 403 kept for an actual refusal.
    h.chain.failReads(true);
    const res = await follow(h, links.feed!);
    expect(res.status).toBe(503);
    expect(res.body.error).toBe("read_failed");
    expect(res.headers["retry-after"]).toBe("5");
    expect(res.body.executed).toBeUndefined();
  });
});
