import { isAddressEqual, type Address } from "viem";

import type { ServerConfig } from "./config.js";
import type { ChainReader } from "./chainReader.js";
import type { PassStore, ActionBinding } from "./passStore.js";

/// One rejection reason per condition of "The capability configuration" that
///  a followed link can fail, plus the fresh read that could not be taken. As
///  with `AuthError`, each maps to a sentence in the standard.
export type CapabilityError =
  | "unknown_capability" // no live link (never minted, rotated away, or not this configuration)
  | "binding_mismatch" // the request names an action other than the one the link is bound to
  | "not_owner" // the fresh read does not name the account the link was issued to
  | "read_failed"; // the fresh ownership read could not be taken

export interface CapabilityDeps {
  config: ServerConfig;
  chain: ChainReader;
  passStore: PassStore;
}

export type CapabilityResult =
  | { ok: true; binding: ActionBinding; owner: Address }
  | { ok: false; error: CapabilityError };

/// Map each rejection reason to an HTTP status, on the same footing as
///  `statusFor` for the signed path: a link that does not resolve is a 404, a
///  mis-scoped request is a 400, a refused account is a 403 (reserved for the
///  entitlement refusal, as in Gated acquisition), and a read that could not
///  be taken is a 503.
export function capabilityStatusFor(error: CapabilityError): number {
  switch (error) {
    case "unknown_capability":
      return 404;
    case "binding_mismatch":
      return 400;
    case "not_owner":
      return 403;
    case "read_failed":
      return 503;
  }
}

/// Resolve an action link without side effects. Condition (1) of the
///  capability configuration: "the deployment operates the gated
///  configuration". In the public configuration the manifest is public data,
///  so a link derived from it could never carry the possession role; no action
///  link exists there and every capability is unknown. Conditions (2) and (4)
///  fall out of resolution itself: a token that was never minted here, or that
///  rotated away, has no binding.
export function resolveActionLink(capability: string, deps: CapabilityDeps): ActionBinding | null {
  if (deps.config.manifestMode !== "gated") {
    return null;
  }
  return deps.passStore.resolveActionCapability(capability);
}

/// Authorize an action reached through a capability link. This is the weaker
///  configuration the standard permits where the product does not prompt for
///  a per-action signature: the capability URL "MAY stand in for check (1)",
///  and check (2), the fresh entitlement read, "remains in force
///  unconditionally".
///  The steps mirror `authorize` for the signed path, condition by condition.
export async function authorizeCapabilityAction(
  input: { capability: string; requestedAction?: string },
  deps: CapabilityDeps,
): Promise<CapabilityResult> {
  // 1. The link resolves: gated configuration, minted here, not rotated away.
  const binding = resolveActionLink(input.capability, deps);
  if (!binding) {
    return { ok: false, error: "unknown_capability" };
  }

  // 2. Condition (3): "the URL is bound to the specific token and action it
  //    reaches". The binding decides both; a request that names some other
  //    action is refused rather than honored, exactly as a signed proof for
  //    action A cannot be redeemed for action B.
  if (input.requestedAction !== undefined && input.requestedAction !== binding.action) {
    return { ok: false, error: "binding_mismatch" };
  }

  // 3. Condition (5): the fresh on-chain read, at the time of the request.
  //    "Check (2) is never substitutable." The read fails closed either way,
  //    and the two failures are told apart as on the signed path: a read that
  //    could not be taken is retryable, never a verdict on ownership.
  let owner: Address | null;
  try {
    owner = await deps.chain.ownerOf(deps.config.contract, binding.tokenId);
  } catch {
    return { ok: false, error: "read_failed" };
  }

  // 4. The current owner must be the account the link was issued to. This is
  //    what closes the transfer window for a bearer link: a token sold behind
  //    a still-live link stops acting immediately, before rotation catches up.
  //    A link issued to no one (minted before any proven claim) authorizes no
  //    one. What this does NOT close is forwarding under an unchanged owner;
  //    that is the residual the configuration accepts, and rotation on owner
  //    request is the holder's remedy.
  if (owner === null || binding.issuedTo === undefined || !isAddressEqual(owner, binding.issuedTo)) {
    return { ok: false, error: "not_owner" };
  }

  return { ok: true, binding, owner };
}
