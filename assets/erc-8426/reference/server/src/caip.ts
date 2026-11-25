import { getAddress, type Address } from "viem";

/// Helpers for the two identifiers the standard carries in a challenge's
///  Resources list: a CAIP-19 asset id that binds (chain id, contract, token
///  id) together, and an action URN that names the requested action.
///
///  Both appear verbatim in the spec's worked example:
///    - eip155:1/erc721:0x5F9B5a1cdED9d6B3f5E8a2C47B0e13d6A8F4c2e1/412
///    - urn:wallet-pass:action:feed

/// A token id is accepted as a string so arbitrarily large ids survive without
///  precision loss. It is validated as a non-negative integer no wider than
///  uint256 and reduced to its canonical decimal form: `412` and `0412` are
///  one token to `ownerOf`, so they must be one key in every store and one
///  asset id in every challenge, or a rotation under one spelling would miss
///  links issued under the other.
export type TokenId = string;

export function normalizeTokenId(value: string | number | bigint): TokenId {
  const asString = typeof value === "string" ? value.trim() : value.toString();
  if (!/^[0-9]+$/.test(asString)) {
    throw new Error(`invalid token id: ${asString}`);
  }
  const canonical = BigInt(asString);
  if (canonical >= 1n << 256n) {
    throw new Error(`invalid token id: ${asString}`);
  }
  return canonical.toString();
}

/// Build the CAIP-19 asset id for an ERC-721 token. The contract is
///  checksummed so the string produced here matches the one recomputed at
///  verification time byte for byte.
export function assetId(chainId: number, contract: Address, tokenId: string | number | bigint): string {
  return `eip155:${chainId}/erc721:${getAddress(contract)}/${normalizeTokenId(tokenId)}`;
}

/// Build the action URN, for example urn:wallet-pass:action:feed.
export function actionUrn(action: string): string {
  return `urn:wallet-pass:action:${action}`;
}
