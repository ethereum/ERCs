import express, { type Express, type Request, type Response, type NextFunction } from "express";
import { getAddress, type Address, type Hex } from "viem";

import type { ServerConfig } from "./config.js";
import type { NonceStore } from "./nonceStore.js";
import type { SignatureVerifier } from "./verifiers.js";
import type { ChainReader } from "./chainReader.js";
import type { PassStore, PassFormat } from "./passStore.js";
import { buildChallengeMessage, generateSiweNonce } from "./siwe.js";
import { normalizeTokenId } from "./caip.js";
import { authorize, statusFor, type AuthorizeTarget } from "./authorize.js";
import { executeAction } from "./actions.js";

export interface AppDeps {
  config: ServerConfig;
  nonces: NonceStore;
  verifier: SignatureVerifier;
  chain: ChainReader;
  passStore: PassStore;
  /// Injectable clock (epoch milliseconds), shared with `authorize` so the
  ///  whole request sees one consistent notion of "now".
  now?: () => number;
}

/// Wrap an async handler so a rejected promise becomes a 500 rather than an
///  unhandled rejection. Express 4 does not await handlers itself.
function wrap(handler: (req: Request, res: Response) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => handler(req, res).catch(next);
}

/// Build the reference server. Every collaborator is injected so a test can
///  supply an EOA-only verifier and a fake chain reader, and a deployment can
///  supply viem-backed ones, without touching the routes.
export function createApp(deps: AppDeps): Express {
  const { config, passStore } = deps;
  const now = deps.now ?? Date.now;
  const app = express();
  app.use(express.json());

  // POST /challenge: issue a Sign-In with Ethereum challenge that binds a
  // token and an action, with a fresh single-use nonce and a short expiry.
  app.post(
    "/challenge",
    wrap(async (req, res) => {
      let account: Address;
      let contract: Address;
      let chainId: number;
      let tokenId: string;
      let action: string;
      try {
        account = getAddress(req.body?.account);
        contract = getAddress(req.body?.contract);
        chainId = Number(req.body?.chainId);
        tokenId = normalizeTokenId(req.body?.tokenId);
        action = String(req.body?.action ?? "");
        if (!Number.isInteger(chainId) || chainId <= 0 || action.length === 0) {
          throw new Error("bad challenge request");
        }
      } catch {
        res.status(400).json({ error: "invalid_request" });
        return;
      }

      const nonce = generateSiweNonce();
      const issuedAt = new Date(now());
      const expirationTime = new Date(now() + config.challengeTtlSeconds * 1000);
      deps.nonces.issue(nonce, now() + config.nonceTtlSeconds * 1000);

      const message = buildChallengeMessage({
        domain: config.domain,
        uri: config.uri,
        account,
        chainId,
        contract,
        tokenId,
        action,
        nonce,
        issuedAt,
        expirationTime,
      });

      res.status(200).json({ message, nonce, expiresAt: expirationTime.toISOString() });
    }),
  );

  // POST /action: redeem a signed challenge to execute an action. The target
  // (what the caller intends to run) is declared here and checked against what
  // the signed message authorizes.
  app.post(
    "/action",
    wrap(async (req, res) => {
      const message = req.body?.message;
      const signature = req.body?.signature;
      if (typeof message !== "string" || typeof signature !== "string") {
        res.status(400).json({ error: "invalid_request" });
        return;
      }

      let target: AuthorizeTarget;
      try {
        target = {
          chainId: Number(req.body?.chainId),
          contract: getAddress(req.body?.contract),
          tokenId: normalizeTokenId(req.body?.tokenId),
          action: String(req.body?.action ?? ""),
        };
        if (!Number.isInteger(target.chainId) || target.action.length === 0) {
          throw new Error("bad action request");
        }
      } catch {
        res.status(400).json({ error: "invalid_request" });
        return;
      }

      const result = await authorize({ message, signature: signature as Hex, target }, deps);
      if (!result.ok) {
        res.status(statusFor(result.error)).json({ error: result.error });
        return;
      }

      res.status(200).json({ ok: true, ...executeAction(target, result.account) });
    }),
  );

  // GET /manifest/:tokenId: serve the pass manifest. In the public
  // configuration it is served to anyone; in the gated configuration it
  // requires a verified control proof for the acquire action, carried in
  // request headers (see the gated-proof note below).
  app.get(
    "/manifest/:tokenId",
    wrap(async (req, res) => {
      let tokenId: string;
      try {
        tokenId = normalizeTokenId(String(req.params.tokenId));
      } catch {
        res.status(400).json({ error: "invalid_request" });
        return;
      }

      if (config.manifestMode === "gated") {
        const gate = await checkGatedProof(req, tokenId, deps);
        if (!gate.ok) {
          res.status(gate.status).json({ error: gate.error });
          return;
        }
      }

      res.status(200).json(passStore.getManifest(tokenId));
    }),
  );

  // GET /passes/:format/:token: resolve a capability token. This stands in for
  // the endpoint that would stream a signed Apple .pkpass or redirect to a Save
  // to Google Wallet link; here it only proves the capability mapping and its
  // rotation. A token that has rotated away no longer resolves.
  app.get(
    "/passes/:format/:token",
    wrap(async (req, res) => {
      const format = req.params.format as PassFormat;
      const binding = passStore.resolveCapability(String(req.params.token));
      if (!binding || binding.format !== format) {
        res.status(404).json({ error: "unknown_capability" });
        return;
      }
      // Stub: a real server would set Content-Type application/vnd.apple.pkpass
      // and stream the signed bundle, or redirect to the Google save link.
      res.status(200).json({ stub: true, format: binding.format, tokenId: binding.tokenId });
    }),
  );

  return app;
}

interface GateOk {
  ok: true;
}
interface GateFail {
  ok: false;
  status: number;
  error: string;
}

/// Verify the control proof required to resolve a gated manifest. The proof
///  reuses the challenge flow with the acquire action for this token, bound to
///  the server's configured chain and contract.
///
///  A SIWE message contains line breaks, which HTTP headers cannot carry, so
///  the message is passed base64url-encoded in `X-Wallet-Pass-Proof` and the
///  signature in `X-Wallet-Pass-Signature`. This keeps manifest resolution a
///  GET while still carrying a full challenge.
async function checkGatedProof(req: Request, tokenId: string, deps: AppDeps): Promise<GateOk | GateFail> {
  const encoded = req.get("x-wallet-pass-proof");
  const signature = req.get("x-wallet-pass-signature");
  if (!encoded || !signature) {
    return { ok: false, status: 401, error: "proof_required" };
  }

  let message: string;
  try {
    message = Buffer.from(encoded, "base64url").toString("utf8");
  } catch {
    return { ok: false, status: 400, error: "invalid_message" };
  }

  const target: AuthorizeTarget = {
    chainId: deps.config.chainId,
    contract: deps.config.contract,
    tokenId,
    action: deps.config.acquireAction,
  };
  const result = await authorize({ message, signature: signature as Hex, target }, deps);
  if (!result.ok) {
    return { ok: false, status: statusFor(result.error), error: result.error };
  }
  return { ok: true };
}
