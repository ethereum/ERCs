---
eip: 8520
title: ERC-721 Composition Extension
description: An ERC-721 extension declaring the assets each token holds in its own locked container, released only to the owner recorded at burn.
author: Antonio Ferraioli (@antferr)
discussions-to: https://ethereum-magicians.org/t/erc-721-composition-extension/30181
status: Draft
type: Standards Track
category: ERC
created: 2026-11-26
requires: 20, 165, 721, 1271, 6551, 7528, 8423
---

## Abstract

This proposal extends [ERC-721](./eip-721.md) with two view functions. `compositionOf` returns the constituents a token was minted with: native asset or [ERC-20](./eip-20.md) amounts, declared once and fixed forever. `compositionAccountOf` returns the container that holds them, its type, and the data a third party needs to verify it. Every compliant token has a container exclusive to itself, in which nothing can be moved, approved, or authorized while the token exists; after the token is burned, only the address [ERC-8423](./eip-8423.md)'s `burnedBy` records for it can move the contents out. The interface is detectable through [ERC-165](./eip-165.md). A container may be an [ERC-6551](./eip-6551.md) token bound account or a contract of another design, provided it meets the same lock.

## Motivation

A gold ring carries two values at once: the work of making it, and the metal it is cast from, recoverable by melting the ring down. An NFT today carries only the first kind of value, decided entirely by what someone else will pay for it. Ways to associate fungible tokens with an NFT already exist, and in nearly all of them the contents can be moved out while the token still exists: the holder, an approved operator, or the issuing contract can empty them, leaving a buyer no guarantee that what they are purchasing still holds what it is supposed to.

[ERC-6551](./eip-6551.md) states the case precisely in its own Security Considerations: a token's bound account holds assets, the holder withdraws them, and only then accepts an offer to sell the now-empty token. The standard notes two mitigations an application could apply, a list of assets expected to remain and a lock that an account implementation could enforce, and leaves both to marketplaces and to implementations choosing to adopt them. This proposal takes up the second and turns it into something a third party can rely on without knowing how a given collection was built: an account implementation can already refuse to treat the holder as a valid signer, which is sufficient to keep assets in without changing ERC-6551 itself, but nothing today lets a marketplace, an indexer, or a wallet tell that lock apart from a merely decorative balance, a figure in metadata that nothing backs. Reading a container's current balance never settles this either way: a balance can be padded with assets nobody promised, or fall under a composition whose constituent's own contract can reduce it, so neither emptiness nor abundance proves what a token was minted with.

A reader who recognizes the code of two contracts, this extension's token contract and the container it names, can treat what `compositionOf` reports as a lower bound the container is holding. Without a common interface for that declaration, the reader falls back to the balance, which says what is there now, never what is bound to stay. This is a question of interoperability between applications that do not share a codebase, which is the question ERCs exist to answer; nothing here depends on how any one collection prices, markets, or issues its tokens.

The two functions of this proposal and `burnedBy` of [ERC-8423](./eip-8423.md) were suggested, in this split, during the discussion of ERC-6551 itself, by an author of that proposal: one interface for the address recorded as a token's owner at the moment it was burned, one for the canonical composition of the assets a token holds and the container that holds them. Taken on their own, each of the two is a plain description, readable by anyone, of a fact already on chain. Inseparability is not a property either standardizes by itself: it is a relation between them, required by this proposal as rules 4 and 5 of the Specification, below.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

Every compliant contract MUST implement [ERC-721](./eip-721.md), [ERC-165](./eip-165.md), and the `IERC721BurnRecord` interface of [ERC-8423](./eip-8423.md). It MUST return `true` from ERC-165 `supportsInterface` when called with `0xd60a6c7e`, the identifier of the interface below, and with `0x43470a89`, the identifier of `IERC721BurnRecord`.

```solidity
/// @dev The ERC-165 identifier for this interface is 0xd60a6c7e
interface IERC721Composition /* is IERC721, IERC721BurnRecord, IERC165 */ {
    /// @param asset  The ERC-20 contract, or 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
    ///               (see ERC-7528) for the chain's native asset
    /// @param amount The declared amount, in the asset's smallest unit. Never zero.
    struct Constituent {
        address asset;
        uint256 amount;
    }

    /// @notice Emitted exactly once for each token, in the transaction that mints it,
    ///         including tokens minted in batch. Carries the same data that
    ///         `compositionOf` and `compositionAccountOf` return for `tokenId`.
    event CompositionDeclared(
        uint256 indexed tokenId,
        address indexed account,
        bytes4 accountType,
        bytes accountData,
        Constituent[] constituents
    );

    /// @notice The declared composition of `tokenId`, fixed at mint.
    function compositionOf(uint256 tokenId) external view returns (Constituent[] memory constituents);

    /// @notice The container that holds the constituents of `tokenId`, its type, and the
    ///         data needed to verify it, all fixed at mint.
    function compositionAccountOf(uint256 tokenId)
        external
        view
        returns (address account, bytes4 accountType, bytes memory accountData);
}
```

1. **Views never revert, and never change after they first answer.** `compositionOf` and `compositionAccountOf` MUST NOT revert for any `tokenId`, minted or not. For a `tokenId` with no declaration, `compositionOf` MUST return an empty array and `compositionAccountOf` MUST return the zero address, `bytes4(0)`, and an empty `bytes`; an empty array MUST be read as "no declaration for this id", never as "declared with zero constituents". A `tokenId` that has never been minted has no declaration, except within the transaction that mints it, where rule 4 requires the declaration to come first. Once a token is minted, both functions MUST return the same values for the rest of the contract's life, including after the token is burned.

2. **Constituents.** Each constituent's `asset` MUST be either an [ERC-20](./eip-20.md) contract or the address `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`, the convention of [ERC-7528](./eip-7528.md), for the chain's native asset. A given `asset` MUST appear at most once among a token's constituents. Every `amount` MUST be nonzero. The constituents returned by `compositionOf`, and carried by `CompositionDeclared`, MUST be ordered by strictly increasing `asset` address. An implementation SHOULD NOT declare a constituent whose balance the container cannot be guaranteed to keep, such as a rebasing token or one whose issuing contract can reduce a holder's balance without a transfer.

3. **The container.** `compositionAccountOf` reports the address holding a token's constituents, together with an `accountType`, the ERC-165 identifier of an interface the container supports and confirms through its own `supportsInterface`, and `accountData`, whatever a reader of that interface needs to verify the container. For a container that is an [ERC-6551](./eip-6551.md) token bound account, `accountType` MUST be `0x6faff5f1`, `accountData` MUST be `abi.encode(implementation, salt)` for that account, and `account` MUST equal the address the canonical ERC-6551 registry computes from them for this chain, this contract, and `tokenId`. A container declared for one token MUST NOT be declared for any other token of the same contract. When a token is minted, the container `compositionAccountOf` reports for it MUST already be a contract (rule 4).

4. **A lower bound, in place before the token exists.** A token MUST NOT be minted until its composition and container are declared, its container is a contract, and the container holds, for every declared constituent, a balance at least equal to the declared `amount`. A declared `amount` MUST NOT exceed the amount the container received for that token in the minting transaction. A contract that receives the token at mint, through `onERC721Received` or otherwise, therefore already finds the declaration, the container, and the declared amounts in place. Nothing in this proposal constrains what the container may hold beyond the declared amounts, before or after the mint, nor how soon after the burn its contents may leave, which can be within the minting transaction itself.

5. **Locked until the burn.** While a token exists, its container MUST NOT let any call, by any account and under any authorization, reduce a constituent's balance in the container below the amount it held when the token was minted, and MUST NOT execute, approve, or otherwise authorize any action whose purpose is to move a constituent out. Once the token is burned, every constituent in its container MUST become movable, and MUST be movable only by the address that `burnedBy` of [ERC-8423](./eip-8423.md) returns for that `tokenId`. On a chain other than the one on which the token was minted, the container MUST NOT authorize any call by anyone.

6. **ERC-6551 containers.** Where the container is a token bound account under [ERC-6551](./eip-6551.md), its `isValidSigner` MUST NOT return the magic value defined there for any `signer` before the token is burned, and MUST return it after the burn only when `signer` equals the address `burnedBy` returns. Its `isValidSignature`, defined by [ERC-1271](./eip-1271.md), MUST NOT return its magic value for any signature before the burn, and MUST return it after the burn only for a signature valid under the address `burnedBy` returns.

7. **One event per token.** `CompositionDeclared` MUST be emitted exactly once for each token, in the transaction that mints it, including tokens minted in batch, and MUST carry the same `account`, `accountType`, `accountData`, and `constituents` that `compositionOf` and `compositionAccountOf` return for that `tokenId` from then on.

8. **No cycles through declared containers.** A token of a compliant contract MUST NOT be transferred or minted to any address that contract has declared, through `CompositionDeclared`, as the container of any token, including the token's own container and the container of any other token, whether that other token still exists or has been burned.

9. **No re-minting.** A `tokenId` that has been burned MUST NOT be minted again by a compliant contract.

10. **Non-upgradeability.** Where a container's logic is implemented as code reachable through a proxy, including an [ERC-6551](./eip-6551.md) token bound account, that code MUST NOT be upgradeable and MUST NOT delegate its logic to code that can later change. The token contract itself is subject to the same requirement: it MUST NOT be upgradeable and MUST NOT delegate its logic to code that can later change.

The table below locates each fact this proposal fixes: which function returns it, which event announces it, and what, if anything, can change it afterward.

| Fact | Read with | Announced by | What changes it |
| --- | --- | --- | --- |
| Declared composition, i.e. the lower bound | `compositionOf` | `CompositionDeclared`, at mint | Nothing: fixed at mint (rule 4) |
| Container, its type, and the data to verify it | `compositionAccountOf` | `CompositionDeclared`, at mint | Nothing: fixed at mint |
| Who owned the token when it was burned | `burnedBy` ([ERC-8423](./eip-8423.md)) | `Transfer` to the zero address ([ERC-721](./eip-721.md)) | Only the burn itself, once, since re-minting is forbidden (rule 9) |
| The container's current contents | The constituents' own contracts: `balanceOf` for an ERC-20, the address's balance for the native asset | No event of this proposal | Unsolicited deposits, actions by a constituent's issuer (freezes, balance reductions), the burner's withdrawals after the burn; nothing emits an event for the native asset |

## Rationale

### Why a container, and why it must be exclusive and locked

A composition is only as good as the guarantee that it stays where it was declared. Rule 5 is the proposal's central requirement: it is what turns a declared figure into a lower bound a reader can rely on, rather than a number that happened to be true once. Rule 3's exclusivity (one container, one token) is what makes rule 5 checkable at all: a container shared between tokens could be drained for one and refilled for another without any single token's declaration becoming false, so the lower bound would hold for the collection without holding for any one piece a buyer is looking at. This is also why a shared design such as [ERC-4626](./eip-4626.md), in which every holder's shares are claims on one common balance, cannot serve as a container under this proposal, however well suited it is to its own purpose.

### Why the container is not constrained to ERC-6551

[ERC-6551](./eip-6551.md) is the proposal's working example throughout, and the one its reference implementation uses, but `accountType` and `accountData` exist precisely so the lock in rule 5 can be met by a container of another design: a purpose-built minimal contract holding only the native asset and ERC-20 tokens, for instance, can satisfy every rule above without ERC-6551's broader surface. Fixing the interface to one container standard would narrow the guarantee to collections willing to give every token a full ERC-6551 account; naming the type and handing over verification data lets a reader recognize whichever container design a given collection chose, without this proposal picking one for it.

### A lower bound, not an equality

Rule 4 does not require the container's balance to equal the declared amounts at every later moment, only that they are met before the token exists and that no call to the container can take the balance below them afterward (rule 5). Two reasons rule out an equality invariant. First, transfers on Ethereum are permissionless: nothing stops a third party from sending more of a constituent asset to the container after mint, and a rule demanding exact equality would be violated by a deposit nobody authorized and nobody can undo. Second, and more fundamentally, a constituent whose contract can freeze, seize, or otherwise reduce a holder's balance places that balance outside this proposal's reach regardless of the container: a reader checking the lower bound compares the container's current balance against the declared amount for exactly this reason, and rule 2's recommendation against declaring such assets exists because no container design can make their lower bound dependable. The lower bound is therefore a property this proposal can guarantee about the container's behavior, not a promise about every asset's behavior, which no interface at this layer can make.

Rule 4 places the moment at the mint rather than at the end of the minting transaction, for two reasons. A contract that receives the token, through `onERC721Received` or through any call made later in the same transaction, can act on it before the transaction ends, and should find it backed. And a recipient that burns the token and moves its contents out within that same transaction ends it below the declared amounts, which is the release rule 5 allows, not a broken lower bound. Requiring the declaration and the funding before the mint covers both cases with a single moment a reader can check. This timing was made precise during the discussion of the proposal.

### Constituents: native asset and ERC-20, strictly ordered

Limiting constituents to the native asset, under the [ERC-7528](./eip-7528.md) convention, and [ERC-20](./eip-20.md) tokens keeps the interface's reach to assets whose balance in an address is a single, unambiguous number; other asset classes raise questions (partial ownership, per-id state) this proposal does not need to answer to make its central claim. Ordering constituents by strictly increasing address, rather than leaving the order to the implementation, gives two contracts that declare the same assets in the same amounts an identical encoding, so a reader comparing declarations, or recomputing a hash of one, does not have to normalize an arbitrary order first; it also rules out duplicate entries for the same asset without a separate check, since two entries for one address cannot both satisfy strictly increasing order.

### No reverts, and an empty composition is not a declared zero

A view that reverts for some inputs is hostile to on-chain composition, since its failure cannot be told apart from a contract that does not implement the function; ERC-8423 rejects reverting for `burnedBy` for the same reason, and its rule against reverting is the model for rule 1. Answering with empty values instead needs no additional state, and reading them as "no declaration" follows the same one-way logic as ERC-8423, where `address(0)` proves nothing. The alternative, treating an empty answer as "declared, with zero constituents," would make an id this proposal was never applied to look like a declared one, which is the reading rule 1 forbids.

### One event, including batch mints

Rule 7 exists because a contract cannot read its own past logs, and a reader building an off-chain index needs exactly one authoritative moment per token to record the same facts the view functions expose, so that a replay of the logs and a live call agree. ERC-721 allows a contract to create any number of tokens during its own construction without emitting `Transfer`, and [ERC-2309](./eip-2309.md) announces such a batch with a single event for a whole range of ids; this proposal's event is independent of both mechanisms and must still be emitted once per id regardless of how the mint itself is batched, which is why the event, rather than `Transfer`, is what a reader should rely on for this proposal's own facts.

### No cycles through declared containers

Rule 8 closes a gap that an exclusive, locked container would otherwise leave open within a single collection: without it, two tokens of the same contract could each be transferred into the other's container, each becoming reachable only through the other, with neither ever burned. The rule is deliberately narrower than it could be. It stops every cycle a single compliant contract could create among its own declared containers, including a token entering a container declared for a token minted later, which is not itself a cycle; it does not reach a cycle formed through a container that is not declared by this contract, nor through another account the same token separately holds outside this mechanism, nor across two different collections. Closing those wider cases would require knowledge this contract cannot have about other contracts' declarations, and is left to the implementations and marketplaces that choose to look for them, consistently with how [ERC-6551](./eip-6551.md) already leaves the comparable cross-collection case to applications.

### No re-minting

An id that could be minted again after being burned would let whoever controls the next mint become the only party able to open the container of the previous occupant of that id, since `burnedBy` of [ERC-8423](./eip-8423.md) reports only the most recent burn. Rule 9 keeps the address rule 5 names as able to open a container stable for as long as that container can be opened at all; a collection that reuses deterministic identifiers for unrelated purposes cannot be compliant with this proposal for exactly this reason. ERC-8423 itself allows re-minting, and its Security Considerations advise consumers that read the record after the burn to check whether the token contract can re-mint; for a contract compliant with this proposal, rule 9 settles that check once, for all of its tokens.

### Non-upgradeability of the container and of the token contract

Rule 10 covers two contracts for one reason: whichever of the two can change its own logic after the fact is the one a reader's verification does not actually constrain. An upgradeable container defeats rule 5 directly, by replacing code that refuses every pre-burn call with code that does not. An upgradeable token contract defeats the same rule indirectly, since the container opens for whoever the token contract's `burnedBy` names: an upgrade to the token contract alone, leaving the container's code and the declared data untouched, can rewrite what `burnedBy` reports, move a token without an honest burn, or alter a declaration a reader believed was fixed at mint. A reader therefore has to recognize two pieces of code, not one, and this rule is what makes recognizing the second one sufficient. This requirement surfaced during review of the reference implementation, when two independent readers of the discussion thread pointed out that the container-side rule alone left the token contract's own upgradeability unaddressed; a regression test confirmed that an upgrade of the token contract alone, with no change to the container, could open a container before any burn.

### Relationship to ERC-8423

This proposal's lock is written as a relation to `burnedBy`, not as a restatement of it: rule 5 names the address [ERC-8423](./eip-8423.md) records, and this proposal adds no competing notion of who may act for a burned token. The owner at the time of the burn is a standard of its own for the reason ERC-8423's Motivation gives: a custodian that performs the burn can record the owner itself, but a custodian that does not has no standard place to look. A container under this proposal is a custodian of the second kind: it holds a token's declared assets and takes no part in the burn. Splitting the two lets either be adopted, or reviewed, on its own; requiring one from the other through `requires` is what keeps the combination binding rather than advisory.

### Prior art

Several standards associate fungible assets with an NFT, and each makes its own choice on the points this proposal fixes, so the comparison is worth drawing precisely.

[ERC-6551](./eip-6551.md) already lets an NFT hold assets in an account assigned to it, and its own Security Considerations describe the withdrawal-before-sale scenario this proposal is built to close; by default, nothing in that standard stops the holder from emptying the account at any time, which is a deliberate design choice the standard leaves to implementations and marketplaces, not a gap in the text. [ERC-998](./eip-998.md) and [ERC-7401](./eip-7401.md) let one token hold others and expose the tokens it holds, but both permit removing or reassigning a child token without destroying the parent, so neither ties possession to a burn.

[ERC-4353](./eip-4353.md) lets wallets and marketplaces read the amount of fungible tokens bound to an NFT, and the implementation it suggests already deposits them at mint and gives them back only at the burn. It leaves that pattern to the implementation, allows variants that deposit and withdraw at any time, and notes in its own Security Considerations that the amount it reports is unreliable unless a lock is enforced; this proposal makes that lock a requirement, for several assets per token. [ERC-7527](./eip-7527.md) ties an NFT to fungible currency at the interface level, through a pair of functions that create the token as currency comes in and destroy it as currency goes out; the amount is computed by a function at each of those moments rather than fixed for each token at mint, and every token's currency is handled by a single contract serving the whole collection. [ERC-3589](./eip-3589.md) comes closest among merged standards: its reference implementation already gives assets back only by burning the token that holds them, and has done so since 2021. It differs from this proposal in three respects that matter to a reader verifying a lower bound: the assets of every token sit in one shared contract rather than in a container exclusive to each token, so a reader cannot check one token's lower bound independently of the others; the composition is recoverable only from the token id's construction or from an event, not from a view function; and exiting only through the burn is a property of its example implementation, not a requirement any compliant contract must meet. [ERC-8414](./eip-8414.md), for a purpose unrelated to this one, requires a distinct account per token whose funds leave only through the paths that standard defines, and recommends a locked ERC-6551 account for it: the same way of writing a lock as a rule on the result that rule 5 uses. A further proposal, still open as a pull request and not yet merged into the ERCs repository at the time of writing, defines a single native-asset value redeemable only by burning the token that carries it, which is the same inseparability this proposal requires, but for native value alone, with no requirement that the amount stay fixed after mint or that it be held apart from other tokens' value, both of which this proposal's rules 2 and 4, together with rule 3's exclusivity, make binding wherever this extension is implemented.

### The canonical-accounting objection

The most direct objection to standardizing any of this is that whether a container truly backs a declared figure is an application-level question, answerable by looking at the container's own balance, and not something that calls for a new interface. The answer is that a balance alone cannot distinguish a lower bound a reader can rely on from a number that happens to match it today: without a common way to learn which address is the declared container, what kind of container it is, and what `burnedBy` would return for its token, a marketplace, an indexer, or a wallet has no way to tell a locked, exclusive container from an ordinary account a holder could empty before the next block, and so it reads the balance, which answers what is there now, not what the contract has bound itself to keep there. Standardizing the three facts of the Specification, and the single relation (rule 5) that ties them together, is what an application-level reading of a balance cannot reconstruct on its own.

### Cost

Measured on a reference implementation, with the base transaction cost of 21,000 gas included: minting a token with one constituent costs roughly 261,000 gas with an ERC-6551 container against 69,000 for a plain ERC-721 mint, with the difference growing to roughly 412,000 and 832,000 gas for three and eight constituents; a purpose-built minimal container instead of an ERC-6551 account adds a further increase, close to double, because it pays for its own contract creation at every mint. Reading a token's composition costs from roughly 7,600 gas for one constituent to roughly 40,600 for eight; reading its container costs roughly 3,000 gas regardless of composition size. A transfer costs roughly 2,700 gas more than a plain ERC-721 transfer, the cost of checking rule 8 against the declared containers. `CompositionDeclared` alone adds roughly 4,700 to 5,800 gas per token for one to three constituents, on top of the cost already counted in minting.

## Backwards Compatibility

This proposal adds two view functions and one event to [ERC-721](./eip-721.md), and builds on [ERC-8423](./eip-8423.md) without altering either; it introduces no incompatibility with contracts that do not implement it. Because every rule above depends on facts fixed when a token is minted, a contract can only be compliant for tokens it mints after adopting this proposal: there is no retrofit that could make an already-minted token's assets meet rule 4's lower bound or rule 5's lock after the fact, since rule 4 ties the declaration, the container, and the declared amounts to the moment a token is minted, and for tokens minted before adoption that moment has already passed.

## Test Cases

The cases below use only what the Specification requires. Alice, Bob, and Carol are externally owned accounts, `H` is a contract that holds tokens, and every case starts from a freshly deployed, compliant contract with one or more constituents declared at mint.

| # | Scenario | Expected | Rules |
| --- | --- | --- | --- |
| 1 | A token is minted to Alice with a declared composition of several constituents | `compositionOf` returns exactly those constituents, ordered by strictly increasing asset address | 2 |
| 2 | The same token | `compositionAccountOf` returns a container address, its `accountType`, and `accountData` consistent with that type | 3 |
| 3 | A token is minted to a contract `H`, which reads it from inside `onERC721Received` | `H` already finds the composition and the container declared, the container already a contract, and its balance of each constituent at least the declared amount | 3, 4 |
| 4 | A `tokenId` that was never minted | `compositionOf` returns an empty array, `compositionAccountOf` returns the zero address, `bytes4(0)`, and empty data | 1 |
| 5 | Any `tokenId`, minted or not | Neither function reverts | 1 |
| 6 | A token is minted, then burned | Both functions return, after the burn, the same values they returned before it | 1 |
| 7 | A token is minted | `CompositionDeclared` is emitted exactly once, in the minting transaction, with the same `account`, `accountType`, `accountData`, and `constituents` the two functions return afterward | 7 |
| 8 | Several tokens are minted in the same transaction through a batch-minting mechanism that emits no per-token `Transfer` | `CompositionDeclared` is still emitted once for each token minted, with data matching the two functions for each | 7 |
| 9 | While a token exists, its owner, an approved operator, the token contract itself, and an unrelated account each attempt to move, approve, or authorize moving a constituent out of its container | None of these calls reduces the container's balance of any constituent below the amount held when it was minted, and none leaves a standing approval | 5 |
| 10 | The same attempts, made on a chain other than the one on which the token was minted | None is authorized | 5 |
| 11 | The token's container is an ERC-6551 token bound account; its `isValidSigner` and `isValidSignature` are queried for the owner, for an approved operator, and for the token contract, before the token is burned | Neither function returns its magic value for any of them | 6 |
| 12 | Alice burns the token | `burnedBy` (ERC-8423) now returns Alice; every constituent in the container can be moved, and moved only by Alice | 5 |
| 13 | After the burn in the previous case, the container is an ERC-6551 account; `isValidSigner` and `isValidSignature` are queried again | Both return their magic value for Alice, and for no one else | 6 |
| 14 | A third party sends an additional amount of a constituent asset to a token's container after it is minted, then the token is burned | The surplus is included in what the recorded address can move out; the declared amount is unaffected | 4, 5 |
| 15 | Alice transfers a token to Bob, who later burns it | `burnedBy` returns Bob, and only Bob can move the container's constituents after the burn; Alice cannot | 5 |
| 16 | Alice approves Carol for a token, and Carol burns it on Alice's behalf | `burnedBy` returns Alice, not Carol; only Alice can move the container's constituents afterward | 5 |
| 17 | A token is minted to a contract `H`, which later burns it | `burnedBy` returns `H`; only `H` can move the container's constituents afterward | 5 |
| 18 | A token is minted to a contract `H` that, inside `onERC721Received`, burns it and moves every constituent out of its container | The mint succeeds; `burnedBy` returns `H`, `H` holds the constituents, the minting transaction ends with the container below the declared amounts, and both functions still return the declaration | 1, 4, 5 |
| 19 | A token is transferred or minted to the address of its own container | The transfer or mint is rejected | 8 |
| 20 | A token is transferred or minted to the address declared as the container of a different token of the same contract, whether that other token is still live or has already been burned | The transfer or mint is rejected | 8 |
| 21 | A token is minted whose declared container is the predicted address of a container that a later mint, in the same contract, will declare for a different token | The earlier mint succeeds; the later mint, naming the earlier token's container as its own, is rejected | 3 |
| 22 | A token is burned, then an attempt is made to mint the same `tokenId` again | The mint is rejected, and `burnedBy` for that id continues to report the original burner | 9 |
| 23 | A container is implemented as an ERC-6551 account behind the canonical registry's proxy, or as a token contract behind an upgradeable proxy | A reader that inspects the implementation code reachable from the proxy finds it to be neither upgradeable nor delegating to code that can change | 10 |

## Reference Implementation

The implementation below builds on the reference implementation of [ERC-8423](./eip-8423.md), `ERC721BurnRecord`, and keeps a token's composition and container in contract state, written once per token and read by the two view functions. It covers rules 1 through 4, 7, 8, and 9; minting, the lock itself, and the non-upgradeability of rule 10 are left to the contract that creates each container, shown afterward for an ERC-6551 container. A mint path that does not go through `_update`, such as a batch mint during construction announced under ERC-2309, has to make the same checks itself: it declares every token before the batch and refuses a receiver that `_containerToken` reports as a declared container.

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC721BurnRecord} from "./ERC721BurnRecord.sol"; // reference implementation of ERC-8423
import {IERC721Composition} from "./IERC721Composition.sol";

/// @title Reference implementation of the ERC-721 composition extension
/// @notice Keeps the declared composition and the container of each token in state. The
///         state is the source of truth, the two view functions read it, and
///         {CompositionDeclared} announces it once per token.
abstract contract ERC721Composition is ERC721BurnRecord, IERC721Composition {
    struct Declaration {
        address account;
        uint96 length;
    }

    mapping(uint256 tokenId => Declaration) private _declarations;
    mapping(uint256 tokenId => mapping(uint256 index => Constituent)) private _constituents;
    mapping(address account => uint256 tokenIdPlusOne) private _containerTokens;

    error CompositionAlreadyDeclared(uint256 tokenId);
    error CompositionNotDeclared(uint256 tokenId);
    error EmptyComposition();
    error UnsortedConstituent(uint256 index);
    error ZeroAmountConstituent(uint256 index);
    error InvalidAccount(address account);
    error ContainerAlreadyDeclared(address account, uint256 containerTokenId);
    error TransferToDeclaredContainer(uint256 tokenId, uint256 containerTokenId);
    error BurnedTokenRemint(uint256 tokenId);

    /// @inheritdoc IERC721Composition
    function compositionOf(uint256 tokenId) public view virtual returns (Constituent[] memory constituents) {
        uint256 length = _declarations[tokenId].length;
        constituents = new Constituent[](length);
        mapping(uint256 => Constituent) storage stored = _constituents[tokenId];
        for (uint256 i; i < length; ++i) {
            constituents[i] = stored[i];
        }
    }

    /// @inheritdoc IERC721Composition
    function compositionAccountOf(uint256 tokenId)
        public
        view
        virtual
        returns (address account, bytes4 accountType, bytes memory accountData)
    {
        account = _declarations[tokenId].account;
        if (account != address(0)) {
            (accountType, accountData) = _accountTypeAndData(tokenId);
        }
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC721Composition).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @dev Type and verification data of the container of a declared token. Constant for
    ///      each token: implementations derive them from immutable parameters.
    function _accountTypeAndData(uint256 tokenId) internal view virtual returns (bytes4, bytes memory);

    /// @dev Whether `account` is a container this contract has declared, and for which token.
    function _containerToken(address account) internal view returns (bool declared, uint256 tokenId) {
        uint256 tokenIdPlusOne = _containerTokens[account];
        declared = tokenIdPlusOne != 0;
        if (declared) tokenId = tokenIdPlusOne - 1;
    }

    /// @dev Records the composition and the container of `tokenId` and emits
    ///      {CompositionDeclared}. The caller ensures the container holds at least the
    ///      declared amounts before the token is minted.
    function _declareComposition(uint256 tokenId, address account, Constituent[] memory constituents)
        internal
        virtual
    {
        if (_declarations[tokenId].account != address(0)) revert CompositionAlreadyDeclared(tokenId);
        if (account == address(0) || account.code.length == 0) revert InvalidAccount(account);
        uint256 holder = _containerTokens[account];
        if (holder != 0) revert ContainerAlreadyDeclared(account, holder - 1);
        uint256 length = constituents.length;
        if (length == 0) revert EmptyComposition();

        mapping(uint256 => Constituent) storage stored = _constituents[tokenId];
        address previous = address(0);
        for (uint256 i; i < length; ++i) {
            Constituent memory constituent = constituents[i];
            if (constituent.asset <= previous) revert UnsortedConstituent(i);
            if (constituent.amount == 0) revert ZeroAmountConstituent(i);
            stored[i] = constituent;
            previous = constituent.asset;
        }
        _declarations[tokenId] = Declaration(account, uint96(length));
        _containerTokens[account] = tokenId + 1;

        (bytes4 accountType, bytes memory accountData) = _accountTypeAndData(tokenId);
        emit CompositionDeclared(tokenId, account, accountType, accountData, constituents);
    }

    /// @dev Rejects a transfer or a mint to any declared container, a mint of an undeclared
    ///      token, and a mint of a previously burned token. A mint that bypasses this
    ///      function, such as a batch mint during construction, makes these checks itself,
    ///      with {_containerToken}.
    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        if (to != address(0)) {
            uint256 holder = _containerTokens[to];
            if (holder != 0) revert TransferToDeclaredContainer(tokenId, holder - 1);
            if (_ownerOf(tokenId) == address(0)) {
                if (_declarations[tokenId].account == address(0)) revert CompositionNotDeclared(tokenId);
                if (burnedBy(tokenId) != address(0)) revert BurnedTokenRemint(tokenId);
            }
        }
        return super._update(to, tokenId, auth);
    }
}
```

An ERC-6551 container implements the lock of rules 5 and 6 by withholding the magic values of `isValidSigner` and `isValidSignature` until a burn record exists for its token, and granting them only to the address that record names:

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IERC721BurnRecord} from "./IERC721BurnRecord.sol"; // ERC-8423

/// @title ERC-6551 account that stays locked until its token is burned
/// @notice While the token exists nobody is a valid signer; after the burn, only the
///         address that ERC-8423's burnedBy returns for it.
contract LockedERC6551Account /* is IERC6551Account, IERC6551Executable, IERC1271, IERC165 */ {
    function isValidSigner(address signer, bytes calldata) external view returns (bytes4) {
        return _isValidSigner(signer) ? bytes4(keccak256("isValidSigner(address,bytes)")) : bytes4(0);
    }

    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        address burner = _burner();
        if (burner != address(0) && SignatureChecker.isValidSignatureNow(burner, hash, signature)) {
            return bytes4(keccak256("isValidSignature(bytes32,bytes)"));
        }
        return bytes4(0xffffffff);
    }

    /// @dev The address `burnedBy` names for this account's token, read from the token
    ///      contract and the identifying data this proxy carries; zero while the token
    ///      exists, if it was never minted, on another chain, or if the call fails.
    function _burner() internal view returns (address burner) {
        // chainId, tokenContract and tokenId are read from this proxy's own appended data,
        // as specified by ERC-6551; on another chain this reports no burner at all.
    }

    function _isValidSigner(address signer) internal view returns (bool) {
        address burner = _burner();
        return burner != address(0) && signer == burner;
    }
}
```

## Security Considerations

**This proposal verifies code, not intentions.** The two functions name a container and the rules that are supposed to govern it; they do not themselves prove that the code at that address enforces rule 5. A reader has to recognize two pieces of code, the container's and the token contract's, as implementing this proposal faithfully, the same way a reader of [ERC-8423](./eip-8423.md) already has to trust the token contract's `burnedBy`. Recognizing arbitrary code in general is not solvable at this layer; a reader limited to a known, audited set of container and token-contract implementations can do it in practice, and one that is not should treat an unrecognized container as unverified, not as compliant.

**Signature consumers.** A contract that accepts [ERC-1271](./eip-1271.md) signatures from a token's container as authorization for something outside this proposal inherits the same lock: before a burn, no signature should validate, and after, only one from the recorded burner should. A consumer that queries `isValidSignature` without also checking the token's burn status may accept a signature from an account whose code has not yet begun to apply rule 6, for instance during a transitional upgrade on an implementation that does not itself meet rule 10.

**The lower bound depends on the constituent, not only on the container.** Rule 2 recommends against declaring an asset whose own contract can reduce a holder's balance without a transfer, such as a rebasing or freezable token, and rule 4 bounds only what the container held when the token was minted. A container meeting every rule above still cannot keep such an asset's balance from falling if its issuer acts on it; a reader checking the lower bound for a token with such a constituent is checking a number the container cannot itself guarantee.

**An intermediary is named, not the person behind it.** When a contract holds and burns a token on someone else's behalf, `burnedBy`, and therefore the address able to open the container, names that contract, following the same rule ERC-8423 states for itself. If that contract has no function allowing it to move the container's constituents out again, they remain reachable only by calling that contract, and are effectively stuck if it does not expose that path; wallets and marketplaces that burn on a holder's behalf should ensure the holder, not an intermediary contract, performs the burn directly, or that the intermediary can relay a later withdrawal.

**Cycles this proposal does not close.** Rule 8 rejects every cycle a single compliant contract could create among the containers it has itself declared. It does not reach a cycle formed by sending a token into an account that is not declared as any token's container by this contract, by an account the token separately holds through some other mechanism, or by containers declared across two different collections. These remain possible, and are left to implementations and marketplaces that want to detect them, consistently with how [ERC-6551](./eip-6551.md) already leaves the comparable application-level case to them.

**Assets sent to a container's address before its token is minted.** Because an ERC-6551 account's address is computed deterministically from its eventual token id, an address can receive assets before any token names it as a container. Once the corresponding token is minted and that address is declared, those assets become part of the container's balance and, unless separately declared as part of that token's composition, are surplus under rule 4, reachable by the same address rule 5 names once the token is burned.

**Surplus can include assets nobody wants attributed to a token.** Because transfers to a container cannot be refused, a container's balance can include an asset its own token's composition never declares, sent by a third party for any reason, including to make a token appear to hold more than it was minted with. A reader relying on `compositionOf` rather than on a container's raw balance is not misled by this, but a party relying on the balance alone could be.

**The token contract's code is as load-bearing as the container's.** Because the container opens for whoever the token contract's `burnedBy` names, an honest container paired with a token contract that misreports burns, or that can be upgraded to do so, offers no guarantee at all; rule 10's requirement on the token contract exists for this reason, and a reader who verifies only the container's code while trusting the token contract by name alone has verified half of what this proposal requires.

**Reading a long composition has a cost, and a cost limit of its own.** A contract reading another token's `compositionOf` pays gas proportional to the number of constituents, and a contract copying the returned `accountData` into its own storage or into a further external call should bound how much it is willing to copy, since nothing in this proposal limits how large a compliant implementation's `accountData` may be.

**Nothing here addresses the governance of the chain itself.** A protocol-level change able to move funds without going through any account's authorization, however unlikely, is outside what a contract-level lock can prevent; this proposal's guarantees hold within the ordinary operation of the chains it is deployed on, not against changes to the chains themselves.

**Non-upgradeability has to be checked at the level of reachable code, not of the address alone.** An address whose code never changes directly can still be upgradeable if it is a proxy whose implementation address can be redirected, including the common [ERC-1967](./eip-1967.md) pattern; a reader applying rule 10 needs to follow a proxy to the implementation it currently points to, confirm that implementation is itself immutable, and recognize that a legitimate upgrade mechanism elsewhere in the same codebase does not, by itself, mean every contract this proposal depends on shares it.

**Chain reorganizations are outside this proposal's reach.** Like any other on-chain fact, a mint, a burn, or a transfer this proposal depends on can be reorganized away before it is final by whatever finality rule the deployed chain uses; a reader treating a recent event as settled before that point is exposed to the same risk it would face reading any other recent transaction.

**The interface identifier does not cover the return types.** ERC-165 identifiers are derived from function names and argument types only. A contract that declares `0xd60a6c7e` but returns something other than what `compositionOf` and `compositionAccountOf` specify would pass detection while breaking every caller that relies on the declared shape. This is a property of ERC-165 in general: implementations must match the interface above exactly, return types included.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
