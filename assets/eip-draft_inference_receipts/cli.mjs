// node cli.mjs verify <receipt.json>            the receipt is well formed and signed by its signer
// node cli.mjs root <day.jsonl>                 the day list for a day file: count, root, unreadable lines
// node cli.mjs prove <day.jsonl> <index>        the proof for one receipt, checked against the day root
// node cli.mjs check <day-list.json>            a served day list: every receipt valid, its count and root right
import { readFileSync } from "node:fs";

import { dayList, dayOf, dayRoot, listProblem, problem, proof, readDay, verifyProof } from "./receipts.mjs";

const [command, file, arg] = process.argv.slice(2);
const read = () => readFileSync(file, "utf8");
const fail = (message) => {
  console.error(message);
  process.exit(1);
};

if (command === "verify") {
  const why = problem(JSON.parse(read()));
  if (why) fail(`invalid: ${why}`);
  console.log("valid");
} else if (command === "root" || command === "prove") {
  const { receipts, unreadable } = readDay(read());
  if (!receipts.length) fail("no readable receipts");
  for (const [i, r] of receipts.entries()) if (problem(r)) fail(`receipt ${i}: ${problem(r)}`);
  if (command === "root") {
    const { receipts: _, ...list } = dayList(dayOf(receipts[0]), receipts[0].signer, receipts, unreadable);
    console.log(JSON.stringify(list, null, 2));
  } else {
    const index = Number(arg), path = proof(receipts, index), root = dayRoot(receipts);
    console.log(JSON.stringify({ index, proof: path, root, valid: verifyProof(receipts[index], path, root) }, null, 2));
  }
} else if (command === "check") {
  const why = listProblem(JSON.parse(read()));
  if (why) fail(`invalid: ${why}`);
  console.log("valid");
} else {
  fail("usage: node cli.mjs verify <receipt.json> | root <day.jsonl> | prove <day.jsonl> <index> | check <day-list.json>");
}
