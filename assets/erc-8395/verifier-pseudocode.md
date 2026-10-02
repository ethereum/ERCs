# ERC-8395 verifier pseudocode

Reference pseudocode for [ERC-8395](../../ERCS/erc-8395.md).

A signer selects a supported profile, supplies its public key when required, obtains a grant from the Ethereum root or an authorized delegate, and signs each RFC 9421 signature base using that profile. For example, a WebCrypto P-256 key uses `delegateProfile="ecdsa-p256-sha256"`; the grant carries its public JWK in `delegate`, from which the signer derives its SHA-256 JWK Thumbprint URI. An existing Ethereum wallet uses an Ethereum profile and its Account ID in `delegate`.

```ts
async function verifyDelegated(req: Request, candidate: Candidate, policy: Policy) {
  const links = decodeAndValidateLinks(req.delegationField, policy.limits);
  const chain = reconstructAndValidateChain(links); // expands signed fields, checks parent digests and attenuation
  validateLocallyBeforeRpc(req, candidate, chain, policy); // includes route opt-in and profile/alg checks

  const M = signatureBase(req, candidate);
  const leafProof = await verifyWithDelegateProfile(
    chain.leaf.delegateProfile, chain.leaf.delegate, M, candidate.sig
  ); // Ethereum adapter or existing HTTP Message Signature algorithm implementation
  if (!leafProof.valid) throw classifiedRequestProofFailure(leafProof);

  for (let i = links.length - 1; i >= 0; i--) {
    const link = links[i];
    const digest = link.digest ??= eip712DelegationDigest(link.grant, chain.revocationAccounts[i]);
    const proof = grantCache.get([digest, link.signature])
      ?? await verifyGrantProof(link, links[i - 1], chain.revocationAccounts[i], digest);
    if (!proof.valid) throw classifiedGrantProofFailure(proof);
  }

  for (let i = 0; i < links.length; i++) {
    await requireActive(links[i], chain.revocationAccounts[i], chain.registryHandles[i]);
  }
  requireRoutePermissions(chain.effectivePermissions, policy.requiredPermissions);
  if (candidate.nonce !== undefined) await consumeLeafNonceLast(candidate, chain.leaf.delegateId);
  else await requireReplayableInvalidationActive(candidate, chain.leaf.delegateId);
  return delegatedResult(chain);
}
```
