// Reference implementation of the Inference Receipts draft: canonical form, receipt hash, signature check, day root,
// inclusion proofs and reading a day file. No dependencies: Keccak-256 and secp256k1 recovery are written out below
// with BigInt, for clarity over speed.

// Keccak-256 (the original Keccak padding, as Ethereum uses it).

const MASK = (1n << 64n) - 1n;
const RC = [
  0x0000000000000001n, 0x0000000000008082n, 0x800000000000808an, 0x8000000080008000n, 0x000000000000808bn, 0x0000000080000001n,
  0x8000000080008081n, 0x8000000000008009n, 0x000000000000008an, 0x0000000000000088n, 0x0000000080008009n, 0x000000008000000an,
  0x000000008000808bn, 0x800000000000008bn, 0x8000000000008089n, 0x8000000000008003n, 0x8000000000008002n, 0x8000000000000080n,
  0x000000000000800an, 0x800000008000000an, 0x8000000080008081n, 0x8000000000008080n, 0x0000000080000001n, 0x8000000080008008n,
];
// Rotation offsets, ROT[x][y].
const ROT = [[0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61], [28, 55, 25, 21, 56], [27, 20, 39, 8, 14]];
const rotl = (v, n) => (n === 0 ? v : ((v << BigInt(n)) | (v >> BigInt(64 - n))) & MASK);

function permute(s) {
  for (let round = 0; round < 24; round++) {
    const c = [0, 1, 2, 3, 4].map((x) => s[x] ^ s[x + 5] ^ s[x + 10] ^ s[x + 15] ^ s[x + 20]);
    const d = [0, 1, 2, 3, 4].map((x) => c[(x + 4) % 5] ^ rotl(c[(x + 1) % 5], 1));
    for (let i = 0; i < 25; i++) s[i] ^= d[i % 5];
    const b = new Array(25);
    for (let x = 0; x < 5; x++) for (let y = 0; y < 5; y++) b[y + 5 * ((2 * x + 3 * y) % 5)] = rotl(s[x + 5 * y], ROT[x][y]);
    for (let x = 0; x < 5; x++) for (let y = 0; y < 5; y++) s[x + 5 * y] = b[x + 5 * y] ^ (~b[((x + 1) % 5) + 5 * y] & b[((x + 2) % 5) + 5 * y]);
    s[0] ^= RC[round];
  }
}

export function keccak256(bytes) {
  const rate = 136;
  const padded = new Uint8Array(bytes.length + rate - (bytes.length % rate));
  padded.set(bytes);
  padded[bytes.length] ^= 0x01;
  padded[padded.length - 1] ^= 0x80;
  const s = new Array(25).fill(0n);
  for (let off = 0; off < padded.length; off += rate) {
    for (let i = 0; i < rate / 8; i++) {
      let lane = 0n;
      for (let k = 7; k >= 0; k--) lane = (lane << 8n) | BigInt(padded[off + i * 8 + k]);
      s[i] ^= lane;
    }
    permute(s);
  }
  const out = new Uint8Array(32);
  for (let i = 0; i < 4; i++) for (let k = 0, lane = s[i]; k < 8; k++, lane >>= 8n) out[i * 8 + k] = Number(lane & 0xffn);
  return out;
}

// Hex and text helpers. Hashes and signatures are lowercase 0x hex; addresses are ERC-55.

export const toHex = (bytes) => `0x${Buffer.from(bytes).toString("hex")}`;
export function fromHex(hex) {
  if (typeof hex !== "string" || !/^0x([0-9a-fA-F]{2})*$/.test(hex)) throw new Error(`not hex: ${hex}`);
  return Uint8Array.from(Buffer.from(hex.slice(2), "hex"));
}
const utf8 = (text) => new TextEncoder().encode(text);
const concat = (...parts) => Uint8Array.from(parts.flatMap((p) => [...p]));

export function checksum(address) {
  const lower = address.toLowerCase().replace(/^0x/, "");
  if (!/^[0-9a-f]{40}$/.test(lower)) throw new Error(`not an address: ${address}`);
  const hash = Buffer.from(keccak256(utf8(lower))).toString("hex");
  return `0x${[...lower].map((ch, i) => (parseInt(hash[i], 16) >= 8 ? ch.toUpperCase() : ch)).join("")}`;
}

// secp256k1 public key recovery, affine coordinates.

const P = 2n ** 256n - 2n ** 32n - 977n;
const N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;
const G = [0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798n, 0x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8n];
const mod = (a, m) => ((a % m) + m) % m;
function inverse(a, m) {
  let [lm, hm, low, high] = [1n, 0n, mod(a, m), m];
  while (low > 1n) {
    const q = high / low;
    [lm, hm, low, high] = [hm - lm * q, lm, high - low * q, low];
  }
  return mod(lm, m);
}
function power(base, exp, m) {
  let result = 1n;
  for (base = mod(base, m); exp > 0n; exp >>= 1n, base = (base * base) % m) if (exp & 1n) result = (result * base) % m;
  return result;
}
function add(a, b) {
  if (!a) return b;
  if (!b) return a;
  const [x1, y1] = a, [x2, y2] = b;
  if (x1 === x2 && mod(y1 + y2, P) === 0n) return null;
  const l = x1 === x2 ? mod(3n * x1 * x1 * inverse(2n * y1, P), P) : mod((y2 - y1) * inverse(x2 - x1, P), P);
  const x3 = mod(l * l - x1 - x2, P);
  return [x3, mod(l * (x1 - x3) - y1, P)];
}
function multiply(point, k) {
  let result = null;
  for (let q = point; k > 0n; k >>= 1n, q = add(q, q)) if (k & 1n) result = add(result, q);
  return result;
}
const bigint = (bytes) => BigInt(toHex(bytes));
const bytes32 = (n) => fromHex(`0x${n.toString(16).padStart(64, "0")}`);

/** The ERC-55 address that signed a 32-byte digest, or null for a signature that recovers to no key. */
export function recover(digest, signature) {
  const sig = fromHex(signature);
  if (sig.length !== 65) return null;
  const r = bigint(sig.slice(0, 32)), s = bigint(sig.slice(32, 64)), v = sig[64] >= 27 ? sig[64] - 27 : sig[64];
  if (v > 1 || r === 0n || r >= N || s === 0n || s >= N) return null;
  const y2 = mod(r ** 3n + 7n, P);
  let y = power(y2, (P + 1n) / 4n, P);
  if ((y * y) % P !== y2) return null;
  if (Number(y & 1n) !== v) y = P - y;
  const z = bigint(digest), rInv = inverse(r, N);
  const q = add(multiply([r, y], mod(s * rInv, N)), multiply(G, mod(-z * rInv, N)));
  if (!q) return null;
  return checksum(toHex(keccak256(concat(bytes32(q[0]), bytes32(q[1]))).slice(12)));
}

// Receipts.

export const KEYS = ["v", "request", "response", "model", "upstream", "tokensIn", "tokensOut", "price", "fee", "absorbed", "judged", "asset", "network", "payer", "nonce", "at", "signer"];
export const VERDICT = ["accepted", "passProbability", "bar", "decision"];

/** The signed form: these keys in this order, the verdict's too, nothing else, no whitespace. */
export function canonical(receipt) {
  const { judged } = receipt;
  const ordered = Object.fromEntries(KEYS.map((key) => [key, receipt[key]]));
  ordered.judged = judged === null || judged === undefined ? null : Object.fromEntries(VERDICT.map((key) => [key, judged[key]]));
  return JSON.stringify(ordered);
}

export const receiptHash = (receipt) => toHex(keccak256(utf8(canonical(receipt))));

/** The ERC-191 digest of a receipt hash: version 0x45 over the 32 hash bytes. */
export const digest = (hash) => keccak256(concat(utf8("\x19Ethereum Signed Message:\n32"), fromHex(hash)));

/** Why a receipt fails, or null when it is well formed and signed by its signer. */
export function problem(receipt) {
  if (!receipt || typeof receipt !== "object") return "not an object";
  const extra = Object.keys(receipt).filter((key) => key !== "signature" && !KEYS.includes(key));
  if (extra.length) return `unknown members: ${extra.join(", ")}`;
  const missing = KEYS.filter((key) => !(key in receipt));
  if (missing.length) return `missing members: ${missing.join(", ")}`;
  if (receipt.v !== 1) return "v is not 1";
  for (const key of ["request", "response"]) if (!/^0x[0-9a-f]{64}$/.test(receipt[key])) return `${key} is not a lowercase 32-byte hash`;
  for (const key of ["asset", "payer", "signer"]) {
    try {
      if (checksum(receipt[key]) !== receipt[key]) return `${key} is not in ERC-55 form`;
    } catch {
      return `${key} is not an address`;
    }
  }
  for (const key of ["tokensIn", "tokensOut"]) if (!Number.isSafeInteger(receipt[key]) || receipt[key] < 0) return `${key} is not a whole number`;
  for (const key of ["price", "fee", "absorbed"]) if (!/^(0|[1-9][0-9]*)$/.test(receipt[key])) return `${key} is not a decimal string`;
  if (BigInt(receipt.fee) > BigInt(receipt.price)) return "fee is more than price";
  if (typeof receipt.nonce !== "string" || !/^((0|[1-9][0-9]*)|0x[0-9a-f]{64})$/.test(receipt.nonce)) return "nonce is not a decimal string or a lowercase 32-byte hex";
  if (!/^[-a-z0-9]{3,8}:[-_a-zA-Z0-9]{1,32}$/.test(receipt.network)) return "network is not a CAIP-2 chain id";
  if (typeof receipt.at !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(receipt.at) || new Date(receipt.at).toISOString() !== receipt.at) return "at is not a UTC time with milliseconds";
  for (const key of ["model", "upstream"]) if (typeof receipt[key] !== "string" || receipt[key] === "") return `${key} is empty`;
  const j = receipt.judged;
  if (j !== null) {
    if (typeof j !== "object" || Object.keys(j).length !== VERDICT.length || !VERDICT.every((key) => key in j)) return "judged is neither null nor a verdict";
    if (typeof j.accepted !== "boolean" || typeof j.decision !== "string") return "judged is neither null nor a verdict";
    for (const key of ["passProbability", "bar"]) if (typeof j[key] !== "number" || !(j[key] >= 0 && j[key] <= 1)) return `judged.${key} is not between 0 and 1`;
  }
  if (recover(digest(receiptHash(receipt)), receipt.signature) !== receipt.signer) return "the signature is not the signer's";
  return null;
}

export const verifyReceipt = (receipt) => problem(receipt) === null;

/** The UTC day a receipt belongs to. */
export const dayOf = (receipt) => receipt.at.slice(0, 10);

// Day roots: sorted-pair Keccak-256, an unpaired node carried up as it is.

function pair(a, b) {
  const [x, y] = a < b ? [a, b] : [b, a]; // lowercase hex of equal length: text order is numeric order
  return toHex(keccak256(concat(fromHex(x), fromHex(y))));
}

function layers(receipts) {
  if (receipts.length === 0) throw new Error("a day without receipts has no root");
  const tree = [receipts.map(receiptHash)];
  while (tree.at(-1).length > 1) {
    const below = tree.at(-1), above = [];
    for (let i = 0; i < below.length; i += 2) above.push(i + 1 < below.length ? pair(below[i], below[i + 1]) : below[i]);
    tree.push(above);
  }
  return tree;
}

/** The day root over the receipts in the order given (the order they were signed). */
export const dayRoot = (receipts) => layers(receipts).at(-1)[0];

/** Siblings from the receipt's hash up to the root, in the form OpenZeppelin's MerkleProof.verify takes. */
export function proof(receipts, index) {
  if (!Number.isInteger(index) || index < 0 || index >= receipts.length) throw new RangeError(`no receipt at ${index}`);
  const path = [];
  for (const layer of layers(receipts).slice(0, -1)) {
    if (layer[index ^ 1] !== undefined) path.push(layer[index ^ 1]);
    index >>= 1;
  }
  return path;
}

/** Whether a receipt is covered by a root. The leaf is always computed from the receipt, never taken as given. */
export const verifyProof = (receipt, path, root) => path.reduce((node, sibling) => pair(node, sibling), receiptHash(receipt)) === root;

/** A day file: one receipt per line. Lines that do not parse are counted, not guessed at. */
export function readDay(text) {
  const receipts = [];
  let unreadable = 0;
  for (const line of text.split("\n")) {
    if (!line) continue;
    try {
      receipts.push(JSON.parse(line));
    } catch {
      unreadable += 1;
    }
  }
  return { receipts, unreadable };
}

/** The day list an issuer serves for a day. */
export function dayList(day, signer, receipts, unreadable = 0) {
  return { day, signer, count: receipts.length, root: receipts.length ? dayRoot(receipts) : null, unreadable, receipts };
}

/** Why a day list fails, or null: every receipt valid, of that day and signer, and the count and root right. */
export function listProblem(list) {
  for (const [i, receipt] of list.receipts.entries()) {
    const why = problem(receipt);
    if (why) return `receipt ${i}: ${why}`;
    if (dayOf(receipt) !== list.day) return `receipt ${i} is of ${dayOf(receipt)}, not ${list.day}`;
    if (receipt.signer !== list.signer) return `receipt ${i} is signed by ${receipt.signer}, not ${list.signer}`;
  }
  if (list.count !== list.receipts.length) return `count ${list.count} for ${list.receipts.length} receipts`;
  const root = list.receipts.length ? dayRoot(list.receipts) : null;
  if (list.root !== root) return `root ${list.root}, computed ${root}`;
  return null;
}

/** The day record an issuer publishes on chain for a closed day. */
export const dayRecord = (list) => ({ kind: "receipts", date: list.day, signer: list.signer, count: list.count, root: list.root });
