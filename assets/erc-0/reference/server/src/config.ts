import { getAddress, type Address } from "viem";

/// The two configurations the standard defines under "Acquisition URLs".
///
///  - "public": the manifest is served to anyone. Its acquisition URLs are
///    public data (one chain read from anyone who can enumerate token ids), so
///    they are hygiene only and never a proof of possession.
///  - "gated": manifest resolution is gated behind a proof of control of the
///    owning account, reusing the challenge flow with the acquire action. Only
///    in this configuration may an acquisition URL stand in as a possession
///    proof, and here the URLs MUST rotate on transfer.
export type ManifestMode = "public" | "gated";

export interface ServerConfig {
  /// The verifier identity. In a Sign-In with Ethereum challenge this is the
  ///  `domain` on the first line, and the standard's authorization section
  ///  requires the verifier to check it. Kept scheme-implicit (HTTPS) to match
  ///  the spec's example challenge.
  domain: string;

  /// The RFC 3986 URI that is the subject of the signing (the SIWE `URI`
  ///  field). This is where signed action messages are submitted.
  uri: string;

  /// Base origin used to compose stubbed capability acquisition URLs.
  baseUrl: string;

  /// The chain and contract this server issues passes for. The challenge binds
  ///  all three of (chainId, contract, tokenId) as a CAIP-19 asset id, and the
  ///  gated manifest flow reads them from here rather than from the request.
  chainId: number;
  contract: Address;

  /// Lifetime of an issued challenge. The SIWE `Expiration Time` is
  ///  `Issued At` plus this many seconds; a short window keeps a leaked proof
  ///  from staying useful.
  challengeTtlSeconds: number;

  /// How long a nonce is retained in the store. Deliberately a little longer
  ///  than the challenge lifetime so that a submission arriving after the
  ///  message expired is rejected as "challenge_expired" (precise) rather than
  ///  as an unknown nonce (generic). The single-use consumption, not eviction,
  ///  is what stops replay inside the window.
  nonceTtlSeconds: number;

  /// Which of the two spec configurations the manifest endpoint operates in.
  manifestMode: ManifestMode;

  /// The action name used by the gated manifest flow, surfaced in the challenge
  ///  as `urn:wallet-pass:action:acquire`.
  acquireAction: string;

  /// The action name a signed rotation request carries, surfaced as
  ///  `urn:wallet-pass:action:rotate`. It is its own action rather than a reuse
  ///  of the acquire proof because "an acquire proof MUST NOT authorize any
  ///  other action" (Gated acquisition), and rotating every live URL is another
  ///  action.
  rotateAction: string;

  /// The actions a pass may expose as capability links in the gated
  ///  configuration (The capability configuration). Each installed pass gets
  ///  one unguessable link per action here, bound to its token. The acquire
  ///  and rotate actions are never in this list: they always take a signed
  ///  proof.
  capabilityActions: string[];
}

/// A ready-to-use configuration. The chain id and contract mirror the values in
///  the spec's worked example so an issued challenge lines up with it field for
///  field.
export function defaultConfig(overrides: Partial<ServerConfig> = {}): ServerConfig {
  const base: ServerConfig = {
    domain: "issuer.example",
    uri: "https://issuer.example/wallet-pass/actions",
    baseUrl: "https://issuer.example",
    chainId: 1,
    contract: getAddress("0x5F9B5a1cdED9d6B3f5E8a2C47B0e13d6A8F4c2e1"),
    challengeTtlSeconds: 300,
    nonceTtlSeconds: 600,
    manifestMode: "public",
    acquireAction: "acquire",
    rotateAction: "rotate",
    capabilityActions: ["feed", "water"],
  };
  // Apply only the overrides that are actually set, so an unset environment
  // variable never clobbers a default with undefined.
  for (const [key, value] of Object.entries(overrides)) {
    if (value !== undefined) {
      (base as unknown as Record<string, unknown>)[key] = value;
    }
  }
  return base;
}
