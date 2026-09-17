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
{"issuer":"eip155:1:0x2b5ad5c4795c026514f8317c7a215e218dccd6cf","delegate":"eip155:1:0x6813eb9362372eef6200f3b1dbc3f819671cba69","audiences":["https://api.example","https://backup.example"],"id":"0x1111111111111111111111111111111111111111111111111111111111111111","epoch":7,"validAfter":1699999000,"validUntil":1700003600,"maxRequestValiditySeconds":60,"remainingDelegations":2,"delegateProfile":"erc8128-eoa","requireNonReplayable":true,"requiredComponents":["@authority"],"permissions":["resource:read","resource:write"],"parentGrantHash":"0x0000000000000000000000000000000000000000000000000000000000000000"}
```

```text
domainSeparator = 0x41237ea78b607a6925c377e4ca50454d8bf74a3e7d19c5e9f3b6329e50ef5f42
structHash_g0 = 0x3fa5b9e054bdc99c0ad54d7e1209a6f7b0620a895b76c52a27d20af75d30412c
B_g0 = 0x190141237ea78b607a6925c377e4ca50454d8bf74a3e7d19c5e9f3b6329e50ef5f423fa5b9e054bdc99c0ad54d7e1209a6f7b0620a895b76c52a27d20af75d30412c
digest_g0 = 0xdde6bac3e712164244107986d00cfbd4cccdcbf497adda5728995705e0ac0289
signature_g0 = 0xe63ca77f09ac197008f4a3e180e18c6c31f3995c63a662c4612d0747fb942fdc086ac8ec034347e355e5431bc0ddfcd81c74aba85cedd3e39080f712be985b711c
```

`g1` is Delegate A to Delegate B:

```json
{"issuer":"eip155:1:0x6813eb9362372eef6200f3b1dbc3f819671cba69","delegate":"eip155:1:0x1eff47bc3a10a45d4b230b5d10e37751fe6aa718","audiences":["https://api.example"],"id":"0x2222222222222222222222222222222222222222222222222222222222222222","epoch":3,"validAfter":1699999500,"validUntil":1700001800,"maxRequestValiditySeconds":60,"remainingDelegations":1,"delegateProfile":"erc8128-eoa","requireNonReplayable":true,"requiredComponents":["@method"],"permissions":["resource:read"],"parentGrantHash":"0xdde6bac3e712164244107986d00cfbd4cccdcbf497adda5728995705e0ac0289"}
```

```text
structHash_g1 = 0xb8fcf6aaf6a4bbc69a9f30c0c9634389e0883b0e8a13dc88d23fdf99124dbd8b
B_g1 = 0x190141237ea78b607a6925c377e4ca50454d8bf74a3e7d19c5e9f3b6329e50ef5f42b8fcf6aaf6a4bbc69a9f30c0c9634389e0883b0e8a13dc88d23fdf99124dbd8b
digest_g1 = 0xee3c38ed47a91510db81e7d701b2935a477b5820cef0bb88d39df373a8e0845d
signature_g1 = 0xd1acb5c092bb82cefcfe2fe0aea1aa565745b75b21340d8879d9ba5709db70077439cf7b73781c215048662ede402556110de5e54ce3a7692deb1a21526186311c
```

## Single-link request vector

The `g0` Byte Sequence is 321 bytes. Its exact uninterrupted base64 value is:

```text
jngzZWlwMTU1OjE6MHgyYjVhZDVjNDc5NWMwMjY1MTRmODMxN2M3YTIxNWUyMThkY2NkNmNmeDNlaXAxNTU6MToweDY4MTNlYjkzNjIzNzJlZWY2MjAwZjNiMWRiYzNmODE5NjcxY2JhNjmCc2h0dHBzOi8vYXBpLmV4YW1wbGV2aHR0cHM6Ly9iYWNrdXAuZXhhbXBsZVggEREREREREREREREREREREREREREREREREREREREREREHGmVT7RgaZVP/EBg8AmtlcmM4MTI4LWVvYfWBakBhdXRob3JpdHmCbXJlc291cmNlOnJlYWRucmVzb3VyY2U6d3JpdGVYQeY8p38JrBlwCPSj4YDhjGwx85lcY6ZixGEtB0f7lC/cCGrI7ANDR+NV5UMbwN382Bx0q6hc7dPjkID3Er6YW3Ec
```

For readability, `<G0>` in the following HTTP and signature-base blocks means the exact base64 bytes above. It MUST be substituted before parsing, transmission, hashing, or signing; the angle brackets are not part of the vector.

The complete request is:

```http
GET /resource?x=1 HTTP/1.1
Host: api.example
ERC-8128-Delegation: g0=:<G0>:
Signature-Input: request=("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="ASNFZ4mrze8QMlR2mLrc_g";keyid="eip155:1:0x6813eb9362372eef6200f3b1dbc3f819671cba69";tag="erc8128-delegated"
Signature: request=:rM3rq/zDuE3/UWoT/DpyjvhQduc5UHDYo7q845K6mkdYul82Z1WNh/yVzEhFHeEIXBbsW2jAuDno5X2Mq++uqBs=:
```

The exact 802-byte signature base is:

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
H_request_g0 = 0xd8a54ca9f285a7ffa02a4bc3c6eb975eeec7fd11f90665ef78dea067d4452065
S_request_g0 = 0xaccdebabfcc3b84dff516a13fc3a728ef85076e7395070d8a3babce392ba9a4758ba5f3667558d87fc95cc48451de1085c16ec5b68c0b839e8e57d8cabefaea81b
```

The expected Principal is Root and Signer is Delegate A. The request is Request-Bound and Non-Replayable, and only Delegate A's nonce is consumed.

## Depth-two request vector

The `g1` Byte Sequence is 261 bytes. Its exact uninterrupted base64 value is:

```text
jngzZWlwMTU1OjE6MHgxZWZmNDdiYzNhMTBhNDVkNGIyMzBiNWQxMGUzNzc1MWZlNmFhNzE4gXNodHRwczovL2FwaS5leGFtcGxlWCAiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIgMaZVPvDBplU/gIGDwBa2VyYzgxMjgtZW9h9YFnQG1ldGhvZIFtcmVzb3VyY2U6cmVhZFgg3ea6w+cSFkJEEHmG0Az71MzNy/SXrdpXKJlXBeCsAolYQdGstcCSu4LO/P4v4K6hqlZXRbdbITQNiHnZulcJ23AHdDnPe3N4HCFQSGYu3kAlVhEN5eVM46dpLesaIVJhhjEc
```

This vector uses the exact `g0` Byte Sequence above, followed by `g1`. In the following blocks, `<G0>` and `<G1>` MUST be substituted with their exact displayed base64 bytes before processing.

```http
GET /resource?x=1 HTTP/1.1
Host: api.example
ERC-8128-Delegation: g0=:<G0>:, g1=:<G1>:
Signature-Input: request=("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="RERERERERERERERERERERA";keyid="eip155:1:0x1eff47bc3a10a45d4b230b5d10e37751fe6aa718";tag="erc8128-delegated"
Signature: request=:hlywRzinjDY5XVzV95OAgHkMZhqVu8lGou3GNBQg0s4vUm5GxOrIq/223PXn+QmUDdp/XNq+A7FI8keB8xlp4xs=:
```

The exact 1157-byte signature base is:

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
H_request_g1 = 0x2fa06dc893a353c24e2da4853443b96f10ab05cdff935db5c34e3b0528128bba
S_request_g1 = 0x865cb04738a78c36395d5cd5f7938080790c661a95bbc946a2edc6341420d2ce2f526e46c4eac8abfdb6dcf5e7f909940dda7f5cdabe03b148f24781f31969e31b
```

The expected Principal is Root and Signer is Delegate B. Effective Audience is `https://api.example`, Effective Permissions contain `resource:read`, Effective Components contain `@authority` and `@method`, Effective Non-Replayable Requirement is true, and only Delegate B's nonce is consumed.

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
{"issuer":"eip155:1:0x2b5ad5c4795c026514f8317c7a215e218dccd6cf","delegate":"{\"crv\":\"P-256\",\"kty\":\"EC\",\"x\":\"sBoXKnakYCyS0yQsuJfd4wJMdA3rshW0xrCq6Twikak\",\"y\":\"6FwQdDI32tVv7A4t-6cDeRwA93Acfha9_XxIU4_Hf-I\"}","audiences":["https://api.example"],"id":"0x3333333333333333333333333333333333333333333333333333333333333333","epoch":7,"validAfter":1699999000,"validUntil":1700003600,"maxRequestValiditySeconds":60,"remainingDelegations":2,"delegateProfile":"ecdsa-p256-sha256","requireNonReplayable":true,"requiredComponents":["@authority"],"permissions":["resource:read"],"parentGrantHash":"0x0000000000000000000000000000000000000000000000000000000000000000"}
```

```text
structHash_p0 = 0x98e416b4718d2f40560f57870c382d87627d79a6eeb795c43c08fb0f823d2c6c
B_p0 = 0x190141237ea78b607a6925c377e4ca50454d8bf74a3e7d19c5e9f3b6329e50ef5f4298e416b4718d2f40560f57870c382d87627d79a6eeb795c43c08fb0f823d2c6c
digest_p0 = 0x4981163c09ca44a4c79a2e52aea3255fc041fc7fa04ed11ff804ed8d5dd49d5d
signature_p0 = 0x5dbcc1ea56a61f09221f382ad503ba7f12d81d70b595365305a35c81e823d6d97055bdfd76ae77af63b700c77348b78d7dab51e77797297a6bd5e040491ab73c1c
```

Its 364-byte CBOR link has this exact base64 encoding; `<P0>` below MUST be replaced with this value:

```text
jngzZWlwMTU1OjE6MHgyYjVhZDVjNDc5NWMwMjY1MTRmODMxN2M3YTIxNWUyMThkY2NkNmNmeH57ImNydiI6IlAtMjU2Iiwia3R5IjoiRUMiLCJ4Ijoic0JvWEtuYWtZQ3lTMHlRc3VKZmQ0d0pNZEEzcnNoVzB4ckNxNlR3aWthayIsInkiOiI2RndRZERJMzJ0VnY3QTR0LTZjRGVSd0E5M0FjZmhhOV9YeElVNF9IZi1JIn2Bc2h0dHBzOi8vYXBpLmV4YW1wbGVYIDMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzMzBxplU+0YGmVT/xAYPAJxZWNkc2EtcDI1Ni1zaGEyNTb1gWpAYXV0aG9yaXR5gW1yZXNvdXJjZTpyZWFkWEFdvMHqVqYfCSIfOCrVA7p/EtgdcLWVNlMFo1yB6CPW2XBVvf12rnevY7cAx3NIt419q1Hnd5cpemvV4EBJGrc8HA==
```

```http
GET /resource?x=1 HTTP/1.1
Host: api.example
ERC-8128-Delegation: g0=:<P0>:
Signature-Input: request=("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="VVVVVVVVVVVVVVVVVVVVVQ";keyid="urn:ietf:params:oauth:jwk-thumbprint:sha-256:uhdbksqePVMcTx2Fvr5RY78RjuSE2bd16nNAkdfZ36I";tag="erc8128-delegated"
Signature: request=:Ya4AlMAF2lFrOHE7mEv6GGfNS5cMc6+u8xA5bb15HALu/iYSvMtZ0sfZ7Z6G7F2JvMHBDEIod7Fq31aaGHUysA==:
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
SHA256_request_p0 = 0xeb63ac9f0d839c0d55d9399a39a9ca18526cc7c55c6d330bff95868d3838bf44
S_request_p0 = 0x61ae0094c005da516b38713b984bfa1867cd4b970c73afaef310396dbd791c02eefe2612bccb59d2c7d9ed9e86ec5d89bcc1c10c422877b16adf569a187532b0
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
{"issuer":"urn:ietf:params:oauth:jwk-thumbprint:sha-256:uhdbksqePVMcTx2Fvr5RY78RjuSE2bd16nNAkdfZ36I","delegate":"{\"crv\":\"Ed25519\",\"kty\":\"OKP\",\"x\":\"PuKopyg8sv1yiUPaoSfvCeSDBxqLS8aZukUi8JsUz94\"}","audiences":["https://api.example"],"id":"0x4444444444444444444444444444444444444444444444444444444444444444","epoch":7,"validAfter":1699999000,"validUntil":1700003600,"maxRequestValiditySeconds":60,"remainingDelegations":1,"delegateProfile":"ed25519","requireNonReplayable":true,"requiredComponents":["@authority"],"permissions":["resource:read"],"parentGrantHash":"0x4981163c09ca44a4c79a2e52aea3255fc041fc7fa04ed11ff804ed8d5dd49d5d"}
```

```text
structHash_q1 = 0xa519b82c4e455b4d6ae67118f7caadcd463704b99ca289043556e4520b5ac5cc
B_q1 = 0x190141237ea78b607a6925c377e4ca50454d8bf74a3e7d19c5e9f3b6329e50ef5f42a519b82c4e455b4d6ae67118f7caadcd463704b99ca289043556e4520b5ac5cc
digest_q1 = 0xceee10b0478d81f3180fa258a47f1692bf8219988ecf5d9c7ce827115d119a03
signature_q1 = 0xbe1ee689a26e6ef26aeb99a0e99d39a4dbbb602841b1b7dccfc9d18231caf6c298556b3d18c8aef183d29c493d331e31cf8352a89389088973d01ab13f0efdc5
registryHandle_q1 = 0x679b640f99604b63dc32db4a6cf2ccb183ee9da37ee64d7168229e91945e0536
```

Its 286-byte CBOR link has the following exact base64 value, substituted for `<Q1>` below:

```text
jXhPeyJjcnYiOiJFZDI1NTE5Iiwia3R5IjoiT0tQIiwieCI6IlB1S29weWc4c3YxeWlVUGFvU2Z2Q2VTREJ4cUxTOGFadWtVaThKc1V6OTQifYFzaHR0cHM6Ly9hcGkuZXhhbXBsZVggREREREREREREREREREREREREREREREREREREREREREQaZVPtGBplU/8QGDwBZ2VkMjU1MTn1gWpAYXV0aG9yaXR5gW1yZXNvdXJjZTpyZWFkWCBJgRY8CcpEpMeaLlKuoyVfwEH8f6BO0R/4BO2NXdSdXVhAvh7miaJubvJq65mg6Z05pNu7YChBsbfcz8nRgjHK9sKYVWs9GMiu8YPSnEk9Mx4xz4NSqJOJCIlz0BqxPw79xQ==
```

`q2` is issued by Delegate D, using the profile and key authorized in `q1`:

```json
{"issuer":"urn:ietf:params:oauth:jwk-thumbprint:sha-256:ts1eTI_oZYXecqXBULbizrUm9_vtL32WjRh2-lHeOZ8","delegate":"{\"crv\":\"P-256\",\"kty\":\"EC\",\"x\":\"Ytl3nb7psFNAQnQtOrVMrcHSOJgPzpfbtN2dwdtvs5M\",\"y\":\"rVrMvZHp2CRP8V13EWfO4KLtUfa752p42lQKag8JlX4\"}","audiences":["https://api.example"],"id":"0x5555555555555555555555555555555555555555555555555555555555555555","epoch":7,"validAfter":1699999000,"validUntil":1700003600,"maxRequestValiditySeconds":60,"remainingDelegations":0,"delegateProfile":"ecdsa-p256-sha256","requireNonReplayable":true,"requiredComponents":["@authority"],"permissions":["resource:read"],"parentGrantHash":"0xceee10b0478d81f3180fa258a47f1692bf8219988ecf5d9c7ce827115d119a03"}
```

```text
structHash_q2 = 0xac36c8d98ad75d8fbf9dcaee0fb77506fcf295f49a7c5fa8ce47db60619a140f
B_q2 = 0x190141237ea78b607a6925c377e4ca50454d8bf74a3e7d19c5e9f3b6329e50ef5f42ac36c8d98ad75d8fbf9dcaee0fb77506fcf295f49a7c5fa8ce47db60619a140f
digest_q2 = 0xdf48d0ad7a684311d826f079caf8ed2a6c475f29e4c35bc9542f397aeb0ce4b0
signature_q2 = 0x6dffa55710cee05af55b053e2747296da770e27b05253b09c5957c3a0d58dd1d581a2d5230c1426ccbd3d86aa8f31f85d70fe184d6e9edc89069ca22e939f608
registryHandle_q2 = 0x6e718368d26c6e9ef5c710c42475a7bb2749abdf4b4906daf8ac7bdb7cf40ebf
```

Its 343-byte CBOR link has the following exact base64 value, substituted for `<Q2>` below:

```text
jXh+eyJjcnYiOiJQLTI1NiIsImt0eSI6IkVDIiwieCI6Ill0bDNuYjdwc0ZOQVFuUXRPclZNcmNIU09KZ1B6cGZidE4yZHdkdHZzNU0iLCJ5IjoiclZyTXZaSHAyQ1JQOFYxM0VXZk80S0x0VWZhNzUycDQybFFLYWc4SmxYNCJ9gXNodHRwczovL2FwaS5leGFtcGxlWCBVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVRplU+0YGmVT/xAYPABxZWNkc2EtcDI1Ni1zaGEyNTb1gWpAYXV0aG9yaXR5gW1yZXNvdXJjZTpyZWFkWCDO7hCwR42B8xgPolikfxaSv4IZmI7PXZx86CcRXRGaA1hAbf+lVxDO4Fr1WwU+J0cpbadw4nsFJTsJxZV8Og1Y3R1YGi1SMMFCbMvT2Gqo8x+F1w/hhNbp7ciQacoi6Tn2CA==
```

`<P0>` retains the exact encoding from the P-256 leaf vector. Delegate E signs the HTTP request covering the complete chain:

```http
GET /resource?x=1 HTTP/1.1
Host: api.example
ERC-8128-Delegation: g0=:<P0>:, g1=:<Q1>:, g2=:<Q2>:
Signature-Input: request=("@scheme" "@authority" "@method" "@path" "@query" "erc-8128-delegation";sf);created=1700000000;expires=1700000060;nonce="ZmZmZmZmZmZmZmZmZmZmZg";keyid="urn:ietf:params:oauth:jwk-thumbprint:sha-256:dua6RYkNcqxX7xRiMQ5XZyMedBizg7y9jkqbcMKgldM";tag="erc8128-delegated"
Signature: request=:o1xoL/eqOcAARK8XeXyrUzVnGHHkXA6bfzuczaCQDWD8sWewk3tDeA60Ke5cGEbp8wOuIKI8jqHY4WhpsYgxNQ==:
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
SHA256_request_q2 = 0x2fdde2e70bd93d97827fe243d107e4d11ca8479e816970024e1975c6051d6a3d
S_request_q2 = 0xa35c682ff7aa39c00044af17797cab5335671871e45c0e9b7f3b9ccda0900d60fcb167b0937b43780eb429ee5c1846e9f303ae20a23c8ea1d8e16869b1883135
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
| Set `permissions` to an empty value, include more than 32 values, make a value longer than 256 bytes, use invalid separators, or include a value that is not an RFC 9651 Token | Ignore all ERC-8395 authority metadata in the challenge |
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
| Set child `permissions=[]` and re-sign the child and request on the `resource:read` route | authenticated `insufficient_permissions`; empty permissions do not inherit |
| Set a parent `remainingDelegations=0` with a child, or give a child a value at least its parent's, and re-sign affected material | `delegation_attenuation_violation` |
| Use a link with an incorrect element count | `bad_delegation_field` before cryptography |
| Put a value that is not an RFC 9651 Token in `permissions` and re-sign the grant | `bad_delegation_field` before cryptography |
| Exceed an extension field, link, array, or text-string limit | `delegation_too_large` with 400 before cryptography |
| Remove or alter `;sf` on delegation coverage | `delegation_not_covered` |
| Change request `keyid` to differ from the Leaf Delegate's Delegate ID | `delegate_mismatch` |
| Configure maximum depth one and use the depth-two vector | `delegation_chain_too_long` with 400 |
| Include a child `issuer`, a JWK-issued child `epoch`, or a root `parentGrantHash` in a CBOR link | `bad_delegation_field` |
| Sign a grant with an issuer, inherited epoch, or root parent digest different from its reconstructed value, then re-sign the request over that proof | `bad_grant_signature` |
| Give `g1` a new Audience, `resource:admin`, a wider window, or `maxRequestValiditySeconds=61` | `delegation_attenuation_violation` |
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
| Require `resource:write` on the depth-two route | authenticated `insufficient_permissions` with 403 |
| Flip one grant-signature bit and re-sign the request over the mutated field | `bad_grant_signature` after leaf proof |
| Make grant-issuer account classification unavailable | `grant_verification_unavailable` with 503 |
| Return `isRevoked=true` for `g1` | `authorization_revoked` |
| Return epoch 8 for Root or 4 for Delegate A | `authorization_epoch_mismatch` |
| Make registry state unavailable with no live positive entry | `revocation_unavailable` with 503 |
| Revoke the middle link in the three-link derived chain | `authorization_revoked` |
| Advance the middle link issuer's epoch in the three-link derived chain | `authorization_epoch_mismatch` |
| Put a well-formed failing Delegated candidate before either positive candidate | the later candidate wins; the failed nonce remains unused |
