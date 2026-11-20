"""Known-answer tests for ethcrypto against published values."""
from ethcrypto import address_of_key, eip712_digest, jcs, keccak256, recover, sign, unhex


def test():
    # keccak256: published values
    assert keccak256(b"").hex() == "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
    assert keccak256(b"abc").hex() == "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45"
    # function selector of transfer(address,uint256) is 0xa9059cbb (multi-purpose check)
    assert keccak256(b"transfer(address,uint256)")[:4].hex() == "a9059cbb"
    # address of private key 1 (widely published)
    assert address_of_key(1) == "0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf"

    # EIP-712 specification example ("Ether Mail"): digest and signature from the EIP
    types = {"Person": [{"name": "name", "type": "string"}, {"name": "wallet", "type": "address"}],
             "Mail": [{"name": "from", "type": "Person"}, {"name": "to", "type": "Person"},
                      {"name": "contents", "type": "string"}]}
    domain = {"name": "Ether Mail", "version": "1", "chainId": 1,
              "verifyingContract": "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC"}
    msg = {"from": {"name": "Cow", "wallet": "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826"},
           "to": {"name": "Bob", "wallet": "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB"},
           "contents": "Hello, Bob!"}
    d = eip712_digest(types, "Mail", domain, msg)
    assert d.hex() == "be609aee343fb3c4b28e1df9e632fca64fcfaede20f02e86244efddf30957bd2", d.hex()
    sig = unhex("4355c47d63924e8a72e509b65029052eb6c299d53a04e167c5775fd466751c9d"
                "07299936d304c153f6443dfa05f40ff007d72911b6f72307f996231605b91562") + bytes([28])
    assert recover(d, sig) == "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826"

    # the EIP's signer key is keccak("cow"); our own signature must recover to it
    cow = int.from_bytes(keccak256(b"cow"), "big")
    assert address_of_key(cow) == "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826"
    assert recover(d, sign(cow, d)) == "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826"

    # JCS: sorted keys, no whitespace, floats rejected
    assert jcs({"b": 1, "a": [True, None, "x"]}) == b'{"a":[true,null,"x"],"b":1}'
    try:
        jcs({"x": 1.5})
        raise AssertionError("float accepted")
    except ValueError:
        pass
    print("ethcrypto: all known-answer tests pass")


if __name__ == "__main__":
    test()
