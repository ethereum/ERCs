---
eip: 1
title: ERC Purpose and Guidelines
status: Living
type: Meta
author: Martin Becze <mb@ethereum.org>, Hudson Jameson <hudson@ethereum.org>, et al.
created: 2015-10-27
---

### **What is an ERC?**

ERC stands for Ethereum Request for Comment. An ERC is a design document providing information to the Ethereum community or proposing a new standard for application-level protocols, interfaces, or conventions within the Ethereum ecosystem. The ERC should include a concise technical specification of the standard and a rationale for its adoption.

ERCs are:

- **Independent of Ethereum Core Protocol Changes**: ERCs do not require consensus from Ethereum Core Developers or execution via hard forks.
- **Consensus-Driven Among Stakeholders**: ERCs achieve finality based on broad consensus among authors, implementers, and the community.
- **Application-Focused**: ERCs address the needs of developers, dapps, and infrastructure providers.

Unlike Ethereum Improvement Proposals (EIPs), ERCs focus on standards for applications and infrastructure surrounding Ethereum, independent of core protocol changes or hard forks. This process aims to foster community-driven innovation and ensure the adoption of robust and interoperable standards.

## ERC Rationale

We intend ERCs to be the primary mechanisms for proposing new standards, collecting community technical input, and documenting the design decisions that shape Ethereum’s ecosystem. Because ERCs are maintained as text files in a versioned repository, their revision history serves as the historical record of the proposal.

For Ethereum implementers, ERCs provide a convenient way to track the progress of standard adoption. Ideally, each implementation maintainer would list the ERCs they have implemented, offering end users a clear understanding of the current status of a given implementation or library.

## ERC Types

There are three types of ERC:

- A **Standards Track ERC** outlines any technical standard that impacts the broader Ethereum ecosystem, including proposed conventions or specifications for decentralized applications, wallets, smart contracts, or their interoperability. These ERCs often include detailed design documents, implementation guidelines, and, if applicable, updates to formal specifications. Standards Track ERCs serve as the foundation for creating cohesive and interoperable tools and protocols within the Ethereum ecosystem.
Standards Track ERCs are further divided into the following subcategories:

  - **Apps**: These ERCs define standards for decentralized applications. They cover APIs, conventions, and data formats to ensure dapp interoperability and smooth intercommunication with wallets.

  - **Wallets**: These ERCs focus on standards specific to wallet implementations. This includes features like transaction signing protocols, account management, and interoperability with other Ethereum ecosystem tools.

  - **Smart Contracts**: These ERCs specify standards for smart contract design, such as reusable templates, interaction patterns, or security practices. They aim to improve code reliability, compatibility, and efficiency in smart contract development.

- A **Meta ERC** describes a process surrounding the Ethereum ecosystem or proposes a change to a process. Meta ERCs are procedural and do not propose changes to Ethereum's core protocol or applications themselves. They often require community consensus and may include guidelines, decision-making processes, or changes to development tools and environments. Meta ERCs are crucial for maintaining and improving Ethereum’s ecosystem-wide workflows.

- **Informational ERC** provides general guidance or information to the Ethereum community. Unlike Standards Track ERCs, they do not define new standards or require implementation but serve as references for best practices or clarifications.
follow their advice.

It is highly recommended that a single ERC contain a single key proposal or new idea. The more focused the ERC, the more successful it tends to be. A change to one client doesn't require an ERC; a change that affects multiple clients, or defines a standard for multiple apps to use, does.

An ERC must meet certain minimum criteria. It must be a clear and complete description of the proposed enhancement. The enhancement must represent a net improvement. The proposed implementation, if applicable, must be solid and must not complicate the protocol unduly.
## ERC Work Flow

### Shepherding an ERC

Parties involved in the process are you, the champion or *ERC author*, the [*ERC editors*](#eip-editors), and the [*Ethereum Core Developers*](https://github.com/ethereum/pm).

Before you begin writing a formal ERC, you should vet your idea. Ask the Ethereum community first if an idea is original to avoid wasting time on something that will be rejected based on prior research. It is thus recommended to open a discussion thread on [the Ethereum Magicians forum](https://ethereum-magicians.org/) to do this.

Once the idea has been vetted, your next responsibility will be to present (by means of an ERC) the idea to the reviewers and all interested parties, invite editors, developers, and the community to give feedback on the aforementioned channels. You should try and gauge whether the interest in your ERC is commensurate with both the work involved in implementing it and how many parties will have to conform to it. Negative community feedback will be taken into consideration and may prevent your ERC from moving past the Draft stage.

### ERC Process

The following is the standardization process for all ERCs in all tracks:

![EIP Status Diagram](../assets/eip-1/EIP-process-update.jpg)

**Idea** - An idea that is pre-draft. This is not tracked within the ERC Repository.

**Draft** - The first formally tracked stage of an ERC in development. An ERC is merged by an ERC Editor into the ERC repository when properly formatted.

**Review** - An ERC Author marks an ERC as ready for and requesting Peer Review.

**Last Call** - This is the final review window for an ERC before moving to `Final`. An ERC editor will assign `Last Call` status and set a review end date (`last-call-deadline`), typically 14 days later.

If this period results in necessary normative changes it will revert the ERC to `Review`.

**Final** - This ERC represents the final standard. A Final ERC exists in a state of finality and should only be updated to correct errata and add non-normative clarifications.

A PR moving an ERC from Last Call to Final SHOULD contain no changes other than the status update. Any content or editorial proposed change SHOULD be separate from this status-updating PR and committed prior to it.

**Stagnant** - Any ERC in `Draft` or `Review` or `Last Call` if inactive for a period of 6 months or greater is moved to `Stagnant`. An ERC may be resurrected from this state by Authors or ERC Editors through moving it back to `Draft` or it's earlier status. If not resurrected, a proposal may stay forever in this status.

>*ERC Authors are notified of any algorithmic change to the status of their ERC*

**Withdrawn** - The ERC Author(s) have withdrawn the proposed ERC. This state has finality and can no longer be resurrected using this ERC number. If the idea is pursued at a later date it is considered a new proposal.

**Living** - A special status for ERCs that are designed to be continually updated and not reach a state of finality. This includes most notably ERC-1.

## What belongs in a successful ERC?

Each EIP should have the following parts:

- Preamble - RFC 822 style headers containing metadata about the EIP, including the EIP number, a short descriptive title (limited to a maximum of 44 characters), a description (limited to a maximum of 140 characters), and the author details. Irrespective of the category, the title and description should not include EIP number. See [below](./eip-1.md#eip-header-preamble) for details.
- Abstract - Abstract is a multi-sentence (short paragraph) technical summary. This should be a very terse and human-readable version of the specification section. Someone should be able to read only the abstract to get the gist of what this specification does.
- Motivation *(optional)* - A motivation section is critical for EIPs that want to change the Ethereum protocol. It should clearly explain why the existing protocol specification is inadequate to address the problem that the EIP solves. This section may be omitted if the motivation is evident.
- Specification - The technical specification should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations for any of the current Ethereum platforms (besu, erigon, ethereumjs, go-ethereum, nethermind, or others).
- Rationale - The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages. The rationale should discuss important objections or concerns raised during discussion around the EIP.
- Backwards Compatibility *(optional)* - All EIPs that introduce backwards incompatibilities must include a section describing these incompatibilities and their consequences. The EIP must explain how the author proposes to deal with these incompatibilities. This section may be omitted if the proposal does not introduce any backwards incompatibilities, but this section must be included if backward incompatibilities exist.
- Test Cases *(optional)* - Test cases for an implementation are mandatory for EIPs that are affecting consensus changes. Tests should either be inlined in the EIP as data (such as input/expected output pairs, or included in `../assets/eip-###/<filename>`. This section may be omitted for non-Core proposals.
- Reference Implementation *(optional)* - An optional section that contains a reference/example implementation that people can use to assist in understanding or implementing this specification. This section may be omitted for all EIPs.
- Security Considerations - All EIPs must contain a section that discusses the security implications/considerations relevant to the proposed change. Include information that might be important for security discussions, surfaces risks and can be used throughout the life-cycle of the proposal. E.g. include security-relevant design decisions, concerns, important discussions, implementation-specific guidance and pitfalls, an outline of threats and risks and how they are being addressed. EIP submissions missing the "Security Considerations" section will be rejected. An EIP cannot proceed to status "Final" without a Security Considerations discussion deemed sufficient by the reviewers.
- Copyright Waiver - All EIPs must be in the public domain. The copyright waiver MUST link to the license file and use the following wording: `Copyright and related rights waived via [CC0](../LICENSE.md).`

## EIP Formats and Templates

EIPs should be written in [markdown](https://github.com/adam-p/markdown-here/wiki/Markdown-Cheatsheet) format. There is a [template](https://github.com/ethereum/EIPs/blob/master/eip-template.md) to follow.

## EIP Header Preamble

Each EIP must begin with an [RFC 822](https://www.ietf.org/rfc/rfc822.txt) style header preamble, preceded and followed by three hyphens (`---`). This header is also termed ["front matter" by Jekyll](https://jekyllrb.com/docs/front-matter/). The headers must appear in the following order.

`eip`: *EIP number*

`title`: *The EIP title is a few words, not a complete sentence*

`description`: *Description is one full (short) sentence*

`author`: *The list of the author's or authors' name(s) and/or username(s), or name(s) and email(s). Details are below.*

`discussions-to`: *The url pointing to the official discussion thread*

`status`: *Draft, Review, Last Call, Final, Stagnant, Withdrawn, Living*

`last-call-deadline`: *The date last call period ends on* (Optional field, only needed when status is `Last Call`)

`type`: *One of `Standards Track`, `Meta`, or `Informational`*

`category`: *One or more of `Apps`, `Wallets`, `Smart Contracts`*

`created`: *Date the EIP was created on*

`requires`: *EIP number(s)* (Optional field)

`withdrawal-reason`: *A sentence explaining why the EIP was withdrawn.* (Optional field, only needed when status is `Withdrawn`)

Headers that permit lists must separate elements with commas.

Headers requiring dates will always do so in the format of ISO 8601 (yyyy-mm-dd).

### `author` header

The `author` header lists the names, email addresses or usernames of the authors/owners of the EIP. Those who prefer anonymity may use a username only, or a first name and a username. The format of the `author` header value must be:

> Random J. User &lt;address@dom.ain&gt;

or

> Random J. User (@username)

or

> Random J. User (@username) &lt;address@dom.ain&gt;

if the email address and/or GitHub username is included, and

> Random J. User

if neither the email address nor the GitHub username are given.

At least one author must use a GitHub username, in order to get notified on change requests and have the capability to approve or reject them.

### `discussions-to` header

While an EIP is a draft, a `discussions-to` header will indicate the URL where the EIP is being discussed.

The preferred discussion URL is a topic on [Ethereum Magicians](https://ethereum-magicians.org/). The URL cannot point to Github pull requests, any URL which is ephemeral, and any URL which can get locked over time (i.e. Reddit topics).

### `type` header

The `type` header specifies the type of EIP: Standards Track, Meta, or Informational. If the track is Standards please include the subcategories (Wallet, Application, Smart Contract).

### `created` header

The `created` header records the date that the EIP was assigned a number. Both headers should be in yyyy-mm-dd format, e.g. 2001-08-14.

### `requires` header

EIPs may have a `requires` header, indicating the EIP numbers that this EIP depends on. If such a dependency exists, this field is required.

A `requires` dependency is created when the current EIP cannot be understood or implemented without a concept or technical element from another EIP. Merely mentioning another EIP does not necessarily create such a dependency.

## Linking to External Resources

Other than the specific exceptions listed below, links to external resources **SHOULD NOT** be included. External resources may disappear, move, or change unexpectedly.

The process governing permitted external resources is described in [EIP-5757](./eip-5757.md).

### Execution Client Specifications

Links to the Ethereum Execution Client Specifications may be included using normal markdown syntax, such as:

```markdown
[Ethereum Execution Client Specifications](https://github.com/ethereum/execution-specs/blob/9a1f22311f517401fed6c939a159b55600c454af/README.md)
```

Which renders to:

[Ethereum Execution Client Specifications](https://github.com/ethereum/execution-specs/blob/9a1f22311f517401fed6c939a159b55600c454af/README.md)

Permitted Execution Client Specifications URLs must anchor to a specific commit, and so must match this regular expression:

```regex
^(https://github.com/ethereum/execution-specs/(blob|commit)/[0-9a-f]{40}/.*|https://github.com/ethereum/execution-specs/tree/[0-9a-f]{40}/.*)$
```

### Consensus Layer Specifications

Links to specific commits of files within the Ethereum Consensus Layer Specifications may be included using normal markdown syntax, such as:

```markdown
[Beacon Chain](https://github.com/ethereum/consensus-specs/blob/26695a9fdb747ecbe4f0bb9812fedbc402e5e18c/specs/sharding/beacon-chain.md)
```

Which renders to:

[Beacon Chain](https://github.com/ethereum/consensus-specs/blob/26695a9fdb747ecbe4f0bb9812fedbc402e5e18c/specs/sharding/beacon-chain.md)

Permitted Consensus Layer Specifications URLs must anchor to a specific commit, and so must match this regular expression:

```regex
^https://github.com/ethereum/consensus-specs/(blob|commit)/[0-9a-f]{40}/.*$
```

### Networking Specifications

Links to specific commits of files within the Ethereum Networking Specifications may be included using normal markdown syntax, such as:

```markdown
[Ethereum Wire Protocol](https://github.com/ethereum/devp2p/blob/40ab248bf7e017e83cc9812a4e048446709623e8/caps/eth.md)
```

Which renders as:

[Ethereum Wire Protocol](https://github.com/ethereum/devp2p/blob/40ab248bf7e017e83cc9812a4e048446709623e8/caps/eth.md)

Permitted Networking Specifications URLs must anchor to a specific commit, and so must match this regular expression:

```regex
^https://github.com/ethereum/devp2p/(blob|commit)/[0-9a-f]{40}/.*$
```

### World Wide Web Consortium (W3C)

Links to a W3C "Recommendation" status specification may be included using normal markdown syntax. For example, the following link would be allowed:

```markdown
[Secure Contexts](https://www.w3.org/TR/2021/CRD-secure-contexts-20210918/)
```

Which renders as:

[Secure Contexts](https://www.w3.org/TR/2021/CRD-secure-contexts-20210918/)

Permitted W3C recommendation URLs MUST anchor to a specification in the technical reports namespace with a date, and so MUST match this regular expression:

```regex
^https://www\.w3\.org/TR/[0-9][0-9][0-9][0-9]/.*$
```

### Web Hypertext Application Technology Working Group (WHATWG)

Links to WHATWG specifications may be included using normal markdown syntax, such as:

```markdown
[HTML](https://html.spec.whatwg.org/commit-snapshots/578def68a9735a1e36610a6789245ddfc13d24e0/)
```

Which renders as:

[HTML](https://html.spec.whatwg.org/commit-snapshots/578def68a9735a1e36610a6789245ddfc13d24e0/)

Permitted WHATWG specification URLs must anchor to a specification defined in the `spec` subdomain (idea specifications are not allowed) and to a commit snapshot, and so must match this regular expression:

```regex
^https:\/\/[a-z]*\.spec\.whatwg\.org/commit-snapshots/[0-9a-f]{40}/$
```

Although not recommended by WHATWG, EIPs must anchor to a particular commit so that future readers can refer to the exact version of the living standard that existed at the time the EIP was finalized. This gives readers sufficient information to maintain compatibility, if they so choose, with the version referenced by the EIP and the current living standard.

### Internet Engineering Task Force (IETF)

Links to an IETF Request For Comment (RFC) specification may be included using normal markdown syntax, such as:

```markdown
[RFC 8446](https://www.rfc-editor.org/rfc/rfc8446)
```

Which renders as:

[RFC 8446](https://www.rfc-editor.org/rfc/rfc8446)

Permitted IETF specification URLs MUST anchor to a specification with an assigned RFC number (meaning cannot reference internet drafts), and so MUST match this regular expression:

```regex
^https:\/\/www.rfc-editor.org\/rfc\/.*$
```

### Bitcoin Improvement Proposal

Links to Bitcoin Improvement Proposals may be included using normal markdown syntax, such as:

```markdown
[BIP 38](https://github.com/bitcoin/bips/blob/3db736243cd01389a4dfd98738204df1856dc5b9/bip-0038.mediawiki)
```

Which renders to:

[BIP 38](https://github.com/bitcoin/bips/blob/3db736243cd01389a4dfd98738204df1856dc5b9/bip-0038.mediawiki)

Permitted Bitcoin Improvement Proposal URLs must anchor to a specific commit, and so must match this regular expression:

```regex
^(https://github.com/bitcoin/bips/blob/[0-9a-f]{40}/bip-[0-9]+\.mediawiki)$
```

### National Vulnerability Database (NVD)

Links to the Common Vulnerabilities and Exposures (CVE) system as published by the National Institute of Standards and Technology (NIST) may be included, provided they are qualified by the date of the most recent change, using the following syntax:

```markdown
[CVE-2023-29638 (2023-10-17T10:14:15)](https://nvd.nist.gov/vuln/detail/CVE-2023-29638)
```

Which renders to:

[CVE-2023-29638 (2023-10-17T10:14:15)](https://nvd.nist.gov/vuln/detail/CVE-2023-29638)

### Digital Object Identifier System

Links qualified with a Digital Object Identifier (DOI) may be included using the following syntax:

````markdown
This is a sentence with a footnote.[^1]

[^1]:
    ```csl-json
    {
      "type": "article",
      "id": 1,
      "author": [
        {
          "family": "Jameson",
          "given": "Hudson"
        }
      ],
      "DOI": "00.0000/a00000-000-0000-y",
      "title": "An Interesting Article",
      "original-date": {
        "date-parts": [
          [2022, 12, 31]
        ]
      },
      "URL": "https://sly-hub.invalid/00.0000/a00000-000-0000-y",
      "custom": {
        "additional-urls": [
          "https://example.com/an-interesting-article.pdf"
        ]
      }
    }
    ```
````

Which renders to:

<!-- markdownlint-capture -->
<!-- markdownlint-disable code-block-style -->

This is a sentence with a footnote.[^1]

[^1]:
    ```csl-json
    {
      "type": "article",
      "id": 1,
      "author": [
        {
          "family": "Jameson",
          "given": "Hudson"
        }
      ],
      "DOI": "00.0000/a00000-000-0000-y",
      "title": "An Interesting Article",
      "original-date": {
        "date-parts": [
          [2022, 12, 31]
        ]
      },
      "URL": "https://sly-hub.invalid/00.0000/a00000-000-0000-y",
      "custom": {
        "additional-urls": [
          "https://example.com/an-interesting-article.pdf"
        ]
      }
    }
    ```

<!-- markdownlint-restore -->

See the [Citation Style Language Schema](https://resource.citationstyles.org/schema/v1.0/input/json/csl-data.json) for the supported fields. In addition to passing validation against that schema, references must include a DOI and at least one URL.

The top-level URL field must resolve to a copy of the referenced document which can be viewed at zero cost. Values under `additional-urls` must also resolve to a copy of the referenced document, but may charge a fee.

## Linking to other EIPs

References to other EIPs should follow the format `EIP-N` where `N` is the EIP number you are referring to.  Each EIP that is referenced in an EIP **MUST** be accompanied by a relative markdown link the first time it is referenced, and **MAY** be accompanied by a link on subsequent references.  The link **MUST** always be done via relative paths so that the links work in this GitHub repository, forks of this repository, the main EIPs site, mirrors of the main EIP site, etc.  For example, you would link to this EIP as `./eip-1.md`.

## Auxiliary Files

Images, diagrams and auxiliary files should be included in a subdirectory of the `assets` folder for that EIP as follows: `assets/eip-N` (where **N** is to be replaced with the EIP number). When linking to an image in the EIP, use relative links such as `../assets/eip-1/image.png`.

## Transferring EIP Ownership

It occasionally becomes necessary to transfer ownership of EIPs to a new champion. In general, we'd like to retain the original author as a co-author of the transferred EIP, but that's really up to the original author. A good reason to transfer ownership is because the original author no longer has the time or interest in updating it or following through with the EIP process, or has fallen off the face of the 'net (i.e. is unreachable or isn't responding to email). A bad reason to transfer ownership is because you don't agree with the direction of the EIP. We try to build consensus around an EIP, but if that's not possible, you can always submit a competing EIP.

If you are interested in assuming ownership of an EIP, send a message asking to take over, addressed to both the original author and the EIP editor. If the original author doesn't respond to the email in a timely manner, the EIP editor will make a unilateral decision (it's not like such decisions can't be reversed :)).

## EIP Editors

The current EIP editors are

- Matt Garnett (@lightclient)
- Sam Wilson (@SamWilsn)
- Zainan Victor Zhou (@xinbenlv)
- Gajinder Singh (@g11tech)

Emeritus EIP editors are

- Alex Beregszaszi (@axic)
- Casey Detrio (@cdetrio)
- Gavin John (@Pandapip1)
- Greg Colvin (@gcolvin)
- Hudson Jameson (@Souptacular)
- Martin Becze (@wanderer)
- Micah Zoltu (@MicahZoltu)
- Nick Johnson (@arachnid)
- Nick Savers (@nicksavers)
- Vitalik Buterin (@vbuterin)

If you would like to become an EIP editor, please check [EIP-5069](./eip-5069.md).

## EIP Editor Responsibilities

For each new EIP that comes in, an editor does the following:

- Read the EIP to check if it is ready: sound and complete. The ideas must make technical sense, even if they don't seem likely to get to final status.
- The title should accurately describe the content.
- Check the EIP for language (spelling, grammar, sentence structure, etc.), markup (GitHub flavored Markdown), code style

If the EIP isn't ready, the editor will send it back to the author for revision, with specific instructions.

Once the EIP is ready for the repository, the EIP editor will:

- Assign an EIP number (generally incremental; editors can reassign if number sniping is suspected)
- Merge the corresponding [pull request](https://github.com/ethereum/EIPs/pulls)
- Send a message back to the EIP author with the next step.

Many EIPs are written and maintained by developers with write access to the Ethereum codebase. The EIP editors monitor EIP changes, and correct any structure, grammar, spelling, or markup mistakes we see.

The editors don't pass judgment on EIPs. We merely do the administrative & editorial part.

## Style Guide

### Titles

The `title` field in the preamble:

- Should not include the word "standard" or any variation thereof; and
- Should not include the EIP's number.

### Descriptions

The `description` field in the preamble:

- Should not include the word "standard" or any variation thereof; and
- Should not include the EIP's number.

### EIP numbers

When referring to an EIP with a `category` of `ERC`, it must be written in the hyphenated form `ERC-X` where `X` is that EIP's assigned number. When referring to EIPs with any other `category`, it must be written in the hyphenated form `EIP-X` where `X` is that EIP's assigned number.

### RFC 2119 and RFC 8174

EIPs are encouraged to follow [RFC 2119](https://www.ietf.org/rfc/rfc2119.html) and [RFC 8174](https://www.ietf.org/rfc/rfc8174.html) for terminology and to insert the following at the beginning of the Specification section:

> The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

## History

This document was derived heavily from [Bitcoin's BIP-0001](https://github.com/bitcoin/bips) written by Amir Taaki which in turn was derived from [Python's PEP-0001](https://peps.python.org/). In many places text was simply copied and modified. Although the PEP-0001 text was written by Barry Warsaw, Jeremy Hylton, and David Goodger, they are not responsible for its use in the Ethereum Improvement Process, and should not be bothered with technical questions specific to Ethereum or the EIP. Please direct all comments to the EIP editors.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
