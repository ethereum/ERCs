---
eip: XXX
title: Oracle-Permissioned ERC-20 with ZK-Verified ISO 20022 Payment Instructions
status: Draft
type: Standards Track
author: Siyuan Zheng (@andrewcoder666) <zhengsiyuan.zsy@antgroup.com>, Xiaoyu Liu (@elizabethxiaoyu) <jiushi.lxy@antgroup.com>, Wenwei Ma (@madyinglight) <huiwei.mww@antgroup.com>, Jun Meng Tan (@chadxeth) <junmeng.t@antgroup.com>, Yuxiang Fu (@tmac4096) <kunfu.fyx@antgroup.com>, Kecheng Gao (@thanks-v-me-50) <gaokecheng.gkc@antgroup.com>, Alwin Ng Jun Wei (@alwinngjw) <alwin.ng@antgroup.com>, Chenxin Wang (@3235773541) <wcx465603@antgroup.com>, Xiang Gao (@GaoYiRu) <gaoxiang.gao@antgroup.com>, yuanshanhshan (@xunayuan) <yuanshanshan.yss@antgroup.com>, Hao Zou (@BruceZH0915) <situ.zh@antgroup.com>, Yanyi Liang <eason.lyy@antgroup.com>, Yuehua Zhang (@astroyhzcc) <ruoying.zyh@antgroup.com>
created: 2025-05-13
---

Proposed by Ant International: https://www.ant-intl.com/en/

# Simple Summary
Extend ERC-20 so that a token transfer is **valid only when an external "Transfer Oracle" pre-approves it**. Approvals reference an off-chain ISO 20022 payment instruction (pain.001 instruction) that is proven on-chain via a **zero-knowledge proof**. The scheme is issuer-agnostic, proof-system-agnostic, and network-agnostic (L1/L2).

# Abstract
This EIP standardises:

+ `ITransferOracle` – a minimal interface that any ERC-20-compatible contract can consult to decide whether `transfer` / `transferFrom`should succeed.
+ `approveTransfer` flow – whereby an _issuer_ (token owner) deposits a one-time approval in the oracle, accompanied by a zk-proof attesting that the approval matches a canonicalised ISO 20022 payment message.
+ `canTransfer` query – whereby the token contract atomically consumes an approval when the holder initiates the transfer.
+ Generic data structures, events, and hooks that allow alternative permissioning logics (KYC lists, travel-rule attestations, CBDC quotas) to share the same plumbing.

Reference circuits, SDKs, and Solidity templates are provided, but the standard admits **any zk-proof system** and any JSON (or future XML) schema.

# Motivation
Institutional tokenisation requires _both_ ERC-20 fungibility **and** legally enforceable control over who may send value to whom and why.  
Hard-coding rules in every token contract is brittle and non-standard. Centralising rules in a singleton oracle and proving off-chain documentation on-chain gives:

+ **Compliance traceability** – every transfer links to a signed payment  
order recognised by traditional finance systems.
+ **Issuer flexibility** – any institution can swap out its oracle logic  
without breaking ERC-20 compatibility.
+ **Composability** – DeFi protocols can interact with permissioned tokens  
using familiar ERC-20 flows, while downstream permission checks are  
encapsulated in the oracle.

# Specification
The key words “MUST”, “MUST NOT”, “REQUIRED”, “SHALL”, “SHALL NOT”, “SHOULD”, “SHOULD NOT”, “RECOMMENDED”, “MAY”, and “OPTIONAL” in this document are to be interpreted as described in RFC 2119.

### Interfaces
```solidity
/// @notice One-time ZK-backed approval for a single transfer.
struct TransferApproval {
    address  sender;
    address  recipient;
    uint256  minAmt;
    uint256  maxAmt;
    uint256  expiry;      // UNIX seconds; 0 == never
    bytes32  proofId;     // keccak256(root‖senderHash‖recipientHash)
}

/// @title  External oracle consulted by permissioned tokens.
interface ITransferOracle {
    /// @dev   Verifies zk-proof and stores a one-time approval.
    /// @return proofId – unique handle for off-chain reconciliation
    function approveTransfer(
        TransferApproval calldata approval,
        bytes calldata proof,          // ABI-encoded a,b,c|proof
        bytes calldata publicInputs      // circuit-specific
    ) external returns (bytes32 proofId);

    /// @dev   Atomically consumes an approval that covers `amount`.
    ///        MUST revert if no such approval exists.
    function canTransfer(
        address token,
        address issuer,
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bytes32 proofId);
}
```

### ERC-20 Hook
A _Permissioned ERC-20_ **MUST** replace the standard internal  
`_update(address from, address to, uint256 amount)` logic with:

```solidity
bytes32 proofId = ORACLE.canTransfer(address(this), owner(), from, to, amount);
// MUST revert on failure
_super._update(from, to, amount);
emit TransferValidated(proofId);
```

`ORACLE` is an immutable constructor argument. (up to design)

### Events
```solidity
event TransferApproved(
    address indexed issuer,
    address indexed sender,
    address indexed recipient,
    uint256 minAmt,
    uint256 maxAmt,
    uint256  expiry,
    bytes32 proofId
);

event ApprovalConsumed(
    address indexed issuer,
    address indexed sender,
    address indexed recipient,
    uint256 amount,
    bytes32 proofId
);

event TransferValidated(bytes32 indexed proofId);
```

### Canonicalisation of ISO 20022 JSON
+ Apply [RFC 8785: JSON Canonicalization Scheme (JCS)](https://www.rfc-editor.org/rfc/rfc8785).
+ Convert numeric amounts to integers of 10⁻³ (milli-units) to avoid floats.
    - <font style="color:rgba(0, 0, 0, 0.88);">This means that all monetary amounts in the ISO 20022 payment instructions must be converted from decimal numbers (e.g., </font>1.50 USD<font style="color:rgba(0, 0, 0, 0.88);">) into integers representing milli-units (e.g., </font>1500<font style="color:rgba(0, 0, 0, 0.88);">), where:</font>  
<font style="color:rgba(0, 0, 0, 0.88);">1 milli-unit = 0.001 (10⁻³) of the base currency unit.</font>
+ UTF-8 NFC normalisation; strip insignificant whitespace.

### Merkle-and-Proof Requirements (Flex-Slot)
The merkle tree root is used to verify that the public inputs actually come from the original off-chain payment instruction.

| Public Inputs | Purpose | Rationale |
| --- | --- | --- |
| `root` | Merkle root of doc | Data-integrity |
| `sender` | Poseidon(Dbtr) | Privacy-preserving ID |
| `recipient` | Poseidon(Cdtr) | Same as above |
| `minAmt`/`maxAmt` | Value bounds | Anti-front-running |
| `expiry` | Approval TTL | Prevents replay |


*The oracle MAY accept additional public inputs, e.g., currency code, jurisdiction, sanctions list epoch*

### Upgradeability
+ Token and Oracle **MAY** be behind EIP-1967 proxies.
+ Verifier is stateless; safe to swap when a new circuit (PLONK, STARK…) is adopted.

## Rationale
Keeping oracle logic out of the token contract preserves fungibility and lets one oracle serve hundreds of issuers.`TransferApproval`uses _amount ranges_ so issuers can sign a single approval before the final FX quote is known.`canTransfer`returns the`proofId`, enabling downstream analytics and  
regulators to join on-chain transfers with off-chain SWIFT messages.

## Backwards Compatibility
Existing ERC-20 consumers remain unaffected; a failed `transfer` simply reverts. Wallets and exchanges **should** surface the oracle’s revert messages so users know they lack approval.

## Security Considerations
+ **Replay Protection** – approvals are one-time and keyed by `proofId`.
+ **Oracle Risk** – issuers SHOULD deploy dedicated oracles; a compromised oracle only endangers its own tokens.
+ **Trusted Setup** – reference circuits use Groth16; institutions MAY adopt STARKs to remove setup risk.

## Reference Implementation
+ Solidity v0.8.26 contracts & Hardhat tests:  
[chadxeth/eip-permissioned-erc20](https://github.com/chadxeth/eip-permissioned-erc20)
+ Circom 2 circuits & `snarkjs` verifier generator.

# Copyright
Copyright and related rights waived via CC0