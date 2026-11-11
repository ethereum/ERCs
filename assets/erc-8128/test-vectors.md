# ERC-8128 test vectors

The fixed private key is public and MUST NOT hold assets:

| Role | Private key | Account ID |
| --- | --- | --- |
| Signer | `0x0000000000000000000000000000000000000000000000000000000000000001` | `eip155:1:0x7e5f4552091a69125d5dfcb7b8c2659029395bdf` |

For these vectors, the verifier clock is `1700000001`, allowed skew is 30 seconds, the origin is reconstructed as HTTPS, the Account has no code, the route accepts Non-Replayable signatures, replay state is initially empty, and Principal policy accepts the Account.

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

The expected Principal and Signer are both the fixture Account. The signature is Request-Bound and Non-Replayable. The nonce is consumed only after all checks pass. A route that does not accept Non-Replayable signatures yields `nonce_not_supported`.

## Positive vector without a nonce

The same request signed without `nonce`, which makes the signature Request-Bound and Replayable. A route that accepts Replayable signatures authenticates it; a route that accepts only Non-Replayable signatures yields `nonce_required`. Only the signature fields differ:

```http
Signature-Input: request=("@scheme" "@authority" "@method" "@path" "@query" "content-digest" "content-type");created=1700000000;expires=1700000060;keyid="eip155:1:0x7e5f4552091a69125d5dfcb7b8c2659029395bdf";tag="erc8128"
Signature: request=:lY9LxcRQU0KTI56g6xpTpleh/JDkZgApnbC5wG4L6OtJtNMRis/6jneKOz9FkE2hrF138NnNs+nD2FP/6fdC3hs=:
```

The exact signature base `M` is 418 UTF-8 bytes, uses one LF byte between displayed lines, and has no trailing LF:

```text
"@scheme": https
"@authority": api.example
"@method": POST
"@path": /items
"@query": ?view=full
"content-digest": sha-256=:k6I5cakU5erL8KjSUVTNownDwccvu5kU1Hxg88toFYg=:
"content-type": application/json
"@signature-params": ("@scheme" "@authority" "@method" "@path" "@query" "content-digest" "content-type");created=1700000000;expires=1700000060;keyid="eip155:1:0x7e5f4552091a69125d5dfcb7b8c2659029395bdf";tag="erc8128"
```

```text
H = 0x9aabac90688b9c0d5b7b16a580ccfcd7322872edfd4c79aacd763eeef3024dfc
S = 0x958f4bc5c450534293239ea0eb1a53a657a1fc90e46600299db0b9c06e0be8eb49b4d3118acffa8e778a3b3f45904da1ac5d77f0d9cdb3e9c3d853ffe9f742de1b
```

## Negative and classification vectors

Each mutation starts from the positive vector with a nonce unless stated, leaves signature bytes unchanged unless stated, and uses fresh replay state.

| Mutation or state | Expected result |
| --- | --- |
| Remove `Signature` or `Signature-Input` | `signature_missing` |
| Make either signature field invalid RFC 9651 syntax | `signature_input_invalid` with 400; no candidate evaluation |
| Remove the correlated `Signature` member from a well-formed first candidate and append the positive candidate | first candidate yields `signature_input_invalid`; later candidate wins |
| Exceed a field, decoded member, component, parameter, or candidate limit | `signature_too_large` with 400 before cryptography |
| Replace the only `tag` with an unknown extension tag | `no_acceptable_signature` |
| Replace `keyid` with a non-canonical CAIP-10 value | `invalid_keyid` |
| Use a valid `keyid` on a chain the verifier does not serve | `unsupported_chain` before RPC |
| Add `mode="eoa"`, re-sign, and make account-state RPC unavailable | authenticates; no account code is obtained |
| Give the Account ERC-1271 code, add `mode="eoa"`, and use a signature that only its implementation accepts | local recovery fails; ERC-1271 is called and its result applies |
| Give the Account an EIP-7702 delegation indicator, add `mode="eoa"`, and re-sign with its key | authenticates by local recovery; ERC-1271 is not called |
| Set `mode` to another String or to a Token and re-sign | ignored; result as without `mode` |
| Remove `created`, make it a String, or set `expires <= created` | `invalid_time` |
| With `now=1699999969`, keep the displayed times and skew | `request_not_yet_valid` |
| With `now=1700000091`, keep the displayed times and skew | `request_expired` |
| Configure a 60-second route maximum and re-sign with `expires=1700000061` | `request_validity_too_long` before cryptography; a challenge that includes `max_validity` carries `60` |
| Make `nonce` a Token or 129 ASCII bytes | `invalid_nonce` |
| Remove `@query` from coverage | `insufficient_coverage` |
| Keep non-empty content but remove `Content-Digest` | `content_digest_required` |
| Change content, make the digest malformed, or add a supported mismatching digest | `bad_content_digest` |
| Remove `nonce` on a Non-Replayable-only route | `nonce_required` |
| Submit the positive vector twice | first succeeds; second yields `nonce_reused` |
| Submit the positive vector to a route that does not accept Non-Replayable signatures | `nonce_not_supported` before cryptography; no replay state is read or written |
| Put the positive candidate before the candidate without a nonce, under distinct labels, on a route that does not accept Non-Replayable signatures | first candidate yields `nonce_not_supported`; later candidate wins |
| Remove `nonce` where Principal policy accepts only Non-Replayable signatures | `nonce_required` |
| Accept Replayable signatures with no early invalidation and submit the vector without a nonce twice | both authenticate; no replay or invalidation state is read or written |
| Accept Replayable signatures with no early invalidation and re-sign without `nonce` with `expires=1700000061` | `request_validity_too_long` before cryptography; a challenge that includes `max_validity` carries `60` |
| Accept Replayable signatures with early invalidation, invalidate the vector without a nonce, and submit it | authenticates; the 60-second window is not checked against invalidation state |
| Accept Replayable signatures with early invalidation, re-sign without `nonce` with `expires=1700000061`, invalidate that signature, and submit it | `signature_invalidated` |
| Add `alg` to `Signature-Input` | `unsupported_algorithm` |
| Change the query while retaining the signature | `bad_signature`; no nonce consumption |
| Make account classification RPC unavailable | `signature_verification_unavailable` with 503 |
| Configure Principal policy to reject the displayed Account | `principal_not_allowed`; before cryptography unless the verifier defers Principal policy (Section 3.5) |
| Put a well-formed failing candidate before the positive candidate | later candidate wins; this distinguishes the case from `no_acceptable_signature` |
