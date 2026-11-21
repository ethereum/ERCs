import { getAddress, hashTypedData, isAddressEqual, parseAbi, type Address, type Hex, type PublicClient } from "viem";
import { INTERFACE_ID, REGISTRY_ABI, REGISTRY_ADDRESSES } from "./abi";
import { policyHash } from "./jcs";
import { intentHash, recoverReceiptSigner, typedReceipt, type Intent, type ReceiptJson } from "./receipt";

export interface Commitment {
  policyHash: Hex;
  version: bigint;
  effectiveAt: bigint;
  policyURI: string;
  schemaURI: string;
}

export interface AccountStatus {
  account: Address;
  /** Where the interface was read: the account itself or the registry. */
  source: Address;
  enforced: boolean;
  policySigner: Address;
  publisher: Address;
  receiptSigner: Address;
  signersSince: bigint;
  policy: Commitment | null;
  pending: Commitment | null;
  mandate: { uri: string; configHash: Hex } | null;
  stopped: boolean;
}

const ZERO = "0x0000000000000000000000000000000000000000";
const ZERO32 = `0x${"0".repeat(64)}`;

/** True if `address` answers ERC-165 for IPolicyEnforcedAccount (a revert or no code counts as no). */
export async function supportsStandard(client: PublicClient, address: Address): Promise<boolean> {
  try {
    return await client.readContract({ address, abi: REGISTRY_ABI, functionName: "supportsInterface", args: [INTERFACE_ID] });
  } catch {
    return false;
  }
}

/**
 * Reads an account's policy status from the chain only. Order: the account itself (if it implements the
 * interface), else the registry. No API, no key.
 */
export async function readAccount(client: PublicClient, account: Address, registry: Address): Promise<AccountStatus> {
  const acct = getAddress(account);
  const source = (await supportsStandard(client, acct)) ? acct : getAddress(registry);
  if (source !== acct && !(await supportsStandard(client, source))) throw new Error(`${source} does not implement IPolicyEnforcedAccount`);
  const r = (functionName: "policySigner" | "policyOf" | "pendingPolicyOf" | "mandateOf" | "isStopped") =>
    client.readContract({ address: source, abi: REGISTRY_ABI, functionName, args: [acct] } as never) as Promise<unknown>;
  const [signers, policy, pending, mandate, stopped] = (await Promise.all([r("policySigner"), r("policyOf"), r("pendingPolicyOf"), r("mandateOf"), r("isStopped")])) as [
    { policySigner: Address; publisher: Address; receiptSigner: Address; since: bigint },
    Commitment,
    [boolean, Commitment],
    [string, Hex],
    boolean,
  ];
  return {
    account: acct,
    source,
    enforced: signers.policySigner !== ZERO,
    policySigner: signers.policySigner,
    publisher: signers.publisher,
    receiptSigner: signers.receiptSigner,
    signersSince: signers.since,
    policy: policy.policyHash === ZERO32 ? null : policy,
    pending: pending[0] ? pending[1] : null,
    mandate: mandate[0] ? { uri: mandate[0], configHash: mandate[1] } : null,
    stopped,
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
}

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
  const read = (fn: "signersAt" | "policySigner", args: readonly unknown[]) =>
    client.readContract({ address: getAddress(trusted), abi: REGISTRY_ABI, functionName: fn, args } as never) as Promise<{ receiptSigner: Address }>;
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
  if (opts.intent && intentHash(opts.intent).toLowerCase() !== receipt.intentHash.toLowerCase()) problems.push("receipt is not bound to this intent");
  return { valid: problems.length === 0, signer, expectedSigner, problems };
}
