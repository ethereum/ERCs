// Minimal RFC 8785 (JCS) canonicalisation sufficient for AID documents:
// objects with sorted keys, no whitespace, integers only (no floats with exponent), strings JSON-escaped.
function canonicalize(v) {
  if (v === null || typeof v === "boolean") return JSON.stringify(v);
  if (typeof v === "number") {
    if (!Number.isFinite(v)) throw new Error("non-finite number");
    if (Number.isInteger(v)) return String(v);
    // RFC 8785 uses ES6 Number-to-string; JSON.stringify matches for finite doubles
    return JSON.stringify(v);
  }
  if (typeof v === "string") return JSON.stringify(v);
  if (Array.isArray(v)) return "[" + v.map(canonicalize).join(",") + "]";
  if (typeof v === "object") {
    const keys = Object.keys(v).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0)); // code-unit order
    return "{" + keys.map((k) => JSON.stringify(k) + ":" + canonicalize(v[k])).join(",") + "}";
  }
  throw new Error("unsupported type " + typeof v);
}
module.exports = { canonicalize };
