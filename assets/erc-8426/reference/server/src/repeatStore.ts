import { createHash } from "node:crypto";

/// A store of recent request outcomes, so that a repeat of an identical request
///  is answered with the first request's outcome.
///
///  The standard: "A repeat of an identical request is not a replay. Device
///  wallets and in-app browsers retry a request the device abandoned, so a
///  verifier can receive the same presentation twice for one tap ... A Pass
///  Issuer SHOULD answer a repeat that is identical to a request it is still
///  processing, or that it completed within a short window, with that
///  request's outcome, and SHOULD NOT execute the action a second time or
///  refuse the repeat as `nonce_invalid`" (Authorization of pass-reachable
///  actions).
///
///  Identity is a digest of everything the request carries: for the signed
///  route the message, signature and declared target; for a capability link
///  the capability and the body. A request that differs in any field has a
///  different key and is handled on its own, so a spent nonce presented with a
///  different body is still refused as a replay by the nonce store.
///
///  While the first request is in flight, a repeat awaits the same promise, so
///  the action runs once however many identical requests arrive together. Once
///  it has completed, the recorded outcome is returned until the window
///  closes; the window is measured from when the handler resolved, not from
///  when the request arrived, so a slow handler does not shorten it. After the
///  window the repeat is a new request, and on the signed route the nonce
///  store refuses it.
///
///  A 503 (read_failed) is never recorded. It says the request could not be
///  judged, not how it was judged, so a retry is judged afresh: a capability
///  link retried after Retry-After meets a fresh read, and a signed retry meets
///  the nonce store (see the /action route for why it needs a fresh challenge).
///
///  This is a reference simplification: one process, one map. A production
///  verifier would keep the same keys in a shared store with a TTL so that a
///  repeat landing on another instance is still recognized.
export interface Outcome {
  status: number;
  body: Record<string, unknown>;
}

export interface RepeatStore {
  /// Run `handler` for the request identified by `key`, or return the outcome
  ///  of an identical request that is in flight or completed within the window.
  join(key: string, nowMs: number, handler: () => Promise<Outcome>): Promise<Outcome>;
}

/// Digest the parts that make a request identical. Each part is length-
///  prefixed so no two sequences of parts share a digest.
export function requestKey(...parts: string[]): string {
  const hash = createHash("sha256");
  for (const part of parts) {
    hash.update(`${part.length}:`);
    hash.update(part);
  }
  return hash.digest("base64url");
}

/// Outcomes that are not recorded: the fresh read could not be taken, so there
///  is no verdict to repeat.
function isRecordable(outcome: Outcome): boolean {
  return outcome.status !== 503;
}

/// `now` is read when a handler resolves, to stamp its completion; it defaults
///  to the wall clock and is injected alongside the app's clock in tests.
export function createRepeatStore(windowMs: number, now: () => number = Date.now): RepeatStore {
  const inFlight = new Map<string, Promise<Outcome>>();
  const completed = new Map<string, { outcome: Outcome; completedAtMs: number }>();

  function sweep(nowMs: number): void {
    for (const [key, entry] of completed) {
      if (nowMs - entry.completedAtMs >= windowMs) {
        completed.delete(key);
      }
    }
  }

  return {
    async join(key, nowMs, handler) {
      sweep(nowMs);
      const pending = inFlight.get(key);
      if (pending) {
        return pending;
      }
      const recent = completed.get(key);
      if (recent) {
        return recent.outcome;
      }
      const run = handler().then(
        (outcome) => {
          if (isRecordable(outcome)) {
            completed.set(key, { outcome, completedAtMs: now() });
          }
          inFlight.delete(key);
          return outcome;
        },
        (error: unknown) => {
          // A handler that threw recorded nothing: the next identical request
          // is handled afresh rather than answered with an error it may not
          // reproduce.
          inFlight.delete(key);
          throw error;
        },
      );
      inFlight.set(key, run);
      return run;
    },
  };
}
