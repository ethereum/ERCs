---
title: Chain-ID-Based RPC Provider URLs
description: Standardizes how RPC providers expose node endpoints by chain-ID to simplify multichain integration.
author: Soham Zemse (@zemse)
discussions-to: <URL>
status: Draft
type: Meta
created: 2025-09-03
---

## Abstract

This EIP defines a standardized URL format that RPC providers **MUST** expose to allow wallets and multichain applications to connect to any supported Ethereum-based chain by specifying its chain-ID.

## Motivation

Node RPC providers are an intregral part of the ecosystem, enabling applications and users to interact with Ethereum and L2s. However, they often use custom URL format for each chain which is based on name slugs. And these slugs are not consistent across providers (e.g. `opt` used by alchemy while `optimism` by ankr). This causes applications to hardcode many URLs, which is fragile. Also many applications tend to hardcode node RPC URLs rather than let users customise them, to avoid giving too many input boxes to the users.

There is also friction when an application wants to decrease trust by integrating with multiple node RPC providers to ensure reliability and integrity, since they have to input URLs for many networks for many node RPC providers.

Users should be able to simply set a base URL in their wallet or application for accessing Ethereum and L2s. Any developer should be easily able to program an application to connect with multiple networks and be able to switch RPC providers or use multiple.

A consistent endpoint format, based on `chain-ID`, lets developers and users switch between RPC providers simply by chaning the base URL, without modifying per-network URLs.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

The following grammar MUST be supported by compliant providers, and the endpoint MUST expose a standard JSON-RPC interface for the relevant chain:

```
<BASE_URL>/:?api_key/:chain_id/
```

`BASE_URL`: an endpoint on the node RPC provider's web infrastructure.

`api_key`: optionaly required API key by node RPC providers to cover their node running costs.

`chain_id`: chain id of the network whose JSON RPC interface is being exposed.

### Examples

- `https://noderpcprovider.com/ABCDE_ApiKey/1` - RPC giving access to Ethereum mainnet with API key 
- `https://noderpcprovider.com/ABCDE_ApiKey/10/` - RPC giving access to Optimism with API key.
- `https://eip-x.existingprovider.com/v4/ABCDE/8453` - Old RPC giving access Base with provider under a subdomain.
- `http://newprovider.is/cool/ABCDE/42161` - New RPC giving access to Arbitrum under a fancy scope
- `http://iamfreerpc.com/534352` - A free RPC giving access to Scroll

## Rationale

- For Node RPC providers, supporting a common interface like this should be easily possible by creating an additional endpoint and internally forwarding requests to their existing infrastructure endpoints.
- Instead of a subdomain approach, URL argument approach is choosen for easier implementation.
- Node RPC providers can simply provide a URL that combines base url and api key, it can be used by applications and wallets easily.


- Most providers can implement this easily by forwarding requests internally.
- Using path parameters (rather than subdomains) simplifies implementation and avoids DNS complexity.
- Node RPC providers can simply provide a URL to developers that combines base url and api key, so that applications and wallets can easily add the chain ID further to it.


## Backwards Compatibility

This ERC suggest existing node RPC providers keep supporting existing custom endpoints so that already developed applications with hardcoded URLs do not face disruptions.

Adopting this new format is optional and non-breaking, it offers a streamlined alternative without disrupting existing integrations.

## Test Cases

A JSON-RPC call to `eth_chainId` on any compliant endpoint **MUST** return the same chain ID that appears in the URL path.


## Security Considerations

Needs discussion.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
