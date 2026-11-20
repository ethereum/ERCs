// SPDX-License-Identifier: CC0-1.0
// ERC-8281 reference verifier (erc8281/1).
//
// Implements the full verification invariant:
//   1. Recompute  — hash the supplied observation bytes with the declared hash_function
//   2. Compare    — H_prime == digest
//   3. Confirm inclusion — extraction rule (chain check, receipt fetch, log selection,
//      topic-count assertion, topic-0 assertion, address assertion, digest extraction)
//   4. Confirm committer — topics[2] == committer
//   5. Confirm block     — receipt.blockNumber == block_number
//   plus the optional block_hash assertion when the field is present.
//
// Dependency-free: SHA-256 via node:crypto; Keccak-256 and parameterized
// BLAKE2b-256 are implemented below so the verifier has no npm dependencies.
//
// Usage:
//   import { verify } from './verify.mjs';
//   const result = await verify(envelope, observationBytes, provider);
//   // provider: { eth_chainId(): Promise<hex string>,
//   //             eth_getTransactionReceipt(txHash): Promise<receipt|null> }
//   // result: { valid: true } | { valid: false, reason: string }

import { createHash } from 'node:crypto';

// ---------------------------------------------------------------------------
// Constants (ERC-8281)
// ---------------------------------------------------------------------------

export const TOPIC0 =
  '0xdca60c2087041cbb12d9a57628c6cad28ecbd0437e47c7ab6c3aa6e162bf4497'; // keccak256("Recorded(bytes32,address)")
export const ERC165_INTERFACE_ID = '0xb5c645bd'; // bytes4(keccak256("record(bytes32)"))
export const ENVELOPE_VERSION = 'erc8281/1';
export const ALLOWED_HASH_FUNCTIONS = ['sha2-256', 'keccak-256', 'blake2b-256'];

// ---------------------------------------------------------------------------
// Keccak-256 (original Keccak padding 0x01, rate 1088) — pure JS, BigInt lanes
// ---------------------------------------------------------------------------

const KECCAK_RC = [
  0x0000000000000001n, 0x0000000000008082n, 0x800000000000808an, 0x8000000080008000n,
  0x000000000000808bn, 0x0000000080000001n, 0x8000000080008081n, 0x8000000000008009n,
  0x000000000000008an, 0x0000000000000088n, 0x0000000080008009n, 0x000000008000000an,
  0x000000008000808bn, 0x800000000000008bn, 0x8000000000008089n, 0x8000000000008003n,
  0x8000000000008002n, 0x8000000000000080n, 0x000000000000800an, 0x800000008000000an,
  0x8000000080008081n, 0x8000000000008080n, 0x0000000080000001n, 0x8000000080008008n,
];
const KECCAK_ROT = [
  [0n, 36n, 3n, 41n, 18n],
  [1n, 44n, 10n, 45n, 2n],
  [62n, 6n, 43n, 15n, 61n],
  [28n, 55n, 25n, 21n, 56n],
  [27n, 20n, 39n, 8n, 14n],
];
const M64 = (1n << 64n) - 1n;
const rol64 = (x, n) => n === 0n ? x : (((x << n) | (x >> (64n - n))) & M64);

function keccakF(A) {
  for (let r = 0; r < 24; r++) {
    const C = [], D = [];
    for (let x = 0; x < 5; x++) C[x] = A[x][0] ^ A[x][1] ^ A[x][2] ^ A[x][3] ^ A[x][4];
    for (let x = 0; x < 5; x++) D[x] = C[(x + 4) % 5] ^ rol64(C[(x + 1) % 5], 1n);
    for (let x = 0; x < 5; x++) for (let y = 0; y < 5; y++) A[x][y] ^= D[x];
    const B = [[], [], [], [], []];
    for (let x = 0; x < 5; x++)
      for (let y = 0; y < 5; y++) B[y][(2 * x + 3 * y) % 5] = rol64(A[x][y], KECCAK_ROT[x][y]);
    for (let x = 0; x < 5; x++)
      for (let y = 0; y < 5; y++) A[x][y] = B[x][y] ^ ((~B[(x + 1) % 5][y] & M64) & B[(x + 2) % 5][y]);
    A[0][0] ^= KECCAK_RC[r];
  }
}

export function keccak256(bytes) {
  const rate = 136;
  const padLen = rate - (bytes.length % rate);
  const p = new Uint8Array(bytes.length + padLen);
  p.set(bytes);
  p[bytes.length] = 0x01;
  p[p.length - 1] |= 0x80;
  const A = Array.from({ length: 5 }, () => [0n, 0n, 0n, 0n, 0n]);
  for (let off = 0; off < p.length; off += rate) {
    for (let i = 0; i < rate / 8; i++) {
      let lane = 0n;
      for (let b = 7; b >= 0; b--) lane = (lane << 8n) | BigInt(p[off + i * 8 + b]);
      A[i % 5][(i / 5) | 0] ^= lane;
    }
    keccakF(A);
  }
  const out = new Uint8Array(32);
  for (let i = 0; i < 4; i++) {
    let lane = A[i % 5][(i / 5) | 0];
    for (let b = 0; b < 8; b++) { out[i * 8 + b] = Number(lane & 0xffn); lane >>= 8n; }
  }
  return out;
}

// ---------------------------------------------------------------------------
// BLAKE2b with parameterized digest length (RFC 7693) — pure JS, BigInt words
// blake2b256(m) is BLAKE2b initialized with digest_length = 32.
// NOTE: this is NOT a truncation of BLAKE2b-512; the digest length is part of
// the parameter block XORed into the IV, per the Hash Function Registry note.
// ---------------------------------------------------------------------------

const B2B_IV = [
  0x6a09e667f3bcc908n, 0xbb67ae8584caa73bn, 0x3c6ef372fe94f82bn, 0xa54ff53a5f1d36f1n,
  0x510e527fade682d1n, 0x9b05688c2b3e6c1fn, 0x1f83d9abfb41bd6bn, 0x5be0cd19137e2179n,
];
const B2B_SIGMA = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
  [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
  [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
  [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
  [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
  [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
  [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
  [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
  [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
  [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
  [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
];
const ror64 = (x, n) => ((x >> n) | (x << (64n - n))) & M64;

function b2bCompress(h, block, t, last) {
  const m = [];
  for (let i = 0; i < 16; i++) {
    let w = 0n;
    for (let b = 7; b >= 0; b--) w = (w << 8n) | BigInt(block[i * 8 + b]);
    m[i] = w;
  }
  const v = h.concat(B2B_IV.slice());
  v[12] ^= t & M64;
  v[13] ^= 0n; // t high — message sizes here never exceed 2^64
  if (last) v[14] ^= M64;
  const G = (a, b, c, d, x, y) => {
    v[a] = (v[a] + v[b] + x) & M64; v[d] = ror64(v[d] ^ v[a], 32n);
    v[c] = (v[c] + v[d]) & M64;     v[b] = ror64(v[b] ^ v[c], 24n);
    v[a] = (v[a] + v[b] + y) & M64; v[d] = ror64(v[d] ^ v[a], 16n);
    v[c] = (v[c] + v[d]) & M64;     v[b] = ror64(v[b] ^ v[c], 63n);
  };
  for (let r = 0; r < 12; r++) {
    const s = B2B_SIGMA[r];
    G(0, 4, 8, 12, m[s[0]], m[s[1]]);
    G(1, 5, 9, 13, m[s[2]], m[s[3]]);
    G(2, 6, 10, 14, m[s[4]], m[s[5]]);
    G(3, 7, 11, 15, m[s[6]], m[s[7]]);
    G(0, 5, 10, 15, m[s[8]], m[s[9]]);
    G(1, 6, 11, 12, m[s[10]], m[s[11]]);
    G(2, 7, 8, 13, m[s[12]], m[s[13]]);
    G(3, 4, 9, 14, m[s[14]], m[s[15]]);
  }
  for (let i = 0; i < 8; i++) h[i] ^= v[i] ^ v[i + 8];
}

export function blake2b256(bytes) {
  const outLen = 32;
  const h = B2B_IV.slice();
  h[0] ^= 0x01010000n ^ BigInt(outLen); // parameter block: digest_length=32, fanout=1, depth=1
  let t = 0n;
  let i = 0;
  // process all blocks except the last (final block is always compressed with last=true)
  while (bytes.length - i > 128) {
    t += 128n;
    b2bCompress(h, bytes.subarray(i, i + 128), t, false);
    i += 128;
  }
  const lastBlock = new Uint8Array(128);
  lastBlock.set(bytes.subarray(i));
  t += BigInt(bytes.length - i);
  b2bCompress(h, lastBlock, t, true);
  const out = new Uint8Array(outLen);
  for (let w = 0; w < 4; w++) {
    let word = h[w];
    for (let b = 0; b < 8; b++) { out[w * 8 + b] = Number(word & 0xffn); word >>= 8n; }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Hash dispatch (Hash Function Registry)
// ---------------------------------------------------------------------------

function computeDigest(hashFunction, bytes) {
  switch (hashFunction) {
    case 'sha2-256':    return new Uint8Array(createHash('sha256').update(bytes).digest());
    case 'keccak-256':  return keccak256(bytes);
    case 'blake2b-256': return blake2b256(bytes);
    default:            return null; // not in the allowed set
  }
}

// ---------------------------------------------------------------------------
// Encoding helpers and field normalization (Proof Envelope Schema)
// ---------------------------------------------------------------------------

const toHex = (bytes) => '0x' + Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
const isHex32 = (s) => typeof s === 'string' && /^0x[0-9a-f]{64}$/.test(s);
const isDecimal = (s) => typeof s === 'string' && /^(0|[1-9][0-9]*)$/.test(s);
const isAddressShape = (s) => typeof s === 'string' && /^0x[0-9a-fA-F]{40}$/.test(s);
const bytesEq = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
const hexToBytes = (s) => Uint8Array.from(s.slice(2).match(/.{2}/g) ?? [], (h) => parseInt(h, 16));

// EIP-55 checksum: uppercase hex letter where keccak256(lowercase-ascii-address)
// nibble >= 8, lowercase otherwise. Verifiers MUST reject failing addresses.
export function isValidEip55(address) {
  if (!isAddressShape(address)) return false;
  const lower = address.slice(2).toLowerCase();
  const hash = toHex(keccak256(new TextEncoder().encode(lower))).slice(2);
  for (let i = 0; i < 40; i++) {
    const c = address[2 + i];
    if (!/[a-fA-F]/.test(c)) continue;
    const upper = parseInt(hash[i], 16) >= 8;
    if (upper !== (c === c.toUpperCase())) return false;
  }
  return true;
}

const addressBytes = (address) => hexToBytes('0x' + address.slice(2).toLowerCase());
// JSON-RPC quantities are 0x-prefixed hex; envelope integers are decimal strings.
const quantityToBigInt = (q) => BigInt(q);
const decimalToBigInt = (d) => BigInt(d);

// ---------------------------------------------------------------------------
// Envelope schema validation (returns null if OK, else rejection reason)
// ---------------------------------------------------------------------------

function validateEnvelope(env) {
  if (typeof env !== 'object' || env === null) return 'envelope_not_object';
  // Unknown additional fields MUST be ignored — so we only validate known fields.
  if (env.version !== ENVELOPE_VERSION) return 'version_not_supported'; // exact, case-sensitive match
  if (!isHex32(env.digest)) return 'digest_format_invalid';
  if (!ALLOWED_HASH_FUNCTIONS.includes(env.hash_function)) return 'hash_function_not_allowed';
  if (!isDecimal(env.chain_id)) return 'chain_id_format_invalid';
  if (!isAddressShape(env.contract)) return 'contract_format_invalid';
  if (!isValidEip55(env.contract)) return 'eip55_checksum_invalid';
  if (!isHex32(env.tx_hash)) return 'tx_hash_format_invalid';
  if (!isDecimal(env.block_number)) return 'block_number_format_invalid';
  if (!isDecimal(env.receipt_log_position)) return 'log_position_format_invalid';
  if (!isAddressShape(env.committer)) return 'committer_format_invalid';
  if (!isValidEip55(env.committer)) return 'eip55_checksum_invalid';
  if (env.block_hash !== undefined && !isHex32(env.block_hash)) return 'block_hash_format_invalid';
  return null;
}

// ---------------------------------------------------------------------------
// Verification invariant
// ---------------------------------------------------------------------------

export async function verify(envelope, observationBytes, provider) {
  const reject = (reason) => ({ valid: false, reason });

  // Envelope schema + normalization rules (includes registry and version checks)
  const schemaError = validateEnvelope(envelope);
  if (schemaError) return reject(schemaError);

  // Step 1 — Recompute
  const hPrime = computeDigest(envelope.hash_function, observationBytes);
  if (hPrime === null) return reject('hash_function_not_allowed');

  // Step 2 — Compare (decoded bytes comparison)
  if (!bytesEq(hPrime, hexToBytes(envelope.digest))) return reject('digest_mismatch');

  // Step 3 — Confirm inclusion (extraction rule)
  // 3.1 The endpoint MUST serve the declared chain (decoded integer comparison).
  const endpointChainId = quantityToBigInt(await provider.eth_chainId());
  if (endpointChainId !== decimalToBigInt(envelope.chain_id)) return reject('chain_id_mismatch');

  // 3.2 Fetch the receipt; it MUST exist and MUST have status == 1.
  const receipt = await provider.eth_getTransactionReceipt(envelope.tx_hash);
  if (!receipt) return reject('receipt_not_found');
  if (quantityToBigInt(receipt.status) !== 1n) return reject('receipt_reverted');

  // 3.3 Select the log by ARRAY POSITION within receipt.logs (zero-indexed).
  // NOT the JSON-RPC logIndex field, which is block-scoped.
  const position = Number(decimalToBigInt(envelope.receipt_log_position));
  const log = receipt.logs[position];
  if (log === undefined) return reject('log_position_out_of_range');

  // 3.4 The selected log's address MUST match `contract` (decoded 20-byte comparison).
  if (!bytesEq(addressBytes(log.address), addressBytes(envelope.contract)))
    return reject('contract_mismatch');

  // 3.5 The log MUST contain exactly three topics, and topics[0] MUST be the
  // canonical topic-0. A log with fewer or more topics MUST be rejected even
  // if topics[0] matches. The data field is not used and is ignored.
  if (!Array.isArray(log.topics) || log.topics.length !== 3) return reject('topic_count_invalid');
  if (!bytesEq(hexToBytes(log.topics[0].toLowerCase()), hexToBytes(TOPIC0)))
    return reject('topic0_mismatch');

  // 3.6 topics[1] contains the digest verbatim (indexed fixed-size parameter).
  const onChainDigest = hexToBytes(log.topics[1].toLowerCase());
  if (!bytesEq(onChainDigest, hexToBytes(envelope.digest))) return reject('onchain_digest_mismatch');

  // Step 4 — Confirm committer: topics[2] is the address, right-aligned in 32 bytes.
  const onChainCommitter = hexToBytes(log.topics[2].toLowerCase()).slice(12);
  if (!bytesEq(onChainCommitter, addressBytes(envelope.committer))) return reject('committer_mismatch');

  // Step 5 — Confirm block (integer comparison).
  if (quantityToBigInt(receipt.blockNumber) !== decimalToBigInt(envelope.block_number))
    return reject('block_number_mismatch');

  // Optional block_hash — when present, MUST equal the receipt's blockHash.
  if (envelope.block_hash !== undefined) {
    if (!bytesEq(hexToBytes(receipt.blockHash.toLowerCase()), hexToBytes(envelope.block_hash)))
      return reject('block_hash_mismatch');
  }

  return { valid: true };
}

// ---------------------------------------------------------------------------
// Convenience: provider backed by a JSON-RPC HTTP endpoint
// ---------------------------------------------------------------------------

export function httpProvider(rpcUrl) {
  let id = 0;
  const call = async (method, params) => {
    const res = await fetch(rpcUrl, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', id: ++id, method, params }),
    });
    const body = await res.json();
    if (body.error) throw new Error(`${method}: ${body.error.message}`);
    return body.result;
  };
  return {
    eth_chainId: () => call('eth_chainId', []),
    eth_getTransactionReceipt: (txHash) => call('eth_getTransactionReceipt', [txHash]),
  };
}
