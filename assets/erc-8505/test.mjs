// Offline tests: node --test test.mjs
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import {
  buildRecord, canonical, checkRecord, checksum, compileSource, createdAtProblem, dataUriBytes, decodeWorkers,
  diffSteps, dropLate, encodeCall, findDuplicates, giveFeedbackCalldata, hexToBytes, indexGaps, isDue, judge, keccak256,
  moneyTasks, otherAgents, parseAddress, parseEvent, readFile, stepsOf, taskKey, TRANSFER_TOPIC, unbackedTransfers,
  validCreatedAt,
} from "./work-records.mjs";

const vectors = JSON.parse(readFileSync(new URL("vectors.json", import.meta.url), "utf8"));
const mainnet = vectors.sources["brainchain-mainnet"];

test("keccak256 known answers", () => {
  assert.equal(keccak256(""), "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470");
  assert.equal(keccak256("abc"), "0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45");
  assert.equal(keccak256("x".repeat(135) + "y".repeat(137)), "0xf9c9d7fc05688ea4e9a1e9ac4363a8bcd4f2fc15f639a1b404481f6921731a28");
});

test("addresses: lowercase or correctly checksummed; a checksum typo is an error", () => {
  assert.equal(checksum("0x44b8464342bbfb9b565fae494dfdefa37d33a211"), "0x44b8464342Bbfb9B565FAE494DfDefa37D33A211");
  assert.equal(parseAddress("0x97d558417c3d61f1074422ad843e1db1e565b952"), "0x97D558417c3D61f1074422AD843e1Db1E565b952");
  assert.equal(parseAddress("0x97D558417c3D61f1074422AD843e1Db1E565b952"), "0x97D558417c3D61f1074422AD843e1Db1E565b952");
  assert.throws(() => parseAddress("0x97D558417c3D61f1074422AD843e1Db1E565B953"), /wrong ERC-55 checksum/);
  assert.throws(() => parseAddress("0x12"), /not an address/);
});

test("strict hex and createdAt", () => {
  assert.throws(() => hexToBytes("0xabc"), /not hex bytes/);
  assert.throws(() => hexToBytes("0xzz"), /not hex bytes/);
  assert.ok(validCreatedAt("2026-11-16T09:00:00Z"));
  for (const s of ["2026-11-16T09:00:00.000Z", "2026-11-16T09:00:00+00:00", "2026-02-30T09:00:00Z", "2026-11-16 09:00:00Z"]) assert.equal(validCreatedAt(s), false, s);
});

test("canonical JSON sorts keys and refuses what JCS cannot carry here", () => {
  assert.equal(canonical({ b: [true, null], a: "x", c: 7 }), '{"a":"x","b":[true,null],"c":7}');
  assert.throws(() => canonical({ a: 1.5 }), /integer/);
  assert.throws(() => canonical({ a: "\ud800" }), /lone surrogate/);
  assert.throws(() => canonical([1, , 3]), /sparse/);
});

test("event grammar: canonical types, exact form, no static arrays or tuples, three indexed at most", () => {
  assert.equal(parseEvent("E(uint256 indexed a, bytes32[] b)").topic, keccak256("E(uint256,bytes32[])"));
  for (const sig of [
    "E(uint indexed a)", "E(uint256 indexed a,uint256 b)", "E(uint256  indexed a)", "E(uint256[2] a)", "E((uint256,bool) a)",
    "E(uint256 indexed a, uint256 indexed b, uint256 indexed c, uint256 indexed d)", "E(uint256 indexed)", "E(byte a)",
  ]) assert.throws(() => parseEvent(sig), Error, sig);
});

test("descriptors compile; broken ones are refused", () => {
  for (const s of Object.values(vectors.sources)) compileSource(s);
  const mutate = (fn) => {
    const d = structuredClone(mainnet);
    fn(d);
    return () => compileSource(d);
  };
  assert.throws(mutate((d) => (d.events = d.events.filter((e) => e.step !== "refunded"))), /refunded/);
  assert.throws(mutate((d) => (d.events[0].fields.brief = "briefURI")), /cannot hold/);
  assert.throws(mutate((d) => d.events.push(structuredClone(d.events[0]))), /declared twice/);
  assert.throws(mutate((d) => delete d.fromBlock), /fromBlock/);
  assert.throws(mutate((d) => (d.events[1].actor = "client")), /actor/);
  assert.throws(mutate((d) => (d.events[4].actor = "worker")), /maps no worker/);
  assert.throws(mutate((d) => (d.vault = d.contract.toLowerCase())), /vault must be an ERC-55 checksummed address/);
  assert.throws(mutate((d) => (d.vault = "vaultOf(address)")), /vault must be/);
  assert.throws(mutate((d) => (d.vault = 1)), /vault must be/);
  assert.throws(mutate((d) => (d.events[0].feeIncluded = true)), /feeIncluded/);
  assert.throws(mutate((d) => (d.finality = 0)), /finality/);
  compileSource({ ...structuredClone(mainnet), finality: 12 });
  compileSource({ ...structuredClone(mainnet), vault: "vaultOf(uint256)" });
  compileSource({ ...structuredClone(mainnet), vault: checksum("0x000000000000000000000000000000000000fa17") });
});

for (const v of vectors.valid) {
  test(`${v.name} (${v.network})`, () => {
    const out = buildRecord({ source: vectors.sources[v.source], logs: v.logs, task: v.task, head: v.head, terminalTime: v.terminalTime });
    assert.equal(out.outcome, v.expect.outcome);
    if (v.expect.entry === null) return assert.equal(out.entry, null);
    assert.equal(out.file, v.expect.file);
    assert.equal(out.bytes, v.expect.bytes);
    assert.equal(out.entry.feedbackHash, v.expect.feedbackHash);
    assert.deepEqual({ tag1: out.entry.tag1, tag2: out.entry.tag2, value: out.entry.value }, v.expect.entry);
    const rec = readFile(dataUriBytes(out.entry.feedbackURI), out.entry.feedbackHash, { ...v.head, tag1: out.entry.tag1, tag2: out.entry.tag2, value: out.entry.value, valueDecimals: 0 });
    assert.deepEqual(checkRecord(rec, { pinned: vectors.sources[v.source], logs: v.logs }).errors, []);
  });
}

function invalidError(v) {
  const base = vectors.valid.find((x) => x.name === v.base);
  const pinned = vectors.sources[base.source];
  if (v.kind === "logs") return judge(stepsOf(compileSource(pinned), v.logs, base.task)).problems.join("; ");
  if (v.kind === "build") {
    try {
      buildRecord({ source: pinned, logs: base.logs, task: base.task, head: { ...base.head, createdAt: v.createdAt }, terminalTime: base.terminalTime });
    } catch (e) {
      return e.message;
    }
    return "";
  }
  if (v.kind === "duplicate") {
    const rec = JSON.parse(base.expect.file);
    return findDuplicates(v.entries.map(() => rec)).length ? "duplicate" : "";
  }
  let rec;
  try {
    rec = readFile(dataUriBytes(v.feedbackURI), v.feedbackHash);
  } catch (e) {
    return e.message;
  }
  return checkRecord(rec, { pinned, logs: base.logs }).errors.join("; ");
}

for (const v of vectors.invalid) {
  test(`fails: ${v.name}`, () => assert.match(invalidError(v), new RegExp(v.expectError)));
}

test("a file that is not canonical, or whose hash or URI is wrong, is refused", () => {
  const { file, feedbackHash } = vectors.valid[0].expect;
  const spaced = JSON.stringify(JSON.parse(file), null, 1);
  assert.throws(() => readFile(new TextEncoder().encode(spaced), keccak256(spaced)), /canonical/);
  assert.throws(() => readFile(new TextEncoder().encode(file), keccak256("other")), /feedbackHash/);
  assert.throws(() => dataUriBytes(`data:application/json;base64,${Buffer.from(file).toString("base64")}=`), /base64/);
  assert.equal(readFile(new TextEncoder().encode(file), feedbackHash).work.task, "50");
});

// A minimal source whose worker accepts tasks on chain, for the rules the BrainChain board does not exercise.
const W = "0x00000000000000000000000000000000000000aa";
const X = "0x00000000000000000000000000000000000000bb";
const C = "0x00000000000000000000000000000000000000cc";
const toy = {
  chainId: 1, contract: checksum("0x000000000000000000000000000000000000beef"), asset: `eip155:1/erc20:${checksum("0x000000000000000000000000000000000000c0de")}`, fromBlock: 1, finality: "finalized",
  events: [
    { step: "funded", event: "Funded(uint256 indexed task, address indexed client, uint256 amount)", fields: { task: "task", client: "client", amount: "amount" } },
    { step: "assigned", event: "Accepted(uint256 indexed task, address indexed worker)", fields: { task: "task", worker: "worker" }, actor: "worker" },
    { step: "assigned", event: "Hired(uint256 indexed task, address indexed worker)", fields: { task: "task", worker: "worker" } },
    { step: "delivered", event: "Delivered(uint256 indexed task, address indexed worker, bytes32 result)", fields: { task: "task", worker: "worker", result: "result" }, actor: "worker" },
    { step: "verdict", event: "Verdict(uint256 indexed task, address indexed evaluator, bool accepted, bytes32 ref)", fields: { task: "task", accepted: "accepted", evaluator: "evaluator", ref: "ref" } },
    { step: "verdict", event: "Approved(uint256 indexed task, uint256 ref)", fields: { task: "task", accepted: true, ref: "ref" } },
    { step: "challenge", event: "Disputed(uint256 indexed task, address indexed by)", fields: { task: "task", by: "by" } },
    { step: "paid", event: "Paid(uint256 indexed task, address indexed to, uint256 amount)", fields: { task: "task", to: "to", amount: "amount" } },
    { step: "refunded", event: "Refunded(uint256 indexed task, address indexed to, uint256 amount)", fields: { task: "task", to: "to", amount: "amount" } },
  ],
};
const topicOf = (step) => parseEvent(toy.events.find((e) => e.step === step || e.event.startsWith(step)).event).topic;
const t32 = (v) => "0x" + BigInt(v).toString(16).padStart(64, "0");
const w32 = (v) => BigInt(v).toString(16).padStart(64, "0");
let n = 0;
function log(step, extra, data, tx = `t${++n}`) {
  return { address: toy.contract, blockNumber: n, logIndex: 0, transactionHash: t32(BigInt(keccak256(tx))), topics: [topicOf(step), t32(7), ...extra.map(t32)], data: "0x" + data.map(w32).join("") };
}
const funded = () => log("funded", [C], [1000]);
const taken = (who = W) => log("assigned", [who], []);
const hired = (who = W) => log("Hired", [who], []);
const delivered = () => log("delivered", [W], [1]);
const verdict = (ok) => log("verdict", [C], [ok ? 1 : 0, 0]);
const paid = (amount = 1000) => log("paid", [W], [amount]);
const refunded = () => log("refunded", [C], [1000]);
const approved = () => log("Approved", [], [0xea]);
const disputed = () => log("challenge", [C], []);
const outcomeOf = (logs) => judge(stepsOf(compileSource(toy), logs, 7));
const lapse = (logs) => {
  const { outcome, lapsedAfter } = outcomeOf(logs);
  return [outcome, lapsedAfter];
};

test("no forced entries: a lapse before delivery needs the worker's own act, read from the event's worker field", () => {
  assert.deepEqual(lapse([funded(), taken(), refunded()]), ["lapsed", "assigned"]);
  assert.equal(outcomeOf([funded(), hired(), refunded()]).outcome, "unstarted");
  assert.equal(outcomeOf([funded(), hired(), verdict(false), refunded()]).outcome, "unstarted");
  assert.equal(outcomeOf([funded(), taken(X), hired(W), refunded()]).outcome, "unstarted", "the act must be the task's worker's");
  assert.equal(buildRecord({ source: toy, logs: [funded(), hired(), refunded()], task: 7, head: {} }).entry, null);
  const steps = stepsOf(compileSource(toy), [funded(), taken(), refunded()], 7).steps;
  assert.ok(steps.every((step) => !("sender" in step)), "no transaction sender is read or recorded");
});

test("a lapsed task takes a work.lapsed entry, named by the step it lapsed after", () => {
  const logs = [funded(), taken(), delivered(), refunded()];
  const out = buildRecord({ source: toy, logs, task: 7, head: vectors.valid[0].head });
  assert.deepEqual({ tag1: out.entry.tag1, tag2: out.entry.tag2, value: out.entry.value }, { tag1: "work.lapsed", tag2: "delivered", value: 0 });
  assert.equal(out.record.work.outcome, "lapsed");
  assert.equal(buildRecord({ source: toy, logs: [funded(), taken(), refunded()], task: 7, head: vectors.valid[0].head }).entry.tag2, "assigned");
  const rec = readFile(dataUriBytes(out.entry.feedbackURI), out.entry.feedbackHash);
  assert.deepEqual(checkRecord(rec, { pinned: toy, logs }).errors, []);
  assert.match(checkRecord({ ...rec, tag2: "assigned" }, { pinned: toy, logs }).errors.join(), /lapsed after delivered, the record says assigned/);
  const asRejection = canonical({ ...rec, tag1: "work.outcome", tag2: "rejected" });
  assert.throws(() => readFile(new TextEncoder().encode(asRejection), keccak256(asRejection)), /do not follow the profile/);
  assert.equal(outcomeOf([funded(), taken(), delivered(), verdict(false), refunded()]).outcome, "rejected");
});

test("a step carries no sender field", () => {
  const rec = JSON.parse(vectors.valid[0].expect.file);
  rec.work.steps[2].sender = checksum("0x" + "11".repeat(20));
  const text = canonical(rec);
  assert.throws(() => readFile(new TextEncoder().encode(text), keccak256(text)), /delivered step has a field this profile does not define: sender/);
});

test("a vault the descriptor names holds the money: transfers are checked to and from it", () => {
  const V = checksum("0x000000000000000000000000000000000000fa17");
  const asset = toy.asset.split(":").at(-1);
  const transfer = (from, to) => ({ address: asset, logIndex: 0, topics: [TRANSFER_TOPIC, t32(from), t32(to)], data: "0x" + w32(1000) });
  const fund = { ...funded(), logIndex: 1 };
  const refund = { ...refunded(), logIndex: 1 };
  const fixed = compileSource({ ...toy, vault: V });
  assert.deepEqual(unbackedTransfers(fixed, { logs: [transfer(C, V), fund] }), []);
  assert.deepEqual(unbackedTransfers(fixed, { logs: [transfer(V, C), refund] }), []);
  assert.equal(unbackedTransfers(fixed, { logs: [transfer(C, toy.contract), fund] }).length, 1);
  assert.deepEqual(unbackedTransfers(compileSource(toy), { logs: [transfer(C, toy.contract), fund] }), [], "without a vault, the source");
  const getter = compileSource({ ...toy, vault: "vaultOf(uint256)" });
  assert.deepEqual(moneyTasks(getter, { logs: [transfer(C, V), fund, { ...taken(), logIndex: 2 }] }), [7n]);
  assert.deepEqual(unbackedTransfers(getter, { logs: [transfer(C, V), fund] }, new Map([[7n, V]])), []);
  assert.equal(unbackedTransfers(getter, { logs: [transfer(C, toy.contract), fund] }, new Map([[7n, V]])).length, 1);
  assert.throws(() => unbackedTransfers(getter, { logs: [fund] }), /vault of task 7 is needed/);
});

test("each Transfer log backs one step, across every task in the transaction", () => {
  const compiled = compileSource(toy);
  const asset = toy.asset.split(":").at(-1);
  const fund = (task, i) => ({ ...funded(), logIndex: i, topics: [topicOf("funded"), t32(task), t32(C)] });
  const transfer = (i, amount = 1000, token = asset) => ({ address: token, logIndex: i, topics: [TRANSFER_TOPIC, t32(C), t32(toy.contract)], data: "0x" + w32(amount) });
  const missing = (logs) => unbackedTransfers(compiled, { logs }).map((m) => [String(m.task), m.amount]);
  assert.deepEqual(missing([transfer(0), fund(7, 1), fund(8, 2)]), [["8", 1000n]]);
  assert.deepEqual(missing([transfer(0), transfer(1), fund(7, 2), fund(8, 3)]), []);
  assert.deepEqual(missing([transfer(0, 999), fund(7, 1)]), [["7", 1000n]]);
  assert.deepEqual(missing([transfer(0, 1000, "0x000000000000000000000000000000000000dead"), fund(7, 1)]), [["7", 1000n]]);
});

test("resubmission: the last verdict after the last delivery decides", () => {
  assert.equal(outcomeOf([funded(), taken(), delivered(), verdict(false), delivered(), verdict(true), paid()]).outcome, "accepted");
  assert.deepEqual(lapse([funded(), taken(), delivered(), verdict(true), delivered(), refunded()]), ["lapsed", "delivered"]);
});

test("amounts and terminal steps", () => {
  assert.deepEqual(outcomeOf([funded(), delivered(), verdict(true), paid()]).problems, []);
  assert.match(outcomeOf([funded(), delivered(), verdict(true), paid(990)]).problems.join(), /settles 990 of 1000/);
  const both = [paid(), refunded()].map((l, i) => ({ ...l, transactionHash: t32(99), blockNumber: 1_000_000, logIndex: i }));
  assert.match(outcomeOf([funded(), delivered(), verdict(true), ...both]).problems.join(), /2 terminal steps/);
});

test("a literal accepted is written into the step, and ref is the 32-byte word", () => {
  const logs = [funded(), delivered(), approved(), paid()];
  const found = stepsOf(compileSource(toy), logs, 7);
  const step = found.steps.find((x) => x.step === "verdict");
  assert.equal(step.accepted, true);
  assert.equal(step.ref, "0x" + "ea".padStart(64, "0"));
  const recorded = JSON.parse(vectors.valid[0].expect.file).work.steps.find((x) => x.step === "verdict");
  assert.match(recorded.ref, /^0x0{61}0ea$/);
});

test("a challenge with no later verdict leaves the challenged verdict standing", () => {
  assert.equal(outcomeOf([funded(), delivered(), verdict(true), disputed(), paid()]).outcome, "accepted");
  assert.equal(outcomeOf([funded(), delivered(), verdict(false), disputed(), refunded()]).outcome, "rejected");
  assert.match(outcomeOf([funded(), delivered(), verdict(false), disputed(), paid()]).problems.join(), /a rejected task ends in paid/);
});

test("a log that does not match its declared event makes the task inconsistent", () => {
  const extra = { ...verdict(true), topics: [...verdict(true).topics, t32(1)] };
  const logs = [funded(), delivered(), extra, paid()];
  assert.match(judge(stepsOf(compileSource(toy), logs, 7)).problems.join(), /does not match its declared event/);
});

test("a source that stops producing blocks still lets tasks fall due", () => {
  assert.equal(isDue(0, 0, 72 * 3600), true);
  assert.equal(isDue(0, 10, 72 * 3600 - 1), false);
});

test("late logs: a declared log after the entry does not count against the writer", () => {
  const logs = [funded(), delivered(), verdict(true), paid(), verdict(false)];
  const found = stepsOf(compileSource(toy), logs, 7);
  assert.match(judge(found).problems.join(), /after the terminal transaction/);
  const late = logs.at(-1).blockNumber;
  assert.deepEqual(judge(dropLate(found, (b) => b >= late)).problems, []);
});

test("createdAt lies between the terminal step and the entry", () => {
  assert.match(createdAtProblem("2026-11-15T14:15:27Z", 1794752128), /precedes the terminal step/);
  assert.equal(createdAtProblem("2026-11-15T14:15:28Z", 1794752128, 1794752128), undefined);
  assert.match(createdAtProblem("2026-11-16T12:00:01Z", undefined, Date.parse("2026-11-16T12:00:00Z") / 1000), /lies after/);
});

test("reader messages name the first differing step and field", () => {
  const steps = JSON.parse(vectors.valid[0].expect.file).work.steps;
  const altered = structuredClone(steps);
  altered[4].amount = "970000";
  assert.equal(diffSteps(altered, steps), "step 5 paid.amount: record 970000, chain 1000000");
  assert.match(diffSteps(steps.slice(0, 3), steps), /^step 4: the chain has a verdict step/);
  const upper = structuredClone(steps);
  upper[0].tx = upper[0].tx.toUpperCase().replace("0X", "0x");
  assert.equal(diffSteps(upper, steps), undefined);
  const rec = JSON.parse(vectors.valid[0].expect.file);
  const bytes = new TextEncoder().encode(vectors.valid[0].expect.file);
  assert.throws(() => readFile(bytes, vectors.valid[0].expect.feedbackHash, { ...rec, agentId: 20425 }), /names agent 20424 but the entry is about agent 20425/);
  assert.match(diffSteps([{ ...steps[1], step: "assigned" }], [steps[0]]), /the record has an assigned step where the chain has a funded step/);
  const padded = structuredClone(rec);
  padded.work.steps[4].amount = "01000000";
  const text = canonical(padded);
  assert.throws(() => readFile(new TextEncoder().encode(text), keccak256(text)), /paid.amount must be a decimal string without leading zeros/);
});

test("a task posted for another agent is found", () => {
  const key = taskKey(mainnet, 50);
  assert.deepEqual([...otherAgents(new Set([key]), 20424n, [{ key, agentId: 20425n }, { key, agentId: 20424n }])], [[key, [20425n]]]);
  assert.equal(otherAgents(new Set([key]), 20424n, [{ key: taskKey(mainnet, 51), agentId: 20425n }]).size, 0);
});

test("reader rules: pinned descriptors, duplicates, index gaps, due times", () => {
  const rec = JSON.parse(vectors.valid[0].expect.file);
  assert.match(checkRecord(rec, { pinned: undefined, logs: [] }).errors.join(), /holds no descriptor/);
  assert.deepEqual(findDuplicates([rec, rec]).map((d) => d.at), [[0, 1]]);
  assert.deepEqual(findDuplicates([rec, JSON.parse(vectors.valid[1].expect.file)]), []);
  assert.deepEqual(indexGaps([1n, 2n, 4n], 5n), [3n, 5n]);
  assert.equal(isDue(0, 72 * 3600 - 1), false);
  assert.equal(isDue(0, 72 * 3600), true);
});

test("giveFeedback calldata matches an independent ABI encoder; encodeCall checks ranges", () => {
  const v = vectors.valid[0];
  const e = v.expect;
  const calldata = giveFeedbackCalldata(v.head.agentId, { ...e.entry, valueDecimals: 0, feedbackHash: e.feedbackHash }, `data:application/json;base64,${Buffer.from(e.file).toString("base64")}`);
  // keccak256 of the calldata Foundry's `cast calldata` gives for the same arguments.
  assert.equal(keccak256(hexToBytes(calldata)), "0x0535f12b0d54dfe0e99f9dfc4df5cc3d91d37fb0278f72e39848c8d11c799026");
  assert.throws(() => encodeCall("f(uint8)", [256]), /out of range/);
  assert.throws(() => encodeCall("f(int8)", [-129]), /out of range/);
  assert.throws(() => encodeCall("f(string)", [5]), /not a string/);
  assert.throws(() => encodeCall("f(address)", ["0x12"]), /not an address/);
});

test("work.workers metadata decodes with bounds checks", () => {
  const refs = [{ chainId: 274663, source: "0x44b8464342Bbfb9B565FAE494DfDefa37D33A211", worker: "0x5f1c28741ee74be2a828fd337283ca47e477a0cd56bf5ad31c61e1ce3ce1d22f" }];
  const value = "0x" + w32(32) + w32(refs.length) + refs.map((r) => w32(r.chainId) + w32(r.source) + r.worker.slice(2)).join("");
  assert.deepEqual(decodeWorkers(value), refs);
  assert.deepEqual(decodeWorkers("0x"), []);
  assert.throws(() => decodeWorkers("0x" + w32(32) + w32(5)), /runs past/);
  assert.throws(() => decodeWorkers("0x" + w32(31) + w32(0)), /multiple of 32/);
});

test("example-record.json is task 50's record, byte for byte", () => {
  const bytes = new Uint8Array(readFileSync(new URL("example-record.json", import.meta.url)));
  assert.equal(keccak256(bytes), vectors.valid[0].expect.feedbackHash);
});

const cli = (...args) => spawnSync(process.execPath, [new URL("cli.mjs", import.meta.url).pathname, ...args], { encoding: "utf8" });

test("CLI: exit codes, --help, --flag=value and descriptor errors (offline)", () => {
  assert.equal(cli("--help").status, 0);
  assert.equal(cli("-h").status, 0);
  for (const c of ["build", "check", "entries", "vectors"]) assert.equal(cli(c, "-h").status, 0, c);
  assert.equal(cli("nope").status, 2);
  assert.equal(cli("check", "--bogus=1").status, 2);
  const typo = cli("build", "--rpc=https://x.example", "--descriptor", "d.json", "--task", "1", "--registry", "eip155:4663:0x8004A169FB4a3325136EB29fA0ceB6D2e539a432", "--agent", "1", "--writer", "0x97D558417c3D61f1074422AD843e1Db1E565B953");
  assert.equal(typo.status, 2);
  assert.match(typo.stderr, /wrong ERC-55 checksum/);
  assert.equal(cli("build", "--task", "1", "--task", "2").status, 2);
  const dir = mkdtempSync(join(tmpdir(), "ewr-"));
  writeFileSync(join(dir, "bom.json"), "\ufeff{}");
  writeFileSync(join(dir, "bad.json"), "{");
  const file = new URL("example-record.json", import.meta.url).pathname;
  for (const [name, message] of [["bom.json", /bom\.json: starts with a byte order mark/], ["bad.json", /bad\.json: not JSON/]]) {
    const r = cli("check", "--rpc", "https://x.example", "--descriptor", join(dir, name), "--file", file);
    assert.equal(r.status, 1);
    assert.match(r.stderr, message);
  }
  assert.equal(cli("check", "--rpc", "https://x.example", "--descriptor", "d.json").status, 2);
  const descriptor = new URL("sources/brainchain-mainnet.json", import.meta.url).pathname;
  writeFileSync(join(dir, "cut.json"), readFileSync(file, "utf8").slice(0, 100));
  const cut = cli("check", "--rpc", "https://x.example", "--descriptor", descriptor, "--file", join(dir, "cut.json"));
  assert.equal(cut.status, 1);
  assert.equal(cut.stdout.trim(), `FAIL: ${join(dir, "cut.json")} is not valid JSON`);
  const missing = cli("check", "--rpc", "https://x.example", "--descriptor", descriptor, "--file", join(dir, "nope.json"));
  assert.equal(missing.status, 1);
  assert.match(missing.stderr, /no such file: .*nope\.json/);
  assert.equal(cli("entries", "--registry-rpc", "https://x.example", "--reputation", "eip155:4663:0x8004BAa17C55a88189AE136b182e5fdA19dE9b63", "--agent", "9007199254740992", "--writer", "0x97D558417c3D61f1074422AD843e1Db1E565b952", "--from-block", "0").status, 2);
  const verify = cli("vectors", "--verify", "1=https://x.example");
  assert.equal(verify.status, 1);
  assert.match(verify.stderr, /no vectors for chain 1/);
});
