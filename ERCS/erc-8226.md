---
eip: 8226
title: Regulated Agent Mandate
description: A compliance delegation layer for AI agents operating on tokenized regulated assets.
author: Ludovico Rossi (@ludovicor-eth) <ludovico@brickken.com>, Dario Lo Buglio (@xaler5) <dario@brickken.com>, Thamer Dridi (@thamerdridi) <thamer@brickken.com>, Nabil El Alami Khalifi (@nabil-brickken) <nabil@brickken.com>
discussions-to: https://ethereum-magicians.org/t/erc-8226-regulated-agent-mandate/28208
status: Draft
type: Standards Track
category: ERC
created: 2026-04-12
requires: 165, 712, 1271
---

## Abstract

This standard defines a compliance delegation layer for AI agents operating on tokenized regulated assets. It specifies how a verified principal can delegate scoped, time-bounded, and financially capped authority to an on-chain agent, and how a regulated token verifies the mandate before an agent-initiated action.

Regulated Agent Mandate Standard, or RAMS, is agnostic to the agent identity system, the token standard, and the token compliance framework. It works with any agent identity system (such as [ERC-8004](./eip-8004.md)), any token standard ([ERC-20](./eip-20.md), [ERC-721](./eip-721.md), [ERC-1155](./eip-1155.md)), and any regulated token standard (such as [ERC-7943](./eip-7943.md) or [ERC-3643](./eip-3643.md)).

## Motivation

The market for tokenized real-world assets is entering a phase of institutional adoption. Platforms operating under regulatory frameworks are starting to support programmable, agent-driven portfolio management on regulated instruments. AI agents that can autonomously execute securities transactions are no longer theoretical; they are being built now, without a standard that makes their operation legally defensible.

An agent purchasing a tokenized fund unit on behalf of an investor must satisfy three conditions that no existing standard addresses jointly:

1. The principal on whose behalf the agent acts must be a verified, Know Your Customer (KYC)-cleared legal identity, not merely an Ethereum address.
1. The mandate granted to the agent must be legally traceable, time-bounded, and financially capped, analogous to a power of attorney in traditional finance.
1. The asset contract must validate the mandate atomically at execution time, without relying on off-chain coordination.

Regulated token standards such as [ERC-7943](./eip-7943.md) and [ERC-3643](./eip-3643.md) govern who may hold or transact a token, but neither defines an agent delegation model. Agent identity standards such as [ERC-8004](./eip-8004.md) provide agent discovery and trust signals but no mandate framework, and general-purpose agent authorization standards do not address regulated assets. RAMS defines the delegation interface, the compliance provider model, and the integration pattern with regulated token contracts.

The compliance responsibilities across the three layers are as follows:

| Layer | Responsibility | Standard |
|---|---|---|
| Token compliance | Investor eligibility on this specific asset | Token compliance framework (e.g., [ERC-7943](./eip-7943.md), [ERC-3643](./eip-3643.md)) |
| Mandate compliance | Agent authority from this principal for this scope | This ERC |
| Agent identity | Agent exists and is registered | Agent registry (e.g., [ERC-8004](./eip-8004.md)) |

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHOULD", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174). All implementations MUST implement [ERC-165](./eip-165.md).

RAMS defines two interfaces. Implementations SHOULD deploy them as separate contracts so that an independent compliance operator and the registry operator can be governed separately; a single operator MAY combine them.

| Interface | Role | Deployed by |
|---|---|---|
| `IComplianceProvider` | Verifies principal eligibility (identity + compliance) | Compliance operator or platform |
| `IAgentMandate` | Mandate lifecycle, execution recording, freeze, and views | RAMS registry operator |

RAMS-aware regulated token contracts consult the RAMS registry inside their existing pre-transfer compliance hook.

### `IComplianceProvider`

`IComplianceProvider` is implemented by a third-party compliance operator or platform (for example, a KYC provider or an on-chain identity registry adapter), deployed independently of the RAMS registry. Its address is supplied by the principal at mandate grant time via the `complianceProvider` field of `IAgentMandate.grantMandate`. A single `IComplianceProvider` instance MAY serve multiple mandates across multiple principals.

The compliance provider manages principal eligibility: granting, revoking, and checking whether a principal is eligible.

When used, `checkPrincipal` MUST return structured data sufficient for regulatory audit: a binary oracle is non-conformant, since reason codes and expiry timestamps are required for any credible compliance trail. It MUST verify that `identityRef` resolves to a valid, unrevoked attestation and return `eligible == false` if it does not.

The provider is mandatory: `grantMandate` MUST revert if `complianceProvider` is `address(0)`.

```solidity
interface IComplianceProvider is IERC165 {
    enum ReasonCode {
        COMPLIANT,             // 0
        KYC_EXPIRED,           // 1
        AML_FLAG,              // 2
        NOT_ACCREDITED,        // 3
        NOT_QUALIFIED,         // 4
        JURISDICTION_BLOCKED,  // 5
        IDENTITY_NOT_FOUND,    // 6
        ATTESTATION_REVOKED,   // 7
        OTHER                  // 8
    }

    /// @notice Emitted when a principal is granted eligibility.
    event PrincipalGranted(
        address indexed principal,
        bytes32 indexed identityRef
    );

    /// @notice Emitted when a previously eligible principal is revoked.
    event PrincipalRevoked(
        address indexed principal,
        bytes32 indexed identityRef,
        ReasonCode reason
    );

    /// @notice Grants eligibility to a principal.
    /// @param principal The on-chain address of the principal.
    /// @param identityRef An off-chain identity reference (e.g., keccak256 of a Decentralized Identifier (DID) or attestation ID).
    /// @param expiresAt Unix timestamp after which eligibility MUST be re-checked. 0 means no expiry.
    function grantPrincipal(address principal, bytes32 identityRef, uint48 expiresAt) external;

    /// @notice Revokes a principal's eligibility.
    /// @param principal The on-chain address of the principal.
    /// @param reason The reason for revocation.
    function revokePrincipal(address principal, ReasonCode reason) external;

    /// @notice Returns eligibility of a principal.
    /// @param principal The on-chain address of the principal.
    /// @param identityRef An off-chain identity reference (e.g., keccak256 of a Decentralized Identifier (DID) or attestation ID).
    /// @return eligible True if the principal is compliant.
    /// @return reason Reason code. MUST be COMPLIANT when eligible is true.
    /// @return expiresAt Unix timestamp after which this result MUST be re-checked. 0 means no expiry.
    function checkPrincipal(address principal, bytes32 identityRef)
        external view returns (bool eligible, ReasonCode reason, uint48 expiresAt);
}
```

An `IComplianceProvider` implementation MAY delegate identity verification to on-chain identity standards, Ethereum Attestation Service (EAS) attestations, or any other identity backend. The interface is agnostic to the source.

### `IAgentMandate`

`IAgentMandate` is implemented by the RAMS registry, a single contract deployed by a registry operator (e.g., a platform or a regulated entity acting as operator). Principals interact with this contract to grant, extend, and revoke mandates. Any contract in the agent's execution path calls `canExecute` to verify the mandate and `recordExecution` to record use.

Mandate storage is keyed by `(agent, principal)`. Each `(agent, principal)` pair has at most one active mandate at any given time.

A mandate authorizes the agent to act on a set of actions on a specific asset. Actions are identified by `bytes32` labels.

A value of `type(uint256).max` in `maxTransactionValue` or `maxCumulativeValue` signals "no limit."

Caps are denominated in the asset's transfer quantity: the token amount for [ERC-20](./eip-20.md) and [ERC-1155](./eip-1155.md), and a token count (1 per transfer) for [ERC-721](./eip-721.md). RAMS caps the quantity transferred, not specific token identifiers.

Freezing MUST be restricted to authorized enforcer roles defined by the implementation's access control, and the enforcer address MUST be recorded in the `AgentFrozen` event. The admin role governing enforcer permissions MUST NOT be the same address as any enforcer.

An approved operator MAY call `revokeMandate` and `extendMandate` on behalf of the principal.

`recordExecution` MUST only be callable by an authorized recorder: the mandate's `asset`, the principal's account, or an address granted the recorder role by the implementation's access control. Arbitrary callers MUST be rejected. `recordExecution` MUST apply the same existence, validity-window, revocation, action, and freeze checks as `canExecute` and revert if any fail. `recordExecution` increments `cumulativeUsed` by `amount` and MUST revert if the amount exceeds `maxTransactionValue` or if `cumulativeUsed + amount` exceeds `maxCumulativeValue` (when either is not set to `type(uint256).max`). `cumulativeUsed` MUST NOT reset on `extendMandate`. A cap reset requires explicit revocation and re-issuance.

#### Signed lifecycle operations

`grantMandate`, `revokeMandate`, `extendMandate`, and `setOperator` MAY be called directly by the principal (`msg.sender == principal`) or by any submitter providing a principal signature over an [EIP-712](./eip-712.md) typed message. Implementations MUST verify principal signatures using [EIP-1271](./eip-1271.md)-compatible verification. The reference path is `SignatureChecker.isValidSignatureNow(principal, digest, signature)`, which handles EOAs, contract wallets (multisigs, DAOs), and [EIP-7702](./eip-7702.md)-delegated accounts.

The typed-data domain separator follows [EIP-712](./eip-712.md) with `name = "RAMS"`, `version = "1"`, current `chainId`, and `verifyingContract` set to the RAMS registry address. Implementations MUST track a nonce per principal (`nonces[principal]`) and include it in every signed operation. Implementations MUST revert if `block.timestamp > deadline` or if the recovered signer does not match `principal`.

The normative [EIP-712](./eip-712.md) typehashes are:

```solidity
bytes32 constant GRANT_MANDATE_TYPEHASH = keccak256(
    "GrantMandate(address agent,uint48 validFrom,uint48 validUntil,"
    "address principal,address complianceProvider,bytes32 identityRef,"
    "address asset,uint256 maxTransactionValue,uint256 maxCumulativeValue,"
    "bytes32 metadata,bytes32[] actions,uint256 nonce,uint256 deadline)"
);

bytes32 constant REVOKE_MANDATE_TYPEHASH = keccak256(
    "RevokeMandate(address agent,address principal,uint256 nonce,uint256 deadline)"
);

bytes32 constant EXTEND_MANDATE_TYPEHASH = keccak256(
    "ExtendMandate(address agent,address principal,uint48 newValidUntil,uint256 nonce,uint256 deadline)"
);

bytes32 constant SET_OPERATOR_TYPEHASH = keccak256(
    "SetOperator(address principal,address operator,bool approved,uint256 nonce,uint256 deadline)"
);
```

`grantMandate` MUST revert if the `(agent, principal)` pair already has an active mandate. `grantMandate` MUST revert if `complianceProvider` is `address(0)`, and MUST revert if `complianceProvider.checkPrincipal` returns `eligible == false`. `extendMandate` MUST revert if `newValidUntil` is less than or equal to the current `validUntil`.

At `grantMandate` the implementation writes the signed `actions[]` array into the `actionEnabled` mapping keyed by `(agent, principal)`. It MUST first clear any actions enabled by a prior mandate for the pair, and the new mandate MUST start with `revoked` set to false and `cumulativeUsed` set to 0. Subsequent on-chain enforcement reads from this mapping in O(1).

#### Authorization check

`canExecute` MUST behave as follows (Solidity pseudocode, illustrative):

```solidity
function canExecute(
    address agent,
    address principal,
    address asset,
    bytes32 action,
    uint256 amount
) public view returns (bool) {
    Mandate storage m = mandates[agent][principal];

    if (m.principal == address(0))                                              return false; // mandate does not exist
    if (asset != m.asset)                                                       return false; // wrong asset
    if (block.timestamp < m.validFrom || block.timestamp > m.validUntil)        return false; // outside validity window
    if (m.revoked)                                                              return false;
    if (!actionEnabled[agent][principal][action])                               return false;
    if (isFrozen(agent))                                                        return false;

    if (m.maxTransactionValue != type(uint256).max
        && amount > m.maxTransactionValue)                                      return false;

    if (m.maxCumulativeValue != type(uint256).max
        && m.cumulativeUsed + amount > m.maxCumulativeValue)                    return false;

    return true;
}
```

#### Interface

```solidity
interface IAgentMandate is IERC165 {

    struct Mandate {
        address agent;
        uint48  validFrom;
        uint48  validUntil;
        address principal;
        bool    revoked;
        address complianceProvider;
        bytes32 identityRef;
        address asset;
        uint256 maxTransactionValue;
        uint256 maxCumulativeValue;
        uint256 cumulativeUsed;
        bytes32 metadata;
    }

    /// @notice Emitted when a mandate is granted.
    event MandateGranted(
        address indexed agent,
        address indexed principal,
        address complianceProvider,
        address asset,
        uint48 validFrom,
        uint48 validUntil,
        bytes32 metadata
    );

    /// @notice Emitted when an action is enabled on a mandate at grant time.
    event ActionEnabled(address indexed agent, address indexed principal, bytes32 indexed action);

    /// @notice Emitted when a mandate is revoked.
    event MandateRevoked(
        address indexed agent,
        address indexed principal,
        address revokedBy
    );

    /// @notice Emitted when a mandate's validity is extended.
    event MandateExtended(
        address indexed agent,
        address indexed principal,
        uint48 newValidUntil
    );

    /// @notice Emitted when an operator approval is set or revoked.
    event OperatorSet(
        address indexed principal,
        address indexed operator,
        bool approved
    );

    /// @notice Emitted when an agent executes an action recorded by a RAMS-aware token.
    event ExecutionRecorded(
        address indexed agent,
        address indexed principal,
        bytes32 indexed action,
        uint256 amount,
        uint256 cumulativeUsed
    );

    /// @notice Emitted when an agent is frozen. Freezing is restricted to authorized enforcer roles.
    event AgentFrozen(
        address indexed agent,
        address indexed enforcer
    );

    /// @notice Emitted when a freeze is lifted.
    event AgentUnfrozen(
        address indexed agent,
        address indexed enforcer
    );

    /// @notice Parameters for grantMandate, bundled into a struct to avoid stack-too-deep.
    /// @param agent The address of the agent receiving the mandate.
    /// @param validFrom Unix timestamp from which the mandate is active.
    /// @param validUntil Unix timestamp after which the mandate expires.
    /// @param principal The address of the principal granting the mandate.
    /// @param complianceProvider Address of an IComplianceProvider. MUST be a non-zero address.
    /// @param identityRef Off-chain identity reference for the principal.
    /// @param asset Specific asset address.
    /// @param maxTransactionValue Per-transaction value cap.
    /// @param maxCumulativeValue Cumulative value cap over the mandate's lifetime.
    /// @param metadata Optional 32-byte pointer to off-chain metadata (e.g., legal-text content hash).
    /// @param actions Array of action labels.
    /// @param deadline Signature expiry timestamp (replay protection).
    struct GrantMandateParams {
        address   agent;
        uint48    validFrom;
        uint48    validUntil;
        address   principal;
        address   complianceProvider;
        bytes32   identityRef;
        address   asset;
        uint256   maxTransactionValue;
        uint256   maxCumulativeValue;
        bytes32   metadata;
        bytes32[] actions;
        uint256   deadline;
    }

    /// @notice Grants a mandate from a principal to an agent.
    /// @dev If `signature` is empty, msg.sender MUST equal params.principal. Otherwise the signature is verified
    ///      via SignatureChecker against the GrantMandate [EIP-712](./eip-712.md) digest.
    /// @param params The mandate parameters.
    /// @param signature Principal signature ([EIP-712](./eip-712.md), [EIP-1271](./eip-1271.md) supported).
    function grantMandate(GrantMandateParams calldata params, bytes calldata signature) external;

    /// @notice Revokes the active mandate for the given agent and principal.
    /// @dev Callable by the principal directly or by anyone with a valid principal signature. An approved operator MAY also call this.
    /// @param agent The agent address whose mandate is revoked.
    /// @param principal The principal address whose mandate is revoked.
    /// @param deadline Signature expiry timestamp.
    /// @param signature Principal signature ([EIP-712](./eip-712.md), [EIP-1271](./eip-1271.md) supported).
    function revokeMandate(
        address agent,
        address principal,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /// @notice Extends the validity of an existing mandate without resetting cumulativeUsed.
    /// @dev Callable by the principal directly or by anyone with a valid principal signature. An approved operator MAY also call this.
    /// @param agent The agent address.
    /// @param principal The principal address.
    /// @param newValidUntil New expiry timestamp. MUST be greater than the current validUntil.
    /// @param deadline Signature expiry timestamp.
    /// @param signature Principal signature ([EIP-712](./eip-712.md), [EIP-1271](./eip-1271.md) supported).
    function extendMandate(
        address agent,
        address principal,
        uint48 newValidUntil,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /// @notice Freezes an agent, halting all of its mandates. Restricted to authorized enforcer roles.
    /// @param agent The agent address to freeze.
    function freezeAgent(address agent) external;

    /// @notice Lifts a freeze on an agent.
    /// @param agent The agent address to unfreeze.
    function unfreezeAgent(address agent) external;

    /// @notice Sets or revokes operator approval for the principal.
    /// @dev Callable by the principal directly or by anyone with a valid principal signature.
    /// @param principal The principal granting/revoking operator status.
    /// @param operator The operator address being approved or revoked.
    /// @param approved True to approve, false to revoke.
    /// @param deadline Signature expiry timestamp.
    /// @param signature Principal signature ([EIP-712](./eip-712.md), [EIP-1271](./eip-1271.md) supported).
    function setOperator(
        address principal,
        address operator,
        bool approved,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /// @notice Records an agent-initiated execution. Called by RAMS-aware regulated tokens.
    /// @param agent The agent address.
    /// @param principal The principal on whose behalf the action is executed.
    /// @param action The action label being executed.
    /// @param amount The amount in the asset's base unit.
    function recordExecution(
        address agent,
        address principal,
        bytes32 action,
        uint256 amount
    ) external;

    /// @notice Returns true if the agent can execute the action on the asset for the principal at the given amount.
    /// @dev Bundles asset, existence, validity, freeze, action, and cap checks into one call.
    /// @param agent The agent address.
    /// @param principal The principal address.
    /// @param asset The asset the action targets; MUST equal the mandate's `asset`.
    /// @param action The action label being checked.
    /// @param amount The amount to check, in the asset's base unit.
    /// @return True if the agent can execute the action at this amount.
    function canExecute(
        address agent,
        address principal,
        address asset,
        bytes32 action,
        uint256 amount
    ) external view returns (bool);

    /// @notice Returns true if the action is enabled on the mandate.
    /// @param agent The agent address.
    /// @param principal The principal address.
    /// @param action The action label.
    /// @return True if the action is enabled.
    function isActionEnabled(address agent, address principal, bytes32 action) external view returns (bool);

    /// @notice Returns the full Mandate struct for the given agent and principal.
    /// @param agent The agent address.
    /// @param principal The principal address.
    /// @return The Mandate struct.
    function getMandate(address agent, address principal) external view returns (Mandate memory);

    /// @notice Returns true if the operator is approved for the given principal.
    /// @param principal The principal address.
    /// @param operator The operator address.
    /// @return True if approved.
    function isOperator(address principal, address operator) external view returns (bool);

    /// @notice Returns true if the agent is frozen.
    /// @param agent The agent address.
    /// @return True if frozen.
    function isFrozen(address agent) external view returns (bool);

    /// @notice Returns the current nonce for a principal (used in signed operations).
    /// @param principal The principal address.
    /// @return The current nonce value.
    function nonces(address principal) external view returns (uint256);

    /// @notice Returns the [EIP-712](./eip-712.md) domain separator.
    /// @return The domain separator hash.
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
```

### Integration with Regulated Token Contracts

A regulated token integrates RAMS inside its existing pre-transfer hook (e.g., `canTransfer` in [ERC-7943](./eip-7943.md), transfer restrictions in [ERC-3643](./eip-3643.md)). The principal is the holder (`from`) and the agent is the caller (`msg.sender`); a transfer with `msg.sender != from` is agent-initiated and MUST satisfy the `(msg.sender, from)` mandate. The example below uses [ERC-20](./eip-20.md); the same pattern applies to [ERC-721](./eip-721.md) and [ERC-1155](./eip-1155.md).

RAMS mandate validity does NOT replace token-level allowance or operator approval. For an agent-initiated transfer to succeed, both the token-level authorization ([ERC-20](./eip-20.md) allowance, or [ERC-721](./eip-721.md)/[ERC-1155](./eip-1155.md) operator approval) and the RAMS mandate MUST pass. RAMS is an additional compliance layer, not a replacement for token ownership semantics.

The `action` label is an opaque `bytes32` chosen by the integrating token. The token MAY use a function selector (as below), a keccak256 of a namespaced string, or any other 32-byte identifier consistent with the labels the principal authorized in the mandate.

```solidity
// Pseudocode: canTransfer for RAMS-aware ERC-7943 tokens.

function canTransfer(address from, address to, uint256 amount)
    public view returns (bool)
{
    require(canSend(from), ERC7943CannotTransfer(from, to, amount));
    require(canReceive(to), ERC7943CannotTransfer(from, to, amount));

    if (msg.sender == from) return true;
    if (ramsRegistry.getMandate(msg.sender, from).principal == address(0)) return true; // plain allowance, no mandate

    bytes32 action = bytes32(IERC20.transferFrom.selector);
    return ramsRegistry.canExecute(msg.sender, from, address(this), action, amount);
}
```

```solidity
// Pseudocode: _update hook recording RAMS execution.

function _update(address from, address to, uint256 amount) internal override {
    require(canTransfer(from, to, amount), ERC7943CannotTransfer(from, to, amount));

    if (from != address(0) && msg.sender != from
        && ramsRegistry.getMandate(msg.sender, from).principal != address(0)) {
        bytes32 action = bytes32(IERC20.transferFrom.selector);
        ramsRegistry.recordExecution(msg.sender, from, action, amount);
    }

    super._update(from, to, amount);
}
```

This example is permissive: a transfer with no `(msg.sender, from)` mandate falls through to normal allowance rules. A token MAY instead require a mandate for every non-holder transfer.

The same `canExecute` and `recordExecution` calls apply from any of the three enforcement venues:

1. **Token hook**: a RAMS-aware token gates transfers in its compliance hook (above).
2. **[EIP-7702](./eip-7702.md) account**: the principal delegates their account to an `IAgentExecutor`; agent actions originate as the principal.
3. **Executor**: the principal approves an `IAgentExecutor` contract; the agent acts only through it.

All read the same mandate. The venue is the integrator's choice and is out of scope of the normative interface.

## Rationale

RAMS is a separate ERC rather than an extension of any agent identity or token compliance standard because mandate delegation is a distinct concern. Coupling it to a specific standard would limit its use across the fragmented regulated token ecosystem.

Mandate storage is keyed by `(agent, principal)` addresses, similar to [ERC-20](./eip-20.md) `allowance`.

A single `IComplianceProvider` interface is used rather than separate identity and compliance interfaces because identity verification is a logical subset of compliance checking. A compliance provider that declares a principal eligible has already verified that the underlying identity is valid and unrevoked.

Mandate scope is encoded fully on-chain and bound by the principal's [EIP-712](./eip-712.md) signature, eliminating drift between on-chain state and any off-chain document. Actions are signed as a `bytes32[]` array and written into a mapping at grant time for O(1) enforcement. The `metadata` field is non-normative and does not participate in enforcement.

All signed lifecycle operations include a nonce and deadline; [EIP-1271](./eip-1271.md) verification allows smart-wallet principals (multisigs, DAOs).

`canExecute` bundles every runtime check into one call so the integrator cannot accidentally skip one.

Freeze authority is kept within `IAgentMandate` rather than a separate registry because an enforcer does not exist independently of the mandates it can freeze. Enforcer authority is governed by the implementation's access-control roles, not by a hardcoded tier.

Enforcement is venue-agnostic: RAMS standardizes the mandate, not how it is enforced. Any contract in the agent's path applies it by calling `canExecute`, so the same mandate is honored whether the gate is a token hook, an account, or an executor.

Agents use standard token functions ([ERC-20](./eip-20.md), [ERC-721](./eip-721.md), [ERC-1155](./eip-1155.md)) rather than agent-prefixed variants because that would require interface duplication. The token's existing compliance hook validates mandates via `canExecute`, requiring no new functions on the token.

Value limits are denominated in token base units rather than fiat to stay deterministic and oracle-free.

`cumulativeUsed` does not reset on `extendMandate` because a mandate represents a single delegation agreement; a cap reset requires explicit revocation and re-issuance.

Freezing is reserved for authorized enforcer roles, reflecting the exceptional nature of a halt.

Operator permissions are explicitly scoped so that delegation remains auditable: an operator can revoke or extend a mandate but cannot grant new ones.

## Backwards Compatibility

RAMS introduces no changes to any existing standard.

## Reference Implementation

A reference implementation and test suite are [available](../assets/eip-8226/README.md): the `IAgentMandate` registry, an `IComplianceProvider`, an `IAgentExecutor`, and an [ERC-7943](./eip-7943.md) asset integration.

`IAgentExecutor` is an OPTIONAL, non-normative companion interface for the account-side enforcement venues (an [EIP-7702](./eip-7702.md) delegate or a standalone executor). The forwarding logic is never part of `IAgentMandate`.

```solidity
interface IAgentExecutor {
    /// @dev msg.sender is the agent; the implementer is bound to a principal.
    ///      action = bytes4(data), amount read from data, so gated values match the real call.
    ///      Calls canExecute and reverts if false, records the execution, then forwards the call.
    function execute(address target, bytes calldata data) external returns (bytes memory);
}
```

The executor maintains a mapping from each supported action selector to the position of its amount argument; on `execute`, it reads the gated amount from that position in the forwarded calldata, so the gated value is always the value that executes. Actions with no value argument gate at amount 0. RAMS gates a registered set of action signatures, not arbitrary calldata.

## Security Considerations

`identityRef` is a reference, not proof of eligibility. Grant-time eligibility comes from `checkPrincipal`; runtime eligibility always comes from the token's own check. If an agent wallet is also a standard investor address, the agent-detection logic could misidentify it; agent identity registries should require proof of key control and emit a distinct event when registering an agent wallet.

If `recordExecution` were callable by arbitrary addresses, an attacker could advance `cumulativeUsed` to exhaust the cap and deny service to the legitimate agent. The caller restriction specified in the Specification closes this attack surface. Callers can use `canExecute` for pre-transaction checks or rely on `recordExecution`'s revert behavior for atomic enforcement.

A compromised compliance provider can approve an ineligible principal at grant time. This is bounded: compliance is checked at grant, not on the execution path, so a provider going offline cannot brick active mandates; the token's own eligibility check (`canSend`) still runs on every transfer; and an enforcer can freeze the agent independently of provider state. Principals should select compliance providers with audited, time-locked upgrade mechanisms.

A transaction can fail at two distinct compliance layers: the token's investor eligibility check on the principal, or the RAMS mandate validity check on the agent. Frontends and autonomous agents should pre-verify both layers before submitting a transaction to enable clear diagnostic reporting.

A window exists between a `PrincipalRevoked` event from the compliance provider and enforcement of a freeze on the RAMS registry. High-sensitivity protocols should use an automated freeze relay that monitors `PrincipalRevoked` events and calls `freezeAgent` immediately. The admin role MUST NOT be the same address as any enforcer, preventing self-escalation.

An `IAgentExecutor` reads the gated amount from a registered per-action position. That registry is a trusted surface: a wrong position silently mis-gates caps, so the role that maintains it needs the same care as the enforcer role.

The `metadata` field is non-normative: implementations and integrators MUST NOT rely on it for enforcement decisions, since its content (e.g., off-chain legal text) is not verifiable on-chain. It is provided as an opaque pointer for human-readable context and audit purposes only.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).