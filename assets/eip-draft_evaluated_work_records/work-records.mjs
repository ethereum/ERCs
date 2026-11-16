// Evaluated Work Records: descriptors, steps, outcomes, record files and reader rules.
// Pure: no network access and no dependencies. Node.js 18 or later.

const MASK = (1n << 64n) - 1n;
const RC = [
  0x0000000000000001n, 0x0000000000008082n, 0x800000000000808an, 0x8000000080008000n, 0x000000000000808bn,
  0x0000000080000001n, 0x8000000080008081n, 0x8000000000008009n, 0x000000000000008an, 0x0000000000000088n,
  0x0000000080008009n, 0x000000008000000an, 0x000000008000808bn, 0x800000000000008bn, 0x8000000000008089n,
  0x8000000000008003n, 0x8000000000008002n, 0x8000000000000080n, 0x000000000000800an, 0x800000008000000an,
  0x8000000080008081n, 0x8000000000008080n, 0x0000000080000001n, 0x8000000080008008n,
];
const ROT = [[0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61], [28, 55, 25, 21, 56], [27, 20, 39, 8, 14]];
const rotl = (v, n) => (n === 0 ? v : ((v << BigInt(n)) | (v >> BigInt(64 - n))) & MASK);

function permute(s) {
  for (const rc of RC) {
    const c = [0, 1, 2, 3, 4].map((x) => s[x] ^ s[x + 5] ^ s[x + 10] ^ s[x + 15] ^ s[x + 20]);
    for (let x = 0; x < 5; x++) {
      const d = c[(x + 4) % 5] ^ rotl(c[(x + 1) % 5], 1);
      for (let y = 0; y < 25; y += 5) s[x + y] ^= d;
    }
    const b = new Array(25);
    for (let x = 0; x < 5; x++) for (let y = 0; y < 5; y++) b[y + 5 * ((2 * x + 3 * y) % 5)] = rotl(s[x + 5 * y], ROT[x][y]);
    for (let x = 0; x < 5; x++) {
      for (let y = 0; y < 25; y += 5) s[x + y] = b[x + y] ^ (~b[((x + 1) % 5) + y] & MASK & b[((x + 2) % 5) + y]);
    }
    s[0] ^= rc;
  }
}

/** keccak256 of a UTF-8 string or of bytes, as 0x-prefixed hex. */
export function keccak256(input) {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  const rate = 136;
  const padded = new Uint8Array((Math.floor(bytes.length / rate) + 1) * rate);
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
  let out = "0x";
  for (let i = 0; i < 4; i++) for (let k = 0; k < 8; k++) out += Number((s[i] >> BigInt(8 * k)) & 0xffn).toString(16).padStart(2, "0");
  return out;
}

export function hexToBytes(hex) {
  if (typeof hex !== "string" || !/^0x([0-9a-fA-F]{2})*$/.test(hex)) throw new Error(`${String(hex).slice(0, 20)} is not hex bytes`);
  return Uint8Array.from(Buffer.from(hex.slice(2), "hex"));
}

export function checksum(address) {
  if (typeof address !== "string" || !/^0x[0-9a-fA-F]{40}$/.test(address)) throw new Error(`not an address: ${address}`);
  const lower = address.slice(2).toLowerCase();
  const hash = keccak256(lower);
  return "0x" + [...lower].map((ch, i) => (parseInt(hash[i + 2], 16) >= 8 ? ch.toUpperCase() : ch)).join("");
}

/** An address as a user types it: all lowercase, or with a correct ERC-55 checksum. Returns the checksummed form. */
export function parseAddress(value) {
  if (typeof value !== "string" || !/^0x[0-9a-fA-F]{40}$/.test(value)) throw new Error(`not an address: ${value}`);
  if (/^0x[0-9a-f]{40}$/.test(value)) return checksum(value);
  if (checksum(value) !== value) throw new Error(`${value} has a wrong ERC-55 checksum (expected ${checksum(value)}); check for a typo`);
  return value;
}

const LONE_SURROGATE = /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/;

/** RFC 8785 (JCS) for the values a record holds: objects, arrays, strings, booleans, null and safe integers. */
export function canonical(value) {
  if (value === null || typeof value === "boolean") return JSON.stringify(value);
  if (typeof value === "string") {
    if (LONE_SURROGATE.test(value)) throw new Error("a string holds a lone surrogate");
    return JSON.stringify(value);
  }
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value) || value < 0) throw new Error(`not an integer from 0 to 2^53 - 1: ${value}`);
    return String(value);
  }
  if (Array.isArray(value)) {
    for (let i = 0; i < value.length; i++) if (!(i in value)) throw new Error("an array is sparse");
    return `[${value.map(canonical).join(",")}]`;
  }
  if (typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype) {
    return `{${Object.keys(value).sort().map((k) => `${canonical(k)}:${canonical(value[k])}`).join(",")}}`;
  }
  throw new Error(`canonical JSON cannot hold a ${typeof value}`);
}

export const STEPS = {
  funded: { required: ["task", "client", "amount"], optional: ["brief"] },
  assigned: { required: ["task", "worker"], optional: [] },
  delivered: { required: ["task", "worker"], optional: ["result"] },
  verdict: { required: ["task", "accepted"], optional: ["ref", "evaluator"] },
  challenge: { required: ["task"], optional: ["by", "bond"] },
  paid: { required: ["task", "to", "amount"], optional: ["worker", "fee"] },
  refunded: { required: ["task", "to", "amount"], optional: [] },
};
const TERMINAL = new Set(["paid", "refunded"]);
const REQUIRED_STEPS = ["funded", "delivered", "verdict", "paid", "refunded"];
export const ENTRY = { accepted: 100, rejected: 0, undelivered: 0 };
export const TAG1 = "work.outcome";
export const VERSION = "work-record/v1";
export const URI_PREFIX = "data:application/json;base64,";
export const MAX_FILE = 8192;
export const DUE_SECONDS = 72 * 3600;
const takesEntry = (outcome) => Object.hasOwn(ENTRY, outcome);
const a = (word) => `${/^[aeiu]/.test(word) ? "an" : "a"} ${word}`;

const SIZES = Array.from({ length: 32 }, (_, i) => String(8 * (i + 1)));
const isUint = (t) => t.startsWith("uint") && SIZES.includes(t.slice(4));
const isInt = (t) => t.startsWith("int") && SIZES.includes(t.slice(3));
const isBytesN = (t) => /^bytes([1-9]|[12]\d|3[0-2])$/.test(t);
const isElementary = (t) => isUint(t) || isInt(t) || isBytesN(t) || ["address", "bool", "bytes", "string"].includes(t);
const FIELD_TYPE = {
  task: (t) => t === "uint256",
  client: (t) => t === "address",
  to: (t) => t === "address",
  by: (t) => t === "address",
  evaluator: (t) => t === "address",
  worker: (t) => t === "address" || t === "bytes32",
  amount: isUint,
  fee: isUint,
  bond: isUint,
  brief: (t) => t === "bytes32" || isUint(t),
  result: (t) => t === "bytes32" || isUint(t),
  ref: (t) => t === "bytes32" || isUint(t),
  accepted: (t) => t === "bool",
};

/**
 * Parses `Name(type [indexed] name, ...)`: canonical ABI type names, elementary types or their dynamic arrays, no
 * static arrays or tuples, at most three indexed parameters.
 */
export function parseEvent(signature) {
  const m = /^([A-Za-z_][A-Za-z0-9_]*)\((.*)\)$/.exec(signature);
  if (!m) throw new Error(`${signature} is not an event signature`);
  const params = m[2] === "" ? [] : m[2].split(", ").map((p) => {
    const parts = p.split(" ");
    const indexed = parts.length === 3 && parts[1] === "indexed";
    const [type, name] = [parts[0], parts.at(-1)];
    const base = type.replace(/(\[\])+$/, "");
    if (!(parts.length === 2 || indexed) || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(name) || name === "indexed") {
      throw new Error(`"${p}" in ${signature} is not of the form "type [indexed] name"`);
    }
    if (!isElementary(base)) throw new Error(`type "${type}" is not a canonical ABI type this profile accepts, in ${signature}`);
    return { type, indexed, name, dynamic: base !== type || base === "bytes" || base === "string" };
  });
  if (new Set(params.map((p) => p.name)).size !== params.length) throw new Error(`${signature} repeats a parameter name`);
  if (params.filter((p) => p.indexed).length > 3) throw new Error(`${signature} has more than three indexed parameters`);
  const topic = keccak256(`${m[1]}(${params.map((p) => p.type).join(",")})`);
  return { name: m[1], params, topic };
}

const isPlain = (v) => v !== null && typeof v === "object" && Object.getPrototypeOf(v) === Object.prototype;
const exactKeys = (obj, keys, optional, what) => {
  if (!isPlain(obj)) throw new Error(`${what} must be a JSON object`);
  for (const k of keys) if (!Object.hasOwn(obj, k)) throw new Error(`${what} lacks the field ${k}`);
  for (const k of Object.keys(obj)) if (!keys.includes(k) && !optional.includes(k)) throw new Error(`${what} has a field this profile does not define: ${k}`);
};

/** Checks a source descriptor and compiles it for decoding. Throws on the first rule it breaks. */
export function compileSource(source) {
  exactKeys(source, ["chainId", "contract", "asset", "fromBlock", "finality", "events"], [], "source");
  if (!Number.isSafeInteger(source.chainId) || source.chainId <= 0) throw new Error("the source's chainId must be a positive integer");
  if (!Number.isSafeInteger(source.fromBlock) || source.fromBlock < 0) throw new Error("the source's fromBlock must be a block number");
  if (source.finality !== "finalized" && !(Number.isSafeInteger(source.finality) && source.finality > 0)) {
    throw new Error('the source\'s finality must be "finalized" or a confirmation depth above 0');
  }
  if (checksum(source.contract) !== source.contract) throw new Error("the source's contract must be an ERC-55 checksummed address");
  const asset = /^eip155:(\d+)\/erc20:(0x[0-9a-fA-F]{40})$/.exec(source.asset);
  if (!asset || Number(asset[1]) !== source.chainId || checksum(asset[2]) !== asset[2]) throw new Error("the source's asset must be eip155:<chainId>/erc20:<ERC-55 address> on the source's chain");
  if (!Array.isArray(source.events)) throw new Error("the source's events must be an array");
  const byTopic = new Map();
  for (const entry of source.events) {
    exactKeys(entry, ["step", "event", "fields"], ["actor", "feeIncluded"], "event entry");
    if (!Object.hasOwn(STEPS, entry.step)) throw new Error(`${entry.step} is not a step this profile defines`);
    const rule = STEPS[entry.step];
    const event = parseEvent(entry.event);
    if (byTopic.has(event.topic)) throw new Error(`the topic of ${entry.event} is declared twice`);
    exactKeys(entry.fields, rule.required, rule.optional, `fields of ${event.name}`);
    if (Object.hasOwn(entry, "actor") && entry.actor !== "worker") throw new Error(`the actor of ${event.name} must be "worker"`);
    if (Object.hasOwn(entry, "feeIncluded") && (entry.step !== "paid" || !Object.hasOwn(entry.fields, "fee") || typeof entry.feeIncluded !== "boolean")) {
      throw new Error(`feeIncluded on ${event.name} must be a boolean on a paid event that maps fee`);
    }
    const firstIndexed = event.params.find((p) => p.indexed);
    if (!firstIndexed || entry.fields.task !== firstIndexed.name || firstIndexed.type !== "uint256") {
      throw new Error(`the task field of ${event.name} must name its first indexed parameter, a uint256`);
    }
    const map = {};
    for (const [field, target] of Object.entries(entry.fields)) {
      if (field === "accepted" && typeof target === "boolean") {
        map[field] = { literal: target };
        continue;
      }
      const param = event.params.find((p) => p.name === target);
      if (!param) throw new Error(`${event.name} has no parameter named ${target}`);
      if (!FIELD_TYPE[field](param.type)) throw new Error(`${event.name}.${target} is a ${param.type}, which cannot hold ${field}`);
      map[field] = { param, type: param.type };
    }
    byTopic.set(event.topic, { step: entry.step, event, map, actor: entry.actor === "worker", feeIncluded: entry.feeIncluded === true });
  }
  for (const step of REQUIRED_STEPS) {
    if (![...byTopic.values()].some((e) => e.step === step)) throw new Error(`the descriptor declares no event for the ${step} step`);
  }
  return { source, byTopic, contract: source.contract.toLowerCase() };
}

const word = (hex, i) => {
  const w = hex.slice(2 + 64 * i, 2 + 64 * (i + 1));
  if (w.length !== 64) throw new Error("a log's data ends before a word it should hold");
  return w;
};

function decodeWord(w, type) {
  const v = BigInt("0x" + w);
  if (type === "address") {
    if (v >> 160n) throw new Error("an address word has bits set above its 20 bytes");
    return checksum("0x" + w.slice(24));
  }
  if (type === "bool") {
    if (v > 1n) throw new Error("a bool word holds a value other than 0 or 1");
    return v === 1n;
  }
  if (type === "bytes32") return "0x" + w.toLowerCase();
  if (v >> BigInt(type.slice(4))) throw new Error(`a value does not fit in a ${type}`);
  return v;
}

const hex32 = (v) => "0x" + v.toString(16).padStart(64, "0");
const ADDRESS_FIELDS = ["client", "to", "by", "evaluator"];

function formatField(field, value, type) {
  if (field === "task" || field === "accepted" || ADDRESS_FIELDS.includes(field)) return value;
  if (field === "amount" || field === "fee" || field === "bond") return value.toString();
  if (type === "address") return "0x" + value.slice(2).toLowerCase().padStart(64, "0");
  return typeof value === "bigint" ? hex32(value) : value;
}

/** Decodes one log against a compiled source: `{ entry, task, fields }`, or undefined for a log it does not declare. */
export function decodeLog(compiled, log) {
  const entry = compiled.byTopic.get(String(log.topics[0]).toLowerCase());
  if (!entry || String(log.address).toLowerCase() !== compiled.contract) return undefined;
  const indexed = entry.event.params.filter((p) => p.indexed);
  const unindexed = entry.event.params.filter((p) => !p.indexed);
  if (log.topics.length !== 1 + indexed.length) throw new Error(`a ${entry.event.name} log has the wrong number of topics`);
  const raw = (param) => (param.indexed ? word(log.topics[1 + indexed.indexOf(param)], 0) : word(log.data, unindexed.indexOf(param)));
  const fields = {};
  for (const [field, m] of Object.entries(entry.map)) {
    fields[field] = "literal" in m ? m.literal : formatField(field, decodeWord(raw(m.param), m.type), m.type);
  }
  const task = fields.task;
  delete fields.task;
  return { entry, task, fields };
}

const num = (v) => (typeof v === "string" ? Number(BigInt(v)) : v);
const lower = (s) => String(s).toLowerCase();

/**
 * The steps of one task from the source's logs: every declared log of the task through the end of the transaction
 * holding its first terminal step, and the declared logs after that transaction. `senders` maps a transaction hash to
 * its sender; it is needed only for events the descriptor marks as sent by the worker.
 */
export function stepsOf(compiled, logs, taskId, senders = {}) {
  const task = BigInt(taskId);
  const mine = [];
  const malformed = [];
  for (const log of logs) {
    let d;
    try {
      d = decodeLog(compiled, log);
    } catch (e) {
      if (log.topics[1] !== undefined && BigInt(log.topics[1]) === task) malformed.push(`log ${num(log.logIndex)} in block ${num(log.blockNumber)}: ${e.message}`);
      continue;
    }
    if (d && d.task === task) mine.push({ log, d });
  }
  mine.sort((a, b) => num(a.log.blockNumber) - num(b.log.blockNumber) || num(a.log.logIndex) - num(b.log.logIndex));
  const first = mine.findIndex((x) => TERMINAL.has(x.d.entry.step));
  let end = mine.length;
  if (first >= 0) {
    end = first + 1;
    while (end < mine.length && lower(mine[end].log.transactionHash) === lower(mine[first].log.transactionHash)) end++;
  }
  const toStep = ({ log, d }) => {
    const step = { step: d.entry.step, block: num(log.blockNumber), tx: lower(log.transactionHash), log: num(log.logIndex), ...d.fields };
    if (d.entry.actor) {
      const sender = senders[step.tx];
      if (!sender) throw new Error(`the sender of ${step.tx} is needed, since ${d.entry.event.name} is marked as sent by the worker`);
      step.sender = checksum(sender);
    }
    return step;
  };
  const kept = mine.slice(0, end);
  return { settled: first >= 0, steps: kept.map(toStep), entries: kept.map((x) => x.d.entry), after: mine.slice(end).map(toStep), malformed };
}

/** Drops the logs after the terminal transaction that `isLate(block)` places after the entry: they are the source's problem. */
export const dropLate = (found, isLate) => ({ ...found, after: found.after.filter((s) => !isLate(s.block)) });

/** The task's worker, its outcome, and every consistency rule it breaks. */
export function judge({ settled, steps, entries, after, malformed = [] }) {
  const deliveredAt = steps.flatMap((s, i) => (s.step === "delivered" ? [i] : []));
  const assigned = steps.filter((s) => s.step === "assigned" && BigInt(s.worker) !== 0n);
  const worker = deliveredAt.length ? steps[deliveredAt[0]].worker : assigned.at(-1)?.worker;
  const lastDelivered = deliveredAt.at(-1) ?? -1;
  const verdicts = steps.filter((s, i) => s.step === "verdict" && lastDelivered >= 0 && i > lastDelivered);
  const workerActed = worker !== undefined && steps.some((s) => s.step !== "delivered" && s.sender && BigInt(s.sender) === BigInt(worker));
  let outcome;
  if (!settled) outcome = "unsettled";
  else if (worker === undefined) outcome = "no worker";
  else if (!deliveredAt.length) outcome = workerActed ? "undelivered" : "unstarted";
  else if (!verdicts.length) outcome = "unevaluated";
  else outcome = verdicts.at(-1).accepted ? "accepted" : "rejected";

  const problems = [];
  if (settled && worker !== undefined) {
    const funded = steps.filter((s) => s.step === "funded");
    if (funded.length !== 1) problems.push(`the task has ${funded.length} funded steps`);
    else if (deliveredAt.length && steps.indexOf(funded[0]) > deliveredAt[0]) problems.push("the funded step comes after a delivery");
    const terminals = steps.flatMap((s, i) => (TERMINAL.has(s.step) ? [i] : []));
    if (terminals.length !== 1) problems.push(`the terminal transaction holds ${terminals.length} terminal steps`);
    const t = steps[terminals[0]];
    if ((outcome === "accepted") !== (t.step === "paid")) problems.push(`${a(outcome)} task ends in ${t.step}`);
    if (funded.length === 1) {
      const fee = BigInt(t.fee ?? 0);
      const settledAmount = t.step === "paid" ? (entries[terminals[0]].feeIncluded ? BigInt(t.amount) : BigInt(t.amount) + fee) : BigInt(t.amount);
      if (settledAmount !== BigInt(funded[0].amount)) problems.push(`the terminal step settles ${settledAmount} of ${funded[0].amount} funded`);
    }
    for (const s of steps) {
      if ((s.step === "delivered" || (s.step === "paid" && "worker" in s)) && s.worker !== worker) problems.push(`${a(s.step)} step names another worker`);
    }
    const firstVerdict = steps.findIndex((s) => s.step === "verdict");
    if (steps.some((s, i) => s.step === "challenge" && (firstVerdict < 0 || i < firstVerdict))) problems.push("a challenge comes before any verdict");
    if (after.length) problems.push(`the source emitted ${after.length} declared ${after.length === 1 ? "log" : "logs"} after the terminal transaction`);
    for (const m of malformed) problems.push(`the source emitted a log that does not match its declared event (${m})`);
  }
  return { worker, outcome, problems };
}

export function encodeFile(text) {
  return URI_PREFIX + Buffer.from(text, "utf8").toString("base64");
}

/** Builds the record of one task, or says why the task gets no entry. */
export function buildRecord({ source, logs, task, head, senders, terminalTime, now }) {
  const compiled = compileSource(source);
  const found = stepsOf(compiled, logs, task, senders);
  if (found.steps.length === 0 && found.after.length === 0) throw new Error(`task ${task} has no logs at ${source.contract} on chain ${source.chainId}`);
  const { worker, outcome, problems } = judge(found);
  if (!takesEntry(outcome)) return { outcome, problems, entry: null, reason: `no entry for outcome "${outcome}"` };
  if (problems.length) return { outcome, problems, entry: null, reason: `inconsistent: ${problems.join("; ")}` };
  const record = {
    agentRegistry: head.agentRegistry,
    agentId: head.agentId,
    clientAddress: head.clientAddress,
    createdAt: head.createdAt,
    value: ENTRY[outcome],
    valueDecimals: 0,
    tag1: TAG1,
    tag2: outcome,
    work: { v: VERSION, source, task: BigInt(task).toString(), worker, outcome, steps: found.steps },
  };
  checkHead(record);
  const late = createdAtProblem(record.createdAt, terminalTime, now);
  if (late) throw new Error(late);
  const file = canonical(record);
  const bytes = Buffer.byteLength(file);
  return {
    outcome, problems, record, file, bytes,
    entry: { tag1: TAG1, tag2: outcome, value: ENTRY[outcome], valueDecimals: 0, feedbackURI: bytes <= MAX_FILE ? encodeFile(file) : null, feedbackHash: keccak256(file) },
  };
}

const CAIP10 = /^eip155:(\d+):(0x[0-9a-fA-F]{40})$/;
const DECIMAL = /^(0|[1-9]\d*)$/;
const HASH = /^0x[0-9a-f]{64}$/;

export function validCreatedAt(s) {
  return typeof s === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(s) && !Number.isNaN(Date.parse(s))
    && new Date(s).toISOString() === s.replace("Z", ".000Z");
}

/** createdAt may not precede the terminal block's time, nor follow `latest` (the entry's block time, or now). */
export function createdAtProblem(createdAt, terminalTime, latest) {
  const t = Date.parse(createdAt) / 1000;
  if (terminalTime !== undefined && t < terminalTime) return `createdAt ${createdAt} precedes the terminal step (${new Date(terminalTime * 1000).toISOString().replace(".000", "")})`;
  if (latest !== undefined && t > latest) return `createdAt ${createdAt} lies after ${new Date(latest * 1000).toISOString().replace(".000", "")}`;
  return undefined;
}

function checkSteps(steps) {
  if (!Array.isArray(steps) || steps.length === 0) throw new Error("work.steps must be a non-empty array");
  for (const s of steps) {
    if (!isPlain(s) || !Object.hasOwn(STEPS, s.step)) throw new Error("a step has a kind this profile does not define");
    const rule = STEPS[s.step];
    exactKeys(s, ["step", "block", "tx", "log"], [...rule.required, ...rule.optional, "sender"].filter((k) => k !== "task"), `${s.step} step`);
    if (!Number.isSafeInteger(s.block) || !Number.isSafeInteger(s.log)) throw new Error(`${s.step} step: block and log must be integers`);
    if (!HASH.test(s.tx)) throw new Error(`${s.step} step: tx must be a 32-byte hash in lowercase hex`);
    for (const [k, v] of Object.entries(s)) {
      const at = `${s.step}.${k}`;
      if (["amount", "fee", "bond"].includes(k) && !(typeof v === "string" && DECIMAL.test(v))) throw new Error(`${at} must be a decimal string without leading zeros`);
      if (["worker", "brief", "result", "ref"].includes(k) && !HASH.test(v)) throw new Error(`${at} must be 32 bytes in lowercase hex`);
      if ([...ADDRESS_FIELDS, "sender"].includes(k) && !(typeof v === "string" && /^0x[0-9a-fA-F]{40}$/.test(v) && checksum(v) === v)) throw new Error(`${at} must be an ERC-55 checksummed address`);
      if (k === "accepted" && typeof v !== "boolean") throw new Error(`${at} must be a JSON boolean`);
    }
  }
}

function checkHead(rec) {
  exactKeys(rec, ["agentRegistry", "agentId", "clientAddress", "createdAt", "value", "valueDecimals", "tag1", "tag2", "work"], [], "record");
  for (const k of ["agentRegistry", "clientAddress"]) {
    const m = CAIP10.exec(rec[k]);
    if (!m || checksum(m[2]) !== m[2]) throw new Error(`${k} is not a CAIP-10 id with an ERC-55 checksummed address`);
  }
  if (CAIP10.exec(rec.agentRegistry)[1] !== CAIP10.exec(rec.clientAddress)[1]) throw new Error("agentRegistry and clientAddress must be on the same chain");
  if (!Number.isSafeInteger(rec.agentId) || rec.agentId < 0) throw new Error("agentId must be a JSON integer no larger than 2^53 - 1");
  if (!validCreatedAt(rec.createdAt)) throw new Error("createdAt must be RFC 3339 in UTC to the second, as YYYY-MM-DDThh:mm:ssZ");
  if (rec.tag1 !== TAG1 || !takesEntry(rec.tag2) || rec.value !== ENTRY[rec.tag2] || rec.valueDecimals !== 0) {
    throw new Error("tag1, tag2, value and valueDecimals do not follow the profile");
  }
  exactKeys(rec.work, ["v", "source", "task", "worker", "outcome", "steps"], [], "work");
  if (rec.work.v !== VERSION) throw new Error(`work.v must be ${VERSION}`);
  if (!DECIMAL.test(rec.work.task)) throw new Error("work.task must be a decimal string");
  if (!HASH.test(rec.work.worker)) throw new Error("work.worker must be 32 bytes in lowercase hex");
  if (rec.work.outcome !== rec.tag2) throw new Error("work.outcome must equal tag2");
  checkSteps(rec.work.steps);
}

/** The bytes a `data:` URI carries, refusing any other spelling than the canonical base64. */
export function dataUriBytes(feedbackURI) {
  if (!feedbackURI.startsWith(URI_PREFIX)) throw new Error("feedbackURI is not a base64 JSON data: URI");
  const b64 = feedbackURI.slice(URI_PREFIX.length);
  const bytes = Buffer.from(b64, "base64");
  if (bytes.toString("base64") !== b64) throw new Error("the base64 in feedbackURI is not canonical");
  if (bytes.length > MAX_FILE) throw new Error(`a data: URI carries ${bytes.length} bytes, more than ${MAX_FILE}`);
  return new Uint8Array(bytes);
}

/**
 * Reads a record file: the hash, BOM-free UTF-8, canonical bytes and the record's own fields. `entry` holds what the
 * registry logged: agentRegistry, agentId, clientAddress, tag1, tag2, value, valueDecimals.
 */
export function readFile(bytes, feedbackHash, entry) {
  if (keccak256(bytes) !== lower(feedbackHash)) throw new Error("feedbackHash is not keccak256 of the record bytes");
  if (bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) throw new Error("the record bytes start with a byte order mark");
  const text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes);
  let rec;
  try {
    rec = JSON.parse(text);
  } catch (cause) {
    throw new Error("the record bytes are not valid JSON", { cause });
  }
  if (canonical(rec) !== text) throw new Error("the record bytes are not in canonical form");
  checkHead(rec);
  compileSource(rec.work.source);
  if (entry) {
    for (const k of ["agentRegistry", "clientAddress", "tag1", "tag2"]) if (entry[k] !== rec[k]) throw new Error(`${k} in the record differs from the entry`);
    if (BigInt(entry.agentId) !== BigInt(rec.agentId)) throw new Error(`the record names agent ${rec.agentId} but the entry is about agent ${entry.agentId}`);
    if (BigInt(entry.value) !== BigInt(rec.value) || Number(entry.valueDecimals) !== rec.valueDecimals) throw new Error("value or valueDecimals in the record differs from the entry");
  }
  return rec;
}

/** The first difference between a record's steps and the steps rebuilt from the chain. */
export function diffSteps(recorded, rebuilt) {
  for (let i = 0; i < Math.max(recorded.length, rebuilt.length); i++) {
    const [r, c] = [recorded[i], rebuilt[i]];
    if (!r) return `step ${i + 1}: the chain has ${a(c.step)} step (tx ${c.tx}, log ${c.log}) the record leaves out`;
    if (!c) return `step ${i + 1}: the record has ${a(r.step)} step the chain does not`;
    if (r.step !== c.step) return `step ${i + 1}: the record has ${a(r.step)} step where the chain has ${a(c.step)} step (tx ${c.tx}, log ${c.log})`;
    for (const k of new Set([...Object.keys(r), ...Object.keys(c)])) {
      const [a, b] = [r[k], c[k]];
      const same = typeof a === "string" && typeof b === "string" ? a.toLowerCase() === b.toLowerCase() : a === b;
      if (!same) return `step ${i + 1} ${c.step}.${k}: record ${a === undefined ? "(none)" : a}, chain ${b === undefined ? "(none)" : b}`;
    }
  }
  return undefined;
}

/**
 * Checks a record against the reader's pinned descriptor and the task's logs from the descriptor's fromBlock.
 * `isLate(block)` says whether a source block comes after the entry; such logs are not held against the writer.
 */
export function checkRecord(rec, { pinned, logs, senders, isLate = () => false }) {
  if (!pinned) return { errors: [`the reader holds no descriptor for ${rec.work.source.contract} on chain ${rec.work.source.chainId}`] };
  if (canonical(pinned) !== canonical(rec.work.source)) return { errors: ["the record's descriptor differs from the one the reader holds"] };
  const found = dropLate(stepsOf(compileSource(pinned), logs, rec.work.task, senders), isLate);
  const { worker, outcome, problems } = judge(found);
  const errors = [];
  const diff = diffSteps(rec.work.steps, found.steps);
  if (diff) errors.push(diff);
  if (outcome !== rec.work.outcome) errors.push(`outcome is ${outcome}, the record says ${rec.work.outcome}`);
  if (worker !== rec.work.worker) errors.push("worker differs from the source's logs");
  if (problems.length) errors.push(`inconsistent: ${problems.join("; ")}`);
  return { outcome, worker, errors, found };
}

/** The transfers a task's transactions must contain, from its steps and the descriptor entries they came from. */
export function expectedTransfers(source, { steps, entries }) {
  const asset = lower(source.asset.split(":").at(-1));
  const funded = steps.find((s) => s.step === "funded");
  const out = [{ tx: funded.tx, asset, from: funded.client, to: source.contract, amount: BigInt(funded.amount) }];
  for (const [i, s] of steps.entries()) {
    const fee = entries[i].feeIncluded ? BigInt(s.fee ?? 0) : 0n;
    if (s.step === "paid") out.push({ tx: s.tx, asset, from: source.contract, to: s.to, amount: BigInt(s.amount) - fee });
    if (s.step === "refunded") out.push({ tx: s.tx, asset, from: source.contract, to: s.to, amount: BigInt(s.amount) });
  }
  return out;
}

export const TRANSFER_TOPIC = keccak256("Transfer(address,address,uint256)");

export function hasTransfer(receipt, t) {
  return receipt.logs.some((l) => lower(l.address) === t.asset && lower(l.topics[0]) === TRANSFER_TOPIC && l.topics.length === 3
    && BigInt(l.topics[1]) === BigInt(t.from) && BigInt(l.topics[2]) === BigInt(t.to) && BigInt(l.data) === t.amount);
}

/** The key a task is counted once by: its source's chain and contract, and its id. */
export const taskKey = (source, task) => `${source.chainId}:${lower(source.contract)}:${BigInt(task)}`;

/** Tasks with more than one entry: within one writer a failure, across writers counted once. */
export function findDuplicates(records) {
  const byTask = new Map();
  for (const [i, rec] of records.entries()) {
    const key = taskKey(rec.work.source, rec.work.task);
    byTask.set(key, [...(byTask.get(key) ?? []), i]);
  }
  return [...byTask].filter(([, at]) => at.length > 1).map(([key, at]) => ({ key, at }));
}

/** Keys of `mine` (chainId:contract:task) that the writer also posted for another agent: `others` holds { key, agentId }. */
export function otherAgents(mine, agentId, others) {
  const out = new Map();
  for (const o of others) if (mine.has(o.key) && BigInt(o.agentId) !== BigInt(agentId)) out.set(o.key, [...(out.get(o.key) ?? []), o.agentId]);
  return out;
}

export function indexGaps(indexes, lastIndex) {
  const have = new Set(indexes.map(String));
  const gaps = [];
  for (let i = 1n; i <= BigInt(lastIndex); i++) if (!have.has(String(i))) gaps.push(i);
  return gaps;
}

/**
 * Whether a task whose terminal block is final is due: the later of the source's finalized head time and the registry
 * chain's latest block time is at least 72 hours past the terminal block's time, so a source that stops producing
 * blocks cannot hold the clock.
 */
export const isDue = (terminalTime, finalizedTime, registryTime = 0) => Math.max(finalizedTime, registryTime) - terminalTime >= DUE_SECONDS;

const pad = (v) => BigInt.asUintN(256, BigInt(v)).toString(16).padStart(64, "0");

function encodeArg(type, v) {
  if (isUint(type) || isInt(type)) {
    const bits = BigInt(type.replace(/^u?int/, ""));
    const x = BigInt(v);
    const ok = isUint(type) ? x >= 0n && x < 1n << bits : x >= -(1n << (bits - 1n)) && x < 1n << (bits - 1n);
    if (!ok) throw new Error(`${v} is out of range for ${type}`);
    return pad(x);
  }
  if (type === "address") return pad(checksum(v));
  if (type === "bytes32") {
    if (!/^0x[0-9a-fA-F]{64}$/.test(v)) throw new Error(`${v} is not 32 bytes of hex`);
    return v.slice(2).toLowerCase();
  }
  if (type === "bool") return pad(v ? 1 : 0);
  throw new Error(`encodeCall cannot encode a ${type}`);
}

/** ABI-encodes a call by its signature's types: integers, address, bytes32, bool and string. */
export function encodeCall(signature, args) {
  const types = /^\w+\((.*)\)$/.exec(signature)[1].split(",").filter(Boolean);
  if (types.length !== args.length) throw new Error(`${signature} takes ${types.length} arguments`);
  let head = "";
  let tail = "";
  for (const [i, type] of types.entries()) {
    if (type === "string") {
      if (typeof args[i] !== "string") throw new Error(`argument ${i} of ${signature} is not a string`);
      head += pad(32 * types.length + tail.length / 2);
      const hex = Buffer.from(args[i], "utf8").toString("hex");
      tail += pad(hex.length / 2) + hex.padEnd(Math.ceil(hex.length / 64) * 64, "0");
    } else head += encodeArg(type, args[i]);
  }
  return keccak256(signature).slice(0, 10) + head + tail;
}

export function giveFeedbackCalldata(agentId, entry, feedbackURI = entry.feedbackURI) {
  return encodeCall("giveFeedback(uint256,int128,uint8,string,string,string,string,bytes32)", [
    agentId, entry.value, entry.valueDecimals, entry.tag1, entry.tag2, "", feedbackURI, entry.feedbackHash,
  ]);
}

const wordNum = (hex, i) => {
  const v = BigInt("0x" + word(hex, i));
  if (v > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error("an ABI offset or length is too large");
  return Number(v);
};

/** Reads ABI `bytes`/`string` whose offset sits at word `at` of `hex`, with bounds checks. */
function readDynamic(hex, at) {
  const off = wordNum(hex, at);
  if (off % 32) throw new Error("an ABI offset is not a multiple of 32");
  const len = wordNum(hex, off / 32);
  const start = 2 + 2 * (off + 32);
  if (start + 2 * len > hex.length) throw new Error("an ABI length runs past the data");
  return hex.slice(start, start + 2 * len);
}

export const NEW_FEEDBACK = parseEvent(
  "NewFeedback(uint256 indexed agentId, address indexed clientAddress, uint64 feedbackIndex, int128 value, uint8 valueDecimals, string indexed indexedTag1, string tag1, string tag2, string endpoint, string feedbackURI, bytes32 feedbackHash)",
);

export function decodeFeedback(log) {
  const d = log.data;
  const str = (at) => new TextDecoder("utf-8", { fatal: true }).decode(Buffer.from(readDynamic(d, at), "hex"));
  return {
    agentId: BigInt(log.topics[1]),
    clientAddress: checksum("0x" + word(log.topics[2], 0).slice(24)),
    feedbackIndex: BigInt("0x" + word(d, 0)),
    value: BigInt.asIntN(256, BigInt("0x" + word(d, 1))),
    valueDecimals: Number(BigInt("0x" + word(d, 2))),
    tag1: str(3),
    tag2: str(4),
    endpoint: str(5),
    feedbackURI: str(6),
    feedbackHash: "0x" + word(d, 7),
    blockNumber: num(log.blockNumber),
    logIndex: num(log.logIndex),
    transactionHash: lower(log.transactionHash),
  };
}

/** Decodes what readFeedback returns: value, valueDecimals, tag1, tag2 and isRevoked. */
export function decodeReadFeedback(returned) {
  const str = (at) => new TextDecoder("utf-8", { fatal: true }).decode(Buffer.from(readDynamic(returned, at), "hex"));
  const revoked = BigInt("0x" + word(returned, 4));
  if (revoked > 1n) throw new Error("isRevoked holds a value other than 0 or 1");
  return {
    value: BigInt.asIntN(256, BigInt("0x" + word(returned, 0))),
    valueDecimals: Number(BigInt("0x" + word(returned, 1))),
    tag1: str(2),
    tag2: str(3),
    isRevoked: revoked === 1n,
  };
}

export const METADATA_SET = parseEvent("MetadataSet(uint256 indexed agentId, string indexed indexedMetadataKey, string metadataKey, bytes metadataValue)");

export const metadataValue = (log) => "0x" + readDynamic(log.data, 1);

/** Decodes a `work.workers` value, `abi.encode(WorkerRef[])`, with bounds checks. */
export function decodeWorkers(value) {
  if (value === "0x") return [];
  const at = wordNum(value, 0);
  if (at % 32) throw new Error("an ABI offset is not a multiple of 32");
  const n = wordNum(value, at / 32);
  if ((value.length - 2) / 64 < at / 32 + 1 + 3 * n) throw new Error("the WorkerRef[] runs past the data");
  return Array.from({ length: n }, (_, i) => {
    const base = at / 32 + 1 + 3 * i;
    if (BigInt("0x" + word(value, base + 1)) >> 160n) throw new Error("a WorkerRef address has bits set above its 20 bytes");
    return { chainId: wordNum(value, base), source: checksum("0x" + word(value, base + 1).slice(24)), worker: "0x" + word(value, base + 2) };
  });
}
