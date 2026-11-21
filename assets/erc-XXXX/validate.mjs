#!/usr/bin/env node
// Dependency-free validator for Agent Linkability Report test vectors.
// Usage: node validate.mjs            (validates vectors/valid/* must pass, vectors/invalid/* must fail)
//        node validate.mjs report.json (validates one report)
// It implements the JSON Schema keywords used by linkability-report.schema.json and refuses any other
// keyword, then applies the rules of the specification that a schema cannot express.

import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const schema = JSON.parse(readFileSync(join(here, 'linkability-report.schema.json'), 'utf8'));

const KNOWN = new Set(['$schema', '$id', '$defs', 'title', '$ref', 'type', 'required', 'properties',
  'additionalProperties', 'enum', 'const', 'pattern', 'items', 'minItems', 'minimum', 'maximum', 'oneOf']);

function typeOf(v) {
  if (v === null) return 'null';
  if (Array.isArray(v)) return 'array';
  if (typeof v === 'number') return Number.isInteger(v) ? 'integer' : 'number';
  return typeof v;
}
function typeOk(v, t) {
  const actual = typeOf(v);
  return actual === t || (t === 'number' && actual === 'integer');
}
function resolve(ref) {
  if (!ref.startsWith('#/')) throw new Error(`unsupported $ref ${ref}`);
  return ref.slice(2).split('/').reduce((o, k) => o[k], schema);
}

function validate(v, s, path, errs) {
  for (const k of Object.keys(s)) if (!KNOWN.has(k)) throw new Error(`schema keyword not supported: ${k}`);
  if (s.$ref) return validate(v, resolve(s.$ref), path, errs);
  if (s.type) {
    const types = Array.isArray(s.type) ? s.type : [s.type];
    if (!types.some((t) => typeOk(v, t))) { errs.push(`${path}: expected ${types.join('|')}, got ${typeOf(v)}`); return; }
  }
  if ('const' in s && JSON.stringify(v) !== JSON.stringify(s.const)) errs.push(`${path}: expected ${JSON.stringify(s.const)}`);
  if (s.enum && !s.enum.some((e) => JSON.stringify(e) === JSON.stringify(v))) errs.push(`${path}: not in ${JSON.stringify(s.enum)}`);
  if (s.pattern && typeof v === 'string' && !new RegExp(s.pattern).test(v)) errs.push(`${path}: does not match ${s.pattern}`);
  if (typeof v === 'number') {
    if ('minimum' in s && v < s.minimum) errs.push(`${path}: below ${s.minimum}`);
    if ('maximum' in s && v > s.maximum) errs.push(`${path}: above ${s.maximum}`);
  }
  if (Array.isArray(v)) {
    if ('minItems' in s && v.length < s.minItems) errs.push(`${path}: fewer than ${s.minItems} items`);
    if (s.items) v.forEach((x, i) => validate(x, s.items, `${path}/${i}`, errs));
  }
  if (typeOf(v) === 'object') {
    for (const r of s.required || []) if (!(r in v)) errs.push(`${path}: missing ${r}`);
    const props = s.properties || {};
    for (const [k, x] of Object.entries(v)) {
      if (k in props) validate(x, props[k], `${path}/${k}`, errs);
      else if (s.additionalProperties === false) errs.push(`${path}: unexpected member ${k}`);
    }
  }
  if (s.oneOf) {
    const passing = s.oneOf.filter((alt) => { const e = []; validate(v, alt, path, e); return e.length === 0; });
    if (passing.length !== 1) errs.push(`${path}: matches ${passing.length} of oneOf (needs exactly 1)`);
  }
}

// Rules of the specification beyond the schema.
function rules(r, errs) {
  const lc = (a) => (a == null ? a : a.toLowerCase());
  // 1. partial is true exactly when a field is not read for a reason other than "unsupported",
  //    and partial_reasons lists exactly those fields.
  const found = [];
  (function walk(o, p) {
    if (Array.isArray(o)) o.forEach((x, i) => walk(x, `${p}/${i}`));
    else if (o && typeof o === 'object') {
      if (o.status === 'not_read' && o.reason !== 'unsupported') found.push(`${p}|${o.reason}`);
      for (const [k, x] of Object.entries(o)) if (k !== 'partial_reasons') walk(x, `${p}/${k}`);
    }
  })(r, '');
  const listed = (r.partial_reasons || []).map((x) => `${x.field}|${x.reason}`);
  if (r.partial !== found.length > 0) errs.push(`rule partial: partial is ${r.partial} but ${found.length} field(s) not read for a reason other than unsupported`);
  if (found.sort().join() !== listed.slice().sort().join()) errs.push('rule partial_reasons: does not list exactly the fields not read for a reason other than unsupported');

  // 2. every evidence block is at or before the report's block.
  const block = BigInt(r.block);
  (function walk(o, p) {
    if (Array.isArray(o)) o.forEach((x, i) => walk(x, `${p}/${i}`));
    else if (o && typeof o === 'object') {
      if (p.includes('/evidence/')) for (const k of ['block', 'to_block', 'from_block']) if (typeof o[k] === 'string' && BigInt(o[k]) > block) errs.push(`rule block: ${p}/${k} is after the report block`);
      for (const [k, x] of Object.entries(o)) walk(x, `${p}/${k}`);
    }
  })(r, '');

  // 3. per-address entries name the agent's addresses as read at the report block.
  const a = r.agent;
  const owner = a.owner.status === 'read' ? lc(a.owner.value) : undefined;
  const wallet = a.agentWallet.status === 'read' ? lc(a.agentWallet.value) : undefined;
  const payTo = a.payTo.status === 'read' ? a.payTo.value.map(lc) : undefined;
  const groups = { ...r.findings, ...r.helps };
  for (const [name, f] of Object.entries(groups)) {
    if (!f || !Array.isArray(f.entries)) continue;
    f.entries.forEach((e, i) => {
      const where = `rule entries: ${name}/entries/${i}`;
      const addr = lc(e.address);
      if (e.role === 'agentWallet' && wallet !== undefined && addr !== wallet) errs.push(`${where} names ${addr} but agent.agentWallet is ${wallet}`);
      if (e.role === 'payTo' && payTo !== undefined && addr !== null && !payTo.includes(addr)) errs.push(`${where} names a payTo the agent does not list`);
      if (e.role === 'owner' && owner !== undefined && addr !== owner) errs.push(`${where} names ${addr} but agent.owner is ${owner}`);
      if (name === 'payment_lands_on_owner' && e.status === 'read' && owner !== undefined) {
        const want = addr === null ? 'unset' : addr === owner;
        if (e.value !== want) errs.push(`${where} value ${JSON.stringify(e.value)} but the addresses give ${JSON.stringify(want)}`);
      }
      if ((name === 'owner_funded_payment_address' || name === 'owner_payment_direct_link') && e.status === 'read' && owner !== undefined && (e.value === 'same-address') !== (addr === owner)) errs.push(`${where} same-address does not agree with the addresses`);
    });
  }
}

function check(file) {
  const r = JSON.parse(readFileSync(file, 'utf8'));
  const errs = [];
  validate(r, schema, '', errs);
  if (errs.length === 0) rules(r, errs);
  return errs;
}

const args = process.argv.slice(2);
if (args.length) {
  let bad = 0;
  for (const f of args) { const e = check(f); console.log(`${e.length ? 'FAIL' : 'ok  '} ${f}`); e.forEach((x) => console.log(`     ${x}`)); bad += e.length ? 1 : 0; }
  process.exit(bad ? 1 : 0);
}
let failures = 0;
for (const kind of ['valid', 'invalid']) {
  const dir = join(here, 'vectors', kind);
  for (const f of readdirSync(dir).filter((x) => x.endsWith('.json')).sort()) {
    const errs = check(join(dir, f));
    const pass = kind === 'valid' ? errs.length === 0 : errs.length > 0;
    if (!pass) failures++;
    console.log(`${pass ? 'ok  ' : 'FAIL'} ${kind}/${f}${kind === 'invalid' && errs.length ? `  (rejected: ${errs[0]})` : ''}`);
    if (kind === 'valid') errs.forEach((x) => console.log(`     ${x}`));
  }
}
console.log(failures ? `${failures} vector(s) did not behave as expected` : 'all vectors behave as expected');
process.exit(failures ? 1 : 0);
