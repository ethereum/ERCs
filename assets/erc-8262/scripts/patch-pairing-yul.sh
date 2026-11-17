#!/usr/bin/env bash
#
# Patch a bb-generated UltraHonk verifier in two ways:
#
#   1. Replace the abi.encodePacked-based pairing() free function with an inline
#      Yul equivalent. Saves ~186 bytes per verifier, bringing each generated
#      verifier under the EIP-170 24,576 B limit. (Credit: Merkle Bonsai.)
#
#   2. Annotate the six remaining `assembly { ... }` blocks emitted by `bb` as
#      `assembly ("memory-safe") { ... }`. Each block grabs the free memory
#      pointer, does its work in scratch space, and advances `mload(0x40)`
#      before returning -- the standard memory-safe pattern, just unannotated
#      by `bb`. Adding the marker lets the via-IR pipeline reorder operations
#      across the block, which in turn lets `forge coverage` (via-IR required)
#      compile the giant `HonkVerificationKey.loadVerificationKey()` struct
#      literal without "stack too deep".
#
# Idempotent: skips files that are already patched.
#
# Usage: patch-pairing-yul.sh <verifier.sol>
#
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <verifier.sol>" >&2
    exit 2
fi

FILE="$1"
if [[ ! -f "$FILE" ]]; then
    echo "error: $FILE not found" >&2
    exit 1
fi

apply_pairing_yul() {
    # Already patched: a Yul-bodied pairing contains this exact marker.
    if grep -q 'staticcall(gas(), 0x08, m, 0x180, m, 0x20)' "$FILE"; then
        return 0
    fi

    # Sanity-check the function we're replacing exists in the expected form.
    if ! grep -q 'function pairing(Honk.G1Point memory rhs, Honk.G1Point memory lhs) view returns (bool decodedResult) {' "$FILE"; then
        echo "error: pairing() free function not found in $FILE -- bb output format may have changed" >&2
        exit 1
    fi

    perl -i -0777 -pe '
        s{
            ^function\ pairing\(Honk\.G1Point\ memory\ rhs,\ Honk\.G1Point\ memory\ lhs\)\ view\ returns\ \(bool\ decodedResult\)\ \{\n
            .*?
            ^\}\n
        }{function pairing(Honk.G1Point memory rhs, Honk.G1Point memory lhs) view returns (bool decodedResult) {
    assembly ("memory-safe") {
        let m := mload(0x40)
        mstore(m, mload(rhs))
        mstore(add(m, 0x20), mload(add(rhs, 0x20)))
        mstore(add(m, 0x40), 0x198e9393920d483a7260bfb731fb5d25f1aa493335a9e71297e485b7aef312c2)
        mstore(add(m, 0x60), 0x1800deef121f1e76426a00665e5c4479674322d4f75edadd46debd5cd992f6ed)
        mstore(add(m, 0x80), 0x090689d0585ff075ec9e99ad690c3395bc4b313370b38ef355acdadcd122975b)
        mstore(add(m, 0xa0), 0x12c85ea5db8c6deb4aab71808dcb408fe3d1e7690c43d37b4ce6cc0166fa7daa)
        mstore(add(m, 0xc0), mload(lhs))
        mstore(add(m, 0xe0), mload(add(lhs, 0x20)))
        mstore(add(m, 0x100), 0x260e01b251f6f1c7e7ff4e580791dee8ea51d87a358e038b4efe30fac09383c1)
        mstore(add(m, 0x120), 0x0118c4d5b837bcc2bc89b5b398b5974e9f5944073b32078b7e231fec938883b0)
        mstore(add(m, 0x140), 0x04fc6369f7110fe3d25156c1bb9a72859cf2a04641f99ba4ee413c80da6a5fe4)
        mstore(add(m, 0x160), 0x22febda3c0c0632a56475b4214e5615e11e6dd3f96e6cea2854a87d4dacc5e55)
        let success := staticcall(gas(), 0x08, m, 0x180, m, 0x20)
        decodedResult := and(success, eq(mload(m), 1))
    }
}
}msx;
    ' "$FILE"

    if ! grep -q 'staticcall(gas(), 0x08, m, 0x180, m, 0x20)' "$FILE"; then
        echo "error: pairing patch did not apply cleanly to $FILE" >&2
        exit 1
    fi
}

annotate_memory_safe() {
    # Each plain `<indent>assembly {` line becomes `<indent>assembly ("memory-safe") {`.
    # The trailing `\{$` anchor avoids touching lines already annotated as
    # `assembly ("memory-safe") {`. Run only after the pairing rewrite, which
    # already emits the annotated form for the pairing block.
    perl -i -pe 's|^(\s*)assembly \{$|${1}assembly ("memory-safe") {|' "$FILE"
}

apply_pairing_yul
annotate_memory_safe
