// SPDX-License-Identifier: CC0-1.0
// pq_key_binding.v1/signatures: reproduce the signature fixtures and their negative controls.
//
// Contract: FIPS 204 / FIPS 205 pure mode, empty context, message = the 32 raw bytes named by each
// case. The message is RECOMPUTED here, from the statement (direct route) or the carrier
// (carrier-bound route); `message_hex` in the vectors is only compared against, never trusted.
//
// Requires @noble/post-quantum (tested with 0.7.1):
//   npm install --no-save @noble/post-quantum@0.7.1
//   node check_signatures.mjs pq-key-binding-v1.signature-vectors.json
// Exit 0 when every case and every control reproduces, 1 otherwise.
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import { slh_dsa_sha2_192s } from '@noble/post-quantum/slh-dsa.js';
import { ml_dsa65 } from '@noble/post-quantum/ml-dsa.js';
import { sha256, sha512 } from '@noble/hashes/sha2.js';
import { schnorr } from '@noble/curves/secp256k1.js';

const ALG = { 'SLH-DSA-SHA2-192s': slh_dsa_sha2_192s, 'ML-DSA-65': ml_dsa65 };
const PREHASH = { sha256, sha512 };
const hex = (h) => Uint8Array.from(Buffer.from(h, 'hex'));
const toHex = (b) => Buffer.from(b).toString('hex');
const sha = (s) => createHash('sha256').update(s).digest('hex');
const flip = (b) => { const c = Uint8Array.from(b); c[0] ^= 1; return c; };
// JCS (RFC 8785) for the flat statements these fixtures cover: sorted keys, compact, literal UTF-8.
const jcs = (o) => '{' + Object.keys(o).sort().map((k) => JSON.stringify(k) + ':' + JSON.stringify(o[k])).join(',') + '}';
const eventId = (c) => sha(JSON.stringify([0, c.pubkey, c.created_at, c.kind_number, c.tags, c.content]));

function verify(alg, sig, msg, pub, opts = {}) {
  try {
    const signer = opts.prehash ? alg.prehash(PREHASH[opts.prehash]) : alg;
    return signer.verify(sig, msg, pub, opts.context ? { context: new TextEncoder().encode(opts.context) } : undefined)
      ? 'valid' : 'invalid';
  } catch (err) {
    return opts.prehash ? 'refused' : 'error: ' + err.message;
  }
}

const fx = JSON.parse(fs.readFileSync(process.argv[2] || 'pq-key-binding-v1.signature-vectors.json', 'utf8'));
let bad = 0, total = 0;
const report = (ok, label, detail) => { total++; if (!ok) bad++; console.log(`${ok ? 'OK ' : 'BAD'} ${label}${detail ? '  ' + detail : ''}`); };

for (const c of fx.cases) {
  const alg = ALG[c.algorithm];
  if (!alg) { report(false, c.id, `unknown algorithm ${c.algorithm}`); continue; }
  const statementCA = sha(jcs(c.statement));
  let msgHex;
  if (c.route === 'direct') {
    msgHex = statementCA;
  } else if (c.route === 'carrier-bound') {
    report(sha(c.carrier.content) === statementCA, `${c.id} carrier content is the statement`);
    msgHex = eventId(c.carrier);
    // The carrier must be signed by the binding's classical identity (BIP-340 over the event id).
    report(c.carrier.pubkey === c.statement.secp256k1_pubkey, `${c.id} carrier key is the statement's classical identity`);
    let schnorrOk = false;
    try { schnorrOk = schnorr.verify(hex(c.carrier.sig), hex(msgHex), hex(c.carrier.pubkey)); } catch { schnorrOk = false; }
    report(schnorrOk, `${c.id} carrier BIP-340 signature`);
  } else { report(false, c.id, `unknown route ${c.route}`); continue; }
  report(msgHex === c.message_hex, `${c.id} recomputed message matches`, msgHex === c.message_hex ? '' : `${msgHex} != ${c.message_hex}`);

  const msg = hex(msgHex), pub = hex(c.public_key_hex), sig = hex(c.signature_hex);
  const got = verify(alg, sig, msg, pub);
  report(got === c.expect, `${c.id} pure, empty context`, `${got}`);

  for (const n of c.negative_controls) {
    let r;
    switch (n.id) {
      case 'wrong_context': r = verify(alg, sig, msg, pub, { context: n.context_utf8 }); break;
      case 'prehash_sha256': case 'prehash_sha512': r = verify(alg, sig, msg, pub, { prehash: n.prehash }); break;
      case 'message_as_hex_string': r = verify(alg, sig, new TextEncoder().encode(msgHex), pub); break;
      case 'wrong_message': r = verify(alg, sig, flip(msg), pub); break;
      case 'wrong_key': r = verify(alg, sig, msg, hex(n.public_key_hex)); break;
      case 'mutated_signature': r = verify(alg, flip(sig), msg, pub); break;
      case 'direct_route_over_statement_digest': r = verify(alg, sig, hex(statementCA), pub); break;
      case 'carrier_wrong_classical_key': {
        const other = Buffer.from(schnorr.getPublicKey(new Uint8Array(32).fill(9))).toString('hex');
        let v = false; try { v = schnorr.verify(hex(c.carrier.sig), hex(msgHex), hex(other)); } catch { v = false; }
        r = v ? 'valid' : 'invalid';
        break;
      }
      case 'tampered_carrier': {
        const t = { ...c.carrier, content: c.carrier.content + ' ' };
        r = (sha(t.content) !== statementCA && eventId(t) !== msgHex) ? 'link_broken' : 'link_intact';
        break;
      }
      default: r = `unknown control ${n.id}`;
    }
    const ok = n.expect === 'invalid_or_refused' ? (r === 'invalid' || r === 'refused') : r === n.expect;
    report(ok, `${c.id} control ${n.id}`, r);
  }
}
console.log(`${total - bad}/${total} checks reproduced`);
process.exit(bad ? 1 : 0);
