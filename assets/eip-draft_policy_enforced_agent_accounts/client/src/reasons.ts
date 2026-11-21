import { hexToString, stringToHex, type Hex } from "viem";

/**
 * Standard reason codes (append-only; an identifier is never reused or redefined).
 * On the wire a code is the ASCII identifier right-padded to bytes32. NONE (all zeros) means allowed.
 * Project-specific detail codes use "<namespace>:<code>" in the receipt's detailCode, e.g. "palisec:PS_BUDGET_001".
 */
export const REASONS = {
  TARGET_NOT_ALLOWED: "The target address is not allowed by the policy.",
  METHOD_NOT_ALLOWED: "The function (selector) is not allowed on this target.",
  DENY_RULE: "An explicit deny rule matched.",
  OVER_TX_CAP: "The transaction exceeds the per-transaction cap.",
  OVER_BUDGET: "The transaction exceeds the rolling or cumulative budget.",
  OVER_LIMIT: "A value limit (per-transaction or budget) is exceeded; the enforcer does not distinguish which.",
  RATE_LIMITED: "Too many requests in the policy's window.",
  COOLDOWN_OR_LOOP: "The same intent or calldata was repeated within the cooldown.",
  REPLAY: "The request or authorization was already used, or has expired.",
  PAUSED: "The agent or account is paused, or the emergency stop is engaged.",
  HUMAN_APPROVAL_REQUIRED: "A human approver must approve this exact operation first.",
  ASSET_UNSAFE: "Simulation shows an unsafe asset outcome (honeypot, tax, unexpected balance change).",
  APPROVAL_RISK: "An unlimited or oversized token approval to a spender that is not allowed.",
  SIMULATION_UNAVAILABLE: "The required simulation could not run.",
  FEE_UNAVAILABLE: "The fee could not be estimated or is invalid.",
  POLICY_UNAVAILABLE: "No valid active policy.",
  STATE_UNAVAILABLE: "The enforcer's authoritative state could not be read.",
  DEPENDENCY_UNAVAILABLE: "An external dependency the policy requires could not be read.",
  NOT_RECOVERABLE: "The policy requires a recovery setup the account does not meet.",
  WRONG_CHAIN: "The chain or its infrastructure is not available for this request.",
  ATTESTATION_FAILED: "The signer's attestation could not be verified.",
  UNAUTHORIZED: "The requester is not authenticated or not allowed to ask.",
  INVALID_REQUEST: "The request is malformed.",
  OTHER: "Another reason; see the detail code.",
} as const;
export type ReasonCode = keyof typeof REASONS | "NONE";

export const encodeReason = (code: string): Hex => (code === "NONE" || code === "" ? (`0x${"0".repeat(64)}` as Hex) : stringToHex(code, { size: 32 }));
export const decodeReason = (b: Hex): string => (/^0x0{64}$/i.test(b) ? "NONE" : hexToString(b, { size: 32 }).replace(/\0+$/, ""));

/** Palisec's PS_* codes mapped to the standard codes (the reference enforcer's profile). */
export const PALISEC_REASON_MAP: Record<string, keyof typeof REASONS> = {
  PS_AUTH_001: "UNAUTHORIZED",
  PS_POLICY_001: "POLICY_UNAVAILABLE",
  PS_POLICY_002: "DENY_RULE",
  PS_TARGET_001: "TARGET_NOT_ALLOWED",
  PS_METHOD_001: "METHOD_NOT_ALLOWED",
  PS_BUDGET_001: "OVER_LIMIT",
  PS_RATE_001: "RATE_LIMITED",
  PS_LOOP_001: "COOLDOWN_OR_LOOP",
  PS_REPLAY_001: "REPLAY",
  PS_ATTEST_001: "ATTESTATION_FAILED",
  PS_SIM_001: "SIMULATION_UNAVAILABLE",
  PS_FEE_001: "FEE_UNAVAILABLE",
  PS_HUMAN_001: "HUMAN_APPROVAL_REQUIRED",
  PS_PAUSED_001: "PAUSED",
  PS_STATE_001: "STATE_UNAVAILABLE",
  PS_CHAIN_001: "WRONG_CHAIN",
  PS_REQUEST_001: "INVALID_REQUEST",
  PS_ASSET_001: "ASSET_UNSAFE",
  PS_ASSET_002: "ASSET_UNSAFE",
  PS_ASSET_003: "ASSET_UNSAFE",
  PS_APPROVAL_001: "APPROVAL_RISK",
  PS_RECOVERY_001: "NOT_RECOVERABLE",
  PS_RECOVERY_002: "NOT_RECOVERABLE",
  PS_RECOVERY_003: "DEPENDENCY_UNAVAILABLE",
};
