"""
@title ERC-8270: Canonical Validator Wrapper — Format Helpers
@license CC0
@author bbjubjub.eth
@dev these functions waste gas: they should be used in view functions running off-chain.
"""

# pragma version ==0.4.3
# pragma evm-version prague


@pure
def bytes32_to_hex(data: bytes32) -> String[64]:
    v: uint256 = convert(data, uint256)
    return concat(
        self.to_hex(v >> 248),
        self.to_hex(v >> 240),
        self.to_hex(v >> 232),
        self.to_hex(v >> 224),
        self.to_hex(v >> 216),
        self.to_hex(v >> 208),
        self.to_hex(v >> 200),
        self.to_hex(v >> 192),
        self.to_hex(v >> 184),
        self.to_hex(v >> 176),
        self.to_hex(v >> 168),
        self.to_hex(v >> 160),
        self.to_hex(v >> 152),
        self.to_hex(v >> 144),
        self.to_hex(v >> 136),
        self.to_hex(v >> 128),
        self.to_hex(v >> 120),
        self.to_hex(v >> 112),
        self.to_hex(v >> 104),
        self.to_hex(v >> 96),
        self.to_hex(v >> 88),
        self.to_hex(v >> 80),
        self.to_hex(v >> 72),
        self.to_hex(v >> 64),
        self.to_hex(v >> 56),
        self.to_hex(v >> 48),
        self.to_hex(v >> 40),
        self.to_hex(v >> 32),
        self.to_hex(v >> 24),
        self.to_hex(v >> 16),
        self.to_hex(v >> 8),
        self.to_hex(v),
    )


@pure
def bytes16_to_hex(data: bytes16) -> String[32]:
    v: uint256 = convert(data, uint256)
    return concat(
        self.to_hex(v >> 120),
        self.to_hex(v >> 112),
        self.to_hex(v >> 104),
        self.to_hex(v >> 96),
        self.to_hex(v >> 88),
        self.to_hex(v >> 80),
        self.to_hex(v >> 72),
        self.to_hex(v >> 64),
        self.to_hex(v >> 56),
        self.to_hex(v >> 48),
        self.to_hex(v >> 40),
        self.to_hex(v >> 32),
        self.to_hex(v >> 24),
        self.to_hex(v >> 16),
        self.to_hex(v >> 8),
        self.to_hex(v),
    )


@pure
def address_to_hex_erc55(addr: address) -> String[40]:
    plain: String[40] = self.address_to_hex(addr)
    checksum: uint256 = convert(keccak256(plain), uint256)
    return concat(
        self.erc55_process_nibble(checksum >> 252, slice(plain, 0, 1)),
        self.erc55_process_nibble(checksum >> 248, slice(plain, 1, 1)),
        self.erc55_process_nibble(checksum >> 244, slice(plain, 2, 1)),
        self.erc55_process_nibble(checksum >> 240, slice(plain, 3, 1)),
        self.erc55_process_nibble(checksum >> 236, slice(plain, 4, 1)),
        self.erc55_process_nibble(checksum >> 232, slice(plain, 5, 1)),
        self.erc55_process_nibble(checksum >> 228, slice(plain, 6, 1)),
        self.erc55_process_nibble(checksum >> 224, slice(plain, 7, 1)),
        self.erc55_process_nibble(checksum >> 220, slice(plain, 8, 1)),
        self.erc55_process_nibble(checksum >> 216, slice(plain, 9, 1)),
        self.erc55_process_nibble(checksum >> 212, slice(plain, 10, 1)),
        self.erc55_process_nibble(checksum >> 208, slice(plain, 11, 1)),
        self.erc55_process_nibble(checksum >> 204, slice(plain, 12, 1)),
        self.erc55_process_nibble(checksum >> 200, slice(plain, 13, 1)),
        self.erc55_process_nibble(checksum >> 196, slice(plain, 14, 1)),
        self.erc55_process_nibble(checksum >> 192, slice(plain, 15, 1)),
        self.erc55_process_nibble(checksum >> 188, slice(plain, 16, 1)),
        self.erc55_process_nibble(checksum >> 184, slice(plain, 17, 1)),
        self.erc55_process_nibble(checksum >> 180, slice(plain, 18, 1)),
        self.erc55_process_nibble(checksum >> 176, slice(plain, 19, 1)),
        self.erc55_process_nibble(checksum >> 172, slice(plain, 20, 1)),
        self.erc55_process_nibble(checksum >> 168, slice(plain, 21, 1)),
        self.erc55_process_nibble(checksum >> 164, slice(plain, 22, 1)),
        self.erc55_process_nibble(checksum >> 160, slice(plain, 23, 1)),
        self.erc55_process_nibble(checksum >> 156, slice(plain, 24, 1)),
        self.erc55_process_nibble(checksum >> 152, slice(plain, 25, 1)),
        self.erc55_process_nibble(checksum >> 148, slice(plain, 26, 1)),
        self.erc55_process_nibble(checksum >> 144, slice(plain, 27, 1)),
        self.erc55_process_nibble(checksum >> 140, slice(plain, 28, 1)),
        self.erc55_process_nibble(checksum >> 136, slice(plain, 29, 1)),
        self.erc55_process_nibble(checksum >> 132, slice(plain, 30, 1)),
        self.erc55_process_nibble(checksum >> 128, slice(plain, 31, 1)),
        self.erc55_process_nibble(checksum >> 124, slice(plain, 32, 1)),
        self.erc55_process_nibble(checksum >> 120, slice(plain, 33, 1)),
        self.erc55_process_nibble(checksum >> 116, slice(plain, 34, 1)),
        self.erc55_process_nibble(checksum >> 112, slice(plain, 35, 1)),
        self.erc55_process_nibble(checksum >> 108, slice(plain, 36, 1)),
        self.erc55_process_nibble(checksum >> 104, slice(plain, 37, 1)),
        self.erc55_process_nibble(checksum >> 100, slice(plain, 38, 1)),
        self.erc55_process_nibble(checksum >> 96, slice(plain, 39, 1)),
    )


@pure
def address_to_hex(addr: address) -> String[40]:
    v: uint256 = convert(addr, uint256)
    return concat(
        self.to_hex(v >> 152),
        self.to_hex(v >> 144),
        self.to_hex(v >> 136),
        self.to_hex(v >> 128),
        self.to_hex(v >> 120),
        self.to_hex(v >> 112),
        self.to_hex(v >> 104),
        self.to_hex(v >> 96),
        self.to_hex(v >> 88),
        self.to_hex(v >> 80),
        self.to_hex(v >> 72),
        self.to_hex(v >> 64),
        self.to_hex(v >> 56),
        self.to_hex(v >> 48),
        self.to_hex(v >> 40),
        self.to_hex(v >> 32),
        self.to_hex(v >> 24),
        self.to_hex(v >> 16),
        self.to_hex(v >> 8),
        self.to_hex(v),
    )


@pure
def to_hex_digit(nibble: uint256) -> String[1]:
    alphabet: String[16] = "0123456789abcdef"
    return slice(alphabet, nibble % 16, 1)


@pure
def to_hex(byte: uint256) -> String[2]:
    return concat(self.to_hex_digit(byte // 16), self.to_hex_digit(byte % 16))


@pure
def erc55_process_nibble(checksum: uint256, char: String[1]) -> String[1]:
    if checksum % 16 > 7:
        if char == "a":
            char = "A"
        elif char == "b":
            char = "B"
        elif char == "c":
            char = "C"
        elif char == "d":
            char = "D"
        elif char == "e":
            char = "E"
        elif char == "f":
            char = "F"
    return char
