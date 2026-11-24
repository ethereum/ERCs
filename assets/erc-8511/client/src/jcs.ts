import { keccak256, toBytes, type Hex } from "viem";

/**
 * RFC 8785 (JSON Canonicalization Scheme) for the JSON a policy document can contain: objects with keys
 * sorted by UTF-16 code units, arrays in order, ECMAScript number serialization, minimal string escaping.
 * Non-finite numbers and non-JSON values are rejected.
 */
export function canonicalize(value: unknown): string {
  if (value === null) return "null";
  switch (typeof value) {
    case "boolean":
      return value ? "true" : "false";
    case "number":
      if (!Number.isFinite(value)) throw new Error("JCS: non-finite number");
      return JSON.stringify(value); // ECMAScript Number serialization, as RFC 8785 requires
    case "string":
      return JSON.stringify(value);
    case "object": {
      if (Array.isArray(value)) return `[${value.map(canonicalize).join(",")}]`;
      const o = value as Record<string, unknown>;
      const keys = Object.keys(o).filter((k) => o[k] !== undefined).sort();
      return `{${keys.map((k) => `${JSON.stringify(k)}:${canonicalize(o[k])}`).join(",")}}`;
    }
    default:
      throw new Error(`JCS: cannot canonicalize ${typeof value}`);
  }
}

/** policyHash = keccak256 of the UTF-8 bytes of the document's JCS form. */
export function policyHash(document: unknown): Hex {
  return keccak256(toBytes(canonicalize(document)));
}
