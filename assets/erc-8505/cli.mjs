#!/usr/bin/env node
// Reference writer and reader for Evaluated Work Records. Reads public JSON-RPC endpoints; holds no key, sends nothing.
// `node cli.mjs <command> --help` lists each command's flags.
// Exit codes: 0 every check passed, 1 a check failed or an error, 2 usage, 3 nothing to post.

import { readFileSync, writeFileSync } from "node:fs";
import {
  buildRecord, checkRecord, checksum, compileSource, createdAtProblem, dataUriBytes, decodeFeedback, decodeReadFeedback,
  decodeWorkers, DUE_SECONDS, encodeCall, entryOf, findDuplicates, giveFeedbackCalldata, hexToBytes, indexGaps, isDue,
  judge, keccak256, LAPSED, MAX_FILE, METADATA_SET, metadataValue, moneyTasks, moneyTxs, NEW_FEEDBACK, otherAgents,
  outcomeLabel, parseAddress, readFile, stepsOf, TAG1, taskKey, unbackedTransfers, validCreatedAt,
} from "./work-records.mjs";

const HERE = new URL(".", import.meta.url);
const MAX_FETCHED = 1 << 20;
const NOTHING_TO_POST = 3;

class UsageError extends Error {}
const usageError = (what) => {
  throw new UsageError(what);
};
const expected = (what) => {
  throw new Error(`expected ${what}`);
};

const TYPES = {
  url: (v) => (/^https?:\/\//.test(v) && new URL(v) ? v : expected("an http(s) URL")),
  int: (v) => (/^(0|[1-9]\d*)$/.test(v) ? v : expected("a decimal integer")),
  agent: (v) => (/^(0|[1-9]\d*)$/.test(v) && BigInt(v) <= BigInt(Number.MAX_SAFE_INTEGER) ? v : expected("an agent id from 0 to 2^53 - 1, the largest a record can carry")),
  address: parseAddress,
  hash: (v) => (/^0x[0-9a-fA-F]{64}$/.test(v) ? v.toLowerCase() : expected("a 32-byte hex hash")),
  caip10: (v) => {
    const m = /^eip155:(\d+):(0x[0-9a-fA-F]{40})$/.exec(v) ?? expected("eip155:<chainId>:<address>");
    return `eip155:${m[1]}:${parseAddress(m[2])}`;
  },
  chainUrl: (v) => {
    const m = /^(\d+)=(https?:\/\/.+)$/.exec(v) ?? expected("<chainId>=<http(s) URL>");
    return [Number(m[1]), m[2]];
  },
  file: (v) => v,
  uri: (v) => (/^(data:|https:\/\/|ipfs:\/\/)/.test(v) ? v : expected("a data:, https:// or ipfs:// URI")),
  created: (v) => (validCreatedAt(v) ? v : expected("RFC 3339 UTC to the second, such as 2026-11-16T09:00:00Z")),
  bool: (v) => v,
};

const COMMANDS = {
  build: {
    about: "Writer: builds the record of one task from the source's final logs and prints it with its giveFeedback calldata.\nExits 3 with the reason when the task takes no entry.",
    flags: {
      rpc: { type: "url", required: true, help: "the source chain's JSON-RPC endpoint" },
      descriptor: { type: "file", required: true, help: "the source's descriptor (the one its deployer publishes)" },
      task: { type: "int", required: true, help: "the task id" },
      registry: { type: "caip10", required: true, help: "the ERC-8004 Identity Registry, eip155:<chainId>:<address>" },
      agent: { type: "agent", required: true, help: "the agent id the task is bound to" },
      writer: { type: "address", required: true, help: "the address that will post the entry" },
      created: { type: "created", help: "createdAt (default: the source's finalized head time); not before the terminal step, not in the future" },
      "serve-uri": { type: "uri", help: "https:// or ipfs:// URI serving the file, for a record over 8,192 bytes" },
      calldata: { type: "bool", help: "print only the giveFeedback calldata" },
      out: { type: "file", help: "also write the record bytes to this file, for check --file" },
    },
  },
  check: {
    about: "Reader: checks one record against the source's logs and transfers.\nThe agent id and the binding are checked only against an entry, by the entries command.",
    flags: {
      rpc: { type: "url", required: true, help: "the source chain's JSON-RPC endpoint" },
      descriptor: { type: "file", required: true, help: "the descriptor you hold for the source" },
      file: { type: "file", help: "a file holding the record bytes (instead of --uri)" },
      uri: { type: "uri", help: "the entry's feedbackURI (with --hash)" },
      hash: { type: "hash", help: "the entry's feedbackHash (required with --uri; with --file, checked if given)" },
      "ipfs-gateway": { type: "url", help: "gateway for ipfs:// URIs, such as https://ipfs.io" },
    },
  },
  entries: {
    about: "Reader: checks every entry one writer posted about one agent: records, transfers, binding, revocations,\nduplicates across agents and, with --rebuild, coverage.",
    flags: {
      "registry-rpc": { type: "url", required: true, help: "JSON-RPC endpoint of the registries' chain" },
      reputation: { type: "caip10", required: true, help: "the ERC-8004 Reputation Registry, eip155:<chainId>:<address>" },
      agent: { type: "agent", required: true, help: "the agent id" },
      writer: { type: "address", required: true, help: "the writer (the entries' clientAddress)" },
      "from-block": { type: "int", required: true, help: "where to scan from: the Reputation Registry's deployment block on its chain" },
      rpc: { type: "chainUrl", multi: true, help: "<chainId>=<url> for each source chain" },
      descriptor: { type: "file", multi: true, help: "a descriptor you hold, one per source" },
      span: { type: "int", help: "blocks per eth_getLogs request (default 10000000); halves when an endpoint refuses" },
      rebuild: { type: "bool", help: "also check coverage: every due task of each worker the writer used has an entry" },
      "ipfs-gateway": { type: "url", help: "gateway for ipfs:// URIs" },
    },
  },
  vectors: {
    about: "Compares vectors.json with what the library builds from the stored logs.\nWith --verify, also compares the stored logs, times and transfers with the chain's.",
    flags: { verify: { type: "chainUrl", multi: true, help: "<chainId>=<url> of a chain to verify the vectors against" } },
  },
};

function parseArgs(name, argv) {
  const schema = COMMANDS[name].flags;
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--help" || argv[i] === "-h") return { help: true };
    if (!argv[i].startsWith("--")) usageError(`unexpected "${argv[i]}"; flags start with --`);
    const eq = argv[i].indexOf("=");
    const flag = eq < 0 ? argv[i].slice(2) : argv[i].slice(2, eq);
    const inline = eq < 0 ? undefined : argv[i].slice(eq + 1);
    const spec = Object.hasOwn(schema, flag) ? schema[flag] : usageError(`${name} has no flag --${flag}`);
    let value = true;
    if (spec.type !== "bool") {
      const raw = inline ?? (argv[i + 1] !== undefined && !argv[i + 1].startsWith("--") ? argv[++i] : usageError(`--${flag} needs a value`));
      try {
        value = TYPES[spec.type](raw);
      } catch (e) {
        usageError(`--${flag}: ${e.message}`);
      }
    } else if (inline !== undefined) usageError(`--${flag} takes no value`);
    if (spec.multi) out[flag] = [...(out[flag] ?? []), value];
    else if (Object.hasOwn(out, flag)) usageError(`--${flag} given twice`);
    else out[flag] = value;
  }
  for (const [flag, spec] of Object.entries(schema)) if (spec.required && !Object.hasOwn(out, flag)) usageError(`missing --${flag} (${spec.help})`);
  return out;
}

function usage(name) {
  const c = COMMANDS[name];
  console.log(`node cli.mjs ${name} [--flag value | --flag=value] ...\n${c.about}\n`);
  for (const [k, s] of Object.entries(c.flags)) console.log(`  --${k}${s.type === "bool" ? "" : " <value>"}${s.required ? "" : " (optional)"}${s.multi ? " (repeatable)" : ""}\n      ${s.help}`);
  console.log("\nExit codes: 0 every check passed, 1 a check failed or an error, 2 usage, 3 nothing to post.");
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const backoff = (attempt, retryAfter) => (retryAfter ? Math.min(Number(retryAfter) * 1000, 30_000) : 500 * 2 ** attempt);
const TOO_BIG = /range|span|limit|too many|narrow|more than \d+ results|exceed/i;
let rpcId = 0;

async function rpc(url, method, params) {
  const host = new URL(url).host;
  for (let attempt = 0; ; attempt++) {
    let res;
    try {
      res = await fetch(url, {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", id: ++rpcId, method, params }), signal: AbortSignal.timeout(30_000),
      });
    } catch (cause) {
      if (attempt < 3) {
        await sleep(backoff(attempt));
        continue;
      }
      throw new Error(`${method} at ${host}: ${cause.message}`, { cause });
    }
    if (res.status === 429 || res.status >= 500) {
      if (attempt < 3) {
        await sleep(backoff(attempt, res.headers.get("retry-after")));
        continue;
      }
      throw new Error(`${method} at ${host}: HTTP ${res.status}`);
    }
    if (!res.ok) throw new Error(`${method} at ${host}: HTTP ${res.status}`);
    let body;
    try {
      body = await res.json();
    } catch (cause) {
      throw new Error(`${method} at ${host}: the reply is not JSON`, { cause });
    }
    if (body.error) {
      if (body.error.code === -32005 && !TOO_BIG.test(body.error.message) && attempt < 3) {
        await sleep(backoff(attempt));
        continue;
      }
      const err = new Error(`${method} at ${host}: ${body.error.message}`, { cause: body.error });
      err.code = body.error.code;
      throw err;
    }
    if (!Object.hasOwn(body, "result")) throw new Error(`${method} at ${host}: the reply has no result`);
    return body.result;
  }
}

const isRevert = (e) => e.code === 3 || /execution reverted/i.test(e.message);
const noHistory = (e) => /historical state|missing trie node|header not found/i.test(e.message);
const hex = (n) => "0x" + BigInt(n).toString(16);
const call = (url, to, data, block) => rpc(url, "eth_call", [{ to, data }, hex(block)]);
const lower = (s) => String(s).toLowerCase();

/** eth_getLogs over [from, to]: halves the span when the endpoint refuses a range or a result count, then grows it back. */
async function getLogs(url, filter, from, to, span = 10_000_000, cap = 2000) {
  const logs = [];
  let size = span;
  let requests = 0;
  for (let start = BigInt(from); start <= BigInt(to);) {
    const end = start + BigInt(size) - 1n < BigInt(to) ? start + BigInt(size) - 1n : BigInt(to);
    if (++requests > cap) throw new Error(`eth_getLogs needed more than ${cap} requests; start later or raise --span`);
    try {
      logs.push(...(await rpc(url, "eth_getLogs", [{ ...filter, fromBlock: hex(start), toBlock: hex(end) }])));
      start = end + 1n;
      size = Math.min(span, size * 2);
    } catch (e) {
      if (size <= 1 || !TOO_BIG.test(e.message)) throw e;
      size = Math.floor(size / 2);
    }
  }
  return logs;
}

const chains = new Map();
async function chainOf(url) {
  if (!chains.has(url)) chains.set(url, Number(BigInt(await rpc(url, "eth_chainId", []))));
  return chains.get(url);
}
async function onChain(url, chainId, what) {
  const served = await chainOf(url);
  if (served !== chainId) throw new Error(`${new URL(url).host} serves chain ${served}, but ${what} is on chain ${chainId}`);
  return url;
}

const times = new Map();
async function blockTime(url, n) {
  const key = `${url}#${n}`;
  if (!times.has(key)) times.set(key, Number(BigInt((await rpc(url, "eth_getBlockByNumber", [hex(n), false])).timestamp)));
  return times.get(key);
}
const head = async (url) => Number(BigInt(await rpc(url, "eth_blockNumber", [])));
/** The source chain's finalized head, read the way its descriptor says. */
async function finalizedHead(url, descriptor) {
  if (descriptor.finality === "finalized") {
    const b = await rpc(url, "eth_getBlockByNumber", ["finalized", false]);
    return { number: Number(BigInt(b.number)), time: Number(BigInt(b.timestamp)) };
  }
  const number = Math.max(0, (await head(url)) - descriptor.finality);
  return { number, time: await blockTime(url, number) };
}

const topicOf = (n) => "0x" + BigInt(n).toString(16).padStart(64, "0");
async function taskLogs(url, compiled, task, to, span) {
  return getLogs(url, { address: compiled.source.contract, topics: [[...compiled.byTopic.keys()], topicOf(task)] }, compiled.source.fromBlock, to, span);
}

/**
 * What the descriptor's vault getter returns for each task with money moving in the receipt. A descriptor names a
 * getter only when the account never changes, so the head answers for every past task.
 */
async function vaultsOf(url, compiled, receipt, at) {
  const called = new Map();
  if (!compiled.vault?.getter) return called;
  for (const task of moneyTasks(compiled, receipt)) {
    const what = `${compiled.vault.getter} for task ${task} at ${compiled.source.contract}`;
    let returned;
    try {
      returned = await call(url, compiled.source.contract, encodeCall(compiled.vault.getter, [task]), at);
    } catch (e) {
      if (isRevert(e)) throw new Error(`${what} reverted`);
      throw e;
    }
    if (!/^0x0{24}[0-9a-fA-F]{40}$/.test(returned)) throw new Error(`${what} returned no address`);
    called.set(task, "0x" + returned.slice(26));
  }
  return called;
}

async function fundsErrors(url, source, found) {
  const errors = [];
  const compiled = compileSource(source);
  const at = await head(url);
  for (const tx of moneyTxs(found)) {
    const receipt = await rpc(url, "eth_getTransactionReceipt", [tx]);
    if (!receipt) {
      errors.push(`no receipt for ${tx}`);
      continue;
    }
    const called = await vaultsOf(url, compiled, receipt, at);
    for (const m of unbackedTransfers(compiled, receipt, called)) errors.push(`no transfer of ${m.amount} from ${m.from} to ${m.to} in ${tx} for task ${m.task}`);
  }
  return errors;
}

async function fileBytes(uri, gateway) {
  if (uri.startsWith("data:")) return dataUriBytes(uri);
  let url = uri;
  if (uri.startsWith("ipfs://")) url = gateway ? `${gateway.replace(/\/$/, "")}/ipfs/${uri.slice(7)}` : usageError("--ipfs-gateway is needed to read an ipfs:// URI");
  const res = await fetch(url, { signal: AbortSignal.timeout(30_000), redirect: "error" });
  if (!res.ok) throw new Error(`${new URL(url).host} answered HTTP ${res.status} for the file`);
  const bytes = new Uint8Array(await res.arrayBuffer());
  if (bytes.length > MAX_FETCHED) throw new Error(`the served file is over ${MAX_FETCHED} bytes`);
  if (bytes.length <= MAX_FILE) throw new Error(`a file of ${bytes.length} bytes must travel as a data URI`);
  return bytes;
}

function readLocal(path) {
  try {
    return readFileSync(path);
  } catch (e) {
    if (e.code === "ENOENT") throw new Error(`no such file: ${path}`);
    throw new Error(`cannot read ${path} (${e.code ?? e.message})`, { cause: e });
  }
}

function loadDescriptor(path) {
  const bytes = readLocal(path);
  if (bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) throw new Error(`${path}: starts with a byte order mark`);
  let d;
  try {
    d = JSON.parse(bytes.toString("utf8"));
  } catch (e) {
    throw new Error(`${path}: not JSON (${e.message})`);
  }
  try {
    compileSource(d);
  } catch (e) {
    throw new Error(`${path}: ${e.message}`);
  }
  return d;
}
const loadDescriptors = (files = []) => new Map(files.map((f) => {
  const d = loadDescriptor(f);
  return [`${d.chainId}:${lower(d.contract)}`, d];
}));
const pinnedFor = (pins, source) => pins.get(`${source.chainId}:${lower(source.contract)}`);
const keyOf = (rec) => taskKey(rec.work.source, rec.work.task);
const labelOf = (rec) => outcomeLabel({ outcome: rec.work.outcome, lapsedAfter: rec.tag2 });
const PROFILE_TAGS = [TAG1, LAPSED];
const iso = (t) => new Date(t * 1000).toISOString().replace(".000Z", "Z");
const duration = (s) => `${Math.floor(Math.abs(s) / 3600)} h ${Math.floor((Math.abs(s) % 3600) / 60)} min`;

function line(status, subject, detail = [], more = []) {
  const [first, ...rest] = [].concat(detail);
  console.log(`${status.padEnd(8)}${subject}${first ? `: ${first}` : ""}`);
  for (const d of [...rest, ...more]) console.log(`        ${d}`);
}

async function build(o) {
  const source = loadDescriptor(o.descriptor);
  const compiled = compileSource(source);
  await onChain(o.rpc, source.chainId, `the descriptor's source`);
  const fin = await finalizedHead(o.rpc, source);
  const logs = await taskLogs(o.rpc, compiled, o.task, fin.number);
  if (!logs.length) {
    const pending = await taskLogs(o.rpc, compiled, o.task, await head(o.rpc));
    if (pending.length) {
      console.error(`nothing to post for task ${o.task}: its logs are not final yet (finalized head ${fin.number})`);
      return NOTHING_TO_POST;
    }
    throw new Error(`task ${o.task} has no logs at ${source.contract} on chain ${source.chainId}`);
  }
  const found = stepsOf(compiled, logs, o.task);
  const terminalTime = found.settled ? await blockTime(o.rpc, found.steps.at(-1).block) : undefined;
  const registryChain = o.registry.split(":")[1];
  const now = Math.floor(Date.now() / 1000);
  const out = buildRecord({
    source, logs, task: o.task, terminalTime, now,
    head: { agentRegistry: o.registry, agentId: Number(o.agent), clientAddress: `eip155:${registryChain}:${o.writer}`, createdAt: o.created ?? iso(fin.time) },
  });
  if (!out.entry) {
    console.error(`nothing to post for task ${o.task}: ${out.reason}`);
    return NOTHING_TO_POST;
  }
  if (out.entry.feedbackURI && o["serve-uri"]) usageError(`--serve-uri is for records over ${MAX_FILE} bytes; this one is ${out.bytes} and travels as a data URI`);
  if (o.out) writeFileSync(o.out, out.file);
  const uri = out.entry.feedbackURI ?? o["serve-uri"];
  const calldata = uri ? giveFeedbackCalldata(o.agent, out.entry, uri) : null;
  if (o.calldata && calldata) console.log(calldata);
  else console.log(JSON.stringify({
    task: o.task, outcome: out.outcome, bytes: out.bytes, feedbackHash: out.entry.feedbackHash,
    giveFeedback: { agentId: Number(o.agent), value: out.entry.value, valueDecimals: 0, tag1: out.entry.tag1, tag2: out.entry.tag2, endpoint: "", feedbackURI: uri ?? null, feedbackHash: out.entry.feedbackHash },
    calldata, file: out.file,
  }, null, 2));
  if (!uri) {
    console.error(`nothing to post yet: the record is ${out.bytes} bytes; serve the file at an https:// or ipfs:// URI and pass it as --serve-uri`);
    return NOTHING_TO_POST;
  }
  return 0;
}

/** Rebuilds one record's task from the pinned descriptor and checks it, its createdAt and its transfers. */
async function verifyRecord(rec, { pins, rpcs, latest, span }) {
  const pinned = pinnedFor(pins, rec.work.source);
  const url = rpcs.get(rec.work.source.chainId);
  if (!pinned) return { errors: [`no --descriptor held for ${rec.work.source.chainId}:${rec.work.source.contract}`] };
  if (!url) return { errors: [`no --rpc for chain ${rec.work.source.chainId}`] };
  await onChain(url, pinned.chainId, `the source ${pinned.contract}`);
  const compiled = compileSource(pinned);
  const logs = await taskLogs(url, compiled, rec.work.task, await head(url), span);
  const lateBlocks = new Set();
  for (const l of logs) {
    const b = Number(BigInt(l.blockNumber));
    if ((await blockTime(url, b)) > latest) lateBlocks.add(b);
  }
  const result = checkRecord(rec, { pinned, logs, isLate: (b) => lateBlocks.has(b) });
  if (result.errors.length) return result;
  const late = createdAtProblem(rec.createdAt, await blockTime(url, result.found.steps.at(-1).block), latest);
  if (late) result.errors.push(late);
  result.errors.push(...(await fundsErrors(url, pinned, result.found)));
  return result;
}

async function check(o) {
  if (!!o.file === !!o.uri) usageError("give --file, or --uri with --hash");
  if (o.uri && !o.hash) usageError("--uri needs --hash");
  const bytes = o.file ? new Uint8Array(readLocal(o.file)) : await fileBytes(o.uri, o["ipfs-gateway"]);
  const hash = o.hash ?? keccak256(bytes);
  const label = o.file ?? "the record at --uri";
  let rec;
  try {
    rec = readFile(bytes, hash);
  } catch (e) {
    console.log(e.message === "the record bytes are not valid JSON" ? `FAIL: ${label} is not valid JSON` : `FAIL: ${label}: ${e.message}`);
    return 1;
  }
  const pins = loadDescriptors([o.descriptor]);
  const result = await verifyRecord(rec, { pins, rpcs: new Map([[rec.work.source.chainId, o.rpc]]), latest: Math.floor(Date.now() / 1000) });
  const subject = `task ${rec.work.task} at ${rec.work.source.contract}`;
  if (result.errors.length) line("FAIL", subject, result.errors);
  else line("ok", `${subject} (${labelOf(rec)})`, [], [`feedbackHash ${hash}`, `agent ${rec.agentId} and the binding are checked only against an entry, by the entries command`]);
  return result.errors.length ? 1 : 0;
}

/** The agent's work.workers value at an entry, from the Identity Registry's MetadataSet logs: no archive node needed. */
const declarations = new Map();
async function declaredValue(url, identity, agentId, at, span) {
  const key = `${identity}:${agentId}`;
  if (!declarations.has(key)) {
    const topics = [METADATA_SET.topic, topicOf(agentId), keccak256("work.workers")];
    declarations.set(key, await getLogs(url, { address: identity, topics }, 0, await head(url), span));
  }
  const before = declarations.get(key).filter((l) => {
    const [b, i] = [Number(BigInt(l.blockNumber)), Number(BigInt(l.logIndex))];
    return b < at.block || (b === at.block && i < at.logIndex);
  });
  return before.length ? metadataValue(before.at(-1)) : "0x";
}

/** Why an entry cannot count because the agent paid for its own task: its client is the agent's owner or agentWallet. */
async function selfPaid(rec, url, at) {
  const identity = rec.agentRegistry.split(":")[2];
  const client = rec.work.steps.find((s) => s.step === "funded").client;
  for (const [sig, who] of [["ownerOf(uint256)", "owner"], ["getAgentWallet(uint256)", "agentWallet"]]) {
    try {
      if (BigInt(await call(url, identity, encodeCall(sig, [rec.agentId]), at.block)) === BigInt(client)) return `the task's client is the agent's ${who}: the agent paid for its own task`;
    } catch (e) {
      if (noHistory(e)) return `checking the client against the agent's ${who} needs state at block ${at.block}, which ${new URL(url).host} no longer serves; use an archive endpoint`;
      if (!isRevert(e)) throw e;
    }
  }
  return undefined;
}

async function bindingOf(rec, url, at, span) {
  const identity = rec.agentRegistry.split(":")[2];
  const { chainId, contract } = rec.work.source;
  const value = await declaredValue(url, identity, rec.agentId, at, span);
  let declared;
  try {
    declared = decodeWorkers(value);
  } catch (e) {
    return { binding: "writer", note: `undecodable work.workers metadata: ${e.message}` };
  }
  if (declared.some((w) => w.chainId === chainId && w.source === contract && w.worker === rec.work.worker)) return { binding: "declared" };
  const walletTyped = [...compileSource(rec.work.source).byTopic.values()].some((e) => e.actor && e.map.worker?.type === "address");
  if (!walletTyped) return { binding: "writer" };
  for (const sig of ["ownerOf(uint256)", "getAgentWallet(uint256)"]) {
    try {
      if (BigInt(await call(url, identity, encodeCall(sig, [rec.agentId]), at.block)) === BigInt(rec.work.worker)) return { binding: "wallet" };
    } catch (e) {
      if (noHistory(e)) return { binding: "writer", note: `the wallet binding needs state at block ${at.block}, which ${new URL(url).host} no longer serves; use an archive endpoint` };
      if (!isRevert(e)) throw e;
    }
  }
  return { binding: "writer" };
}

async function registryOf(url, reputation) {
  const [, chain, address] = reputation.split(":");
  await onChain(url, Number(chain), "--reputation");
  const at = await head(url);
  const notRegistry = `${address} on chain ${chain} is not an ERC-8004 Reputation Registry`;
  if ((await rpc(url, "eth_getCode", [address, "latest"])) === "0x") throw new Error(`${notRegistry}: it has no code`);
  let returned;
  try {
    returned = await call(url, address, encodeCall("getIdentityRegistry()", []), at);
  } catch (e) {
    if (isRevert(e)) throw new Error(`${notRegistry}: getIdentityRegistry() reverted`);
    throw e;
  }
  if (!/^0x0{24}[0-9a-fA-F]{40}$/.test(returned) || BigInt(returned) === 0n) throw new Error(`${notRegistry}: getIdentityRegistry() returned no address`);
  return { chain: Number(chain), address, at, agentRegistry: `eip155:${chain}:${checksum("0x" + returned.slice(26))}` };
}

async function entries(o) {
  const url = o["registry-rpc"];
  const pins = loadDescriptors(o.descriptor);
  const rpcs = new Map(o.rpc ?? []);
  const span = o.span ? Number(o.span) : undefined;
  const reg = await registryOf(url, o.reputation);
  const agent = BigInt(o.agent);
  const writerTopic = "0x" + o.writer.slice(2).toLowerCase().padStart(64, "0");
  const all = (await getLogs(url, { address: reg.address, topics: [NEW_FEEDBACK.topic, topicOf(agent), writerTopic] }, o["from-block"], reg.at, span)).map(decodeFeedback);
  const last = BigInt(await call(url, reg.address, encodeCall("getLastIndex(uint256,address)", [agent, o.writer]), reg.at));
  let failures = 0;
  const gaps = indexGaps(all.map((f) => f.feedbackIndex), last);
  if (gaps.length) {
    failures++;
    line("FAIL", `entries of agent ${agent} from ${o.writer}`, [`feedbackIndex ${gaps.join(", ")} missing (last is ${last}); start --from-block at the registry's deployment block`]);
  }
  const work = all.filter((f) => PROFILE_TAGS.includes(f.tag1));
  const elsewhere = [];
  let unmatched = 0;
  if (work.length) {
    const theirs = [];
    // One value per topic position: endpoints allow far narrower ranges for queries that list several.
    for (const tag of PROFILE_TAGS) theirs.push(...(await getLogs(url, { address: reg.address, topics: [NEW_FEEDBACK.topic, null, writerTopic, keccak256(tag)] }, o["from-block"], reg.at, span)));
    for (const f of theirs.map(decodeFeedback).filter((x) => x.agentId !== agent)) {
      let other;
      try {
        other = readFile(await fileBytes(f.feedbackURI, o["ipfs-gateway"]), f.feedbackHash);
      } catch (e) {
        if (e.code !== undefined) throw e;
        unmatched++;
        continue;
      }
      elsewhere.push({ key: keyOf(other), agentId: f.agentId });
    }
  }
  const checked = [];
  let unbound = 0;
  for (const f of work) {
    const subject = `entry ${f.feedbackIndex}`;
    const feedback = decodeReadFeedback(await call(url, reg.address, encodeCall("readFeedback(uint256,address,uint64)", [agent, o.writer, f.feedbackIndex]), reg.at));
    if (feedback.isRevoked) {
      failures++;
      line("FAIL", `${subject} (revoked)`, ["the writer revoked it; a writer must not revoke, and the task counts as having no entry"]);
      continue;
    }
    let rec;
    try {
      rec = readFile(await fileBytes(f.feedbackURI, o["ipfs-gateway"]), f.feedbackHash, {
        agentRegistry: reg.agentRegistry, agentId: f.agentId, clientAddress: `eip155:${reg.chain}:${f.clientAddress}`, tag1: f.tag1, tag2: f.tag2, value: f.value, valueDecimals: f.valueDecimals,
      });
    } catch (e) {
      failures++;
      line("FAIL", subject, [e.message]);
      continue;
    }
    const label = `${subject} (task ${rec.work.task})`;
    const { errors } = await verifyRecord(rec, { pins, rpcs, latest: await blockTime(url, f.blockNumber), span });
    const others = otherAgents(new Set([keyOf(rec)]), agent, elsewhere).get(keyOf(rec));
    if (others) errors.push(`the writer also posted task ${rec.work.task} for agent ${others.join(", ")}`);
    if (!errors.length) {
      const own = await selfPaid(rec, url, { block: f.blockNumber });
      if (own) errors.push(own);
    }
    if (errors.length) {
      failures++;
      line("FAIL", label, errors);
      continue;
    }
    const { binding, note } = await bindingOf(rec, url, { block: f.blockNumber, logIndex: f.logIndex }, span);
    checked.push({ rec, feedbackIndex: f.feedbackIndex });
    if (binding === "writer") {
      unbound++;
      line("unbound", `${label}, ${labelOf(rec)}`, ["bound only by the writer's word; the agent declares no such worker"], note ? [note] : []);
    } else line("ok", `${label}, ${labelOf(rec)}, binding ${binding}`);
  }
  for (const d of findDuplicates(checked.map((c) => c.rec))) {
    failures++;
    line("FAIL", `task ${d.key}`, [`posted twice by this writer, in entries ${d.at.map((i) => checked[i].feedbackIndex).join(" and ")}`]);
  }
  if (o.rebuild) failures += await coverage(checked, { pins, rpcs, span, registryTime: await blockTime(url, reg.at) });
  if (unmatched) console.log(`note    ${unmatched} ${unmatched === 1 ? "entry" : "entries"} of this writer about other agents could not be read, so duplicates with them were not checked`);
  console.log(`${all.length} entries, ${work.length} under ${TAG1} or ${LAPSED}, ${unbound} unbound${unbound ? " (unbound entries pass, but rest on the writer's word alone)" : ""}`);
  if (!work.length) console.error(`no ${TAG1} or ${LAPSED} entries from ${o.writer} about agent ${agent}`);
  else if (failures) console.error(`${failures} ${failures === 1 ? "check" : "checks"} failed`);
  return failures || !work.length ? 1 : 0;
}

/** Every task of each worker the writer used, settled since its first entry for that worker, needs an entry once due. */
async function coverage(checked, { pins, rpcs, span, registryTime }) {
  const covered = new Set(checked.map(({ rec }) => keyOf(rec)));
  const since = new Map();
  for (const { rec } of checked) {
    const key = `${rec.work.source.chainId}:${lower(rec.work.source.contract)}:${rec.work.worker}`;
    const block = rec.work.steps.at(-1).block;
    if (!since.has(key) || since.get(key).block > block) since.set(key, { block, rec });
  }
  let failures = 0;
  for (const { block, rec } of since.values()) {
    const pinned = pinnedFor(pins, rec.work.source);
    const url = rpcs.get(pinned.chainId);
    const compiled = compileSource(pinned);
    const fin = await finalizedHead(url, pinned);
    const terminal = [...compiled.byTopic].filter(([, e]) => e.step === "paid" || e.step === "refunded").map(([t]) => t);
    const settledLogs = await getLogs(url, { address: pinned.contract, topics: [terminal] }, block, fin.number, span);
    for (const task of new Set(settledLogs.map((l) => BigInt(l.topics[1])))) {
      if (covered.has(taskKey(pinned, task))) continue;
      const logs = await taskLogs(url, compiled, task, fin.number, span);
      const found = stepsOf(compiled, logs, task);
      const judged = judge(found);
      if (judged.worker !== rec.work.worker || !entryOf(judged) || judged.problems.length) continue;
      const settledAt = await blockTime(url, found.steps.at(-1).block);
      const age = Math.max(fin.time, registryTime) - settledAt;
      if (isDue(settledAt, fin.time, registryTime)) {
        failures++;
        line("FAIL", `task ${task} at ${pinned.contract} (${outcomeLabel(judged)})`, [`no entry from the writer, ${duration(age)} past the terminal step`]);
      } else line("wait", `task ${task} at ${pinned.contract} (${outcomeLabel(judged)})`, [`terminal step ${duration(age)} ago; the entry is due in ${duration(DUE_SECONDS - age)}`]);
    }
  }
  return failures;
}

async function vectors(o) {
  const file = JSON.parse(readFileSync(new URL("vectors.json", HERE), "utf8"));
  const verify = new Map(o.verify ?? []);
  for (const chainId of verify.keys()) {
    if (!Object.values(file.sources).some((s) => s.chainId === chainId)) throw new Error(`vectors.json has no vectors for chain ${chainId}`);
  }
  let failures = 0;
  for (const v of file.valid) {
    const source = file.sources[v.source];
    const errors = [];
    const out = buildRecord({ source, logs: v.logs, task: v.task, head: v.head, terminalTime: v.terminalTime });
    if (out.outcome !== v.expect.outcome) errors.push(`outcome ${out.outcome}`);
    if (v.expect.entry === null ? out.entry !== null : out.entry?.feedbackHash !== v.expect.feedbackHash || out.file !== v.expect.file) errors.push("record bytes or hash differ");
    const url = verify.get(source.chainId);
    if (url) {
      await onChain(url, source.chainId, `the vectors' source`);
      const compiled = compileSource(source);
      const live = await taskLogs(url, compiled, v.task, await head(url));
      const strip = (ls) => ls.map((l) => ({ address: lower(l.address), blockNumber: Number(BigInt(l.blockNumber)), transactionHash: lower(l.transactionHash), logIndex: Number(BigInt(l.logIndex)), topics: l.topics.map(lower) }));
      if (JSON.stringify(strip(live)) !== JSON.stringify(strip(v.logs))) errors.push("stored logs differ from the chain's");
      for (const [i, l] of live.entries()) {
        const stored = v.logs[i];
        if (stored && (keccak256(hexToBytes(l.data)) !== stored.dataHash || !lower(l.data).startsWith(lower(stored.data)))) errors.push(`log ${i}: data differs from the chain's`);
      }
      const found = stepsOf(compiled, v.logs, v.task);
      if (found.settled && (await blockTime(url, found.steps.at(-1).block)) !== v.terminalTime) errors.push("terminalTime differs from the chain's");
      if (found.settled && found.steps.some((s) => s.step === "funded")) errors.push(...(await fundsErrors(url, source, found)));
    }
    if (errors.length) failures++;
    line(errors.length ? "FAIL" : "ok", `${v.name}${url ? " (verified on chain)" : ""}`, errors.length ? errors : [outcomeLabel(out)]);
  }
  if (failures) console.error(`${failures} ${failures === 1 ? "vector" : "vectors"} failed`);
  else console.log(`all ${file.valid.length} vectors pass; the ${file.invalid.length} invalid cases run in test.mjs`);
  return failures ? 1 : 0;
}

const [name, ...rest] = process.argv.slice(2);
if (name === "--help" || name === "-h") {
  console.log(`node cli.mjs <${Object.keys(COMMANDS).join("|")}> [flags]; node cli.mjs <command> --help for its flags.\nExit codes: 0 every check passed, 1 a check failed or an error, 2 usage, 3 nothing to post.`);
  process.exitCode = 0;
} else if (!Object.hasOwn(COMMANDS, name ?? "")) {
  console.error(`usage: node cli.mjs <${Object.keys(COMMANDS).join("|")}> [flags], or node cli.mjs <command> --help`);
  process.exitCode = 2;
} else {
  try {
    const o = parseArgs(name, rest);
    if (o.help) usage(name);
    else process.exitCode = await { build, check, entries, vectors }[name](o);
  } catch (e) {
    console.error(e instanceof UsageError ? `usage: ${e.message} (node cli.mjs ${name} --help)` : e.message);
    process.exitCode = e instanceof UsageError ? 2 : 1;
  }
}
