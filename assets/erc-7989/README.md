# ERC-7965: Ethereum Intent URI (EIURI)

This directory contains assets and resources related to ERC-7965, which defines a standardized URI format for representing and triggering Ethereum JSON-RPC requests.

## Overview

ERC-7965 introduces a universal action URI format for Ethereum that allows users to execute blockchain actions directly via URLs or QR codes. It extends the existing `ethereum:` URI scheme by supporting:

- Full RPC methods beyond just `eth_sendTransaction`
- Optional chain identifiers for multi-chain support
- Multi-step requests via base64-encoded payloads
- Enhanced semantic metadata for better UX

## Key Features

- **Backward Compatible**: Extends existing `ethereum:` URI standard
- **QR-Friendly**: Designed for real-world usage scenarios
- **Multi-Chain Support**: Chain-specific targeting with `@chainId` syntax
- **Flexible Parameters**: Support for nested objects and arrays via bracket notation
- **Dynamic Addressing**: `CURRENT_ACCOUNT` placeholder for user's active address

## Example URIs

### Basic Transaction
```
ethereum:eth_sendTransaction-0x0000000000000000000000000000000000000000@1?from=CURRENT_ACCOUNT&to=0x742d35Cc6634C0532925a3b8D4C9db96C4b4d8b6&value=0xde0b6b3a7640000
```

### Add Network
```
ethereum:wallet_addEthereumChain-0x0000000000000000000000000000000000000000?chainId=0x89&chainName=Polygon&rpcUrls[0]=https://polygon-rpc.com&nativeCurrency[name]=MATIC&nativeCurrency[symbol]=MATIC&nativeCurrency[decimals]=18
```

### Multi-Request
```
ethereum:multiRequest-0x0000000000000000000000000000000000000000@1?requests_b64=W3sibWV0aG9kIjoiZXRoX2NoYWluSWQiLCJwYXJhbXMiOltdfV0=
```

## Use Cases

- **QR Code Payments**: Generate payment URIs for physical transactions
- **DApp Deep Links**: Direct users to specific actions without wallet connection
- **Batch Operations**: Execute multiple transactions in sequence
- **Cross-Chain Interactions**: Specify target chains for multi-chain operations
- **Offline Signing**: Create URIs for offline transaction signing

## Implementation

See the main ERC document for complete specification and reference implementation in JavaScript.

## Security Considerations

- Validate all parameters before execution
- Implement proper base64 decoding with size limits
- Verify chain ID compatibility
- Display clear action information to users
- Implement gas limit protections 
