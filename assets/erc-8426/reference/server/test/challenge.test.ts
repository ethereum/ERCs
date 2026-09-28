import { describe, it, expect } from "vitest";
import request from "supertest";
import { parseSiweMessage } from "viem/siwe";

import { buildHarness, newSigner } from "./helpers.js";

describe("POST /challenge", () => {
  it("issues a SIWE message shaped like the spec's worked example", async () => {
    const { app, config } = buildHarness();
    const account = newSigner();

    const res = await request(app).post("/challenge").send({
      account: account.address,
      chainId: 1,
      contract: config.contract,
      tokenId: "412",
      action: "feed",
    });

    expect(res.status).toBe(200);
    const message: string = res.body.message;

    // First line carries the verifier identity, scheme-implicit like the example.
    expect(message.startsWith("issuer.example wants you to sign in with your Ethereum account:")).toBe(true);
    // Statement names the action in plain language, matching the example wording.
    expect(message).toContain("Authorize the feed action for wallet pass token 412 on issuer.example.");

    const parsed = parseSiweMessage(message);
    expect(parsed.domain).toBe("issuer.example");
    expect(parsed.address?.toLowerCase()).toBe(account.address.toLowerCase());
    expect(parsed.uri).toBe("https://issuer.example/wallet-pass/actions");
    expect(parsed.version).toBe("1");
    expect(parsed.chainId).toBe(1);
    expect(parsed.expirationTime).toBeInstanceOf(Date);

    // The token and action live in the Resources list: a CAIP-19 asset id that
    // binds chain, contract, and token id together, and an action URN.
    expect(parsed.resources).toEqual([
      `eip155:1/erc721:${config.contract}/412`,
      "urn:wallet-pass:action:feed",
    ]);

    // The nonce is present and meets the ERC-4361 minimum of 8 characters.
    expect(res.body.nonce.length).toBeGreaterThanOrEqual(8);
    expect(parsed.nonce).toBe(res.body.nonce);
  });

  it("rejects a malformed request", async () => {
    const { app } = buildHarness();
    const res = await request(app).post("/challenge").send({ account: "not-an-address" });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("invalid_request");
  });
});
