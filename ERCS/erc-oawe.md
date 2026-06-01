---
eip: TBD
title: OAWE - OAuth With Ethereum
description: A permissionless OAuth 2.0 client authentication protocol using Ethereum accounts.
author: Zainan Victor Zhou (@xinbenlv) <zzn@zzn.im>
status: Draft
type: Standards Track
category: ERC
created: 2026-03-11
requires: 191, 712
---

## Abstract

OAuth With Ethereum (OAWE) provides a standard for permissionless OAuth 2.0 client authentication. It allows developers to bypass centralized application registration portals by using an Ethereum address or ENS name as their OAuth `client_id`. By leveraging existing OAuth 2.0 extensions (RFC 9101 and RFC 7523), developers use their Ethereum private key to dynamically sign authorization requests and token exchanges, proving ownership and intent without a static `client_secret`.

## Motivation

Traditional OAuth 2.0 requires developers to register applications with centralized platforms to obtain a `client_id`, `client_secret`, and to whitelist `redirect_uri`s. This introduces significant friction, creates vulnerabilities around secret management, and relies on centralized gatekeeping.

While various technologies and academic proposals have attempted to bridge decentralized cryptography and OAuth, a critical gap remains regarding *permissionless client registration*:

* **Sign-In With Ethereum (EIP-4361):** SIWE successfully decentralized the *Resource Owner* (user) authentication phase. However, it leaves the *Client* (developer) reliant on legacy, centralized registration portals to obtain the credentials necessary to initiate the SIWE flow.
* **RFC 7523 (Private Key JWTs):** Existing OAuth standards do support asymmetric key authentication to replace static `client_secret`s. However, this still requires a permissioned registration step where developers must manually upload their public keys or JWKS URIs to the platform's backend for approval.
* **DID and SSI-based OAuth:** Many academic and W3C proposals (such as Decentralized Identifiers in OAuth) attempt to decentralize the entire Authorization Server. This requires massive infrastructure overhauls and breaks backward compatibility, severely limiting adoption by established Web2 platforms.
* **Web3-Native API Authentication:** Many decentralized applications utilize ad-hoc EIP-712 signatures as backend API keys. However, these are isolated, proprietary implementations that fail to integrate with the standardized OAuth 2.0 Authorization Code flow utilized globally.

OAWE addresses this specific whitespace. By combining standard Ethereum account cryptography with existing, unmodified OAuth 2.0 extensions (RFC 9101 for the front-channel and RFC 7523 for the back-channel), OAWE enables a completely permissionless, dynamic client registration process. Developers can instantly integrate APIs while Authorization Servers can dynamically verify client identity and callback routing without prior registration, maintaining strict cryptographic security and maximum backward compatibility.

## Specification

The OAWE protocol utilizes standard OAuth 2.0 infrastructure, modifying only the client authentication mechanisms.

### 1. Client Identification

The OAuth `client_id` MUST be a valid Ethereum address or a verified ENS name that resolves to an Ethereum address.

### 2. Phase 1: Authorization Request (Front-Channel)

The client MUST NOT pass authorization parameters (like `redirect_uri`) as plain query strings. Instead, the client MUST use a JWT Secured Authorization Request (JAR) as defined in RFC 9101.

* The client constructs an EIP-712 typed data payload containing standard OAuth parameters (`response_type`, `client_id`, `redirect_uri`, `scope`, `state`, `nonce`).
* The payload is signed by the Ethereum private key associated with the `client_id`.
* The Authorization Server validates the signature against the `client_id` before presenting the user consent screen, dynamically trusting the provided `redirect_uri`.

### 3. Phase 2: Token Exchange (Back-Channel)

To exchange the authorization code for an Access Token, the client MUST authenticate using a JSON Web Token (JWT) as defined in RFC 7523, replacing the traditional `client_secret`.

* The client constructs a JWT assertion signed by the Ethereum private key associated with the `client_id`.
* The Authorization Server verifies the signature before issuing the Access Token.

## Backwards Compatibility

OAWE is entirely backwards compatible with existing OAuth 2.0 deployments. It relies exclusively on established IETF standards (RFC 9101 and RFC 7523). Platforms only need to implement secp256k1 signature verification to support OAWE clients alongside traditional static clients.

## Security Considerations

* **Phishing & Spoofing:** Because any developer can generate an Ethereum address instantly, Authorization Servers SHOULD treat raw OAWE addresses as "Unverified" and display warnings to users. Reputation can be established via ENS, on-chain staking, or verifiable credentials.
* **Sybil Attacks & Rate Limiting:** Malicious actors can generate infinite addresses to bypass API quotas. Platforms MAY implement Web3-native Sybil resistance mechanisms, such as requiring the `client_id` to hold a minimum ETH balance or a specific attestation.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
