import express, { type Express, type Request, type Response, type NextFunction } from "express";
import { getAddress, isAddressEqual, isHex, type Address } from "viem";

import type { ServerConfig } from "./config.js";
import type { NonceStore } from "./nonceStore.js";
import type { SignatureVerifier } from "./verifiers.js";
import type { ChainReader } from "./chainReader.js";
import type { PassStore, PassFormat } from "./passStore.js";
import { buildChallengeMessage, generateSiweNonce } from "./siwe.js";
import { normalizeTokenId } from "./caip.js";
import { authorize, statusFor, type AuthorizeTarget } from "./authorize.js";
import { authorizeCapabilityAction, capabilityStatusFor, resolveActionLink } from "./capability.js";
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

/// Send a refusal. A 503 means the fresh read could not be taken: the client
///  may retry, and the server never answers from a cached owner instead, so
///  every such refusal carries Retry-After.
function refuse(res: Response, status: number, body: Record<string, unknown>): void {
  if (status === 503) {
    res.set("Retry-After", "5");
  }
  res.status(status).json(body);
}

/// Build the reference server. Every collaborator is injected so a test can
///  supply an EOA-only verifier and a fake chain reader, and a deployment can
///  supply viem-backed ones, without touching the routes.
export function createApp(deps: AppDeps): Express {
  const { config, passStore } = deps;
  const now = deps.now ?? Date.now;
  const app = express();
  app.use(express.json());

  // Issue a challenge for one (account, token, action) with a fresh single-use
  // nonce and a short expiry. Shared by POST /challenge and the gated
  // manifest's challenge endpoint.
  const issueChallenge = (input: {
    account: Address;
    contract: Address;
    chainId: number;
    tokenId: string;
    action: string;
  }) => {
    const nonce = generateSiweNonce();
    const issuedAt = new Date(now());
    const expirationTime = new Date(now() + config.challengeTtlSeconds * 1000);
    deps.nonces.issue(nonce, now() + config.nonceTtlSeconds * 1000);
    const message = buildChallengeMessage({
      domain: config.domain,
      uri: config.uri,
      ...input,
      nonce,
      issuedAt,
      expirationTime,
    });
    return { message, nonce, expiresAt: expirationTime.toISOString() };
  };

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

      res.status(200).json(issueChallenge({ account, contract, chainId, tokenId, action }));
    }),
  );

  // POST /action: redeem a signed challenge to execute an action. The target
  // (what the caller intends to run) is declared here and checked against what
  // the signed message authorizes.
  // Note that the generic challenge endpoint above issues a challenge for any
  // chain, contract, token, and action it is asked for. The floor is enforced
  // where a proof is redeemed, never where a challenge is issued: /action and
  // the gated manifest path check the chain id and contract against this
  // server's configuration, so a challenge for a token this server does not
  // serve is refused when presented, whoever issued it.
  app.post(
    "/action",
    wrap(async (req, res) => {
      const message = req.body?.message;
      const signature = req.body?.signature;
      // The signature must at least be a hex string before it reaches a
      // verifier; its length is the verifier's call (see SignatureVerifier).
      if (typeof message !== "string" || typeof signature !== "string" || !isHex(signature)) {
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

      // The floor's chain id and contract are checked against the verifier's
      // own configuration, never against the request: a caller who could name
      // the chain and contract would have the message verified against values
      // it chose, while the ownership read only ever answers for the token
      // this server serves. The acquire action is reserved for gated manifest
      // resolution ("an acquire proof MUST NOT authorize any other action"),
      // and the rotate action for the rotation route, so both are refused
      // here before they could reach executeAction.
      if (
        target.chainId !== config.chainId ||
        getAddress(target.contract) !== getAddress(config.contract) ||
        target.action === config.acquireAction ||
        target.action === config.rotateAction
      ) {
        res.status(400).json({ error: "invalid_request" });
        return;
      }

      const result = await authorize({ message, signature, target }, deps);
      if (!result.ok) {
        refuse(res, statusFor(result.error), { error: result.error });
        return;
      }

      res.status(200).json({ ok: true, ...executeAction(target, result.account) });
    }),
  );

  // GET /manifest/:tokenId/challenge?address=<account>: the challenge endpoint
  // a gated manifest's 401 response points at (Gated acquisition). It issues
  // the acquire challenge for this token, bound to the server's chain and
  // contract, for the claimed account. With `action=rotate` it issues the
  // rotation challenge instead (the rotation route's 401 points here with
  // that query); no other action is issued from this endpoint.
  app.get(
    "/manifest/:tokenId/challenge",
    wrap(async (req, res) => {
      let tokenId: string;
      let account: Address;
      const action = req.query.action === undefined ? config.acquireAction : String(req.query.action);
      try {
        tokenId = normalizeTokenId(String(req.params.tokenId));
        account = getAddress(String(req.query.address ?? ""));
        if (action !== config.acquireAction && action !== config.rotateAction) {
          throw new Error("bad challenge action");
        }
      } catch {
        res.status(400).json({ error: "invalid_request" });
        return;
      }
      res.setHeader("Cache-Control", "no-store");
      res.status(200).json(
        issueChallenge({
          account,
          contract: config.contract,
          chainId: config.chainId,
          tokenId,
          action,
        }),
      );
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
        const gate = await checkGatedProof(req, tokenId, deps, config.acquireAction);
        if (!gate.ok) {
          refuse(res, gate.status, gate.challenge ? { error: gate.error, challenge: gate.challenge } : { error: gate.error });
          return;
        }
        // Gated acquisition: a proven account that is not the account passes
        // were last issued to is making its first claim, so the acquisition
        // URLs rotate before the manifest is returned. The very first claim
        // for a token only records the account; there is no earlier holder
        // whose URLs need retiring, so nothing rotates. The account is
        // recorded before rotating so the fresh links are issued to it.
        const last = passStore.lastIssuedTo(tokenId);
        passStore.recordIssuance(tokenId, gate.account);
        if (last !== undefined && !isAddressEqual(last, gate.account)) {
          passStore.rotateOnTransfer(tokenId);
        }
      }

      // Clients MUST NOT durably cache acquisition URLs (Client requirements).
      res.setHeader("Cache-Control", "no-store");
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

  // POST /manifest/:tokenId/rotate: rotate every capability URL for the token
  // on the owner's explicit request ("Implementations SHOULD rotate
  // acquisition URLs on explicit owner request"). This is the holder's remedy
  // for the residual the capability configuration accepts: a link forwarded
  // while ownership is unchanged keeps working until the owner rotates it.
  // The request is guarded like the gated manifest, by a signed proof carried
  // in the same headers, but for the rotate action: an acquire proof cannot
  // rotate, and a rotate proof cannot acquire or act. The proof's fresh read
  // means only the current owner can rotate.
  app.post(
    "/manifest/:tokenId/rotate",
    wrap(async (req, res) => {
      let tokenId: string;
      try {
        tokenId = normalizeTokenId(String(req.params.tokenId));
      } catch {
        res.status(400).json({ error: "invalid_request" });
        return;
      }

      const gate = await checkGatedProof(req, tokenId, deps, config.rotateAction);
      if (!gate.ok) {
        refuse(res, gate.status, gate.challenge ? { error: gate.error, challenge: gate.challenge } : { error: gate.error });
        return;
      }

      // The proven owner is who the fresh links are issued to.
      passStore.recordIssuance(tokenId, gate.account);
      const manifest = passStore.rotateOnOwnerRequest(tokenId);
      res.setHeader("Cache-Control", "no-store");
      res.status(200).json({ ok: true, rotated: true, ...manifest });
    }),
  );

  // GET /links/:capability: describe an action link without performing it.
  // A link embedded in an installed pass is followed by devices, previewers,
  // and crawlers that prefetch it, so the GET MUST be side-effect free (see
  // the deployment notes); only the POST below performs the action. The
  // description carries nothing a bearer could not already learn from the
  // pass, and in the public configuration no action link exists at all.
  app.get(
    "/links/:capability",
    wrap(async (req, res) => {
      const binding = resolveActionLink(String(req.params.capability), deps);
      if (!binding) {
        res.status(404).json({ error: "unknown_capability" });
        return;
      }
      res.setHeader("Cache-Control", "no-store");
      res.status(200).json({ tokenId: binding.tokenId, action: binding.action, method: "POST", executed: false });
    }),
  );

  // POST /links/:capability: perform the action a capability link is bound
  // to. This is the capability configuration: the unguessable URL stands in
  // for the signed proof of check (1), and the fresh entitlement read of check
  // (2) is taken exactly as on /action. The body MAY name the action; a body
  // that names a different one is refused, since the link decides.
  app.post(
    "/links/:capability",
    wrap(async (req, res) => {
      const requested = req.body?.action;
      if (requested !== undefined && typeof requested !== "string") {
        res.status(400).json({ error: "invalid_request" });
        return;
      }

      const result = await authorizeCapabilityAction(
        { capability: String(req.params.capability), requestedAction: requested },
        deps,
      );
      if (!result.ok) {
        refuse(res, capabilityStatusFor(result.error), { error: result.error });
        return;
      }

      const target: AuthorizeTarget = {
        chainId: config.chainId,
        contract: config.contract,
        tokenId: result.binding.tokenId,
        action: result.binding.action,
      };
      res.status(200).json({ ok: true, ...executeAction(target, result.owner) });
    }),
  );

  return app;
}

interface GateOk {
  ok: true;
  /// The proven account, so the manifest handler can tell a first claim by a
  ///  new owner from a repeat claim by the account passes were last issued to.
  account: Address;
}
interface GateFail {
  ok: false;
  status: number;
  error: string;
  /// Present on every 401: the URI of the challenge endpoint for the token.
  ///  Whether the proof was missing, expired, replayed, or badly signed, the
  ///  client's next step is the same fresh challenge.
  challenge?: string;
}

/// Verify the control proof required to resolve a gated manifest, or to rotate
///  on owner request. The proof reuses the challenge flow with the given action
///  (acquire or rotate) for this token, bound to the server's configured chain
///  and contract.
///
///  A SIWE message contains line breaks, which HTTP headers cannot carry, so
///  the message is passed base64url-encoded in `X-Wallet-Pass-Proof` and the
///  signature in `X-Wallet-Pass-Signature`. This keeps manifest resolution a
///  GET while still carrying a full challenge.
async function checkGatedProof(req: Request, tokenId: string, deps: AppDeps, action: string): Promise<GateOk | GateFail> {
  const query = action === deps.config.acquireAction ? "" : `?action=${action}`;
  const challenge = `${deps.config.baseUrl}/manifest/${tokenId}/challenge${query}`;
  const encoded = req.get("x-wallet-pass-proof");
  const signature = req.get("x-wallet-pass-signature");
  if (!encoded || !signature) {
    // Gated acquisition: point the client at the challenge endpoint for this token.
    return { ok: false, status: 401, error: "proof_required", challenge };
  }
  // As on /action: hex or nothing, with the length left to the verifier.
  if (!isHex(signature)) {
    return { ok: false, status: 400, error: "invalid_request" };
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
    action,
  };
  const result = await authorize({ message, signature, target }, deps);
  if (!result.ok) {
    const status = statusFor(result.error);
    return status === 401
      ? { ok: false, status, error: result.error, challenge }
      : { ok: false, status, error: result.error };
  }
  return { ok: true, account: result.account };
}
