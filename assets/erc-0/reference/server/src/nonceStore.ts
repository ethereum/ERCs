/// A single-use nonce store with expiry.
///
///  The standard requires the challenge nonce to be "single-use" and "issued by
///  the verifier": both properties live here. `issue` records a fresh nonce
///  with an expiry; `consume` returns true at most once per nonce and only
///  while it is unexpired. Because Node runs this on one thread, the
///  check-and-delete inside `consume` cannot interleave with another request,
///  so a replayed nonce arriving concurrently still sees at most one success.
///
///  This is a reference simplification. A production verifier would back the
///  same interface with a shared store (for example Redis with per-key TTL and
///  an atomic GETDEL) so single-use holds across many server instances.
export interface NonceStore {
  issue(nonce: string, expiresAtMs: number): void;
  consume(nonce: string, nowMs: number): boolean;
}

export function createNonceStore(): NonceStore {
  const expiries = new Map<string, number>();

  return {
    issue(nonce, expiresAtMs) {
      expiries.set(nonce, expiresAtMs);
    },

    consume(nonce, nowMs) {
      const expiresAtMs = expiries.get(nonce);
      if (expiresAtMs === undefined) {
        return false;
      }
      // Delete first so the nonce is spent whether or not it was still valid;
      // a spent-but-expired nonce is never resurrected.
      expiries.delete(nonce);
      return nowMs < expiresAtMs;
    },
  };
}
