---
title: ERC-721 Burn Record Extension
description: An ERC-721 extension that lets contracts read the address recorded as the owner of a token when it was burned
author: Antonio Ferraioli (@antferr)
discussions-to: https://ethereum-magicians.org/t/erc-721-burn-record-extension/29732
status: Draft
type: Standards Track
category: ERC
created: 2026-09-24
requires: 165, 721
---

## Abstract

This proposal extends [ERC-721](./eip-721.md) with one view function, `burnedBy`, through which other contracts can read the address recorded as the owner of a token when it was burned: the `from` of the `Transfer` event emitted by the burn. It returns `address(0)` when no record exists, whether the token still exists, was never minted, or was burned before the record existed. The interface is detectable through [ERC-165](./eip-165.md), and its guarantee runs one way: a non-zero answer proves the burn and names that owner, while zero proves nothing.

## Motivation

Burning an ERC-721 token emits a `Transfer` event to `address(0)`, and off-chain indexers record who burned it. Logs are not accessible from the EVM, so a contract that has to act on that fact cannot simply read it.

This matters when the burn and the claims that depend on it come apart:

- **Several independent custodians.** More than one contract holds value on behalf of the same token, for example an account that holds its assets and a separate contract that accrues rewards to its id. Only one of them can take part in the burn. The others learn about it later, each in its own transaction, and still have to decide whom to release their share to.
- **Value that arrives after the burn.** A contract that burns a token and pays out in one step can only pay what exists at that moment. Value that reaches a contract afterwards, such as rewards settled late, still has to go to someone, and the contract holding it took no part in the burn.

When a single contract holds everything and performs the burn itself, it can read the owner just before burning, and this proposal adds nothing. The need starts where that contract is not the only one involved.

A custodian that performs the burn can record the owner itself; a custodian that does not has no standard place to look. This proposal keeps that fact once, in the token contract, where every burn happens, so that any contract can read it.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

Every compliant contract MUST implement ERC-721 and the following interface, and MUST return `true` from ERC-165 `supportsInterface` when called with `0x43470a89`.

```solidity
/// @dev The ERC-165 identifier for this interface is 0x43470a89
interface IERC721BurnRecord /* is IERC721, IERC165 */ {
    /// @notice Get the address recorded as having burned a token
    /// @dev Returns address(0) when no burn record exists for `tokenId`
    /// @param tokenId The token to query
    /// @return The address that burned the token, or address(0)
    function burnedBy(uint256 tokenId) external view returns (address);
}
```

The semantics of `burnedBy` are as follows:

1. `address(0)` means "no burn record for this `tokenId`". It does not mean "not burned".
2. The recorded address MUST equal the `from` of the `Transfer` event emitted for the burn, so a contract reading this function and an indexer reading the logs never disagree.
3. Burned means the token no longer exists and a `Transfer` to `address(0)` was emitted. A token held by a conventionally dead address still has an owner and is out of scope.
4. While a token exists, `burnedBy` MUST return `address(0)`. A contract that re-mints a token id therefore reports its most recent burn only.
5. Every burn that occurs while the contract supports this interface MUST produce a record, which `burnedBy` MUST return until the token id is minted again. Only burns that occurred before the contract supported this interface MAY lack a record.
6. `burnedBy` MUST NOT revert, whatever the `tokenId`.
7. A non-zero answer is a guarantee and `address(0)` proves nothing: consumers MUST treat `address(0)` as the absence of authorization.

## Rationale

### A getter alongside the event

The contract's state is the source of truth for whether a token was burned and who owned it at that moment. `burnedBy` is how other contracts read that state, and the `Transfer` to `address(0)` announces the change to everyone else. Rule 2 guarantees that the two views never disagree. This proposal speaks of state rather than of a stored value because of rule 4: the answer also depends on whether the token exists.

ERC-721 already draws this line. Ownership changes, burns included, are announced by `Transfer`, and the current owner is still exposed through `ownerOf` and `balanceOf`, because contracts cannot read logs. Its rationale applies the same test the other way round: it accepted metadata that other contracts could not consume at the time, because no on-chain application was expected to query it. The burner is the opposite case, since the consumers this proposal has in mind are contracts. [ERC-7634](./eip-7634.md) and [ERC-6672](./eip-6672.md) make the same choice for their own facts, emitting an event and exposing a getter for the same state.

### The owner, not the caller

The record is the `from` of the burn's `Transfer`, that is, the owner at the time of the burn, not the account that called the burn function. When an approved operator burns a token, the record names the owner. This is what keeps the record useful in mediated flows: when a redemption contract burns a token on the holder's behalf, a record based on the caller would name the redemption contract itself, which tells every other custodian nothing. It is also the address the log carries, so the record can be checked against the log.

### One address, and a guarantee that runs one way

Alternatives considered and rejected:

- A pair `(bool burned, address burner)`. For tokens burned before a contract adopted this interface, the flag could only come from a heuristic or from data supplied at deployment, and the contract could vouch for neither.
- A separate `isBurned` function. The same problem, with more surface.
- Reverting for tokens without a record. A view that fails is hostile to on-chain composition, and its failure cannot be told apart from a contract that does not implement the function.
- A three-state enumeration. It overlaps with `ownerOf` and still does not return the burner.
- A hook that notifies custodians at burn time. The token contract would have to know every custodian in advance, while custodians are independent of it and of each other; and ERC-721 does not even include burning in its specification.

Returning a single address keeps existence where ERC-721 already put it, in `ownerOf`. Read together:

| `ownerOf` | `burnedBy` | Meaning |
|---|---|---|
| returns | `address(0)` | Live token |
| reverts | non-zero | Burned; the record names the owner at the time of the burn |
| reverts | `address(0)` | Never minted, or burned before the record existed |
| returns | non-zero | Forbidden by rule 4 |

User interfaces that show this record should present `address(0)` as "no record", never as evidence that the token never existed.

### Re-minting is allowed

This proposal does not constrain minting. Minting is outside the scope of ERC-721, a rule against reusing ids could not be verified from outside the contract, and it would rule out bridges that re-create the same id. The price is permanence: `burnedBy` reports the most recent burn only and is not a receipt. The consequences for consumers are in the Security Considerations.

### Deliberately left out: time and transaction

The hash of the burning transaction is not available to the EVM, so it cannot be recorded. The time of the burn could share the storage slot of the address, so cost is not the argument; scope is. It can be proposed as a separate optional interface if there is demand. Burn history and links to transactions remain the job of indexers.

### Receipt proofs do not replace the record

Recent block hashes are readable from state since [EIP-2935](./eip-2935.md), and older ancestors can be reached with more effort through beacon chain roots, as that proposal itself notes. A contract can therefore verify, against a proof supplied by someone else, that a given `Transfer` was emitted. This does not replace the record. The proof has to be produced off-chain and passed to the contract, and it costs far more than a view call. Above all, a proof speaks about a past block, and the answer a consumer needs is about the present: the proof shows that a burn happened, but not that the id was not minted and burned again since. The contract's state is the only source that answers for the present.

### Cost

In the reference implementation the record costs one new storage slot per burn, 22,479 gas measured with cold storage and before refunds, and nothing on mint, because `burnedBy` checks whether the token exists instead of clearing the record when an id is minted again.

## Backwards Compatibility

This proposal only adds a view function to ERC-721 and changes none of its behaviour, so it introduces no incompatibility. A contract that adopts it after some of its tokens were already burned, for example through an upgrade, has no record for those burns: `burnedBy` returns `address(0)` for them, which is the third row of the table in the Rationale and is allowed by rule 5. Only new or upgradeable contracts can adopt this interface.

## Test Cases

The cases below use only what the Specification requires. Alice, Bob and Carol are externally owned accounts, `H` is a contract that holds tokens, and each case starts from a fresh token contract.

| # | Scenario | Expected | Rules |
|---|---|---|---|
| 1 | Token 1 is minted to Alice and never burned | `burnedBy(1)` returns `address(0)` | 4 |
| 2 | Token id 42 was never minted | `burnedBy(42)` returns `address(0)` | 1 |
| 3 | Any `tokenId`, in any state | `burnedBy` does not revert | 6 |
| 4 | Alice burns token 1 | `burnedBy(1)` returns Alice | 2, 5 |
| 5 | Alice transfers token 7 to Bob, then Bob burns it | `burnedBy(7)` returns the `from` of the burn's `Transfer` log, that is Bob | 2 |
| 6 | Alice approves Carol for token 1, then Carol burns it | `burnedBy(1)` returns Alice, not Carol | 2 |
| 7 | Alice approves Carol for all her tokens, then Carol burns token 1 | `burnedBy(1)` returns Alice | 2 |
| 8 | The contract burns token 1 under its own logic, without a call from the owner or an operator | `burnedBy(1)` returns Alice | 2, 5 |
| 9 | Token 1 is minted to `H`, and `H` burns it | `burnedBy(1)` returns `H` | 2 |
| 10 | Alice transfers token 1 to `0x000000000000000000000000000000000000dEaD` | `ownerOf(1)` returns that address, `burnedBy(1)` returns `address(0)` | 3, 4 |
| 11 | Token 1 moves from Alice to Bob, then to Carol | `burnedBy(1)` returns `address(0)` after each transfer | 4 |
| 12 | Alice burns token 1, then token 1 is minted to Bob | `burnedBy(1)` returns `address(0)` | 4 |
| 13 | As in case 12, then Bob burns token 1 | `burnedBy(1)` returns Bob | 4, 5 |
| 14 | Any sequence of mints, transfers, approvals, burns and re-mints | No existing token has a non-zero record, and every burned token not minted again returns the `from` of its last burn | 2, 4, 5 |
| 15 | Interface detection | `supportsInterface` returns `true` for `0x43470a89`, `0x80ac58cd` and `0x01ffc9a7`, and `false` for `0xffffffff`; `0x43470a89` is the selector of `burnedBy(uint256)` | ERC-165 |

## Reference Implementation

The implementation below extends OpenZeppelin Contracts 5.x, in which every burn goes through `_update`. It writes the record only on burns and lets `burnedBy` check whether the token exists, so minting pays nothing extra.

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721BurnRecord} from "./IERC721BurnRecord.sol";

/// @title Reference implementation of the ERC-721 burn record extension
/// @notice Lets other contracts read which address burned a token. The contract's state
///         is the source of truth, {burnedBy} is how other contracts read it, and the
///         `Transfer` event emitted by the burn announces the change.
/// @dev In OpenZeppelin Contracts 5.x every burn path goes through {ERC721-_update},
///      which returns the owner before the update: that is the single point to extend.
///      The stored record is written only on burns, and {burnedBy} reads state, not the
///      stored record alone: while a token exists it returns zero, whatever the stored
///      record holds and whatever path minted the token, so re-minting needs no extra write.
abstract contract ERC721BurnRecord is ERC721, IERC721BurnRecord {
    mapping(uint256 tokenId => address burner) private _burners;

    /// @inheritdoc IERC721BurnRecord
    function burnedBy(uint256 tokenId) public view virtual returns (address) {
        if (_ownerOf(tokenId) != address(0)) {
            return address(0);
        }
        return _burners[tokenId];
    }

    /// @dev See {IERC165-supportsInterface}.
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC721BurnRecord).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @dev Records the burner when `to` is the zero address. `from` is the owner
    ///      returned by {ERC721-_update}, the same address carried by the `Transfer`
    ///      event, so the getter and the log cannot disagree.
    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        address from = super._update(to, tokenId, auth);
        if (to == address(0) && from != address(0)) {
            _burners[tokenId] = from;
        }
        return from;
    }
}
```

A contract that combines it with other ERC-721 extensions has to resolve `_update` and `supportsInterface` explicitly, as Solidity requires when several bases define the same function:

```solidity
contract MyToken is ERC721, ERC721Burnable, ERC721BurnRecord {
    constructor() ERC721("MyToken", "MTK") {}

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721BurnRecord)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721BurnRecord) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
```

## Security Considerations

**The record is only as trustworthy as the contract that exposes it.** A non-zero answer proves a burn only to the extent that the token contract implements this proposal faithfully, which is the same trust a consumer already places in `ownerOf`. A malicious contract can report any address, and an upgradeable one can change its answers after the fact. Consumers that guard value on the record should accept it only from token contracts they already trust.

**`burnedBy` is not a receipt.** Because re-minting is allowed, the record describes the most recent burn only. A consumer that reads the record again on every request can authorize twice for the same token id: once for the burner before a re-mint, and again for whoever burns the re-minted token. A consumer should read the record once and store the result: at burn time if it takes part in the burn, otherwise at its first request for that token id. In the second case, if the token contract re-mints ids, a window remains between the burn and that first reading, during which a re-mint and a new burn would redirect the claim to the second burner. Consumers that rely on the second pattern should check whether the token contract can re-mint.

**Zero proves nothing.** `address(0)` covers live tokens, tokens never minted and tokens burned before the record existed. Rule 7 forbids treating it as authorization, and user interfaces should not present it as evidence that a token was not burned or never existed.

**Intermediaries are named, not the people behind them.** When a contract holds a token and burns it, as a router or a marketplace may do, the record names that contract. Whether value then reaches the right person depends on that contract; no rule in this proposal can see past it.

**The interface identifier does not cover the return type.** ERC-165 identifiers are derived from function names and argument types only. A contract that declares `0x43470a89` but returns something other than a single `address` from `burnedBy` would pass detection and break its callers. This is a property of ERC-165 in general: implementations must match the interface in the Specification exactly, return type included.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
