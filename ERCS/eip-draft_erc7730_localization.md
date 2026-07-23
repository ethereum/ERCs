---
title: Translation Files for ERC-7730 Descriptors
description: Translation file format, key namespace, and integrity mechanism for localizing ERC-7730 clear-signing descriptors.
author: Alex Forshtat (@forshtat)
discussions-to: TBD
status: Draft
type: Standards Track
category: ERC
created: 2026-07-22
requires: 7730
---

## Abstract

This specification defines the translation file format referenced by the `$i18n` field of an [ERC-7730](./eip-7730.md) document: how translatable strings are keyed, how a reserved namespace for shared vocabulary is resolved, how translation resources are integrity-checked, and how wallets look up localized strings at render time. ERC-7730 itself only defines the `$i18n` link field and the optional `labelKey`/`intentKey`/`interpolatedIntentKey` sibling properties; this specification defines everything on the other side of that link.

## Motivation

ERC-7730 needs to support translation of clear-signing descriptors into multiple languages without coupling the core clear-signing format to a specific, still-evolving localization mechanism. Embedding the full translation-file format directly in ERC-7730 would force every consumer of an ERC-7730 document, including the many English-only descriptors already in use, to carry the weight of a mechanism they may never use, and would tie changes to that mechanism to changes in the core format.

Separating the two lets descriptors and translations evolve independently: an existing descriptor gains translations by adding an optional `$i18n` entry and optional `<field>Key` properties, with no other changes, and the translation mechanism itself — key format, shared-vocabulary reuse, integrity — can be refined here without touching every descriptor that has adopted it.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Required languages

Documents that provide an `$i18n` field pointing at resources conforming to this specification MUST provide translations for at least the following languages:

| Language           | BCP-47 tag |
|--------------------|------------|
| Arabic             | `ar`       |
| Farsi              | `fa`       |
| French             | `fr`       |
| German             | `de`       |
| Hindi              | `hi`       |
| Japanese           | `ja`       |
| Portuguese         | `pt`       |
| Russian            | `ru`       |
| Simplified Chinese | `zh-Hans`  |
| Spanish            | `es`       |
| Turkish            | `tr`       |

These languages were selected to be familiar to the majority of internet users worldwide. Documents that do not include `$i18n` are unaffected by this requirement.

### Translation file format

A translation file is a JSON document with the following fields:

| Field          | Required | Description                                              |
|----------------|----------|-----------------------------------------------------------|
| `$schema`      | Yes      | Translation files have a separate schema.                 |
| `$locale`      | Yes      | BCP-47 language tag.                                       |
| `translations` | Yes      | Flat map from translation key to translated string.        |

```json
{
    "$schema": "https://eips.ethereum.org/assets/eip-7730/erc7730-i18n-v3.0.0-next.schema.json",
    "$locale": "fr",
    "translations": {
        "erc20.transfer.intent":              "Envoyer",
        "erc20.transfer.interpolated_intent":  "Envoyer {value} à {to}",
        "erc20.transfer.to_label":             "Destinataire",
        "erc20.transfer.amount_label":         "Montant",
        "common.send":                         "Envoyer"
    }
}
```

See [`example-main.fr.json`](../assets/erc-7730-localization/example-main.fr.json) for a complete example, and [`erc7730-i18n-v3.0.0-next.schema.json`](../assets/erc-7730-localization/erc7730-i18n-v3.0.0-next.schema.json) for the JSON schema of the translation file format. Its version tag tracks ERC-7730's own schema version (`3.0.0-next`), since the two evolve together; this file replaces the identically-named draft schema that briefly existed under `assets/erc-7730/` during ERC-7730's v3 development, before translation files were split out into this specification.

### Key format

Translation keys MUST match the pattern:

```
^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$
```

That is: one or more dot-separated segments, each segment starting with a lowercase ASCII letter and containing only lowercase ASCII letters, digits, and underscores (e.g. `erc20.transfer.amount_label`, `swap.confirm_intent`).

Authors SHOULD derive keys from the descriptor's own structure (contract or message name, function or field name, and role of the string) so that keys stay unique and stable across unrelated descriptors without coordination.

### Shared vocabulary namespace

The first segment `common` is reserved. Keys of the form `common.<name>` (e.g. `common.send`, `common.cancel`, `common.confirm`) are resolved against a canonical, separately-published shared vocabulary package covering strings reused across many descriptors (button labels, generic actions, and similar high-frequency terms), rather than against a descriptor-specific translation file alone.

Wallets resolving a `common.`-namespaced key MUST apply the following precedence:

1. If the descriptor's own translation file for the resolved locale defines the key, use that value. This lets a descriptor override a shared term when its context requires different wording.
2. Otherwise, look up the key in the shared vocabulary package for the same locale.
3. If neither defines the key, fall back to the literal field value as with any other missing translation.

The canonical shared vocabulary package's content, publication location, and versioning are out of scope for this specification and are expected to be defined by follow-up work; this specification only reserves the namespace and fixes the resolution precedence so descriptors and wallets can rely on it once that package exists.

### Translation resource integrity

Each `uri` value within a document's `$i18n` array entries MAY include a fragment of the form `#<hash-algorithm>-<base64-digest>`, using the same syntax as [W3C Subresource Integrity](https://www.w3.org/TR/SRI/) (e.g. `#sha256-<base64>`).

When present, wallets MUST compute the digest of the fetched translation resource's bytes using the named algorithm and MUST refuse to use the resource if the digest does not match. This guards against a compromised host or registry silently substituting altered translations without requiring a signature scheme or a single trusted signing authority — appropriate for ERC-7730's permissionless, multi-author registry model, where translations may be authored and hosted independently of the descriptor itself.

Wallets SHOULD warn the user, rather than silently falling back to English, when an `$i18n` entry without an integrity fragment is used, since such a reference cannot be verified.

### Lookup semantics

Wallets MUST apply the following procedure for each user-facing string field that carries a `<field>Key` property (e.g. `labelKey`, `intentKey`, `interpolatedIntentKey`):

1. Determine the user's preferred locale using BCP-47 matching and custom preferences.\
   The default BCP-47 tag resolution relies on widening the match conditions, e.g.: `zh-Hans-HK` → `zh-Hans` → `zh` → `en`.\
   Users SHOULD be able to define their own preferences in their wallets, e.g.: `sk` → `cs` → `ru` → `en`.
2. If a matching locale is listed in `$i18n`, fetch the translation resource at the first `uri` entry the wallet is able to resolve, verifying its integrity fragment if present (see above).
3. Look up the field's key in the resource's `translations` map, applying the shared-vocabulary precedence above when the key is in the `common.` namespace.
4. If a translation is found, display it. Otherwise, the wallet SHOULD present a clear warning about missing translations and fall back to the field's literal English value.

Fields with no `<field>Key` property are not translatable under this specification and are always displayed using their literal value.

`interpolatedIntent`-style strings contain field-value placeholders in the form `{fieldPath}`. These MUST appear verbatim in the translation. Word order may be rearranged around placeholders to suit the target language. Validators MUST check that every placeholder present in the English source also appears in the translated value, for example:

```
"erc20.swap.interpolated_intent":
    en: "You are providing {amount} as liquidity to {poolName}"
    uk: "Ви надаєте ліквідність до {poolName} на суму {amount}"
```

## Rationale

### Keys instead of raw English strings

An earlier draft of this mechanism used the literal English string itself as the translation-file key, needing a `|translatorNote` suffix convention to disambiguate homographs like "Transfer" as a noun versus a verb. Stable, author-chosen keys remove the need for that convention entirely: a key like `erc20.transfer.label` is unambiguous by construction, and doesn't drift when the English copy is edited for clarity, unlike a literal-string key which breaks every existing translation the moment the English wording changes.

Both Trezor firmware (`trezor/trezor-firmware`, `core/translations/en.json`) and Ledger Live (`LedgerHQ/ledger-live`, i18next-based) key their translations this way rather than by literal source string, for the same reasons.

### Dot-namespaced snake_case over other key shapes

A free-form, author-chosen key (with no required structure) was considered, but it gives up any shared convention for reuse across descriptors, and leaves nothing for the shared-vocabulary namespace to hook into. The chosen shape borrows the flat, snake_case segment style Trezor firmware uses, joined with dots so that a namespace can be reserved (`common.`) without a separate mechanism for distinguishing namespace from name.

### Why not a signed-bundle attestation scheme

Trezor firmware attests its translation bundles with a single Merkle root and signature per released version (`signatures.json`), verified against Trezor's own release key. That model fits a single vendor shipping one firmware release train. ERC-7730's registry is permissionless and multi-author: there is no single party positioned to sign every translation file for every descriptor. A per-reference integrity hash, in the style of Subresource Integrity, instead lets each descriptor author (or registry) commit to the exact bytes of the translation file they intend to be used, without requiring a shared signing authority.

### Shared vocabulary namespace

Both Trezor firmware and Ledger Live's translation catalogs show that a large fraction of UI vocabulary repeats across otherwise unrelated screens or descriptors — Ledger Live's `common` i18next namespace alone carries generic terms like `send`, `cancel`, `confirm`, and `save` that recur across its `swap`, `stake`, and `account` feature namespaces. Reserving `common.` and fixing its resolution precedence now means descriptor authors can start using shared terms immediately, and a canonical shared vocabulary package can be introduced later without any descriptor needing to change.

## Backwards Compatibility

This specification is new and additive; the `$i18n` field it governs is optional in ERC-7730. It supersedes the identically-named draft `erc7730-i18n-v3.0.0-next.schema.json` that briefly existed under `assets/erc-7730/`, and the literal-English-string-as-key mechanism that existed briefly in ERC-7730's v3 draft before translation files were split out into this specification; neither shipped in a finalized ERC-7730 release, so no deployed descriptor or translation file requires migration.

## Test Cases

Given the following field in an ERC-7730 document:

```json
{
    "label": "Transfer",
    "labelKey": "erc20.transfer.label"
}
```

And the following French translation resource, referenced from `$i18n.fr`:

```json
{
    "$schema": "https://eips.ethereum.org/assets/eip-7730/erc7730-i18n-v3.0.0-next.schema.json",
    "$locale": "fr",
    "translations": {
        "erc20.transfer.label": "Destinataire"
    }
}
```

A wallet resolving the `fr` locale MUST display "Destinataire". A wallet resolving the `de` locale, for which no translation resource is listed, MUST display the literal "Transfer".

Given the interpolated field:

```json
{
    "interpolatedIntent": "Send {value} to {to}",
    "interpolatedIntentKey": "erc20.transfer.interpolated_intent"
}
```

A translation value of `"Envoyer {value} à {to}"` is valid (both placeholders preserved, word order unchanged). A translation value of `"Envoyer à {to}"` is invalid and MUST be rejected by validators, since it drops the `{value}` placeholder.

## Reference Implementation

See [`erc7730-i18n-v3.0.0-next.schema.json`](../assets/erc-7730-localization/erc7730-i18n-v3.0.0-next.schema.json) for the translation file JSON schema, and [`example-main.fr.json`](../assets/erc-7730-localization/example-main.fr.json) for a complete translation file referenced by the [ERC-7730](./eip-7730.md) example descriptor.

## Security Considerations

Translation resources are fetched from the same kind of untrusted or semi-trusted hosts as the descriptors that reference them, and are subject to the same [registry poisoning](./eip-7730.md#registry-poisoning) concerns discussed in ERC-7730. A malicious or compromised translation resource can alter what a user is shown without altering the descriptor itself, so the integrity mechanism in this specification is not optional in practice: wallets that resolve an `$i18n` entry without a verifiable integrity fragment are trusting the host of that resource outright, and SHOULD surface that trust gap to the user rather than silently proceeding.

Missing or malformed translations must never fail open into an incorrect but plausible-looking string; wallets MUST fall back to the literal English value and SHOULD warn the user, rather than displaying a partially-resolved or truncated string. The placeholder-preservation check for interpolated strings is a validator-time, not just a wallet-time, concern: registries curating translation resources SHOULD reject files that drop or reorder-corrupt placeholders before they ever reach a wallet.

The shared vocabulary namespace introduces a second trust boundary: a wallet resolving `common.*` keys against a shared package is trusting that package's publisher for every descriptor that uses it, not just one. Wallets SHOULD apply the same integrity verification to the shared package as to any other translation resource.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
