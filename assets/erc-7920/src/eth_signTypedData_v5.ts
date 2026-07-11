import { ethers } from "ethers";
import { keccak256 } from "@ethersproject/keccak256";
import { Eip712TypedData } from "web3";
import {
  ecrecover,
  fromRpcSig,
  publicToAddress,
  bytesToHex,
} from "@ethereumjs/util";
import * as sigUtil from "eth-sig-util";

import { MerkleTree } from "./merkle";

type MerkleProof = ReadonlyArray<`0x${string}`>;

/**
 * Signs multiple EIP-712 typed data messages with a single signature.
 *
 * This function creates a Merkle tree from the hashes of multiple EIP-712 typed data messages,
 * then signs the Merkle root to produce a single signature that can validate any of the individual messages.
 *
 * @param args - The arguments for the function
 * @param args.privateKey - The private key to sign with
 * @param args.messages - Single message or a list of EIP-712 typed data messages to include in the composite signature
 * @returns Object containing the signature, Merkle root, and proofs for each message
 */
async function eth_signTypedData_v5(args: {
  readonly privateKey: Buffer;
  readonly messages: Eip712TypedData | ReadonlyArray<Eip712TypedData>;
}): Promise<{
  readonly signature: `0x${string}`;
  readonly merkleRoot: `0x${string}`;
  readonly proofs: ReadonlyArray<MerkleProof>;
}> {
  const { privateKey } = args;
  const messages = Array.isArray(args.messages)
    ? args.messages
    : [args.messages];
  const messageHashes: ReadonlyArray<Buffer> = messages.map(
    ({ message, domain, types }) => {
      const { EIP712Domain, ...typesWithoutDomain } = types;
      const hash = ethers.TypedDataEncoder.hash(
        domain,
        typesWithoutDomain,
        message
      );

      return Buffer.from(hash.slice(2), "hex");
    }
  );

  const tree = new MerkleTree(messageHashes as Array<Buffer>);

  const merkleRoot = tree.getRoot();
  const wallet = new ethers.Wallet(`0x${privateKey.toString("hex")}`);
  const signature = wallet.signingKey.sign(merkleRoot);

  const proofs: ReadonlyArray<MerkleProof> = messageHashes.map((hash) =>
    tree
      .getProof(hash)
      .map((proof) => `0x${proof.toString("hex")}` as `0x${string}`)
  );

  return {
    signature: signature.serialized as `0x${string}`,
    merkleRoot: `0x${merkleRoot.toString("hex")}`,
    proofs,
  };
}

/**
 * Recovers the signer of a composite message.
 *
 * This function verifies that a message was included in a composite signature by:
 * 1. Verifying the Merkle proof against the Merkle root
 * 2. Recovering the signer from the composite signature
 *
 * @param args - The arguments for the function
 * @param args.signature - The signature produced by eth_signTypedData_v5
 * @param args.merkleRoot - The Merkle root of all signed messages
 * @param args.proof - The Merkle proof for the specific message being verified
 * @param args.message - The EIP-712 typed data message to verify
 * @returns The recovered signer address as a 0x-prefixed string, or undefined if the signature or proof is invalid
 */
function recoverCompositeTypedDataSig(args: {
  readonly signature: `0x${string}`;
  readonly merkleRoot: `0x${string}`;
  readonly proof: MerkleProof;
  readonly message: Eip712TypedData;
}): `0x${string}` | undefined {
  const { signature, message } = args;

  const { EIP712Domain, ...typesWithoutDomain } = message.types;
  const leafHex = ethers.TypedDataEncoder.hash(
    message.domain,
    typesWithoutDomain,
    message.message
  );
  const leaf = Buffer.from(leafHex.slice(2), "hex");

  const proof = args.proof.map((d) => Buffer.from(d.slice(2), "hex"));
  const merkleRoot = Buffer.from(args.merkleRoot.slice(2), "hex");

  function _keccak256(data: Buffer): Buffer {
    return Buffer.from(keccak256(data).slice(2), "hex");
  }

  let computedHash = leaf;
  for (let i = 0; i < proof.length; i++) {
    if (Buffer.compare(computedHash, proof[i]) == -1) {
      computedHash = _keccak256(Buffer.concat([computedHash, proof[i]]));
    } else {
      computedHash = _keccak256(Buffer.concat([proof[i], computedHash]));
    }
  }

  if (Buffer.compare(computedHash, merkleRoot) != 0) {
    return;
  }

  const sigParams = fromRpcSig(signature);
  const pubKey = ecrecover(merkleRoot, sigParams.v, sigParams.r, sigParams.s);
  return bytesToHex(publicToAddress(pubKey)) as `0x${string}`;
}

async function main() {
  const messages: ReadonlyArray<Eip712TypedData> = [
    {
      types: {
        EIP712Domain: [
          { name: "name", type: "string" },
          { name: "version", type: "string" },
          { name: "chainId", type: "uint256" },
          { name: "verifyingContract", type: "address" },
        ],
        Mail: [
          { name: "from", type: "Person" },
          { name: "to", type: "Person" },
          { name: "contents", type: "string" },
        ],
        Person: [
          { name: "name", type: "string" },
          { name: "wallet", type: "address" },
        ],
      },
      primaryType: "Mail",
      domain: {
        name: "Ether Mail",
        version: "1",
        chainId: 1,
        verifyingContract: "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC",
      },
      message: {
        from: {
          name: "Cow",
          wallet: "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826",
        },
        to: {
          name: "Bob",
          wallet: "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB",
        },
        contents: "Hello, Bob!",
      },
    },
    {
      types: {
        EIP712Domain: [
          { name: "name", type: "string" },
          { name: "version", type: "string" },
          { name: "chainId", type: "uint256" },
          { name: "verifyingContract", type: "address" },
        ],
        Transfer: [
          { name: "amount", type: "uint256" },
          { name: "recipient", type: "address" },
        ],
      },
      primaryType: "Transfer",
      domain: {
        name: "Ether Mail",
        version: "1",
        chainId: 1,
        verifyingContract: "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC",
      },
      message: {
        amount: "1000000000000000000",
        recipient: "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB",
      },
    },
    {
      types: {
        EIP712Domain: [
          { name: "name", type: "string" },
          { name: "version", type: "string" },
          { name: "chainId", type: "uint256" },
          { name: "verifyingContract", type: "address" },
        ],
        Transfer: [
          { name: "amount", type: "uint256" },
          { name: "recipient", type: "address" },
        ],
      },
      primaryType: "Transfer",
      domain: {
        name: "Ether Mail",
        version: "1",
        chainId: 1,
        verifyingContract: "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC",
      },
      message: {
        amount: "2000000000000000000",
        recipient: "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB",
      },
    },
    {
      types: {
        EIP712Domain: [
          { name: "name", type: "string" },
          { name: "version", type: "string" },
          { name: "chainId", type: "uint256" },
          { name: "verifyingContract", type: "address" },
        ],
        Transfer: [
          { name: "amount", type: "uint256" },
          { name: "recipient", type: "address" },
        ],
      },
      primaryType: "Transfer",
      domain: {
        name: "Ether Mail",
        version: "1",
        chainId: 1,
        verifyingContract: "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC",
      },
      message: {
        amount: "3000000000000000000",
        recipient: "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB",
      },
    },
  ];

  const nonMessage = {
    types: {
      EIP712Domain: [
        { name: "name", type: "string" },
        { name: "version", type: "string" },
        { name: "chainId", type: "uint256" },
        { name: "verifyingContract", type: "address" },
      ],
      Transfer: [
        { name: "amount", type: "uint256" },
        { name: "recipient", type: "address" },
      ],
    },
    primaryType: "Transfer",
    domain: {
      name: "Ether Mail",
      version: "1",
      chainId: 1,
      verifyingContract: "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC",
    },
    message: {
      amount: "4000000000000000000",
      recipient: "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB",
    },
  };

  const wallet = ethers.Wallet.createRandom();
  const result = await eth_signTypedData_v5({
    privateKey: Buffer.from(wallet.privateKey.slice(2), "hex"),
    messages,
  });

  for (let i = 0; i < messages.length; i++) {
    const recovered = recoverCompositeTypedDataSig({
      signature: result.signature,
      merkleRoot: result.merkleRoot,
      proof: result.proofs[i],
      message: messages[i],
    });
    if (
      recovered == null ||
      recovered.toLowerCase() != wallet.address.toLowerCase()
    ) {
      throw new Error("Recovered address does not match");
    }
  }

  console.log("All messages recovered ✅");

  const nonRecovered = recoverCompositeTypedDataSig({
    signature: result.signature,
    merkleRoot: result.merkleRoot,
    proof: result.proofs[0],
    message: nonMessage,
  });

  if (nonRecovered != null) {
    throw new Error("Non-message recovered ❌");
  }

  console.log("Non-message not recovered ✅");

  const singleMessage = await eth_signTypedData_v5({
    privateKey: Buffer.from(wallet.privateKey.slice(2), "hex"),
    messages: messages[0],
  });

  const singleMessageSig = sigUtil.signTypedData_v4(
    Buffer.from(wallet.privateKey.slice(2), "hex"),
    {
      data: messages[0],
    }
  );

  if (singleMessage.signature != singleMessageSig) {
    throw new Error("Single message signature does not match");
  }

  console.log("Single message signature matches ✅");
}

main();
