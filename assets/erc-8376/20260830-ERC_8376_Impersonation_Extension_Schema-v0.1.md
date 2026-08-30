# ERC-8376 Impersonation Extension Schema v0.1

The reference extension schema for `PATTERN_IMPERSONATION`, published at a stable URI as
the Extension Signals section of ERC-8376 requires.

`PATTERN_IMPERSONATION` cannot be scored from the base vector. A deployer may retain no supply, lock liquidity, hold no privileged powers, and read clean on all twelve signals, because the abuse is entirely in the identity claim. It is the reason extension schemas exist and is specified here as their reference.

Schema `keccak256("erc.launch.schema.impersonation")`, version 1:

| Field | Type | Units | Definition | Polarity | Threshold |
| --- | --- | --- | --- | --- | --- |
| `symbolCollision` | `uint16` | bitmask | Established tokens sharing this symbol on this chain, by class: `0x0001` any, `0x0002` one of greater age, `0x0004` one of greater liquidity | Adverse | any bit set |
| `nameSimilarity` | `uint16` | bps | Similarity of the token name to that of an established token, by a published measure the detector MUST name in `evidenceURI` | Adverse | 8000 |
| `metadataReuse` | `uint16` | bps | Share of launch metadata, including logo and stated URIs, identical to an established project's | Adverse | 5000 |

Weights: `symbolCollision` 40, `nameSimilarity` 30, `metadataReuse` 20, `priorUpheldClaims` 10.

"Established" MUST be defined by the deployment and published with the profile. Age and liquidity are both reasonable bases; neither is mandated, because the right threshold differs by chain and venue.

Detectors MUST NOT report `nameSimilarity` from a proprietary measure without naming it. A measure that a third party cannot reproduce cannot be verified, and a bond posted against it cannot be enforced.
