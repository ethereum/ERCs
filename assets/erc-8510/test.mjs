// SPDX-License-Identifier: CC0-1.0
// Offline tests for the reference implementation against vectors.json: node --test test.mjs
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import {
  canonical, checksum, dayList, dayRecord, dayRoot, digest, findRecord, keccak256, listProblem, parseJson, proof, readDay, receiptProblem,
  receiptHash, receiptsProblem, recordListProblem, recordProblem, recover, toHex, verifyProof,
} from "./receipts.mjs";

const v = JSON.parse(readFileSync(new URL("./vectors.json", import.meta.url), "utf8"));
const utf8 = (s) => new TextEncoder().encode(s);
const N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;

test("Keccak-256 and ERC-55 match known values, across the 136-byte block edge", () => {
  assert.equal(toHex(keccak256(utf8(""))), "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470");
  assert.equal(toHex(keccak256(utf8("abc"))), "0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45");
  const a = (n) => new Uint8Array(n).fill(0x61);
  assert.equal(toHex(keccak256(a(135))), "0x34367dc248bbd832f4e3e69dfaac2f92638bd0bbd18f2912ba4ef454919cf446");
  assert.equal(toHex(keccak256(a(136))), "0xa6c4d403279fe3e0af03729caada8374b5ca54d8065329a3ebcaeb4b60aa386e");
  assert.equal(toHex(keccak256(a(137))), "0xd869f639c7046b4929fc92a4d988a8b22c55fbadb802c0c66ebcd484f1915f39");
  assert.equal(checksum("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed"), "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed");
});

test("each receipt's canonical form and hash match the vectors", () => {
  v.receipts.forEach((r, i) => {
    assert.equal(canonical(r), v.canonical[i]);
    assert.equal(receiptHash(r), v.hashes[i]);
  });
});

test("every valid receipt verifies, every invalid one fails for its reason", () => {
  for (const r of v.receipts) assert.equal(receiptProblem(r), null);
  for (const { name, receipt, reason } of v.invalid) assert.equal(receiptProblem(receipt), reason, name);
});

test("edge values are valid and serialize as the vectors give them", () => {
  for (const { name, receipt, canonical: expected, hash } of v.edges) {
    assert.equal(receiptProblem(receipt), null, name);
    assert.equal(canonical(receipt), expected, name);
    assert.equal(receiptHash(receipt), hash, name);
  }
});

test("the canonical form comes from values, whatever the JSON text or member order", () => {
  for (const { name, line, hash } of v.textForms) {
    const receipt = parseJson(line);
    assert.equal(receiptProblem(receipt), null, name);
    assert.equal(receiptHash(receipt), hash, name);
  }
  const r = v.receipts[2];
  const shuffled = Object.fromEntries(Object.entries(r).reverse());
  shuffled.judged = Object.fromEntries(Object.entries(r.judged).reverse());
  assert.equal(canonical(shuffled), canonical(r));
});

test("the receipts that break a type or value rule carry the signer's own signature", () => {
  const typed = ["price as a number", "request as an array", "network as an array", "fee more than price", "nonce with a leading zero",
    "network without a chain id", "passProbability above 1", "bar with seven decimals", "model outside printable ASCII", "price of 2^256"];
  for (const name of typed) {
    const { receipt } = v.invalid.find((x) => x.name === name);
    assert.equal(recover(digest(receiptHash(receipt)), receipt.signature), v.signer, name);
  }
});

test("the higher s recovers the same key, and the receipt carrying it is invalid", () => {
  const high = v.invalid.find((x) => x.name === "high s");
  assert.equal(recover(digest(v.hashes[0]), high.receipt.signature), v.signer);
  assert.equal(receiptProblem(high.receipt), high.reason);
});

test("malformed signatures recover no key", () => {
  const sig = v.receipts[0].signature, hash = digest(v.hashes[0]);
  assert.equal(recover(hash, `${sig.slice(0, -2)}00`), null);
  assert.equal(recover(hash, `${sig.slice(0, -2)}01`), null);
  assert.equal(recover(hash, `0x${"0".repeat(64)}${sig.slice(66)}`), null);
  assert.equal(recover(hash, `0x${N.toString(16)}${sig.slice(66)}`), null);
  assert.equal(recover(hash, `${sig.slice(0, 66)}${"0".repeat(64)}${sig.slice(-2)}`), null);
  assert.equal(recover(hash, sig.slice(0, -2)), null);
  assert.equal(recover(hash, "not hex"), null);
});

test("receiptProblem never throws, whatever it is given", () => {
  const r = v.receipts[0];
  for (const input of [null, 7, "x", [], [r], { ...r, signature: undefined }, { ...r, signature: 5 }, { ...r, signature: "0x1" },
    { ...r, at: "2026-13-21T01:00:00.000Z" }, { ...r, at: "2026-11-21T25:00:00.000Z" }, { ...r, judged: [] }, { ...r, judged: "x" },
    { ...r, asset: 1 }, { ...r, nonce: null }]) {
    assert.equal(typeof receiptProblem(input), "string");
  }
});

test("a JSON text that repeats a member name is refused, at any depth", () => {
  for (const { name, line, reason } of v.invalidLines) assert.throws(() => parseJson(line), { message: reason }, name);
  assert.throws(() => parseJson('{"a":{"b":1,"b":2}}'), /repeated member name: b/);
  assert.deepEqual(parseJson('{"a":[{"b":1},{"b":2}],"c":"{\\"c\\":1}"}'), { a: [{ b: 1 }, { b: 2 }], c: '{"c":1}' });
});

test("the day root, the proofs and the record match the vectors", () => {
  assert.equal(dayRoot(v.receipts), v.dayList.root);
  assert.deepEqual(dayList(v.dayList.day, v.signer, v.receipts, 0, v.dayList.records), v.dayList);
  assert.equal(listProblem(v.dayList), null);
  assert.deepEqual(dayRecord(v.dayList), v.record);
  v.receipts.forEach((r, i) => {
    assert.deepEqual(proof(v.receipts, i), { leaf: v.hashes[i], proof: v.proofs[i], root: v.dayList.root });
    assert.ok(verifyProof(r, v.proofs[i], v.dayList.root));
  });
  for (const { count, root } of v.trees) assert.equal(dayRoot(v.receipts.slice(0, count)), root, `${count} receipts`);
});

test("a day list is in day-list order whatever order the receipts arrive in; equal times go by receipt hash", () => {
  assert.deepEqual(dayList(v.dayList.day, v.signer, [...v.receipts].reverse(), 0, v.dayList.records), v.dayList);
  const pair = dayList("2026-11-21", v.signer, [...v.equalAt.receipts].reverse());
  assert.deepEqual(pair.receipts, v.equalAt.receipts);
  assert.equal(pair.root, v.equalAt.root);
  assert.ok(v.equalAt.hashes[0] < v.equalAt.hashes[1]);
  const swapped = { ...v.dayList, receipts: [v.receipts[1], v.receipts[0], ...v.receipts.slice(2)] };
  assert.match(listProblem(swapped), /out of day-list order/);
});

test("an unpaired node is carried up, so repeating the last receipt changes the root", () => {
  const five = v.receipts, six = [...v.receipts, v.receipts.at(-1)];
  assert.notEqual(dayRoot(six), dayRoot(five));
  assert.equal(proof(five, 4).proof.length, 1);
  assert.equal(dayRoot([]), null);
});

test("sorted pairs: swapping two siblings keeps the root, moving a receipt to another pair changes it", () => {
  const siblings = [v.receipts[1], v.receipts[0], ...v.receipts.slice(2)];
  assert.equal(dayRoot(siblings), dayRoot(v.receipts));
  const moved = [v.receipts[2], v.receipts[1], v.receipts[0], ...v.receipts.slice(3)];
  assert.notEqual(dayRoot(moved), dayRoot(v.receipts));
});

test("a proof fails for another receipt, another root or a changed receipt", () => {
  const { root } = v.dayList;
  assert.ok(!verifyProof(v.receipts[1], v.proofs[0], root));
  assert.ok(!verifyProof(v.receipts[0], v.proofs[0], v.public.dayList.root));
  assert.ok(!verifyProof({ ...v.receipts[0], price: "1" }, v.proofs[0], root));
});

test("a proof with malformed nodes fails; hex digits may be in any case behind a 0x prefix", () => {
  const { root } = v.dayList;
  assert.ok(!verifyProof(v.receipts[0], ["0x12"], root));
  assert.ok(!verifyProof(v.receipts[0], "not a proof", root));
  assert.ok(!verifyProof(v.receipts[0], v.proofs[0], null));
  assert.ok(verifyProof(v.receipts[0], v.proofs[0].map((n) => n.toUpperCase().replace("0X", "0x")), root.toUpperCase().replace("0X", "0x")));
  assert.ok(!verifyProof(v.receipts[0], v.proofs[0].map((n) => n.replace("0x", "0X")), root));
});

test("a day list with wrong members, count, root, day or records is invalid", () => {
  assert.match(listProblem({ ...v.dayList, count: 4 }), /^count 4/);
  assert.match(listProblem({ ...v.dayList, root: v.hashes[0] }), /^root /);
  assert.match(listProblem({ ...v.dayList, day: "2026-11-20" }), /is of 2026-11-21/);
  assert.match(listProblem({ ...v.dayList, day: "garbage" }), /^day must be/);
  assert.match(listProblem({ ...v.dayList, signer: v.signer.toLowerCase() }), /^signer must be/);
  assert.match(listProblem({ ...v.dayList, unreadable: "0" }), /whole numbers/);
  assert.match(listProblem({ ...v.dayList, root: v.dayList.root.toUpperCase().replace("0X", "0x") }), /^root must be lowercase hex/);
  assert.match(listProblem({ ...v.dayList, extra: 1 }), /unknown members: extra/);
  assert.match(listProblem({ day: "2026-11-21", signer: v.signer, count: 0, root: null }), /missing members: unreadable, records, receipts/);
  assert.match(listProblem({ ...v.dayList, records: { ...v.dayList.records, network: "eip155:01" } }), /records.network/);
  assert.match(listProblem({ ...v.dayList, records: { ...v.dayList.records, publishers: [] } }), /records.publishers/);
  assert.equal(listProblem(dayList("2026-11-22", v.signer, [], 0, v.dayList.records)), null);
});

test("a day list holding a receipt twice, or two receipts for the same payment, is invalid", () => {
  const repeated = [...v.receipts.slice(0, 2), v.receipts[1]];
  assert.match(receiptsProblem(v.dayList.day, v.signer, repeated), /repeats receipt 1/);
  assert.match(receiptsProblem(v.dayList.day, v.signer, [v.receipts[0], v.repeatedPayment.receipt]), /repeats a payment/);
});

test("a day file may use CRLF, a byte-order mark and blank lines; unreadable lines are counted and left out", () => {
  const lines = [JSON.stringify(v.receipts[1]), '{"v":1,"request":"0x', "   ", JSON.stringify(v.receipts[0]), "null", v.invalidLines[0].line, ""];
  const { day, signer, receipts, unreadable } = readDay(`\uFEFF${lines.join("\r\n")}`);
  assert.deepEqual([day, signer, receipts.length, unreadable], [v.dayList.day, v.signer, 2, 3]);
  assert.equal(dayList(v.dayList.day, v.signer, receipts, unreadable).root, dayRoot(v.receipts.slice(0, 2)));
  const strict = readDay([...v.receipts, ...v.public.dayList.receipts].map((r) => JSON.stringify(r)).join("\n"), v.dayList.day, v.signer);
  assert.equal(strict.receipts.length, 5);
  assert.equal(strict.unreadable, 1);
  assert.deepEqual(readDay(""), { day: null, signer: null, receipts: [], unreadable: 0 });
});

test("a record is refused while a day has unreadable entries; an empty day's record has a zero root", () => {
  assert.throws(() => dayRecord({ ...v.dayList, unreadable: 1 }), /unreadable/);
  assert.equal(dayRecord(dayList("2026-11-22", v.signer, [])).root, `0x${"0".repeat(64)}`);
});

test("the public day verifies, its one receipt is its root, and the record on chain states it", () => {
  const list = v.public.dayList;
  assert.equal(listProblem(list), null);
  const { records, ...served } = list;
  assert.match(listProblem(served), /missing members: records/);
  assert.equal(list.root, receiptHash(list.receipts[0]));
  assert.deepEqual(JSON.parse(v.public.inscription.data), v.public.record);
  assert.equal(recordProblem(v.public.record), null);
  assert.equal(recordListProblem(v.public.record, list), null);
  assert.equal(records.contract, v.public.inscription.contract);
  assert.deepEqual(records.publishers, [v.public.inscription.by]);
  assert.match(recordListProblem({ ...v.public.record, root: v.hashes[0] }, list), /^root /);
});

test("a record is well-formed only with its five members written as the spec says", () => {
  const r = v.public.record;
  assert.match(recordProblem({ ...r, root: r.root.toUpperCase().replace("0X", "0x") }), /^not well-formed: root must be lowercase hex/);
  assert.match(recordProblem({ ...r, root: r.root.replace("0x", "0X") }), /root must be lowercase hex/);
  assert.match(recordProblem({ ...r, kind: "receipt" }), /kind must be receipts/);
  assert.match(recordProblem({ ...r, date: "2026-11-31" }), /date must be/);
  assert.match(recordProblem({ ...r, count: 1.5 }), /count must be/);
  assert.match(recordProblem({ ...r, signer: r.signer.toLowerCase() }), /signer must be/);
  assert.equal(recordProblem({ ...r, extra: "allowed" }), null);
});

/** A JSON-RPC endpoint over the mocked chain in vectors.json; eth_getLogs filters by block range only. */
function mockRpc(chain, { latest = chain.latest } = {}) {
  const calls = [];
  const timestamp = (n) => chain.closedAt + (n - chain.firstClosedBlock) * chain.secondsPerBlock;
  const answer = ({ method, params }) => {
    if (method === "eth_chainId") return chain.chainId;
    if (method === "eth_blockNumber") return `0x${latest.toString(16)}`;
    if (method === "eth_getBlockByNumber") return { timestamp: `0x${timestamp(Number(BigInt(params[0]))).toString(16)}` };
    if (method === "eth_getLogs") {
      const [from, to] = [Number(BigInt(params[0].fromBlock)), Number(BigInt(params[0].toBlock))];
      return chain.logs.filter((log) => Number(BigInt(log.blockNumber)) >= from && Number(BigInt(log.blockNumber)) <= to);
    }
    throw new Error(`unexpected ${method}`);
  };
  const fetch = async (_url, init) => {
    const request = JSON.parse(init.body);
    calls.push(request.method);
    return { ok: true, json: async () => ({ jsonrpc: "2.0", id: request.id, result: answer(request) }) };
  };
  return { fetch, calls };
}

test("findRecord takes the first well-formed record from a publisher after the day closed", async () => {
  for (const chunk of [50_000, 4]) {
    const { fetch } = mockRpc(v.findRecord);
    const found = await findRecord("http://rpc.test", v.public.dayList, { fetch, chunk });
    assert.deepEqual({ blockNumber: found.blockNumber, logIndex: found.logIndex, transactionHash: found.transactionHash }, v.findRecord.expected, `chunk ${chunk}`);
    assert.deepEqual(found.record, v.public.record);
    assert.equal(found.problem, null);
  }
});

test("findRecord refuses a chain other than the list's records name, and finds nothing before the day closes", async () => {
  const wrong = mockRpc({ ...v.findRecord, chainId: "0x1237" });
  await assert.rejects(findRecord("http://rpc.test", v.public.dayList, { fetch: wrong.fetch }), /serves eip155:4663, the records are on eip155:274663/);
  const early = mockRpc(v.findRecord, { latest: v.findRecord.firstClosedBlock - 1 });
  assert.equal(await findRecord("http://rpc.test", v.public.dayList, { fetch: early.fetch }), null);
  assert.ok(!early.calls.includes("eth_getLogs"));
});

test("the CLI: exit 0 when a check passes, 1 when it fails or cannot read, 2 for a usage mistake", () => {
  const dir = mkdtempSync(join(tmpdir(), "erc8510-"));
  const file = (name, body) => {
    writeFileSync(join(dir, name), body);
    return join(dir, name);
  };
  const cli = (...args) => spawnSync(process.execPath, [new URL("./cli.mjs", import.meta.url).pathname, ...args], { encoding: "utf8" });
  const day = file("day.jsonl", [...v.receipts].reverse().map((r) => JSON.stringify(r)).join("\r\n"));
  const mixed = file("mixed.jsonl", [...v.receipts, ...v.public.dayList.receipts].map((r) => JSON.stringify(r)).join("\n"));
  const empty = file("empty.jsonl", "");
  const receipt = file("r.json", JSON.stringify(v.receipts[0]));
  const proofFile = file("proof.json", JSON.stringify(v.proofs[0]));
  const list = file("list.json", JSON.stringify(v.dayList));
  const publicList = file("public.json", JSON.stringify(v.public.dayList));
  const record = file("record.json", v.public.inscription.data);
  const upper = file("upper.json", JSON.stringify({ ...v.public.record, root: v.public.record.root.toUpperCase().replace("0X", "0x") }));
  const cases = [
    [["verify", receipt], 0],
    [["verify", file("bad.json", "{nope")], 1],
    [["verify", file("dup.json", v.invalidLines[0].line)], 1],
    [["verify", join(dir, "missing.json")], 1],
    [["verify"], 2],
    [["verify", receipt, "extra"], 2],
    [["root", day], 0],
    [["root", mixed], 0],
    [["root", mixed, v.public.dayList.day, v.public.dayList.signer], 0],
    [["root", empty], 0],
    [["root", day, v.dayList.day], 2],
    [["prove", day, "4"], 0],
    [["prove", day, "9"], 1],
    [["prove", day, "x"], 2],
    [["prove", day, "01"], 2],
    [["prove", day, ""], 2],
    [["prove", day, "4", "extra"], 2],
    [["check", list], 0],
    [["check", file("nolist.json", "{}")], 1],
    [["check-proof", receipt, proofFile, v.dayList.root], 0],
    [["check-proof", receipt, proofFile, v.hashes[1]], 1],
    [["check-proof", receipt, file("proof-out.json", JSON.stringify({ proof: v.proofs[0] })), v.dayList.root.toUpperCase().replace("0X", "0x")], 0],
    [["check-record", record, publicList], 0],
    [["check-record", upper, publicList], 1],
    [["check-record", record, list], 1],
    [["find-record", "http://127.0.0.1:9", publicList, "0"], 2],
    [["find-record", "http://127.0.0.1:9"], 2],
    [["find-record", "http://127.0.0.1:9", file("bad-list.json", "{}")], 1],
    [["nonsense"], 2],
  ];
  for (const [args, code] of cases) assert.equal(cli(...args).status, code, args.join(" "));
  assert.equal(JSON.parse(cli("root", day).stdout).root, v.dayList.root);
  assert.deepEqual(JSON.parse(cli("root", mixed).stdout), { day: v.dayList.day, signer: v.signer, count: 5, root: v.dayList.root, unreadable: 1 });
  assert.deepEqual(JSON.parse(cli("root", mixed, v.public.dayList.day, v.public.dayList.signer).stdout).unreadable, 5);
  assert.deepEqual(JSON.parse(cli("root", empty).stdout), { day: null, signer: null, count: 0, root: null, unreadable: 0 });
  assert.deepEqual(JSON.parse(cli("prove", day, "4").stdout), { leaf: v.hashes[4], proof: v.proofs[4], root: v.dayList.root });
  assert.match(cli("check-record", upper, publicList).stderr, /not well-formed: root must be lowercase hex/);
});
