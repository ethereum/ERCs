// ERC-8512 reference off-chain library (Node 20+, zero external dependencies).
// SPDX-License-Identifier: CC0-1.0

import { createHmac } from 'node:crypto';

const utf8Encoder = new TextEncoder();

export const ZERO_BYTES32 = '0x' + '00'.repeat(32);
export const MAX_UINT64 = (1n << 64n) - 1n;
export const MAX_UINT256 = (1n << 256n) - 1n;

export const STATEMENT_KIND = 'ERC8512/statement/1';
export const EIP712_NAME = 'GPU Collateral Evidence';
export const EIP712_VERSION = '1';

export const ROLES = new Set(['servicer', 'lessee', 'lender', 'third-party']);
export const METHODS = new Set(['hw-attestation', 'bmc-telemetry', 'workload-meter', 'site-inspection']);
export const INSTANT_METHODS = new Set(['hw-attestation', 'site-inspection']);

export const STATEMENT_KEYS = [
  'kind',
  'registry',
  'servicer',
  'collateralId',
  'deviceKey',
  'pciDeviceId',
  'location',
  'periodStart',
  'periodEnd',
  'observer',
  'role',
  'method',
  'checksPassed',
  'checksFailed',
  'servedSeconds',
  'missedSeconds',
  'unknownSeconds',
  'evidence',
];
const STATEMENT_KEY_SET = new Set(STATEMENT_KEYS);
const EVIDENCE_KEY_SET = new Set(['type', 'uri', 'hash']);

const INT_RE = /^(?:0|[1-9][0-9]*)$/;
const BYTES32_RE = /^0x[0-9a-f]{64}$/;
const ADDRESS_RE = /^0x[0-9a-f]{40}$/;
const PCI_DEVICE_RE = /^[0-9a-f]{4}$/;
const LOCATION_RE = /^[A-Z]{2}$/;
const SIG_RE = /^0x[0-9a-f]{130}$/;

// ---------------------------------------------------------------------------
// Byte & hex utilities
// ---------------------------------------------------------------------------

export function utf8ToBytes(str) {
  return utf8Encoder.encode(str);
}

export function hexToBytes(hex) {
  if (typeof hex !== 'string' || !hex.startsWith('0x')) {
    throw new Error(`Expected 0x-prefixed hex string, got: ${String(hex)}`);
  }
  const body = hex.slice(2);
  if (body.length % 2 !== 0 || !/^[0-9a-fA-F]*$/.test(body)) {
    throw new Error(`Invalid hex string: ${hex}`);
  }
  const out = new Uint8Array(body.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(body.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

export function bytesToHex(bytes) {
  let out = '0x';
  for (let i = 0; i < bytes.length; i++) {
    out += bytes[i].toString(16).padStart(2, '0');
  }
  return out;
}

export function concatBytes(...arrays) {
  let total = 0;
  for (const a of arrays) total += a.length;
  const out = new Uint8Array(total);
  let offset = 0;
  for (const a of arrays) {
    out.set(a, offset);
    offset += a.length;
  }
  return out;
}

export function bigIntToBytes32(n) {
  if (n < 0n || n > MAX_UINT256) {
    throw new RangeError('Value out of uint256 range');
  }
  const out = new Uint8Array(32);
  let x = n;
  for (let i = 31; i >= 0; i--) {
    out[i] = Number(x & 0xffn);
    x >>= 8n;
  }
  return out;
}

export function bytesToBigInt(bytes) {
  let out = 0n;
  for (let i = 0; i < bytes.length; i++) {
    out = (out << 8n) | BigInt(bytes[i]);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Keccak-256 (BigInt, original Keccak 0x01 padding)
// ---------------------------------------------------------------------------

const MASK64 = 0xffffffffffffffffn;

const KECCAK_RC = [
  0x0000000000000001n, 0x0000000000008082n, 0x800000000000808an, 0x8000000080008000n,
  0x000000000000808bn, 0x0000000080000001n, 0x8000000080008081n, 0x8000000000008009n,
  0x000000000000008an, 0x0000000000000088n, 0x0000000080008009n, 0x000000008000000an,
  0x000000008000808bn, 0x800000000000008bn, 0x8000000000008089n, 0x8000000000008003n,
  0x8000000000008002n, 0x8000000000000080n, 0x000000000000800an, 0x800000008000000an,
  0x8000000080008081n, 0x8000000000008080n, 0x0000000080000001n, 0x8000000080008008n,
];

const KECCAK_ROTC = [
  1n, 3n, 6n, 10n, 15n, 21n, 28n, 36n, 45n, 55n, 2n, 14n,
  27n, 41n, 56n, 8n, 25n, 43n, 62n, 18n, 39n, 61n, 20n, 44n,
];

const KECCAK_PILN = [
  10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4,
  15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1,
];

function rotl64(x, n) {
  return ((x << n) | (x >> (64n - n))) & MASK64;
}

function keccakF1600(st) {
  const bc = new Array(5);
  for (let round = 0; round < 24; round++) {
    // Theta
    for (let i = 0; i < 5; i++) {
      bc[i] = st[i] ^ st[i + 5] ^ st[i + 10] ^ st[i + 15] ^ st[i + 20];
    }
    for (let i = 0; i < 5; i++) {
      const t = bc[(i + 4) % 5] ^ rotl64(bc[(i + 1) % 5], 1n);
      for (let j = 0; j < 25; j += 5) {
        st[j + i] ^= t;
      }
    }
    // Rho and Pi
    let t = st[1];
    for (let i = 0; i < 24; i++) {
      const j = KECCAK_PILN[i];
      bc[0] = st[j];
      st[j] = rotl64(t, KECCAK_ROTC[i]);
      t = bc[0];
    }
    // Chi
    for (let j = 0; j < 25; j += 5) {
      for (let i = 0; i < 5; i++) bc[i] = st[j + i];
      for (let i = 0; i < 5; i++) {
        st[j + i] ^= (~bc[(i + 1) % 5] & MASK64) & bc[(i + 2) % 5];
      }
    }
    // Iota
    st[0] ^= KECCAK_RC[round];
  }
}

export function keccak256Bytes(input) {
  const data = typeof input === 'string' ? utf8ToBytes(input) : input;
  if (!(data instanceof Uint8Array)) {
    throw new TypeError('keccak256 expects a Uint8Array or string');
  }
  const rate = 136; // 1088 bits
  const state = new Array(25).fill(0n);

  const absorbBlock = (block) => {
    for (let i = 0; i < rate; i += 8) {
      const lane =
        BigInt(block[i]) |
        (BigInt(block[i + 1]) << 8n) |
        (BigInt(block[i + 2]) << 16n) |
        (BigInt(block[i + 3]) << 24n) |
        (BigInt(block[i + 4]) << 32n) |
        (BigInt(block[i + 5]) << 40n) |
        (BigInt(block[i + 6]) << 48n) |
        (BigInt(block[i + 7]) << 56n);
      state[i >> 3] ^= lane;
    }
    keccakF1600(state);
  };

  let offset = 0;
  while (offset + rate <= data.length) {
    absorbBlock(data.subarray(offset, offset + rate));
    offset += rate;
  }

  const last = new Uint8Array(rate);
  const rem = data.length - offset;
  last.set(data.subarray(offset), 0);
  last[rem] ^= 0x01;
  last[rate - 1] ^= 0x80;
  absorbBlock(last);

  const out = new Uint8Array(32);
  for (let i = 0; i < 4; i++) {
    let lane = state[i];
    for (let b = 0; b < 8; b++) {
      out[i * 8 + b] = Number(lane & 0xffn);
      lane >>= 8n;
    }
  }
  return out;
}

export function keccak256(input) {
  return bytesToHex(keccak256Bytes(input));
}

// ---------------------------------------------------------------------------
// secp256k1 (BigInt Jacobian arithmetic, RFC 6979 low-s signing, recovery)
// ---------------------------------------------------------------------------

const SECP_P = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2fn;
const SECP_N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;
const SECP_HALF_N = SECP_N >> 1n;
const SECP_GX = 0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798n;
const SECP_GY = 0x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8n;
const SECP_SQRT_EXP = (SECP_P + 1n) >> 2n;

function mod(a, m) {
  const r = a % m;
  return r >= 0n ? r : r + m;
}

function modInv(a, m) {
  let t = 0n;
  let newT = 1n;
  let r = m;
  let newR = mod(a, m);
  while (newR !== 0n) {
    const q = r / newR;
    [t, newT] = [newT, t - q * newT];
    [r, newR] = [newR, r - q * newR];
  }
  if (r !== 1n) throw new Error('Value is not invertible');
  return t < 0n ? t + m : t;
}

function modPow(base, exp, m) {
  let result = 1n;
  let b = mod(base, m);
  let e = exp;
  while (e > 0n) {
    if (e & 1n) result = (result * b) % m;
    b = (b * b) % m;
    e >>= 1n;
  }
  return result;
}

// Point at infinity is { X: 0n, Y: 1n, Z: 0n }
const JAC_INF = { X: 0n, Y: 1n, Z: 0n };
const JAC_G = { X: SECP_GX, Y: SECP_GY, Z: 1n };

function jacDouble(p) {
  if (p.Z === 0n || p.Y === 0n) return JAC_INF;
  const { X, Y, Z } = p;
  const A = (X * X) % SECP_P;
  const B = (Y * Y) % SECP_P;
  const C = (B * B) % SECP_P;
  const D = (2n * ((((X + B) * (X + B)) % SECP_P) - A - C)) % SECP_P;
  const E = (3n * A) % SECP_P;
  const F = (E * E) % SECP_P;
  const X3 = mod(F - 2n * D, SECP_P);
  const Y3 = mod(E * (D - X3) - 8n * C, SECP_P);
  const Z3 = mod(2n * Y * Z, SECP_P);
  return { X: X3, Y: Y3, Z: Z3 };
}

function jacAdd(p, q) {
  if (p.Z === 0n) return q;
  if (q.Z === 0n) return p;
  const Z1Z1 = (p.Z * p.Z) % SECP_P;
  const Z2Z2 = (q.Z * q.Z) % SECP_P;
  const U1 = (p.X * Z2Z2) % SECP_P;
  const U2 = (q.X * Z1Z1) % SECP_P;
  const S1 = (p.Y * q.Z % SECP_P) * Z2Z2 % SECP_P;
  const S2 = (q.Y * p.Z % SECP_P) * Z1Z1 % SECP_P;
  const H = mod(U2 - U1, SECP_P);
  const r = mod(S2 - S1, SECP_P);
  if (H === 0n) {
    if (r === 0n) return jacDouble(p);
    return JAC_INF;
  }
  const HH = (H * H) % SECP_P;
  const HHH = (H * HH) % SECP_P;
  const V = (U1 * HH) % SECP_P;
  const X3 = mod(r * r - HHH - 2n * V, SECP_P);
  const Y3 = mod(r * (V - X3) - S1 * HHH, SECP_P);
  const Z3 = mod(p.Z * q.Z % SECP_P * H, SECP_P);
  return { X: X3, Y: Y3, Z: Z3 };
}

function jacMul(k, p) {
  let n = mod(k, SECP_N);
  if (n === 0n || p.Z === 0n) return JAC_INF;
  let acc = JAC_INF;
  let addend = p;
  while (n > 0n) {
    if (n & 1n) acc = jacAdd(acc, addend);
    addend = jacDouble(addend);
    n >>= 1n;
  }
  return acc;
}

function jacToAffine(p) {
  if (p.Z === 0n) return null;
  const zInv = modInv(p.Z, SECP_P);
  const zInv2 = (zInv * zInv) % SECP_P;
  const zInv3 = (zInv2 * zInv) % SECP_P;
  return {
    x: (p.X * zInv2) % SECP_P,
    y: (p.Y * zInv3) % SECP_P,
  };
}

function parsePrivateKey(privKey) {
  let d;
  if (typeof privKey === 'bigint') {
    d = privKey;
  } else if (typeof privKey === 'string') {
    if (!BYTES32_RE.test(privKey.toLowerCase())) {
      throw new Error('Private key must be 32-byte 0x hex string or BigInt');
    }
    d = BigInt(privKey);
  } else if (privKey instanceof Uint8Array && privKey.length === 32) {
    d = bytesToBigInt(privKey);
  } else {
    throw new TypeError('Invalid private key type');
  }
  if (d < 1n || d >= SECP_N) {
    throw new RangeError('Private key out of secp256k1 scalar range');
  }
  return d;
}

export function privateKeyToPublicKey(privKey) {
  const d = parsePrivateKey(privKey);
  const pt = jacToAffine(jacMul(d, JAC_G));
  return concatBytes(bigIntToBytes32(pt.x), bigIntToBytes32(pt.y));
}

export function publicKeyToAddress(pubKeyBytes) {
  let raw = pubKeyBytes;
  if (raw instanceof Uint8Array && raw.length === 65 && raw[0] === 0x04) {
    raw = raw.subarray(1);
  }
  if (!(raw instanceof Uint8Array) || raw.length !== 64) {
    throw new Error('Public key must be 64 uncompressed bytes (or 65 bytes prefixed with 0x04)');
  }
  const hash = keccak256Bytes(raw);
  return bytesToHex(hash.subarray(12));
}

export function privateKeyToAddress(privKey) {
  return publicKeyToAddress(privateKeyToPublicKey(privKey));
}

function hmacSha256(key, ...parts) {
  const hmac = createHmac('sha256', key);
  for (const part of parts) hmac.update(part);
  return new Uint8Array(hmac.digest());
}

/**
 * Deterministic RFC 6979 secp256k1 signing (HMAC-SHA256) with low-s normalization.
 * Returns 65-byte r || s || v (v in {27, 28}) as 0x-prefixed lowercase hex.
 */
export function signDigest(digestHex, privKey) {
  if (!BYTES32_RE.test(digestHex)) {
    throw new Error(`Invalid bytes32 digest: ${digestHex}`);
  }
  const d = parsePrivateKey(privKey);
  const h1 = hexToBytes(digestHex);
  const z = bytesToBigInt(h1);
  const xOctets = bigIntToBytes32(d);
  const h1Octets = bigIntToBytes32(z % SECP_N);
  const bx = concatBytes(xOctets, h1Octets);

  let V = new Uint8Array(32).fill(0x01);
  let K = new Uint8Array(32).fill(0x00);

  K = hmacSha256(K, V, Uint8Array.of(0x00), bx);
  V = hmacSha256(K, V);
  K = hmacSha256(K, V, Uint8Array.of(0x01), bx);
  V = hmacSha256(K, V);

  while (true) {
    V = hmacSha256(K, V);
    const k = bytesToBigInt(V);
    if (k >= 1n && k < SECP_N) {
      const R = jacToAffine(jacMul(k, JAC_G));
      if (R !== null) {
        const r = R.x % SECP_N;
        if (r !== 0n) {
          let s = (modInv(k, SECP_N) * mod(z + r * d, SECP_N)) % SECP_N;
          if (s !== 0n) {
            let recId = Number(R.y & 1n) | (R.x >= SECP_N ? 2 : 0);
            if (s > SECP_HALF_N) {
              s = SECP_N - s;
              recId ^= 1;
            }
            if (recId === 0 || recId === 1) {
              const v = 27 + recId;
              return bytesToHex(concatBytes(bigIntToBytes32(r), bigIntToBytes32(s), Uint8Array.of(v)));
            }
          }
        }
      }
    }
    K = hmacSha256(K, V, Uint8Array.of(0x00));
    V = hmacSha256(K, V);
  }
}

/**
 * Recover 64-byte uncompressed secp256k1 public key from digest and 65-byte r||s||v signature.
 * Enforces v in {27, 28} and low-s (1 <= s <= N/2).
 */
export function recoverPublicKey(digestHex, sigHex) {
  if (!BYTES32_RE.test(digestHex)) {
    throw new Error('Invalid bytes32 digest');
  }
  if (typeof sigHex !== 'string' || !SIG_RE.test(sigHex)) {
    throw new Error('Signature must be 65 lowercase hex bytes (0x + 130 hex chars)');
  }
  const sig = hexToBytes(sigHex);
  const r = bytesToBigInt(sig.subarray(0, 32));
  const s = bytesToBigInt(sig.subarray(32, 64));
  const v = sig[64];

  if (v !== 27 && v !== 28) {
    throw new Error('Signature v must be 27 or 28');
  }
  if (r < 1n || r >= SECP_N) {
    throw new Error('Signature r out of range');
  }
  if (s < 1n || s > SECP_HALF_N) {
    throw new Error('Signature s out of low-s range');
  }

  const x = r;
  if (x >= SECP_P) {
    throw new Error('Recovered point x out of field range');
  }
  const y2 = mod(modPow(x, 3n, SECP_P) + 7n, SECP_P);
  let y = modPow(y2, SECP_SQRT_EXP, SECP_P);
  if ((y * y) % SECP_P !== y2) {
    throw new Error('No curve point for signature r');
  }
  const recId = v - 27;
  if (Number(y & 1n) !== recId) {
    y = SECP_P - y;
  }

  const R = { X: x, Y: y, Z: 1n };
  const z = bytesToBigInt(hexToBytes(digestHex));
  const rInv = modInv(r, SECP_N);
  const u1 = mod(-(z % SECP_N) * rInv, SECP_N);
  const u2 = (s * rInv) % SECP_N;

  const Q = jacToAffine(jacAdd(jacMul(u1, JAC_G), jacMul(u2, R)));
  if (Q === null) {
    throw new Error('Recovered point is at infinity');
  }
  return concatBytes(bigIntToBytes32(Q.x), bigIntToBytes32(Q.y));
}

export function recoverAddress(digestHex, sigHex) {
  return publicKeyToAddress(recoverPublicKey(digestHex, sigHex));
}

// ---------------------------------------------------------------------------
// Strict JSON parser rejecting duplicate member names (RFC 8259)
// ---------------------------------------------------------------------------

export function parseJson(text) {
  if (typeof text !== 'string') {
    throw new TypeError('parseJson expects a string');
  }
  let pos = 0;
  const len = text.length;

  const skipWs = () => {
    while (pos < len) {
      const c = text.charCodeAt(pos);
      if (c === 0x20 || c === 0x09 || c === 0x0a || c === 0x0d) pos++;
      else break;
    }
  };

  const fail = (msg) => {
    throw new SyntaxError(`${msg} at position ${pos}`);
  };

  const parseString = () => {
    if (text.charCodeAt(pos) !== 0x22) fail('Expected string');
    pos++;
    let out = '';
    while (pos < len) {
      const ch = text.charCodeAt(pos);
      if (ch === 0x22) {
        pos++;
        return out;
      }
      if (ch < 0x20) {
        fail('Unescaped control character in string');
      }
      if (ch === 0x5c) {
        pos++;
        if (pos >= len) fail('Unterminated escape sequence');
        const esc = text.charCodeAt(pos++);
        switch (esc) {
          case 0x22: out += '"'; break;
          case 0x5c: out += '\\'; break;
          case 0x2f: out += '/'; break;
          case 0x62: out += '\b'; break;
          case 0x66: out += '\f'; break;
          case 0x6e: out += '\n'; break;
          case 0x72: out += '\r'; break;
          case 0x74: out += '\t'; break;
          case 0x75: {
            const hex = text.slice(pos, pos + 4);
            if (!/^[0-9a-fA-F]{4}$/.test(hex)) fail('Invalid unicode escape');
            pos += 4;
            out += String.fromCharCode(parseInt(hex, 16));
            break;
          }
          default:
            fail('Invalid escape character');
        }
      } else {
        out += text[pos++];
      }
    }
    fail('Unterminated string');
  };

  const parseNumber = () => {
    const start = pos;
    if (text[pos] === '-') pos++;
    if (pos >= len) fail('Invalid number');
    if (text[pos] === '0') {
      pos++;
    } else if (text[pos] >= '1' && text[pos] <= '9') {
      while (pos < len && text[pos] >= '0' && text[pos] <= '9') pos++;
    } else {
      fail('Invalid number');
    }
    if (text[pos] === '.') {
      pos++;
      if (pos >= len || text[pos] < '0' || text[pos] > '9') fail('Invalid fractional number');
      while (pos < len && text[pos] >= '0' && text[pos] <= '9') pos++;
    }
    if (text[pos] === 'e' || text[pos] === 'E') {
      pos++;
      if (text[pos] === '+' || text[pos] === '-') pos++;
      if (pos >= len || text[pos] < '0' || text[pos] > '9') fail('Invalid exponent');
      while (pos < len && text[pos] >= '0' && text[pos] <= '9') pos++;
    }
    return Number(text.slice(start, pos));
  };

  const parseArray = () => {
    pos++; // '['
    skipWs();
    const arr = [];
    if (text[pos] === ']') {
      pos++;
      return arr;
    }
    while (true) {
      arr.push(parseValue());
      skipWs();
      if (text[pos] === ',') {
        pos++;
        skipWs();
      } else if (text[pos] === ']') {
        pos++;
        return arr;
      } else {
        fail('Expected "," or "]" in array');
      }
    }
  };

  const parseObject = () => {
    pos++; // '{'
    skipWs();
    const obj = {};
    const seen = new Set();
    if (text[pos] === '}') {
      pos++;
      return obj;
    }
    while (true) {
      skipWs();
      if (text[pos] !== '"') fail('Expected member name string');
      const key = parseString();
      if (seen.has(key)) {
        throw new SyntaxError(`Duplicate member name: "${key}"`);
      }
      seen.add(key);
      skipWs();
      if (text[pos] !== ':') fail('Expected ":" after member name');
      pos++;
      const val = parseValue();
      Object.defineProperty(obj, key, {
        value: val,
        enumerable: true,
        writable: true,
        configurable: true,
      });
      skipWs();
      if (text[pos] === ',') {
        pos++;
        skipWs();
      } else if (text[pos] === '}') {
        pos++;
        return obj;
      } else {
        fail('Expected "," or "}" in object');
      }
    }
  };

  const parseValue = () => {
    skipWs();
    if (pos >= len) fail('Unexpected end of JSON input');
    const ch = text[pos];
    if (ch === '{') return parseObject();
    if (ch === '[') return parseArray();
    if (ch === '"') return parseString();
    if (ch === '-' || (ch >= '0' && ch <= '9')) return parseNumber();
    if (text.startsWith('true', pos)) { pos += 4; return true; }
    if (text.startsWith('false', pos)) { pos += 5; return false; }
    if (text.startsWith('null', pos)) { pos += 4; return null; }
    fail(`Unexpected token "${ch}"`);
  };

  const value = parseValue();
  skipWs();
  if (pos !== len) fail('Unexpected trailing content');
  return value;
}

// ---------------------------------------------------------------------------
// RFC 8785 (JCS) Canonical JSON serialization
// ---------------------------------------------------------------------------

function canonicalizeString(str) {
  let out = '"';
  for (let i = 0; i < str.length; i++) {
    const code = str.charCodeAt(i);
    // Reject lone UTF-16 surrogates (not valid UTF-8)
    if (code >= 0xd800 && code <= 0xdbff) {
      const next = str.charCodeAt(i + 1);
      if (!(next >= 0xdc00 && next <= 0xdfff)) {
        throw new Error('Lone high surrogate in string');
      }
      out += str[i] + str[i + 1];
      i++;
      continue;
    }
    if (code >= 0xdc00 && code <= 0xdfff) {
      throw new Error('Lone low surrogate in string');
    }
    if (code === 0x22) out += '\\"';
    else if (code === 0x5c) out += '\\\\';
    else if (code === 0x08) out += '\\b';
    else if (code === 0x09) out += '\\t';
    else if (code === 0x0a) out += '\\n';
    else if (code === 0x0c) out += '\\f';
    else if (code === 0x0d) out += '\\r';
    else if (code < 0x20) out += '\\u' + code.toString(16).padStart(4, '0');
    else out += str[i];
  }
  return out + '"';
}

export function canonicalizeJson(value) {
  if (value === null) return 'null';
  const t = typeof value;
  if (t === 'string') return canonicalizeString(value);
  if (t === 'boolean') return value ? 'true' : 'false';
  if (t === 'number') {
    if (!Number.isFinite(value)) throw new TypeError('Non-finite numbers are not valid JSON');
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return '[' + value.map((item) => canonicalizeJson(item)).join(',') + ']';
  }
  if (t === 'object') {
    // RFC 8785 Section 3.2.3: sort property names by UTF-16 code units.
    const keys = Object.keys(value).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
    const parts = [];
    for (const k of keys) {
      const v = value[k];
      if (v === undefined) continue;
      parts.push(`${canonicalizeString(k)}:${canonicalizeJson(v)}`);
    }
    return '{' + parts.join(',') + '}';
  }
  throw new TypeError(`Unsupported JSON value type: ${t}`);
}

// ---------------------------------------------------------------------------
// ERC-8512 device keys, EIP-712, Merkle root
// ---------------------------------------------------------------------------

const DEVICE_PREFIX = utf8ToBytes('ERC8512.device');

const EIP712_DOMAIN_TYPEHASH = keccak256Bytes(
  'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
);
const STATEMENT_TYPEHASH = keccak256Bytes('Statement(bytes32 statementId)');
const NAME_HASH = keccak256Bytes(EIP712_NAME);
const VERSION_HASH = keccak256Bytes(EIP712_VERSION);

export function deviceKey(pciVendorId, idType, idBytes) {
  if (!Number.isInteger(pciVendorId) || pciVendorId < 0 || pciVendorId > 0xffff) {
    throw new RangeError('pciVendorId must be a uint16 integer');
  }
  if (!Number.isInteger(idType) || idType < 0 || idType > 0xff) {
    throw new RangeError('idType must be a uint8 integer');
  }
  if (!(idBytes instanceof Uint8Array)) {
    throw new TypeError('idBytes must be a Uint8Array');
  }
  const header = Uint8Array.of((pciVendorId >> 8) & 0xff, pciVendorId & 0xff, idType);
  return keccak256(concatBytes(DEVICE_PREFIX, header, idBytes));
}

export function parseAccount(account) {
  if (typeof account !== 'string') return null;
  const parts = account.split(':');
  if (parts.length !== 3 || parts[0] !== 'eip155') return null;
  const [, chainIdStr, address] = parts;
  if (!INT_RE.test(chainIdStr)) return null;
  const chainId = BigInt(chainIdStr);
  if (chainId > MAX_UINT256) return null;
  if (!ADDRESS_RE.test(address)) return null;
  return { chainId, chainIdStr, address };
}

export function formatAccount(chainId, address) {
  const cid = BigInt(chainId);
  if (cid < 0n || cid > MAX_UINT256) throw new RangeError('chainId out of uint256 range');
  const addr = address.toLowerCase();
  if (!ADDRESS_RE.test(addr)) throw new Error(`Invalid address: ${address}`);
  return `eip155:${cid.toString()}:${addr}`;
}

export function statementId(statement) {
  return keccak256(utf8ToBytes(canonicalizeJson(statement)));
}

export function domainSeparator(chainId, verifyingContract) {
  const cid = BigInt(chainId);
  if (cid < 0n || cid > MAX_UINT256) throw new RangeError('chainId out of uint256 range');
  const addr = verifyingContract.toLowerCase();
  if (!ADDRESS_RE.test(addr)) throw new Error(`Invalid verifyingContract: ${verifyingContract}`);
  const addrWord = concatBytes(new Uint8Array(12), hexToBytes(addr));
  return keccak256(
    concatBytes(EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, bigIntToBytes32(cid), addrWord)
  );
}

export function statementDigest(chainId, verifyingContract, stmtId) {
  if (!BYTES32_RE.test(stmtId)) {
    throw new Error(`Invalid bytes32 statementId: ${stmtId}`);
  }
  const domSep = hexToBytes(domainSeparator(chainId, verifyingContract));
  const structHash = keccak256Bytes(concatBytes(STATEMENT_TYPEHASH, hexToBytes(stmtId)));
  return keccak256(concatBytes(Uint8Array.of(0x19, 0x01), domSep, structHash));
}

export function statementLeaf(stmtId) {
  if (!BYTES32_RE.test(stmtId)) {
    throw new Error(`Invalid bytes32 statementId: ${stmtId}`);
  }
  return keccak256(concatBytes(Uint8Array.of(0x00), hexToBytes(stmtId)));
}

export function hashMerklePair(leftHex, rightHex) {
  return keccak256(concatBytes(Uint8Array.of(0x01), hexToBytes(leftHex), hexToBytes(rightHex)));
}

export function statementRoot(statementIds) {
  if (!Array.isArray(statementIds)) {
    throw new TypeError('statementIds must be an array');
  }
  if (statementIds.length === 0) return ZERO_BYTES32;
  for (const id of statementIds) {
    if (typeof id !== 'string' || !BYTES32_RE.test(id)) {
      throw new Error(`Invalid bytes32 statementId: ${String(id)}`);
    }
  }
  const sorted = [...statementIds].sort((a, b) => {
    const ba = BigInt(a);
    const bb = BigInt(b);
    return ba < bb ? -1 : ba > bb ? 1 : 0;
  });
  for (let i = 1; i < sorted.length; i++) {
    if (sorted[i] === sorted[i - 1]) {
      throw new Error(`Duplicate statementId: ${sorted[i]}`);
    }
  }

  let level = sorted.map((id) => statementLeaf(id));
  while (level.length > 1) {
    const next = [];
    for (let i = 0; i < level.length; i += 2) {
      if (i + 1 < level.length) {
        next.push(hashMerklePair(level[i], level[i + 1]));
      } else {
        next.push(level[i]);
      }
    }
    level = next;
  }
  return level[0];
}

// ---------------------------------------------------------------------------
// Statement validation, signing, envelope verification, aggregation & reports
// ---------------------------------------------------------------------------

function isPlainObject(val) {
  return val !== null && typeof val === 'object' && !Array.isArray(val);
}

function parseIntString(val) {
  if (typeof val !== 'string' || !INT_RE.test(val)) return null;
  return BigInt(val);
}

export function statementProblem(statement) {
  if (!isPlainObject(statement)) {
    return 'statement must be a JSON object';
  }

  const keys = Object.keys(statement);
  for (const k of STATEMENT_KEYS) {
    if (!Object.prototype.hasOwnProperty.call(statement, k)) {
      return `missing required member: ${k}`;
    }
  }
  for (const k of keys) {
    if (!STATEMENT_KEY_SET.has(k)) {
      return `unexpected member: ${k}`;
    }
  }

  if (statement.kind !== STATEMENT_KIND) {
    return `kind must be "${STATEMENT_KIND}"`;
  }

  const registry = parseAccount(statement.registry);
  if (!registry) return 'invalid registry account';
  const servicer = parseAccount(statement.servicer);
  if (!servicer) return 'invalid servicer account';
  const observer = parseAccount(statement.observer);
  if (!observer) return 'invalid observer account';

  if (registry.chainId !== servicer.chainId || registry.chainId !== observer.chainId) {
    return 'registry, servicer, and observer must share the same chainId';
  }

  if (typeof statement.collateralId !== 'string' || !BYTES32_RE.test(statement.collateralId)) {
    return 'invalid collateralId bytes32';
  }
  if (typeof statement.deviceKey !== 'string' || !BYTES32_RE.test(statement.deviceKey)) {
    return 'invalid deviceKey bytes32';
  }
  if (typeof statement.pciDeviceId !== 'string' || !PCI_DEVICE_RE.test(statement.pciDeviceId)) {
    return 'invalid pciDeviceId (expected 4 lowercase hex digits)';
  }
  if (typeof statement.location !== 'string' || !LOCATION_RE.test(statement.location)) {
    return 'invalid location (expected ISO 3166-1 alpha-2 uppercase country code)';
  }

  const periodStart = parseIntString(statement.periodStart);
  if (periodStart === null || periodStart > MAX_UINT64) {
    return 'invalid periodStart (must be uint64 integer string)';
  }
  const periodEnd = parseIntString(statement.periodEnd);
  if (periodEnd === null || periodEnd > MAX_UINT64) {
    return 'invalid periodEnd (must be uint64 integer string)';
  }

  if (typeof statement.role !== 'string' || !ROLES.has(statement.role)) {
    return `invalid role: ${String(statement.role)}`;
  }
  if (typeof statement.method !== 'string' || !METHODS.has(statement.method)) {
    return `invalid method: ${String(statement.method)}`;
  }

  const checksPassed = parseIntString(statement.checksPassed);
  if (checksPassed === null) return 'invalid checksPassed integer string';
  const checksFailed = parseIntString(statement.checksFailed);
  if (checksFailed === null) return 'invalid checksFailed integer string';
  const servedSeconds = parseIntString(statement.servedSeconds);
  if (servedSeconds === null) return 'invalid servedSeconds integer string';
  const missedSeconds = parseIntString(statement.missedSeconds);
  if (missedSeconds === null) return 'invalid missedSeconds integer string';
  const unknownSeconds = parseIntString(statement.unknownSeconds);
  if (unknownSeconds === null) return 'invalid unknownSeconds integer string';

  if (!Array.isArray(statement.evidence)) {
    return 'evidence must be an array';
  }
  for (let i = 0; i < statement.evidence.length; i++) {
    const item = statement.evidence[i];
    if (!isPlainObject(item)) return `evidence[${i}] must be an object`;
    const itemKeys = Object.keys(item);
    for (const req of EVIDENCE_KEY_SET) {
      if (!Object.prototype.hasOwnProperty.call(item, req)) {
        return `evidence[${i}] missing member: ${req}`;
      }
    }
    for (const k of itemKeys) {
      if (!EVIDENCE_KEY_SET.has(k)) {
        return `evidence[${i}] unexpected member: ${k}`;
      }
    }
    if (typeof item.type !== 'string') return `evidence[${i}].type must be a string`;
    if (typeof item.uri !== 'string') return `evidence[${i}].uri must be a string`;
    if (typeof item.hash !== 'string' || !BYTES32_RE.test(item.hash)) {
      return `evidence[${i}].hash must be a bytes32`;
    }
  }

  // Rule 1: periodEnd > periodStart and served + missed + unknown == periodEnd - periodStart
  if (periodEnd <= periodStart) {
    return 'periodEnd must be greater than periodStart';
  }
  const duration = periodEnd - periodStart;
  if (servedSeconds + missedSeconds + unknownSeconds !== duration) {
    return 'servedSeconds + missedSeconds + unknownSeconds must equal periodEnd - periodStart';
  }

  // Rule 3: instant methods report whole period as unknownSeconds; non-attestation checks must be 0
  if (INSTANT_METHODS.has(statement.method)) {
    if (servedSeconds !== 0n || missedSeconds !== 0n || unknownSeconds !== duration) {
      return `${statement.method} must report the whole period as unknownSeconds`;
    }
  }
  if (statement.method !== 'hw-attestation') {
    if (checksPassed !== 0n || checksFailed !== 0n) {
      return `checksPassed and checksFailed must be zero for method ${statement.method}`;
    }
  }

  return null;
}

export function signStatement(statement, privKey) {
  const problem = statementProblem(statement);
  if (problem !== null) {
    throw new Error(`Cannot sign invalid statement: ${problem}`);
  }
  const reg = parseAccount(statement.registry);
  const obs = parseAccount(statement.observer);
  const signerAddr = privateKeyToAddress(privKey);
  if (signerAddr !== obs.address) {
    throw new Error(`Private key address ${signerAddr} does not match statement observer ${obs.address}`);
  }
  const id = statementId(statement);
  const digest = statementDigest(reg.chainId, reg.address, id);
  const signature = signDigest(digest, privKey);
  return { statement, signature };
}

// Verifies an envelope signed by an externally owned account. Observers listed in
// options.contractObservers (lowercase addresses) are contracts: their signatures need an
// ERC-1271 call against the state after the report block, which this offline script does not
// make, so their envelopes are reported as unverified.
export function verifyEnvelope(envelope, options = {}) {
  if (!isPlainObject(envelope)) {
    return { ok: false, problem: 'envelope must be an object' };
  }
  const keys = Object.keys(envelope);
  if (
    keys.length !== 2 ||
    !Object.prototype.hasOwnProperty.call(envelope, 'statement') ||
    !Object.prototype.hasOwnProperty.call(envelope, 'signature')
  ) {
    return { ok: false, problem: 'envelope must have exactly "statement" and "signature" members' };
  }

  const stmtProb = statementProblem(envelope.statement);
  if (stmtProb !== null) {
    return { ok: false, problem: stmtProb };
  }

  const reg = parseAccount(envelope.statement.registry);
  const obs = parseAccount(envelope.statement.observer);
  const contractObservers = (options.contractObservers || []).map((x) => String(x).toLowerCase());
  if (contractObservers.includes(obs.address)) {
    return { ok: false, problem: 'contract observer: ERC-1271 check at the report block required, not performed offline' };
  }
  const id = statementId(envelope.statement);
  const digest = statementDigest(reg.chainId, reg.address, id);

  let recovered;
  try {
    recovered = recoverAddress(digest, envelope.signature);
  } catch (err) {
    return { ok: false, problem: `invalid signature: ${err.message}` };
  }

  if (recovered !== obs.address) {
    return { ok: false, problem: 'signature does not recover to observer' };
  }

  return { ok: true, statementId: id, digest, signer: recovered };
}

function toBigIntField(val, name) {
  if (typeof val === 'bigint') return val;
  if (typeof val === 'number' && Number.isInteger(val) && val >= 0) return BigInt(val);
  if (typeof val === 'string' && INT_RE.test(val)) return BigInt(val);
  throw new Error(`Invalid integer field ${name}`);
}

/**
 * Validate envelopes against optional `expected` constraints and compute ERC-8512 report aggregates.
 */
export function aggregate(envelopes, expected = null) {
  if (!Array.isArray(envelopes)) {
    throw new Error('envelopes must be an array');
  }

  const pledgedSet =
    expected && expected.pledgedDeviceKeys != null
      ? new Set(expected.pledgedDeviceKeys)
      : null;

  const seenIds = new Set();
  const statementIds = [];
  const byDevice = new Map();

  for (let i = 0; i < envelopes.length; i++) {
    const env = envelopes[i];
    const check = verifyEnvelope(env, { contractObservers: expected && expected.contractObservers });
    if (!check.ok) {
      throw new Error(`envelope[${i}]: ${check.problem}`);
    }
    const id = check.statementId;
    if (seenIds.has(id)) {
      throw new Error(`duplicate statementId: ${id}`);
    }
    seenIds.add(id);
    statementIds.push(id);

    const s = env.statement;
    if (expected) {
      if (expected.registry !== undefined && s.registry !== expected.registry) {
        throw new Error(`envelope[${i}]: statement registry mismatch`);
      }
      if (expected.servicer !== undefined && s.servicer !== expected.servicer) {
        throw new Error(`envelope[${i}]: statement servicer mismatch`);
      }
      if (expected.collateralId !== undefined && s.collateralId !== expected.collateralId) {
        throw new Error(`envelope[${i}]: statement collateralId mismatch`);
      }
      if (expected.periodStart !== undefined && BigInt(s.periodStart) !== toBigIntField(expected.periodStart, 'periodStart')) {
        throw new Error(`envelope[${i}]: statement periodStart mismatch`);
      }
      if (expected.periodEnd !== undefined && BigInt(s.periodEnd) !== toBigIntField(expected.periodEnd, 'periodEnd')) {
        throw new Error(`envelope[${i}]: statement periodEnd mismatch`);
      }
      if (pledgedSet !== null && !pledgedSet.has(s.deviceKey)) {
        throw new Error(`envelope[${i}]: deviceKey ${s.deviceKey} is not actively pledged`);
      }
    }

    let list = byDevice.get(s.deviceKey);
    if (!list) {
      list = [];
      byDevice.set(s.deviceKey, list);
    }
    list.push({ id, statement: s });
  }

  statementIds.sort((a, b) => {
    const ba = BigInt(a);
    const bb = BigInt(b);
    return ba < bb ? -1 : ba > bb ? 1 : 0;
  });

  const root = statementRoot(statementIds);
  const devicesReported = byDevice.size;
  let devicesAttested = 0;
  let servedSeconds = 0n;
  let missedSeconds = 0n;
  let unknownSeconds = 0n;
  const selectedByDevice = {};

  for (const [devKey, entries] of byDevice.entries()) {
    const attested = entries.some(
      ({ statement }) => statement.method === 'hw-attestation' && BigInt(statement.checksPassed) > 0n
    );
    if (attested) devicesAttested++;

    const observed = entries.filter(
      ({ statement }) => BigInt(statement.servedSeconds) + BigInt(statement.missedSeconds) > 0n
    );
    const pool = observed.length > 0 ? observed : entries;
    let selected = pool[0];
    for (let i = 1; i < pool.length; i++) {
      if (BigInt(pool[i].id) < BigInt(selected.id)) {
        selected = pool[i];
      }
    }
    selectedByDevice[devKey] = selected.id;
    servedSeconds += BigInt(selected.statement.servedSeconds);
    missedSeconds += BigInt(selected.statement.missedSeconds);
    unknownSeconds += BigInt(selected.statement.unknownSeconds);
  }

  return {
    devicesReported,
    devicesAttested,
    servedSeconds,
    missedSeconds,
    unknownSeconds,
    statementRoot: root,
    statementIds,
    selectedByDevice,
  };
}

/**
 * Check whether `report` is a correct ERC-8512 report for `envelopes` (array or raw JSON text)
 * under `context` ({ registry, servicer, collateralId, pledgedDeviceKeys }).
 * Returns null if correct, or a string describing the first problem found.
 */
export function reportProblem(report, envelopes, context) {
  if (!isPlainObject(report)) return 'report must be an object';
  if (!isPlainObject(context)) return 'context must be an object';
  for (const k of ['registry', 'servicer', 'collateralId']) {
    if (typeof context[k] !== 'string') return `context.${k} is required`;
  }
  if (!Array.isArray(context.pledgedDeviceKeys)) return 'context.pledgedDeviceKeys is required';

  let parsedEnvelopes = envelopes;
  if (typeof envelopes === 'string') {
    try {
      parsedEnvelopes = parseJson(envelopes);
    } catch (err) {
      return `invalid envelopes JSON: ${err.message}`;
    }
  }

  let periodStart;
  let periodEnd;
  let devicesReported;
  let devicesAttested;
  let servedSeconds;
  let missedSeconds;
  let unknownSeconds;
  try {
    periodStart = toBigIntField(report.periodStart, 'periodStart');
    periodEnd = toBigIntField(report.periodEnd, 'periodEnd');
    devicesReported = toBigIntField(report.devicesReported, 'devicesReported');
    devicesAttested = toBigIntField(report.devicesAttested, 'devicesAttested');
    servedSeconds = toBigIntField(report.servedSeconds, 'servedSeconds');
    missedSeconds = toBigIntField(report.missedSeconds, 'missedSeconds');
    unknownSeconds = toBigIntField(report.unknownSeconds, 'unknownSeconds');
  } catch (err) {
    return err.message;
  }

  if (periodStart > MAX_UINT64 || periodEnd > MAX_UINT64 || periodEnd <= periodStart) {
    return 'invalid report period';
  }
  if (typeof report.statementRoot !== 'string' || !BYTES32_RE.test(report.statementRoot)) {
    return 'invalid report statementRoot';
  }

  let computed;
  try {
    computed = aggregate(parsedEnvelopes, {
      registry: context.registry,
      servicer: context.servicer,
      collateralId: context.collateralId,
      periodStart,
      periodEnd,
      pledgedDeviceKeys: context.pledgedDeviceKeys,
      contractObservers: context.contractObservers,
    });
  } catch (err) {
    return err.message;
  }

  if (computed.statementRoot !== report.statementRoot) {
    return `statementRoot mismatch: expected ${computed.statementRoot}, got ${report.statementRoot}`;
  }
  if (BigInt(computed.devicesReported) !== devicesReported) {
    return `devicesReported mismatch: expected ${computed.devicesReported}, got ${devicesReported}`;
  }
  if (BigInt(computed.devicesAttested) !== devicesAttested) {
    return `devicesAttested mismatch: expected ${computed.devicesAttested}, got ${devicesAttested}`;
  }
  if (computed.servedSeconds !== servedSeconds) {
    return `servedSeconds mismatch: expected ${computed.servedSeconds}, got ${servedSeconds}`;
  }
  if (computed.missedSeconds !== missedSeconds) {
    return `missedSeconds mismatch: expected ${computed.missedSeconds}, got ${missedSeconds}`;
  }
  if (computed.unknownSeconds !== unknownSeconds) {
    return `unknownSeconds mismatch: expected ${computed.unknownSeconds}, got ${unknownSeconds}`;
  }

  return null;
}
