import { parseAbi } from "viem";

/** ERC-165 interface id of IPolicyEnforcedAccount v2 (XOR of its seven read selectors). */
export const INTERFACE_ID = "0x7e0f19f9" as const;
/** ERC-165 interface id of the first draft (v1, six read selectors). */
export const INTERFACE_ID_V1 = "0xcc16d336" as const;

/** Reference registry v2 deployments (same address on every chain, via the deterministic deployer). */
export const REGISTRY_ADDRESSES: Record<number, `0x${string}`> = {
  4663: "0xCa3bAE26d29a3A2cED7B87Fa996ca4C44367448d", // Robinhood Chain mainnet
};
/** The first draft's registry (v1). Still readable; receipts issued under it verify with domain version "1". */
export const REGISTRY_V1_ADDRESSES: Record<number, `0x${string}`> = {
  4663: "0x20D6B38B47F7cb765A2318a1f318ed54a6f87e92", // Robinhood Chain mainnet
};
/** CREATE2 salt and init-code hash of the reference registry v2 (deployer 0x4e59b44847b379578588920cA78FbF26c0B4956C). */
export const REGISTRY_SALT = "0x024f49b9244eb29d949eff4fefd5bfba8e33ed73219212770b92237033cd63a7" as const; // keccak256("policy-enforced-accounts registry v2")
export const REGISTRY_INIT_CODE_HASH = "0x50a3c63221dd915e4ab49f82e98469be4826ea4575640bd68d1a6f0bfcde53d1" as const;

const COMMON = [
  "struct PolicyCommitment { bytes32 policyHash; uint64 version; uint64 effectiveAt; string policyURI; string schemaURI; }",
  "function policyOf(address account) view returns (PolicyCommitment)",
  "function pendingPolicyOf(address account) view returns (bool exists, PolicyCommitment)",
  "function mandateOf(address account) view returns (string mandateURI, bytes32 configHash)",
  "function isStopped(address account) view returns (bool)",
  "function supportsInterface(bytes4 interfaceId) view returns (bool)",
  "function activate(address account, bytes32 policyHash, uint64 version, string policyURI, string schemaURI)",
  "function setPending(address account, bytes32 policyHash, uint64 version, uint64 effectiveAt, string policyURI, string schemaURI)",
  "function cancelPending(address account, string reason)",
  "function setStopped(address account, bool stopped, string reason)",
  "function setMandate(address account, string mandateURI, bytes32 configHash)",
  "event PolicyActivated(address indexed account, bytes32 indexed policyHash, uint64 version, uint64 effectiveAt, string policyURI, string schemaURI)",
  "event PolicyPending(address indexed account, bytes32 indexed policyHash, uint64 version, uint64 effectiveAt, string policyURI, string schemaURI)",
  "event PolicyCancelled(address indexed account, bytes32 indexed policyHash, uint64 version, string reason)",
  "event EmergencyStop(address indexed account, string reason)",
  "event EmergencyStopLifted(address indexed account)",
  "event MandateSet(address indexed account, string mandateURI, bytes32 configHash)",
] as const;

/** The registry v2 ABI (reads, writes, events and errors). */
export const REGISTRY_ABI = parseAbi([
  "struct Signers { address policySigner; address publisher; address receiptSigner; uint64 since; uint32 minDelay; uint8 signerType; }",
  ...COMMON,
  "function policySigner(address account) view returns (Signers)",
  "function signersAt(address account, uint64 timestamp) view returns (Signers)",
  "function pendingSignersOf(address account) view returns (bool exists, Signers)",
  "function declare(address policySigner, address publisher, address receiptSigner, uint32 minDelay, uint8 signerType)",
  "function cancelSigners()",
  "function MAX_MIN_DELAY() view returns (uint32)",
  "event SignersDeclared(address indexed account, address policySigner, address publisher, address receiptSigner, uint32 minDelay, uint8 signerType)",
  "event SignersPending(address indexed account, address policySigner, address publisher, address receiptSigner, uint32 minDelay, uint8 signerType, uint64 effectiveAt)",
  "event SignersCancelled(address indexed account, address policySigner, address publisher, address receiptSigner, uint64 effectiveAt)",
  "error NotPublisher()",
  "error NotPublisherOrAccount()",
  "error ZeroSigner()",
  "error BadSignerType()",
  "error DelayTooLong()",
  "error StaleVersion()",
  "error TooSoon()",
  "error NotDue()",
  "error NoPending()",
]);

/** The first draft's registry ABI (v1). */
export const REGISTRY_V1_ABI = parseAbi([
  "struct Signers { address policySigner; address publisher; address receiptSigner; uint64 since; }",
  ...COMMON,
  "function policySigner(address account) view returns (Signers)",
  "function signersAt(address account, uint64 timestamp) view returns (Signers)",
  "function declare(address policySigner, address publisher, address receiptSigner)",
  "event SignersDeclared(address indexed account, address policySigner, address publisher, address receiptSigner)",
]);

/** How the policy signer is wired into the account (`signerType`). */
export const SIGNER_TYPES = { 1: "co-signer in the signature path", 2: "validator module", 3: "guard or hook", 4: "other" } as const;
