---
eip: 8495
title: Token Metadata JSON Schema
description: Specifies the JSON that token URIs resolve to, including media fields, traits, and a way for later proposals to extend it.
author: Devin Finzer (@dfinzer), Alex Atallah (@alexanderatallah), Ryan Ghods (@ryanio)
discussions-to: https://ethereum-magicians.org/t/erc-8495-token-metadata-json-schema/30339
status: Draft
type: Standards Track
category: ERC
created: 2026-10-26
requires: 721, 1155, 4804, 4906, 6909
---

## Abstract

This proposal specifies the JSON document that `tokenURI` ([ERC-721](./eip-721.md), [ERC-6909](./eip-6909.md)) and `uri` ([ERC-1155](./eip-1155.md)) resolve to. It covers the display fields, the `attributes` array of traits, which URI schemes clients resolve, how clients treat malformed values, and how other proposals add fields. It writes down the format most deployed tokens already use.

## Motivation

ERC-721 defines `name`, `description`, and `image`, and ERC-1155 adds `decimals`, `properties`, and `localization`. Everything else wallets and marketplaces show, including video, HTML, and traits, follows a format OpenSea documented in 2018 that was never specified. Clients fill the gaps differently: whether a trait value can be a boolean or a quoted number, whether dates are in seconds or milliseconds, which URI schemes to resolve, and how to isolate HTML.

Proposals that add metadata fields, such as [ERC-5625](./eip-5625.md), have no base document to require and no rules for naming fields or for what older clients show. This proposal gives them both.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

A *metadata URI* is the string returned by `tokenURI(uint256)` in ERC-721 or ERC-6909, or by `uri(uint256)` in ERC-1155. A *metadata document* is the JSON object it resolves to. A *producer* publishes metadata documents, and a *client*, such as a wallet, marketplace, or indexer, reads them.

### Resolving URIs

These rules apply to the metadata URI and to every URI-valued field.

Clients MUST resolve `https`, `ipfs` (InterPlanetary File System), `ar` (Arweave), and `data` URIs. Clients MAY resolve other schemes, such as `ipns` or the `web3` scheme of [ERC-4804](./eip-4804.md), and MUST NOT resolve schemes that run code or read local resources, such as `javascript` or `file`.

Producers MUST use absolute URIs, SHOULD use `ipfs`, `ar`, or `data` for content that is not meant to change, and SHOULD NOT use `http`. An `ipfs` URI MUST have the form `ipfs://<cid>`, where `<cid>` is a content identifier, with an optional path. Producers SHOULD NOT write an IPFS gateway URL in place of an `ipfs` URI. Clients MAY fetch `ipfs` and `ar` content through any gateway.

A `data` URI ([RFC 2397](https://www.rfc-editor.org/rfc/rfc2397)) that carries a metadata document SHOULD use the prefix `data:application/json;base64,`. Clients MUST accept base64 payloads. Clients SHOULD also accept unencoded payloads, such as `data:application/json;utf8,{"name":"Example"}`, and SHOULD percent-decode one that does not parse as written.

For ERC-1155 tokens, clients MUST apply ERC-1155's `{id}` substitution to the metadata URI and to string values in the document.

### Fetching

A metadata document MUST be a JSON object ([RFC 8259](https://www.rfc-editor.org/rfc/rfc8259)) encoded as UTF-8. Clients MUST treat any other top-level value as absent, and SHOULD parse the body as JSON whatever its `Content-Type`. Servers SHOULD send an accurate `Content-Type` and `Access-Control-Allow-Origin: *`.

A client that fetches from its own servers, such as an indexer, MUST NOT connect to loopback, private, or link-local addresses. It MUST apply this check to the address each hostname resolves to and to every redirect.

### Fields

| Field | Type | Meaning |
| --- | --- | --- |
| `name` | string | Name of the token. |
| `description` | string | Description of the token. |
| `image` | URI | Still image, used in lists and previews. |
| `animation_url` | URI | Video, audio, 3D model, or HTML page, shown in place of `image`. |
| `external_url` | URI | Page about the token on the producer's site. |
| `background_color` | string | Color behind the image. |
| `attributes` | array | Traits of the token. |

Every field is OPTIONAL. Producers SHOULD include `name` and `image`, and SHOULD omit a field rather than set it to `null` or an empty string.

Clients MUST treat `null` and empty strings as absent and MUST ignore fields they do not recognize. Clients SHOULD ignore a field of the wrong type and read the rest of the document, and MAY truncate or drop values that exceed their own limits.

#### `name` and `description`

`name` is plain text. Clients MUST NOT interpret Markdown or HTML in it.

`description` MAY contain CommonMark Markdown. Clients MUST NOT render raw HTML in it and SHOULD NOT load remote images it references.

#### `image`

Producers SHOULD use a format browsers display natively, such as PNG, JPEG, GIF, WebP, AVIF, or SVG (Scalable Vector Graphics). Clients MUST display SVG without running its scripts, for example in an image element or by rasterizing it.

#### `animation_url`

Clients that can render `animation_url` SHOULD show it in the token's detail view in place of `image`, MUST fall back to `image` when they cannot, and SHOULD show `image` as cover art for audio. Producers SHOULD use one of these media types:

| Kind | Media types |
| --- | --- |
| Video | `video/mp4`, `video/x-m4v`, `video/webm`, `video/ogg` |
| Audio | `audio/mpeg`, `audio/wav`, `audio/ogg` |
| 3D model | `model/gltf-binary`, `model/gltf+json` (glTF 2.0) |
| Interactive | `text/html` |

Clients SHOULD take the media type from the `Content-Type` header or the `data` URI, and MAY fall back to the file extension.

A client that renders an HTML page:

- MUST isolate it from the client's origin, for example in an `iframe` sandboxed with `allow-scripts` but not `allow-same-origin`.
- MUST NOT expose a wallet provider or signing interface to it.
- SHOULD block popups and top-level navigation from it.
- SHOULD resolve relative references against the page's own location.

#### `external_url` and `background_color`

Producers SHOULD use `https` for `external_url`.

`background_color` is six hexadecimal digits without a leading `#`, such as `"E0F2FE"`, in either case. Clients SHOULD ignore other formats, and MAY remove a leading `#` first.

#### `attributes`

An array of trait objects:

| Field | Type | Meaning |
| --- | --- | --- |
| `trait_type` | string | Name of the trait. SHOULD be present. |
| `value` | string or number | Value of the trait. REQUIRED. |
| `display_type` | string | How clients present the value. |
| `max_value` | number | Upper bound of a numeric value. |

`value` MUST be a string or a number, so `"5"` is a string trait and `5` is a numeric trait. Clients SHOULD ignore an attribute whose `value` is absent, `null`, an empty string, an object, or an array, and MAY read a boolean as the string `"true"` or `"false"`.

A `trait_type` MAY repeat to give a trait several values, and clients SHOULD keep each value. Clients SHOULD compare trait types and string values exactly after trimming leading and trailing whitespace. Producers SHOULD list attributes in display order.

| `display_type` | `value` | Meaning |
| --- | --- | --- |
| absent | string | Categorical trait. |
| absent | number | Numeric trait. Clients MAY show it relative to `max_value`. |
| `string` or `text` | string | The same as absent. Producers SHOULD write `string`. |
| `number` | number | Numeric stat. |
| `boost_number` | number | Signed bonus, such as `+40`. |
| `boost_percentage` | number | Signed percentage. `10` means `+10%`. |
| `date` | number | Unix time in seconds, which SHOULD be an integer. |

For `number`, `boost_number`, `boost_percentage`, and `date`, `value` MUST be a number, and clients MAY accept a string of a decimal number. Clients MUST treat a `display_type` they do not recognize as absent. `max_value` applies only to numeric traits and MUST be greater than or equal to `value`.

#### Other fields

`decimals`, `properties`, and `localization` have their ERC-1155 meaning for tokens of any standard. Producers SHOULD put traits in `attributes`, not `properties`.

Clients MAY read two legacy fields that producers SHOULD NOT use: `image_data`, raw SVG markup used when `image` is absent, and `youtube_url`, used when `animation_url` is absent.

#### Deployed forms

Clients MAY accept these forms, which producers MUST NOT use:

- `attributes` as an object, such as `{"Background": "Blue"}`.
- Traits in an array named `traits` or `properties` instead of `attributes`.
- `image_url` instead of `image`.
- `ipfs://ipfs/<cid>`, read as `ipfs://<cid>`.
- `date` values in milliseconds. Clients MAY read a value of `1000000000000` or more as milliseconds.

### Extensions

An extension is a proposal that adds fields to the metadata document.

1. An extension MUST list this proposal in `requires`.
2. An extension MUST name every top-level field it defines, and SHOULD define a single top-level field whose value is an object.
3. Field names SHOULD use only lowercase ASCII letters, digits, and underscores, and SHOULD begin with a letter.
4. An extension MUST NOT change the meaning or type of a field defined by this proposal or another extension. It MAY define new `display_type` values and new attribute fields.
5. A document that uses an extension MUST still conform to this proposal. An extension SHOULD state which base fields producers fill as a fallback.
6. Clients that do not implement an extension MUST ignore its fields. Clients that do SHOULD prefer its data over the fallback.

Producers MAY add fields that no proposal defines, and SHOULD name them so they are unlikely to collide with an extension, for example by including the project's name.

### Metadata updates

When a document changes, ERC-721 contracts SHOULD emit an [ERC-4906](./eip-4906.md) event and ERC-1155 contracts SHOULD emit `URI`. Clients that cache documents SHOULD refetch on these events, and MAY refetch on their own schedule.

### JSON Schema

Where this schema differs from the text above, the text applies.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "Token Metadata",
  "type": "object",
  "properties": {
    "name": { "type": "string" },
    "description": { "type": "string" },
    "image": { "type": "string", "format": "uri" },
    "animation_url": { "type": "string", "format": "uri" },
    "external_url": { "type": "string", "format": "uri" },
    "background_color": { "type": "string", "pattern": "^[0-9A-Fa-f]{6}$" },
    "attributes": { "type": "array", "items": { "$ref": "#/$defs/attribute" } },
    "decimals": { "type": "integer", "minimum": 0 },
    "properties": { "type": "object" },
    "localization": {
      "type": "object",
      "required": ["uri", "default", "locales"],
      "properties": {
        "uri": { "type": "string" },
        "default": { "type": "string" },
        "locales": { "type": "array", "items": { "type": "string" } }
      }
    },
    "image_data": { "type": "string", "deprecated": true },
    "youtube_url": { "type": "string", "format": "uri", "deprecated": true }
  },
  "$defs": {
    "attribute": {
      "type": "object",
      "required": ["value"],
      "properties": {
        "trait_type": { "type": "string" },
        "value": { "type": ["string", "number"] },
        "display_type": { "type": "string" },
        "max_value": { "type": "number" }
      },
      "if": {
        "required": ["display_type"],
        "properties": {
          "display_type": { "enum": ["number", "boost_number", "boost_percentage", "date"] }
        }
      },
      "then": { "properties": { "value": { "type": "number" } } }
    }
  }
}
```

### Example

```json
{
  "name": "Dave Starbelly",
  "description": "A friendly sea creature that enjoys long swims in the ocean.",
  "image": "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi/3.png",
  "animation_url": "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi/3.glb",
  "external_url": "https://example.com/creatures/3",
  "background_color": "E0F2FE",
  "attributes": [
    { "trait_type": "Base", "value": "Starfish" },
    { "trait_type": "Level", "value": 5, "max_value": 10 },
    { "display_type": "boost_percentage", "trait_type": "Stamina Increase", "value": 10 },
    { "display_type": "date", "trait_type": "Birthday", "value": 1546360800 }
  ]
}
```

## Rationale

Figures below come from a survey of metadata from 708 Ethereum and Base contracts in October 2026.

- Field names stay as deployed. `animation_url` holds more than animations, and `external_url` differs from `external_link` in [ERC-7572](./eip-7572.md), but renaming either would break existing documents.
- No field is required, because ERC-721 requires none and deployed documents often omit fields.
- `attributes` is an array because traits repeat, have an order, and carry display hints, and most deployed documents already use one.
- Unknown display types read as absent, so producers and extensions can add new ones without breaking clients. `text` is accepted because more surveyed contracts use it than `string`.
- Dates are in seconds to match `block.timestamp`. The millisecond cutoff of `1000000000000` catches every millisecond date after September 2001 and no date in seconds before the year 33000. A lower cutoff would misread `253402300800` (the year 10000), which some contracts use to mean "never expires".
- Gateway URLs tie content to one server: 113 of the 204 surveyed token URIs written as IPFS gateway URLs failed to load. An `ipfs` URI can be fetched through any gateway or node.
- Base64 is the recommended `data` encoding because browsers treat `#` as the start of a fragment and drop the rest of an unencoded payload, which breaks JSON that contains a `#`, such as a name like `Creature #42`. Clients still accept unencoded payloads because many deployed contracts emit them.
- Extensions are top-level objects because clients already detect optional data by checking whether a field is present. A list of implemented proposals, like the `interop` object in [ERC-1046](./eip-1046.md), or a version field would repeat that and could disagree with it. Names begin with a letter so they are valid identifiers in GraphQL and Protocol Buffers.
- There is no contract interface or [ERC-165](./eip-165.md) identifier, because the document tells a client everything an interface could.
- Attributes are display data that producers can change. Protocols that settle on a trait's value need an onchain source such as [ERC-7496](./eip-7496.md).

## Backwards Compatibility

Documents that conform to the ERC-721 or ERC-1155 metadata schemas, or follow the 2018 format described in [Motivation](#motivation), conform to this proposal. The forms in [Deployed forms](#deployed-forms) do not conform, but clients may still accept them.

## Test Cases

| Metadata URI | Document |
| --- | --- |
| `data:application/json;base64,eyJuYW1lIjoiRXhhbXBsZSJ9` | `{"name":"Example"}` |
| `data:application/json;utf8,{"name":"Example"}` | `{"name":"Example"}` |
| `ipfs://ipfs/bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi/1.json` | Not conformant. Read as `ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi/1.json` by clients that accept it. |

For an ERC-1155 token with ID `314592`, `ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi/{id}.json` resolves to `ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi/000000000000000000000000000000000000000000000000000000000004cce0.json`.

| Document | Result |
| --- | --- |
| `{"name": "Example", "image": 42}` | `image` has the wrong type and is ignored. |
| `{"name": "Example", "description": null}` | `description` is absent. |
| `{"name": "Example", "background_color": "#E0F2FE"}` | Not conformant. Read as `E0F2FE` by clients that remove the `#`. |
| `{"name": "Example", "glow": {"color": "gold"}}` | Conformant. `glow` is ignored. |

| Attribute | Result |
| --- | --- |
| `{"trait_type": " Eyes ", "value": "Big "}` | String trait `Eyes` with value `Big`. |
| `{"value": "Happy"}` | String trait with no trait type. |
| `{"trait_type": "Level", "value": "5"}` | String trait. |
| `{"trait_type": "Level", "value": 5, "max_value": 10}` | Numeric trait, 5 out of 10. |
| `{"display_type": "text", "trait_type": "Faction", "value": "Red"}` | String trait. |
| `{"display_type": "sparkle", "trait_type": "Mood", "value": "Calm"}` | String trait, since `sparkle` is unknown. |
| `{"display_type": "date", "trait_type": "Expires", "value": 253402300800}` | `10000-01-01T00:00:00Z`. |
| `{"display_type": "date", "trait_type": "Registered", "value": 1694173211000}` | `2023-09-08T11:40:11Z` for clients that accept milliseconds. |
| `{"trait_type": "Mood", "value": null}` | Ignored. |

Two attributes with `trait_type` `Accessory` and values `Scarf` and `Glasses` form one trait with both values.

## Security Considerations

- HTML in `animation_url` and SVG images can run scripts. Rendered in the client's origin, they reach its cookies, storage, and connected wallet. The isolation rules above prevent this.
- Links in `description` and `external_url` can lead to phishing pages. Clients should follow only `https` links and show the destination's domain.
- Indexers fetch URIs that any contract deployer chooses. Without the address checks in [Fetching](#fetching), a URI or redirect can reach internal services such as a cloud instance metadata endpoint.
- Documents and media can be huge, slow, deeply nested, or compressed. Clients should limit size, depth, time, and redirects.
- A producer's server sees every client that fetches from it directly, and can serve moderators different content than users. Clients should fetch through their own cache.
- A document served over `https` can change between a buyer's decision and settlement, so a seller can change a token's attributes to fill a trait offer and then change them back. Content-addressed URIs change only when the contract returns a new one. Protocols that settle on traits should read them onchain.
- Anyone can copy another collection's name and image. Clients should identify tokens by chain, contract, and token ID, never by metadata.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
