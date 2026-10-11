# ERC-8395 test vectors

Section references refer to [ERC-8395](../../ERCS/erc-8395.md).

The fixed private keys are public and MUST NOT hold assets:

| Role | Private key | Account ID |
| --- | --- | --- |
| Root | `0x0000000000000000000000000000000000000000000000000000000000000002` | `eip155:1:0x2b5ad5c4795c026514f8317c7a215e218dccd6cf` |
| Delegate A | `0x0000000000000000000000000000000000000000000000000000000000000003` | `eip155:1:0x6813eb9362372eef6200f3b1dbc3f819671cba69` |
| Delegate B | `0x0000000000000000000000000000000000000000000000000000000000000004` | `eip155:1:0x1eff47bc3a10a45d4b230b5d10e37751fe6aa718` |

The clock is `1700000001`, skew is 30 seconds, the effective origin is `https://api.example`, all three accounts have no code, replay state is empty, scope processing is supported, the route explicitly permits Delegated Request Signatures and requires `resource:read`, and Principal policy accepts Root. Neither a route request-validity maximum nor a grant-validity maximum is configured. The registry reports `(false, 7)` for Root and `(false, 3)` for Delegate A.

## EIP-712 grant vectors

JSON grant values below show the full EIP-712 signing data, including fields reconstructed from the chain rather than transmitted in CBOR.

`g0` is Root to Delegate A:

```json
{"issuer":"eip155:1:0x2b5ad5c4795c026514f8317c7a215e218dccd6cf","delegate":"eip155:1:0x6813eb9362372eef6200f3b1dbc3f819671cba69","audienceScopes":[{"audience":"https://api.example","scopes":["resource:read","resource:write"]},{"audience":"https://backup.example","scopes":["resource:read"]}],"id":"0x1111111111111111111111111111111111111111111111111111111111111111","epoch":7,"validAfter":1699999000,"validUntil":1700003600,"maxRequestValiditySeconds":60,"remainingDelegations":2,"delegateProfile":"erc8128-eoa","requireNonReplayable":true,"requiredComponents":["@authority"],"parentGrantHash":"0x0000000000000000000000000000000000000000000000000000000000000000"}
```

```text
domainSeparator = 0xbfa3ef2ffa516b4a513d3dc11b82f54744ff269a42a518551a62fd138e3c34d4
structHash_g0 = 0x585eb4ef34d6b8eee793dca2c929ea24f2f339928eedcaedfcc6470fec5cd4b3
B_g0 = 0x1901bfa3ef2ffa516b4a513d3dc11b82f54744ff269a42a518551a62fd138e3c34d4585eb4ef34d6b8eee793dca2c929ea24f2f339928eedcaedfcc6470fec5cd4b3
digest_g0 = 0x2eb367345c88e81888af6089940e946533ae6059f1c781369a29b7405b378620
signature_g0 = 0x18ec6f90b4a58fb9ea3a389accd20b22fcf3c7912beaa0e3b760b4d04306f1b53e68a8e1a674fea5d7ef33dd99bd43d02abaa43137ab0d9ef255bd081e01b4291b
```

`g1` is Delegate A to Delegate B:

```json
{"issuer":"eip155:1:0x6813eb9362372eef6200f3b1dbc3f819671cba69","delegate":"eip155:1:0x1eff47bc3a10a45d4b230b5d10e37751fe6aa718","audienceScopes":[{"audience":"https://api.example","scopes":["resource:read"]}],"id":"0x2222222222222222222222222222222222222222222222222222222222222222","epoch":3,"validAfter":1699999500,"validUntil":1700001800,"maxRequestValiditySeconds":60,"remainingDelegations":1,"delegateProfile":"erc8128-eoa","requireNonReplayable":true,"requiredComponents":["@method"],"parentGrantHash":"0x2eb367345c88e81888af6089940e946533ae6059f1c781369a29b7405b378620"}
```

```text
structHash_g1 = 0x2e275b47b3205bed22ceba7de7fb61286feaf2f2b35662ca1e04bb5cfb59d626
B_g1 = 0x1901bfa3ef2ffa516b4a513d3dc11b82f54744ff269a42a518551a62fd138e3c34d42e275b47b3205bed22ceba7de7fb61286feaf2f2b35662ca1e04bb5cfb59d626
digest_g1 = 0x9bfc92f42443547ff12d0d009d52e25863514cd919442ce737effbfa09b3c157
signature_g1 = 0x3dbca150c5f8a0890473d835db1a0fec9a2c2d0b27d3a37ccc57e497be9013520bbe53a75c69817b8a04c21a3fcc5832d67095c964fa197f1cb1569eab129d0d1b
```

Each mutation of `g0` below yields the listed `structHash`, with arrays hashed in their signed order:

| Mutation of `g0` | `structHash` |
| --- | --- |
| Give the `https://backup.example` entry no tokens; an empty array hashes as `keccak256("")` | `0xd3359780984197f85e7a02463c3260752f3229b6585094c614d24af245a26f35` |
| Append a third entry, `https://third.example` with no tokens | `0x1df75982d9d43c812b1e2e614ea11d0844be539771805522df430d0c6380d9a5` |
| Place that third entry first, before the two entries of `g0` | `0xf91667aeae12cad3fd871a37cc1d43e5bc50f12823145ab5ac98a2c7209613b1` |
| Swap the two tokens of the `https://api.example` entry | `0x057b742f524836323601d0b54d82310c6d3f33607d42a5eab89ef58beb66f3eb` |
| Give `requiredComponents` no entries | `0xde1bfc8159210631f47f87418e98132f0206bc8928914c126ac6c6f0b85bc67d` |
| Hashing only, as such a grant is invalid: one entry whose `audience` and only token are empty strings, and one empty-string required component | `0x0252d5f806cb38dc14db94899f2ec32e450a1356cacf1144d390259d14892393` |

## Single-link request vector

The `g0` Byte Sequence is 338 bytes. Its exact uninterrupted base64 value is:

```text
jXgzZWlwMTU1OjE6MHgyYjVhZDVjNDc5NWMwMjY1MTRmODMxN2M3YTIxNWUyMThkY2NkNmNmeDNlaXAxNTU6MToweDY4MTNlYjkzNjIzNzJlZWY2MjAwZjNiMWRiYzNmODE5NjcxY2JhNjmCgnNodHRwczovL2FwaS5leGFtcGxlgm1yZXNvdXJjZTpyZWFkbnJlc291cmNlOndyaXRlgnZodHRwczovL2JhY2t1cC5leGFtcGxlgW1yZXNvdXJjZTpyZWFkWCAREREREREREREREREREREREREREREREREREREREREREQcaZVPtGBplU/8QGDwCa2VyYzgxMjgtZW9h9YFqQGF1dGhvcml0eVhBGOxvkLSlj7nqOjiazNILIvzzx5Er6qDjt2C00EMG8bU+aKjhpnT+pdfvM92ZvUPQKrqkMTerDZ7yVb0IHgG0KRs=
```

For readability, `<G0>` in the following HTTP and signature-base blocks means the exact base64 bytes above. It MUST be substituted before parsing, transmission, hashing, or signing; the angle brackets are not part of the vector.

The complete request is:

```http
GET /resource?x=1 HTTP/1.1
Host: api.example
ERC-8128-Delegation: g0=:<G0>:
Signature-Input: request=("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="ASNFZ4mrze8QMlR2mLrc_g";keyid="eip155:1:0x6813eb9362372eef6200f3b1dbc3f819671cba69";tag="erc8128-delegated"
Signature: request=:+s7Ag8pBpYsf76mSs/8XOLi2aiGD0iqRsKT9LnKejt5FsSqALyDkoIxvQO4nmTIC0y997fMWMbY21s8fAp1DoBs=:
```

The exact 826-byte signature base is:

```text
"@scheme": https
"@authority": api.example
"@method": GET
"@path": /resource
"@query": ?x=1
"erc-8128-delegation";sf: g0=:<G0>:
"@signature-params": ("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="ASNFZ4mrze8QMlR2mLrc_g";keyid="eip155:1:0x6813eb9362372eef6200f3b1dbc3f819671cba69";tag="erc8128-delegated"
```

```text
H_request_g0 = 0xa83066be20c75ff394022784ea52b29379daa666c641f4c680e78ead0471c2fa
S_request_g0 = 0xfacec083ca41a58b1fefa992b3ff1738b8b66a2183d22a91b0a4fd2e729e8ede45b12a802f20e4a08c6f40ee27993202d32f7dedf31631b636d6cf1f029d43a01b
```

The expected Principal is Root and Signer is Delegate A. The request is Request-Bound and Non-Replayable, and only Delegate A's nonce is consumed.

## Depth-two request vector

The `g1` Byte Sequence is 262 bytes. Its exact uninterrupted base64 value is:

```text
jXgzZWlwMTU1OjE6MHgxZWZmNDdiYzNhMTBhNDVkNGIyMzBiNWQxMGUzNzc1MWZlNmFhNzE4gYJzaHR0cHM6Ly9hcGkuZXhhbXBsZYFtcmVzb3VyY2U6cmVhZFggIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIDGmVT7wwaZVP4CBg8AWtlcmM4MTI4LWVvYfWBZ0BtZXRob2RYIC6zZzRciOgYiK9giZQOlGUzrmBZ8ceBNpopt0BbN4YgWEE9vKFQxfigiQRz2DXbGg/smiwtCyfTo3zMV+SXvpATUgu+U6dcaYF7igTCGj/MWDLWcJXJZPoZfxyxVp6rEp0NGw==
```

This vector uses the exact `g0` Byte Sequence above, followed by `g1`. In the following blocks, `<G0>` and `<G1>` MUST be substituted with their exact displayed base64 bytes before processing.

```http
GET /resource?x=1 HTTP/1.1
Host: api.example
ERC-8128-Delegation: g0=:<G0>:, g1=:<G1>:
Signature-Input: request=("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="RERERERERERERERERERERA";keyid="eip155:1:0x1eff47bc3a10a45d4b230b5d10e37751fe6aa718";tag="erc8128-delegated"
Signature: request=:jWSeh0et5RDGPFgLZ6zr0Gs0DL8rtiPVm7OJFG+tM5h3S1C7aW5FIJQIaRj81NKvSHazGfQAFYsoJfn8eCYpkxs=:
```

The exact 1185-byte signature base is:

```text
"@scheme": https
"@authority": api.example
"@method": GET
"@path": /resource
"@query": ?x=1
"erc-8128-delegation";sf: g0=:<G0>:, g1=:<G1>:
"@signature-params": ("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="RERERERERERERERERERERA";keyid="eip155:1:0x1eff47bc3a10a45d4b230b5d10e37751fe6aa718";tag="erc8128-delegated"
```

```text
H_request_g1 = 0x635a35b75aaeb8f1f3eccba13d8f3a1df42aa4ed2eb57a3dc234bae49b6491ec
S_request_g1 = 0x8d649e8747ade510c63c580b67acebd06b340cbf2bb623d59bb389146fad3398774b50bb696e452094086918fcd4d2af4876b319f400158b2825f9fc782629931b
```

The expected Principal is Root and Signer is Delegate B. Effective Audience is `https://api.example`, Effective Scopes at `https://api.example` contain `resource:read`, Effective Components contain `@authority` and `@method`, Effective Non-Replayable Requirement is true, and only Delegate B's nonce is consumed.

## P-256 leaf vector

This vector requires Section 3.5 support and an explicitly enabled delegated route. It uses the same clock, Root, and registry state as above. The public fixture private key is `0x0000000000000000000000000000000000000000000000000000000000000006` on P-256 (not secp256k1). Its public JWK is the RFC 7638 thumbprint input:

```json
{"crv":"P-256","kty":"EC","x":"sBoXKnakYCyS0yQsuJfd4wJMdA3rshW0xrCq6Twikak","y":"6FwQdDI32tVv7A4t-6cDeRwA93Acfha9_XxIU4_Hf-I"}
```

Its SHA-256 JWK Thumbprint URI is:

```text
urn:ietf:params:oauth:jwk-thumbprint:sha-256:uhdbksqePVMcTx2Fvr5RY78RjuSE2bd16nNAkdfZ36I
```

The grant `p0` is signed by Root:

```json
{"issuer":"eip155:1:0x2b5ad5c4795c026514f8317c7a215e218dccd6cf","delegate":"{\"crv\":\"P-256\",\"kty\":\"EC\",\"x\":\"sBoXKnakYCyS0yQsuJfd4wJMdA3rshW0xrCq6Twikak\",\"y\":\"6FwQdDI32tVv7A4t-6cDeRwA93Acfha9_XxIU4_Hf-I\"}","audienceScopes":[{"audience":"https://api.example","scopes":["resource:read"]}],"id":"0x3333333333333333333333333333333333333333333333333333333333333333","epoch":7,"validAfter":1699999000,"validUntil":1700003600,"maxRequestValiditySeconds":60,"remainingDelegations":2,"delegateProfile":"ecdsa-p256-sha256","requireNonReplayable":true,"requiredComponents":["@authority"],"parentGrantHash":"0x0000000000000000000000000000000000000000000000000000000000000000"}
```

```text
structHash_p0 = 0x77a67137f39da316b2df8c33f423b4291870253af15200eeb09fd9e7c0125232
B_p0 = 0x1901bfa3ef2ffa516b4a513d3dc11b82f54744ff269a42a518551a62fd138e3c34d477a67137f39da316b2df8c33f423b4291870253af15200eeb09fd9e7c0125232
digest_p0 = 0xc09d7f9eccfeeb77e98b5aaf8aa11e9e2ed06e1a9ab5c5e9f3e5779193baaee7
signature_p0 = 0xbda677fd8c04fbfa3e9a4066534423fa12b57d90299e1d89b4a48dfe024bb3b25c37b239db63f1cbe7d65e8d9660f01aecf888630961c4009461a3f34f4951721c
```

Its 365-byte CBOR link has this exact base64 encoding; `<P0>` below MUST be replaced with this value:

```text
jXgzZWlwMTU1OjE6MHgyYjVhZDVjNDc5NWMwMjY1MTRmODMxN2M3YTIxNWUyMThkY2NkNmNmeH57ImNydiI6IlAtMjU2Iiwia3R5IjoiRUMiLCJ4Ijoic0JvWEtuYWtZQ3lTMHlRc3VKZmQ0d0pNZEEzcnNoVzB4ckNxNlR3aWthayIsInkiOiI2RndRZERJMzJ0VnY3QTR0LTZjRGVSd0E5M0FjZmhhOV9YeElVNF9IZi1JIn2BgnNodHRwczovL2FwaS5leGFtcGxlgW1yZXNvdXJjZTpyZWFkWCAzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMwcaZVPtGBplU/8QGDwCcWVjZHNhLXAyNTYtc2hhMjU29YFqQGF1dGhvcml0eVhBvaZ3/YwE+/o+mkBmU0Qj+hK1fZApnh2JtKSN/gJLs7JcN7I522Pxy+fWXo2WYPAa7PiIYwlhxACUYaPzT0lRchw=
```

```http
GET /resource?x=1 HTTP/1.1
Host: api.example
ERC-8128-Delegation: g0=:<P0>:
Signature-Input: request=("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="VVVVVVVVVVVVVVVVVVVVVQ";keyid="urn:ietf:params:oauth:jwk-thumbprint:sha-256:uhdbksqePVMcTx2Fvr5RY78RjuSE2bd16nNAkdfZ36I";tag="erc8128-delegated"
Signature: request=:vFwYha1yhscOVgpuZ2Jsy70nIvWCMOi18ux9pwvMPnkFXsNVs/WvON8OJEsi8OnHOH0nRU7xRyIvRNF5jb2I3w==:
```

The exact 899-byte signature base, with LF separators and no trailing LF, is:

```text
"@scheme": https
"@authority": api.example
"@method": GET
"@path": /resource
"@query": ?x=1
"erc-8128-delegation";sf: g0=:<P0>:
"@signature-params": ("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="VVVVVVVVVVVVVVVVVVVVVQ";keyid="urn:ietf:params:oauth:jwk-thumbprint:sha-256:uhdbksqePVMcTx2Fvr5RY78RjuSE2bd16nNAkdfZ36I";tag="erc8128-delegated"
```

```text
SHA256_request_p0 = 0x5cb1ff63aaf83a59e89993d367dc5c0a8fa19cc55b3e7e91c6535242e2362eac
S_request_p0 = 0xbc5c1885ad7286c70e560a6e67626ccbbd2722f58230e8b5f2ec7da70bcc3e79055ec355b3f5af38df0e244b22f0e9c7387d27454ef147222f44d1798dbd88df
```

The expected Principal is Root; the Signer is identified by the displayed JWK Thumbprint URI. Only its nonce is consumed. Grant-proof verification and registry status checks remain required; the leaf requires no Account classification or callback.

| Mutation or state | Expected result |
| --- | --- |
| Present the vector to a verifier without P-256 support | `unsupported_delegate_profile` before cryptography |
| Supply non-canonical JWK serialization, duplicate or additional members, private key material, or a key inconsistent with its algorithm | `bad_delegation_field` |
| Use a malformed request `keyid` | `invalid_keyid` |
| Use a JWK as `g0.issuer` | `bad_delegation_field` |
| Use a symmetric algorithm or key | `bad_delegation_field` |
| Name an unsupported registered asymmetric algorithm or key type | `unsupported_delegate_profile` |
| Supply a non-String `alg` or name a different algorithm | `unsupported_algorithm`; no Ethereum fallback |
| Add `alg="ecdsa-p256-sha256"` to this request and re-sign it | Valid; the grant already supplies the same algorithm |
| Add `alg="ecdsa-p256-sha256"` to an Ethereum Account leaf candidate | `unsupported_algorithm`; no P-256 fallback |
| Replace request `keyid` with a different valid JWK Thumbprint URI | `delegate_mismatch` |
| Replace the grant's delegate key and update the request `keyid` accordingly, re-sign the grant, and retain the original request signature | `bad_signature` |
| Supply DER encoding, append a recovery byte, or sign an ERC-191 hash or a double SHA-256 hash instead of `M` under Section 3.5 | `bad_signature` |
| Replace the valid request signature's `s` with `n - s`, where `n` is the P-256 group order | Valid proof; the same nonce still authenticates at most once |
| Submit the vector concurrently twice | Exactly one request authenticates; the other yields `nonce_reused` |
| Revoke `p0.id` or advance Root's epoch | `authorization_revoked` or `authorization_epoch_mismatch` |

For Replayable coverage, reissue `p0` with `requireNonReplayable=false`, re-sign it, and sign a request without `nonce` on a route permitting Replayable requests. Invalidation by `(Signer, signature base)` MUST reject both valid `s` representatives. An invalidation request must be Request-Bound and Non-Replayable and pass the same grant checks.

## JWK redelegation vector

This chain uses the existing `p0` as `g0`: Root → Delegate C (P-256) → Delegate D (Ed25519) → Delegate E (P-256). Delegate C uses the P-256 private scalar from the preceding vector; Delegate D uses the 32-byte seed `0x0000000000000000000000000000000000000000000000000000000000000007`; Delegate E uses P-256 private scalar `0x0000000000000000000000000000000000000000000000000000000000000008`. All fixture keys are public. Clock, route, Root, and registry state match the previous vectors. Both child grants inherit Root as their Revocation Account and epoch 7.

`q1` is issued by Delegate C, using the profile and key authorized in `p0`:

```json
{"issuer":"urn:ietf:params:oauth:jwk-thumbprint:sha-256:uhdbksqePVMcTx2Fvr5RY78RjuSE2bd16nNAkdfZ36I","delegate":"{\"crv\":\"Ed25519\",\"kty\":\"OKP\",\"x\":\"PuKopyg8sv1yiUPaoSfvCeSDBxqLS8aZukUi8JsUz94\"}","audienceScopes":[{"audience":"https://api.example","scopes":["resource:read"]}],"id":"0x4444444444444444444444444444444444444444444444444444444444444444","epoch":7,"validAfter":1699999000,"validUntil":1700003600,"maxRequestValiditySeconds":60,"remainingDelegations":1,"delegateProfile":"ed25519","requireNonReplayable":true,"requiredComponents":["@authority"],"parentGrantHash":"0xc09d7f9eccfeeb77e98b5aaf8aa11e9e2ed06e1a9ab5c5e9f3e5779193baaee7"}
```

```text
structHash_q1 = 0x25ae5b1b46904e81bc8f8546d77237f428bb59db61d0eb01723f5792d7e03586
B_q1 = 0x1901bfa3ef2ffa516b4a513d3dc11b82f54744ff269a42a518551a62fd138e3c34d425ae5b1b46904e81bc8f8546d77237f428bb59db61d0eb01723f5792d7e03586
digest_q1 = 0x86914d13882258958311e14ce6b87dbdfde260f6dc5abf9cd23095b6adfeecda
signature_q1 = 0xdb6f273f6fd54e16f4ac0a7a0c316dc727c7403d6feaff6b2d67f44788b4081543aa41e76142a8bcbb733a30a6a7bb4fb7bf8d541ea9d540d6b2f48fcd3c6000
registryHandle_q1 = 0x744d35239d3d09fc0f9946a2750980c8a0a7a922ebb3a2d5cdfab683c139bb33
```

Its 287-byte CBOR link has the following exact base64 value, substituted for `<Q1>` below:

```text
jHhPeyJjcnYiOiJFZDI1NTE5Iiwia3R5IjoiT0tQIiwieCI6IlB1S29weWc4c3YxeWlVUGFvU2Z2Q2VTREJ4cUxTOGFadWtVaThKc1V6OTQifYGCc2h0dHBzOi8vYXBpLmV4YW1wbGWBbXJlc291cmNlOnJlYWRYIEREREREREREREREREREREREREREREREREREREREREREGmVT7RgaZVP/EBg8AWdlZDI1NTE59YFqQGF1dGhvcml0eVggwJ1/nsz+63fpi1qviqEeni7QbhqatcXp8+V3kZO6rudYQNtvJz9v1U4W9KwKegwxbccnx0A9b+r/ay1n9EeItAgVQ6pB52FCqLy7czowpqe7T7e/jVQeqdVA1rL0j808YAA=
```

`q2` is issued by Delegate D, using the profile and key authorized in `q1`:

```json
{"issuer":"urn:ietf:params:oauth:jwk-thumbprint:sha-256:ts1eTI_oZYXecqXBULbizrUm9_vtL32WjRh2-lHeOZ8","delegate":"{\"crv\":\"P-256\",\"kty\":\"EC\",\"x\":\"Ytl3nb7psFNAQnQtOrVMrcHSOJgPzpfbtN2dwdtvs5M\",\"y\":\"rVrMvZHp2CRP8V13EWfO4KLtUfa752p42lQKag8JlX4\"}","audienceScopes":[{"audience":"https://api.example","scopes":["resource:read"]}],"id":"0x5555555555555555555555555555555555555555555555555555555555555555","epoch":7,"validAfter":1699999000,"validUntil":1700003600,"maxRequestValiditySeconds":60,"remainingDelegations":0,"delegateProfile":"ecdsa-p256-sha256","requireNonReplayable":true,"requiredComponents":["@authority"],"parentGrantHash":"0x86914d13882258958311e14ce6b87dbdfde260f6dc5abf9cd23095b6adfeecda"}
```

```text
structHash_q2 = 0xa5ea651f9fbd8c56216567bf925c12e9bbdc7c641d741bb26d487d06a86cc11f
B_q2 = 0x1901bfa3ef2ffa516b4a513d3dc11b82f54744ff269a42a518551a62fd138e3c34d4a5ea651f9fbd8c56216567bf925c12e9bbdc7c641d741bb26d487d06a86cc11f
digest_q2 = 0xf9c4c0cacc5ef8dd6219bbb9ab0c58aa4a5a6555e38ae205a7e478c4a34df1a9
signature_q2 = 0xc62e50ee64f7145fc2a394fffaf530391584dff9a2ba6389d52daeea9c92c1ec3bd41ab91c0ddbd4fe92a31d8c40a0dfd8179d40eba503b3cae634798dc41e01
registryHandle_q2 = 0x7dea78e742289b1efc793f1e899bae544a89c10f66933b3b322289a880c2e4c5
```

Its 344-byte CBOR link has the following exact base64 value, substituted for `<Q2>` below:

```text
jHh+eyJjcnYiOiJQLTI1NiIsImt0eSI6IkVDIiwieCI6Ill0bDNuYjdwc0ZOQVFuUXRPclZNcmNIU09KZ1B6cGZidE4yZHdkdHZzNU0iLCJ5IjoiclZyTXZaSHAyQ1JQOFYxM0VXZk80S0x0VWZhNzUycDQybFFLYWc4SmxYNCJ9gYJzaHR0cHM6Ly9hcGkuZXhhbXBsZYFtcmVzb3VyY2U6cmVhZFggVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUaZVPtGBplU/8QGDwAcWVjZHNhLXAyNTYtc2hhMjU29YFqQGF1dGhvcml0eVgghpFNE4giWJWDEeFM5rh9vf3iYPbcWr+c0jCVtq3+7NpYQMYuUO5k9xRfwqOU//r1MDkVhN/5orpjidUtruqcksHsO9QauRwN29T+kqMdjECg39gXnUDrpQOzyuY0eY3EHgE=
```

`<P0>` retains the exact encoding from the P-256 leaf vector. Delegate E signs the HTTP request covering the complete chain:

```http
GET /resource?x=1 HTTP/1.1
Host: api.example
ERC-8128-Delegation: g0=:<P0>:, g1=:<Q1>:, g2=:<Q2>:
Signature-Input: request=("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="ZmZmZmZmZmZmZmZmZmZmZg";keyid="urn:ietf:params:oauth:jwk-thumbprint:sha-256:dua6RYkNcqxX7xRiMQ5XZyMedBizg7y9jkqbcMKgldM";tag="erc8128-delegated"
Signature: request=:4JdBVuBIMSS5ZLSCNVr+f1+kKF8q4SNqtgFez6EKkt9NQrlkVKtxuhPBbtkUiHQatb9/HAwRyEgUvTFc7jHbIA==:
```

The exact 1757-byte signature base uses LF separators and no trailing LF:

```text
"@scheme": https
"@authority": api.example
"@method": GET
"@path": /resource
"@query": ?x=1
"erc-8128-delegation";sf: g0=:<P0>:, g1=:<Q1>:, g2=:<Q2>:
"@signature-params": ("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="ZmZmZmZmZmZmZmZmZmZmZg";keyid="urn:ietf:params:oauth:jwk-thumbprint:sha-256:dua6RYkNcqxX7xRiMQ5XZyMedBizg7y9jkqbcMKgldM";tag="erc8128-delegated"
```

```text
SHA256_request_q2 = 0x38c7135dd581d55bb9ecde979eb04cd96ced739509b0e0293af82e65c71c009a
S_request_q2 = 0xe0974156e0483124b964b482355afe7f5fa4285f2ae1236ab6015ecfa10a92df4d42b96454ab71ba13c16ed91488741ab5bf7f1c0c11c84814bd315cee31db20
```

The expected Principal is Root, and the Signer is identified by Delegate E's JWK Thumbprint URI. Only Delegate E's nonce is consumed. The registry checks Root's status at `p0.id`, `registryHandle_q1`, and `registryHandle_q2`; each reports `(false, 7)`. No JWK issuer requires Account classification.

| Mutation or state | Expected result |
| --- | --- |
| Replace Root with a JWK issuer | `bad_delegation_field` |
| Sign a child with its own recipient key rather than its parent's delegate key | `bad_grant_signature` |
| Use a JWK delegate's private key to sign `D` or its hex text instead of the 66-byte `B` | `bad_grant_signature` |
| Alter the parent profile or key without renewing its proof | Rejected; child metadata cannot replace parent authorization |
| Insert a child under another parent and re-sign the HTTP request | `delegation_chain_discontinuous` |
| Change that child's parent digest to match the new parent without renewing the child proof; use the same issuer key and compatible authority, and re-sign the request | `bad_grant_signature` |
| Sign the root proof with a different domain chain ID or `verifyingContract`, or omit `verifyingContract` | `bad_grant_signature` |
| Broaden a child's scopes or window, or fail to decrease remaining delegations | `delegation_attenuation_violation` |
| Revoke `registryHandle_q1` under Root | `authorization_revoked` for this chain and descendants of `q1`; a sibling with a distinct handle is unaffected |
| Revoke `p0.id` or advance Root's epoch | All descendants reject with `authorization_revoked` or `authorization_epoch_mismatch` |
| Substitute a grant's proof with another valid encoding over the same input and re-sign the HTTP request | Parent digests and registry handles remain unchanged |

## Authority metadata vectors

The following authority challenge metadata is valid; `future` is ignored:

```http
WWW-Authenticate: ERC8128 error="insufficient_scope", scope="orders:create resource:read", audience="https://merchant.example", max_validity="3600", max_depth="2", future="ignored"
Accept-Signature: delegated=("@scheme" "@authority" "@method" "@path" "@query" "content-digest" "content-type" "erc-8128-delegation";sf);keyid;created;expires;tag="erc8128-delegated";nonce
```

| Challenge mutation | Expected client result |
| --- | --- |
| Set `scope` to an empty value, include more than 32 values, repeat a value, make a value longer than 256 bytes, use invalid separators, or include a value that is not an RFC 9651 Token | Ignore all ERC-8395 authority metadata in the challenge |
| Set `audience` to `http://merchant.example`, `https://merchant.example/`, a wildcard, or another non-canonical origin | Ignore all ERC-8395 authority metadata in the challenge |
| Set `max_validity` or `max_depth` to `0`, `01`, `-1`, `+1`, `1.0`, `9007199254740992`, or an unquoted token value | Ignore all ERC-8395 authority metadata in the challenge |
| Repeat any recognized ERC-8395 auth-param | Ignore all ERC-8395 authority metadata in the challenge |
| Add an unrecognized auth-param with a valid quoted-string value | Ignore only that parameter and retain the valid ERC-8395 authority metadata |
| Include a delegated `Accept-Signature` member with `alg="ecdsa-p256-sha256"` or `alg="ed25519"` | Advertise the named registered algorithm; an existing grant authorizing another profile cannot be reused |
| Retain `max_depth` but remove every `Accept-Signature` member that covers the delegation field | Do not infer runtime Delegated Request Signature support |

For discovery, a recognized member with a wrong type, an out-of-range integer, a non-Token scope, or a non-canonical Audience is ignored independently; an invalid `max_depth` does not advertise delegation support.

## Negative and classification vectors

Each mutation starts from the applicable positive vector, leaves all signatures unchanged unless stated, and uses fresh replay state.

For the three-link rows, implementers extend the depth-two chain with a valid attenuated `g2` from Delegate B to private key `0x0000000000000000000000000000000000000000000000000000000000000005`, Account `eip155:1:0xe1ab8145f7e55dc933d51a18c793f901a3a0b276`. They set `g2.remainingDelegations=0`, sign `g2` with Delegate B and construct the corresponding leaf request signature with private key `0x...05`.

| Mutation or state | Expected result |
| --- | --- |
| Present the single-link candidate to a verifier that recognizes but does not implement this extension | `unsupported_delegation` |
| Remove `g0`, use `g01`, skip an index, add another member, corrupt CBOR or UTF-8, append trailing bytes, use a non-shortest CBOR head, or use an indefinite-length item | `bad_delegation_field` before cryptography |
| Send a valid candidate to a route with no explicit delegated-access policy | `unsupported_delegation` before cryptography |
| Remove `resource:read` from the child's `https://api.example` entry, leaving it empty, and re-sign the child and request on the `resource:read` route | authenticated `insufficient_scope`; omitted scopes are not inherited |
| Set a parent `remainingDelegations=0` with a child, or give a child a value at least its parent's, and re-sign affected material | `delegation_attenuation_violation` |
| Use a link with an incorrect element count | `bad_delegation_field` before cryptography |
| Give a grant no `audienceScopes` entries, repeat an entry's `audience`, or put a value that is not an RFC 9651 Token in an entry, and re-sign the grant | `bad_delegation_field` before cryptography |
| Give an entry a non-canonical `audience`, such as `https://api.example:443`, `https://api.example/`, an IDNA U-label, a trailing-dot host, userinfo, a query, a fragment, or a wildcard, and re-sign the grant | `bad_delegation_field` before cryptography |
| Send the single-link field as `g0=:AAAA:, g0=:<G0>:` | Accepted as the single-link vector: RFC 9651 keeps the last `g0`, and the strictly serialized delegation-field component contains only it |
| Send the single-link field as `g0=:<G0>:, g0=:AAAA:` | `bad_delegation_field`; the surviving last `g0` is not a Delegation Link |
| Sign the single-link request for `https://backup.example/resource?x=1` instead | Accepted; Effective Scopes at `https://backup.example` contain `resource:read` |
| Sign the single-link request for `https://backup.example/resource?x=1` on a route that requires `resource:write` | authenticated `insufficient_scope`; `g0` grants `resource:write` only at `https://api.example` |
| Exceed an extension field, link, entry, token, or text-string limit | `delegation_too_large` with 400 before cryptography |
| Remove or alter `;sf` on delegation coverage | `delegation_not_covered` |
| Change request `keyid` to differ from the Leaf Delegate's Delegate ID | `delegate_mismatch` |
| Configure maximum depth one and use the depth-two vector | `delegation_chain_too_long` with 400 |
| Include a child `issuer`, a JWK-issued child `epoch`, or a root `parentGrantHash` in a CBOR link | `bad_delegation_field` |
| Sign a grant with an issuer, inherited epoch, or root parent digest different from its reconstructed value, then re-sign the request over that proof | `bad_grant_signature` |
| Give `g1` an entry for a new Audience, `resource:admin` at `https://api.example`, an entry for `https://backup.example` holding `resource:write`, a wider window, or `maxRequestValiditySeconds=61` | `delegation_attenuation_violation` |
| With `now=1699999469`, use the depth-two vector | `grant_not_yet_valid` |
| With `now=1700001831`, use the depth-two vector | `grant_expired` |
| Configure a 3599-second maximum window for any individual grant and use `g0`, whose window is 4600 seconds | `grant_validity_too_long` |
| With no per-grant maximum configured, configure a 2299-second route Effective Grant Window maximum and use the depth-two vector, whose Effective Grant Window is 2300 seconds | `grant_validity_too_long` |
| With `now=1700001771`, re-sign the request with `created=1700001741` and `expires=1700001801`, using the depth-two chain | `request_outside_grant_window` |
| Set request `expires-created` to 61 | `delegation_request_validity_exceeded` |
| Put an unsupported derived identifier in `requiredComponents` and re-sign the grant | `delegation_components_unsupported` |
| Add supported `content-type` to `requiredComponents`, re-sign, and omit it from request coverage | `delegation_components_uncovered` |
| Remove the nonce from either positive request without changing its grant | `delegation_nonce_required` |
| Change Effective Audience to exclude `https://api.example` | `audience_mismatch` |
| Use a verifier without scope processing for either positive vector | `unsupported_scopes` |
| Use a verifier without scope processing on a route that requires none, with `g0` re-signed to hold no tokens at `https://api.example` and the request re-signed | Accepted; tokens granted only at `https://backup.example` need no processing for this request |
| Require `resource:write` on the depth-two route | authenticated `insufficient_scope` with 403 |
| Flip one grant-signature bit and re-sign the request over the mutated field | `bad_grant_signature` after leaf proof |
| Make grant-issuer account classification unavailable | `grant_verification_unavailable` with 503 |
| Return `isRevoked=true` for `g1` | `authorization_revoked` |
| Return epoch 8 for Root or 4 for Delegate A | `authorization_epoch_mismatch` |
| Make registry state unavailable with no live positive entry | `revocation_unavailable` with 503 |
| Revoke the middle link in the three-link derived chain | `authorization_revoked` |
| Advance the middle link issuer's epoch in the three-link derived chain | `authorization_epoch_mismatch` |
| Put a well-formed failing Delegated candidate before either positive candidate | the later candidate wins; the failed nonce remains unused |
