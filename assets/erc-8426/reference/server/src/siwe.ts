import { createSiweMessage } from "viem/siwe";
import { getAddress, type Address } from "viem";

import { assetId, actionUrn, normalizeTokenId } from "./caip.js";

export interface ChallengeParams {
  domain: string;
  uri: string;
  account: Address;
  chainId: number;
  contract: Address;
  tokenId: string | number | bigint;
  action: string;
  nonce: string;
  issuedAt: Date;
  expirationTime: Date;
}

/// Serialize a challenge as a Sign-In with Ethereum message (ERC-4361), the
///  serialization the standard RECOMMENDS. The output matches the spec's worked
///  example field for field, except that viem emits RFC 3339 timestamps with
///  fractional seconds (.000Z) where the example omits them; both forms conform:
///
///    - the verifier identity is the `domain` on the first line
///    - the claimed account is the `address` line
///    - the action is named in plain language in the `statement` and, machine
///      readable, as an `urn:wallet-pass:action:<name>` resource
///    - the token is the CAIP-19 asset id resource (chain id, contract, token
///      id together)
///    - the single-use nonce is `Nonce`, the expiry is `Expiration Time`
///
///  The statement wording mirrors the example
///  ("Authorize the feed action for wallet pass token 412 on issuer.example.").
export function buildChallengeMessage(params: ChallengeParams): string {
  const tokenId = normalizeTokenId(params.tokenId);
  return createSiweMessage({
    domain: params.domain,
    address: getAddress(params.account),
    statement: `Authorize the ${params.action} action for wallet pass token ${tokenId} on ${params.domain}.`,
    uri: params.uri,
    version: "1",
    chainId: params.chainId,
    nonce: params.nonce,
    issuedAt: params.issuedAt,
    expirationTime: params.expirationTime,
    resources: [assetId(params.chainId, params.contract, tokenId), actionUrn(params.action)],
  });
}

export { parseSiweMessage, generateSiweNonce } from "viem/siwe";
