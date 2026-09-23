# Typed-data signature requests

This document specifies the `typed_data_signature_request` type in ERC-8410.
It is the single additional document type alongside `execution_plan`, sharing
its reference envelope but keeping a separate body and request digest. This
is not a generic artifact extension mechanism. Supporting this type is optional;
the requirements below apply to implementations that support it. Existing
execution-plan v1 documents and digests are unchanged.

## Motivation

An intent producer may return several EIP-712 approvals, accept their signatures,
and only then construct an order for another signing round. A solver may settle
the order without the wallet broadcasting any transaction. A gasless supply
flow may instead return a transaction after receiving a permit signature.

These flows need portable, concrete signing requests. They do not require a
workflow language inside an execution plan. The producer constructs each next
request after receiving the preceding results; the wallet evaluates each new
request independently. An execution plan is returned only when there are actual
calls for the wallet to execute.

## Specification

The key words MUST, MUST NOT, REQUIRED, SHOULD, SHOULD NOT, and MAY are to be
interpreted as described in RFC 2119 and RFC 8174.

### Request artifact

The reference envelope's `artifact_type` MUST be `typed_data_signature_request`. Consumers
MUST apply ERC-8410's reference retrieval and integrity rules, using their
typed-data size limit rather than the execution-plan size limit. Consumers that
do not implement this artifact type MUST reject it. Inline requests are also
permitted, with no verified producer origin inferred from their contents.

The [request schema](typed-data-signature-request.schema.json) defines this body:

| Field | Required | Meaning |
| --- | --- | --- |
| `schema_version` | yes | `"1"` |
| `kind` | yes | `"typed_data_signature_request"` |
| `signer` | yes | Expected account, as a 20-byte hexadecimal address |
| `typed_data` | yes | Complete EIP-712 `types`, `primaryType`, `domain`, `message` |
| `valid_until` | no | Exclusive wallet signing and release cutoff |
| `delivery` | no | Required release destination when present |

Unknown body fields MUST be rejected. Optional fields MUST be omitted when
absent; explicit nulls are invalid. Producer prose belongs in the reference's
unauthoritative `instruction`, not among signed message fields or policy inputs.
The body contains exactly one message. Several independent approvals MAY be
returned as several references in one tool response.

`signer` MUST identify the account whose authorization the verifier expects.
Consumers MUST verify it against the selected account. They MUST NOT silently
replace a contract account with its owner's address. Signature/account formats
unsupported by either the wallet or the intended verifier MUST be rejected.

`valid_until`, when present, MUST be Unix time in seconds, encoded as a
canonical unsigned decimal string fitting uint64. Consumers MUST refuse to sign
or release at or after that time, and MUST check again after any approval wait.
It is a wallet constraint, not a claim about the verifier's expiration rules.

### Typed-data validation

`typed_data` MUST be an EIP-712 object, not a JSON string containing one.
`types.EIP712Domain` MUST explicitly describe the supplied domain. This revision
supports the standard domain fields `name`, `version`, `chainId`,
`verifyingContract`, and `salt`, with the types and order specified in EIP-712,
omitting absent fields. Other domain fields require a later revision.
`primaryType` MUST name a declared message type and MUST NOT be `EIP712Domain`.

Consumers MUST reject duplicate JSON keys before converting the document into a
map. They MUST reject duplicate struct member names, missing or undeclared
message/domain members, invalid types, unresolved type references, unused type
declarations (apart from `EIP712Domain`), and values that do not fit their
declared types. This applies recursively to structs and arrays. Type references
may be recursive, but concrete values MUST be finite and within resource limits.

Integer values MUST be canonical decimal strings, never JSON numbers. Unsigned
values use `0` or a digit string with no leading zero; signed values additionally
allow a leading minus for nonzero values. `-0`, leading plus, and exponent forms
are invalid. Booleans MUST be JSON booleans. Strings MUST contain valid Unicode
scalar values and MUST NOT be normalized. Addresses and bytes MUST have a `0x`
prefix, even-length hexadecimal digits, and the length required by their type.
Producers MUST emit lowercase hexadecimal; consumers MUST normalize hexadecimal
case by declared type for hashing. Ordinary string values are case-sensitive.

Domain chain IDs, if present, are signed message data. An outer chain selection
MUST NOT be represented as replay protection for a chainless message. Wallets
MAY require a domain chain ID or other restrictions as policy. A contract-account
validation chain selected outside the message MUST be recorded separately from
the signed domain. This format does not require wallets to support every
EIP-712 domain or account kind.

Type and member identifiers MUST match `[A-Za-z_][A-Za-z0-9_]*`. Type
expressions MUST be at most 128 characters. This revision permits at most 128
types and 128 members per type, as enforced by the schema. Consumers MUST also
bound document size, nesting, and arrays before expensive hashing or review.
RECOMMENDED limits are 256 KiB per request, 64 levels of value nesting, and
4096 total array elements. Consumers MUST reject rather than truncate. The schema checks
structure only; these semantic and procedural checks are also REQUIRED.

### Digests and approval binding

There are three different commitments:

1. **Artifact integrity** is ERC-8410's keccak256 over the exact retrieved bytes.
2. **Signing digest** is the EIP-712 value
   `keccak256(0x1901 || domainSeparator || hashStruct(message))`.
3. **Request digest** identifies the wallet request, including the signer and
   release constraints, as specified below.

The consumer MUST calculate the signing digest from the validated typed data.
`hashStruct(message)` alone is insufficient: it omits the domain separator.
The account signs the signing digest using its supported EIP-712 signing
mechanism. It MUST NOT sign the request digest in place of the signing digest.

The request digest is keccak256 of the UTF-8 serialization of this projection:

```json
{
  "kind": "typed_data_signature_request",
  "schema_version": "1",
  "signer": "0x1111111111111111111111111111111111111111",
  "signing_digest": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "valid_until": "1800000000",
  "delivery": {
    "url": "https://producer.example/signature-results",
    "request_id": "quote-123-permit-1"
  }
}
```

The zero digest above is a placeholder illustrating the projection, not a test
vector. [Concrete vectors](typed-data-test-vectors.json) include all digests.

Member order MUST be exactly as shown, including `url` before `request_id`.
There MUST be no whitespace between tokens. Hexadecimal values MUST be lowercase.
Absent `valid_until` and `delivery` MUST be represented as JSON null in the
projection, even though null is not accepted in the input artifact. All other
scalar values are strings. The restricted ASCII delivery fields below and the
other projection strings MUST be emitted literally without optional JSON
escapes. This fixed-order serialization follows the execution-plan convention;
it is not RFC 8785 canonicalization. No EIP-712 JSON canonicalization is needed:
the typed data contributes its signing digest, not a serialized JSON object.

Changing signer, signed message/domain, cutoff, destination, or producer request
ID changes the request digest. Reordering JSON object keys does not. Consumers
MUST bind authorization to the request digest and selected account instance,
and MUST recheck current policy and expiry before signing or releasing. The
policy record MUST additionally bind any wallet-observed provenance or other
context used in the decision. A producer-authored origin string, a digest, or
a previously approved request does not establish authority.

### Signature results

The [result schema](typed-data-result.schema.json) defines the value returned to
the caller or delivered to the producer:

```json
{
  "kind": "typed_data_result",
  "schema_version": "1",
  "request_digest": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "signing_digest": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "signer": "0x1111111111111111111111111111111111111111",
  "signature": "0x1234"
}
```

This is a shape example, not a valid signature. `signature` is an opaque,
nonempty hexadecimal byte string. Consumers MUST NOT assume it is 65 bytes or
split it into r/s/v in the portable format. EOAs commonly use that encoding;
contract-account validation may use a different one, including ERC-1271.
The recipient MUST associate the result with its stored request, recompute both
digests, match the signer, and verify the signature using the agreed account
validation mechanism before accepting it. Verifying a signature does not prove
that an order has settled.

### Optional controlled delivery

Omitting `delivery` allows the wallet to return raw signature bytes to its
caller. The wallet MUST treat this as release to the caller: producer prose
cannot constrain where that caller forwards the bytes.

When `delivery` is present, it is a requirement, not a hint. A consumer that
cannot enforce this profile MUST reject the request. It MUST NOT fall back to
returning the signature to the agent. It MAY return a wallet-local opaque handle
or a delivery receipt; any handle MUST be scoped to the caller, account, and
request, and MUST NOT permit raw signature export or destination substitution.
Handles are not public artifact references.

`delivery` MUST contain exactly `url` and `request_id`. This initial profile
restricts the URL to `https://` followed by a lowercase ASCII DNS hostname with
at least two labels, followed by an absolute path. Host labels are 1–63 letters,
digits, or hyphens, with an alphanumeric first and last character; the hostname
is at most 253 characters. Each nonempty path segment uses only ASCII letters,
digits, underscores, and hyphens. `/` is allowed; other trailing or repeated
slashes are not. Ports, IP literals, userinfo, query strings, fragments,
percent-encoding, and dot segments are forbidden. The full URL MUST be at most
2048 characters. `request_id` is 1–128 ASCII
letters, digits, underscores, or hyphens. These restrictions avoid URL and JSON
canonicalization ambiguity. They do not require a fixed endpoint path.

The destination MUST have the same HTTPS origin as the origin from which the
wallet itself retrieved and verified the request. Inline, `data:`, and `file:`
requests therefore cannot use this profile. Producer identity is the observed HTTPS
origin, not the EIP-712 domain name, an MCP alias, or a field in an envelope.
Policies MAY restrict permitted paths as well as origins. Trusting an origin
requires knowing that its admitted paths do not merely host arbitrary
attacker-authored request bodies. TLS proves origin control, not protocol safety.

The wallet MUST independently authorize both signing and release. A single owner
review or explicit policy MAY cover both. It MUST reapply ERC-8410's public
address, TLS, no-redirect, timeout, size, and no-ambient-credentials rules at
delivery time and connect only to a checked address. The wallet MUST NOT accept
caller-specified HTTP methods, headers, or body templates. Signatures MUST NOT
appear in URLs, logs, or error messages. Response bodies are untrusted input.
This profile uses no ambient authentication; authenticated delivery would need
a separately specified connection profile.

The wallet POSTs `application/json` to `delivery.url` with the exact shape
defined in the [delivery request schema](typed-data-delivery.schema.json):

```json
{
  "action": "submit",
  "request_id": "quote-123-permit-1",
  "result": {
    "kind": "typed_data_result",
    "schema_version": "1",
    "request_digest": "0x0000000000000000000000000000000000000000000000000000000000000000",
    "signing_digest": "0x0000000000000000000000000000000000000000000000000000000000000000",
    "signer": "0x1111111111111111111111111111111111111111",
    "signature": "0x1234"
  }
}
```

These placeholder values have the same meaning as in the result example. The
receiver MUST match `request_id` and the request digest to its stored request,
including its delivery URL, and verify the signature before any state change.
It MUST deduplicate by request digest: retrying the same request MUST NOT create
another order or effect, including when another valid encoding of its signature
is supplied. The deduplication state MUST persist for as long as replay could
cause a distinct effect, or the underlying protocol MUST prevent that effect.

The same endpoint MUST support status lookup without releasing a signature:

```json
{
  "action": "status",
  "request_id": "quote-123-permit-1",
  "request_digest": "0x0000000000000000000000000000000000000000000000000000000000000000"
}
```

Both operations return the [receipt shape](typed-data-receipt.schema.json):
`kind: "typed_data_receipt"`, `schema_version: "1"`, the exact `request_id`
and `request_digest`, and `status` equal to `accepted`, `rejected`, or `unknown`.
`accepted` requires an opaque `operation_id`, stable for that request, with the
same character and length restrictions as `request_id`. Other statuses MUST
omit `operation_id`.
Receipts MUST NOT return signatures or private order contents. Deployments MUST
use unguessable request IDs where even operation existence is sensitive and
MUST rate-limit lookups. Unknown and mismatched lookup pairs MUST return no
information about other requests.

`accepted` means the producer durably accepted the result, not that a solver
accepted an order or that settlement occurred. `rejected` means that producer
declined it, not that the signature is unusable elsewhere. `unknown`, malformed
responses, and transport failures are ambiguous. Consumers MUST persist this
state, query or retry the same request, and MUST NOT assume it is safe to sign a
replacement order. Submission retries remain subject to `valid_until`; status
lookups do not release a signature and MAY continue after that cutoff.

This profile deliberately starts with producer proxying. Direct third-party
delivery and MCP-native result injection may be specified separately. DNS
resolution alone cannot authorize a recipient, and this profile makes no claim
that the producer cannot forward a signature after receiving it.

### Re-enterable flows

The following names illustrate tool behavior, not required MCP method names or
a claim about a deployed producer API:

```text
prepare_order(inputs)
  -> approval request references A, B, C
sign(A), sign(B), sign(C)
  -> raw results, or controlled delivery receipts
prepare_order(session, results or receipt identifiers)
  -> order request reference O
sign(O)
  -> raw result for relay_order(), or producer delivery receipt
order_status(operation_id)
  -> producer-specific acceptance and settlement status
```

Each request MUST contain final typed data before it is authorized. The producer
MAY construct O using A/B/C signatures; there is no template evaluation inside
the wallet. Session IDs and predecessor results correlate work, not authority.
Every subsequent artifact MUST be independently validated and authorized.

Alternatively, the producer returns an execution-plan v1 reference after the
approval signatures. Its calldata already contains any signatures it consumes.
The wallet uses ordinary plan simulation, authorization, and execution. Existing
`signature_dependent_execution` may label such a call, but conveys no authority.

No execution plan is required when only offchain signing and relay occur. A
transaction-first flow waits for the necessary transaction confirmation before
preparing the next concrete request. Orchestrators SHOULD bound rounds, waits,
and retries and MUST NOT treat producer instructions as permission to sign.

## Security and policy considerations

### Separate signing authority

Implementations adding this format MUST NOT implicitly expand existing
transaction policies to authorize typed-data signatures. A wallet may initially
support only owner-reviewed signing. Unattended policies should bind the
verified producer origin, signer, complete domain/type identity, and appropriate
typed message values. A friendly name or `primaryType` alone does not identify
an authorization's semantics. Policies should consider spending limits,
recipients, tokens, nonces, deadlines, and any witness binding as applicable.

Review, policy, and signing MUST use the same validated typed-data semantics.
A signature request does not supply a generic transaction simulation. Protocol
adapters may add meaningful checks, but a successful earlier transaction
simulation is not evidence of a later order's safety. Limits on cumulative
authority must account for outstanding signatures and concurrent requests,
not only mined spend.

### No rollback or recipient restriction on use

Several signatures are not an atomic batch. An earlier permit may remain usable
if a later signature is denied or the workflow stops. Before releasing any
signature, the wallet must assess the authority of that signature independently
of hoped-for later steps. Delivery confinement protects where the wallet
releases bytes; it does not restrict their subsequent use by the producer or
another recipient. Only verifier-enforced signed conditions can do that.

### Expiry and replay

`valid_until` limits new wallet signing and release; it does not revoke a
signature already released. Protocol expiry must be enforced through the signed
message and verifier. In particular, an ERC-2612 deadline limits when the permit
can be accepted, not how long the resulting allowance lasts. EIP-712 hashing
does not itself provide nonce consumption or replay prevention.

Changing a wallet cutoff requires a new request digest and reevaluation. A
digest-excluded freshness estimate may guide scheduling outside the artifact,
but MUST NOT extend a bound deadline or grant signing authority. No expiry
field or new extension semantics are added to execution-plan v1.

## Interoperability review

- Does one concrete message per artifact, with multiple references per tool
  response, cover the producer's approval batches and second signing round?
- Is the optional same-origin HTTPS delivery profile useful now, or should the
  first integration return raw results through existing MCP tool calls?
- Which account formats and protocol-specific validations must the first
  integration support? The wire format alone cannot establish verifier support.

These questions guide review of this draft; they do not change the
requirements of the proposed profile above.

## Validation assets

The [fixture runner](typed-data-tests/README.md) checks schemas, request-digest
vectors, and EIP-712 hashes with independent ethers and viem implementations.
It also recomputes every existing execution-plan vector. It is not a wallet,
network delivery implementation, or complete adversarial EIP-712 parser.

## References

- [EIP-712](https://eips.ethereum.org/EIPS/eip-712)
- [ERC-1271](https://eips.ethereum.org/EIPS/eip-1271)
- [ERC-2612](https://eips.ethereum.org/EIPS/eip-2612)

## Copyright

Copyright and related rights waived via [CC0](../../LICENSE.md).
