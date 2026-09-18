# ERC-8128 signer and verifier pseudocode

The reference implementation signs the RFC 9421 signature base `M`, covering `@scheme`, `@authority`, `@method`, `@path`, and `@query`, plus the content fields required by Section 3.1.1. The signer computes an ERC-191 signature over `M`, and the verifier applies Universal Account verification.

## Signer (client)

Steps:

1. If the request has a body, compute and attach `Content-Digest`.
2. Build `Signature-Input` with the covered components and required parameters.
3. Construct `M` exactly per RFC 9421.
4. Produce an ERC-191 signature over `M`, then set `Signature-Input` and `Signature`.

```ts
type Req = {
  scheme: string;
  method: string;
  authority: string; // host[:port]
  path: string;
  query?: string;    // includes leading "?"; absent serializes as "?"
  body?: Uint8Array;
  headers: Record<string, string>;
};

type SignParams = {
  keyid: `eip155:${number}:0x${string}`;
  created: number;  // unix seconds
  expires: number;  // unix seconds
  nonce?: string;   // sf-string (recommend base64url)
  label?: string;   // sf-key; defaults to "eth"
};

function covered(req: Req): string[] {
  const c = ["@scheme", "@authority", "@method", "@path", "@query"];
  if (req.headers["content-digest"]) c.push("content-digest");
  if (req.headers["content-type"]) c.push("content-type");
  return c;
}

export async function signRequest(
  req: Req,
  wallet: { signMessage: (m: string) => Promise<Uint8Array> },
  p: SignParams
): Promise<Req> {
  if (req.body && req.body.length > 0 && !req.headers["content-digest"]) {
    req.headers["content-digest"] = computeContentDigest(req.body); // RFC Content-Digest value
  }

  const label = p.label ?? "eth";
  const components = covered(req);

  // Serialize Signature-Input per RFC 9421 (Structured Fields)
  const sigInput = sfSerializeSignatureInput(label, components, {
    created: p.created,
    expires: p.expires,
    nonce: p.nonce,
    keyid: p.keyid,
    tag: "erc8128",
  });

  // RFC 9421: compute the signature base for the selected label
  const M = createSignatureBase(req, label, sigInput);

  // Ethereum signing: ERC-191 over the UTF-8 bytes of M
  const sigBytes = await wallet.signMessage(M);

  req.headers["signature-input"] = sigInput;
  req.headers["signature"] = `${label}=:${base64(sigBytes)}:`;
  return req;
}
```

## Verifier (server)

Steps:

1. Parse the complete `Signature-Input` and `Signature` fields.
2. Evaluate candidates in wire order under the limits in Section 3.5.
3. Validate the served chain, request coverage, content, time, replay posture, and policy.
4. Reconstruct `M` and apply Universal Account verification.
5. Atomically consume the winning nonce.

```ts
async function verifyRequest(req: Request, policy: Policy): Promise<AuthResult> {
  const fields = parseWholeSignatureFields(req); // whole-field SF errors throw signature_input_invalid
  const candidates = candidatesInWireOrder(fields, "erc8128");
  enforceLimits(fields, candidates);              // signature_too_large
  const failures: FailureCode[] = [];

  for (const candidate of candidates) {
    const checked = validateBeforeRpc(req, candidate, policy);
    if (!checked.ok) { failures.push(checked.reason); continue; }

    const M = rfc9421SignatureBase(req, candidate);
    const H = eth191Hash(M);
    const proof = await verifyUniversalAccount(candidate.keyid, H, candidate.signature);
    if (proof === "invalid") { failures.push("bad_signature"); continue; }
    if (proof === "unavailable") {
      failures.push("signature_verification_unavailable"); continue;
    }

    if (candidate.nonce !== undefined &&
        !await consumeIfUnused([checked.signer, candidate.nonce], checked.replayUntil)) {
      failures.push("nonce_reused"); continue;
    }
    return checked.result;
  }
  throw selectFailure(failures);
}
```
