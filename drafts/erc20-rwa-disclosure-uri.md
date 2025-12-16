---
eip: TBD
title: ERC-20 RWA Disclosure URI Extension
description: Standard interface for publishing a canonical disclosure URI for ERC-20 tokens.
author: Fahd Saifuddin (@FahdSaif)
discussions-to: https://ethereum-magicians.org/
status: Draft
type: Standards Track
category: ERC
created: 2025-12-16
---

## Abstract

This ERC defines a minimal extension to ERC-20 tokens that exposes a canonical disclosure URI. The disclosure URI points to issuer-provided, human-readable disclosure material related to a real-world asset.

## Motivation

Tokenised real-world assets require a consistent and discoverable mechanism for users, wallets, explorers, and indexers to locate issuer disclosures. Currently, disclosure links are scattered across websites and documentation with no standard on-chain discovery mechanism. This ERC standardises a minimal interface for publishing such information.

## Specification

The key words "MUST", "SHOULD", and "MAY" are to be interpreted as described in RFC 2119.

### Interface

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

interface IERC20RwaDisclosureURI {
    /// @notice Emitted when the disclosure URI is updated.
    event DisclosureURIUpdated(string uri);

    /// @notice Returns the canonical disclosure URI for this token.
    function disclosureURI() external view returns (string memory);
}

