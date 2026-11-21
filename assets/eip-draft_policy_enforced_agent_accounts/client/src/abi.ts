import { parseAbi } from "viem";

/** ERC-165 interface id of IPolicyEnforcedAccount (XOR of its six read selectors). */
export const INTERFACE_ID = "0xcc16d336" as const;

/** Reference registry deployments (same address on every chain, via the deterministic deployer). */
export const REGISTRY_ADDRESSES: Record<number, `0x${string}`> = {
  4663: "0x20D6B38B47F7cb765A2318a1f318ed54a6f87e92", // Robinhood Chain mainnet
};
/** CREATE2 salt and init-code hash of the reference registry (deployer 0x4e59b44847b379578588920cA78FbF26c0B4956C). */
export const REGISTRY_SALT = "0xa00ed4cc286daa7197b2f598cc468157416809b8ad9da128e1ba2e65328267b0" as const; // keccak256("policy-enforced-accounts registry v1")
export const REGISTRY_INIT_CODE_HASH = "0xc98be6f0d47025b813e5f7c35ed4f26edaaa102d2d65f13019e217412dc2d946" as const;

export const REGISTRY_ABI = parseAbi([
  "struct Signers { address policySigner; address publisher; address receiptSigner; uint64 since; }",
  "struct PolicyCommitment { bytes32 policyHash; uint64 version; uint64 effectiveAt; string policyURI; string schemaURI; }",
  "function policySigner(address account) view returns (Signers)",
  "function signersAt(address account, uint64 timestamp) view returns (Signers)",
  "function policyOf(address account) view returns (PolicyCommitment)",
  "function pendingPolicyOf(address account) view returns (bool exists, PolicyCommitment)",
  "function mandateOf(address account) view returns (string mandateURI, bytes32 configHash)",
  "function isStopped(address account) view returns (bool)",
  "function supportsInterface(bytes4 interfaceId) view returns (bool)",
  "function declare(address policySigner, address publisher, address receiptSigner)",
  "function activate(address account, bytes32 policyHash, uint64 version, string policyURI, string schemaURI)",
  "function setPending(address account, bytes32 policyHash, uint64 version, uint64 effectiveAt, string policyURI, string schemaURI)",
  "function cancelPending(address account, string reason)",
  "function setStopped(address account, bool stopped, string reason)",
  "function setMandate(address account, string mandateURI, bytes32 configHash)",
  "event SignersDeclared(address indexed account, address policySigner, address publisher, address receiptSigner)",
  "event PolicyActivated(address indexed account, bytes32 indexed policyHash, uint64 version, uint64 effectiveAt, string policyURI, string schemaURI)",
  "event PolicyPending(address indexed account, bytes32 indexed policyHash, uint64 version, uint64 effectiveAt, string policyURI, string schemaURI)",
  "event PolicyCancelled(address indexed account, bytes32 indexed policyHash, uint64 version, string reason)",
  "event EmergencyStop(address indexed account, string reason)",
  "event EmergencyStopLifted(address indexed account)",
  "event MandateSet(address indexed account, string mandateURI, bytes32 configHash)",
]);
