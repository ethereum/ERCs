---
eip: 8473
title: uRWA Policy
description: An external policy that ERC-7943 tokens consult for every movement and for their compliance checks.
author: Filipe Venancio (@fepvenancio)
discussions-to: https://ethereum-magicians.org/t/erc-8473-urwa-policy-interface/30048
status: Draft
type: Standards Track
category: ERC
created: 2026-10-22
requires: 165, 7943
---

## Abstract

This ERC defines how an [ERC-7943](./eip-7943.md) token delegates its compliance decisions to a separate policy contract.

For every movement of its balances, the token builds a `TransferContext`. The context is labelled with the authority under which the movement happens, determined from on-chain facts. The token asks the policy for a `bytes32` decision before any balance changes. One fixed non-zero value permits; every other value, zero included, rejects.

The same policy answers the token's ERC-7943 `canSend`, `canReceive` and `canTransfer` checks. The token evaluates `canTransfer` with the same checks as the movements that check predicts. A policy that keeps state observes completed movements through an authenticated callback. The token also calls the policy on every installation, so that it can initialise that state.

## Motivation

ERC-7943 standardises what a permissioned token exposes:
- account eligibility (`canSend`, `canReceive`);
- a transfer pre-flight (`canTransfer`);
- frozen balances;
- `forcedTransfer`.

It deliberately leaves open how the token reaches its decisions.

Those decisions, about identity, jurisdiction, lock-ups, holder caps and settlement hours, change more often than a token's accounting. They are written and audited by different teams, and one set of rules often serves many instruments. Tokens therefore keep them in a separate contract, and each implementation invents its own interface to that contract. The result:

- A compliance provider integrates with every token family separately.
- A token cannot replace its compliance logic with another provider's without a custom adapter.
- Auditors must work out, for each implementation, which operations reach the compliance contract and with what information.
- Integrators cannot know whether a token's pre-flight answer is computed the same way as the transfer it predicts.

[ERC-3643](./eip-3643.md) defines such a boundary for its own token: a `canTransfer(from, to, amount)` that returns a `bool`, plus `transferred`, `created` and `destroyed` callbacks. Its check is told neither who initiated a movement nor under what authority, and it cannot say why it rejects. ERC-7943 also notes that ERC-3643's `canTransfer` does not perform the send and receive checks ERC-7943 requires.

This ERC standardises the boundary behind ERC-7943. Tokens and policies written independently then interoperate, and when both meet this ERC, the guarantees ERC-7943 asks of a token's checks hold.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

### Terms

- **Token**: a contract that implements one of the ERC-7943 interfaces and `IERC8473`.
- **Policy**: a contract that implements `IERC8473Policy`.
- **Movement**: one change recorded by the token's base-standard transfer events: each event, and each item of a batch event, is one movement. ERC-7943 calls the operation that causes a movement a transfer. Transfers, mints, burns and forced transfers are movements of any amount, including zero. One operation may cause several movements, for example a batch, or a forced transfer implemented as a burn and a mint. An event with both `from` and `to` equal to `address(0)`, which [ERC-1155](./eip-1155.md) allows to announce a token type, is not a movement.
- **Holder** of a movement: the account whose tokens move (`from`). When `from` is an escrow that the token itself operates, the holder is the account the token records as entitled to the escrowed tokens, such as the controller of an [ERC-7540](./eip-7540.md) request. A mint has a holder only when it settles a claim the token records: the holder is then the account the token records as entitled to the claim, such as the controller of an ERC-7540 request. Elsewhere, "holder caps" and "holder counts" use the word in its ordinary sense: any account with a balance.
- **Directed by the holder**: the movement's accounts and amount follow from an authorisation of the holder's that the token can check on-chain. That authorisation may be a call to the token, an allowance or operator approval, a signature the token verifies, or a request the token records. A recorded request directs every destination that it, or the token's documented request lifecycle (fulfilment, claim, rejection, cancellation), names, whoever made the request.
- **The token's own checks**: the permissioned conditions the token applies to a movement outside its policy: the frozen amount that ERC-7943 defines, a pause if the token has one, and any account-level conditions the token adds to `canSend` or `canReceive`, such as a frozen wallet. They exclude the base standard's own validations, such as ownership, allowances and approvals, and access control on the functions that cause movements.
- **Check**: `checkSend`, `checkReceive` or `checkTransfer`. A check **permits** when it returns `TRANSFER_OK` and **rejects** when it returns anything else.
- **Installation**: each time the token sets the policy it consults, including the first time, a policy it consulted before, and the policy it already consults.

### Interfaces

```solidity
/// @dev The only value a check returns to permit. Every other value, including zero, rejects.
bytes32 constant TRANSFER_OK = keccak256('TRANSFER_OK');

/**
 * @title IERC8473Policy
 * @notice Decides whether an account may send or receive an ERC-7943 token, and whether a movement of it may happen
 */
interface IERC8473Policy is IERC165 {
  /*///////////////////////////////////////////////////////////////
                            ENUMS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice The authority under which a movement happens. The set is closed
   * @param TRANSFER Any other movement between two accounts, typically one the holder directed
   * @param EXECUTED A signed holder instruction the token verified, executed by an account the token authorises
   * @param FORCED The token's enforcement authority, which does not depend on the holder directing the movement
   * @param MINT Issuance under the token's ordinary issuance rules
   * @param BURN Destruction the holder directed
   */
  enum TransferKind {
    TRANSFER,
    EXECUTED,
    FORCED,
    MINT,
    BURN
  }

  /*///////////////////////////////////////////////////////////////
                            STRUCTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice One movement, as the token describes it to its policy
   * @param token The token whose balance or ownership changes
   * @param from The account whose position decreases, or address(0) when the movement creates the position
   * @param to The account whose position increases, or address(0) when the movement destroys the position
   * @param tokenId 0 for an ERC-20 token; the token identifier for ERC-721, ERC-1155 and ERC-6909 tokens
   * @param amount The quantity moved; 1 for an ERC-721 token
   * @param operator The account that called the token to cause the movement
   * @param kind The authority under which the movement happens
   * @param data Token-defined data. For EXECUTED and FORCED, whatever the token passes. For TRANSFER, MINT and BURN,
   *        empty or only values the token derives from its own state, never anything the caller supplied
   */
  struct TransferContext {
    address token;
    address from;
    address to;
    uint256 tokenId;
    uint256 amount;
    address operator;
    TransferKind kind;
    bytes data;
  }

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Records a movement after balances changed, in the same transaction
   * @dev Only the token named in the context may call it
   * @param _context The context the token passed to `checkTransfer` for this movement
   */
  function afterTransfer(
    TransferContext calldata _context
  ) external;

  /**
   * @notice Initialises the policy for a token that installs it
   * @dev Called by the token on every installation, once its `policy()` returns this policy. Only `_token` may call it
   * @param _token The token installing the policy
   * @param _previousPolicy The policy the token consulted until now; address(0) on the first installation
   * @param _data Data from the account that installs the policy, passed on unchanged
   */
  function onInstall(
    address _token,
    address _previousPolicy,
    bytes calldata _data
  ) external;

  /**
   * @notice Account-level eligibility to receive `_token`; backs the token's ERC-7943 `canReceive`
   * @param _token The token
   * @param _account The account
   * @return _reason TRANSFER_OK to permit, any other value to reject
   */
  function checkReceive(
    address _token,
    address _account
  ) external view returns (bytes32 _reason);

  /**
   * @notice Account-level eligibility to send `_token`; backs the token's ERC-7943 `canSend`
   * @param _token The token
   * @param _account The account
   * @return _reason TRANSFER_OK to permit, any other value to reject
   */
  function checkSend(
    address _token,
    address _account
  ) external view returns (bytes32 _reason);

  /**
   * @notice Decides one movement
   * @dev Called by the token before balances change, and by anyone to simulate
   * @param _context The movement
   * @return _reason TRANSFER_OK to permit, any other value to reject
   */
  function checkTransfer(
    TransferContext calldata _context
  ) external view returns (bytes32 _reason);

  /**
   * @notice Whether the token must call `afterTransfer` after each movement
   * @dev May change with the policy's configuration
   * @return _wantsAfter True if the token must call `afterTransfer`
   */
  function wantsAfterTransfer() external view returns (bool _wantsAfter);
}

/**
 * @title IERC8473
 * @notice An ERC-7943 token governed by an external policy
 */
interface IERC8473 is IERC165 {
  /*///////////////////////////////////////////////////////////////
                            EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Emitted on every installation, including the first
   * @param _previousPolicy The policy before the change; address(0) on the first installation
   * @param _newPolicy The policy after the change
   */
  event PolicyChanged(address indexed _previousPolicy, address indexed _newPolicy);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Recommended error when the policy rejects a movement
   * @param _reason The policy's reason code
   */
  error ERC8473PolicyRejected(bytes32 _reason);

  /*///////////////////////////////////////////////////////////////
                            VIEW
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice The policy the token consults for every movement and for its ERC-7943 checks
   * @return _policy The policy
   */
  function policy() external view returns (address _policy);
}
```

`TransferKind` is ABI-encoded as `uint8`, and `TransferContext` as a tuple. The selectors are:

| Function | Signature | Selector |
|---|---|---|
| `checkSend` | `checkSend(address,address)` | `0xec1cb5d7` |
| `checkReceive` | `checkReceive(address,address)` | `0x8b203e96` |
| `checkTransfer` | `checkTransfer((address,address,address,uint256,uint256,address,uint8,bytes))` | `0x64a1a08e` |
| `wantsAfterTransfer` | `wantsAfterTransfer()` | `0x38bff1a5` |
| `afterTransfer` | `afterTransfer((address,address,address,uint256,uint256,address,uint8,bytes))` | `0x2595b359` |
| `onInstall` | `onInstall(address,address,bytes)` | `0x820203aa` |
| `policy` | `policy()` | `0x0505c8c9` |

The [ERC-165](./eip-165.md) identifiers are:
- `0x9cb56a99` for `IERC8473Policy`, the XOR of its six selectors;
- `0x0505c8c9` for `IERC8473`.

### Decisions and reason codes

`TRANSFER_OK` is `keccak256("TRANSFER_OK")`, which is `0xf059ed422c5a003e2d831cdef17f0af416cf22aae18c781d82aaacaa5c77fd3f`.

A check permits if and only if it returns `TRANSFER_OK`. Every other value is a rejection, including `bytes32(0)`.

Policies SHOULD derive each rejection reason as the `keccak256` of an upper-case name, for example `keccak256("RECEIVER_NOT_ELIGIBLE")`. They SHOULD document the reasons they return. Integrators MUST NOT treat an unrecognised value as permission.

### Transfer kinds

The kind records the authority under which a movement happens, as determined from on-chain facts. It is not the name of the function or business process that caused the movement. The token MUST give each movement the first kind in this list whose condition holds:

1. **`FORCED`**: the token makes the movement under its enforcement authority. That is the case when any of the following holds:
   - the movement is an ERC-7943 `forcedTransfer`, or one of the two movements of a `forcedTransfer` implemented as a burn and a mint;
   - it takes tokens from their holder, or settles a claim the token records, without being directed by the holder;
   - it goes through a path the token provides so that it can happen even when ERC-7943's account-level checks or the frozen amount would block it. ERC-7943 allows such bypasses for permissioned mints and burns.
2. **`MINT`**: `from` is `address(0)`.
3. **`BURN`**: `to` is `address(0)`.
4. **`EXECUTED`**: the holder directed the movement by a signed instruction the token verified itself, such as an [EIP-712](./eip-712.md) signature, or an [ERC-1271](./eip-1271.md) answer from a holder that is a contract. The token carries the instruction out through a function it restricts to accounts it has granted that capability, independently of the instruction. A function that any account may call, or only an account the instruction names (such as the payee), does not qualify. A request the token records is not a signed instruction: carrying it out is never `EXECUTED`.
5. **`TRANSFER`**: any other movement. These include movements the holder directed:
   - directly;
   - through an allowance or operator approval;
   - through a signature that any account, or the account it names, may submit;
   - through a request the token records.

This order has two consequences:
- A `forcedTransfer` is `FORCED` whatever its reason, including a recovery the holder asked for off-chain.
- A movement directed by the holder is never `FORCED` unless it goes through an enforcement path, even when a privileged account triggers it. For example, returning escrowed tokens to an account that the request, or its documented lifecycle, names is a `TRANSFER`.

`MINT` and `BURN` are therefore ordinary issuance, subject to the account-level checks, and holder-directed destruction, subject to those checks and the frozen amount. A `FORCED` movement MUST NOT have both `from` and `to` equal to `address(0)`. A movement caused through the base standard's transfer functions (such as `transfer`, `transferFrom`, `safeTransferFrom` and their batch forms) MUST NOT be `EXECUTED` or `FORCED`.

The set of kinds is closed. The encodings are `TRANSFER = 0`, `EXECUTED = 1`, `FORCED = 2`, `MINT = 3` and `BURN = 4`. Adding a kind requires a new interface.

### Transfer context

- `token` MUST be the address of the token whose balance or ownership changes. When the token calls its policy, `token` is `address(this)`.
- `from` MUST be `address(0)` for `MINT` and `to` MUST be `address(0)` for `BURN`. `TRANSFER` and `EXECUTED` movements have non-zero `from` and `to`.
- `tokenId` MUST be `0` for an [ERC-20](./eip-20.md) token. For other tokens it MUST be the identifier of the token moved.
- `amount` MUST be the quantity moved, and `1` for an [ERC-721](./eip-721.md) token.
- `operator` MUST be the account that called the token to cause the movement. That is `msg.sender`, or the sender resolved by a trusted forwarder as in [ERC-2771](./eip-2771.md). It MUST NOT be `tx.origin`. For `EXECUTED`, `operator` is the executing account. For `FORCED`, it is the enforcing account. In the context of `canTransfer`, `operator` is as check rule 3 defines it; in an `EXECUTED` pre-flight, as check rule 6 does.
- `kind` MUST follow the rules above.
- `data` MUST be empty for `TRANSFER`, `MINT` and `BURN`, or hold only values the token derives from its own state, such as the balances of `from` and `to` before the movement. It MUST NOT hold anything the caller supplied. For `EXECUTED` and `FORCED`, the token MAY pass other data, for example an instruction reference and deadline, or a reference to a legal order. A token that passes data MUST document its encoding.

### Token requirements

#### Movements

1. Before any balance or ownership change of a movement takes effect, the token MUST call `checkTransfer` on its policy with that movement's context, and MUST revert unless the call returns `TRANSFER_OK`. For `TRANSFER`, `MINT` and `BURN`, the operation MUST NOT have changed the token's balances, ownership, total supply or frozen amounts before this call, except through earlier movements of the same operation.
2. Between that call and the balance change, the token MUST NOT make any external call other than to its policy.
3. The token SHOULD revert with `ERC8473PolicyRejected(reason)` when the policy rejects. When the token rejects through one of its own checks, it SHOULD use the more specific error ERC-7943 recommends, such as `ERC7943InsufficientUnfrozenBalance`.
4. The movement MUST revert if any of the following happens:
   - `checkTransfer` or `wantsAfterTransfer` reverts;
   - either returns fewer than 32 bytes of data;
   - `wantsAfterTransfer` returns a word other than `0` or `1`;
   - the policy address has no code.
5. The token MUST read its policy address once per movement. It MUST use that one address for the movement's `checkTransfer`, `wantsAfterTransfer` and `afterTransfer` calls.
6. After the movement's balances change and its base-standard transfer event is emitted, the token MUST call `wantsAfterTransfer` on that policy. If it returns `true`, the token MUST then call `afterTransfer` with a context identical to the one it passed to `checkTransfer`. A revert of `afterTransfer` MUST revert the movement.
7. The calls in rule 6 MUST complete before the token makes any call to the movement's recipient, such as an ERC-721 or ERC-1155 receiver hook, and before another movement begins.
8. The token MUST call `checkSend`, `checkReceive`, `checkTransfer` and `wantsAfterTransfer` with `STATICCALL`.
9. The token MUST NOT allow a movement to begin while `afterTransfer` runs, for example by guarding its balance-changing path against reentrancy.
10. The token MUST process the items of a batch operation in the order given. For each item it checks, changes balances, emits that item's transfer event and notifies, all before checking the next item. An ERC-1155 token therefore emits one `TransferSingle` per item, which ERC-1155 allows. If any item is rejected, the whole batch MUST revert.
11. When `policy()` returns `address(0)`, the token MUST reject every movement.
12. A `TRANSFER`, `EXECUTED`, `MINT` or `BURN` movement MUST NOT happen unless both the token's own checks and the policy permit it. The token's account-level conditions apply to `from` as for `canSend`, and to `to` as for `canReceive`. For `TRANSFER`, `MINT` and `BURN`, the token's own checks MUST NOT depend on `msg.sender`, `operator`, `tx.origin`, the remaining gas or any other transaction context. Nor may they depend on state the operation changes before the check, other than through earlier movements of the same operation.
13. For `FORCED` movements, the token applies its own checks as ERC-7943 specifies for `forcedTransfer` and for permissioned minting and burning. For example, `forcedTransfer` MAY bypass them in single-party permissioned contexts, where it SHOULD still apply those on `to`, and SHOULD apply them in multi-party ones. If a `FORCED` movement moves frozen tokens, the token MUST first reduce the frozen amount by at least the frozen part of what moves (for a non-fungible token, unfreeze it). It MUST then emit `Frozen`, before the base standard's transfer event.
14. The token's views of balances, ownership, total supply and frozen amounts MUST NOT revert while a movement is in progress or while `onInstall` runs. A policy may read them during `checkTransfer`, `afterTransfer` and `onInstall`.

#### Checks and pre-flights

1. `canSend(address(0))` MUST return `true` without calling the policy. For any other account, `canSend(account)` MUST return `true` if and only if `checkSend(address(this), account)` returns `TRANSFER_OK` and the token's own account-level conditions for sending permit.
2. `canReceive(address(0))` MUST return `true` without calling the policy. For any other account, `canReceive(account)` MUST return `true` if and only if `checkReceive(address(this), account)` returns `TRANSFER_OK` and the token's own account-level conditions for receiving permit.
3. `canTransfer` is the pre-flight for the `TRANSFER`, `MINT` or `BURN` movement its arguments describe:
   - a `TRANSFER` when `from` and `to` are both non-zero;
   - a `MINT` when `from` is zero;
   - a `BURN` when `to` is zero.

   It MUST return `true` if and only if both of the following hold:
   - the token's own checks permit that movement;
   - `checkTransfer` returns `TRANSFER_OK` for this context:
     - `token`: `address(this)`;
     - `from`, `to`: the arguments;
     - `tokenId`: the `tokenId` argument, or `0` for the fungible interface;
     - `amount`: the `amount` argument, or `1` for the non-fungible interface;
     - `operator`: `from`, which is zero for a mint;
     - `kind`: as listed above;
     - `data`: as the movement would build it for this kind from the token's current state, or empty if the token passes none.

   When both `from` and `to` are zero, `canTransfer` MUST return `false`. The zero side of a mint or a burn passes the account checks (check rules 1 and 2), so the account checks of a mint fall on `to` alone, and those of a burn on `from` alone.
4. The token's own checks in `canTransfer` include ERC-7943's unfrozen-amount validation: when a non-zero `from` has a non-zero frozen amount, `canTransfer` returns `false` for an `amount` above the unfrozen amount. Balances, ownership of a non-fungible token and allowances stay outside the token's own checks, as ERC-7943 specifies for base-standard validations: with nothing frozen, an `amount` above the balance does not fail those checks, although the movement fails. This ERC also leaves access control on the functions that cause movements outside them, such as a role on a mint or burn function.
5. `canSend`, `canReceive` and `canTransfer` MUST NOT revert, as ERC-7943 requires. When they call the policy, they MUST return `false` if any of the following happens:
   - the policy call reverts;
   - it runs out of gas;
   - it returns fewer than 32 bytes of data;
   - the policy has no code.

   This holds provided the caller leaves the token enough gas to finish after a call that received at most 63/64 of the remaining gas. The token SHOULD copy at most 32 bytes of the policy's return data.
6. A token that offers a pre-flight for `EXECUTED` movements, for example a view that takes a signed instruction and the executing account, MUST build the context exactly as that account's execution would, including `operator` and `data`. It MUST NOT answer that the movement would succeed when the token's own checks would reject it, or when `checkTransfer` for that context reverts, returns fewer than 32 bytes, or returns anything other than `TRANSFER_OK`.

These rules, together with the policy requirements below, have the following consequences:
- `canTransfer` performs ERC-7943's `canSend` check on `from` and `canReceive` check on `to`, the zero address included.
- Given enough gas, `canTransfer` returns the decision that the `TRANSFER`, `MINT` or `BURN` movement with these accounts and amount would receive at the same state, whoever submits it. That movement may be a `transfer`, a `transferFrom` by a spender, a mint, or a holder-directed burn. The validations and access control in check rule 4 stay outside it, as does a failure of `wantsAfterTransfer` or `afterTransfer`, which `canTransfer` does not call.
- For an operation that causes several movements, `canTransfer` predicts each one at the state it starts from. Integrators can simulate the operation as a whole.

`canTransfer` does not predict `EXECUTED` or `FORCED` movements, because their decisions may depend on `operator` and `data`. A policy MAY treat them more strictly or more leniently than `TRANSFER`.

#### Installing a policy

1. `policy()` MUST return the policy the token currently consults.
2. The token MUST emit `PolicyChanged` on every installation, including the first, where `_previousPolicy` is `address(0)`.
3. The token MUST NOT install a policy that does not return `true` for `supportsInterface(0x9cb56a99)`. Who may install a policy is outside this ERC.
4. The token MUST return `true` for `supportsInterface(0x0505c8c9)` and for the identifier of the ERC-7943 interface it implements.
5. On every installation, once `policy()` returns the new policy, the token MUST call `onInstall` on it with `address(this)`, the policy it consulted until then (`address(0)` on the first installation), and the data supplied by the account that installs the policy, unchanged. If `onInstall` reverts, the installation MUST revert, so the token keeps its previous policy.
6. The token itself MUST NOT make an installation depend on the outgoing policy: it MUST NOT revert it because a call the token makes to that policy reverts, or because of what that policy returns to the token.
7. The token MUST NOT allow a movement or another installation to begin while `onInstall` runs.
8. The token MUST NOT install a policy before its own code is in place, for example from its constructor, because `onInstall` must be able to read it (token rule 14).

### Policy requirements

1. `checkSend`, `checkReceive`, `checkTransfer` and `wantsAfterTransfer` MUST NOT modify state. They MUST NOT revert to express a decision. They reject by returning a value other than `TRANSFER_OK`.
2. Their results MAY depend on their arguments, on persistent contract storage, and on the block's timestamp, number and chain identifier. They MUST NOT depend on `msg.sender`, `tx.origin`, the remaining gas or any other transaction context. This deliberately narrows ERC-7943, which allows its checks to depend on `msg.sender`.
3. `checkSend` and `checkReceive` MUST NOT encode transfer-specific or quantitative rules, such as balance checks or amount limits. ERC-7943 requires this of `canSend` and `canReceive`.
4. For every kind except `FORCED`, `checkTransfer` MUST NOT return `TRANSFER_OK` if either of these holds:
   - `from` is non-zero and `checkSend(_context.token, _context.from)` does not return `TRANSFER_OK`;
   - `to` is non-zero and `checkReceive(_context.token, _context.to)` does not return `TRANSFER_OK`.
5. For `FORCED` with a non-zero `to`, `checkTransfer` SHOULD NOT return `TRANSFER_OK` when `checkReceive(_context.token, _context.to)` does not. This mirrors the receiver check that ERC-7943 recommends for forced transfers and permissioned mints. A policy MAY depart from it where the token documents `FORCED` paths that ERC-7943 allows to bypass `canReceive`.
6. For `TRANSFER`, `MINT` and `BURN`, the result of `checkTransfer` MUST NOT depend on `operator`. It also MUST NOT depend on state that the operation causing the movement changes before calling `checkTransfer`, other than through earlier movements of the same operation. Such state includes the asset holdings of an [ERC-4626](./eip-4626.md) vault, which a deposit raises before shares are minted. For `EXECUTED`, it SHOULD NOT depend on state the operation changes before calling `checkTransfer`, such as the record that an instruction was used, because a pre-flight under check rule 6 cannot reproduce it. The policy MAY read:
   - the token's balances, ownership, total supply and frozen amounts;
   - its own storage;
   - other contracts' state that no operation of the token changes, such as an identity registry.
7. `checkTransfer` MUST NOT return `TRANSFER_OK` for a `kind` outside the enumeration. In Solidity, an out-of-range enum value in a `calldata` struct causes a revert whenever the member is read. That includes copying the struct, ABI-encoding it, forwarding it in an external call or emitting it. Left untouched, the struct does not revert. A policy MUST NOT rely on this unless every path that can permit reads `_context.kind`.
8. A policy MUST NOT return `TRANSFER_OK` if any call it makes in reaching the decision reverts or runs out of gas.
9. Any account can call the checks with any context. A permitting result authorises nothing. A policy MUST NOT treat a call to a check as evidence that the caller is the token, that a signature was verified, or that a movement took place.
10. `afterTransfer` MUST revert unless `msg.sender` equals `_context.token`. A call from one token MUST NOT change state that governs another token's movements. The one exception is a policy that authenticates every token whose movements that state governs, for example through a list of the tokens it serves.
11. While `afterTransfer` runs, the token's balances are those after the movement. The policy MAY make view calls to the token. It cannot start another movement (token rule 9). `afterTransfer` MUST NOT enforce a rule on a `TRANSFER`, `MINT` or `BURN` movement. A rule that can reject one belongs in `checkTransfer`, because `canTransfer` does not call `afterTransfer` and ERC-7943 requires `canTransfer` to return `false` when a permissioned rule would prevent the transfer. It SHOULD NOT enforce a rule on an `EXECUTED` movement, because a pre-flight under check rule 6 does not call `afterTransfer` either.
12. `wantsAfterTransfer` MAY change its answer as the policy's configuration changes. While it returns `false`, the policy MUST NOT depend on receiving `afterTransfer`.
13. The policy MUST return `true` for `supportsInterface(0x9cb56a99)`.
14. The policy SHOULD bound the gas its checks consume. A check that runs out of gas rejects the movement and, given enough gas for the token to finish (check rule 5), makes the token's pre-flight return `false`.
15. `onInstall` MUST revert unless `msg.sender` equals `_token`. A call from one token MUST NOT change state that governs another token's movements, except as policy requirement 10 allows.
16. On every call, `onInstall` MUST either set all state the policy derives from `_token`'s movements, such as a holder count, or revert. It MUST NOT keep such state from an earlier installation, including an earlier installation on the same token. A policy without such state MAY do nothing else in `onInstall`. What it accepts in `_data`, and what it reads on-chain, is up to the policy.

## Rationale

### A policy behind ERC-7943

A pause stays in the token, and is not an account-level condition: it makes `canTransfer` return `false` and leaves `canSend` and `canReceive` unchanged. ERC-7943 likewise lists a pausing mechanism among the permissioned checks of `canTransfer`.

`checkSend` and `checkReceive` take the token as a parameter, as `TransferContext` does. One policy deployment can then serve many tokens, and a simulated call always names the token it is about.

### Kinds record the authority

Policies treat movements differently by authority:
- A lock-up binds the holder but not a court order.
- A holder cap binds ordinary transfers and issuance, not enforcement.

An open list of business operations seems more expressive, but it fails twice:
- **Names overlap.** An escrow release to a recovery account is a release, a recovery and a forced transfer at once.
- **Unknown names.** Every policy must decide how to treat names it has never seen. If it permits them, an unknown name bypasses its checks. If it rejects them, every new operation breaks every deployed policy.

The ordered rules record a real defect in the implementation this ERC is extracted from. An asynchronous vault returned the escrowed shares of a rejected redemption request to the request's controller, an address chosen when the request was made, and labelled the movement `FORCED`. Enforcement was exempt from the holder cap and from the pause, so that path delivered shares past both checks. The movement was directed by the request, so it is a `TRANSFER`.

The kind of the less obvious operations (non-normative):

| Operation | Kind |
|---|---|
| A transfer an agent makes for the holder under an [ERC-8226](./eip-8226.md) mandate, directly or through an executor, using the base standard's transfer functions | `TRANSFER` |
| Returning escrowed shares to an account that the request, or its documented lifecycle, names, when the request is rejected or cancelled | `TRANSFER` |
| Burning escrowed shares when a redemption request is fulfilled | `BURN` |
| An authorised executor carries out a holder-signed burn or mint instruction | `BURN` or `MINT` |
| Moving escrowed shares to a recovery account because the account entitled to them is no longer eligible | `FORCED` |
| Minting a fulfilled claim to a recovery account instead of the claimant | `FORCED` (`from` zero) |
| Burning tokens without the holder's on-chain direction, or despite failed account checks or frozen tokens | `FORCED` (`to` zero) |

`EXECUTED` is separate from `TRANSFER` even though the holder directs both. Its movements arrive through a settlement channel the token restricts, and policies commonly apply rules to that channel that they do not apply to a holder's own transfers, such as business-day windows and cut-off times. A signature that any account, or only the account it names, may submit, as in [ERC-3009](./eip-3009.md), stays a `TRANSFER`, so `canTransfer` can predict it.

`MINT` and `BURN` come before `EXECUTED` to keep one kind for each economic event. A policy's rules on issuance and redemption, such as a holder cap, see a burn as `BURN` whether the holder or an executor submits it, and `canTransfer` predicts both. A token that needs a condition on instructed redemptions, such as a dealing cut-off, enforces it in the function that carries out instructions, as it enforces an instruction's deadline, and `canTransfer` reflects neither. Moving `EXECUTED` ahead of `MINT` would not reach signed subscription orders either: a mint has a holder only when it settles a claim the token records, so no holder directs it.

### What `canTransfer` predicts

ERC-7943 requires that `canTransfer` "MUST return false if any permissioned rule would prevent a given transfer from succeeding". It also requires that public transfers "MUST NOT succeed in cases where `canTransfer` would return `false`".

This ERC reads "a given transfer" as the `TRANSFER`, `MINT` or `BURN` movement described by `canTransfer`'s arguments. `canTransfer(from, to, amount)` receives no instruction, signature, nonce or submitter, so it cannot predict a movement whose outcome depends on them, such as an `EXECUTED` settlement or a `FORCED` enforcement action. Neither may go through the base standard's transfer functions.

ERC-7943 itself lets `forcedTransfer` bypass `canTransfer`, and lets permissioned mints and burns bypass the account checks or the frozen amount. This ERC labels forced transfers, and mints and burns made through such a bypass, `FORCED`. The mints and burns that `canTransfer` predicts are therefore those that cannot use these exceptions.

Under that reading, a policy may close a settlement window for `EXECUTED` while direct transfers remain possible. It may also disable direct transfers entirely while authorised executors settle instructions.

ERC-7943 counts mints and burns as transfers, and requires `canTransfer` to perform `canSend` on `from` and `canReceive` on `to`, but says nothing about a zero address. The zero address is the source of every mint and the sink of every burn, so it passes both account checks, and `canTransfer` still performs both (check rules 1 to 3).

Passing `canReceive` does not make the zero address a destination. [ERC-721](./eip-721.md) and [ERC-1155](./eip-1155.md) reject a transfer to it. ERC-20 does not, and where a token allows one, the movement is a `BURN`.

### Pre-flight parity

The boundary between a token and its policy is where answers drift: a different code path, a different context, a caller the token cannot know, or state that changes inside the operation before the policy is asked. Check rule 3, token rules 1, 12 and 14, and policy requirements 2 and 6 close these gaps.

`TRANSFER`, `MINT` and `BURN` decisions cannot depend on `operator`, so the token can answer without knowing whether the holder or a spender will submit. An allowance is the holder's authority, delegated. A token that wants to limit which contracts act for its holders can restrict `approve` and operator approvals, where that authority is granted. A policy's answer cannot depend on `msg.sender` either, so anyone who calls it directly gets the answer the token would get.

For the same reason, `data` carries nothing the caller supplied for `TRANSFER`, `MINT` and `BURN`. `canTransfer` has no data argument, so a decision that read the data of a `safeTransferFrom`, or a payload such as travel-rule information, could not be predicted. Values the token derives from its own state, such as the balances before the movement, are different: at the same state, `canTransfer` builds the same `data`.

`EXECUTED` and `FORCED` decisions may use `operator` and `data`. The submitter is part of what the policy is asked to approve, and a pre-flight for those kinds is specific to the token and is told the submitter. In `canTransfer`'s context, `operator` is `from`, zero for a mint, so the context depends only on its arguments and the token's state, the same whoever runs the simulation.

ERC-7943 forbids `canTransfer` from reverting, so a policy that reverts or misbehaves must turn into `false`. In Solidity, `try`/`catch` is not enough for this: it does not catch a failure to decode malformed return data.

### Account checks live in the policy

Deriving `canSend` and `canReceive` by probing `checkTransfer` would need an invented counterparty and amount, and a transfer-level rule such as a lock-up would then leak into an account-level answer, so the policy answers them directly. Policy requirement 4 keeps `checkTransfer` consistent with both, so the token can make one check per movement and still meet ERC-7943's requirement that `canTransfer` perform them.

### A non-zero success value

Zero is what Solidity returns from a function whose named return value is never assigned, and what an uninitialised variable holds. A boundary where zero permits therefore fails open on the most common bugs.

[ERC-1271](./eip-1271.md) and ERC-721's receiver hook use a function selector as their magic success value. That would be unsafe here: `checkTransfer` takes one dynamic argument, so a contract that echoes its calldata returns exactly `bytes32(checkTransfer.selector)`. A string hash cannot be produced by accident that way.

Decisions are `bytes32`, not `bool`, because operators and integrators need to know why a movement was rejected. Hashing a name lets every policy define its own reasons without a central registry.

Decisions are returned, not reverted, because a pre-flight cannot tell a revert that expresses a decision from a bug or an out-of-gas condition. For the same reason, a policy may not turn a failed internal call into a permission (policy requirement 8), or a caller could choose a gas limit that makes one rule run out of gas while the policy still permits.

### The after-transfer callback

Policies that keep state, such as holder counts, need to observe completed movements. Stateless policies should not pay for that. `wantsAfterTransfer` says whether the call is needed now. ERC-165 is not a substitute: it says which functions a contract implements, integrators commonly cache its answers, and a composed policy's need for the callback changes with its configuration.

The callback runs before any call to the recipient, so a recipient that starts another movement meets policy state that already includes the first (token rule 7).

### Installing a policy

A policy that keeps state derived from movements, such as a holder count, is only correct for one unbroken installation. While another policy is installed, it sees none of the token's movements, and without being told it cannot know that it was replaced. `onInstall` tells it on every installation, so a policy can rebuild or verify its state at the moment it goes live, or refuse to go live by reverting.

The call is required of every token, not offered as an extension. A policy can only refuse to go live with stale state if every token that may install it makes the call.

Each call initialises again. A guard that skips initialisation for a token the policy has served before, as one-time initialisers do, would keep the state from the earlier installation, which is the case the call exists for. Mappings cannot be cleared, so a policy can key such state by an installation number that `onInstall` increments.

The token passes `_previousPolicy` itself. A policy that copies state from its predecessor, for example from the interim policy of a staged migration (see Security Considerations), then reads the contract the token actually consulted, not an address chosen by whoever prepared the installation. Copying still trusts that contract.

This ERC defines no call from the token to the outgoing policy. If the outgoing policy could revert its own removal, a broken or hostile policy could keep itself installed. [ERC-7579](./eip-7579.md) names this risk for modules that revert in `onUninstall`.

The token sets the new policy before it calls `onInstall`, so the policy can confirm through `policy()` that it is the one being installed.

Until a policy is installed the token rejects every movement (token rule 11), so a token deployed without one is safe. A token behind a proxy can install from an initializer called after the proxy is deployed, not from one the proxy's constructor runs.

### Batches are processed in order

ERC-1155 already requires batch balance changes to occur in array order. Checking, moving and notifying each item before the next makes every item's decision the decision a single movement would get at that point in the batch. Rules on aggregate state, such as holder caps, then stay exact.

OpenZeppelin's `ERC1155` applies a whole batch in `_update` and then emits `TransferBatch`, so a token built on it overrides `_update` to apply the items one at a time.

### Related work

- **Earlier security-token proposals** that were never merged, among them the Security Token Standard and the Simple Restricted Token Standard, already returned a code from a transfer check, with a reason or a message. They define the check a token offers to integrators, as ERC-7943 now does, not an interface between a token and a separate policy.
- **[ERC-7746](./eip-7746.md)** defines generic security layers. A layer must decode each protected function's calldata to learn what moves where, and rejects by reverting from a hook that is not a view, so it cannot back a non-reverting pre-flight.
- **Rule-composition engines**, including the Universal Policy Engine proposal currently under discussion, define how rules combine inside an engine. An engine whose evaluation can run in a `STATICCALL` can implement `IERC8473Policy` as its entry point.

## Backwards Compatibility

This ERC does not change ERC-7943's interface. A token that adopts it keeps that interface, so integrators call it unchanged. This ERC narrows one freedom: the checks may not depend on `msg.sender`. ERC-7943 says nothing about the zero address, and it does not address transfers an executor settles. The Rationale gives this ERC's choices on both.

An adapter can present an ERC-3643 token's compliance contract and identity registry as an `IERC8473Policy`:
- **`checkSend`** permits when the account's wallet is not frozen on the ERC-3643 token.
- **`checkReceive`** permits when the account is verified in the identity registry and its wallet is not frozen.
- **`checkTransfer`** applies both account checks to `TRANSFER` and `EXECUTED`, then the compliance contract's `canTransfer(from, to, amount)`. For `MINT`, it applies only `checkReceive`, which policy requirement 4 demands, although ERC-3643's own mint ignores frozen wallets. For `FORCED` with a non-zero `to`, it requires only that the receiver is verified, as ERC-3643's `forcedTransfer` does. ERC-3643 has no holder-directed burn: its agent burns are `FORCED` with a zero `to`, and the adapter permits them.
- **`afterTransfer`** calls the compliance contract's `created` for movements from zero, `destroyed` for movements to zero, and `transferred` otherwise. This works only where the compliance contract accepts the adapter as its caller.
- **`onInstall`**: ERC-3643 defines no call that rebuilds a compliance contract's state. An adapter over one that keeps state can meet policy requirement 16 only by reverting when it cannot tell that the state is current, which in practice limits it to one installation.

The adapter, not the compliance modules, decides the exemptions, so it is a migration path, not an equivalent.

A token that already consults a policy through its own interface can install an adapter that implements its existing hook interface on top of an `IERC8473Policy`, or migrate to a new token implementation.

## Test Cases

Sent to the reference policy with that policy's own token as `token`, a `TransferContext` whose `kind` is encoded as `5` reverts, because the policy reads `kind`. A `kind` of `4` (`BURN`) decodes.

The executable tests in [`ERC8473.t.sol`](../assets/eip-8473/contracts/test/ERC8473.t.sol) and [`ERC8473Executed.t.sol`](../assets/eip-8473/contracts/test/ERC8473Executed.t.sol), and the unit tests beside the contracts, run against the reference implementation:
- **Fail-closed returns.** For a reverting policy, one that returns 31 bytes, or one that runs out of gas, `canTransfer` returns `false` without reverting, and the movement reverts. A policy with an unassigned return value, or a contract that echoes its calldata, rejects.
- **Account checks.** The zero address passes `canSend` and `canReceive`, and a plain transfer to it still reverts.
- **Fuzzed pre-flight parity.** Over eligibility, pause, frozen amounts, holder caps and amounts, `canTransfer` equals the outcome of `transfer`, `transferFrom` by a spender, a mint and a holder burn, except that with nothing frozen an amount above the balance fails in the movement although `canTransfer` is true.
- **Rejections.** A policy rejection reverts with `ERC8473PolicyRejected` and the policy's reason. A frozen amount reverts with `ERC7943InsufficientUnfrozenBalance`, and an amount above the balance with the base standard's `ERC20InsufficientBalance`.
- **Installation.** If `onInstall` reverts, the previous policy stays. A policy reinstalled after another sets its holder count again.
- **Forced transfers.** A forced transfer succeeds while the token is paused and the holder cap is full, and still requires an eligible receiver. It unfreezes only the frozen part of what moves: with 1000 held and 950 frozen, moving 100 leaves 900 frozen.
- **Executed movements.** The policy sees `EXECUTED`, the executor as `operator`, and the instruction's reference and deadline in `data`. A replayed, expired, altered or wrongly signed instruction reverts. `canExecute` equals the outcome of the execution, and builds the same context.

## Reference Implementation

The assets folder contains:
- [`IERC8473Policy.sol`](../assets/eip-8473/contracts/interfaces/IERC8473Policy.sol) and [`IERC8473.sol`](../assets/eip-8473/contracts/interfaces/IERC8473.sol): the interfaces above;
- [`ExampleToken.sol`](../assets/eip-8473/contracts/example/ExampleToken.sol): an ERC-20 token that implements ERC-7943's fungible interface through this ERC;
- [`ExampleExecutorToken.sol`](../assets/eip-8473/contracts/example/ExampleExecutorToken.sol): `ExampleToken` with a settlement channel. An account with `EXECUTOR_ROLE` carries out a holder's signed EIP-712 instruction as an `EXECUTED` movement, and `canExecute` is its pre-flight;
- [`ExamplePolicy.sol`](../assets/eip-8473/contracts/example/ExamplePolicy.sol): a policy that combines an allowlist with a holder cap. It sets its count in `onInstall` from a list of holders it checks against `totalSupply()`, and keeps it through `afterTransfer`.

The examples are for illustration and are not audited. Imports use the remappings `interfaces/=contracts/interfaces/` and `contracts/=contracts/`.

`_update` gives the movements OpenZeppelin's `ERC20` causes their kind, and every movement goes through `_move`:

```solidity
function _update(
  address _from,
  address _to,
  uint256 _value
) internal override {
  IERC8473Policy.TransferKind _kind = _forcedPending ? IERC8473Policy.TransferKind.FORCED : _inferKind(_from, _to);
  _forcedPending = false;
  _move(_from, _to, _value, _kind, '');
}

function _move(
  address _from,
  address _to,
  uint256 _value,
  IERC8473Policy.TransferKind _kind,
  bytes memory _data
) internal nonReentrant {
  bytes32 _tokenReason = _tokenCheck(_from, _value, _kind);
  if (_tokenReason == _PAUSED) revert EnforcedPause();
  if (_tokenReason == _INSUFFICIENT_UNFROZEN) {
    uint256 _balance = balanceOf(_from);
    if (_value > _balance) revert ERC20InsufficientBalance(_from, _balance, _value);
    revert ERC7943InsufficientUnfrozenBalance(_from, _value, _unfrozen(_from));
  }

  IERC8473Policy.TransferContext memory _ctx = _context(_from, _to, _value, _msgSender(), _kind, _data);
  IERC8473Policy _activePolicy = IERC8473Policy(_policy); // read once for this movement

  // A revert, missing code or short return data reverts here too: the movement fails closed.
  bytes32 _reason = _activePolicy.checkTransfer(_ctx);
  if (_reason != TRANSFER_OK) revert ERC8473PolicyRejected(_reason);

  super._update(_from, _to, _value);

  if (_activePolicy.wantsAfterTransfer()) _activePolicy.afterTransfer(_ctx);
}
```

Its pre-flights call the policy without reverting, and permit only on a full word equal to `TRANSFER_OK`:

```solidity
function _permits(
  bytes memory _payload
) internal view returns (bool _permitted) {
  address _activePolicy = _policy;
  bytes32 _ok = TRANSFER_OK;
  assembly ('memory-safe') {
    let _success := staticcall(gas(), _activePolicy, add(_payload, 0x20), mload(_payload), 0x00, 0x00)
    if and(_success, gt(returndatasize(), 0x1f)) {
      returndatacopy(0x00, 0x00, 0x20)
      _permitted := eq(mload(0x00), _ok)
    }
  }
}
```

## Security Considerations

### Mislabelled kinds

The kind is the token's statement about authority, and policies have to trust it. A holder-directed movement labelled `FORCED` skips the rules policies apply to holders, and usually the token's own pause. An enforcement action labelled `TRANSFER` meets rules it was meant to override. Implementers should review every path that changes a balance against the kind rules, especially paths that move tokens through escrow.

### Enforcement authority

`FORCED` movements are usually exempt from most rules. Access to them is therefore as sensitive as ERC-7943 describes for `forcedTransfer`. Multisignature control and timelocks are recommended.

### Signed instructions

This ERC does not define the instruction behind an `EXECUTED` movement. A token that offers one decides how it protects the signature:

- **One use.** Without a nonce, or a reference the token records as used, an executor can repeat a holder's instruction until the balance runs out. Because a rejected movement reverts, the record is undone with it, and the instruction stays usable until its deadline.
- **Binding.** The signature should cover every value the movement takes from it: the accounts, the amount, and anything passed in `data`. An EIP-712 domain that names the chain and the token stops the signature being used elsewhere.
- **Expiry.** The token enforces a deadline itself. If it offers no way to cancel, the deadline is the holder's only limit.
- **Contract holders.** A contract holder's ERC-1271 answer can change between a pre-flight and the execution.
- **Who executes.** The capability extends to whoever can make the granted account call the token. Granting it to a contract that anyone can call opens the function in practice, which kind rule 4 excludes, and the token cannot detect this.

### Which policy is installed

The policy decides every movement, so installing or replacing it is equivalent to rewriting the token's rules. Tokens SHOULD install only policies whose code has been reviewed. They SHOULD enforce that at installation by comparing the policy's `EXTCODEHASH` with a code hash attested after review, for example in a registry maintained by a security council. Attesting code hashes rather than addresses lets one review cover every deployment of the same code. Immutables, such as the reference policy's `TOKEN`, make the code differ per deployment.

A code-hash check only means something for code that cannot change:
- **Proxies.** A proxy keeps its code hash while its implementation changes, so a policy installed this way SHOULD NOT be a proxy.
- **Delegated decisions.** A policy that delegates decisions to other contracts, such as rules, SHOULD apply the same check to each of them when it adds them.
- **Dependencies.** The contracts a policy reads, such as identity registries or oracles, are outside the check and need their own trust assessment.

Attestations are checked only at installation, because a revocation that disabled a running policy could silently remove checks or block every transfer.

### Failing closed

A movement reverts, and a pre-flight that calls the policy returns `false`, when the policy is missing or has no code, when a call the token makes to it fails, or when a check rejects (token rules 1, 4, 6 and 11, check rules 1 to 3 and 5).

### Pre-flights are snapshots

A permitting pre-flight reflects the state when it ran. Eligibility, frozen amounts, holder counts, the policy's configuration and the block time can all change before the movement executes, and the movement is decided again at that point.

### Escrow and entitled accounts

An escrow contract receives and sends tokens like any other account, so it must pass `checkReceive` and `checkSend` itself. The context shows the escrow as `from` or `to`, not the account entitled to the tokens. Only the kind follows the holder the token records. This ERC defines no field for the entitled account, so a policy cannot rely on being told it.

An escrow that must check the entitled account, for example before paying out a claim, has to do so itself, for instance by calling the token's `canTransfer` or `canReceive` for that account.

### Callbacks, state and reentrancy

The token's guard stops `afterTransfer` and `onInstall` from starting a movement, and `onInstall` from starting another installation (token rule 9, installation rule 7).

A policy whose `wantsAfterTransfer` changes to `true` must initialise its state, and no installation tells it, so it does so when its configuration changes. A policy that takes state from `_data` without checking it trusts whoever installs it, who need not be the policy's own administrator.

Reinstalling a policy is an installation. The same holds for one token of a policy shared by several tokens, when that token switches away and back. Because `onInstall` runs inside the installation, nothing can happen between initialising and installing. A gap remains between reading the state and the moment the installation executes. When the state was computed off-chain and passed in `_data`, a governance action carries fixed calldata, so a value read when it was proposed may be stale when it runs. That gap closes only if:

- the state lives in a contract that stays in place across policy replacements;
- `onInstall` reads or verifies the state on-chain, for example by copying it from `_previousPolicy`, or, for state derived from balances, by checking a sorted list of holders whose balances add up to `totalSupply()`;
- the token is paused from the snapshot until the installation, remembering that a pause may not stop `FORCED` movements; or
- the token exposes a count of its movements, and the installation reverts if the count changed since the snapshot. Such a counter is an optional extension, not part of this ERC.

A list of holders checked against `totalSupply()` must be strictly ascending, so that no account is counted twice. Only its non-zero balances count, so the list may name accounts that hold nothing, including holders that have emptied their balance since the list was made.

A check against `totalSupply()` rejects stale state, but it does not make the installation complete. If an account outside the list can become a holder while a timelocked installation is pending, a transfer to it makes the installation revert, and whoever can make that transfer can repeat it on every attempt. A movement counter is stricter still: any movement makes it revert. The installation completes reliably only if the set of possible holders is closed while it is pending, for example:

- the list names every account the outgoing policy would let receive, and no account is made eligible until the installation executes. This needs eligibility that can be enumerated, such as an allowlist, and is limited by how many entries fit in one transaction: about 4,000 for the reference policy, whose NatSpec gives the measured figures;
- a first installation puts in an interim policy that admits a receiver without a balance only by `FORCED`, while still applying the token's eligibility rules, so ordinary movements cannot create holders. This costs one more installation. The second installation then takes the state from the current holders, either:
  - from a list checked in one transaction, as above. A `FORCED` movement to a new account before it executes makes it revert, so enforcement that moves tokens to new accounts waits until it has run, or the list is prepared again; or
  - from a count the interim policy builds itself, over as many transactions as needed. Anyone may register an account once, while it holds a balance, which adds the balance to a running sum and one to the count. In `afterTransfer` the interim policy keeps the sum and the count current for registered accounts, and ignores movements of zero and movements from an account to itself: otherwise a self-transfer of a whole balance would raise the count, and a zero transfer from an emptied account would lower it, while the sum stays the same. That includes a registered account that emptied and is then refilled by `FORCED`: its flag stays set, so it cannot register again, and the count rises by one when its balance after the move equals the amount it received. An account that is not registered and that a `FORCED` movement leaves with a balance is registered in the same `afterTransfer`, with its balance after the move added to the sum and one to the count. Once the sum equals `totalSupply()`, no unregistered account holds tokens and the count is exact. The second installation's `onInstall` copies the count from the interim policy, which it receives as `_previousPolicy`, and reverts unless the sum still equals `totalSupply()` in that transaction. This has no limit on the number of holders. Once every holder is registered, ordinary movements cannot create a holder and a `FORCED` movement registers the one it creates, so the sum stays equal to `totalSupply()` and the installation completes whenever it executes;
- the state lives in a contract that stays in place across policy replacements, so no list is needed.

Copying the state from the outgoing policy completes in one step, but only when the outgoing policy is trusted. In the staged way above, the outgoing policy at the second installation is the interim one, whose sum the second installation's `onInstall` checks against `totalSupply()`.

### Balance changes that are not movements

The policy sees only movements: changes recorded by the base standard's transfer events. Balance changes that emit no transfer event, such as rebasing or interest accrual, are never checked.

### Gas

A broken or hostile policy can return a large amount of data to make a pre-flight run out of gas. Copying at most one word of return data prevents this.

### Data

A policy that reads `data` depends on the encoding of the token it serves. Nothing in the context identifies that encoding, and `abi.decode` ignores extra words, so a policy shared by tokens with different encodings can read one value as another without reverting. It should fix the encoding per token.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
