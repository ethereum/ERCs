import { randomBytes } from "node:crypto";

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

export interface PassStore {
  getManifest(tokenId: string): PassManifest;
  resolveCapability(token: string): CapabilityBinding | null;
  rotateOnTransfer(tokenId: string): PassManifest;
}

interface TokenPasses {
  apple: string;
  google: string;
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
  // tokenId -> its current capability tokens.
  const passesByToken = new Map<string, TokenPasses>();
  // capability token -> what it resolves to. Rotation deletes the old entries,
  // which is what makes a previous owner's URL stop resolving.
  const bindings = new Map<string, CapabilityBinding>();

  function mint(tokenId: string): TokenPasses {
    const apple = newCapabilityToken();
    const google = newCapabilityToken();
    bindings.set(apple, { tokenId, format: "apple" });
    bindings.set(google, { tokenId, format: "google" });
    const passes: TokenPasses = { apple, google, updatedAt: Math.floor(now() / 1000) };
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

  return {
    getManifest(tokenId) {
      const id = normalizeTokenId(tokenId);
      const passes = passesByToken.get(id) ?? mint(id);
      return toManifest(passes);
    },

    resolveCapability(token) {
      return bindings.get(token) ?? null;
    },

    rotateOnTransfer(tokenId) {
      const id = normalizeTokenId(tokenId);
      const previous = passesByToken.get(id);
      if (previous) {
        // Invalidate the old capability tokens so a pass held by the previous
        // owner stops resolving. The standard requires this in the gated
        // configuration and RECOMMENDS it wherever a pass exposes action links.
        bindings.delete(previous.apple);
        bindings.delete(previous.google);
      }
      return toManifest(mint(id));
    },
  };
}
