import { encodeAbiParameters, getAddress, keccak256, recoverTypedDataAddress, toBytes, type Address, type Hex } from "viem";
import { REGISTRY_V1_ADDRESSES } from "./abi";
import { decodeReason, encodeReason } from "./reasons";

export const DECISIONS = { ALLOW: 0, DENY: 1, REVIEW: 2 } as const;
export type DecisionName = keyof typeof DECISIONS;

/** What was asked: bound into every receipt so it cannot be reused for another transaction. */
export interface Intent {
  chainId: number | bigint;
  account: Address;
  target: Address;
  value: bigint | string;
  data: Hex;
  /** 0 for a call (default), 1 for a delegatecall; for ERC-7579 accounts the call type byte of the execution mode. */
  operation?: number;
}

export const OPERATIONS = { CALL: 0, DELEGATECALL: 1 } as const;

export const INTENT_TYPEHASH = keccak256(toBytes("Intent(uint256 chainId,address account,address target,uint256 value,bytes32 dataHash,uint8 operation)"));
/** The first draft's intent type (v1), without the operation. */
export const INTENT_TYPEHASH_V1 = keccak256(toBytes("Intent(uint256 chainId,address account,address target,uint256 value,bytes32 dataHash)"));

/** intentHash = keccak256(abi.encode(INTENT_TYPEHASH, chainId, account, target, value, keccak256(data), operation)). */
export function intentHash(i: Intent): Hex {
  const op = i.operation ?? 0;
  if (!Number.isInteger(op) || op < 0 || op > 255) throw new Error("operation must be a uint8");
  return keccak256(
    encodeAbiParameters(
      [{ type: "bytes32" }, { type: "uint256" }, { type: "address" }, { type: "address" }, { type: "uint256" }, { type: "bytes32" }, { type: "uint8" }],
      [INTENT_TYPEHASH, BigInt(i.chainId), getAddress(i.account), getAddress(i.target), BigInt(i.value), keccak256(i.data), op],
    ),
  );
}

/** The first draft's intent hash (v1): no operation, so a call and a delegatecall share it. Audits of old receipts only. */
export function intentHashV1(i: Intent): Hex {
  return keccak256(
    encodeAbiParameters(
      [{ type: "bytes32" }, { type: "uint256" }, { type: "address" }, { type: "address" }, { type: "uint256" }, { type: "bytes32" }],
      [INTENT_TYPEHASH_V1, BigInt(i.chainId), getAddress(i.account), getAddress(i.target), BigInt(i.value), keccak256(i.data)],
    ),
  );
}

/** The signed message. Times are Unix seconds (UTC). */
export interface DecisionMessage {
  account: Address;
  intentHash: Hex;
  decision: number;
  reasonCode: Hex;
  detailCode: Hex;
  policyHash: Hex;
  policyVersion: bigint;
  issuedAt: bigint;
  expiresAt: bigint;
  decisionId: Hex;
}

export const RECEIPT_TYPES = {
  Decision: [
    { name: "account", type: "address" },
    { name: "intentHash", type: "bytes32" },
    { name: "decision", type: "uint8" },
    { name: "reasonCode", type: "bytes32" },
    { name: "detailCode", type: "bytes32" },
    { name: "policyHash", type: "bytes32" },
    { name: "policyVersion", type: "uint64" },
    { name: "issuedAt", type: "uint64" },
    { name: "expiresAt", type: "uint64" },
    { name: "decisionId", type: "bytes32" },
  ],
} as const;

/** True when `registry` is a known first-draft (v1) registry on `chainId`: its receipts use domain version "1". */
export function isV1Registry(chainId: number | bigint, registry: Address): boolean {
  const v1 = REGISTRY_V1_ADDRESSES[Number(chainId)];
  return !!v1 && getAddress(v1) === getAddress(registry);
}

/** The EIP-712 domain: version "2" for the v2 registry, "1" for receipts issued under a v1 registry. */
export function receiptDomain(chainId: number | bigint, registry: Address, version?: "1" | "2") {
  return {
    name: "PolicyDecisionReceipt",
    version: version ?? (isV1Registry(chainId, registry) ? "1" : "2"),
    chainId: BigInt(chainId),
    verifyingContract: getAddress(registry),
  } as const;
}

/** JSON form of a receipt (as an API returns it): every field a string, plus the signature. */
export interface ReceiptJson {
  chainId: string;
  registry: Address;
  account: Address;
  intentHash: Hex;
  decision: DecisionName;
  reasonCode: string;
  detailCode: string;
  policyHash: Hex;
  policyVersion: string;
  issuedAt: string;
  expiresAt: string;
  decisionId: Hex;
  signer: Address;
  signature: Hex;
}

export function toMessage(r: Omit<ReceiptJson, "signature" | "signer" | "chainId" | "registry">): DecisionMessage {
  return {
    account: getAddress(r.account),
    intentHash: r.intentHash,
    decision: DECISIONS[r.decision],
    reasonCode: encodeReason(r.reasonCode),
    detailCode: encodeReason(r.detailCode),
    policyHash: r.policyHash,
    policyVersion: BigInt(r.policyVersion),
    issuedAt: BigInt(r.issuedAt),
    expiresAt: BigInt(r.expiresAt),
    decisionId: r.decisionId,
  };
}

/** The EIP-712 typed data of a receipt. `version` overrides the domain version (default: by registry). */
export const typedReceipt = (r: ReceiptJson, version?: "1" | "2") => ({
  domain: receiptDomain(BigInt(r.chainId), r.registry, version),
  types: RECEIPT_TYPES,
  primaryType: "Decision" as const,
  message: toMessage(r),
});

/** Who signed this receipt (EOA signatures). Contract signers are checked with ERC-1271 in verifyReceipt. */
export async function recoverReceiptSigner(r: ReceiptJson, version?: "1" | "2"): Promise<Address> {
  return recoverTypedDataAddress({ ...typedReceipt(r, version), signature: r.signature });
}

export { decodeReason };
