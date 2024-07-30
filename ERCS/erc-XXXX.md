---
eip: XXXX
title: Tamperproof Web Immutable Transaction (TWIT)
description: Provides a mechanism for DAP to use the API defined in EIP-1193 in a tamperproof way
author: Erik Marks, Guillaume Grosbois
discussions-to: TODO
status: Draft
type: Standards Track
category: ERC
created: 2024-07-29
requires: 712, 1193
---

## Abstract

A new `secureRequest` method in addition to EIP-1193 `request` for dApp to interact with extension wallets in a tamperproof way, preventing any MITM from modifying the payload sent to the wallet.
This will allow for dApps to sign their interaction with EIP-1193, and for wallet to visibly display secure interaction, therefor improving the end user experience by explicitly displaying safety
visual cues such as a padlock.

## Motivation

The primary motivation for this standard is to enhance the end user experience by ensuring that they can feel safe when interacting with a trusted dApp (this is in essence very similar to HTTPS vs HTTP).

Currently, the communication channel between a dApp and a wallet is vulnerable to man in the middle attacks: an attacker can intercept the communication by injecting javascript code in the page, and subsequently
modify the call data sent by the dApp to the wallet. XSS vulnerability or malicious extension both provide ways for an attacker to inject javascript. Despite EIP-720 increasing the transparency of the data being
signed by the wallet, the average user will in effect rarely confirm the actual content of a transaction because:

* they have trust in specific well known dApp and will not read the detail thoroughly
* the content of the transaction is compressed to save gas and therefore unreadable
* the user is victim of social engineering

The effect can be pernicious as end users will not necessarily realise there is no chain of trust between the dApp backend and the wallet that will send a transaction on the user's behalf: a MITM attack can
capitalize on trusted dApp to syphon funds.

Such an attack can be used in a variety of ways:

* Modify the call data on the fly, as a user is transacting
* Obtain a replayable signature from the user's wallet
* TODO

Overall, the lack of a chain of trust between the dApp and the wallet hurts the ecosystem as a whole:

* users cannot rely on trusting well known dApp, and are at risk of losing funds if they do not manually verify transactions before signing
* dApp maintainer are at risk of losing their trusted reputation if an attacker finds a viable MITM attack

## Specification

### Overview

We are proposing to use the domain certificate of a dApp as a root of trust to establish a trust chain as follow:

1. end user's browser verifies the domain certificate and display appropriate warning if overtaken
2. the DNS record of the dApp hosts a TXT field pointing to a URL where a JSON manifest is hosted (this file SHOULD be at a well known address such as <https://domain.com/.well-known/twit.json>)
3. the config file contains an array of tuple `[alg, public key]`
4. for secure interaction, a dApp would first call their backend to securely sign the payload with a private key
5. the encrypted payload would be sent to the wallet via the `secureRequest` JSON api call
6. the wallet would verify the signature before sending the payload to the `request` JSON api call

### Wallet integration

#### Key discovery

Attested public keys are necessary for the chain of trust to be established. Since this is traditionally done via DNS certificate, we are proposing to anchor directly on the DNS record to point to a
manifest file containing the keys. This is similar to DKIM, but the use of the configuration file provides more flexibility for future improvements, and support for multiple algo/key pairs.

Similarly to standard JWT practices, wallet could heavily cache dApp keys. The correlary is that in the absence of a revocation mechanism, a compromised/leaked key could still be used until caches have expired.
Wallets SHOULD NOT cache dApp public keys for more than 2h in order to reduce balance a relatively short vulnerability window, and manageable overhead for both wallet and dApp maintainers.

Example DNS record for my-crypto-dapp.org:

```txt
...
TXT: TWIT=/.well-known/twit.json
```

Example TWIT manifest at <https://my-crypto-dapp.org/twit.json>:

```json
{
 "publicKeys": [
    {"id": "1", "alg":"ECDSA", "publicKey": "0xaf34..."},
    {"id": "2", "alg":"RSA-PSS", "publicKey": "0x98ab..."}
  ]
}
```

#### Manifest schema

We are proposing a very simple schema that will allow for future security improvements if needed.

```json
{
 "$schema": "https://json-schema.org/draft/2020-12/schema",
    "title": "TWIT manifest",
    "type": "object",
    "properties":{
        "publicKeys": {
         "type": "array",
            "items":{
             "type": "object",
                "properties": {
                  "id": { "type": "string"},
                  "alg": { "type": "string"},
                  "publicKey": { "type": "string"}
                }
            }
        }
    }
}
```

#### Example implementation

We propose to rely on algorithms supported by [SubtleCrypto](https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto) as they are present in every browsers.

We recommend adding new method `secureRequest` to EIP-1193 as it would provide a simple, yet extensive, implementation for secure calls. In addition, it provides
dApp maintainers/devloppers with an explicit way to ask wallets to verify the integrity of the payload, as opposed to an implicit implementations relying on bit
packing of the arguments.

Example:

```typescript
interface RequestArguments { // this interface comes from EIP-1193
  readonly method: string;
  readonly params?: readonly unknown[] | object;
}
async function secureRequest(requestArg: RequestArguments, signature: byte[], keyId:string): Promise<unknown>;{
  // 0. get the domain of the sender.tab.url
  const domain = getActiveTabDomain()

  // 1. get the manifest for the current domain
  // One can use RFC 8484 for the actual DNS-over-HTTPS specification (see https://datatracker.ietf.org/doc/html/rfc8484).
  // here we are doing it with DoHjs
  //
  // Note: this step is optional, and one could opt to go directly to the well-known address first at `domain + '/.well-known/twit.json'`
  const doh = require('dohjs');
  const resolver = new doh.DohResolver('https://1.1.1.1/dns-query');
  let manifestPath = ""
  const dnsResp = await resolver.query(domain, 'TXT')
  for(record of dnsResp.answers){
    if(!record.data.startsWith("TWIT=")) continue;

    manifestPath = record.data.substring(5) // this should be domain + '/.well-known/twit.json'
    break
  }

  // 2. parse the manifest and get they key and algo based on `keyId`
  const manifestReq = await fetch(manifestPath)
  const manifest = await manifestReq.json()
  const keyData = manifest.publicKeys.filter(x => x.id == keyId)
  if(!keyData){ throw new Error("Could not find the signing key")}
  const key = keyData.publidKey
  const alg = keyData.alg

  // 3. verify the signature
  valid = await crypto.verify(alg, key, signature, requestArg)
  if(!valid){
    throw new Error("The data was tampered with")
  }
  return await request(requestArg)
}
```

### Wallet UX suggestion

Similarly to the padlock icon for HTTPS, wallets should display a visible indication when TWIT is configured on a domain. This will improve the UX of the end user who will immediately be able to tell
that interactions between the dApp they are using and the wallet are secure, and this will encourage dApp developper to adopt TWIT, making the overall ecosystem more secure

When dealing with insecure request, either because the dApp (or an attacker) uses `request` on a domain where TWIT is configured, or because the signature does not match, wallets should warn the user but
not block: an eloquently worded warning will increase the transparency enough that end user may opt to cancel the interaction or proceed with the unsafe call.

### Wallet verification spec

1. Upon receiving an EIP-1193 call, a wallet MUST check of the existence of the TWIT manifest for the `sender.tab.url` domain
  a. a wallet MUST verify that the manifest is hosted on the `sender.tab.url` domain
  b. a wallet SHOULD find the DNS TXT record to find the manifest location
  b. a wallet COULD first try the `/.well-known/twit.json` location
2. if TWIT is NOT configured for the `sender.tab.url` domain, then proceed as usual
3. if TWIT is configured AND the `request` method is used, then the wallet MUST display a visible and actionable warning to the user
  a. if the user opts to ignore the warning, then proceed as usual
  b. if the user opts to cancel, then the wallet MUST cancel the call
4. if TWIT is configured AND the `secureRequest` method is used with the parameters `requestArgs`, `signature` and `keyId` then:
  a. the wallet SHOULD display a visible cue indicating that this interaction is signed
  b. the wallet MUST verify that the keyId exists in the TWIT manifest and find the assiciated key record
  c. from the key record, the wallet MUST use the `alg` field and the `publicKey` field to verify `requestArgs` integrity by calling `crypto.verify(alg, key, signature, requestArgs)`
  d. if the signature is invalid, the wallet MUST display a visible and actionable warning to the user
      i. if the user opts to ignore the warning, then proceed to call `request` with the argument `requestArgs`
      ii. if the user opts to cancel, then the wallet MUST cancel the call
  e. if the signature is valid, the wallet MUST call `request` with the argment `requestArgs`

## Security Considerations

### Replay prevention

While signing the `requestArg` payload guarantees data integrity, it does not prevent replay attacks in itself:

1. a signed payload can be replayed multiple times
2. a signed payload can be replayed accross multiple chains

*Effective* time replay attacks as described in `1.` are generally prevented by the transaction nonce.
Cross chain replay can be prevented by leveraging the EIP-712 `signTypedData` method.

Replay attack would still be possible on any method that is not protected by either: this affects effectively all the "readonly" methods
which are of very limited value for an attacker.

For these reason, we do not recommend a specific replay protection mechanism at this time. If/when the need arise, the extensibility of
the manifest will provide the necessary room to enforce a replay protection envelope (eg:JWT) for affected dApp.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
