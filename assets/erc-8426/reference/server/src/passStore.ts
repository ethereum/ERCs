import { randomBytes } from "node:crypto";
import { getAddress, type Address } from "viem";

import type { ServerConfig } from "./config.js";
import { normalizeTokenId } from "./caip.js";

/// The pass manifest, exactly the shape the standard defines under "Pass
///  manifest": a REQUIRED `formats` map with at least one platform entry, and
///  an OPTIONAL `updatedAt` Unix timestamp (integer seconds) of the last
///  content change.
export interface PassManifest {
  formats: {
    apple: string;
    google: string;
  };
  updatedAt: number;
}

/// The platform an acquisition URL delivers a pass for.
export type PassFormat = "apple" | "google";

/// What a capability token currently resolves to, or null once it has rotated
///  away and been invalidated.
export interface CapabilityBinding {
  tokenId: string;
  format: PassFormat;
}

/// What an action capability (a link embedded in an installed pass) resolves
///  to. The capability configuration requires the URL to be "bound to the
///  specific token and action it reaches"; `issuedTo` is the account passes
///  were last issued to when the link was minted, which the fresh entitlement
///  read is compared against when the link is followed.
export interface ActionBinding {
  tokenId: string;
  action: string;
  issuedTo: Address | undefined;
}

export interface PassStore {
  getManifest(tokenId: string): PassManifest;
  resolveCapability(token: string): CapabilityBinding | null;
  /// The action links a pass generator embeds in this token's pass, keyed by
  ///  action: one capability URL per configured action. Minted alongside the
  ///  download capabilities and rotated with them.
  actionLinks(tokenId: string): Record<string, string>;
  resolveActionCapability(token: string): ActionBinding | null;
  /// Rotate every capability for the token (download and action links alike)
  ///  because a transfer was observed, whether by a transfer watcher or at the
  ///  new owner's first claim. Acquisition URLs "MUST rotate upon the
  ///  implementation observing a transfer or upon the new owner's first claim".
  rotateOnTransfer(tokenId: string): PassManifest;
  /// The same rotation on the owner's explicit request ("Implementations
  ///  SHOULD rotate acquisition URLs on explicit owner request"). Different
  ///  trigger, same effect: a link that leaked while ownership was unchanged,
  ///  the case rotation on transfer cannot reach, stops resolving.
  rotateOnOwnerRequest(tokenId: string): PassManifest;
  /// The account the implementation last issued passes to for this token, or
  ///  undefined before the first issuance. Gated acquisition defines a claim
  ///  by a proven account other than this one as that account's first claim,
  ///  which is what triggers rotation there.
  lastIssuedTo(tokenId: string): Address | undefined;
  recordIssuance(tokenId: string, account: Address): void;
}

interface TokenPasses {
  apple: string;
  google: string;
  /// action -> its current capability token.
  actions: Record<string, string>;
  updatedAt: number;
}

/// High-entropy, URL-safe capability token. Unguessable and not derivable from
///  the token id or any public data, per the standard's guidance on capability
///  URLs.
function newCapabilityToken(): string {
  return randomBytes(32).toString("base64url");
}

/// In-memory pass store.
///
///  This is where the standard's platform plumbing is deliberately stubbed. The
///  acquisition URLs are opaque capability handles mapped back to a token on
///  this server; they do NOT point at real signed artifacts. A production store
///  swaps `getManifest` for one that mints a signed Apple `.pkpass` (served as
///  application/vnd.apple.pkpass) and a Save to Google Wallet JWT on demand, and
///  backs the capability map with durable storage. The standard scopes that
///  generation, signing, and delivery out; only discovery and rotation live
///  here.
export function createPassStore(config: ServerConfig, now: () => number = Date.now): PassStore {
  // The acquire and rotate actions always take a signed proof; a capability
  // link for either would let a bearer URL stand in where the standard
  // requires a signature.
  for (const reserved of [config.acquireAction, config.rotateAction]) {
    if (config.capabilityActions.includes(reserved)) {
      throw new Error(`capabilityActions must not include the reserved action "${reserved}"`);
    }
  }

  // tokenId -> its current capability tokens.
  const passesByToken = new Map<string, TokenPasses>();
  // capability token -> what it resolves to. Rotation deletes the old entries,
  // which is what makes a previous owner's URL stop resolving.
  const bindings = new Map<string, CapabilityBinding>();
  // action capability token -> what it resolves to. Rotated with the above.
  const actionBindings = new Map<string, ActionBinding>();
  // tokenId -> the account passes were last issued to (gated configuration).
  const issuedTo = new Map<string, Address>();

  // Mint fresh capability tokens. `updatedAt` is the manifest's content
  // freshness timestamp and says nothing about acquisition URL validity, so a
  // rotation passes the previous value through unchanged; only a first mint
  // stamps the current time. Action links are bound to the account passes are
  // issued to at this moment, so a link outlives its holder's ownership only
  // until the fresh read notices.
  function mint(tokenId: string, updatedAt: number = Math.floor(now() / 1000)): TokenPasses {
    const apple = newCapabilityToken();
    const google = newCapabilityToken();
    bindings.set(apple, { tokenId, format: "apple" });
    bindings.set(google, { tokenId, format: "google" });
    const actions: Record<string, string> = {};
    for (const action of config.capabilityActions) {
      const token = newCapabilityToken();
      actionBindings.set(token, { tokenId, action, issuedTo: issuedTo.get(tokenId) });
      actions[action] = token;
    }
    const passes: TokenPasses = { apple, google, actions, updatedAt };
    passesByToken.set(tokenId, passes);
    return passes;
  }

  function toManifest(passes: TokenPasses): PassManifest {
    return {
      formats: {
        apple: `${config.baseUrl}/passes/apple/${passes.apple}`,
        google: `${config.baseUrl}/passes/google/${passes.google}`,
      },
      updatedAt: passes.updatedAt,
    };
  }

  // Invalidate every capability the token currently has, download and action
  // links alike, and mint replacements. A pass held by the previous owner, or
  // a link that leaked, stops resolving. The standard requires this in the
  // gated configuration and RECOMMENDS it wherever a pass exposes action links.
  function rotate(tokenId: string): PassManifest {
    const id = normalizeTokenId(tokenId);
    const previous = passesByToken.get(id);
    if (previous) {
      bindings.delete(previous.apple);
      bindings.delete(previous.google);
      for (const token of Object.values(previous.actions)) {
        actionBindings.delete(token);
      }
    }
    return toManifest(mint(id, previous?.updatedAt));
  }

  return {
    getManifest(tokenId) {
      const id = normalizeTokenId(tokenId);
      const passes = passesByToken.get(id) ?? mint(id);
      return toManifest(passes);
    },

    resolveCapability(token) {
      return bindings.get(token) ?? null;
    },

    actionLinks(tokenId) {
      const id = normalizeTokenId(tokenId);
      const passes = passesByToken.get(id) ?? mint(id);
      const links: Record<string, string> = {};
      for (const [action, token] of Object.entries(passes.actions)) {
        links[action] = `${config.baseUrl}/links/${token}`;
      }
      return links;
    },

    resolveActionCapability(token) {
      return actionBindings.get(token) ?? null;
    },

    rotateOnTransfer(tokenId) {
      return rotate(tokenId);
    },

    rotateOnOwnerRequest(tokenId) {
      return rotate(tokenId);
    },

    lastIssuedTo(tokenId) {
      return issuedTo.get(normalizeTokenId(tokenId));
    },

    recordIssuance(tokenId, account) {
      issuedTo.set(normalizeTokenId(tokenId), getAddress(account));
    },
  };
}
