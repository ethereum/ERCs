// SPDX-License-Identifier: CC0-1.0
//
// FrameIntrospector: exposes the EIP-8141 (Draft, 2026) introspection opcodes behind the
// IFrameIntrospector ABI. Solidity inline assembly cannot emit unknown opcodes, so this is a
// standalone Yul object using `verbatim`. Stateless, no owner, read-only.
//
// Opcodes (EIP-8141 Draft):
//   TXPARAM       0xB0  in: param                                out: value
//   FRAMEDATACOPY 0xB2  in: memOffset, dataOffset, length, frameIndex (top-0 first)
//   FRAMEPARAM    0xB3  in: frameIndex, param                     out: value
// Yul pushes builtin and verbatim arguments right-to-left, so the FIRST verbatim argument is
// top-0 of the stack, matching the opcode stack order above.
//
// Every opcode halts exceptionally outside a frame transaction, so every call reverts there.
// NOT executable on today's EVM. Requires an EIP-8141 client. Tests use MockFrameIntrospector.

object "FrameIntrospector" {
    code {
        datacopy(0, dataoffset("runtime"), datasize("runtime"))
        return(0, datasize("runtime"))
    }
    object "runtime" {
        code {
            // TXPARAM params
            // 0x02 SENDER, 0x0A CURRENT_FRAME_INDEX
            // FRAMEPARAM params
            // 0x00 RESOLVED_TARGET, 0x02 MODE, 0x03 FLAGS, 0x04 DATA_LENGTH, 0x08 VALUE

            if callvalue() { revert(0, 0) }
            if lt(calldatasize(), 4) { revert(0, 0) }

            switch shr(224, calldataload(0))
            case 0x725a1145 /* currentFrameIndex() */ { ret(txparam(0x0a)) }
            case 0x1255178d /* txSender() */ { ret(txparam(0x02)) }
            case 0x9e19777b /* frameMode(uint256) */ { ret(frameparam(arg0(), 0x02)) }
            case 0x99af1aac /* frameFlags(uint256) */ { ret(frameparam(arg0(), 0x03)) }
            case 0x5a63d226 /* frameTarget(uint256) */ { ret(frameparam(arg0(), 0x00)) }
            case 0x28a6c641 /* frameValue(uint256) */ { ret(frameparam(arg0(), 0x08)) }
            case 0xb6481b8f /* frameData(uint256) */ {
                let i := arg0()
                let len := frameparam(i, 0x04)
                // ABI: offset (0x20) | length | data (padded to 32 bytes)
                mstore(0x00, 0x20)
                mstore(0x20, len)
                let padded := and(add(len, 31), not(31))
                mstore(add(0x40, sub(padded, 0x20)), 0) // zero the tail word before copying
                framedatacopy(0x40, 0, len, i)
                return(0x00, add(0x40, padded))
            }
            default { revert(0, 0) }

            function arg0() -> v {
                if lt(calldatasize(), 36) { revert(0, 0) }
                v := calldataload(4)
            }

            function ret(v) {
                mstore(0, v)
                return(0, 32)
            }

            function txparam(param) -> v {
                v := verbatim_1i_1o(hex"b0", param)
            }

            function frameparam(frameIndex, param) -> v {
                v := verbatim_2i_1o(hex"b3", frameIndex, param)
            }

            function framedatacopy(memOffset, dataOffset, length, frameIndex) {
                verbatim_4i_0o(hex"b2", memOffset, dataOffset, length, frameIndex)
            }
        }
    }
}
