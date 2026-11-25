---
title: Post-Quantum Validator Keystore
description: Keystore for the post-quantum validator seeds of Ethereum validators and builders
author: Manu Nalepa (@nalepae)
discussions-to: https://ethereum-magicians.org/t/TBD
status: Draft
type: Standards Track
category: ERC
created: 2026-11-25
requires: 2335, 8517
---

## Abstract

This standard defines a JSON keystore that encrypts the validator seed of [ERC-8517](./eip-8517.md) under a password. One keystore holds the secret from which the post-quantum material of one validator or builder is regenerated: its leanXMSS signing key and, for a validator, its verifiable random function (VRF) tree. It also holds the leanXMSS public key, in clear. The format is the one of [ERC-2335](./eip-2335.md) with a 256-bit cipher and the version `5`.

## Motivation

[ERC-2335](./eip-2335.md) is the format in which deposit tools hand validator keys to validator clients and remote signers. It stores one BLS12-381 secret key under AES-128. Post-quantum consensus needs a leanXMSS signing key and a VRF tree per validator, both generated from 32-octet seeds. [ERC-8517](./eip-8517.md) derives both seeds from one validator seed.

Without a standard keystore, each tool chooses which seed to encrypt, and keys cannot move between tools. This standard keeps everything [ERC-2335](./eip-2335.md) tools already implement, and changes only what post-quantum keys require.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

A keystore of this standard is a keystore of [ERC-2335](./eip-2335.md) with the changes of this section. Everything this section does not change, including the password requirements, the modules and the `description` and `uuid` fields, is as in [ERC-2335](./eip-2335.md).

### Secret

The secret encrypted in the keystore is the 32-octet validator seed of [ERC-8517](./eip-8517.md). The leanXMSS seed and the VRF seed are expanded from it as [ERC-8517](./eip-8517.md) specifies. A keystore MUST NOT hold a leanXMSS seed or a VRF seed in place of the validator seed.

The secret is 32 octets.

### Decryption key

The `kdf` module is as in [ERC-2335](./eip-2335.md), with `"scrypt"` or `"pbkdf2"`, except that `dklen` MUST be `64`. The decryption key is therefore 64 octets.

### Password verification

Password verification is as in [ERC-2335](./eip-2335.md#password-verification), except that `DK_slice` is the second half of the 64-octet decryption key, `decryption_key[32:64]`, instead of `decryption_key[16:32]`:

```text
0. DK_slice = decryption_key[32:64]
1. pre_image = DK_slice | cipher_message
2. checksum = SHA256(pre_image)
3. valid_password = checksum == checksum_message
4. return valid_password
```

### Secret decryption

The cipher is AES-256 in counter mode. Its key is the first half of the decryption key, `decryption_key[0:32]`.

| Cipher               | `"function"`    | `"params"`               | `"message"` | Definition                                      |
|----------------------|-----------------|--------------------------|-------------|-------------------------------------------------|
| AES-256 Counter Mode | `"aes-256-ctr"` | <ul><li>`"iv"`</li></ul> |             | [RFC 3686](https://www.rfc-editor.org/rfc/rfc3686) |
### Scheme

The `scheme` field names the post-quantum keys of the keystore. Its value is `"leanxmss"`: a leanXMSS key and a VRF tree, generated from their seeds as EthLib specifies. A tool MUST refuse a keystore whose `scheme` it does not know.

### PubKey

The `pubkey` is the 32-octet leanXMSS public key generated from the leanXMSS seed, encoded in hexadecimal.

### Path

The `path` is the [ERC-8517](./eip-8517.md) path of the validator seed, for example `m/5326/3600/0`. It is the empty string `""` when the path is unknown, for example when the validator seed was not derived with [ERC-8517](./eip-8517.md).

### Version

The `version` is set to `5`.

### Loading

The signer that loads a keystore decrypts the validator seed and derives the leanXMSS seed from it, as [ERC-8517](./eip-8517.md) specifies. For a validator, it also derives the VRF seed.

A tool that decrypts a keystore MUST check that the leanXMSS public key generated from the decrypted seed equals `pubkey`, and MUST refuse the keystore otherwise.

A tool MUST NOT write the validator seed or the seeds derived from it to storage unless they are encrypted at least as strongly as the keystore. It MAY hold them in memory while it signs.

### Signing state

The keystore holds no signing state. It is not modified after it is created, as in [ERC-2335](./eip-2335.md). The leaves a leanXMSS key has signed at are recorded by the signer, outside the keystore.

### JSON schema

```json
{
    "$ref": "#/definitions/Keystore",
    "definitions": {
        "Keystore": {
            "type": "object",
            "properties": {
                "crypto": {
                    "type": "object",
                    "properties": {
                        "kdf": {
                            "$ref": "#/definitions/Module"
                        },
                        "checksum": {
                            "$ref": "#/definitions/Module"
                        },
                        "cipher": {
                            "$ref": "#/definitions/Module"
                        }
                    }
                },
                "description": {
                    "type": "string"
                },
                "scheme": {
                    "type": "string",
                    "enum": ["leanxmss"]
                },
                "pubkey": {
                    "type": "string",
                    "pattern": "^[0-9a-f]{64}$"
                },
                "path": {
                    "type": "string"
                },
                "uuid": {
                    "type": "string",
                    "format": "uuid"
                },
                "version": {
                    "type": "integer",
                    "const": 5
                }
            },
            "required": [
                "crypto",
                "scheme",
                "pubkey",
                "path",
                "uuid",
                "version"
            ],
            "title": "Keystore"
        },
        "Module": {
            "type": "object",
            "properties": {
                "function": {
                    "type": "string"
                },
                "params": {
                    "type": "object"
                },
                "message": {
                    "type": "string"
                }
            },
            "required": [
                "function",
                "message",
                "params"
            ]
        }
    }
}
```

## Rationale

### The validator seed as the secret

One validator seed gives both the leanXMSS key and the VRF tree of a validator. One keystore and one password therefore protect both. Encrypting the leanXMSS seed and the VRF seed separately would need two ciphertexts, or two keystores that can be separated by mistake. The [ERC-8517](./eip-8517.md) path recorded next to it lets a tool show where the seed comes from, as the path of [ERC-2335](./eip-2335.md) does.

### AES-256 and a 64-octet decryption key

Grover's algorithm searches a key of `k` bits in about `2^(k/2)` steps. AES-128 then keeps about 64 bits of security against a quantum adversary, and AES-256 about 128 bits. The keys of this keystore protect stake for the lifetime of post-quantum consensus. The cipher is therefore chosen for that adversary.

A strong password, not the cipher, remains what protects a keystore. The KDF modules are those of [ERC-2335](./eip-2335.md). Tools therefore reuse their implementations.

### Counter mode and SHA-256 checksum

An authenticated cipher such as AES-GCM would replace the checksum. It would also be a new module in every tool, for no gain over the checksum of [ERC-2335](./eip-2335.md), which already rejects a wrong password and a modified ciphertext.

### The public key in clear

Validator clients, remote signers and key management tools list and route keys by public key. Storing the leanXMSS public key lets them do so without the password, as the `pubkey` of [ERC-2335](./eip-2335.md) does. Generating it from the seed needs the top tree of leanXMSS, about 2^24 hashes: a few seconds on one core, paid once when the keystore is created, instead of at every start of every tool.

### One scheme identifier

The parameters of leanXMSS and of the VRF tree are fixed by their specification. A keystore that repeated them could only disagree with it. If the parameters change, the new scheme gets a new identifier.

### No signing state

A keystore is copied, backed up and moved between machines. A counter of signed leaves stored in it would be stale in every copy but one, and a tool trusting a stale copy would sign again at a used leaf. Signing state therefore stays with the signer, which records signed messages as validator clients already do with slashing protection data.

### Version 5

Version `3` is the Web3 Secret Storage format, and version `4` is [ERC-2335](./eip-2335.md). A tool that reads version `4` refuses version `5` instead of reading the validator seed as a BLS secret key.

## Backwards Compatibility

This standard does not change [ERC-2335](./eip-2335.md) keystores. A tool that supports both formats tells them apart by `version`. A tool that only reads version `4` refuses keystores of this standard.

## Test Cases

Both test cases encrypt the validator seed of test case 0 of [ERC-8517](./eip-8517.md), whose path is `m/5326/3600/0`.

Password `"𝔱𝔢𝔰𝔱𝔭𝔞𝔰𝔰𝔴𝔬𝔯𝔡🔑"`
Encoded Password: `0x7465737470617373776f7264f09f9491`
Secret `0x657768d4c2ef1a1e7a2ec5c4af4eb818415cff8a1d52fa943ca13b5ad3b1e5bc`

The leanXMSS seed is `0x813fc0f31d0f32e8089a587de4d3765b4349e3fdf71409892a29d296fb7d3645`.

### Scrypt Test Vector

```json
{
    "crypto": {
        "kdf": {
            "function": "scrypt",
            "params": {
                "dklen": 64,
                "n": 262144,
                "p": 1,
                "r": 8,
                "salt": "d4e56740f876aef8c010b86a40d5f56745a118d0906a34e69aec8c0db1cb8fa3"
            },
            "message": ""
        },
        "checksum": {
            "function": "sha256",
            "params": {},
            "message": "ea05bd4b1782e262cf303f2fcfcb10c1e5d8d6108b871fff258585cc3cd9ea02"
        },
        "cipher": {
            "function": "aes-256-ctr",
            "params": {
                "iv": "264daa3f303d7259501c93d997d84fe6"
            },
            "message": "5c7723f9aab15dd5fe498122bb039de458eb07caaab5efe3b514dfe59b8114df"
        }
    },
    "description": "This is a test keystore that uses scrypt to secure the secret.",
    "scheme": "leanxmss",
    "pubkey": "201f6760dc3095d1e7b7da447ca7108c827f0044dcde80ff64ad8ea21e13ef10",
    "path": "m/5326/3600/0",
    "uuid": "8c5b9f4a-2f0e-4b6d-9a3c-1e7d5f2b8a60",
    "version": 5
}
```

### PBKDF2 Test Vector

```json
{
    "crypto": {
        "kdf": {
            "function": "pbkdf2",
            "params": {
                "dklen": 64,
                "c": 262144,
                "prf": "hmac-sha256",
                "salt": "d4e56740f876aef8c010b86a40d5f56745a118d0906a34e69aec8c0db1cb8fa3"
            },
            "message": ""
        },
        "checksum": {
            "function": "sha256",
            "params": {},
            "message": "d7cf92131c05415193789166f03d2f8f05384abed3c52d7939c7b8788f5d804c"
        },
        "cipher": {
            "function": "aes-256-ctr",
            "params": {
                "iv": "264daa3f303d7259501c93d997d84fe6"
            },
            "message": "93b67e24f8155763849280442fa95458c3afa8567f8c2cfe90958af1f17daad5"
        }
    },
    "description": "This is a test keystore that uses PBKDF2 to secure the secret.",
    "scheme": "leanxmss",
    "pubkey": "201f6760dc3095d1e7b7da447ca7108c827f0044dcde80ff64ad8ea21e13ef10",
    "path": "m/5326/3600/0",
    "uuid": "3e1f7a92-6c4d-4b8e-b5a1-9d2c0f6e7b34",
    "version": 5
}
```

## Reference Implementation

```python
import hashlib
import unicodedata

from Crypto.Cipher import AES
from Crypto.Util import Counter


def encode_password(password: str) -> bytes:
    password = unicodedata.normalize("NFKD", password)

    # Strip the C0, Delete and C1 control codes.
    password = "".join(
        c for c in password if not (ord(c) <= 0x1F or 0x7F <= ord(c) <= 0x9F)
    )

    return password.encode()


def decryption_key(password: bytes, kdf: dict) -> bytes:
    params = kdf["params"]
    assert params["dklen"] == 64

    salt = bytes.fromhex(params["salt"])

    if kdf["function"] == "scrypt":
        return hashlib.scrypt(
            password,
            salt=salt,
            n=params["n"],
            r=params["r"],
            p=params["p"],
            dklen=64,
            maxmem=2**31 - 1,
        )

    assert kdf["function"] == "pbkdf2"
    assert params["prf"] == "hmac-sha256"

    return hashlib.pbkdf2_hmac("sha256", password, salt, params["c"], 64)


def decrypt(keystore: dict, password: str) -> bytes:
    assert keystore["version"] == 5
    assert keystore["scheme"] == "leanxmss"

    crypto = keystore["crypto"]
    assert crypto["cipher"]["function"] == "aes-256-ctr"

    key = decryption_key(encode_password(password), crypto["kdf"])
    cipher_message = bytes.fromhex(crypto["cipher"]["message"])

    # Password verification: the second half of the decryption key.
    checksum = hashlib.sha256(key[32:64] + cipher_message).hexdigest()
    if checksum != crypto["checksum"]["message"]:
        raise ValueError("invalid password")

    # Secret decryption: the first half of the decryption key.
    iv = int.from_bytes(bytes.fromhex(crypto["cipher"]["params"]["iv"]), "big")
    counter = Counter.new(128, initial_value=iv)
    cipher = AES.new(key[0:32], AES.MODE_CTR, counter=counter)

    return cipher.decrypt(cipher_message)
```

The decrypted validator seed is then expanded with [ERC-8517](./eip-8517.md), and the public key is checked against `pubkey`.

## Security Considerations

### Reuse of leanXMSS leaves

Copying an [ERC-2335](./eip-2335.md) keystore is harmless: a BLS key can sign any number of messages. A leanXMSS key cannot. Two signatures at the same leaf over different messages allow forgeries, and the keystore does not record which leaves were used. A tool that imports a keystore, or restores it from a backup, MUST NOT sign with it unless it also holds the signing history of the key, such as the signing protection data of its previous signer. A keystore MUST NOT be loaded by two signers at the same time.

### Password strength

The cipher and the KDF protect the validator seed only as well as the password does. A password with less than 128 bits of entropy is the weakest part of the keystore, against both classical and quantum adversaries. The KDF parameters of the test vectors are a minimum.

### Public material

`pubkey` and `path` are not encrypted. They reveal which validator a keystore belongs to, and that it was derived from a mnemonic, but nothing about the validator seed.

### Unverified public material

An attacker who can modify a keystore can replace `pubkey` without knowing the password. A tool that registers keys from this field without decrypting the keystore registers keys it may not control. The loading check of this standard detects the change once the keystore is decrypted. A tool SHOULD decrypt the keystore and run it before building a registration.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
