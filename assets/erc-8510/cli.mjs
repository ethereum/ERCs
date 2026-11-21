// node cli.mjs verify <receipt.json>            the receipt is well formed and signed by its signer
// node cli.mjs root <day.jsonl>                 the day list of a day file: count, root, unreadable lines
// node cli.mjs prove <day.jsonl> <index>        the proof for the receipt at that index of the day list
// node cli.mjs check <day-list.json>            a served day list: shape, receipts, order, count and root
// Exit codes: 0 the check passed, 1 it failed or the input could not be read, 2 a usage mistake.
import { readFileSync } from "node:fs";

import { dayList, dayOf, listProblem, parseJson, problem, proof, readDay, receiptsProblem } from "./receipts.mjs";

const USAGE = "usage: node cli.mjs verify <receipt.json> | root <day.jsonl> | prove <day.jsonl> <index> | check <day-list.json>";

class Usage extends Error {}

function read(file) {
  if (!file) throw new Usage(USAGE);
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

/** The day list of a day file, refused unless every readable line is a valid receipt of one day and one signer. */
function list(file) {
  const { receipts, unreadable } = readDay(read(file));
  if (!receipts.length) throw new Error(`${file} holds no readable receipts`);
  const [first] = receipts;
  const day = typeof first.at === "string" ? dayOf(first) : undefined;
  const built = dayList(day, first.signer, receipts, unreadable);
  const why = receiptsProblem(built.day, built.signer, built.receipts);
  if (why) throw new Error(`invalid: ${why}`);
  return built;
}

function run([command, file, index]) {
  switch (command) {
    case "verify": {
      const why = problem(json(file));
      if (why) throw new Error(`invalid: ${why}`);
      return "valid";
    }
    case "root": {
      const { receipts, ...rest } = list(file);
      return JSON.stringify(rest, null, 2);
    }
    case "prove": {
      if (index === undefined || !/^\d+$/.test(index)) throw new Usage(`the index must be a whole number. ${USAGE}`);
      const { receipts } = list(file);
      return JSON.stringify({ index: Number(index), ...proof(receipts, Number(index)) }, null, 2);
    }
    case "check": {
      const why = listProblem(json(file));
      if (why) throw new Error(`invalid: ${why}`);
      return "valid";
    }
    default:
      throw new Usage(USAGE);
  }
}

try {
  console.log(run(process.argv.slice(2)));
} catch (error) {
  console.error(error.message);
  process.exit(error instanceof Usage ? 2 : 1);
}
