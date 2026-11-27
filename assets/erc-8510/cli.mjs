// SPDX-License-Identifier: CC0-1.0
// Command line for receipts.mjs; README.md lists the commands and exit codes.
import { readFileSync } from "node:fs";

import { dayList, findRecord, listProblem, parseJson, proof, readDay, receiptProblem, recordListProblem, verifyProof } from "./receipts.mjs";

const USAGE = `usage:
  node cli.mjs verify <receipt.json>
  node cli.mjs root <day.jsonl> [<day> <signer>]
  node cli.mjs prove <day.jsonl> <index>
  node cli.mjs check <day-list.json>
  node cli.mjs check-proof <receipt.json> <proof.json> <root>
  node cli.mjs check-record <record.json> <day-list.json>
  node cli.mjs find-record <rpc-url> <day-list.json> [<blocks-per-query>]`;

class Usage extends Error {}

function read(file) {
  try {
    return readFileSync(file, "utf8");
  } catch (error) {
    throw new Error(`cannot read ${file}: ${error.code ?? error.message}`);
  }
}

function json(file) {
  const text = read(file);
  try {
    return parseJson(text);
  } catch (error) {
    throw new Error(`${file} is not JSON: ${error.message}`);
  }
}

const passes = (why) => {
  if (why) throw new Error(`invalid: ${why}`);
  return "valid";
};

function day(file, date = null, signer = null) {
  const found = readDay(read(file), date, signer);
  return dayList(found.day, found.signer, found.receipts, found.unreadable);
}

const COMMANDS = {
  verify: { arity: [1], run: ([file]) => passes(receiptProblem(json(file))) },
  root: {
    arity: [1, 3],
    run: ([file, date, signer]) => {
      const { receipts, ...list } = day(file, date, signer);
      return JSON.stringify(list, null, 2);
    },
  },
  prove: {
    arity: [2],
    run: ([file, index]) => {
      if (!/^(0|[1-9][0-9]*)$/.test(index)) throw new Usage(`the index must be a whole number without leading zeros\n${USAGE}`);
      return JSON.stringify(proof(day(file).receipts, Number(index)), null, 2);
    },
  },
  check: { arity: [1], run: ([file]) => passes(listProblem(json(file))) },
  "check-proof": {
    arity: [3],
    run: ([receiptFile, proofFile, root]) => {
      const value = json(proofFile);
      const siblings = Array.isArray(value) ? value : value?.proof;
      return passes(verifyProof(json(receiptFile), siblings, root) ? null : "the root does not cover this receipt with this proof");
    },
  },
  "check-record": {
    arity: [2],
    run: ([recordFile, listFile]) => {
      const list = json(listFile);
      return passes(listProblem(list) ?? recordListProblem(json(recordFile), list));
    },
  },
  "find-record": {
    arity: [2, 3],
    run: async ([rpcUrl, listFile, chunk = "50000"]) => {
      if (!/^[1-9][0-9]*$/.test(chunk)) throw new Usage(`blocks-per-query must be a positive whole number\n${USAGE}`);
      const found = await findRecord(rpcUrl, json(listFile), { chunk: Number(chunk) });
      if (!found) throw new Error("no record for this day yet");
      const { problem, ...where } = found;
      console.log(JSON.stringify(where, null, 2));
      return passes(problem);
    },
  },
};

try {
  const [command, ...args] = process.argv.slice(2);
  const entry = COMMANDS[command];
  if (!entry || !entry.arity.includes(args.length)) throw new Usage(USAGE);
  console.log(await entry.run(args));
} catch (error) {
  console.error(error.message);
  process.exit(error instanceof Usage ? 2 : 1);
}
