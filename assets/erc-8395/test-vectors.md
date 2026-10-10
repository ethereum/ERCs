# ERC-8395 test vectors

Section references refer to [ERC-8395](../../ERCS/erc-8395.md).

The fixed private keys are public and MUST NOT hold assets:

| Role | Private key | Account ID |
| --- | --- | --- |
| Root | `0x0000000000000000000000000000000000000000000000000000000000000002` | `eip155:1:0x2b5ad5c4795c026514f8317c7a215e218dccd6cf` |
| Delegate A | `0x0000000000000000000000000000000000000000000000000000000000000003` | `eip155:1:0x6813eb9362372eef6200f3b1dbc3f819671cba69` |
| Delegate B | `0x0000000000000000000000000000000000000000000000000000000000000004` | `eip155:1:0x1eff47bc3a10a45d4b230b5d10e37751fe6aa718` |

The clock is `1700000001`, skew is 30 seconds, the effective origin is `https://api.example`, all three accounts have no code, replay state is empty, permission processing is supported, the route explicitly permits Delegated Request Signatures and requires `resource:read`, and Principal policy accepts Root. Neither a route request-validity maximum nor a grant-validity maximum is configured. The registry reports `(false, 7)` for Root and `(false, 3)` for Delegate A.

## EIP-712 grant vectors

JSON grant values below show the full EIP-712 signing data, including fields reconstructed from the chain rather than transmitted in CBOR.

`g0` is Root to Delegate A:

```json
{"issuer":"eip155:1:0x2b5ad5c4795c026514f8317c7a215e218dccd6cf","delegate":"eip155:1:0x6813eb9362372eef6200f3b1dbc3f819671cba69","audiencePermissions":[{"audience":"https://api.example","permissions":["resource:read","resource:write"]},{"audience":"https://backup.example","permissions":["resource:read"]}],"id":"0x1111111111111111111111111111111111111111111111111111111111111111","epoch":7,"validAfter":1699999000,"validUntil":1700003600,"maxRequestValiditySeconds":60,"remainingDelegations":2,"delegateProfile":"erc8128-eoa","requireNonReplayable":true,"requiredComponents":["@authority"],"parentGrantHash":"0x0000000000000000000000000000000000000000000000000000000000000000"}
```

```text
domainSeparator = 0x750e55fd02747bf6c01af7a1c954aef9438655a5365f7f0561a007e4e169edfd
structHash_g0 = 0xf0d6cbe894222e9e0eca4a7a3ad0ba3dbe6bdf6ee96adb4d9f2bbbf7c69512fd
B_g0 = 0x1901750e55fd02747bf6c01af7a1c954aef9438655a5365f7f0561a007e4e169edfdf0d6cbe894222e9e0eca4a7a3ad0ba3dbe6bdf6ee96adb4d9f2bbbf7c69512fd
digest_g0 = 0xe48128590cbd129cc281f51ffb3f032d698323e9935ed04239bb48dd2e56d5d3
signature_g0 = 0x2f4cca8fd874c4f31933c767552fcb06ea1bb2fb5b169aa81eeea92491c6e287626130a5f664ef1a4eef408ae63f150190a4c4f38f013cdf29f6a5a4e22d2c2f1c
```

`g1` is Delegate A to Delegate B:

```json
{"issuer":"eip155:1:0x6813eb9362372eef6200f3b1dbc3f819671cba69","delegate":"eip155:1:0x1eff47bc3a10a45d4b230b5d10e37751fe6aa718","audiencePermissions":[{"audience":"https://api.example","permissions":["resource:read"]}],"id":"0x2222222222222222222222222222222222222222222222222222222222222222","epoch":3,"validAfter":1699999500,"validUntil":1700001800,"maxRequestValiditySeconds":60,"remainingDelegations":1,"delegateProfile":"erc8128-eoa","requireNonReplayable":true,"requiredComponents":["@method"],"parentGrantHash":"0xe48128590cbd129cc281f51ffb3f032d698323e9935ed04239bb48dd2e56d5d3"}
```

```text
structHash_g1 = 0xa3da51ef511786da52aa78185337a8f05033d0b505e666f15d547dc8b033f755
B_g1 = 0x1901750e55fd02747bf6c01af7a1c954aef9438655a5365f7f0561a007e4e169edfda3da51ef511786da52aa78185337a8f05033d0b505e666f15d547dc8b033f755
digest_g1 = 0xc13ac1770d0addaea13f97cf70638bf28946552059e3a4da6cb3870021aacac1
signature_g1 = 0x3b189101bd0be7ad478a7e72b0d3df661c8491f70d851f2394f4597229bb40087d3db1bf42766c7d11e65a3e958bb9cc33737b73d9378c355fd61663194ed8ff1c
```

Each mutation of `g0` below yields the listed `structHash`, with arrays hashed in their signed order:

| Mutation of `g0` | `structHash` |
| --- | --- |
| Give the `https://backup.example` entry no tokens; an empty array hashes as `keccak256("")` | `0x408df08af0f23c454f4e97922778ddbf69a66aea1942de83c77747192280b195` |
| Append a third entry, `https://third.example` with no tokens | `0x664fc8f999bbfcc92afaf96d87544357e5998cf8008898705902c6a60d6c9c79` |
| Place that third entry first, before the two entries of `g0` | `0xb5ff47125c34766915b13fbc64a53bee13f793804113aeb0914c5e73914c95a9` |
| Swap the two tokens of the `https://api.example` entry | `0x8783f3521663d493eaf15c33f442f95863b604a2c33db083237b73608953937d` |
| Give `requiredComponents` no entries | `0x62153881ad68a203c302db25a16f54df664f2b970b10ac374fcc53f482a5ceb5` |
| Hashing only, as such a grant is invalid: one entry whose `audience` and only token are empty strings, and one empty-string required component | `0xcf468d988194435eb9661b71a8fe50346ef80958d2e21d84a77785be8d7974a9` |

## Single-link request vector

The `g0` Byte Sequence is 338 bytes. Its exact uninterrupted base64 value is:

```text
jXgzZWlwMTU1OjE6MHgyYjVhZDVjNDc5NWMwMjY1MTRmODMxN2M3YTIxNWUyMThkY2NkNmNmeDNlaXAxNTU6MToweDY4MTNlYjkzNjIzNzJlZWY2MjAwZjNiMWRiYzNmODE5NjcxY2JhNjmCgnNodHRwczovL2FwaS5leGFtcGxlgm1yZXNvdXJjZTpyZWFkbnJlc291cmNlOndyaXRlgnZodHRwczovL2JhY2t1cC5leGFtcGxlgW1yZXNvdXJjZTpyZWFkWCAREREREREREREREREREREREREREREREREREREREREREQcaZVPtGBplU/8QGDwCa2VyYzgxMjgtZW9h9YFqQGF1dGhvcml0eVhBL0zKj9h0xPMZM8dnVS/LBuobsvtbFpqoHu6pJJHG4odiYTCl9mTvGk7vQIrmPxUBkKTE848BPN8p9qWk4i0sLxw=
```

For readability, `<G0>` in the following HTTP and signature-base blocks means the exact base64 bytes above. It MUST be substituted before parsing, transmission, hashing, or signing; the angle brackets are not part of the vector.

The complete request is:

```http
GET /resource?x=1 HTTP/1.1
Host: api.example
ERC-8128-Delegation: g0=:<G0>:
Signature-Input: request=("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="ASNFZ4mrze8QMlR2mLrc_g";keyid="eip155:1:0x6813eb9362372eef6200f3b1dbc3f819671cba69";tag="erc8128-delegated"
Signature: request=:aZuojOLxuAVTBh3NtrPn67s0IHF7OZiCmxsTc2IbQ39UKGT99JIFH3zyKUwKGGdzqKR3Ar1HBb96kbZ9ZeMZzhs=:
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
H_request_g0 = 0x5aa7a8f3f01bbde94cda95b45e6c5ed1c291bff4ce461df636f645ecb8444c25
S_request_g0 = 0x699ba88ce2f1b80553061dcdb6b3e7ebbb3420717b3998829b1b1373621b437f542864fdf492051f7cf2294c0a186773a8a47702bd4705bf7a91b67d65e319ce1b
```

The expected Principal is Root and Signer is Delegate A. The request is Request-Bound and Non-Replayable, and only Delegate A's nonce is consumed.

## Depth-two request vector

The `g1` Byte Sequence is 262 bytes. Its exact uninterrupted base64 value is:

```text
jXgzZWlwMTU1OjE6MHgxZWZmNDdiYzNhMTBhNDVkNGIyMzBiNWQxMGUzNzc1MWZlNmFhNzE4gYJzaHR0cHM6Ly9hcGkuZXhhbXBsZYFtcmVzb3VyY2U6cmVhZFggIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIDGmVT7wwaZVP4CBg8AWtlcmM4MTI4LWVvYfWBZ0BtZXRob2RYIOSBKFkMvRKcwoH1H/s/Ay1pgyPpk17QQjm7SN0uVtXTWEE7GJEBvQvnrUeKfnKw099mHISR9w2FHyOU9FlyKbtACH09sb9Cdmx9EeZaPpWLucwzc3tz2TeMNV/WFmMZTtj/HA==
```

This vector uses the exact `g0` Byte Sequence above, followed by `g1`. In the following blocks, `<G0>` and `<G1>` MUST be substituted with their exact displayed base64 bytes before processing.

```http
GET /resource?x=1 HTTP/1.1
Host: api.example
ERC-8128-Delegation: g0=:<G0>:, g1=:<G1>:
Signature-Input: request=("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="RERERERERERERERERERERA";keyid="eip155:1:0x1eff47bc3a10a45d4b230b5d10e37751fe6aa718";tag="erc8128-delegated"
Signature: request=:l5t+b+MAJHPjacakenliySvdPxR+9+/pIayBOsZ50GAkfu5Yp5LbTYE/2Yt0JwVISuLxxjQ4xJvIThUUQNgzgRw=:
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
H_request_g1 = 0xf1e8782ed46ea435727e00036310ad53ba04cf2b0da88c05e8671b92f4501dae
S_request_g1 = 0x979b7e6fe3002473e369c6a47a7962c92bdd3f147ef7efe921ac813ac679d060247eee58a792db4d813fd98b742705484ae2f1c63438c49bc84e151440d833811c
```

The expected Principal is Root and Signer is Delegate B. Effective Audience is `https://api.example`, Effective Permissions at `https://api.example` contain `resource:read`, Effective Components contain `@authority` and `@method`, Effective Non-Replayable Requirement is true, and only Delegate B's nonce is consumed.

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
{"issuer":"eip155:1:0x2b5ad5c4795c026514f8317c7a215e218dccd6cf","delegate":"{\"crv\":\"P-256\",\"kty\":\"EC\",\"x\":\"sBoXKnakYCyS0yQsuJfd4wJMdA3rshW0xrCq6Twikak\",\"y\":\"6FwQdDI32tVv7A4t-6cDeRwA93Acfha9_XxIU4_Hf-I\"}","audiencePermissions":[{"audience":"https://api.example","permissions":["resource:read"]}],"id":"0x3333333333333333333333333333333333333333333333333333333333333333","epoch":7,"validAfter":1699999000,"validUntil":1700003600,"maxRequestValiditySeconds":60,"remainingDelegations":2,"delegateProfile":"ecdsa-p256-sha256","requireNonReplayable":true,"requiredComponents":["@authority"],"parentGrantHash":"0x0000000000000000000000000000000000000000000000000000000000000000"}
```

```text
structHash_p0 = 0xa40a5357ffc2780ad7f1d20e91949f20bfe2e39f0fc4729c92be84ff89212f35
B_p0 = 0x1901750e55fd02747bf6c01af7a1c954aef9438655a5365f7f0561a007e4e169edfda40a5357ffc2780ad7f1d20e91949f20bfe2e39f0fc4729c92be84ff89212f35
digest_p0 = 0x3af591a698a22aef5cb2386b9fc0ab8c7c26268a69bda5ad0b2458d24b8d8237
signature_p0 = 0x74e85bf20b8c74d26f9514b9e0dfdf64cb41d279e062eac8e2dcb972886d97dc55bc6cba3406026299eb7a487b34d92798e4cca7c91aedf8e277adcffbdbf1821b
```

Its 365-byte CBOR link has this exact base64 encoding; `<P0>` below MUST be replaced with this value:

```text
jXgzZWlwMTU1OjE6MHgyYjVhZDVjNDc5NWMwMjY1MTRmODMxN2M3YTIxNWUyMThkY2NkNmNmeH57ImNydiI6IlAtMjU2Iiwia3R5IjoiRUMiLCJ4Ijoic0JvWEtuYWtZQ3lTMHlRc3VKZmQ0d0pNZEEzcnNoVzB4ckNxNlR3aWthayIsInkiOiI2RndRZERJMzJ0VnY3QTR0LTZjRGVSd0E5M0FjZmhhOV9YeElVNF9IZi1JIn2BgnNodHRwczovL2FwaS5leGFtcGxlgW1yZXNvdXJjZTpyZWFkWCAzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMwcaZVPtGBplU/8QGDwCcWVjZHNhLXAyNTYtc2hhMjU29YFqQGF1dGhvcml0eVhBdOhb8guMdNJvlRS54N/fZMtB0nngYurI4ty5cohtl9xVvGy6NAYCYpnrekh7NNknmOTMp8ka7fjid63P+9vxghs=
```

```http
GET /resource?x=1 HTTP/1.1
Host: api.example
ERC-8128-Delegation: g0=:<P0>:
Signature-Input: request=("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="VVVVVVVVVVVVVVVVVVVVVQ";keyid="urn:ietf:params:oauth:jwk-thumbprint:sha-256:uhdbksqePVMcTx2Fvr5RY78RjuSE2bd16nNAkdfZ36I";tag="erc8128-delegated"
Signature: request=:DNcx8gJANHG3j5bgj66W5jQ/J/NYpqqmctkRpGPU6siOMPCF0lMysuJl+B5/cMimxzqbfDhmz/NT/fS4ptrDJg==:
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
SHA256_request_p0 = 0x8cdc80635cd29a10a2afd93cf5ac048e9042ad6bd8d3b8a011126c24c66388d4
S_request_p0 = 0x0cd731f202403471b78f96e08fae96e6343f27f358a6aaa672d911a463d4eac88e30f085d25332b2e265f81e7f70c8a6c73a9b7c3866cff353fdf4b8a6dac326
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
{"issuer":"urn:ietf:params:oauth:jwk-thumbprint:sha-256:uhdbksqePVMcTx2Fvr5RY78RjuSE2bd16nNAkdfZ36I","delegate":"{\"crv\":\"Ed25519\",\"kty\":\"OKP\",\"x\":\"PuKopyg8sv1yiUPaoSfvCeSDBxqLS8aZukUi8JsUz94\"}","audiencePermissions":[{"audience":"https://api.example","permissions":["resource:read"]}],"id":"0x4444444444444444444444444444444444444444444444444444444444444444","epoch":7,"validAfter":1699999000,"validUntil":1700003600,"maxRequestValiditySeconds":60,"remainingDelegations":1,"delegateProfile":"ed25519","requireNonReplayable":true,"requiredComponents":["@authority"],"parentGrantHash":"0x3af591a698a22aef5cb2386b9fc0ab8c7c26268a69bda5ad0b2458d24b8d8237"}
```

```text
structHash_q1 = 0xf757f1b7d98b73495a5db92d646d30711a3017e5ef469b898eab523ce8123fc1
B_q1 = 0x1901750e55fd02747bf6c01af7a1c954aef9438655a5365f7f0561a007e4e169edfdf757f1b7d98b73495a5db92d646d30711a3017e5ef469b898eab523ce8123fc1
digest_q1 = 0x24fde4ec5076c40f52edda0b1539e667324f32028059228338dcfd7ec6de7056
signature_q1 = 0x44dcd5262f2cf9b40a5f9379983b6ff006d46723e34d4440a654aaed08fe4ba83343ea4db94e6bb66bb5681ec0553815a3437e756f19e58ce0dbc95cff6698d0
registryHandle_q1 = 0xaa396f63df553558d9e2401ae6b9a6bed1a0e455e6bf74a50c1e3f4105f51f9a
```

Its 287-byte CBOR link has the following exact base64 value, substituted for `<Q1>` below:

```text
jHhPeyJjcnYiOiJFZDI1NTE5Iiwia3R5IjoiT0tQIiwieCI6IlB1S29weWc4c3YxeWlVUGFvU2Z2Q2VTREJ4cUxTOGFadWtVaThKc1V6OTQifYGCc2h0dHBzOi8vYXBpLmV4YW1wbGWBbXJlc291cmNlOnJlYWRYIEREREREREREREREREREREREREREREREREREREREREREGmVT7RgaZVP/EBg8AWdlZDI1NTE59YFqQGF1dGhvcml0eVggOvWRppiiKu9csjhrn8CrjHwmJoppvaWtCyRY0kuNgjdYQETc1SYvLPm0Cl+TeZg7b/AG1Gcj401EQKZUqu0I/kuoM0PqTblOa7ZrtWgewFU4FaNDfnVvGeWM4NvJXP9mmNA=
```

`q2` is issued by Delegate D, using the profile and key authorized in `q1`:

```json
{"issuer":"urn:ietf:params:oauth:jwk-thumbprint:sha-256:ts1eTI_oZYXecqXBULbizrUm9_vtL32WjRh2-lHeOZ8","delegate":"{\"crv\":\"P-256\",\"kty\":\"EC\",\"x\":\"Ytl3nb7psFNAQnQtOrVMrcHSOJgPzpfbtN2dwdtvs5M\",\"y\":\"rVrMvZHp2CRP8V13EWfO4KLtUfa752p42lQKag8JlX4\"}","audiencePermissions":[{"audience":"https://api.example","permissions":["resource:read"]}],"id":"0x5555555555555555555555555555555555555555555555555555555555555555","epoch":7,"validAfter":1699999000,"validUntil":1700003600,"maxRequestValiditySeconds":60,"remainingDelegations":0,"delegateProfile":"ecdsa-p256-sha256","requireNonReplayable":true,"requiredComponents":["@authority"],"parentGrantHash":"0x24fde4ec5076c40f52edda0b1539e667324f32028059228338dcfd7ec6de7056"}
```

```text
structHash_q2 = 0x1231d82c4afc17a6d5c7b650115a3eabb2399bffa8c9d7c6ae5dc8fa4df4a72e
B_q2 = 0x1901750e55fd02747bf6c01af7a1c954aef9438655a5365f7f0561a007e4e169edfd1231d82c4afc17a6d5c7b650115a3eabb2399bffa8c9d7c6ae5dc8fa4df4a72e
digest_q2 = 0x0d600692f4b28c8d4b6de67014b902cb536696c2de710a6b53bfd2e749613807
signature_q2 = 0xf6b53b07a05089cd853b94f25d40e6ca5dec464402c5d4531d94017aa89a3a802f538a869a9623fd9f21f5d0726ef1737a786537462659e9ddcb41491fe04905
registryHandle_q2 = 0x1ee3d0ba7f8a47675a09470177672ff8678e59aadb0d2c5d69538aae269a5f9a
```

Its 344-byte CBOR link has the following exact base64 value, substituted for `<Q2>` below:

```text
jHh+eyJjcnYiOiJQLTI1NiIsImt0eSI6IkVDIiwieCI6Ill0bDNuYjdwc0ZOQVFuUXRPclZNcmNIU09KZ1B6cGZidE4yZHdkdHZzNU0iLCJ5IjoiclZyTXZaSHAyQ1JQOFYxM0VXZk80S0x0VWZhNzUycDQybFFLYWc4SmxYNCJ9gYJzaHR0cHM6Ly9hcGkuZXhhbXBsZYFtcmVzb3VyY2U6cmVhZFggVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUaZVPtGBplU/8QGDwAcWVjZHNhLXAyNTYtc2hhMjU29YFqQGF1dGhvcml0eVggJP3k7FB2xA9S7doLFTnmZzJPMgKAWSKDONz9fsbecFZYQPa1OwegUInNhTuU8l1A5spd7EZEAsXUUx2UAXqomjqAL1OKhpqWI/2fIfXQcm7xc3p4ZTdGJlnp3ctBSR/gSQU=
```

`<P0>` retains the exact encoding from the P-256 leaf vector. Delegate E signs the HTTP request covering the complete chain:

```http
GET /resource?x=1 HTTP/1.1
Host: api.example
ERC-8128-Delegation: g0=:<P0>:, g1=:<Q1>:, g2=:<Q2>:
Signature-Input: request=("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="ZmZmZmZmZmZmZmZmZmZmZg";keyid="urn:ietf:params:oauth:jwk-thumbprint:sha-256:dua6RYkNcqxX7xRiMQ5XZyMedBizg7y9jkqbcMKgldM";tag="erc8128-delegated"
Signature: request=:EG6/mgwykh7XpAQ3/+GxdJ6JKxn1y4NDmV2z7+ppgN0JujAwalJCZ4IWjkQAH90zP0DAfy5wMddEg0SaeRysVw==:
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
SHA256_request_q2 = 0x3a91fe427193f0b67c5855b7c107a9b1d8144374c1518df9f5c913978032b66b
S_request_q2 = 0x106ebf9a0c32921ed7a40437ffe1b1749e892b19f5cb8343995db3efea6980dd09ba30306a52426782168e44001fdd333f40c07f2e7031d74483449a791cac57
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
| Broaden a child's permissions or window, or fail to decrease remaining delegations | `delegation_attenuation_violation` |
| Revoke `registryHandle_q1` under Root | `authorization_revoked` for this chain and descendants of `q1`; a sibling with a distinct handle is unaffected |
| Revoke `p0.id` or advance Root's epoch | All descendants reject with `authorization_revoked` or `authorization_epoch_mismatch` |
| Substitute a grant's proof with another valid encoding over the same input and re-sign the HTTP request | Parent digests and registry handles remain unchanged |

## Authority metadata vectors

The following authority challenge metadata is valid; `future` is ignored:

```http
WWW-Authenticate: ERC8128 error="insufficient_permissions", permissions="orders:create resource:read", audience="https://merchant.example", max_validity="3600", max_depth="2", future="ignored"
Accept-Signature: delegated=("@scheme" "@authority" "@method" "@path" "@query" "content-digest" "content-type" "erc-8128-delegation";sf);keyid;created;expires;tag="erc8128-delegated";nonce
```

| Challenge mutation | Expected client result |
| --- | --- |
| Set `permissions` to an empty value, include more than 32 values, repeat a value, make a value longer than 256 bytes, use invalid separators, or include a value that is not an RFC 9651 Token | Ignore all ERC-8395 authority metadata in the challenge |
| Set `audience` to `http://merchant.example`, `https://merchant.example/`, a wildcard, or another non-canonical origin | Ignore all ERC-8395 authority metadata in the challenge |
| Set `max_validity` or `max_depth` to `0`, `01`, `-1`, `+1`, `1.0`, `9007199254740992`, or an unquoted token value | Ignore all ERC-8395 authority metadata in the challenge |
| Repeat any recognized ERC-8395 auth-param | Ignore all ERC-8395 authority metadata in the challenge |
| Add an unrecognized auth-param with a valid quoted-string value | Ignore only that parameter and retain the valid ERC-8395 authority metadata |
| Include a delegated `Accept-Signature` member with `alg="ecdsa-p256-sha256"` or `alg="ed25519"` | Advertise the named registered algorithm; an existing grant authorizing another profile cannot be reused |
| Retain `max_depth` but remove every `Accept-Signature` member that covers the delegation field | Do not infer runtime Delegated Request Signature support |

For discovery, a recognized member with a wrong type, an out-of-range integer, a non-Token permission, or a non-canonical Audience is ignored independently; an invalid `max_depth` does not advertise delegation support.

## Negative and classification vectors

Each mutation starts from the applicable positive vector, leaves all signatures unchanged unless stated, and uses fresh replay state.

For the three-link rows, implementers extend the depth-two chain with a valid attenuated `g2` from Delegate B to private key `0x0000000000000000000000000000000000000000000000000000000000000005`, Account `eip155:1:0xe1ab8145f7e55dc933d51a18c793f901a3a0b276`. They set `g2.remainingDelegations=0`, sign `g2` with Delegate B and construct the corresponding leaf request signature with private key `0x...05`.

| Mutation or state | Expected result |
| --- | --- |
| Present the single-link candidate to a verifier that recognizes but does not implement this extension | `unsupported_delegation` |
| Remove `g0`, use `g01`, skip an index, add another member, corrupt CBOR or UTF-8, append trailing bytes, use a non-shortest CBOR head, or use an indefinite-length item | `bad_delegation_field` before cryptography |
| Send a valid candidate to a route with no explicit delegated-access policy | `unsupported_delegation` before cryptography |
| Remove `resource:read` from the child's `https://api.example` entry, leaving it empty, and re-sign the child and request on the `resource:read` route | authenticated `insufficient_permissions`; omitted permissions are not inherited |
| Set a parent `remainingDelegations=0` with a child, or give a child a value at least its parent's, and re-sign affected material | `delegation_attenuation_violation` |
| Use a link with an incorrect element count | `bad_delegation_field` before cryptography |
| Give a grant no `audiencePermissions` entries, repeat an entry's `audience`, or put a value that is not an RFC 9651 Token in an entry, and re-sign the grant | `bad_delegation_field` before cryptography |
| Give an entry a non-canonical `audience`, such as `https://api.example:443`, `https://api.example/`, an IDNA U-label, a trailing-dot host, userinfo, a query, a fragment, or a wildcard, and re-sign the grant | `bad_delegation_field` before cryptography |
| Send the single-link field as `g0=:AAAA:, g0=:<G0>:` | Accepted as the single-link vector: RFC 9651 keeps the last `g0`, and the strictly serialized delegation-field component contains only it |
| Send the single-link field as `g0=:<G0>:, g0=:AAAA:` | `bad_delegation_field`; the surviving last `g0` is not a Delegation Link |
| Sign the single-link request for `https://backup.example/resource?x=1` instead | Accepted; Effective Permissions at `https://backup.example` contain `resource:read` |
| Sign the single-link request for `https://backup.example/resource?x=1` on a route that requires `resource:write` | authenticated `insufficient_permissions`; `g0` grants `resource:write` only at `https://api.example` |
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
| Use a verifier without permission processing for either positive vector | `unsupported_permissions` |
| Use a verifier without permission processing on a route that requires none, with `g0` re-signed to hold no tokens at `https://api.example` and the request re-signed | Accepted; tokens granted only at `https://backup.example` need no processing for this request |
| Require `resource:write` on the depth-two route | authenticated `insufficient_permissions` with 403 |
| Flip one grant-signature bit and re-sign the request over the mutated field | `bad_grant_signature` after leaf proof |
| Make grant-issuer account classification unavailable | `grant_verification_unavailable` with 503 |
| Return `isRevoked=true` for `g1` | `authorization_revoked` |
| Return epoch 8 for Root or 4 for Delegate A | `authorization_epoch_mismatch` |
| Make registry state unavailable with no live positive entry | `revocation_unavailable` with 503 |
| Revoke the middle link in the three-link derived chain | `authorization_revoked` |
| Advance the middle link issuer's epoch in the three-link derived chain | `authorization_epoch_mismatch` |
| Put a well-formed failing Delegated candidate before either positive candidate | the later candidate wins; the failed nonce remains unused |
