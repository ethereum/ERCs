import { isAddressEqual, type Address, type Hex } from "viem";

import type { ServerConfig } from "./config.js";
import type { NonceStore } from "./nonceStore.js";
import type { SignatureVerifier } from "./verifiers.js";
import type { ChainReader } from "./chainReader.js";
import { assetId, actionUrn, normalizeTokenId } from "./caip.js";
import { parseSiweMessage } from "./siwe.js";

/// One rejection reason per hole the standard's authorization model closes.
///  Each is distinct so a caller (and these tests) can tell exactly which check
///  failed, and so the model stays legible: every reason maps to a sentence in
///  "Authorization of pass-reachable actions".
export type AuthError =
  | "invalid_message" // not a parseable SIWE challenge
  | "domain_mismatch" // verifier identity is not this server
  | "nonce_invalid" // unknown, already spent, or evicted nonce
  | "challenge_expired" // Expiration Time missing or in the past
  | "binding_mismatch" // resources do not bind this exact token and action
  | "signature_invalid" // signature not valid for the claimed account
  | "not_owner"; // claimed account is not the current owner (fresh read)

/// What the caller intends to execute, declared independently of the message.
///  The whole point of the binding check is that this target must match what
///  the signed message authorizes: a proof obtained for one action or token
///  cannot be redeemed for another.
export interface AuthorizeTarget {
  chainId: number;
  contract: Address;
  tokenId: string;
  action: string;
}

export interface AuthorizeInput {
  message: string;
  signature: Hex;
  target: AuthorizeTarget;
}

export interface AuthorizeDeps {
  config: ServerConfig;
  nonces: NonceStore;
  verifier: SignatureVerifier;
  chain: ChainReader;
  /// Injectable clock (epoch milliseconds) so tests can advance time.
  now?: () => number;
}

export type AuthorizeResult =
  | { ok: true; account: Address }
  | { ok: false; error: AuthError };

/// Map each rejection reason to an HTTP status: malformed or mis-scoped input
///  is a 400, a failed possession or freshness check is 401, and a valid proof
///  from someone who is not the owner is a 403.
export function statusFor(error: AuthError): number {
  switch (error) {
    case "invalid_message":
    case "domain_mismatch":
    case "binding_mismatch":
      return 400;
    case "nonce_invalid":
    case "challenge_expired":
    case "signature_invalid":
      return 401;
    case "not_owner":
      return 403;
  }
}

/// Run the standard's two-check authorization, in the order the specification
///  lists. The nonce is consumed before the later checks run, so a single
///  presentation spends it whether or not the rest succeeds: a failed attempt
///  cannot be retried with the same nonce.
export async function authorize(input: AuthorizeInput, deps: AuthorizeDeps): Promise<AuthorizeResult> {
  const nowMs = (deps.now ?? Date.now)();
  const { config } = deps;
  const target: AuthorizeTarget = { ...input.target, tokenId: normalizeTokenId(input.target.tokenId) };

  // 1. The message parses as a SIWE challenge carrying the fields the standard
  //    mandates. Expiration is checked in step 4, where the spec orders it.
  const parsed = parseSiweMessage(input.message);
  const resources = parsed.resources ?? [];
  if (!parsed.domain || !parsed.address || !parsed.nonce || parsed.chainId === undefined || resources.length === 0) {
    return { ok: false, error: "invalid_message" };
  }

  // 2. The verifier identity (the SIWE domain) is this server. This keeps a
  //    challenge signed for one issuer from being redeemed at another.
  if (parsed.domain !== config.domain) {
    return { ok: false, error: "domain_mismatch" };
  }

  // 3. The nonce exists, is unexpired, and is consumed atomically. A replay
  //    finds the nonce already spent.
  if (!deps.nonces.consume(parsed.nonce, nowMs)) {
    return { ok: false, error: "nonce_invalid" };
  }

  // 4. The message itself has not expired.
  const expirationMs = parsed.expirationTime ? parsed.expirationTime.getTime() : undefined;
  if (expirationMs === undefined || expirationMs <= nowMs) {
    return { ok: false, error: "challenge_expired" };
  }

  // 5. The resources bind exactly the chain, contract, token, and action being
  //    executed. The CAIP-19 asset id ties the first three together; the action
  //    URN names the fourth. The SIWE Chain ID must agree as well.
  const expectedAsset = assetId(target.chainId, target.contract, target.tokenId);
  const expectedAction = actionUrn(target.action);
  const bound =
    parsed.chainId === target.chainId &&
    resources.includes(expectedAsset) &&
    resources.includes(expectedAction);
  if (!bound) {
    return { ok: false, error: "binding_mismatch" };
  }

  // 6. The signature is valid for the claimed account, through a verifier that
  //    supports both EOA and ERC-1271 contract-account signatures. A verifier
  //    that throws (a signature of the wrong length, an unrecoverable point, or
  //    a failed contract-account call) has not validated the signature, so the
  //    throw is refused as a bad signature rather than surfacing as a crash.
  let signatureValid: boolean;
  try {
    signatureValid = await deps.verifier.verify({
      address: parsed.address,
      message: input.message,
      signature: input.signature,
    });
  } catch {
    signatureValid = false;
  }
  if (!signatureValid) {
    return { ok: false, error: "signature_invalid" };
  }

  // 7. A fresh read of ownership at this moment. This is what closes the
  //    transfer window: a token sold after the challenge was issued stops
  //    acting immediately, however many valid-looking passes remain installed.
  //    A read that throws (nonexistent or burned token, or an RPC failure)
  //    yields no owner equal to the claimant, so the action is refused.
  let owner: Address;
  try {
    owner = await deps.chain.ownerOf(target.contract, target.tokenId);
  } catch {
    return { ok: false, error: "not_owner" };
  }
  if (!isAddressEqual(owner, parsed.address)) {
    return { ok: false, error: "not_owner" };
  }

  return { ok: true, account: parsed.address };
}
