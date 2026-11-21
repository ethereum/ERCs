// Offline tests for the reference implementation against vectors.json: node --test test.mjs
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import {
  canonical, checksum, dayList, dayRecord, dayRoot, digest, keccak256, listProblem, parseJson, problem, proof, readDay,
  receiptHash, receiptsProblem, recordProblem, recover, toHex, verifyProof,
} from "./receipts.mjs";

const v = JSON.parse(readFileSync(new URL("./vectors.json", import.meta.url), "utf8"));
const text = (s) => new TextEncoder().encode(s);
const N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;

test("Keccak-256 and ERC-55 match known values, across the 136-byte block edge", () => {
  assert.equal(toHex(keccak256(text(""))), "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470");
  assert.equal(toHex(keccak256(text("abc"))), "0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45");
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

test("the canonical form does not depend on the order members arrive in", () => {
  const r = v.receipts[2];
  const shuffled = Object.fromEntries(Object.entries(r).reverse());
  shuffled.judged = Object.fromEntries(Object.entries(r.judged).reverse());
  assert.equal(canonical(shuffled), canonical(r));
});

test("every valid receipt verifies, every invalid one fails for its reason", () => {
  for (const r of v.receipts) assert.equal(problem(r), null);
  for (const { name, receipt, reason } of v.invalid) assert.equal(problem(receipt), reason, name);
});

test("the receipts that break a type or value rule carry the signer's own signature", () => {
  const typed = ["price as a number", "request as an array", "network as an array", "fee more than price", "nonce with a leading zero",
    "network not CAIP-2", "passProbability above 1", "bar with seven decimals", "model outside printable ASCII", "price of 2^256"];
  for (const name of typed) {
    const { receipt } = v.invalid.find((x) => x.name === name);
    assert.equal(recover(digest(receiptHash(receipt)), receipt.signature), v.signer, name);
  }
});

test("signature recovery: the other s recovers the same key but is refused; v 0 or 1, zero and out-of-range values recover nothing", () => {
  const sig = v.receipts[0].signature, hash = digest(v.hashes[0]);
  const high = v.invalid.find((x) => x.name === "high s").receipt.signature;
  assert.equal(recover(hash, high), v.signer);
  assert.equal(recover(hash, `${sig.slice(0, -2)}00`), null);
  assert.equal(recover(hash, `${sig.slice(0, -2)}01`), null);
  assert.equal(recover(hash, `0x${"0".repeat(64)}${sig.slice(66)}`), null);
  assert.equal(recover(hash, `0x${N.toString(16)}${sig.slice(66)}`), null);
  assert.equal(recover(hash, `${sig.slice(0, 66)}${"0".repeat(64)}${sig.slice(-2)}`), null);
  assert.equal(recover(hash, sig.slice(0, -2)), null);
  assert.equal(recover(hash, "not hex"), null);
});

test("problem never throws, whatever it is given", () => {
  const r = v.receipts[0];
  for (const input of [null, 7, "x", [], [r], { ...r, signature: undefined }, { ...r, signature: 5 }, { ...r, signature: "0x1" },
    { ...r, at: "2026-13-21T01:00:00.000Z" }, { ...r, at: "2026-11-21T25:00:00.000Z" }, { ...r, judged: [] }, { ...r, judged: "x" },
    { ...r, asset: 1 }, { ...r, nonce: null }]) {
    assert.equal(typeof problem(input), "string");
  }
});

test("a JSON text that repeats a member name is refused, at any depth", () => {
  for (const { name, line, reason } of v.invalidLines) assert.throws(() => parseJson(line), { message: reason }, name);
  assert.throws(() => parseJson('{"a":{"b":1,"b":2}}'), /repeated member name: b/);
  assert.deepEqual(parseJson('{"a":[{"b":1},{"b":2}],"c":"{\\"c\\":1}"}'), { a: [{ b: 1 }, { b: 2 }], c: '{"c":1}' });
});

test("the day root, the proofs and the record match the vectors", () => {
  assert.equal(dayRoot(v.receipts), v.dayList.root);
  assert.deepEqual(dayList(v.dayList.day, v.signer, v.receipts), v.dayList);
  assert.equal(listProblem(v.dayList), null);
  assert.deepEqual(dayRecord(v.dayList), v.record);
  v.receipts.forEach((r, i) => {
    const p = proof(v.receipts, i);
    assert.deepEqual(p, { leaf: v.hashes[i], path: v.proofs[i], root: v.dayList.root });
    assert.ok(verifyProof(r, v.proofs[i], v.dayList.root));
  });
  for (const { count, root } of v.trees) assert.equal(dayRoot(v.receipts.slice(0, count)), root, `${count} receipts`);
});

test("a day list is in day-list order whatever order the receipts arrive in", () => {
  assert.deepEqual(dayList(v.dayList.day, v.signer, [...v.receipts].reverse()), v.dayList);
  const swapped = { ...v.dayList, receipts: [v.receipts[1], v.receipts[0], ...v.receipts.slice(2)] };
  assert.match(listProblem(swapped), /out of day-list order/);
});

test("an unpaired node is carried up, so repeating the last receipt changes the root", () => {
  const five = v.receipts, six = [...v.receipts, v.receipts.at(-1)];
  assert.notEqual(dayRoot(six), dayRoot(five));
  assert.equal(proof(five, 4).path.length, 1);
});

test("sorted pairs: swapping two siblings keeps the root, moving a receipt to another pair changes it", () => {
  const siblings = [v.receipts[1], v.receipts[0], ...v.receipts.slice(2)];
  assert.equal(dayRoot(siblings), dayRoot(v.receipts));
  const moved = [v.receipts[2], v.receipts[1], v.receipts[0], ...v.receipts.slice(3)];
  assert.notEqual(dayRoot(moved), dayRoot(v.receipts));
});

test("a proof fails for another receipt, another root, a changed receipt or malformed nodes, and passes in uppercase", () => {
  const { root } = v.dayList;
  assert.ok(!verifyProof(v.receipts[1], v.proofs[0], root));
  assert.ok(!verifyProof(v.receipts[0], v.proofs[0], v.public.dayList.root));
  assert.ok(!verifyProof({ ...v.receipts[0], price: "1" }, v.proofs[0], root));
  assert.ok(!verifyProof(v.receipts[0], ["0x12"], root));
  assert.ok(!verifyProof(v.receipts[0], "not a path", root));
  assert.ok(!verifyProof(v.receipts[0], v.proofs[0], null));
  assert.ok(verifyProof(v.receipts[0], v.proofs[0].map((n) => n.toUpperCase().replace("0X", "0x")), root.toUpperCase().replace("0X", "0x")));
});

test("a day list that misstates its shape, count or root, or holds another day, a repeat or a repeated payment, fails", () => {
  assert.match(listProblem({ ...v.dayList, count: 4 }), /^count 4/);
  assert.match(listProblem({ ...v.dayList, root: v.hashes[0] }), /^root /);
  assert.match(listProblem({ ...v.dayList, day: "2026-11-20" }), /is of 2026-11-21/);
  assert.match(listProblem({ ...v.dayList, day: "garbage" }), /day is not/);
  assert.match(listProblem({ ...v.dayList, signer: v.signer.toLowerCase() }), /signer is not/);
  assert.match(listProblem({ ...v.dayList, unreadable: "0" }), /whole numbers/);
  assert.match(listProblem({ ...v.dayList, extra: 1 }), /unknown members: extra/);
  assert.match(listProblem({ day: "2026-11-21", signer: v.signer, count: 0, root: null }), /missing members: unreadable, receipts/);
  const repeated = [...v.receipts.slice(0, 2), v.receipts[1]];
  assert.match(receiptsProblem(v.dayList.day, v.signer, repeated), /repeats receipt 1/);
  assert.match(receiptsProblem(v.dayList.day, v.signer, [v.receipts[0], v.repeatedPayment.receipt]), /repeats a payment/);
  assert.equal(listProblem(dayList("2026-11-22", v.signer, [])), null);
});

test("reading a day file: CRLF, a byte-order mark and blank lines are fine; unreadable lines are counted and left out", () => {
  const lines = [JSON.stringify(v.receipts[1]), '{"v":1,"request":"0x', "   ", JSON.stringify(v.receipts[0]), "null", v.invalidLines[0].line, ""];
  const { receipts, unreadable } = readDay(`﻿${lines.join("\r\n")}`);
  assert.equal(receipts.length, 2);
  assert.equal(unreadable, 3);
  assert.equal(dayList(v.dayList.day, v.signer, receipts, unreadable).root, dayRoot(v.receipts.slice(0, 2)));
  const strict = readDay([...v.receipts, ...v.public.dayList.receipts].map((r) => JSON.stringify(r)).join("\n"), v.dayList.day, v.signer);
  assert.equal(strict.receipts.length, 5);
  assert.equal(strict.unreadable, 1);
});

test("a record is refused while a day has unreadable entries; an empty day's record has a zero root", () => {
  assert.throws(() => dayRecord({ ...v.dayList, unreadable: 1 }), /unreadable/);
  assert.equal(dayRecord(dayList("2026-11-22", v.signer, [])).root, `0x${"0".repeat(64)}`);
});

test("the reference deployment's public day verifies, its one receipt is its root, and the inscribed record states it", () => {
  const list = v.public.dayList;
  assert.equal(listProblem(list), null);
  assert.equal(list.root, receiptHash(list.receipts[0]));
  assert.deepEqual(JSON.parse(v.public.inscription.data), v.public.record);
  assert.equal(recordProblem(v.public.record, list), null);
  assert.match(recordProblem({ ...v.public.record, root: v.hashes[0] }, list), /^root /);
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
  const cases = [
    [["verify", file("r.json", JSON.stringify(v.receipts[0]))], 0],
    [["verify", file("bad.json", "{nope")], 1],
    [["verify", file("dup.json", v.invalidLines[0].line)], 1],
    [["verify", join(dir, "missing.json")], 1],
    [["verify"], 2],
    [["root", day], 0],
    [["root", mixed], 1],
    [["prove", day, "4"], 0],
    [["prove", day, "9"], 1],
    [["prove", day, "x"], 2],
    [["prove", day, ""], 2],
    [["check", file("list.json", JSON.stringify(v.dayList))], 0],
    [["check", file("nolist.json", "{}")], 1],
    [["nonsense"], 2],
  ];
  for (const [args, code] of cases) assert.equal(cli(...args).status, code, args.join(" "));
  assert.equal(JSON.parse(cli("root", day).stdout).root, v.dayList.root);
  assert.deepEqual(JSON.parse(cli("prove", day, "4").stdout).path, v.proofs[4]);
});
