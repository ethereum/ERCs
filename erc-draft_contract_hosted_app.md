---
eip: XXXX
title: Contract-Hosted Application HTML
description: A view-only interface for a contract to serve its own self-contained HTML dapp.
author: z0r0z (@z0r0z)
discussions-to: https://ethereum-magicians.org/t/erc-xxxx-contract-hosted-application-html/28407
status: Draft
type: Standards Track
category: ERC
created: 2026-04-30
requires: 1193
---

## Abstract

This proposal defines a single view function, `html()`, that lets a smart
contract serve a complete, self-contained HTML application directly from
its own state. A wallet, browser extension, or block explorer that already
exposes an [EIP-1193](./eip-1193.md) provider can fetch the document with
one `eth_call` and render it. No off-chain hosting (HTTP, IPFS, NPM, CDN)
is involved.

```solidity
function html() external view returns (string memory);
```

This proposal does not prescribe how the bytes are stored on chain. It
prescribes only the interface and the constraints on the returned document
that allow a generic client to render it safely.

## Motivation

Every "decentralized" application today is split across two trust domains:
the contract, which is deterministic and verifiable, and the frontend,
which is hosted somewhere mutable (HTTP, IPFS pin, S3, NPM dependency
tree). Users routinely sign transactions produced by code their wallets
did not verify. This split is the root cause of phishing forks of
legitimate frontends, gateway poisoning, malicious build-time
dependencies, expired or hijacked domains, and frontends that drift away
from the contracts they claim to drive.

If the contract serves its own UI, the wallet can fetch it through the
same RPC it already trusts, and the dapp lives in the same trust domain
as its bytecode. There is no second domain to phish and no dependency
tree to compromise.

The pattern is already viable: the 24576-byte runtime code limit set by
[EIP-170](./eip-170.md) is routinely circumvented by storing the document
across multiple data contracts (e.g. SSTORE2-style) and concatenating
their bytes at read time. Self-contained dapps that implement keccak256,
ABI encoding, ENS resolution, and [ERC-20](./eip-20.md) calls in inline
JavaScript fit comfortably in such budgets. What is missing is a standard
interface so that any client can find and render any such UI.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT",
"SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and
"OPTIONAL" in this document are to be interpreted as described in RFC
2119 and RFC 8174.

### Interface

A compliant contract MUST implement:

```solidity
interface IContractHostedApp {
    /// @notice Returns the contract's self-contained HTML application.
    /// @return A complete UTF-8 encoded HTML document.
    function html() external view returns (string memory);
}
```

The function MUST be `view`, MUST NOT revert under normal operation, and
MUST return a valid UTF-8 byte sequence. How the bytes are stored is out
of scope.

### Document

The string returned by `html()` is the *document*. It MUST satisfy:

1. **Self-contained.** The document MUST NOT reference any external
   network resource by URL. `<script src>`, `<link href>`, `<img src>`,
   `<iframe src>`, `<object data>`, `@import`, remote `url()`, `fetch()`,
   and `XMLHttpRequest` to remote URLs are all forbidden. `data:` URIs
   and `blob:` URIs constructed from in-document strings are permitted.
2. **Wallet provider.** The document SHOULD assume an EIP-1193 provider
   at `window.ethereum` and MUST NOT depend on any other non-standard
   browser global.
3. **Origin contract.** The document MUST be able to identify the
   contract that produced it. The RECOMMENDED method is to embed the
   contract address as a JavaScript constant at write time, made
   deterministic by deploying through CREATE2 / CREATE3 or by writing
   the document after the contract address is known.

### Discovery

A client tests for support by calling `html()` (selector `0x33c34ac3`,
i.e. `bytes4(keccak256("html()"))`) on the target contract. If the call
succeeds and the returned string is non-empty UTF-8, the contract
implements this proposal.

### Rendering

A conforming client:

1. SHOULD render the document in a sandboxed `<iframe>` with a
   default-deny Content-Security-Policy. The frame MUST NOT inherit
   cookies, `localStorage`, or any credentialed resources from the host
   page.
2. MUST inject an EIP-1193 provider into the frame and MUST gate every
   signing request through the host wallet's normal user-confirmation
   flow.
3. MUST NOT grant the document network access beyond `window.ethereum`.

## Rationale

### Why a single function

The minimum viable surface for a client is "give me the HTML". A single
function maps cleanly to a single `eth_call`. Multi-resource bundles,
manifests, and content negotiation add implementation cost without
unlocking a use case the single-document form cannot already serve.

### Why not require a specific storage layout

Storage technique is an implementation detail, and the available
techniques continue to evolve (data-contract chunking, packed slot
storage, EOF data sections). Tying the proposal to a specific layout
would prematurely freeze a transient choice. The reference
implementation uses one common approach for illustration only.

### Origin contract identity

A document is meaningful only if it can call back into the contract that
served it. Embedding the contract address as a JavaScript constant at
write time (deterministic via CREATE2 / CREATE3) makes the document
portable across every conforming client and works in environments
without a wallet. Substitution at render time and wallet-injected
globals were considered and rejected: both make documents
client-specific and let a malicious client retarget the document to a
different contract.

## Backwards Compatibility

This proposal is purely additive. Contracts that do not implement
`html()` are unaffected. Existing per-token metadata interfaces (such as
[ERC-721](./eip-721.md) `tokenURI`) are unaffected — those return
per-token JSON metadata, which has different semantics from a
contract-wide application document. A single contract MAY implement
both. Function selectors do not collide.

## Test Cases

A conforming implementation MUST satisfy the following round-trip
property: if a host contract is deployed to expose an HTML document
`D` via `html()`, then `keccak256(bytes(host.html()))` equals
`keccak256(D)` for every block in which the host's state is unchanged.

A conforming client, when given a contract whose `html()` returns a
document calling
`window.ethereum.request({method: 'eth_chainId'})`, MUST cause that
request to resolve to the chain id of the chain on which the contract
is deployed.

## Reference Implementation

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

interface IContractHostedApp {
    function html() external view returns (string memory);
}

interface IDataChunk {
    function read(address pointer) external view returns (bytes memory);
}

contract HostedHTML is IContractHostedApp {
    address private immutable _chunk1;
    address private immutable _chunk2;
    IDataChunk private immutable _reader;

    constructor(address chunk1, address chunk2, IDataChunk reader) {
        _chunk1 = chunk1;
        _chunk2 = chunk2;
        _reader = reader;
    }

    function html() external view returns (string memory) {
        return string(
            bytes.concat(
                _reader.read(_chunk1),
                _reader.read(_chunk2)
            )
        );
    }
}
```

Deploy flow: write the document bytes to one or more data contracts,
then deploy `HostedHTML` referencing them. A deterministic factory
allows the contract address to be known before deployment so it can be
embedded inside the document itself.

## Security Considerations

### Trust boundary

The document and the contract reach the user through the same channel:
both are bytes returned from `eth_call` against the user's chosen RPC.
A user who already trusts that channel for transaction execution is
relying on the same mechanism when the document arrives. A client MUST
NOT render the document with privileges greater than those it would
grant any other dapp talking to the same contract.

### Sandboxing

A renderer MUST treat the document as untrusted code. Recommended
mitigations: a sandboxed `<iframe>` with `sandbox="allow-scripts"` and a
default-deny Content-Security-Policy; an EIP-1193 provider that gates
every `eth_sendTransaction` through the same confirmation flow used for
any other dapp; no shared cookies, `localStorage`, or other credentialed
state with the host page; and a block on top-level navigation initiated
from inside the frame.

### Phishing surface

Two contracts can return identical-looking HTML with different hardcoded
contract address constants; if the host renders nothing outside the
sandboxed frame, a user cannot tell which contract a "Send" button
actually calls. A conforming client SHOULD display the contract address
and chain id of the document's origin in host-rendered UI outside the
sandboxed frame, where the document cannot overlay or modify it.

### Mutable HTML

If the document is stored in upgradable storage, a contract owner can
swap the UI without any user action. Implementations that want users to
be able to verify that the document is fixed SHOULD use immutable data
pointers and renounce ownership of any setters that can mutate the
document. Clients MAY surface a "mutable" indicator when these
guarantees are absent.

### Cross-chain confusion

A document may be deployed on multiple chains at the same address
(CREATE2 / CREATE3) and reference a hardcoded contract address that is
correct on every chain. The document MUST verify the connected
provider's chain id before transacting; the same address can hold
different contract code on different chains.

### Document size and DoS

`eth_call` to `html()` can return a multi-kilobyte response. Public RPC
operators SHOULD apply standard response-size limits. Clients SHOULD
time out long calls and present a recoverable error rather than
blocking the UI.

Implementations whose documents exceed practical single-call limits MAY
expose a paginated read helper of their own design (for example, a
`htmlChunkAt(uint256)` cursor) and have clients reassemble the bytes
client-side. Standardizing such an interface is intentionally left out
of scope: this proposal's design philosophy is to keep client code
around the contract call as simple as a single `eth_call` returning a
single string, mirroring the trust and complexity profile of any other
view function. Pagination, when needed, is an implementation choice
that does not need to be uniform across every host contract for clients
to interoperate with the base interface defined here.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
