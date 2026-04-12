---
eip: <TBD>
title: Regulated Agent Mandate
description: A compliance delegation layer for AI agents operating on tokenized regulated assets governed by ERC-7943.
author: Ludovico Rossi <ludovico@brickken.com>, Dario Lo Buglio (@xaler5) <dario@brickken.com>, Thamer Dridi (@thamerdridi) <thamer@brickken.com>
discussions-to: <ETH Magicians URL to be added>
status: Draft
type: Standards Track
category: ERC
created: 2026-04-12
requires: 165, 8004, 7943
---

## Abstract

This standard defines a compliance delegation layer for AI agents identified via [ERC-8004](./eip-8004.md) operating on tokenized regulated assets governed by [ERC-7943](./eip-7943.md). It specifies how a verified principal can delegate scoped, time-bounded, and financially capped authority to an on-chain agent, and how [ERC-7943](./eip-7943.md) token contracts verify mandate validity through their existing `canTransfer` hook before executing regulated transfers.

RAMS is not a replacement for [ERC-8004](./eip-8004.md). It is a compliance layer above it, in the same way [ERC-7943](./eip-7943.md) is a compliance layer above [ERC-20](./eip-20.md), [ERC-721](./eip-721.md), and [ERC-1155](./eip-1155.md)/[ERC-6909](./eip-6909.md).

- **[ERC-8004](./eip-8004.md)**: agent identity, discovery, and trust signals
- **[ERC-7943](./eip-7943.md)**: compliance framework for tokenized regulated assets
- **This ERC (RAMS)**: mandate delegation from a verified principal to a compliant agent

## Motivation

The market for tokenized real-world assets is entering a phase of institutional adoption. Platforms operating under MiCA, VARA, and equivalent regulatory frameworks are beginning to support programmable, agent-driven portfolio management on regulated instruments. AI agents that can autonomously execute securities transactions are no longer theoretical — they are being built now, without a standard that makes their operation legally defensible.

An agent purchasing a tokenized fund unit on behalf of an investor must satisfy three conditions that [ERC-8004](./eip-8004.md) alone cannot enforce:

**(a)** The principal on whose behalf the agent acts must be a verified, KYC-cleared legal identity, not merely an Ethereum address.

**(b)** The mandate granted to the agent must be legally traceable, time-bounded, and financially capped, analogous to a power of attorney in traditional finance.

**(c)** The asset contract must verify mandate validity atomically at the point of transfer, without relying on off-chain coordination.

No existing standard addresses these three conditions jointly. Investor eligibility standards such as [ERC-3643](./eip-3643.md) and compliance frameworks such as [ERC-7943](./eip-7943.md) govern who may hold or transact a regulated token, but neither defines an agent delegation model. [ERC-8004](./eip-8004.md) provides agent identity but no mandate framework. RAMS closes this gap by defining the delegation interface, the compliance provider model, and the integration pattern with [ERC-7943](./eip-7943.md)'s existing `canTransfer` hook.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHOULD", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174. All implementations MUST implement [ERC-165](./eip-165.md).

RAMS defines two interfaces deployed as separate contracts:

| Interface | Role | Deployed by |
|---|---|---|
| `IComplianceProvider` | Verifies principal eligibility (identity + compliance) | Compliance operator or platform |
| `IAgentMandate` | Mandate lifecycle, execution recording, freeze, principal resolution, and views | RAMS registry operator |

RAMS-aware [ERC-7943](./eip-7943.md) token contracts consult the RAMS registry inside their existing `canTransfer` hook. No new interfaces or functions are required on the token side. Agents interact with tokens using the standard [ERC-20](./eip-20.md) `transfer` and `transferFrom` functions.

### `IComplianceProvider`

`IComplianceProvider` is implemented by a third-party compliance operator or platform — for example, a KYC provider or an on-chain identity registry adapter — and deployed independently of the RAMS registry. Its address is supplied by the principal at mandate grant time via the `complianceProvider` field of `IAgentMandate.grantMandate`. A single `IComplianceProvider` instance MAY serve multiple mandates across multiple principals.

The compliance provider answers a single question: is this principal, with this identity proof, eligible for this scope? Identity verification is a subset of compliance checking. A compliance provider that declares a principal eligible has implicitly verified that the underlying identity is valid.

Implementations MUST return structured data sufficient for regulatory audit. A binary oracle is not conformant: reason codes and expiry timestamps are required for any credible compliance trail.

```solidity
interface IComplianceProvider {
    enum ReasonCode {
        COMPLIANT,             // 0
        KYC_EXPIRED,           // 1
        AML_FLAG,              // 2
        NOT_ACCREDITED,        // 3
        NOT_QUALIFIED,         // 4
        JURISDICTION_BLOCKED,  // 5
        IDENTITY_NOT_FOUND,    // 6
        ATTESTATION_REVOKED    // 7
    }

    /// @notice Emitted when a previously eligible principal is revoked.
    event PrincipalRevoked(
        address indexed principal,
        bytes32 indexed scopeHash,
        ReasonCode reason
    );

    /// @notice Returns eligibility of a principal for a given scope.
    /// @param principal The on-chain address of the principal.
    /// @param identityRef An off-chain identity reference (e.g., keccak256 of a DID or attestation ID).
    /// @param scopeHash The keccak256 hash of the off-chain scope document.
    /// @return eligible True if the principal is compliant for this scope.
    /// @return reason Reason code. MUST be COMPLIANT when eligible is true.
    /// @return expiresAt Unix timestamp after which this result MUST be re-checked. 0 means no expiry.
    function checkPrincipal(address principal, bytes32 identityRef, bytes32 scopeHash)
        external view returns (bool eligible, ReasonCode reason, uint48 expiresAt);
}
```

An `IComplianceProvider` implementation MAY delegate identity verification to on-chain identity standards, EAS attestations, or any other identity backend. The interface is agnostic to the source.

### `IAgentMandate`

`IAgentMandate` is implemented by the RAMS registry, a single contract deployed by a registry operator (e.g., a platform or a regulated entity acting as operator). Principals interact with this contract to grant, extend, and revoke mandates. [ERC-7943](./eip-7943.md) token contracts interact with this contract inside their `canTransfer` hook to verify mandate validity and record executions.

Each `agentId` has at most one active mandate at any given time. This constraint is by design: in regulated markets, each agent-principal relationship requires segregated accounts and independent audit trails. An operator serving multiple principals deploys one agent wallet per principal, each with its own `agentId` and mandate. This mirrors the account segregation requirements of MiCA (Article 70), MiFID II (Article 16), and VARA.

Value limits in `MandateScopeParams` are denominated in the base unit of the token at `assetAddress`. If `assetAddress` is `address(0)` (asset-class mandate), limits are denominated in the smallest unit of the currency declared in the off-chain scope document. `uint128` accommodates any practical financial instrument value with 18-decimal precision (up to approximately 3.4 × 10^20 whole tokens). A value of `type(uint128).max` signals "no limit" for both `maxTransactionValue` and `maxCumulativeValue`. Implementations MUST revert if an incoming amount exceeds `type(uint128).max`.

The `EnforcerTier` enum distinguishes platform-initiated from regulator-initiated enforcement. This distinction is legally material: in a regulatory dispute, the audit trail must identify both the enforcer address and the authority tier. Implementations MUST use an access control mechanism (e.g., OpenZeppelin `AccessControl`) that enforces this distinction. Access control for `freezeAgent` and `unfreezeAgent` MUST be enforced by the implementation. Global freeze (`bytes32(0)`) MUST be restricted to `REGULATORY` tier enforcers. Jurisdiction-scoped freeze MAY be executed by either tier. The admin role governing enforcer permissions MUST NOT be the same address as any enforcer.

An approved operator MAY call `revokeMandate` and `extendMandate` on behalf of the principal. An operator MUST NOT call `grantMandate` or `grantMandateWithSig`.

`recordExecution` MUST only be callable by the token at `onChainScope.assetAddress` (asset-specific mandates), or by a contract registered in the RAMS token registry, or by an address with enforcer privileges (asset-class mandates). Arbitrary callers MUST be rejected. `recordExecution` MUST revert if the amount exceeds `maxTransactionValue` (when not set to `type(uint128).max`), or if `cumulativeUsed + amount` exceeds `maxCumulativeValue` (when not set to `type(uint128).max`). `cumulativeUsed` MUST NOT reset on `extendMandate`. A cap reset requires explicit revocation and re-issuance.

`grantMandate` MUST revert if `identityRef` is non-zero and the designated `complianceProvider.checkPrincipal` returns `eligible == false`. `grantMandate` and `grantMandateWithSig` MUST revert if `agentId` already has an active mandate. `extendMandate` MUST revert if `newValidUntil` is less than or equal to the current `validUntil`. `grantMandateWithSig` MUST revert if `deadline < block.timestamp`. Nonces MUST be monotonically increasing per principal and consumed atomically with mandate grant.

`isActive` MUST return true if and only if all of the following hold: (a) the mandate exists; (b) `validFrom <= block.timestamp <= validUntil`; (c) the mandate is not revoked; (d) `isFrozen(agentId, mandate.onChainScope.jurisdictionHash)` is false; (e) `isFrozen(agentId, bytes32(0))` is false; (f) `complianceProvider` is `address(0)` or `complianceProvider.checkPrincipal` returns `eligible == true`; (g) `maxCumulativeValue` is `type(uint128).max` or `cumulativeUsed < maxCumulativeValue`. `isActiveForAmount` MUST return true if and only if `isActive` returns true and additionally: (h) `maxTransactionValue` is `type(uint128).max` or `uint128(amount) <= maxTransactionValue`; (i) `maxCumulativeValue` is `type(uint128).max` or `cumulativeUsed + uint128(amount) <= maxCumulativeValue`.

```solidity
interface IAgentMandate is IERC165 {

    struct MandateScopeParams {
        uint128 maxTransactionValue;
        uint128 maxCumulativeValue;
        address assetAddress;
        bytes32 jurisdictionHash;
    }

    struct Mandate {
        address            principal;
        bytes32            identityRef;
        bytes32            scopeHash;
        address            complianceProvider;
        MandateScopeParams onChainScope;
        uint48             validFrom;
        uint48             validUntil;
        uint128            cumulativeUsed;
        bool               revoked;
    }

    enum EnforcerTier { PLATFORM, REGULATORY }

    /// @notice Emitted when a mandate is granted to an agent.
    event MandateGranted(
        uint256 indexed agentId,
        address indexed principal,
        address indexed complianceProvider,
        bytes32 scopeHash,
        uint48 validFrom,
        uint48 validUntil
    );

    /// @notice Emitted when a mandate is revoked.
    event MandateRevoked(
        uint256 indexed agentId,
        address indexed principal,
        address indexed revokedBy
    );

    /// @notice Emitted when a mandate's validity is extended.
    event MandateExtended(
        uint256 indexed agentId,
        address indexed principal,
        uint48 newValidUntil
    );

    /// @notice Emitted when an operator approval is set or revoked.
    event OperatorSet(
        address indexed principal,
        address indexed operator,
        bool approved
    );

    /// @notice Emitted when an agent executes a transfer recorded by a RAMS-aware token.
    event ExecutionRecorded(
        uint256 indexed agentId,
        address indexed principal,
        uint256 amount,
        uint128 cumulativeUsed
    );

    /// @notice Emitted when an agent is frozen for a jurisdiction or globally.
    /// @dev jurisdictionHash of bytes32(0) indicates a global freeze. Global freeze is REGULATORY tier only.
    event AgentFrozen(
        uint256 indexed agentId,
        bytes32 indexed jurisdictionHash,
        address indexed enforcer,
        EnforcerTier tier
    );

    /// @notice Emitted when a freeze is lifted.
    event AgentUnfrozen(
        uint256 indexed agentId,
        bytes32 indexed jurisdictionHash,
        address indexed enforcer
    );

    /// @notice Grants a mandate from msg.sender to the specified agent.
    /// @param agentId The ERC-8004 agent identifier.
    /// @param identityRef Off-chain identity reference for the principal. MUST be non-zero for regulated asset mandates.
    /// @param scopeHash keccak256 of the off-chain scope document stored on IPFS or equivalent.
    /// @param onChainScope Structured on-chain scope parameters.
    /// @param complianceProvider Address of an IComplianceProvider. May be address(0) to skip compliance checks.
    /// @param validFrom Unix timestamp from which the mandate is active.
    /// @param validUntil Unix timestamp after which the mandate expires.
    function grantMandate(
        uint256 agentId,
        bytes32 identityRef,
        bytes32 scopeHash,
        MandateScopeParams calldata onChainScope,
        address complianceProvider,
        uint48 validFrom,
        uint48 validUntil
    ) external;

    /// @notice Grants a mandate on behalf of a principal via an EIP-712 signature.
    /// @param agentId The ERC-8004 agent identifier.
    /// @param principal The address of the principal granting the mandate.
    /// @param identityRef Off-chain identity reference for the principal.
    /// @param scopeHash keccak256 of the off-chain scope document.
    /// @param onChainScope Structured on-chain scope parameters.
    /// @param complianceProvider Address of an IComplianceProvider. May be address(0).
    /// @param validFrom Unix timestamp from which the mandate is active.
    /// @param validUntil Unix timestamp after which the mandate expires.
    /// @param deadline Unix timestamp after which the signature is invalid.
    /// @param signature EIP-712 signature by the principal.
    function grantMandateWithSig(
        uint256 agentId,
        address principal,
        bytes32 identityRef,
        bytes32 scopeHash,
        MandateScopeParams calldata onChainScope,
        address complianceProvider,
        uint48 validFrom,
        uint48 validUntil,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /// @notice Revokes the active mandate for the given agent and principal.
    /// @dev Callable by the principal or an approved operator.
    /// @param agentId The ERC-8004 agent identifier.
    /// @param principal The address of the principal whose mandate is revoked.
    function revokeMandate(uint256 agentId, address principal) external;

    /// @notice Extends the validity of an existing mandate without resetting cumulativeUsed.
    /// @dev Callable by the principal or an approved operator.
    /// @param agentId The ERC-8004 agent identifier.
    /// @param principal The address of the principal whose mandate is extended.
    /// @param newValidUntil New expiry timestamp. MUST be greater than the current validUntil.
    function extendMandate(uint256 agentId, address principal, uint48 newValidUntil) external;

    /// @notice Freezes an agent for a given jurisdiction, or globally if jurisdictionHash is bytes32(0).
    /// @dev Global freeze is restricted to REGULATORY tier enforcers.
    /// @param agentId The ERC-8004 agent identifier.
    /// @param jurisdictionHash keccak256 of the ISO 3166-1 alpha-2 jurisdiction code, or bytes32(0) for global.
    function freezeAgent(uint256 agentId, bytes32 jurisdictionHash) external;

    /// @notice Lifts a freeze for a given agent and jurisdiction.
    /// @param agentId The ERC-8004 agent identifier.
    /// @param jurisdictionHash The jurisdiction hash of the freeze to lift, or bytes32(0) for global.
    function unfreezeAgent(uint256 agentId, bytes32 jurisdictionHash) external;

    /// @notice Sets or revokes operator approval for msg.sender.
    /// @param operator The address being approved or revoked.
    /// @param approved True to approve, false to revoke.
    function setOperator(address operator, bool approved) external;

    /// @notice Records an agent-initiated execution. Called by RAMS-aware ERC-7943 tokens inside canTransfer.
    /// @param agentId The ERC-8004 agent identifier.
    /// @param principal The principal on whose behalf the transfer is executed.
    /// @param amount The transfer amount in the token's base unit.
    function recordExecution(uint256 agentId, address principal, uint256 amount) external;

    /// @notice Returns the principal address of the sole active mandate for the given agent.
    /// @param agentId The ERC-8004 agent identifier.
    /// @return The principal address.
    function getActivePrincipal(uint256 agentId) external view returns (address);

    /// @notice Returns true if the mandate for the given agent and principal is currently active.
    /// @param agentId The ERC-8004 agent identifier.
    /// @param principal The principal address.
    /// @return True if the mandate is active.
    function isActive(uint256 agentId, address principal) external view returns (bool);

    /// @notice Returns true if the mandate is active and the given amount is within all defined limits.
    /// @param agentId The ERC-8004 agent identifier.
    /// @param principal The principal address.
    /// @param amount The transfer amount to check, in the token's base unit.
    /// @return True if the mandate is active and the amount is within limits.
    function isActiveForAmount(uint256 agentId, address principal, uint256 amount) external view returns (bool);

    /// @notice Returns the full Mandate struct for the given agent and principal.
    /// @param agentId The ERC-8004 agent identifier.
    /// @param principal The principal address.
    /// @return The Mandate struct.
    function getMandate(uint256 agentId, address principal) external view returns (Mandate memory);

    /// @notice Returns true if the operator is approved for the given principal.
    /// @param principal The principal address.
    /// @param operator The operator address.
    /// @return True if approved.
    function isOperator(address principal, address operator) external view returns (bool);

    /// @notice Returns true if the agent is frozen for the given jurisdiction.
    /// @param agentId The ERC-8004 agent identifier.
    /// @param jurisdictionHash The jurisdiction hash, or bytes32(0) to check the global freeze.
    /// @return True if frozen.
    function isFrozen(uint256 agentId, bytes32 jurisdictionHash) external view returns (bool);

    /// @notice Returns the current nonce for the given principal, used in EIP-712 signatures.
    /// @param principal The principal address.
    /// @return The current nonce.
    function nonces(address principal) external view returns (uint256);

    /// @notice Returns the EIP-712 domain separator for this deployment.
    /// @return The domain separator bytes32 value.
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
```

### Integration with [ERC-7943](./eip-7943.md) `canTransfer`

[ERC-7943](./eip-7943.md) token contracts call `canTransfer(from, to, amount)` before every token transfer. RAMS-aware tokens extend this hook to detect agent-initiated transfers and enforce mandate validity. No new interfaces or functions are required on the token side. Agents interact with tokens using the standard [ERC-20](./eip-20.md) `transfer` and `transferFrom` functions.

[ERC-8004](./eip-8004.md) allows an agent owner to register an `agentWallet` address, creating a verifiable mapping from a wallet address to an `agentId`. A RAMS-aware [ERC-7943](./eip-7943.md) token uses `getAgentByWallet(sender)` to detect whether the sender is a registered [ERC-8004](./eip-8004.md) agent. If [ERC-8004](./eip-8004.md) does not expose `getAgentByWallet` natively in its final specification, RAMS implementations MUST maintain a separate `agentWallet => agentId` mapping populated at `grantMandate` time.

When the sender is identified as an agent, the token resolves the principal by calling `ramsRegistry.getActivePrincipal(agentId)` and then executes a dual compliance check: first, the token's own [ERC-7943](./eip-7943.md) compliance on the principal (investor eligibility for this specific asset); second, the RAMS mandate validity (agent authority from this principal for this scope). Both conditions MUST hold for the transfer to proceed. The token's [ERC-7943](./eip-7943.md) compliance module is never bypassed. When an agent initiates a transfer, the token applies its investor eligibility checks to the principal address, not the agent wallet. RAMS adds a second compliance layer but does not replace or override the first. The token issuer retains full sovereignty over who may hold or transact their instrument.

The asset address MUST also be verified: if `onChainScope.assetAddress` is not `address(0)`, it MUST equal `address(this)`. If this check fails, the transfer MUST be rejected.

```solidity
// Pseudocode: canTransfer extension for RAMS-aware ERC-7943 tokens.

function canTransfer(address sender, address receiver, uint256 amount)
    internal returns (bool)
{
    uint256 agentId = erc8004Registry.getAgentByWallet(sender);

    if (agentId != 0) {
        address principal = ramsRegistry.getActivePrincipal(agentId);

        // STEP 1: Token's own ERC-7943 compliance on the principal.
        if (!standardCanTransfer(principal, receiver, amount)) return false;

        // STEP 2: RAMS mandate validity for this amount.
        if (!ramsRegistry.isActiveForAmount(agentId, principal, amount)) return false;

        // STEP 3: Asset scope check.
        Mandate memory m = ramsRegistry.getMandate(agentId, principal);
        if (m.onChainScope.assetAddress != address(0) &&
            m.onChainScope.assetAddress != address(this)) return false;

        // STEP 4: Record execution (updates cumulativeUsed).
        ramsRegistry.recordExecution(agentId, principal, amount);

        // STEP 5 (RECOMMENDED): Emit agent operation event.
        emit AgentOperationDetected(agentId, principal, amount);

        return true;
    }

    return standardCanTransfer(sender, receiver, amount);
}
```

RAMS-aware tokens SHOULD emit the following event for every agent-initiated transfer:

```solidity
event AgentOperationDetected(
    uint256 indexed agentId,
    address indexed principal,
    uint256 amount
);
```

The compliance responsibilities across the three layers are as follows:

| Layer | Responsibility | Standard |
|---|---|---|
| Token compliance | Investor eligibility on this specific asset | [ERC-7943](./eip-7943.md) |
| Mandate compliance | Agent authority from this principal for this scope | This ERC |
| Agent identity | Agent exists and is registered | [ERC-8004](./eip-8004.md) |

### [EIP-712](./eip-721.md) Typed Signature

The `grantMandateWithSig` function uses the following type hash:

```solidity
bytes32 constant GRANT_MANDATE_TYPEHASH = keccak256(
    "GrantMandate(uint256 agentId,address principal,bytes32 identityRef,bytes32 scopeHash,address assetAddress,uint128 maxTransactionValue,uint128 maxCumulativeValue,bytes32 jurisdictionHash,address complianceProvider,uint48 validFrom,uint48 validUntil,uint256 nonce,uint256 deadline)"
);
```

The `DOMAIN_SEPARATOR` MUST include `chainId` per EIP-712, making signatures chain-specific and non-replayable across deployments on different chains.

### Scope Document

The off-chain JSON referenced by `scopeHash` MUST be stored on IPFS or equivalent content-addressed storage. The `notes` field SHOULD describe in human-readable language: (a) the actions delegated, (b) operational limitations not captured by structured fields, and (c) the regulatory context.

Implementations MUST verify `onChainScope` internal consistency at `grantMandate` time. Off-chain tooling and the `grantMandate` caller MUST verify that `onChainScope` values are consistent with the scope document referenced by `scopeHash` before submission. Discrepancies discovered post-grant MUST be resolved via revocation.

```json
{
    "type": "urn:eip:RAMS:scope:v1",
    "actions": ["agent.action.buy", "agent.action.sell", "agent.action.transfer"],
    "assetClasses": ["STO", "DTO"],
    "eip7943TokenAddress": "0x...",
    "maxTransactionValue": "500000",
    "maxCumulativeValue": "2000000",
    "valueCurrency": "USD",
    "jurisdictions": ["EU", "AE-DU", "CH"],
    "complianceProviderRef": "eip155:1:0x...",
    "notes": "Agent is authorized to execute secondary market purchases of tokenized real estate securities on behalf of the principal, up to the stated transaction and cumulative limits, within the EU and Dubai (VARA) jurisdictions. No leveraged or derivative transactions are authorized."
}
```

## Rationale

RAMS is defined as a separate ERC rather than an extension of [ERC-8004](./eip-8004.md) because [ERC-8004](./eip-8004.md) is a discovery and trust-signal standard for general-purpose agent economies whose authors have explicitly scoped enforcement out of the protocol. Regulated asset transactions require compliance specificity that would narrow [ERC-8004](./eip-8004.md)'s addressable use case. RAMS follows the same composability model as [ERC-7943](./eip-7943.md) over [ERC-20](./eip-20.md): a minimal base standard extended by a purpose-built compliance layer.

A single `IComplianceProvider` interface is used rather than separate identity and compliance interfaces because identity verification is a logical subset of compliance checking. A compliance provider that declares a principal eligible has already verified that the underlying identity is valid and unrevoked. Splitting these into separate interfaces forces consumers to make two calls to answer one question, creates inconsistency risk, and doubles the integration surface. A single interface with granular `ReasonCode` values preserves diagnostic specificity without the architectural overhead.

Freeze authority is kept within `IAgentMandate` rather than a separate registry because an enforcer does not exist independently of the mandates it can freeze. Extracting freeze into a separate contract creates an additional deployment, audit surface, and integration point for what is functionally an access control list. The `EnforcerTier` distinction (`PLATFORM` vs `REGULATORY`) is preserved in the events, which is where it matters for audit trails.

One active principal per `agentId` is enforced because in regulated markets every managed account must be segregated. A portfolio manager handling multiple clients operates distinct accounts, each with its own mandate, risk profile, and audit trail. The on-chain equivalent is one agent wallet per principal with its own `agentId` registered via [ERC-8004](./eip-8004.md). This mirrors the account segregation requirements of MiCA (Article 70), MiFID II (Article 16), and VARA. Multiple agent wallets are trivially deployable via `CREATE2`.

Agents use standard [ERC-20](./eip-20.md) functions rather than agent-prefixed variants because requiring `agentTransfer(to, amount, principal)` on the token leads to interface duplication: every token operation an agent can perform (`transfer`, `transferFrom`, `mint`, `burn`, `approve`) would require an `agent*` variant. This bloats the token interface, increases the audit surface, and forces every RAMS-aware token to implement a parallel function set. The principal is resolved from the RAMS registry via `getActivePrincipal(agentId)` inside the token's existing `canTransfer` hook, requiring no new functions on the token and no modifications to [ERC-7943](./eip-7943.md).

`canTransfer` executes a dual compliance check because a RAMS-aware token must first apply its own [ERC-7943](./eip-7943.md) investor eligibility checks to the principal and then verify the RAMS mandate. These are two different questions answered by two different layers: the token issuer defines who may hold or transact their instrument, and RAMS defines who may delegate to an agent and under what constraints. Both conditions must hold, preserving full issuer sovereignty.

Value limits are denominated in token base units rather than fiat because denominating in fiat requires an on-chain FX oracle, introducing price manipulation risk and liveness dependency. Limits in token base units are deterministic and oracle-free. The off-chain scope document may include `valueCurrency` for readability; this field has no enforcement role on-chain.

`cumulativeUsed` does not reset on `extendMandate` because a mandate represents a single delegation agreement. Extending validity does not constitute a new agreement. A cap reset requires explicit revocation and re-issuance, preserving audit trail integrity.

Jurisdiction-scoped freeze is supported because a regulatory action in one jurisdiction must not prevent an agent from operating in others. Global freeze (`bytes32(0)`) is reserved for `REGULATORY` enforcers only, reflecting the exceptional nature of a full regulatory halt.

Operator permissions are explicitly scoped so that delegation of authority remains auditable. An operator can revoke or extend a mandate (defensive actions) but cannot grant new mandates (offensive actions that create new legal obligations). This asymmetry reflects the fiduciary principle that a delegate should be able to limit or terminate authority but not expand it without the principal's direct authorization.

RAMS defines its own `IComplianceProvider` interface that is agnostic to the identity verification backend. An implementation MAY use an [ERC-3643](./eip-3643.md)-compatible registry as the data source for principal eligibility checks, but there is no dependency and no requirement. [ERC-7943](./eip-7943.md) is the compliance enforcement point for the token; [ERC-3643](./eip-3643.md) is one of several possible identity backends.

## Backwards Compatibility

RAMS introduces no changes to any existing standard. [ERC-8004](./eip-8004.md) is used as an identity source via the existing `agentWallet` field and `getAgentByWallet` lookup. No modifications to [ERC-8004](./eip-8004.md) are required or proposed. RAMS consumes only these two surface points; changes to other aspects of [ERC-8004](./eip-8004.md) do not affect RAMS conformance. [ERC-7943](./eip-7943.md) tokens that are not RAMS-aware continue to function normally. Non-agent transfers are unaffected. Agent-initiated transfers on tokens that do not consult the RAMS registry pass or fail based on the token's existing investor eligibility logic, independent of any mandate. No modifications to [ERC-7943](./eip-7943.md) are required. RAMS-aware tokens extend the internal logic of `canTransfer` to detect agents and verify mandates; the external interface of [ERC-7943](./eip-7943.md) is unchanged.

## Security Considerations

`identityRef` is a reference, not proof. The compliance provider MUST verify the referenced identity at `grantMandate` time and MUST return `eligible == false` if the attestation is invalid or revoked. Callers MUST NOT treat `identityRef != bytes32(0)` as proof of eligibility without compliance provider verification. If an [ERC-8004](./eip-8004.md) `agentWallet` address is also a standard investor address, the `canTransfer` agent-detection logic could misidentify it. [ERC-8004](./eip-8004.md) implementations MUST require EIP-712 proof of key control for `agentWallet` registration and SHOULD emit a distinct event when an address is registered as an agent wallet.

`recordExecution` MUST only be callable by the token at `onChainScope.assetAddress`, by a contract registered in the RAMS token registry, or by an address with enforcer privileges. Arbitrary callers MUST be rejected to prevent cumulative value manipulation. Callers MUST use `isActiveForAmount` for pre-transaction checks or rely on `recordExecution`'s revert behavior for atomic enforcement.

A compromised compliance provider can declare non-compliant principals as eligible. Principals SHOULD only use compliance providers with audited, time-locked upgrade mechanisms. Enforcers with `REGULATORY` tier MUST be able to freeze an agent independently of compliance provider state. If a compliance provider contract becomes non-responsive, all mandates referencing that provider become inoperative because `isActive` calls `complianceProvider.checkPrincipal`, which will revert. This constitutes a systemic denial-of-service risk. Principals SHOULD select compliance providers with documented uptime SLAs and audited fallback mechanisms. Implementations MAY define a grace period after which a mandate with an unresponsive provider is auto-revoked rather than permanently blocked, provided the revocation is logged for audit.

A transaction can fail at two distinct compliance layers: the token's [ERC-7943](./eip-7943.md) investor eligibility check on the principal, or the RAMS mandate validity check on the agent. Frontends and autonomous agents SHOULD pre-verify both layers before submitting a transaction, using `canTransfer` for the first layer and `isActiveForAmount` for the second, to enable clear diagnostic reporting.

On-chain contracts cannot read or verify the content of an off-chain IPFS document. Implementations MUST verify `onChainScope` internal consistency at `grantMandate` time. Off-chain tooling MUST verify that on-chain parameters match the scope document before calling `grantMandate`. Discrepancies discovered post-grant MUST be resolved via mandate revocation.

A window exists between a `PrincipalRevoked` event from the compliance provider and enforcement of a freeze on the RAMS registry. High-sensitivity protocols SHOULD use an automated freeze relay that monitors `PrincipalRevoked` events and calls `freezeAgent` immediately. Implementations MUST ensure that global freeze (`bytes32(0)`) is restricted to `REGULATORY` tier. A `PLATFORM` enforcer that can execute global freezes is non-conformant. The admin role governing enforcer privileges MUST NOT be the same address as any enforcer to prevent self-escalation.

Nonces MUST be monotonically increasing per principal and consumed atomically with mandate grant. A nonce MUST NOT be reused after revocation. `grantMandateWithSig` MUST reject signatures with `deadline < block.timestamp`. The `DOMAIN_SEPARATOR` includes `chainId` per EIP-712, making signatures chain-specific. A `grantMandateWithSig` signature created for one chain is not valid on a deployment of the same registry on a different chain. Implementations deploying on multiple chains MUST use distinct `verifyingContract` addresses or rely on the `chainId` binding in the domain separator.

## Reference Implementation

A reference implementation is under development at https://github.com/brickken/eip-rams.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).