---
eip: 8050
title: Compressed RPC Link Format with Method-Specific Shortcuts
description: A link-encodable format for JSON-RPC requests using Protocol Buffers, optional Brotli compression, and Base64url encoding. Defines shortcuts for wallet_sendCalls and wallet_sign with optimized transaction type encodings.
author: Bruno Barbieri (@brunobar79), Jake Feldman (@jakefeldman), Lukas Rosario (@lukasrosario)
discussions-to: https://ethereum-magicians.org/t/erc-8050-compressed-rpc-link-format-with-method-specific-shortcuts/25832
status: Draft
type: Standards Track
category: ERC
created: 2025-10-13
requires: 5792, 7871
---

## Abstract

This ERC defines a compact, URL-safe payload format for JSON-RPC requests targeting wallet interactions. It uses Protocol Buffers for binary serialization, an optional Brotli compression layer, and Base64url encoding for transport. The format supports **shortcuts**: method-specific encodings that optimize size and structure for particular RPC methods. This ERC standardizes three shortcuts:

- **Shortcut 0**: Generic JSON-RPC (universal fallback for any method)
- **Shortcut 1**: `wallet_sendCalls` (EIP-5792) with optimized encodings for ERC20 transfers, native transfers, and generic calls
- **Shortcut 2**: `wallet_sign` (EIP-7871) with optimized encodings for spend permissions and receive-with-authorization signatures

## Motivation

Applications often need to pass wallet RPC requests through QR codes, NFC tags, or deep links. JSON is verbose and not URL-friendly at small sizes. This standard provides:

- **Universal compatibility**: Any JSON-RPC request can be encoded via the generic shortcut
- **Optimization**: Common transaction patterns achieve 60-80% size reduction via specialized shortcuts
- **Interoperability**: A single format works across apps, wallets, and programming languages
- **Extensibility**: New shortcuts can be added without changing the core format

This enables one-step, connection-agnostic flows for payments, signatures, and other wallet interactions.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Payload Format

Payloads are Base64url-encoded binary data without padding. The entire string is the payload; applications MAY wrap it in URLs.

```
{base64url_encoded_payload}
```

ABNF (normative):

```
payload = 1*( ALPHA / DIGIT / "-" / "_" )
```

URL embedding (informative):

- Recommended query parameter: `p`
- Recommended link form: `{any-https-url}?p={payload}`
- Implementations SHOULD use iOS Universal Links and Android App Links for routing
- Wallets MUST accept raw payloads (e.g., from QR/NFC) and MAY accept URLs carrying `p`

**Encoding requirements:**

- Encoders MUST NOT include Base64url padding (`=`)
- Decoders MUST accept payloads with or without padding
- Decoders MUST reject:
  - Characters outside the Base64url alphabet (RFC 4648): `A-Z`, `a-z`, `0-9`, `-`, `_`
  - Invalid padding (padding characters not at the end, or incorrect padding length)
  - Payloads that cannot be decoded to valid binary data

### Compression Flags

The first byte of the binary payload indicates the compression method:

- `0x00`: No compression (Protocol Buffers only)
- `0x01`: Brotli compressed

Values `0x02`–`0xFF` are reserved. Decoders MUST reject unknown values.

**Conformance:**

- Decoders MUST implement Brotli decompression for `0x01` with support for:
  - Quality levels 0-11
  - Window size up to 24 bits (16 MB)
  - Standard Brotli RFC 7932 format
- Encoders MAY emit `0x00` when compression is not beneficial
- Encoders SHOULD use `0x01` if the compressed size (including the flag byte) is strictly smaller than uncompressed

**Recommended encoder settings (informative):**

- Quality: 4-6 (balances speed and compression ratio)
- Window size: 22 bits (4 MB) - sufficient for typical payloads
- Mode: GENERIC (works well for mixed text/binary data)
- These settings provide good compression while maintaining fast encoding/decoding

### Core Protocol Buffers Schema

Implementations MUST use the following Protocol Buffers v3 schema for the core payload:

```protobuf
syntax = "proto3";

message RpcLinkPayload {
  uint32 protocol_version = 1;   // Core payload version. This ERC defines version 1.

  // Chain context (optional at core level; shortcuts MAY require it)
  uint32 chain_id = 2;             // Canonical numeric chain ID (e.g., 1, 8453, 84532)

  // Shortcut selection and versioning
  uint32 shortcut_id = 3;          // 0 = GENERIC_JSON_RPC, 1 = WALLET_SEND_CALLS, 2 = WALLET_SIGN
  uint32 shortcut_version = 4;     // Shortcut-specific version (0 for shortcuts defined in this ERC)

  // Payload (selected by shortcut_id)
  oneof body {
    GenericJsonRpc generic = 10;         // shortcut_id = 0
    WalletSendCalls wallet_send_calls = 11;  // shortcut_id = 1
    WalletSign wallet_sign = 12;         // shortcut_id = 2
  }

  // Extension point for metadata/capabilities (values are UTF-8 JSON)
  map<string, bytes> capabilities = 20;
}
```

**Protocol Buffers version (normative):**

- Syntax: `proto3`
- Wire format: Protocol Buffers v3 (compatible with Protobuf 3.21+)
- Unknown fields: MUST be ignored per proto3 semantics
- Unknown enum discriminants: MUST be rejected unless explicitly allowed

**Implementation guidance (informative):**

Mature proto3 libraries for common platforms:

- TypeScript/JS: `@bufbuild/protobuf` ≥ 1.7
- Go: `google.golang.org/protobuf` ≥ v1.33
- Rust: `prost` ≥ 0.12
- Swift: `SwiftProtobuf` ≥ 1.25
- Kotlin/Java: `protobuf-javalite` ≥ 3.24

### Versioning

- `protocol_version` defines the core wire format (this ERC defines version `1`)
- `shortcut_id` selects the shortcut; `shortcut_version` is managed by the shortcut definition
- Backward compatibility: fields MUST NOT be repurposed within the same protocol version
- Forward compatibility: decoders MUST ignore unknown fields and reject unknown enum discriminants

**Decoder support policy:**

- Decoders MUST accept `protocol_version = 1`
- Decoders MUST reject unsupported `protocol_version` with an explicit error
- If `shortcut_id` is unsupported, decoders MUST return an error indicating unsupported shortcut

### Shortcut Registry

- **0** – `GENERIC_JSON_RPC` (this ERC; universal fallback)
- **1** – `WALLET_SEND_CALLS` (this ERC; optimizes EIP-5792 `wallet_sendCalls`)
- **2** – `WALLET_SIGN` (this ERC; optimizes EIP-7871 `wallet_sign`)
- **3..99** – Reserved for future standardized shortcuts
- **1000..1999** – Experimental/vendor shortcuts (MAY be used in private ecosystems)

Wallets and apps MAY support any subset of shortcuts. Unsupported shortcuts MUST trigger an explicit error.

---

## Shortcut 0: Generic JSON-RPC

**Purpose:** Universal fallback for any JSON-RPC method.

### Schema

```protobuf
message GenericJsonRpc {
  string method = 1;        // JSON-RPC method name (e.g., "eth_sendTransaction", "wallet_sendCalls")
  bytes params_json = 2;    // UTF-8 JSON-encoded params array or object (RFC 8259)
  string rpc_version = 3;   // Optional JSON-RPC version (e.g., "2.0")
}
```

### Encoding Rules

- `shortcut_id = 0`
- `method`: case-sensitive, MUST match the target RPC interface
- `params_json`: MUST be well-formed UTF-8 JSON (array or object per JSON-RPC spec)
- `rpc_version`: OPTIONAL; decoders MUST NOT rely on it
- `chain_id`: MAY be present; generic shortcut does not require it

### Decoding Algorithm

1. Validate `shortcut_id = 0`
2. Parse `method` and `params_json` (UTF-8 decode, then JSON parse)
3. Reconstruct JSON-RPC request:

   ```json
   {
     "jsonrpc": rpc_version || "2.0",
     "method": method,
     "params": JSON.parse(params_json)
   }
   ```

### Example

**Input:**

```json
{
  "method": "eth_sendTransaction",
  "params": [{
    "from": "0x1111111111111111111111111111111111111111",
    "to": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
    "value": "0x0",
    "data": "0xa9059cbb..."
  }]
}
```

**Encoding (pseudocode):**

```typescript
const payload: RpcLinkPayload = {
  protocolVersion: 1,
  chainId: 0, // optional
  shortcutId: 0,
  shortcutVersion: 0,
  body: {
    case: 'generic',
    value: {
      method: 'eth_sendTransaction',
      paramsJson: utf8Encode(JSON.stringify([{ from: '0x11...', to: '0xa0...', ... }])),
      rpcVersion: '2.0'
    }
  }
};
```

---

## Shortcut 1: wallet_sendCalls

**Purpose:** Optimized encoding for EIP-5792 `wallet_sendCalls` requests.

### Schema

```protobuf
message WalletSendCalls {
  // Transaction type discriminator
  SendCallsType type = 1;

  // Type-specific data
  oneof transaction_data {
    Erc20Transfer erc20_transfer = 10;
    NativeTransfer native_transfer = 11;
    GenericCalls generic_calls = 12;
  }

  // Optional sender address (from field)
  bytes from = 3;  // 20-byte address

  // RPC version (e.g., "1.0")
  string version = 4;
}

enum SendCallsType {
  SEND_CALLS_UNKNOWN = 0;
  ERC20_TRANSFER = 1;
  NATIVE_TRANSFER = 2;
  GENERIC_CALLS = 3;
}

message Erc20Transfer {
  bytes token = 1;      // 20-byte ERC20 token contract address
  bytes recipient = 2;  // 20-byte recipient address
  bytes amount = 3;     // Amount in token's smallest unit (big-endian bytes, minimal encoding)
}

message NativeTransfer {
  bytes recipient = 1;  // 20-byte recipient address
  bytes amount = 2;     // Amount in wei (big-endian bytes, minimal encoding)
}

message Call {
  bytes to = 1;         // 20-byte contract/EOA address
  bytes data = 2;       // Calldata (may be empty)
  bytes value = 3;      // Value in wei (big-endian bytes, minimal encoding)
                        // Note: For zero value, encoders MAY omit field or use 0x00
}

message GenericCalls {
  repeated Call calls = 1;
}
```

### Type Detection (Normative)

Encoders MUST detect transaction types in this order:

1. **ERC20 Transfer**: Exactly one call where:
   - `data` starts with `0xa9059cbb` (ERC20 `transfer(address,uint256)` selector)
   - `value` is `0x0`, empty, or omitted
   - `data` length is exactly 68 bytes (4-byte selector + 32-byte padded address + 32-byte padded amount)
   - Note: 68 bytes = 136 hex characters (after removing `0x` prefix)

2. **Native Transfer**: Exactly one call where:
   - `data` is empty or `0x`
   - `value` is non-zero

3. **Generic Calls**: Any other `wallet_sendCalls` request

### Encoding Algorithm

1. Parse EIP-5792 `wallet_sendCalls` request
2. Detect transaction type (see above)
3. Extract fields:
   - **ERC20**: Extract `token` (to address), `recipient` (bytes 4-35 of data), `amount` (bytes 36-67 of data, decoded as uint256)
   - **Native**: Extract `recipient` (to address), `amount` (value field)
   - **Generic**: Preserve all calls as-is
4. Set `from` if present in original request
5. Set `version` if present (e.g., "1.0")
6. Populate `RpcLinkPayload` with `shortcut_id = 1`, `chain_id`, and `capabilities`

### Decoding Algorithm

**Helper function `pad32`**: Left-pad bytes with zeros to exactly 32 bytes. For addresses (20 bytes), prepend 12 zero bytes. For amounts, convert to big-endian 32-byte representation.

1. Validate `shortcut_id = 1`
2. Switch on `type`:
   - **ERC20**: Reconstruct call with:
     - `to = token` (as hex with `0x` prefix)
     - `data = 0xa9059cbb + pad32(recipient) + pad32(amount)` (concatenate selector + padded params)
     - `value = 0x0`
   - **Native**: Reconstruct call with:
     - `to = recipient` (as hex with `0x` prefix)
     - `data = 0x` (empty)
     - `value = amount` (as hex with `0x` prefix)
   - **Generic**: Use calls as-is
3. Reconstruct EIP-5792 request:

   ```json
   {
     "method": "wallet_sendCalls",
     "params": [{
       "version": version || "1.0",
       "chainId": "0x" + chainId.toString(16),
       "from": from ? "0x" + from.hex() : undefined,
       "calls": [...],
       "capabilities": parseCapabilities(capabilities)
     }]
   }
   ```

### Example: ERC20 Transfer

**Input (EIP-5792):**

```json
{
  "method": "wallet_sendCalls",
  "params": [{
    "version": "1.0",
    "chainId": "0x2105",
    "calls": [{
      "to": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
      "data": "0xa9059cbb000000000000000000000000fe21034794a5a574b94fe4fdfd16e005f1c96e5100000000000000000000000000000000000000000000000000000000004c4b40",
      "value": "0x0"
    }]
  }]
}
```

**Encoded (pseudocode):**

```typescript
{
  protocolVersion: 1,
  chainId: 8453,
  shortcutId: 1,
  shortcutVersion: 0,
  body: {
    case: 'walletSendCalls',
    value: {
      type: SendCallsType.ERC20_TRANSFER,
      transactionData: {
        case: 'erc20Transfer',
        value: {
          token: hex('833589fCD6eDb6E08f4c7C32D4f71b54bdA02913'),
          recipient: hex('fe21034794a5a574b94fe4fdfd16e005f1c96e51'),
          amount: bigIntToBytes(5000000n) // 0x4c4b40
        }
      },
      version: '1.0'
    }
  }
}
```

---

## Shortcut 2: wallet_sign

**Purpose:** Optimized encoding for EIP-7871 `wallet_sign` requests with EIP-712 typed data.

### Schema

```protobuf
message WalletSign {
  // Signature type discriminator
  SignType type = 1;

  // Type-specific data
  oneof signature_data {
    SpendPermission spend_permission = 10;
    ReceiveWithAuthorization receive_with_authorization = 11;
    GenericTypedData generic_typed_data = 12;
  }

  // RPC version (e.g., "1")
  string version = 3;
}

enum SignType {
  SIGN_UNKNOWN = 0;
  SPEND_PERMISSION = 1;
  RECEIVE_WITH_AUTHORIZATION = 2;
  GENERIC_TYPED_DATA = 3;
}

message SpendPermission {
  // EIP-712 message fields
  bytes account = 1;              // 20-byte account address
  bytes spender = 2;              // 20-byte spender address
  bytes token = 3;                // 20-byte token address
  bytes allowance = 4;            // uint160 (big-endian bytes, minimal encoding)
  uint64 period = 5;              // uint48 in message, fits in uint64
  uint64 start = 6;               // uint48
  uint64 end = 7;                 // uint48
  bytes salt = 8;                 // 32-byte salt
  bytes extra_data = 9;           // extraData (may be empty for "0x")

  // EIP-712 domain fields
  bytes verifying_contract = 10;  // 20-byte verifyingContract
  string domain_name = 11;        // Domain name (e.g., "Spend Permission Manager")
  string domain_version = 12;     // Domain version (e.g., "1")
}

message ReceiveWithAuthorization {
  // EIP-712 message fields
  bytes from = 1;                 // 20-byte from address
  bytes to = 2;                   // 20-byte to address
  bytes value = 3;                // uint256 (big-endian bytes, minimal encoding)
  bytes valid_after = 4;          // uint256 (typically 0)
  bytes valid_before = 5;         // uint256 (timestamp)
  bytes nonce = 6;                // bytes32

  // EIP-712 domain fields
  bytes verifying_contract = 7;   // 20-byte USDC contract
  string domain_name = 8;         // Domain name (e.g., "USDC")
  string domain_version = 9;      // Domain version (e.g., "2")
}

message GenericTypedData {
  bytes typed_data_json = 1;      // UTF-8 JSON-encoded EIP-712 TypedData
}
```

### Type Detection (Normative)

Encoders MUST detect signature types for EIP-712 typed data in this order:

1. **SpendPermission**: `primaryType === "SpendPermission"` and domain has `verifyingContract`
2. **ReceiveWithAuthorization**: `primaryType === "ReceiveWithAuthorization"` and domain has `verifyingContract`
3. **Generic**: Any other `wallet_sign` request with typed data

### Encoding Algorithm

**Type field normalization**: The `type` field in EIP-7871 requests indicates EIP-712 typed data. Encoders MUST accept the following variants as equivalent to EIP-712:

- String `"0x01"` (canonical)
- String `"0x1"` (no leading zero)
- Number `1`
- Missing type field (assume EIP-712 if `data` contains typed data structure)

**Chain ID validation**: EIP-712 typed data contains `chainId` in both the params and the domain. Encoders MUST:

- Verify that `params.chainId` (hex string) and `domain.chainId` (number or hex string) represent the same chain
- Reject requests where these values conflict
- Use the params-level `chainId` for the `RpcLinkPayload.chain_id` field

1. Parse EIP-7871 `wallet_sign` request
2. Validate it contains EIP-712 typed data (check `type` field or inspect `data` structure)
3. Validate chain ID consistency (params vs domain)
4. Detect signature type (see Type Detection section above)
5. Extract fields:
   - **SpendPermission**: Extract all message fields + domain fields
   - **ReceiveWithAuthorization**: Extract all message fields + domain fields
   - **Generic**: Serialize entire typed data as JSON
6. Set `version` if present
7. Populate `RpcLinkPayload` with `shortcut_id = 2`, `chain_id`, and `capabilities`

### Decoding Algorithm

1. Validate `shortcut_id = 2`
2. Switch on `type` and reconstruct EIP-712 typed data:
   
   **SpendPermission**:

   ```json
   {
     "types": {
       "EIP712Domain": [
         {"name": "name", "type": "string"},
         {"name": "version", "type": "string"},
         {"name": "chainId", "type": "uint256"},
         {"name": "verifyingContract", "type": "address"}
       ],
       "SpendPermission": [
         {"name": "account", "type": "address"},
         {"name": "spender", "type": "address"},
         {"name": "token", "type": "address"},
         {"name": "allowance", "type": "uint160"},
         {"name": "period", "type": "uint48"},
         {"name": "start", "type": "uint48"},
         {"name": "end", "type": "uint48"},
         {"name": "salt", "type": "uint256"},
         {"name": "extraData", "type": "bytes"}
       ]
     },
     "domain": {
       "name": domain_name,
       "version": domain_version,
       "chainId": chain_id (as number),
       "verifyingContract": "0x" + verifying_contract.hex()
     },
     "primaryType": "SpendPermission",
     "message": {
       "account": "0x" + account.hex(),
       "spender": "0x" + spender.hex(),
       "token": "0x" + token.hex(),
       "allowance": "0x" + allowance.hex(),
       "period": period (as number),
       "start": start (as number),
       "end": end (as number),
       "salt": "0x" + salt.hex(),
       "extraData": extra_data.length > 0 ? "0x" + extra_data.hex() : "0x"
     }
   }
   ```

   **ReceiveWithAuthorization**:

   ```json
   {
     "types": {
       "EIP712Domain": [
         {"name": "name", "type": "string"},
         {"name": "version", "type": "string"},
         {"name": "chainId", "type": "uint256"},
         {"name": "verifyingContract", "type": "address"}
       ],
       "ReceiveWithAuthorization": [
         {"name": "from", "type": "address"},
         {"name": "to", "type": "address"},
         {"name": "value", "type": "uint256"},
         {"name": "validAfter", "type": "uint256"},
         {"name": "validBefore", "type": "uint256"},
         {"name": "nonce", "type": "bytes32"}
       ]
     },
     "domain": {
       "name": domain_name,
       "version": domain_version,
       "chainId": chain_id (as number),
       "verifyingContract": "0x" + verifying_contract.hex()
     },
     "primaryType": "ReceiveWithAuthorization",
     "message": {
       "from": "0x" + from.hex(),
       "to": "0x" + to.hex(),
       "value": "0x" + value.hex(),
       "validAfter": "0x" + valid_after.hex(),
       "validBefore": "0x" + valid_before.hex(),
       "nonce": "0x" + nonce.hex()
     }
   }
   ```

   **Generic**: Parse `typed_data_json` directly as the EIP-712 TypedData structure

3. Reconstruct EIP-7871 request:

   ```json
   {
     "method": "wallet_sign",
     "params": [{
       "version": version || "1",
       "chainId": "0x" + chainId.toString(16),
       "type": "0x01",
       "data": { /* EIP-712 TypedData from step 2 */ },
       "capabilities": parseCapabilities(capabilities)
     }]
   }
   ```

### Example: SpendPermission

**Input (EIP-7871):**

```json
{
  "method": "wallet_sign",
  "params": [{
    "version": "1",
    "chainId": "0x14a34",
    "type": "0x01",
    "data": {
      "types": {
        "SpendPermission": [
          {"name": "account", "type": "address"},
          {"name": "spender", "type": "address"},
          {"name": "token", "type": "address"},
          {"name": "allowance", "type": "uint160"},
          {"name": "period", "type": "uint48"},
          {"name": "start", "type": "uint48"},
          {"name": "end", "type": "uint48"},
          {"name": "salt", "type": "uint256"},
          {"name": "extraData", "type": "bytes"}
        ]
      },
      "domain": {
        "name": "Spend Permission Manager",
        "version": "1",
        "chainId": 84532,
        "verifyingContract": "0xf85210b21cc50302f477ba56686d2019dc9b67ad"
      },
      "primaryType": "SpendPermission",
      "message": {
        "account": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "spender": "0x8d9F34934dc9619e5DC3Df27D0A40b4A744E7eAa",
        "token": "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
        "allowance": "0x2710",
        "period": 281474976710655,
        "start": 0,
        "end": 1914749767655,
        "salt": "0x2d6688aae9435fb91ab0a1fe7ea54ec3ffd86e8e18a0c17e1923c467dea4b75f",
        "extraData": "0x"
      }
    }
  }]
}
```

**Encoded (pseudocode):**

```typescript
{
  protocolVersion: 1,
  chainId: 84532,
  shortcutId: 2,
  shortcutVersion: 0,
  body: {
    case: 'walletSign',
    value: {
      type: SignType.SPEND_PERMISSION,
      signatureData: {
        case: 'spendPermission',
        value: {
          account: hex('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
          spender: hex('8d9F34934dc9619e5DC3Df27D0A40b4A744E7eAa'),
          token: hex('036CbD53842c5426634e7929541eC2318f3dCF7e'),
          allowance: bigIntToBytes(10000n),
          period: 281474976710655n,
          start: 0n,
          end: 1914749767655n,
          salt: hex('2d6688aae9435fb91ab0a1fe7ea54ec3ffd86e8e18a0c17e1923c467dea4b75f'),
          extraData: new Uint8Array(0), // empty bytes for "0x"
          verifyingContract: hex('f85210b21cc50302f477ba56686d2019dc9b67ad'),
          domainName: 'Spend Permission Manager',
          domainVersion: '1'
        }
      },
      version: '1'
    }
  }
}
```

---

## Canonical Encodings (Normative)

All shortcuts MUST follow these encoding rules:

### Addresses

- Format: exactly 20 bytes, big-endian raw bytes (no 0x prefix on wire)
- Encoders MUST normalize input hex to lowercase before conversion
- Decoders MUST reject lengths other than 20 bytes

### Integer Amounts

- **Format**: big-endian minimal bytes with NO leading zero octets
- **Zero encoding**: Encoders SHOULD encode zero as a single `0x00` byte, but MAY omit the field (proto3 optimization)
- **Zero decoding**: Decoders MUST treat missing fields, empty bytes (length 0), and `0x00` (1 byte) as zero
- **Leading zeros**: Decoders MUST reject encodings with unnecessary leading zeros (e.g., `0x0001` for value 1)
- **Examples**:
  - `0` → `0x00` (1 byte) or omitted field
  - `255` → `0xff` (1 byte)
  - `256` → `0x0100` (2 bytes)
  - `5000000` → `0x4c4b40` (3 bytes)

### Fixed-Size Fields

- `salt`, `nonce`: MUST be exactly 32 bytes
- Decoders MUST reject other lengths

### Calldata

- Format: raw bytes (may be empty)
- Empty calldata: zero-length bytes field

### Chain ID

- Format: uint32 (varint-encoded on wire)
- MUST be the canonical numeric chain ID (e.g., 1 for Ethereum, 8453 for Base)
- Sufficient for all realistic EVM chain IDs (max 4,294,967,295)

### Strings

- Format: UTF-8 without BOM
- Used for: `method`, `version`, `domain_name`, `domain_version`, JSON in capabilities

### Capabilities

- **Storage format**: Each capability value is stored as the UTF-8 bytes of a JSON-serialized value (RFC 8259)
- **Allowed types**: Capability values MAY be any valid JSON value: objects `{}`, arrays `[]`, strings, numbers, booleans, or `null`
- **Object capabilities**: For object values, encoders SHOULD sort keys alphabetically for deterministic encoding
- **Decoding**: Decoders MUST parse the UTF-8 bytes as JSON and validate the result is well-formed
- **Size limits**: Implementations SHOULD enforce size limits (RECOMMENDED ≤ 4 KB per entry, ≤ 16 KB total)
- **Malformed data**: Invalid UTF-8 or JSON syntax errors MUST cause rejection

**Example capability encodings:**

```typescript
// Example 1: Object value
{ "dataCallback": { "callbackURL": "https://example.com", "events": ["initiated"] } }
// Stored as:
capabilities["dataCallback"] = utf8Encode('{"callbackURL":"https://example.com","events":["initiated"]}')

// Example 2: String value
{ "order_id": "ORDER-123" }
// Stored as:
capabilities["order_id"] = utf8Encode('"ORDER-123"') // JSON string includes quotes

// Example 3: Number value
{ "tip_bps": 50 }
// Stored as:
capabilities["tip_bps"] = utf8Encode('50') // No quotes for numbers
```

---

## Complete Encoding Algorithm

Encoders MUST follow this algorithm:

1. **Validate input**: Ensure request is well-formed `wallet_sendCalls`, `wallet_sign`, or generic JSON-RPC
2. **Select shortcut**:
   - `wallet_sendCalls` → shortcut 1 (detect type: ERC20/Native/Generic)
   - `wallet_sign` with EIP-712 → shortcut 2 (detect type: SpendPermission/ReceiveWithAuthorization/Generic)
   - Any other method → shortcut 0 (generic)
3. **Extract fields**: Populate the appropriate protobuf message per shortcut rules
4. **Serialize**: Encode using Protocol Buffers v3
5. **Compress**:
   - Try Brotli compression
   - If `brotliSize + 1 < uncompressedSize + 1`: prepend `0x01` to compressed data
   - Otherwise: prepend `0x00` to uncompressed data
6. **Encode**: Base64url encode the result WITHOUT padding

## Complete Decoding Algorithm

Decoders MUST follow this algorithm:

1. **Base64url decode**: Reject invalid characters or malformed padding
2. **Check compression flag** (first byte):
   - `0x01` → Brotli decompress remaining bytes
   - `0x00` → use remaining bytes directly
   - Other → reject with error
3. **Protobuf decode**: Deserialize into `RpcLinkPayload`
4. **Validate protocol version**: Reject if `protocol_version != 1`
5. **Dispatch by shortcut**:
   - `shortcut_id = 0` → decode `GenericJsonRpc`
   - `shortcut_id = 1` → decode `WalletSendCalls` (dispatch by type)
   - `shortcut_id = 2` → decode `WalletSign` (dispatch by type)
   - Other → reject with "unsupported shortcut" error
6. **Reconstruct RPC request**: Build JSON-RPC request per shortcut rules
7. **Validate**: Ensure reconstructed request is well-formed

---

## Error Handling (Normative)

Decoders MUST return explicit errors and MUST NOT proceed with partially valid data for:

- **Unsupported protocol version**: Unknown `protocol_version`
- **Invalid Base64url**: Characters outside alphabet or invalid padding
- **Unknown compression flag**: Flag byte not `0x00` or `0x01`
- **Decompression failure**: Brotli error, timeout, or corrupted data
- **Invalid protobuf structure**: Missing required oneofs, wrong field lengths
- **Unsupported shortcut**: Unknown or unimplemented `shortcut_id`
- **Non-canonical integers**: Leading zero octets in amount/value fields
- **Wrong address length**: Address fields not exactly 20 bytes
- **Wrong salt/nonce length**: Fixed-size fields not exactly 32 bytes
- **Malformed JSON**: Invalid UTF-8 or JSON syntax in `params_json`, `typed_data_json`, or capabilities
- **Capability size exceeded**: Capability values exceeding implementation limits

---

## Capability Extensions

This standard includes an extension point for metadata via the `capabilities` map. Each capability value MUST be a valid JSON value (object, array, string, number, boolean, or null) serialized as UTF-8 bytes. See [Capabilities](#capabilities) section for encoding rules.

### Data Callback Capability (ERC-8026)

The `dataCallback` capability enables wallet→server event notifications for enhanced UX and allows apps to request user data. It is defined in [ERC-8026](https://github.com/ethereum/ERCs/pull/1216).

**Structure:**

- `callbackURL`: HTTPS URL for webhook events
- `events`: Array of event objects, each with:
  - `type`: One of `"initiated"`, `"preSign"`, or `"postSign"`
  - `context`: Optional app-defined data (any JSON value)
  - `requests`: Optional array for `preSign` events (specifies what user data to collect)

**Encoding example with data requests:**

```json
{
  "capabilities": {
    "dataCallback": {
      "callbackURL": "https://example.com/callback",
      "events": [
        {
          "type": "initiated",
          "context": { "orderId": "ORDER-123" }
        },
        {
          "type": "preSign",
          "requests": [
            { "type": "email" },
            { "type": "physicalAddress", "optional": true }
          ],
          "context": { "shippingTier": "express" }
        },
        {
          "type": "postSign"
        }
      ]
    }
  }
}
```

**Simpler example (notifications only):**

```json
{
  "capabilities": {
    "dataCallback": {
      "callbackURL": "https://example.com/callback",
      "events": [
        { "type": "initiated" },
        { "type": "postSign" }
      ]
    }
  }
}
```

**Security requirements:**

- Wallets MUST use HTTPS for callback URLs
- Wallets SHOULD implement timeouts and retry logic with exponential backoff

**Note:** Full webhook payload schemas, data types, validation rules, and behavior are defined in ERC-8026. This ERC only specifies how to encode the capability in the payload format. The capability value is stored as UTF-8 JSON bytes per the [Capabilities](#capabilities) encoding rules.

---

## Size Savings Analysis (Informative)

Typical compression results (payload size in bytes, including compression flag and Base64url overhead):

| Transaction Type | JSON (minified) | Protobuf only (`0x00`) | Protobuf + Brotli (`0x01`) |
|------------------|-----------------|------------------------|----------------------------|
| ERC20 Transfer   | ~280-350        | ~120-150               | ~90-120                    |
| Native Transfer  | ~180-220        | ~80-100                | ~60-80                     |
| SpendPermission  | ~650-800        | ~200-250               | ~150-200                   |

**Compression ratio:** 60-80% size reduction for optimized shortcuts compared to raw JSON.

---

## Security Considerations

### Request Validation

Wallets MUST treat decoded requests as untrusted input and apply standard safety checks:

- **Transaction simulation**: Simulate before presenting to user
- **Address validation**: Verify addresses against expected checksums or ENS
- **Balance checks**: Ensure sufficient balance for transactions
- **Gas estimation**: Warn on unusually high gas costs
- **Contract analysis**: Flag interactions with unverified contracts
- **Phishing detection**: Check against known malicious addresses

### Privacy

- Payloads are plaintext once decoded; do not embed sensitive data (e.g., private keys, passwords)
- Use HTTPS for any URLs in capabilities
- Consider link expiration for time-sensitive requests

### Front-Running and MEV

This format is suitable for:

- Simple transfers and payments
- Signatures with fixed parameters
- Idempotent operations

This format is NOT suitable for:

- Competitive flows (DEX trades, auctions, liquidations)
- Time-sensitive operations with variable outcomes
- Any transaction where public visibility before execution creates exploitable MEV

### Resource Limits

Implementations MUST enforce limits to prevent resource exhaustion:

- **Decompression timeout**: RECOMMENDED ≤ 5 seconds
- **Parsing timeout**: RECOMMENDED ≤ 2 seconds
- **Capability size**: RECOMMENDED ≤ 4 KB per entry, ≤ 16 KB total
- **Call count**: RECOMMENDED ≤ 100 calls for generic calls
- **Recursion depth**: Bound JSON parsing depth (RECOMMENDED ≤ 32 levels)

### Callback Security

When implementing ERC-8026 callbacks:

- Use HTTPS exclusively
- Implement timeouts and retry limits
- Validate callback response signatures
- Never trust callback data without verification
- Log all callback interactions for audit

---

## Rationale

### Protocol Buffers

Protocol Buffers was chosen for serialization because:

- **Compact binary format**: 50-70% smaller than JSON
- **Schema evolution**: Fields can be added without breaking compatibility
- **Wide adoption**: Mature libraries in all major languages
- **Type safety**: Prevents encoding errors
- **Efficient encoding**: Varint compression for numeric fields

### Brotli Compression

Brotli was selected as the optional compression layer because:

- **Superior compression**: 15-25% better than gzip for structured data
- **Browser support**: Native support in modern browsers (93%+ global)
- **Optimized for text**: Works well with protobuf's wire format

Optional compression supports:

- Environments without Brotli (use `0x00`)
- Very small payloads where compression overhead exceeds benefits
- Applications prioritizing speed over size

### Base64url

Base64url (RFC 4648) was chosen for final encoding because:

- **URL-safe**: Works in query parameters, fragments, paths
- **No padding**: Removes unnecessary trailing `=` characters
- **Universal support**: Available in all programming environments
- **QR-friendly**: Efficient encoding for QR codes (alphanumeric mode)

### Shortcut Architecture

Separating shortcuts from the core format provides:

- **Stability**: Core format remains unchanged as new shortcuts are added
- **Flexibility**: Applications can implement only the shortcuts they need
- **Optimization**: Method-specific encodings achieve maximum compression
- **Backward compatibility**: New shortcuts don't break existing implementations

### No Hardcoded Enums

This ERC deliberately avoids hardcoded chain/token enums (unlike earlier experiments) because:

- **Maintainability**: No need to update the standard as new chains/tokens emerge
- **Simplicity**: Fewer lookup tables and edge cases
- **Universal compatibility**: Works with any EVM chain and any token
- **Size trade-off**: Saves 15-20 bytes per enum, but adds specification complexity

Raw addresses and chain IDs are simple, universal, and sufficient for this use case.

### Minimal Core Schema

Transaction metadata (payee info, order details, tips) is intentionally excluded from the core schema:

- **Broad applicability**: Different applications have different metadata needs
- **Maintainability**: Reduces core specification complexity
- **Flexibility**: Capabilities map allows application-specific extensions
- **Interoperability**: Focused core makes implementation easier

Applications requiring metadata can use the `capabilities` map without modifying the protocol.

---

## Backwards Compatibility

- Any `wallet_sendCalls` (EIP-5792) or `wallet_sign` (EIP-7871) request can be encoded via shortcuts 1/2 or the generic shortcut (0)
- Decoded requests are valid inputs to the original RPC methods
- Wallets without compression support can receive uncompressed payloads (`0x00`)
- This ERC introduces a new format; it does not modify existing RPC standards

---

## Test Vectors

**Note**: The following test vectors are provided as implementation guidance. The Base64url-encoded outputs represent the complete payload after protobuf serialization, Brotli compression, and Base64url encoding. Implementers SHOULD verify that their encoders produce structurally equivalent outputs (same protobuf structure after decoding) and that all fields roundtrip correctly.

### Test Vector 1: ERC20 Transfer (Shortcut 1)

**Input (EIP-5792):**

```json
{
  "method": "wallet_sendCalls",
  "params": [{
    "version": "1.0",
    "chainId": "0x2105",
    "calls": [{
      "to": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
      "data": "0xa9059cbb000000000000000000000000fe21034794a5a574b94fe4fdfd16e005f1c96e5100000000000000000000000000000000000000000000000000000000004c4b40",
      "value": "0x0"
    }]
  }]
}
```

**Protobuf representation (before serialization):**

```
protocol_version: 1
chain_id: 8453
shortcut_id: 1
shortcut_version: 0
wallet_send_calls {
  type: ERC20_TRANSFER
  erc20_transfer {
    token: [20 bytes: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913]
    recipient: [20 bytes: 0xfe21034794a5a574b94fe4fdfd16e005f1c96e51]
    amount: [3 bytes: 0x4c4b40]
  }
  version: "1.0"
}
```

**Expected output (Base64url, Brotli-compressed):**

```
AQj1QRABGgQxLjBSORIUgzWJ_NbttpgvHHMtT3cbVL2gKRMaFP4hA0eUpapXS5T-_RbgBfHJblUiA0xLQA
```

*(Note: Actual output may vary slightly depending on Brotli implementation; decoders must produce the same protobuf structure)*

---

### Test Vector 2: Native Transfer (Shortcut 1)

**Input (EIP-5792):**

```json
{
  "method": "wallet_sendCalls",
  "params": [{
    "version": "1.0",
    "chainId": "0x1",
    "calls": [{
      "to": "0xfe21034794a5a574b94fe4fdfd16e005f1c96e51",
      "data": "0x",
      "value": "0xde0b6b3a7640000"
    }]
  }]
}
```

**Protobuf representation:**

```
protocol_version: 1
chain_id: 1
shortcut_id: 1
shortcut_version: 0
wallet_send_calls {
  type: NATIVE_TRANSFER
  native_transfer {
    recipient: [20 bytes: 0xfe21034794a5a574b94fe4fdfd16e005f1c96e51]
    amount: [8 bytes: 0x0de0b6b3a7640000]
  }
  version: "1.0"
}
```

**Expected output (Base64url, Brotli-compressed):**

```
AQgBEAEaBC4wWh0SFP4hA0eUpapXS5T-_RbgBfHJblUaCQjgtrOn4AAAA
```

---

### Test Vector 3: SpendPermission (Shortcut 2)

**Input (EIP-7871):**

```json
{
  "method": "wallet_sign",
  "params": [{
    "version": "1",
    "chainId": "0x14a34",
    "type": "0x01",
    "data": {
      "types": {
        "SpendPermission": [
          {"name": "account", "type": "address"},
          {"name": "spender", "type": "address"},
          {"name": "token", "type": "address"},
          {"name": "allowance", "type": "uint160"},
          {"name": "period", "type": "uint48"},
          {"name": "start", "type": "uint48"},
          {"name": "end", "type": "uint48"},
          {"name": "salt", "type": "uint256"},
          {"name": "extraData", "type": "bytes"}
        ]
      },
      "domain": {
        "name": "Spend Permission Manager",
        "version": "1",
        "chainId": 84532,
        "verifyingContract": "0xf85210b21cc50302f477ba56686d2019dc9b67ad"
      },
      "primaryType": "SpendPermission",
      "message": {
        "account": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "spender": "0x8d9F34934dc9619e5DC3Df27D0A40b4A744E7eAa",
        "token": "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
        "allowance": "0x2710",
        "period": 281474976710655,
        "start": 0,
        "end": 1914749767655,
        "salt": "0x2d6688aae9435fb91ab0a1fe7ea54ec3ffd86e8e18a0c17e1923c467dea4b75f",
        "extraData": "0x"
      }
    }
  }]
}
```

**Protobuf representation:**

```
protocol_version: 1
chain_id: 84532
shortcut_id: 2
shortcut_version: 0
wallet_sign {
  type: SPEND_PERMISSION
  spend_permission {
    account: [20 bytes: 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa]
    spender: [20 bytes: 0x8d9F34934dc9619e5DC3Df27D0A40b4A744E7eAa]
    token: [20 bytes: 0x036CbD53842c5426634e7929541eC2318f3dCF7e]
    allowance: [2 bytes: 0x2710]
    period: 281474976710655
    start: 0
    end: 1914749767655
    salt: [32 bytes: 0x2d6688aae9435fb91ab0a1fe7ea54ec3ffd86e8e18a0c17e1923c467dea4b75f]
    extra_data: [0 bytes: empty]
    verifying_contract: [20 bytes: 0xf85210b21cc50302f477ba56686d2019dc9b67ad]
    domain_name: "Spend Permission Manager"
    domain_version: "1"
  }
  version: "1"
}
```

**Expected output (Base64url, Brotli-compressed):**

```
AQi0lAUQAhoBMVJWCAESFKqqqqqqqqqqqqqqqqqqqqqqqqqqGhSJ-TSTI8mRnlzhPfJ9CkC0p0R-qiIDNs6cAzZL1TOFY0Zmbu5JljHpM-gv0sXvjGXa0_I-EMiALWaIqulDX7katpH-6U7zPfhui6HAXHkyNHrpK3X_SRRTcGVuZCBQZXJtaXNzaW9uIE1hbmFnZXJaATFiBPiJELISzFDML0d3ukVobaAdybn2rQ
```

---

## Reference Implementation

A reference implementation in TypeScript/JavaScript is provided in the [prolinks library](https://github.com/base/prolinks) (experimental). Implementations SHOULD provide:

- Encoder functions for all three shortcuts
- Decoder functions with full error handling
- Round-trip tests for all transaction types
- Protobuf schema compilation for target language
- Brotli compression/decompression integration

---

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).

