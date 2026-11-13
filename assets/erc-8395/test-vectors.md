# ERC-8395 test vectors

Section references refer to [ERC-8395](../../ERCS/erc-8395.md).

The fixed private keys are public and MUST NOT hold assets:

| Role | Private key | Account ID |
| --- | --- | --- |
| Root | `0x0000000000000000000000000000000000000000000000000000000000000002` | `eip155:1:0x2b5ad5c4795c026514f8317c7a215e218dccd6cf` |
| Delegate A | `0x0000000000000000000000000000000000000000000000000000000000000003` | `eip155:1:0x6813eb9362372eef6200f3b1dbc3f819671cba69` |
| Delegate B | `0x0000000000000000000000000000000000000000000000000000000000000004` | `eip155:1:0x1eff47bc3a10a45d4b230b5d10e37751fe6aa718` |

The clock is `1700000001`, skew is 30 seconds, the effective origin is `https://api.example`, all three accounts have no code, replay state is empty, scope processing is supported, the route explicitly permits Delegated Request Signatures, accepts Non-Replayable and Replayable signatures, and requires `resource:read`, and Principal policy accepts Root. Neither a route request-validity maximum nor a grant-validity maximum is configured. The registry reports `(false, 7)` for Root and `(false, 3)` for Delegate A.

## EIP-712 grant vectors

JSON grant values below show the full EIP-712 signing data, including fields reconstructed from the chain rather than transmitted in CBOR.

`g0` is Root to Delegate A:

```json
{"issuer":"eip155:1:0x2b5ad5c4795c026514f8317c7a215e218dccd6cf","delegate":"eip155:1:0x6813eb9362372eef6200f3b1dbc3f819671cba69","audienceScopes":[{"audience":"https://api.example","scopes":["resource:read","resource:write"]},{"audience":"https://backup.example","scopes":["resource:read"]}],"id":"0x1111111111111111111111111111111111111111111111111111111111111111","epoch":7,"validAfter":1699999000,"validUntil":1700003600,"maxRequestValiditySeconds":60,"remainingDelegations":2,"delegateProfile":"erc8128-eoa","requiredComponents":["@authority"],"parentGrantHash":"0x0000000000000000000000000000000000000000000000000000000000000000"}
```

```text
domainSeparator = 0x6a839aa3fa901cbfb3e93f09818ee980c296246834a5f691ebbcce551c8dcfc2
structHash_g0 = 0xd60bfb138406e0673d769f70717e5f12f73d5997ec7306c3979096278d671719
B_g0 = 0x19016a839aa3fa901cbfb3e93f09818ee980c296246834a5f691ebbcce551c8dcfc2d60bfb138406e0673d769f70717e5f12f73d5997ec7306c3979096278d671719
digest_g0 = 0xbfc6a0fa843eaddb4413f6bddf428811e0436fa9bfd7a34d44d85b2407a63768
signature_g0 = 0x25f443a2f25f0549075249b3efcccdd3b9dd6231037aea2ba3841293f0826b87414535efa0ffac3fcbd7e28e20f4004a3348e057c2ef11e93c4f7865392cf3bf1c
```

`g1` is Delegate A to Delegate B:

```json
{"issuer":"eip155:1:0x6813eb9362372eef6200f3b1dbc3f819671cba69","delegate":"eip155:1:0x1eff47bc3a10a45d4b230b5d10e37751fe6aa718","audienceScopes":[{"audience":"https://api.example","scopes":["resource:read"]}],"id":"0x2222222222222222222222222222222222222222222222222222222222222222","epoch":3,"validAfter":1699999500,"validUntil":1700001800,"maxRequestValiditySeconds":60,"remainingDelegations":1,"delegateProfile":"erc8128-eoa","requiredComponents":["@method"],"parentGrantHash":"0xbfc6a0fa843eaddb4413f6bddf428811e0436fa9bfd7a34d44d85b2407a63768"}
```

```text
structHash_g1 = 0x9bdd392309fb6a3f34d027445e80aa533fbdff2f61aac6f4b05ed10df4a27906
B_g1 = 0x19016a839aa3fa901cbfb3e93f09818ee980c296246834a5f691ebbcce551c8dcfc29bdd392309fb6a3f34d027445e80aa533fbdff2f61aac6f4b05ed10df4a27906
digest_g1 = 0x3a8971812a160d989b61c7b74189968908950f6d17782da8822b565e0803284e
signature_g1 = 0xc061411db9dc14d7794bd1a23776792a67afd0c9482dbb615ede94fdab8f8cfa04b87d34b0db41ec3e3a6682bb9e236d8fd363678676ea4df3a8b5a9e2cd95b91c
```

Each mutation of `g0` below yields the listed `structHash`, with arrays hashed in their signed order:

| Mutation of `g0` | `structHash` |
| --- | --- |
| Give the `https://backup.example` entry no tokens; an empty array hashes as `keccak256("")` | `0xe5fd3c3678ae87995e1df719b5d8b17cdb0f6596704ee314558705be4f57f455` |
| Append a third entry, `https://third.example` with no tokens | `0x018de96d287fb69bceb36af5e036cc26f2197c2b0fb08729d1b60ec83decdbfa` |
| Place that third entry first, before the two entries of `g0` | `0xd162b8a7771411c2812611962927b6470a4a26af0c74f0e64d76daf79a25e040` |
| Swap the two tokens of the `https://api.example` entry | `0xc79f17170275bafc31451dc93291afc0af37e4d3d2e61eb7bd35206e2c318c4e` |
| Give `requiredComponents` no entries | `0x0b25fa16ad2d962b3e5f818ca0363dc37efa40697336c51dfbab7346a2454c37` |
| Hashing only, as such a grant is invalid: one entry whose `audience` and only token are empty strings, and one empty-string required component | `0x29468a4e4bfbf28cf19a524ccf2da4b7d915ab20d591ae346c8cea01d392c53d` |

## Single-link request vector

The `g0` Byte Sequence is 337 bytes. Its exact uninterrupted base64 value is:

```text
jHgzZWlwMTU1OjE6MHgyYjVhZDVjNDc5NWMwMjY1MTRmODMxN2M3YTIxNWUyMThkY2NkNmNmeDNlaXAxNTU6MToweDY4MTNlYjkzNjIzNzJlZWY2MjAwZjNiMWRiYzNmODE5NjcxY2JhNjmCgnNodHRwczovL2FwaS5leGFtcGxlgm1yZXNvdXJjZTpyZWFkbnJlc291cmNlOndyaXRlgnZodHRwczovL2JhY2t1cC5leGFtcGxlgW1yZXNvdXJjZTpyZWFkWCAREREREREREREREREREREREREREREREREREREREREREQcaZVPtGBplU/8QGDwCa2VyYzgxMjgtZW9hgWpAYXV0aG9yaXR5WEEl9EOi8l8FSQdSSbPvzM3Tud1iMQN66iujhBKT8IJrh0FFNe+g/6w/y9fijiD0AEozSOBXwu8R6TxPeGU5LPO/HA==
```

For readability, `<G0>` in the following HTTP and signature-base blocks means the exact base64 bytes above. It MUST be substituted before parsing, transmission, hashing, or signing; the angle brackets are not part of the vector.

The complete request is:

```http
GET /resource?x=1 HTTP/1.1
Host: api.example
ERC-8128-Delegation: g0=:<G0>:
Signature-Input: request=("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="ASNFZ4mrze8QMlR2mLrc_g";keyid="eip155:1:0x6813eb9362372eef6200f3b1dbc3f819671cba69";tag="erc8128-delegated"
Signature: request=:dnfYS7McroZ/R8H5D6FZJ3GnH1R9FyhEavnXyVDPCQEJDNwf8D3cjFgoeuUDtZLyunJVB78RYU1igXuUX7yfBhs=:
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
H_request_g0 = 0x319d6a3f605508196cea84d28925378b5313a51a32e1a6c54bed5f8d68260058
S_request_g0 = 0x7677d84bb31cae867f47c1f90fa1592771a71f547d1728446af9d7c950cf0901090cdc1ff03ddc8c58287ae503b592f2ba725507bf11614d62817b945fbc9f061b
```

The expected Principal is Root and Signer is Delegate A. The request is Request-Bound and Non-Replayable, and only Delegate A's nonce is consumed.

## Depth-two request vector

The `g1` Byte Sequence is 261 bytes. Its exact uninterrupted base64 value is:

```text
jHgzZWlwMTU1OjE6MHgxZWZmNDdiYzNhMTBhNDVkNGIyMzBiNWQxMGUzNzc1MWZlNmFhNzE4gYJzaHR0cHM6Ly9hcGkuZXhhbXBsZYFtcmVzb3VyY2U6cmVhZFggIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIDGmVT7wwaZVP4CBg8AWtlcmM4MTI4LWVvYYFnQG1ldGhvZFggv8ag+oQ+rdtEE/a930KIEeBDb6m/16NNRNhbJAemN2hYQcBhQR253BTXeUvRojd2eSpnr9DJSC27YV7elP2rj4z6BLh9NLDbQew+OmaCu54jbY/TY2eGdupN86i1qeLNlbkc
```

This vector uses the exact `g0` Byte Sequence above, followed by `g1`. In the following blocks, `<G0>` and `<G1>` MUST be substituted with their exact displayed base64 bytes before processing.

```http
GET /resource?x=1 HTTP/1.1
Host: api.example
ERC-8128-Delegation: g0=:<G0>:, g1=:<G1>:
Signature-Input: request=("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="RERERERERERERERERERERA";keyid="eip155:1:0x1eff47bc3a10a45d4b230b5d10e37751fe6aa718";tag="erc8128-delegated"
Signature: request=:KmMIJS4Xx0fhrXtzo9pwvfeg60uijvWkqRC1y7T2Umcot2NF/FTDbb0b8uA39ABxP9JBfLyNqCKr82MyQ6ppNBs=:
```

The exact 1181-byte signature base is:

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
H_request_g1 = 0x34c6177bc6268b8129bcbd18d39f2a35ea04c310556ea8c1f971c5f999338faf
S_request_g1 = 0x2a6308252e17c747e1ad7b73a3da70bdf7a0eb4ba28ef5a4a910b5cbb4f6526728b76345fc54c36dbd1bf2e037f400713fd2417cbc8da822abf3633243aa69341b
```

The expected Principal is Root and Signer is Delegate B. Effective Audience is `https://api.example`, Effective Scopes at `https://api.example` contain `resource:read`, Effective Components contain `@authority` and `@method`, and only Delegate B's nonce is consumed.

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
{"issuer":"eip155:1:0x2b5ad5c4795c026514f8317c7a215e218dccd6cf","delegate":"{\"crv\":\"P-256\",\"kty\":\"EC\",\"x\":\"sBoXKnakYCyS0yQsuJfd4wJMdA3rshW0xrCq6Twikak\",\"y\":\"6FwQdDI32tVv7A4t-6cDeRwA93Acfha9_XxIU4_Hf-I\"}","audienceScopes":[{"audience":"https://api.example","scopes":["resource:read"]}],"id":"0x3333333333333333333333333333333333333333333333333333333333333333","epoch":7,"validAfter":1699999000,"validUntil":1700003600,"maxRequestValiditySeconds":60,"remainingDelegations":2,"delegateProfile":"ecdsa-p256-sha256","requiredComponents":["@authority"],"parentGrantHash":"0x0000000000000000000000000000000000000000000000000000000000000000"}
```

```text
structHash_p0 = 0xb0ccd0687c8d924044182cfc99fd150500e143578f236ca69fe2c773a8e5add6
B_p0 = 0x19016a839aa3fa901cbfb3e93f09818ee980c296246834a5f691ebbcce551c8dcfc2b0ccd0687c8d924044182cfc99fd150500e143578f236ca69fe2c773a8e5add6
digest_p0 = 0xfd3e5af8cb32feee064272b1b69423b5f82dea019996e588f6902edb7fdd6051
signature_p0 = 0xb3b8a850aa12693204519cf0f5392a8723743e525d8d194c03c677e7fc7a5b345f51631df1c61704a6e7aa6a0f49bc47237bc1fde3bb597f8d30f49390c68f9d1c
```

Its 364-byte CBOR link has this exact base64 encoding; `<P0>` below MUST be replaced with this value:

```text
jHgzZWlwMTU1OjE6MHgyYjVhZDVjNDc5NWMwMjY1MTRmODMxN2M3YTIxNWUyMThkY2NkNmNmeH57ImNydiI6IlAtMjU2Iiwia3R5IjoiRUMiLCJ4Ijoic0JvWEtuYWtZQ3lTMHlRc3VKZmQ0d0pNZEEzcnNoVzB4ckNxNlR3aWthayIsInkiOiI2RndRZERJMzJ0VnY3QTR0LTZjRGVSd0E5M0FjZmhhOV9YeElVNF9IZi1JIn2BgnNodHRwczovL2FwaS5leGFtcGxlgW1yZXNvdXJjZTpyZWFkWCAzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMwcaZVPtGBplU/8QGDwCcWVjZHNhLXAyNTYtc2hhMjU2gWpAYXV0aG9yaXR5WEGzuKhQqhJpMgRRnPD1OSqHI3Q+Ul2NGUwDxnfn/HpbNF9RYx3xxhcEpueqag9JvEcje8H947tZf40w9JOQxo+dHA==
```

```http
GET /resource?x=1 HTTP/1.1
Host: api.example
ERC-8128-Delegation: g0=:<P0>:
Signature-Input: request=("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="VVVVVVVVVVVVVVVVVVVVVQ";keyid="urn:ietf:params:oauth:jwk-thumbprint:sha-256:uhdbksqePVMcTx2Fvr5RY78RjuSE2bd16nNAkdfZ36I";tag="erc8128-delegated"
Signature: request=:dZCDEqKsqxmq9DXqO+bmZJnLGRhLpGrEjkPGg0HBVaXlon7ZxIyM27UOp57A8NRpuJNbjPhzaI4z27tCR2pqNA==:
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
SHA256_request_p0 = 0x9e56a1f3250fdbda9cab6a4e985c71410d6fcd417f96d191036e2758a9f6e9e5
S_request_p0 = 0x75908312a2acab19aaf435ea3be6e66499cb19184ba46ac48e43c68341c155a5e5a27ed9c48c8cdbb50ea79ec0f0d469b8935b8cf873688e33dbbb42476a6a34
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

For Replayable coverage, re-sign the request without `nonce`: it authenticates as Replayable, and no nonce is consumed.

For early-invalidation coverage under Section 4.3, reissue `p0` with `maxRequestValiditySeconds=300` and re-sign it, then sign the request without `nonce` and with `expires=1700000300`. The verifier accepts Replayable signatures valid for up to 300 seconds and implements both ERC-8128 mechanisms. Each invalidation request below is sent to the verifier's invalidation endpoint at `https://api.example` and, unless stated, carries a Request-Bound Delegated Request Signature by the same key under the reissued `p0`. Each row starts from empty invalidation state.

| Request or state | Expected result |
| --- | --- |
| Present the 300-second Replayable request to a verifier that implements no early invalidation | `request_validity_too_long` |
| Send `{"message_hash": H}`, where `H` is the ERC-8128 hash of the Replayable request's signature base | HTTP 200; the Replayable request then yields `signature_invalidated`, also with its `s` replaced by `n - s` |
| Send `{"not_before": 1700000001}` | HTTP 200; the Replayable request then yields `signature_invalidated` |
| Send `{"not_before": 1700000001}` with a signature that omits `content-digest` | `insufficient_coverage`; the Replayable request still authenticates |
| Send `{"not_before": 1700000001}` after `p0.id` is revoked | `authorization_revoked`; invalidation state is unchanged |
| Send `{"not_before": 1700000001}` in a direct ERC-8128 request signed by Root | HTTP 200; the Replayable request still authenticates, as its `keyid` is the Delegate's |

## JWK redelegation vector

This chain uses the existing `p0` as `g0`: Root → Delegate C (P-256) → Delegate D (Ed25519) → Delegate E (P-256). Delegate C uses the P-256 private scalar from the preceding vector; Delegate D uses the 32-byte seed `0x0000000000000000000000000000000000000000000000000000000000000007`; Delegate E uses P-256 private scalar `0x0000000000000000000000000000000000000000000000000000000000000008`. All fixture keys are public. Clock, route, Root, and registry state match the previous vectors. Both child grants inherit Root as their Revocation Account and epoch 7.

`q1` is issued by Delegate C, using the profile and key authorized in `p0`:

```json
{"issuer":"urn:ietf:params:oauth:jwk-thumbprint:sha-256:uhdbksqePVMcTx2Fvr5RY78RjuSE2bd16nNAkdfZ36I","delegate":"{\"crv\":\"Ed25519\",\"kty\":\"OKP\",\"x\":\"PuKopyg8sv1yiUPaoSfvCeSDBxqLS8aZukUi8JsUz94\"}","audienceScopes":[{"audience":"https://api.example","scopes":["resource:read"]}],"id":"0x4444444444444444444444444444444444444444444444444444444444444444","epoch":7,"validAfter":1699999000,"validUntil":1700003600,"maxRequestValiditySeconds":60,"remainingDelegations":1,"delegateProfile":"ed25519","requiredComponents":["@authority"],"parentGrantHash":"0xfd3e5af8cb32feee064272b1b69423b5f82dea019996e588f6902edb7fdd6051"}
```

```text
structHash_q1 = 0x6f30674322477cebf96075d47d8584363342aa958540c728d852b70a9d2bf6fe
B_q1 = 0x19016a839aa3fa901cbfb3e93f09818ee980c296246834a5f691ebbcce551c8dcfc26f30674322477cebf96075d47d8584363342aa958540c728d852b70a9d2bf6fe
digest_q1 = 0xdaa0edebace700d536fe21173ec6e71292b0f12edb3d911c94fb89fa9704559b
signature_q1 = 0xbb43b83f3ff3d65935839f71ebd39de10508c1688074c55b8dd25c06a47ce547a939bd2c348d21ce77fa3bb0c68ed1e24b32f76f2da0d0302dcccfd26bceda17
registryHandle_q1 = 0x994d95f089beb56fe65cd5ddb3acc12c5d86a03e6b0167b0b7b3a1e4d34cb725
```

Its 286-byte CBOR link has the following exact base64 value, substituted for `<Q1>` below:

```text
i3hPeyJjcnYiOiJFZDI1NTE5Iiwia3R5IjoiT0tQIiwieCI6IlB1S29weWc4c3YxeWlVUGFvU2Z2Q2VTREJ4cUxTOGFadWtVaThKc1V6OTQifYGCc2h0dHBzOi8vYXBpLmV4YW1wbGWBbXJlc291cmNlOnJlYWRYIEREREREREREREREREREREREREREREREREREREREREREGmVT7RgaZVP/EBg8AWdlZDI1NTE5gWpAYXV0aG9yaXR5WCD9Plr4yzL+7gZCcrG2lCO1+C3qAZmW5Yj2kC7bf91gUVhAu0O4Pz/z1lk1g59x69Od4QUIwWiAdMVbjdJcBqR85UepOb0sNI0hznf6O7DGjtHiSzL3by2g0DAtzM/Sa87aFw==
```

`q2` is issued by Delegate D, using the profile and key authorized in `q1`:

```json
{"issuer":"urn:ietf:params:oauth:jwk-thumbprint:sha-256:ts1eTI_oZYXecqXBULbizrUm9_vtL32WjRh2-lHeOZ8","delegate":"{\"crv\":\"P-256\",\"kty\":\"EC\",\"x\":\"Ytl3nb7psFNAQnQtOrVMrcHSOJgPzpfbtN2dwdtvs5M\",\"y\":\"rVrMvZHp2CRP8V13EWfO4KLtUfa752p42lQKag8JlX4\"}","audienceScopes":[{"audience":"https://api.example","scopes":["resource:read"]}],"id":"0x5555555555555555555555555555555555555555555555555555555555555555","epoch":7,"validAfter":1699999000,"validUntil":1700003600,"maxRequestValiditySeconds":60,"remainingDelegations":0,"delegateProfile":"ecdsa-p256-sha256","requiredComponents":["@authority"],"parentGrantHash":"0xdaa0edebace700d536fe21173ec6e71292b0f12edb3d911c94fb89fa9704559b"}
```

```text
structHash_q2 = 0xd9bfba41ad32d574ddd60376e35929168450f99d8ff27b1cb442275958728e77
B_q2 = 0x19016a839aa3fa901cbfb3e93f09818ee980c296246834a5f691ebbcce551c8dcfc2d9bfba41ad32d574ddd60376e35929168450f99d8ff27b1cb442275958728e77
digest_q2 = 0x5bb773bc9491df32d2ae24b152e49dc400dba1c3df7a4b952e6f14aef3a59a13
signature_q2 = 0x5418cdb72c186480c8c658a024c13300bc482467d662458ecec59d3605beb2e99c0e95a88dbda48522b11289bad2fe77d1499c8f61125aa1f8e28ee682d15a01
registryHandle_q2 = 0x3fdcdee837664f28c3397a539ef33371d8a473f1c287e98bd29c5354b28ced1b
```

Its 343-byte CBOR link has the following exact base64 value, substituted for `<Q2>` below:

```text
i3h+eyJjcnYiOiJQLTI1NiIsImt0eSI6IkVDIiwieCI6Ill0bDNuYjdwc0ZOQVFuUXRPclZNcmNIU09KZ1B6cGZidE4yZHdkdHZzNU0iLCJ5IjoiclZyTXZaSHAyQ1JQOFYxM0VXZk80S0x0VWZhNzUycDQybFFLYWc4SmxYNCJ9gYJzaHR0cHM6Ly9hcGkuZXhhbXBsZYFtcmVzb3VyY2U6cmVhZFggVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUaZVPtGBplU/8QGDwAcWVjZHNhLXAyNTYtc2hhMjU2gWpAYXV0aG9yaXR5WCDaoO3rrOcA1Tb+IRc+xucSkrDxLts9kRyU+4n6lwRVm1hAVBjNtywYZIDIxligJMEzALxIJGfWYkWOzsWdNgW+sumcDpWojb2khSKxEom60v530Umcj2ESWqH44o7mgtFaAQ==
```

`<P0>` retains the exact encoding from the P-256 leaf vector. Delegate E signs the HTTP request covering the complete chain:

```http
GET /resource?x=1 HTTP/1.1
Host: api.example
ERC-8128-Delegation: g0=:<P0>:, g1=:<Q1>:, g2=:<Q2>:
Signature-Input: request=("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="ZmZmZmZmZmZmZmZmZmZmZg";keyid="urn:ietf:params:oauth:jwk-thumbprint:sha-256:dua6RYkNcqxX7xRiMQ5XZyMedBizg7y9jkqbcMKgldM";tag="erc8128-delegated"
Signature: request=:AZIMZKsTlXbBUDqkCsLWodS/aCdwTFaA+6EWb6Wi93K/o7WcWkDwLt8hC4boHbzqTmYtI1I6nLYCqc8GiaeQkA==:
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
SHA256_request_q2 = 0xcae0240046e97a5350c64b6ac0c70a71ad4016e9c79fc3d17e276a4a016ebade
S_request_q2 = 0x01920c64ab139576c1503aa40ac2d6a1d4bf6827704c5680fba1166fa5a2f772bfa3b59c5a40f02edf210b86e81dbcea4e662d23523a9cb602a9cf0689a79090
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
WWW-Authenticate: ERC8128 error="insufficient_scope", scope="orders:create resource:read", audience="https://merchant.example", max_grant_validity="3600", max_depth="2", future="ignored"
Accept-Signature: delegated=("@scheme" "@authority" "@method" "@path" "@query" "content-digest" "content-type" "erc-8128-delegation";sf);keyid;created;expires;tag="erc8128-delegated";nonce
```

| Challenge mutation | Expected client result |
| --- | --- |
| Set `scope` to an empty value, include more than 32 values, repeat a value, make a value longer than 256 bytes, use invalid separators, or include a value that is not an RFC 9651 Token | Ignore all ERC-8395 authority metadata in the challenge |
| Set `audience` to `http://merchant.example`, `https://merchant.example/`, a wildcard, or another non-canonical origin | Ignore all ERC-8395 authority metadata in the challenge |
| Set `max_grant_validity` or `max_depth` to `0`, `01`, `-1`, `+1`, `1.0`, `9007199254740992`, or an unquoted token value | Ignore all ERC-8395 authority metadata in the challenge |
| Repeat any recognized ERC-8395 auth-param | Ignore all ERC-8395 authority metadata in the challenge |
| Add an unrecognized auth-param with a valid quoted-string value | Ignore only that parameter and retain the valid ERC-8395 authority metadata |
| Add ERC-8128's `max_validity="60"` | It bounds the request's validity window under ERC-8128; the ERC-8395 authority metadata is unchanged |
| Include a delegated `Accept-Signature` member with `alg="ecdsa-p256-sha256"` or `alg="ed25519"` | Advertise the named registered algorithm; an existing grant authorizing another profile cannot be reused |
| Retain `max_depth` but remove every `Accept-Signature` member that covers the delegation field | Do not infer runtime Delegated Request Signature support |

For discovery, a recognized member with a wrong type, an out-of-range integer, a non-Token scope, or a non-canonical Audience is ignored independently; an invalid `max_depth` does not advertise delegation support. A top-level `scopes` member with a name that is not an RFC 9651 Token or a value that is not a non-empty string is ignored as a whole, as is a top-level `delegation` member that lacks `max_depth` or `registry_chains` or holds an invalid value for either.

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
| Re-sign either positive request without `nonce` | Accepted as Replayable; no nonce is consumed |
| Re-sign either positive request without `nonce` on a route that accepts only Non-Replayable signatures | `nonce_required` |
| Use either positive request on a route that accepts only Replayable signatures | `nonce_not_supported` |
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
