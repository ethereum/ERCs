// SPDX-License-Identifier: CC0-1.0
// Reference implementation of ERC-8510, Inference Receipts. Keccak-256 and secp256k1 recovery are written out with
// BigInt so the file has no dependencies; that costs about 11 ms per receipt checked.

// Keccak-256 with the original Keccak padding (0x01) that Ethereum uses; SHA-3 pads with 0x06.
const MASK = (1n << 64n) - 1n;
const RC = [
  0x0000000000000001n, 0x0000000000008082n, 0x800000000000808an, 0x8000000080008000n, 0x000000000000808bn, 0x0000000080000001n,
  0x8000000080008081n, 0x8000000000008009n, 0x000000000000008an, 0x0000000000000088n, 0x0000000080008009n, 0x000000008000000an,
  0x000000008000808bn, 0x800000000000008bn, 0x8000000000008089n, 0x8000000000008003n, 0x8000000000008002n, 0x8000000000000080n,
  0x000000000000800an, 0x800000008000000an, 0x8000000080008081n, 0x8000000000008080n, 0x0000000080000001n, 0x8000000080008008n,
];
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

/** The ERC-55 address that signed a 32-byte digest, or null when the signature recovers to no key. Accepts either `s`. */
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

/** JSON.parse, refusing repeated member names, which JSON.parse would silently resolve to the last value. */
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

const MEMBERS = ["v", "request", "response", "model", "upstream", "tokensIn", "tokensOut", "price", "fee", "absorbed", "judged", "asset", "network", "payer", "nonce", "at", "signer"];
const VERDICT = ["accepted", "passProbability", "bar", "decision"];
const HASH = /^0x[0-9a-f]{64}$/;
const ANY_CASE_HASH = /^0x[0-9a-fA-F]{64}$/;
const DECIMAL = /^(0|[1-9][0-9]*)$/;
const TEXT = /^[\x20-\x7e]{1,256}$/;
const AT = /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])T([01]\d|2[0-3]):[0-5]\d:[0-5]\d\.\d{3}Z$/;
const NETWORK = /^eip155:[1-9][0-9]*$/;
const SIGNATURE = /^0x[0-9a-f]{128}(1b|1c)$/;
const TWO_256 = 2n ** 256n;
const isObject = (x) => x !== null && typeof x === "object" && !Array.isArray(x);
const isUint256 = (x) => typeof x === "string" && DECIMAL.test(x) && BigInt(x) < TWO_256;
const isWhole = (n) => Number.isSafeInteger(n) && n >= 0;
// String(x) is the shortest decimal that reads back as x, which is where the spec counts decimals.
const hasSixDecimals = (x) => typeof x === "number" && x >= 0 && x <= 1 && !String(x).includes("e") && (String(x).split(".")[1] ?? "").length <= 6;
const isDay = (day) => typeof day === "string" && /^\d{4}-\d{2}-\d{2}$/.test(day) && !Number.isNaN(Date.parse(day)) && new Date(day).toISOString().slice(0, 10) === day;

/** Members in table order, the verdict's too; JSON.stringify writes values as RFC 8785 does. */
export function canonical(receipt) {
  const { judged } = receipt;
  const ordered = Object.fromEntries(MEMBERS.map((key) => [key, receipt[key]]));
  ordered.judged = judged === null || judged === undefined ? null : Object.fromEntries(VERDICT.map((key) => [key, judged[key]]));
  return JSON.stringify(ordered);
}

export const receiptHash = (receipt) => toHex(keccak256(utf8(canonical(receipt))));

export const digest = (hash) => keccak256(concat(utf8("\x19Ethereum Signed Message:\n32"), fromHex(hash)));

/** Why a receipt is invalid, or null. Never throws. */
export function receiptProblem(receipt) {
  if (!isObject(receipt)) return "not an object";
  const extra = Object.keys(receipt).filter((key) => key !== "signature" && !MEMBERS.includes(key));
  if (extra.length) return `unknown members: ${extra.join(", ")}`;
  const missing = [...MEMBERS, "signature"].filter((key) => !Object.hasOwn(receipt, key));
  if (missing.length) return `missing members: ${missing.join(", ")}`;
  if (receipt.v !== 1) return "v is not 1";
  for (const key of ["request", "response"]) if (typeof receipt[key] !== "string" || !HASH.test(receipt[key])) return `${key} is not a lowercase 32-byte hash`;
  for (const key of ["model", "upstream"]) if (typeof receipt[key] !== "string" || !TEXT.test(receipt[key])) return `${key} is not 1 to 256 printable ASCII characters`;
  for (const key of ["tokensIn", "tokensOut"]) if (!isWhole(receipt[key])) return `${key} is not a whole number up to 2^53 - 1`;
  for (const key of ["price", "fee", "absorbed"]) if (!isUint256(receipt[key])) return `${key} is not a decimal string below 2^256`;
  if (BigInt(receipt.fee) > BigInt(receipt.price)) return "fee is more than price";
  const verdict = receipt.judged;
  if (verdict !== null) {
    if (!isObject(verdict) || Object.keys(verdict).length !== VERDICT.length || !VERDICT.every((key) => Object.hasOwn(verdict, key))) return "judged is neither null nor a verdict";
    if (typeof verdict.accepted !== "boolean") return "judged.accepted is not a boolean";
    for (const key of ["passProbability", "bar"]) if (!hasSixDecimals(verdict[key])) return `judged.${key} is not a number from 0 to 1 with at most 6 decimals`;
    if (typeof verdict.decision !== "string" || !TEXT.test(verdict.decision)) return "judged.decision is not 1 to 256 printable ASCII characters";
  }
  for (const key of ["asset", "payer", "signer"]) if (!isChecksummed(receipt[key])) return `${key} is not an ERC-55 address`;
  if (typeof receipt.network !== "string" || !NETWORK.test(receipt.network)) return "network is not eip155: and a chain id";
  if (!(isUint256(receipt.nonce) || (typeof receipt.nonce === "string" && HASH.test(receipt.nonce)))) return "nonce is not a decimal string below 2^256 or a lowercase 32-byte hex";
  const at = receipt.at;
  if (typeof at !== "string" || !AT.test(at) || new Date(at).toISOString() !== at) return "at is not a UTC time YYYY-MM-DDTHH:MM:SS.sssZ";
  if (typeof receipt.signature !== "string" || !SIGNATURE.test(receipt.signature)) return "signature is not 65 bytes of lowercase hex with v 27 or 28";
  if (BigInt(`0x${receipt.signature.slice(66, 130)}`) > N / 2n) return "signature s is above half the curve order";
  if (recover(digest(receiptHash(receipt)), receipt.signature) !== receipt.signer) return "the signature is not the signer's";
  return null;
}

export const dayOf = (receipt) => receipt.at.slice(0, 10);

// Day-list order. Hashes are lowercase hex of one length, so comparing them as strings compares them as integers.
function order(a, b) {
  if (a.at !== b.at) return a.at < b.at ? -1 : 1;
  const [x, y] = [receiptHash(a), receiptHash(b)];
  return x === y ? 0 : x < y ? -1 : 1;
}

const paymentOf = (r) => `${r.network} ${r.asset} ${r.payer} ${r.nonce}`;

function pair(a, b) {
  const [x, y] = a < b ? [a, b] : [b, a];
  return toHex(keccak256(concat(fromHex(x), fromHex(y))));
}

function tree(receipts) {
  const layers = [receipts.map(receiptHash)];
  while (layers.at(-1).length > 1) {
    const below = layers.at(-1), above = [];
    for (let i = 0; i < below.length; i += 2) above.push(i + 1 < below.length ? pair(below[i], below[i + 1]) : below[i]);
    layers.push(above);
  }
  return layers;
}

/** The root over the receipts in the order given; a day list gives them in day-list order. */
export const dayRoot = (receipts) => (receipts.length ? tree(receipts).at(-1)[0] : null);

/** `proof` lists siblings from the leaf up, in the form OpenZeppelin's MerkleProof.verify takes. */
export function proof(receipts, index) {
  if (!Number.isInteger(index) || index < 0 || index >= receipts.length) throw new RangeError(`no receipt at index ${index}: the list has ${receipts.length}`);
  const layers = tree(receipts), leaf = layers[0][index], siblings = [];
  for (const layer of layers.slice(0, -1)) {
    if (layer[index ^ 1] !== undefined) siblings.push(layer[index ^ 1]);
    index >>= 1;
  }
  return { leaf, proof: siblings, root: layers.at(-1)[0] };
}

/** The leaf is computed from the receipt, never taken as input (see the spec's rule on 64-byte input). */
export function verifyProof(receipt, siblings, root) {
  if (!isObject(receipt) || !Array.isArray(siblings) || typeof root !== "string" || !ANY_CASE_HASH.test(root) || !siblings.every((n) => typeof n === "string" && ANY_CASE_HASH.test(n))) return false;
  return siblings.reduce((node, sibling) => pair(node, sibling.toLowerCase()), receiptHash(receipt)) === root.toLowerCase();
}

/**
 * Reads a day file, one receipt per line in any order. Every non-blank line that is not a valid receipt of the day and
 * signer counts as unreadable. Without `day` and `signer`, those of the first valid receipt are used.
 */
export function readDay(text, day = null, signer = null) {
  const entries = [];
  for (const line of text.replace(/^\uFEFF/, "").split(/\r?\n/)) {
    if (!line.trim()) continue;
    try {
      const receipt = parseJson(line);
      entries.push(receiptProblem(receipt) === null ? receipt : null);
    } catch {
      entries.push(null);
    }
  }
  if (day === null && signer === null) {
    const first = entries.find(Boolean);
    if (first) [day, signer] = [dayOf(first), first.signer];
  }
  const receipts = entries.filter((r) => r && dayOf(r) === day && r.signer === signer);
  return { day, signer, receipts, unreadable: entries.length - receipts.length };
}

/** Sorts the receipts into day-list order and adds their count and root. */
export function dayList(day, signer, receipts, unreadable = 0, records) {
  const sorted = [...receipts].sort(order);
  return { day, signer, count: sorted.length, root: dayRoot(sorted), unreadable, ...(records ? { records } : {}), receipts: sorted };
}

/** Why these receipts, in this order, cannot be the signer's list for the day, or null. */
export function receiptsProblem(day, signer, receipts) {
  const payments = new Set();
  for (const [i, receipt] of receipts.entries()) {
    const why = receiptProblem(receipt);
    if (why) return `receipt ${i}: ${why}`;
    if (dayOf(receipt) !== day) return `receipt ${i} is of ${dayOf(receipt)}, not ${day}`;
    if (receipt.signer !== signer) return `receipt ${i} is signed by ${receipt.signer}, not ${signer}`;
    if (i > 0 && order(receipts[i - 1], receipt) >= 0) return `receipt ${i} is out of day-list order or repeats receipt ${i - 1}`;
    if (payments.has(paymentOf(receipt))) return `receipt ${i} repeats a payment already listed`;
    payments.add(paymentOf(receipt));
  }
  return null;
}

const LIST = ["day", "signer", "count", "root", "unreadable", "records", "receipts"];
const RECORDS = ["network", "contract", "publishers"];

function recordsMemberProblem(records) {
  if (!isObject(records) || Object.keys(records).length !== RECORDS.length || !RECORDS.every((key) => Object.hasOwn(records, key))) return "records must have exactly network, contract and publishers";
  if (typeof records.network !== "string" || !NETWORK.test(records.network)) return "records.network must be eip155: and a chain id";
  if (!isChecksummed(records.contract)) return "records.contract must be an ERC-55 address";
  if (!Array.isArray(records.publishers) || !records.publishers.length || !records.publishers.every(isChecksummed)) return "records.publishers must be a non-empty list of ERC-55 addresses";
  if (new Set(records.publishers).size !== records.publishers.length) return "records.publishers repeats an address";
  return null;
}

/** Why a day list is invalid, or null. */
export function listProblem(list) {
  if (!isObject(list)) return "not an object";
  const extra = Object.keys(list).filter((key) => !LIST.includes(key));
  if (extra.length) return `unknown members: ${extra.join(", ")}`;
  const missing = LIST.filter((key) => !Object.hasOwn(list, key));
  if (missing.length) return `missing members: ${missing.join(", ")}`;
  if (!isDay(list.day)) return "day must be a YYYY-MM-DD date";
  if (!isChecksummed(list.signer)) return "signer must be an ERC-55 address";
  if (!isWhole(list.count) || !isWhole(list.unreadable)) return "count and unreadable must be whole numbers";
  if (list.root !== null && (typeof list.root !== "string" || !HASH.test(list.root))) return "root must be lowercase hex or null";
  const records = recordsMemberProblem(list.records);
  if (records) return `${records}`;
  if (!Array.isArray(list.receipts)) return "receipts must be an array";
  const why = receiptsProblem(list.day, list.signer, list.receipts);
  if (why) return why;
  if (list.count !== list.receipts.length) return `count ${list.count} for ${list.receipts.length} receipts`;
  const root = dayRoot(list.receipts);
  if (list.root !== root) return `root ${list.root}, computed ${root}`;
  return null;
}

const ZERO = `0x${"0".repeat(64)}`;

/** Refuses a day with unreadable entries, which the spec forbids publishing. */
export function dayRecord(list) {
  if (list.unreadable !== 0) throw new Error(`${list.unreadable} unreadable entries: no record until they are resolved`);
  return { kind: "receipts", date: list.day, signer: list.signer, count: list.count, root: list.root ?? ZERO };
}

/** Why a day record is not well-formed, or null. Other members are allowed. */
export function recordProblem(record) {
  if (!isObject(record)) return "not well-formed: not an object";
  if (record.kind !== "receipts") return "not well-formed: kind must be receipts";
  if (!isDay(record.date)) return "not well-formed: date must be a YYYY-MM-DD date";
  if (!isChecksummed(record.signer)) return "not well-formed: signer must be an ERC-55 address";
  if (!isWhole(record.count)) return "not well-formed: count must be a whole number";
  if (typeof record.root !== "string" || !HASH.test(record.root)) return "not well-formed: root must be lowercase hex";
  return null;
}

/** Why a well-formed record does not state this day list, or null. */
export function recordListProblem(record, list) {
  const why = recordProblem(record);
  if (why) return why;
  if (record.date !== list.day) return `date ${record.date}, list ${list.day}`;
  if (record.signer !== list.signer) return `signer ${record.signer}, list ${list.signer}`;
  if (record.count !== list.count) return `count ${record.count}, list ${list.count}`;
  if (record.root !== (list.root ?? ZERO)) return `root ${record.root}, list ${list.root ?? ZERO}`;
  return null;
}

const INSCRIBED = toHex(keccak256(utf8("Inscribed(address,string,bytes)")));
const strictUtf8 = new TextDecoder("utf-8", { fatal: true });

/** The `kind` string and `data` bytes of an Inscribed log, ABI-decoded by hand; throws on anything malformed. */
function decodeInscribed(data) {
  const bytes = fromHex(data);
  const word = (at) => {
    if (at + 32 > bytes.length) throw new Error("data ends early");
    return Number(bigint(bytes.slice(at, at + 32)));
  };
  const dynamic = (head) => {
    const offset = word(head), length = word(offset);
    if (offset + 32 + length > bytes.length) throw new Error("data ends early");
    return bytes.slice(offset + 32, offset + 32 + length);
  };
  return { kind: strictUtf8.decode(dynamic(0)), data: strictUtf8.decode(dynamic(32)) };
}

const quantity = (hex) => Number(BigInt(hex));
const topicOf = (address) => `0x${address.slice(2).toLowerCase().padStart(64, "0")}`;

/**
 * Finds a day list's record on chain over JSON-RPC: the first log, by block number then log index, of the contract named
 * in `records`, sent by one of its publishers after the day closed, whose kind is "receipts" and whose data is a
 * well-formed record for the list's signer and day. Returns null when there is none yet.
 */
export async function findRecord(rpcUrl, list, { fetch: fetchImpl = fetch, chunk = 50_000 } = {}) {
  const why = listProblem(list);
  if (why) throw new Error(`the day list is invalid: ${why}`);
  let id = 0;
  const rpc = async (method, params) => {
    const response = await fetchImpl(rpcUrl, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ jsonrpc: "2.0", id: ++id, method, params }) });
    if (!response.ok) throw new Error(`${method}: HTTP ${response.status}`);
    const body = await response.json();
    if (body.error) throw new Error(`${method}: ${body.error.message ?? JSON.stringify(body.error)}`);
    return body.result;
  };
  const { network, contract, publishers } = list.records;
  const chainId = BigInt(await rpc("eth_chainId", []));
  if (`eip155:${chainId}` !== network) throw new Error(`the RPC serves eip155:${chainId}, the records are on ${network}`);

  const closed = Date.parse(`${list.day}T00:00:00.000Z`) / 1000 + 86_400;
  const timestamp = async (n) => quantity((await rpc("eth_getBlockByNumber", [`0x${n.toString(16)}`, false])).timestamp);
  const latest = quantity(await rpc("eth_blockNumber", []));
  if ((await timestamp(latest)) < closed) return null;
  let low = 0, high = latest;
  while (low < high) {
    const mid = Math.floor((low + high) / 2);
    if ((await timestamp(mid)) >= closed) high = mid;
    else low = mid + 1;
  }

  const senders = new Set(publishers.map(topicOf));
  for (let from = low; from <= latest; from += chunk) {
    const to = Math.min(from + chunk - 1, latest);
    const logs = await rpc("eth_getLogs", [{ address: contract, fromBlock: `0x${from.toString(16)}`, toBlock: `0x${to.toString(16)}`, topics: [INSCRIBED, [...senders]] }]);
    const ordered = logs
      .filter((log) => log.address.toLowerCase() === contract.toLowerCase() && log.topics[0] === INSCRIBED && senders.has(log.topics[1]?.toLowerCase()))
      .filter((log) => quantity(log.blockNumber) >= low)
      .sort((a, b) => quantity(a.blockNumber) - quantity(b.blockNumber) || quantity(a.logIndex) - quantity(b.logIndex));
    for (const log of ordered) {
      let inscribed, record;
      try {
        inscribed = decodeInscribed(log.data);
        record = parseJson(inscribed.data);
      } catch {
        continue;
      }
      if (inscribed.kind !== "receipts" || recordProblem(record) || record.date !== list.day || record.signer !== list.signer) continue;
      return { record, blockNumber: quantity(log.blockNumber), logIndex: quantity(log.logIndex), transactionHash: log.transactionHash, problem: recordListProblem(record, list) };
    }
  }
  return null;
}
