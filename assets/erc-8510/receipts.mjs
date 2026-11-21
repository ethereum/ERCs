// Reference implementation of ERC-8510, Inference Receipts: canonical form, receipt hash, signature check, day lists,
// day roots, inclusion proofs and day records. No dependencies: Keccak-256 and secp256k1 recovery are written out below
// with BigInt, for clarity over speed (about 11 ms to check one receipt).

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
function fromHex(hex) {
  if (typeof hex !== "string" || !/^0x([0-9a-fA-F]{2})*$/.test(hex)) throw new Error(`not hex: ${hex}`);
  return Uint8Array.from(Buffer.from(hex.slice(2), "hex"));
}
const utf8 = (text) => new TextEncoder().encode(text);
const concat = (...parts) => Uint8Array.from(parts.flatMap((p) => [...p]));

export function checksum(address) {
  const lower = typeof address === "string" ? address.toLowerCase().replace(/^0x/, "") : "";
  if (!/^[0-9a-f]{40}$/.test(lower)) throw new Error(`not an address: ${address}`);
  const hash = Buffer.from(keccak256(utf8(lower))).toString("hex");
  return `0x${[...lower].map((ch, i) => (parseInt(hash[i], 16) >= 8 ? ch.toUpperCase() : ch)).join("")}`;
}

const isChecksummed = (address) => {
  try {
    return checksum(address) === address;
  } catch {
    return false;
  }
};

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

/** The ERC-55 address that signed a 32-byte digest, or null when the signature recovers to no key. `v` must be 27 or 28. */
export function recover(digest, signature) {
  let sig;
  try {
    sig = fromHex(signature);
  } catch {
    return null;
  }
  if (sig.length !== 65 || (sig[64] !== 27 && sig[64] !== 28)) return null;
  const r = bigint(sig.slice(0, 32)), s = bigint(sig.slice(32, 64)), v = sig[64] - 27;
  if (r === 0n || r >= N || s === 0n || s >= N) return null;
  const y2 = mod(r ** 3n + 7n, P);
  let y = power(y2, (P + 1n) / 4n, P);
  if ((y * y) % P !== y2) return null;
  if (Number(y & 1n) !== v) y = P - y;
  const z = bigint(digest), rInv = inverse(r, N);
  const q = add(multiply([r, y], mod(s * rInv, N)), multiply(G, mod(-z * rInv, N)));
  if (!q) return null;
  return checksum(toHex(keccak256(concat(bytes32(q[0]), bytes32(q[1]))).slice(12)));
}

// Strict JSON: what JSON.parse accepts, minus repeated member names, which JSON.parse resolves silently to the last one.

/** Parses JSON text and throws when any object in it repeats a member name. */
export function parseJson(text) {
  const value = JSON.parse(text);
  const objects = [];
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (ch === "{") objects.push(new Set());
    else if (ch === "[") objects.push(null);
    else if (ch === "}" || ch === "]") objects.pop();
    else if (ch === '"') {
      let end = i + 1;
      while (text[end] !== '"') end += text[end] === "\\" ? 2 : 1;
      let next = end + 1;
      while (/\s/.test(text[next] ?? "")) next++;
      const names = objects.at(-1);
      if (text[next] === ":" && names) {
        const name = JSON.parse(text.slice(i, end + 1));
        if (names.has(name)) throw new Error(`repeated member name: ${name}`);
        names.add(name);
      }
      i = end;
    }
  }
  return value;
}

// Receipts.

const KEYS = ["v", "request", "response", "model", "upstream", "tokensIn", "tokensOut", "price", "fee", "absorbed", "judged", "asset", "network", "payer", "nonce", "at", "signer"];
const VERDICT = ["accepted", "passProbability", "bar", "decision"];
const HASH = /^0x[0-9a-f]{64}$/;
const DECIMAL = /^(0|[1-9][0-9]*)$/;
const TEXT = /^[\x20-\x7e]{1,256}$/;
const AT = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const SIGNATURE = /^0x[0-9a-f]{128}(1b|1c)$/;
const UINT256 = 2n ** 256n;
const isObject = (x) => x !== null && typeof x === "object" && !Array.isArray(x);
const uint256 = (x) => typeof x === "string" && DECIMAL.test(x) && BigInt(x) < UINT256;
const sixDecimals = (x) => typeof x === "number" && x >= 0 && x <= 1 && Number(x.toFixed(6)) === x;

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

/** Why a receipt fails, or null when it is well formed and signed by its signer. Never throws. */
export function problem(receipt) {
  if (!isObject(receipt)) return "not an object";
  const extra = Object.keys(receipt).filter((key) => key !== "signature" && !KEYS.includes(key));
  if (extra.length) return `unknown members: ${extra.join(", ")}`;
  const missing = [...KEYS, "signature"].filter((key) => !Object.hasOwn(receipt, key));
  if (missing.length) return `missing members: ${missing.join(", ")}`;
  if (receipt.v !== 1) return "v is not 1";
  for (const key of ["request", "response"]) if (typeof receipt[key] !== "string" || !HASH.test(receipt[key])) return `${key} is not a lowercase 32-byte hash`;
  for (const key of ["model", "upstream"]) if (typeof receipt[key] !== "string" || !TEXT.test(receipt[key])) return `${key} is not 1 to 256 printable ASCII characters`;
  for (const key of ["tokensIn", "tokensOut"]) if (!Number.isSafeInteger(receipt[key]) || receipt[key] < 0) return `${key} is not a whole number`;
  for (const key of ["price", "fee", "absorbed"]) if (!uint256(receipt[key])) return `${key} is not a decimal string below 2^256`;
  if (BigInt(receipt.fee) > BigInt(receipt.price)) return "fee is more than price";
  const j = receipt.judged;
  if (j !== null) {
    if (!isObject(j) || Object.keys(j).length !== VERDICT.length || !VERDICT.every((key) => Object.hasOwn(j, key))) return "judged is neither null nor a verdict";
    if (typeof j.accepted !== "boolean") return "judged.accepted is not a boolean";
    for (const key of ["passProbability", "bar"]) if (!sixDecimals(j[key])) return `judged.${key} is not a number from 0 to 1 with at most 6 decimals`;
    if (typeof j.decision !== "string" || !TEXT.test(j.decision)) return "judged.decision is not 1 to 256 printable ASCII characters";
  }
  for (const key of ["asset", "payer", "signer"]) if (!isChecksummed(receipt[key])) return `${key} is not an ERC-55 address`;
  if (typeof receipt.network !== "string" || !/^[-a-z0-9]{3,8}:[-_a-zA-Z0-9]{1,32}$/.test(receipt.network)) return "network is not a CAIP-2 chain id";
  if (!(uint256(receipt.nonce) || (typeof receipt.nonce === "string" && HASH.test(receipt.nonce)))) return "nonce is not a decimal string below 2^256 or a lowercase 32-byte hex";
  const at = receipt.at;
  if (typeof at !== "string" || !AT.test(at) || Number.isNaN(Date.parse(at)) || new Date(at).toISOString() !== at) return "at is not a UTC time with milliseconds";
  if (typeof receipt.signature !== "string" || !SIGNATURE.test(receipt.signature)) return "signature is not 65 bytes of lowercase hex with v 27 or 28";
  if (BigInt(`0x${receipt.signature.slice(66, 130)}`) > N / 2n) return "signature s is above half the curve order";
  if (recover(digest(receiptHash(receipt)), receipt.signature) !== receipt.signer) return "the signature is not the signer's";
  return null;
}

/** Reads one receipt from JSON text: repeated member names are refused, then the receipt is checked. Throws on failure. */
export function parseReceipt(text) {
  const receipt = parseJson(text);
  const why = problem(receipt);
  if (why) throw new Error(why);
  return receipt;
}

/** The UTC day a receipt belongs to. */
export const dayOf = (receipt) => receipt.at.slice(0, 10);

/** Day-list order: ascending `at`, then ascending receipt hash. */
function order(a, b) {
  if (a.at !== b.at) return a.at < b.at ? -1 : 1;
  const [x, y] = [receiptHash(a), receiptHash(b)];
  return x === y ? 0 : x < y ? -1 : 1;
}

const paymentOf = (r) => `${r.network} ${r.asset} ${r.payer} ${r.nonce}`;

// Day roots: sorted-pair Keccak-256, an unpaired node carried up as it is.

function pair(a, b) {
  const [x, y] = a < b ? [a, b] : [b, a]; // lowercase hex of equal length: text order is numeric order
  return toHex(keccak256(concat(fromHex(x), fromHex(y))));
}

function tree(receipts) {
  if (receipts.length === 0) throw new Error("a day without receipts has no root");
  const layers = [receipts.map(receiptHash)];
  while (layers.at(-1).length > 1) {
    const below = layers.at(-1), above = [];
    for (let i = 0; i < below.length; i += 2) above.push(i + 1 < below.length ? pair(below[i], below[i + 1]) : below[i]);
    layers.push(above);
  }
  return layers;
}

/** The day root over the receipts in the order given. A day list gives them in day-list order. */
export const dayRoot = (receipts) => tree(receipts).at(-1)[0];

/** A receipt's leaf, its siblings up to the root (the form OpenZeppelin's MerkleProof.verify takes) and the root. */
export function proof(receipts, index) {
  if (!Number.isInteger(index) || index < 0 || index >= receipts.length) throw new RangeError(`no receipt at index ${index}: the list has ${receipts.length}`);
  const layers = tree(receipts), leaf = layers[0][index], path = [];
  for (const layer of layers.slice(0, -1)) {
    if (layer[index ^ 1] !== undefined) path.push(layer[index ^ 1]);
    index >>= 1;
  }
  return { leaf, path, root: layers.at(-1)[0] };
}

const NODE = /^0x[0-9a-fA-F]{64}$/;

/** Whether a root covers a receipt. The leaf is computed from the receipt, never taken as given; bad input is false. */
export function verifyProof(receipt, path, root) {
  if (!isObject(receipt) || !Array.isArray(path) || typeof root !== "string" || !NODE.test(root) || !path.every((n) => typeof n === "string" && NODE.test(n))) return false;
  return path.reduce((node, sibling) => pair(node, sibling.toLowerCase()), receiptHash(receipt)) === root.toLowerCase();
}

/**
 * A day file: one receipt per line, in any order. Blank lines are skipped; a line that is not JSON, repeats a member
 * name or is not an object is counted as unreadable. Given `day` and `signer`, so is any receipt that is not a valid
 * receipt of that day and signer, as an issuer counts them.
 */
export function readDay(text, day, signer) {
  const receipts = [];
  let unreadable = 0;
  for (const line of text.replace(/^﻿/, "").split(/\r?\n/)) {
    if (!line.trim()) continue;
    let receipt;
    try {
      receipt = parseJson(line);
    } catch {
      unreadable += 1;
      continue;
    }
    const fits = isObject(receipt) && (day === undefined || (problem(receipt) === null && dayOf(receipt) === day && receipt.signer === signer));
    if (fits) receipts.push(receipt);
    else unreadable += 1;
  }
  return { receipts, unreadable };
}

/** The day list an issuer serves for a day: its receipts in day-list order, with their count and root. */
export function dayList(day, signer, receipts, unreadable = 0) {
  const sorted = [...receipts].sort(order);
  return { day, signer, count: sorted.length, root: sorted.length ? dayRoot(sorted) : null, unreadable, receipts: sorted };
}

/** Why a set of receipts cannot be one day's list for a signer, in the order given, or null. */
export function receiptsProblem(day, signer, receipts) {
  const payments = new Set();
  for (const [i, receipt] of receipts.entries()) {
    const why = problem(receipt);
    if (why) return `receipt ${i}: ${why}`;
    if (dayOf(receipt) !== day) return `receipt ${i} is of ${dayOf(receipt)}, not ${day}`;
    if (receipt.signer !== signer) return `receipt ${i} is signed by ${receipt.signer}, not ${signer}`;
    if (i > 0 && order(receipts[i - 1], receipt) >= 0) return `receipt ${i} is out of day-list order or repeats receipt ${i - 1}`;
    if (payments.has(paymentOf(receipt))) return `receipt ${i} repeats a payment already listed`;
    payments.add(paymentOf(receipt));
  }
  return null;
}

const LIST = ["day", "signer", "count", "root", "unreadable", "receipts"];
const isDay = (day) => typeof day === "string" && /^\d{4}-\d{2}-\d{2}$/.test(day) && !Number.isNaN(Date.parse(day)) && new Date(day).toISOString().slice(0, 10) === day;
const isCount = (n) => Number.isSafeInteger(n) && n >= 0;

/** Why a served day list fails, or null: its shape, every receipt valid, of that day and signer, in order, count and root right. */
export function listProblem(list) {
  if (!isObject(list)) return "not an object";
  const extra = Object.keys(list).filter((key) => !LIST.includes(key));
  if (extra.length) return `unknown members: ${extra.join(", ")}`;
  const missing = LIST.filter((key) => !Object.hasOwn(list, key));
  if (missing.length) return `missing members: ${missing.join(", ")}`;
  if (!isDay(list.day)) return "day is not a YYYY-MM-DD date";
  if (!isChecksummed(list.signer)) return "signer is not an ERC-55 address";
  if (!isCount(list.count) || !isCount(list.unreadable)) return "count and unreadable must be whole numbers";
  if (!Array.isArray(list.receipts)) return "receipts is not an array";
  const why = receiptsProblem(list.day, list.signer, list.receipts);
  if (why) return why;
  if (list.count !== list.receipts.length) return `count ${list.count} for ${list.receipts.length} receipts`;
  const root = list.receipts.length ? dayRoot(list.receipts) : null;
  if (list.root !== root) return `root ${list.root}, computed ${root}`;
  return null;
}

const ZERO = `0x${"0".repeat(64)}`;

/** The day record an issuer publishes for a closed day. A day with unreadable entries gets none until they are resolved. */
export function dayRecord(list) {
  if (list.unreadable !== 0) throw new Error(`${list.unreadable} unreadable entries: no record until they are resolved`);
  return { kind: "receipts", date: list.day, signer: list.signer, count: list.count, root: list.root ?? ZERO };
}

/** Why a published record does not state a day list, or null. Members beyond the five required are allowed. */
export function recordProblem(record, list) {
  if (!isObject(record)) return "not an object";
  if (record.kind !== "receipts") return "kind is not receipts";
  if (record.date !== list.day) return `date ${record.date}, list ${list.day}`;
  if (record.signer !== list.signer) return `signer ${record.signer}, list ${list.signer}`;
  if (record.count !== list.count) return `count ${record.count}, list ${list.count}`;
  if (record.root !== (list.root ?? ZERO)) return `root ${record.root}, list ${list.root ?? ZERO}`;
  return null;
}
