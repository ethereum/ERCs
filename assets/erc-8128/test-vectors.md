# ERC-8128 test vectors

Test vectors for [ERC-8128](../../ERCS/erc-8128.md).

The fixed private key is public and MUST NOT hold assets:

| Role | Private key | Account ID |
| --- | --- | --- |
| Signer | `0x0000000000000000000000000000000000000000000000000000000000000001` | `eip155:1:0x7e5f4552091a69125d5dfcb7b8c2659029395bdf` |

For these vectors, the verifier clock is `1700000001`, allowed skew is 30 seconds, the origin is reconstructed as HTTPS, the Account has no code, replay state is initially empty, and Principal policy accepts the Account.

## Positive vector

The exact request content is the 17 ASCII bytes `{"hello":"world"}`. Its SHA-256 digest is `k6I5cakU5erL8KjSUVTNownDwccvu5kU1Hxg88toFYg=`. The complete request is:

```http
POST /items?view=full HTTP/1.1
Host: api.example
Content-Type: application/json
Content-Length: 17
Content-Digest: sha-256=:k6I5cakU5erL8KjSUVTNownDwccvu5kU1Hxg88toFYg=:
Signature-Input: request=("@scheme" "@authority" "@method" "@path" "@query" "content-digest" "content-type");created=1700000000;expires=1700000060;nonce="EjRWeJCrze8BI0VniavN7w";keyid="eip155:1:0x7e5f4552091a69125d5dfcb7b8c2659029395bdf";tag="erc8128"
Signature: request=:/BpEToskxkMJ65uRmaNUPiBwbwwg6z3CxEDJJwEYREIx1Hwn85Z1L8XlRpILGx4q80yeiNugYzaUsVPWiPcB0Bs=:

{"hello":"world"}
```

The exact signature base `M` is 449 UTF-8 bytes, uses one LF byte between displayed lines, and has no trailing LF:

```text
"@scheme": https
"@authority": api.example
"@method": POST
"@path": /items
"@query": ?view=full
"content-digest": sha-256=:k6I5cakU5erL8KjSUVTNownDwccvu5kU1Hxg88toFYg=:
"content-type": application/json
"@signature-params": ("@scheme" "@authority" "@method" "@path" "@query" "content-digest" "content-type");created=1700000000;expires=1700000060;nonce="EjRWeJCrze8BI0VniavN7w";keyid="eip155:1:0x7e5f4552091a69125d5dfcb7b8c2659029395bdf";tag="erc8128"
```

```text
H = 0xa7a6074cd2ab23379c04a8839a3566e98689326367a0ad9cd8ef389a961f96de
S = 0xfc1a444e8b24c64309eb9b9199a3543e20706f0c20eb3dc2c440c9270118444231d47c27f396752fc5e546920b1b1e2af34c9e88dba0633694b153d688f701d01b
```

The expected Principal and Signer are both the fixture Account. The signature is Request-Bound and Non-Replayable. The nonce is consumed only after all checks pass.

## Negative and classification vectors

Each mutation starts from the positive vector, leaves signature bytes unchanged unless stated, and uses fresh replay state.

| Mutation or state | Expected result |
| --- | --- |
| Remove `Signature` or `Signature-Input` | `signature_missing` |
| Make either signature field invalid RFC 9651 syntax | `signature_input_invalid` with 400; no candidate evaluation |
| Remove the correlated `Signature` member from a well-formed first candidate and append the positive candidate | first candidate yields `signature_input_invalid`; later candidate wins |
| Exceed a field, decoded member, component, parameter, or candidate limit | `signature_too_large` with 400 before cryptography |
| Replace the only `tag` with an unknown extension tag | `no_acceptable_signature` |
| Replace `keyid` with a non-canonical CAIP-10 value | `invalid_keyid` |
| Use a valid `keyid` on a chain the verifier does not serve | `unsupported_chain` before RPC |
| Require EOA-only verification and present an ERC-6492 wrapper or an Account with code | `unsupported_account` |
| Remove `created`, make it a String, or set `expires <= created` | `invalid_time` |
| With `now=1699999969`, keep the displayed times and skew | `request_not_yet_valid` |
| With `now=1700000091`, keep the displayed times and skew | `request_expired` |
| Configure a 60-second route maximum and re-sign with `expires=1700000061` | `request_validity_too_long` before cryptography |
| Make `nonce` a Token or 129 ASCII bytes | `invalid_nonce` |
| Remove `@query` from coverage | `insufficient_coverage` |
| Keep non-empty content but remove `Content-Digest` | `content_digest_required` |
| Change content, make the digest malformed, or add a supported mismatching digest | `bad_content_digest` |
| Remove `nonce` on a Non-Replayable-only route | `nonce_required` |
| Configure the route as an early-invalidation endpoint and re-sign without `nonce` | `nonce_required`; invalidation state is unchanged |
| Submit the positive vector twice | first succeeds; second yields `nonce_reused` |
| Remove `nonce` where Replayable is supported but denied by policy | `replayable_not_allowed` |
| Add `alg` to `Signature-Input` | `unsupported_algorithm` |
| Change the query while retaining the signature | `bad_signature`; no nonce consumption |
| Make account classification RPC unavailable | `signature_verification_unavailable` with 503 |
| Configure Principal policy to reject the displayed Account | `principal_not_allowed` before cryptography |
| Put a well-formed failing candidate before the positive candidate | later candidate wins; this distinguishes the case from `no_acceptable_signature` |
