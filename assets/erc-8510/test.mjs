// Offline tests for the reference implementation against vectors.json: node --test test.mjs (or node test.mjs).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { canonical, checksum, dayList, dayRecord, dayRoot, keccak256, listProblem, problem, proof, readDay, receiptHash, toHex, verifyProof } from "./receipts.mjs";

const v = JSON.parse(readFileSync(new URL("./vectors.json", import.meta.url), "utf8"));
const text = (s) => new TextEncoder().encode(s);

test("Keccak-256 and ERC-55 match known values", () => {
  assert.equal(toHex(keccak256(text(""))), "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470");
  assert.equal(toHex(keccak256(text("abc"))), "0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45");
  assert.equal(toHex(keccak256(new Uint8Array(200).fill(0x61))).length, 66);
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

test("the day root, the proofs and the record match the vectors", () => {
  assert.equal(dayRoot(v.receipts), v.dayList.root);
  assert.deepEqual(dayList(v.dayList.day, v.signer, v.receipts), v.dayList);
  assert.equal(listProblem(v.dayList), null);
  assert.deepEqual(dayRecord(v.dayList), v.record);
  v.receipts.forEach((r, i) => {
    assert.deepEqual(proof(v.receipts, i), v.proofs[i]);
    assert.ok(verifyProof(r, v.proofs[i], v.dayList.root));
  });
});

test("an unpaired node is carried up, so repeating the last receipt changes the root", () => {
  const five = v.receipts, six = [...v.receipts, v.receipts.at(-1)];
  assert.notEqual(dayRoot(six), dayRoot(five));
  assert.equal(proof(five, 4).length, 1); // the fifth receipt pairs only at the top
});

test("sorted pairs: swapping two siblings keeps the root, moving a receipt to another pair changes it", () => {
  const siblings = [v.receipts[1], v.receipts[0], ...v.receipts.slice(2)];
  assert.equal(dayRoot(siblings), dayRoot(v.receipts));
  const moved = [v.receipts[2], v.receipts[1], v.receipts[0], ...v.receipts.slice(3)];
  assert.notEqual(dayRoot(moved), dayRoot(v.receipts));
});

test("a proof fails for another receipt, another root, or a hash passed off as a receipt", () => {
  assert.ok(!verifyProof(v.receipts[1], v.proofs[0], v.dayList.root));
  assert.ok(!verifyProof(v.receipts[0], v.proofs[0], v.public.dayList.root));
  assert.ok(!verifyProof({ ...v.receipts[0], price: "1" }, v.proofs[0], v.dayList.root));
});

test("a day list that misstates its count or root, or lists another day, fails", () => {
  assert.match(listProblem({ ...v.dayList, count: 4 }), /^count 4/);
  assert.match(listProblem({ ...v.dayList, root: v.hashes[0] }), /^root /);
  assert.match(listProblem({ ...v.dayList, day: "2026-11-20" }), /is of 2026-11-21/);
});

test("reading a day file counts the lines it cannot parse and leaves them out", () => {
  const file = [JSON.stringify(v.receipts[0]), '{"v":1,"request":"0x', JSON.stringify(v.receipts[1]), ""].join("\n");
  const { receipts, unreadable } = readDay(file);
  assert.equal(receipts.length, 2);
  assert.equal(unreadable, 1);
  assert.equal(dayList(v.dayList.day, v.signer, receipts, unreadable).root, dayRoot(v.receipts.slice(0, 2)));
});

test("the reference deployment's public day verifies, and its one receipt is its root", () => {
  const list = v.public.dayList;
  assert.equal(listProblem(list), null);
  assert.equal(list.root, receiptHash(list.receipts[0]));
  assert.deepEqual(v.public.record, dayRecord(list));
});
