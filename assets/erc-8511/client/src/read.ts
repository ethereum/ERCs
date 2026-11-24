import { getAddress, hashTypedData, isAddressEqual, parseAbi, type Address, type Hex, type PublicClient } from "viem";
import { INTERFACE_ID, INTERFACE_ID_V1, INTERFACE_ID_V2, REGISTRY_ABI, REGISTRY_ADDRESSES, REGISTRY_V1_ABI, REGISTRY_V2_ABI } from "./abi";
import { policyHash } from "./jcs";
import { intentHash, intentHashV1, isV1Registry, recoverReceiptSigner, typedReceipt, type Intent, type ReceiptJson } from "./receipt";

export interface Commitment {
  policyHash: Hex;
  version: bigint;
  effectiveAt: bigint;
  policyURI: string;
  schemaURI: string;
}

export interface SignerSet {
  policySigner: Address;
  publisher: Address;
  receiptSigner: Address;
  since: bigint;
  /** Seconds every publisher change and every later signer change waits (v2; 0 on a v1 source). */
  minDelay: number;
  /** 1 co-signer, 2 validator module, 3 guard or hook, 4 other (v2; 0 on a v1 source or when not enforced). */
  signerType: number;
}

export interface AccountStatus {
  account: Address;
  /** Where the interface was read: the account itself or the registry. */
  source: Address;
  /** Which version of the interface the source implements. */
  standard: "v3" | "v2" | "v1";
  enforced: boolean;
  policySigner: Address;
  publisher: Address;
  receiptSigner: Address;
  signersSince: bigint;
  minDelay: number;
  signerType: number;
  /** A signer change that is not yet effective (v2 only). */
  pendingSigners: SignerSet | null;
  policy: Commitment | null;
  pending: Commitment | null;
  mandate: { uri: string; configHash: Hex } | null;
  stopped: boolean;
  /** The stop was engaged by the account itself: only the account can lift it (v3; false on older sources). */
  stopHeldByAccount: boolean;
}

const ZERO = "0x0000000000000000000000000000000000000000";
const ZERO32 = `0x${"0".repeat(64)}`;

/** True if `address` answers ERC-165 for IPolicyEnforcedAccount (v3 by default; a revert or no code counts as no). */
export async function supportsStandard(client: PublicClient, address: Address, interfaceId: `0x${string}` = INTERFACE_ID): Promise<boolean> {
  try {
    return await client.readContract({ address, abi: REGISTRY_ABI, functionName: "supportsInterface", args: [interfaceId] });
  } catch {
    return false;
  }
}

/** Which version of the interface `address` implements, or null. */
export async function standardOf(client: PublicClient, address: Address): Promise<"v3" | "v2" | "v1" | null> {
  if (await supportsStandard(client, address, INTERFACE_ID)) return "v3";
  if (await supportsStandard(client, address, INTERFACE_ID_V2)) return "v2";
  if (await supportsStandard(client, address, INTERFACE_ID_V1)) return "v1";
  return null;
}

type RawSigners = { policySigner: Address; publisher: Address; receiptSigner: Address; since: bigint; minDelay?: number; signerType?: number };
const signerSet = (s: RawSigners): SignerSet => ({
  policySigner: s.policySigner,
  publisher: s.publisher,
  receiptSigner: s.receiptSigner,
  since: s.since,
  minDelay: Number(s.minDelay ?? 0),
  signerType: Number(s.signerType ?? 0),
});

/**
 * Reads an account's policy status from the chain only. Order: the account itself (if it implements the
 * interface), else the registry. No API, no key.
 */
export async function readAccount(client: PublicClient, account: Address, registry: Address): Promise<AccountStatus> {
  const acct = getAddress(account);
  let source = acct;
  let standard = await standardOf(client, acct);
  if (!standard) {
    source = getAddress(registry);
    standard = await standardOf(client, source);
    if (!standard) throw new Error(`${source} does not implement IPolicyEnforcedAccount`);
  }
  const abi = standard === "v3" ? REGISTRY_ABI : standard === "v2" ? REGISTRY_V2_ABI : REGISTRY_V1_ABI;
  const r = (functionName: "policySigner" | "policyOf" | "pendingPolicyOf" | "mandateOf" | "isStopped" | "pendingSignersOf" | "stopHeldByAccount") =>
    client.readContract({ address: source, abi, functionName, args: [acct] } as never) as Promise<unknown>;
  const [raw, policy, pending, mandate, stopped, pendingSigners, held] = (await Promise.all([
    r("policySigner"),
    r("policyOf"),
    r("pendingPolicyOf"),
    r("mandateOf"),
    r("isStopped"),
    standard === "v1" ? Promise.resolve([false, null]) : r("pendingSignersOf"),
    standard === "v3" ? r("stopHeldByAccount") : Promise.resolve(false),
  ])) as [RawSigners, Commitment, [boolean, Commitment], [string, Hex], boolean, [boolean, RawSigners | null], boolean];
  const signers = signerSet(raw);
  return {
    account: acct,
    source,
    standard,
    enforced: signers.policySigner !== ZERO,
    policySigner: signers.policySigner,
    publisher: signers.publisher,
    receiptSigner: signers.receiptSigner,
    signersSince: signers.since,
    minDelay: signers.minDelay,
    signerType: signers.signerType,
    pendingSigners: pendingSigners[0] && pendingSigners[1] ? signerSet(pendingSigners[1]) : null,
    policy: policy.policyHash === ZERO32 ? null : policy,
    pending: pending[0] ? pending[1] : null,
    mandate: mandate[0] ? { uri: mandate[0], configHash: mandate[1] } : null,
    stopped,
    stopHeldByAccount: held,
  };
}

const MAX_POLICY_BYTES = 1_000_000;
// Best-effort literal-host filter (names and IP literals). It does not resolve DNS: a server that fetches
// untrusted policyURIs should also enforce its own egress rules.
const PRIVATE_HOST =
  /^(localhost|.*\.localhost|.*\.local|.*\.internal|127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.|0\.|\[?::1?\]?$|\[?::ffff:|\[?f[cd][0-9a-f]{2}:|\[?fe[89ab][0-9a-f]:)/i;

/**
 * Fetches a policy document and checks it hashes to the committed policyHash. HTTPS only, no local or
 * private hosts, 10 s timeout, 1 MB limit: a policyURI is chosen by the account's publisher, not by you.
 */
export async function fetchPolicy(c: Commitment, fetcher: typeof fetch = fetch): Promise<{ document: unknown; matches: boolean; hash: Hex }> {
  if (!c.policyURI) throw new Error("This commitment has no policyURI (hash only)");
  const url = new URL(c.policyURI);
  if (url.protocol !== "https:") throw new Error("policyURI must be https");
  if (PRIVATE_HOST.test(url.hostname)) throw new Error("policyURI points to a local or private host");
  const res = await fetcher(url, { headers: { accept: "application/json" }, redirect: "error", signal: AbortSignal.timeout(10_000) });
  if (!res.ok) throw new Error(`policyURI answered HTTP ${res.status}`);
  if (Number(res.headers.get("content-length") ?? 0) > MAX_POLICY_BYTES) throw new Error("policy document too large");
  // Count bytes as they arrive and stop at the limit, whatever content-length said.
  const reader = res.body?.getReader();
  if (!reader) throw new Error("policyURI returned no body");
  const chunks: Uint8Array[] = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > MAX_POLICY_BYTES) {
      await reader.cancel();
      throw new Error("policy document too large");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let at = 0;
  for (const c of chunks) {
    bytes.set(c, at);
    at += c.byteLength;
  }
  const document = JSON.parse(new TextDecoder().decode(bytes));
  const hash = policyHash(document);
  return { document, matches: hash.toLowerCase() === c.policyHash.toLowerCase(), hash };
}

export interface ReceiptCheck {
  valid: boolean;
  signer: Address | null;
  expectedSigner: Address;
  problems: string[];
}

const ERC1271 = parseAbi(["function isValidSignature(bytes32 hash, bytes signature) view returns (bytes4)"]);

export interface VerifyOptions {
  /** The registry you trust. Defaults to the known registry for the client's chain. */
  registry?: Address;
  /** If given, the receipt must be bound to exactly this intent. */
  intent?: Intent;
  /** Unix seconds; defaults to the latest block's timestamp. */
  now?: bigint;
  /** Accept a receipt signed by a key the account has since rotated out (audits of old receipts). Default false. */
  allowRotatedSigner?: boolean;
  /** Largest accepted expiresAt - issuedAt, in seconds. Default 86,400. */
  maxLifetimeSeconds?: bigint;
  /**
   * Set when acting on the receipt (a gate, not an audit). Also requires: an ALLOW bound to `intent`, the
   * receipt's policy hash and version equal to the registry's current policy, the account not stopped, and a
   * decisionId not used before (claimed in `seen`, as the last step, only when everything else passed).
   */
  use?: boolean;
  /** Used decision IDs for `use`. Default: one in-memory set per process (fine for scripts, not for a fleet). */
  seen?: SeenStore;
}

/**
 * Where a verifier records used decision IDs. `claim` must be a single atomic step that returns true only for
 * the first caller, for example `INSERT ... ON CONFLICT DO NOTHING` (true when a row was inserted) or Redis
 * `SET key 1 NX`. A separate "has" then "add" is not safe: two parallel checks could both pass.
 */
export interface SeenStore {
  claim(decisionId: string): boolean | Promise<boolean>;
}
const processSeen = new Set<string>();
const memorySeen: SeenStore = {
  claim: (id) => {
    if (processSeen.has(id)) return false;
    processSeen.add(id);
    return true;
  },
};

/**
 * Verifies a decision receipt against the chain: the receipt must name the trusted registry, be within
 * its validity window, and be signed by the account's receipt signer (the current one, unless
 * allowRotatedSigner is set, then the one declared at issuedAt). EOA recovery, or ERC-1271 for a contract.
 */
export async function verifyReceipt(client: PublicClient, receipt: ReceiptJson, opts: VerifyOptions = {}): Promise<ReceiptCheck> {
  const problems: string[] = [];
  const chainId = BigInt(await client.getChainId());
  if (BigInt(receipt.chainId) !== chainId) problems.push(`receipt is for chain ${receipt.chainId}, the client is on ${chainId}`);
  const trusted = opts.registry ?? REGISTRY_ADDRESSES[Number(chainId)];
  if (!trusted) throw new Error(`no trusted registry for chain ${chainId}: pass opts.registry`);
  if (!isAddressEqual(getAddress(receipt.registry), getAddress(trusted)))
    return { valid: false, signer: null, expectedSigner: ZERO, problems: [...problems, `receipt names registry ${receipt.registry}, not the trusted ${trusted}`] };
  const now = opts.now ?? (await client.getBlock()).timestamp;
  const issuedAt = BigInt(receipt.issuedAt);
  const expiresAt = BigInt(receipt.expiresAt);
  if (issuedAt > now + 300n) problems.push("receipt is issued in the future");
  if (expiresAt < issuedAt) problems.push("receipt expires before it was issued");
  if (expiresAt - issuedAt > (opts.maxLifetimeSeconds ?? 86_400n)) problems.push("receipt lifetime is too long");
  if (expiresAt < now) problems.push("receipt has expired");
  const v1 = isV1Registry(chainId, trusted);
  const abi = v1 ? REGISTRY_V1_ABI : REGISTRY_ABI;
  const read = (fn: "signersAt" | "policySigner", args: readonly unknown[]) =>
    client.readContract({ address: getAddress(trusted), abi, functionName: fn, args } as never) as Promise<{ receiptSigner: Address }>;
  let atIssue: { receiptSigner: Address }, current: { receiptSigner: Address };
  try {
    [atIssue, current] = await Promise.all([read("signersAt", [getAddress(receipt.account), issuedAt]), read("policySigner", [getAddress(receipt.account)])]);
  } catch {
    return { valid: false, signer: null, expectedSigner: ZERO, problems: [...problems, `could not read the registry ${trusted}`] };
  }
  const expectedSigner = opts.allowRotatedSigner ? atIssue.receiptSigner : current.receiptSigner;
  if (expectedSigner === ZERO) problems.push("the account has no declared receipt signer");
  if (!opts.allowRotatedSigner && !isAddressEqual(atIssue.receiptSigner, current.receiptSigner)) problems.push("the receipt signer has been rotated since issuedAt");
  let signer: Address | null = null;
  try {
    signer = await recoverReceiptSigner(receipt);
  } catch {
    /* not an EOA signature */
  }
  let sigOk = signer !== null && expectedSigner !== ZERO && isAddressEqual(signer, expectedSigner);
  if (!sigOk && expectedSigner !== ZERO && (await client.getCode({ address: expectedSigner }))?.length) {
    try {
      const magic = await client.readContract({ address: expectedSigner, abi: ERC1271, functionName: "isValidSignature", args: [hashTypedData(typedReceipt(receipt)), receipt.signature] });
      sigOk = magic === "0x1626ba7e";
      if (sigOk) signer = expectedSigner;
    } catch {
      /* invalid */
    }
  }
  if (!sigOk) problems.push(`signature is not from the receipt signer ${expectedSigner}`);
  const bound = opts.intent ? (v1 ? intentHashV1(opts.intent) : intentHash(opts.intent)) : null;
  if (bound && bound.toLowerCase() !== receipt.intentHash.toLowerCase()) problems.push("receipt is not bound to this intent");
  if (opts.use) {
    // A first-draft receipt does not bind the operation (call or delegatecall): audits only, never acted on.
    if (v1) problems.push("receipts issued under the first-draft (v1) registry are for audits only and cannot be acted on");
    if (receipt.decision !== "ALLOW") problems.push(`receipt decision is ${receipt.decision}, not ALLOW`);
    if (!opts.intent) problems.push("acting on a receipt requires the intent it must be bound to");
    if (opts.allowRotatedSigner) problems.push("a receipt from a rotated signer cannot be acted on");
    try {
      const [policy, stopped] = (await Promise.all([
        client.readContract({ address: getAddress(trusted), abi, functionName: "policyOf", args: [getAddress(receipt.account)] } as never),
        client.readContract({ address: getAddress(trusted), abi, functionName: "isStopped", args: [getAddress(receipt.account)] } as never),
      ])) as [Commitment, boolean];
      if (BigInt(policy.version) !== BigInt(receipt.policyVersion) || policy.policyHash.toLowerCase() !== receipt.policyHash.toLowerCase())
        problems.push(`receipt policy (version ${receipt.policyVersion}) is not the current policy on the registry (version ${policy.version})`);
      if (stopped) problems.push("the account's emergency stop is engaged");
    } catch {
      problems.push(`could not read the current policy from ${trusted}`);
    }
    // Claimed last, and only when everything else passed, so a refused receipt never uses up its ID.
    if (problems.length === 0 && !(await (opts.seen ?? memorySeen).claim(receipt.decisionId.toLowerCase()))) problems.push("decisionId was already used");
  }
  return { valid: problems.length === 0, signer, expectedSigner, problems };
}
