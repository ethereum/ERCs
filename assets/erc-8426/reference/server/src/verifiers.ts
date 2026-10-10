import {
  isAddressEqual,
  recoverMessageAddress,
  type Address,
  type Hex,
  type PublicClient,
} from "viem";

/// Verifies that `signature` is a valid signature of `message` by `address`.
///
///  This is an interface so the caller chooses how much of the account model to
///  support. The standard's authorization section calls for verifying the
///  control proof for externally owned accounts and contract accounts alike,
///  "as with contract account signatures verified per ERC-1271". A production
///  server injects the public-client verifier below, which does exactly that.
///  Tests inject the EOA-only verifier so they need no chain.
///
///  `signature` is any hex string; the handlers check only that it is hex. An
///  EOA signature is exactly 65 bytes (132 hex characters), but an ERC-1271
///  contract-account signature may be longer, so the length is left for the
///  verifier to judge. A verifier MAY throw on a signature it cannot decode;
///  `authorize` treats a throw as a signature that did not verify.
export interface SignatureVerifier {
  verify(input: { address: Address; message: string; signature: Hex }): Promise<boolean>;
}

/// EOA-only verifier: recover the signer from an ERC-191 personal-signed
///  message and compare. Offline and dependency-free, which is why the tests
///  use it. It cannot validate ERC-1271 contract-account signatures, because
///  those require a chain call to the account's `isValidSignature`.
export function eoaSignatureVerifier(): SignatureVerifier {
  return {
    async verify({ address, message, signature }) {
      const recovered = await recoverMessageAddress({ message, signature });
      return isAddressEqual(recovered, address);
    },
  };
}

/// Production verifier: viem's `verifyMessage` resolves an EOA signature by
///  recovery and, when that does not match, falls through to ERC-1271
///  `isValidSignature` (and ERC-6492 for not-yet-deployed accounts). One call
///  covers every account type the standard names, including the email-derived
///  contract accounts it mentions.
export function publicClientSignatureVerifier(client: PublicClient): SignatureVerifier {
  return {
    async verify({ address, message, signature }) {
      return client.verifyMessage({ address, message, signature });
    },
  };
}
