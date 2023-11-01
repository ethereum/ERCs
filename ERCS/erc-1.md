---
erc: 1
title: ERC Purpose and Guidelines
status: draft
type: Meta
author: Joachim Lebrun (@Joachim-Lebrun), Emmanuel (Mawuko.eth)
created: 2023-10-30
---

## What is an ERC?

ERC stands for **Ethereum Request for Comments**. An ERC is a proposed design document that provides information to the Ethereum community, with a specific focus on application-level standards and conventions. These encompass token standards, wallet standards, metadata standards, DAO standards, registry formats, library/package formats, and more.

Each ERC should present a clear technical specification of the standard and a rationale for its adoption.

An ERC author is responsible for building consensus within the community and documenting dissenting opinions, ensuring that the proposal addresses a common need and adds credible value to the Ethereum (app) ecosystem.

## ERC Rationale

We intend ERCs to be the primary mechanisms for proposing new application-level standards and conventions within the Ethereum ecosystem, such as token standards, name registries, and interface specifications. ERCs serve as a process for gathering community (technical) input and insights on specific issues and for documenting the design decisions that shape Ethereum's application layer. Since ERCs are maintained as text files in a versioned repository, their revision history forms the historical record of the standard proposal.

For developers and project teams working within the Ethereum space, ERCs provide a structured way to track the evolution and adoption of various application-level standards. Ideally, each project or library maintainer would list the ERCs that they have adopted or implemented. This would offer end users and other developers a convenient method to understand the compatibility and feature set of different projects, libraries, or applications within the Ethereum ecosystem.

## ERC Document

### What Belongs in a Successful ERC? (Structure)

Each ERC should have the following parts:

| Name                                 | Description                                                                                                                                                                                                                                                                                                                               |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Preamble                             | RFC 822 style headers containing metadata about the ERC, including the ERC number, a short descriptive title (limited to a maximum of 44 characters), a description (limited to a maximum of 140 characters), and the author details. Irrespective of the category, the title and description should not include ERC number. See [below](./erc-1.md#erc-header-preamble) for details. |
| Abstract                             | A multi-sentence (short paragraph) technical summary. This should be a very terse and human-readable version of the specification section. Someone should be able to read only the abstract to get the gist of what this specification does.                                                                                                        |
| Motivation                           | A motivation section is critical for ERCs that propose significant changes or introduce new standards. It should clearly explain why the existing standards or practices are inadequate and how the ERC addresses this inadequacy. This section may be omitted if the motivation is evident.                                      |
| Specification                        | The technical specification should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations within the Ethereum ecosystem. Visual aids or flow diagrams are encouraged for complex mechanisms.                                                  |
| Rationale                            | The rationale should elaborate on the specification by describing what motivated the design and why particular design decisions were made. It should discuss alternate designs, related work, and address important objections or concerns raised during discussion. It must also explain how the proposal affects the backward compatibility of existing solutions when applicable. If the proposal responds to a [CPS][], the 'Rationale' section should explain how it addresses the CPS and answer any questions that the CPS poses for potential solutions. |
| Backwards Compatibility              | All ERCs that introduce backwards incompatibilities must include a section describing these incompatibilities and their consequences. The ERC must explain how the author proposes to deal with these incompatibilities. This section should also discuss the impact on existing contracts or standards, particularly focusing on how the new ERC would coexist or transition from them, including any inheritance from other ERCs.                         |
| Test Cases                           | Test cases for an implementation are encouraged for ERCs, especially those proposing new standards. Providing a suite of standard test cases is highly beneficial. Tests should either be inlined in the ERC or included in `../assets/erc-###/<filename>`.                                                                                       |
| Reference Implementation             | An optional section that contains a reference/example implementation that people can use to assist in understanding or implementing this specification. This section is particularly useful for complex ERCs and is strongly encouraged.                                                                                                          |
| Security Considerations              | All ERCs must contain a section that discusses the security implications/considerations relevant to the proposed change. This section should include security-relevant design decisions, concerns, important discussions, implementation-specific guidance, common pitfalls, known attack vectors, and an outline of threats and risks and how they are being addressed.                                      |
| Copyright Waiver                     | All ERCs must be in the public domain. The copyright waiver MUST link to the license file and use the following wording: `Copyright and related rights waived via [CC0](../LICENSE.md).`                                                                                                                                            |

#### ERC Formats and Templates

ERCs should be written in [markdown](https://github.com/adam-p/markdown-here/wiki/Markdown-Cheatsheet) format. There is a [template](https://github.com/ethereum/ERCs/blob/master/erc-template.md) to follow.

#### ERC Header Preamble

Each ERC must begin with an [RFC 822](https://www.ietf.org/rfc/rfc822.txt) style header preamble, preceded and followed by three hyphens (`---`). This header is also termed ["front matter" by Jekyll](https://jekyllrb.com/docs/front-matter/). The headers must appear in the following order.

| Field               | Description                                                                                                                                                                                                                                                                                     |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| erc                 | *ERC number*                                                                                                                                                                                                                                                                                    |
| title               | *The ERC title is a few words, not a complete sentence*                                                                                                                                                                                                                                      |
| description         | *Description is one full (short) sentence*                                                                                                                                                                                                                                                    |
| author              | *The list of the author's or authors' name(s) and/or username(s), or name(s) and email(s). Details are below.*                                                                                                                                                                                   |
| discussions-to      | *The url pointing to the official discussion thread*                                                                                                                                                                                                                                           |
| status              | *Draft, Review, Last Call, Final, Stagnant, Withdrawn, Living*                                                                                                                                                                                                                                   |
| last-call-deadline  | *The date last call period ends on* (Optional field, only needed when status is `Last Call`)                                                                                                                                                                                                   |
| type                | *One of `Standards Track`, `Meta`, or `Informational`*                                                                                                                                                                                                                                          |
| category            | *One of `Token`, `Registry`, `Interface`, `Package Format`,`DAO`, `Metadata`, or `Wallet`* (Required for `Standards Track` and `Informational` ERCs, optional for `Meta` ERCs)                                                                                                                          |
| subcategory         | *One of `NFT`, `FT`, `SFT`,`SBT`,`RWA`,`Hardware Wallet`,`Software Wallet`, `UserOp`, or `Account Abstraction`* (Optional field; other values can be suggested in proposal and reviewed by ERC Editors) 
| created             | *Date the ERC was created on*                                                                                                                                                                                                                                                                  |
| requires            | *ERC number(s)* (Optional field, especially relevant for ERCs that inherit or extend functionality from other ERCs)                                                                                                                                                                           |
| withdrawal-reason   | *A sentence explaining why the ERC was withdrawn.* (Optional field, only needed when status is `Withdrawn`)                                                                                                                                                                                   |

Headers that permit lists must separate elements with commas.

Headers requiring dates will always do so in the format of ISO 8601 (yyyy-mm-dd).

### `author` header

The `author` header lists the names, email addresses or usernames of the authors/owners of the ERC. Those who prefer anonymity may use a username only, or a first name and a username. The format of the `author` header value must be:

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

While an ERC is a draft, a `discussions-to` header will indicate the URL where the ERC is being discussed.

The preferred discussion URL is a topic on [Ethereum Magicians](https://ethereum-magicians.org/). The URL cannot point to Github pull requests, any URL which is ephemeral, and any URL which can get locked over time (i.e. Reddit topics).

### `type` header

The `type` header specifies the type of ERC: Standards Track, Meta, or Informational.

### `category` header

The `category` header specifies the ERC's category. This is required for either Standards Track, Meta, or Informational ERCs.

### `subcategory` header

The `subcategory` header specifies the ERC's category. This is optional for either Standards Track, Meta, or Informational ERCs.

### `created` header

The `created` header records the date that the ERC was assigned a number. Both headers should be in yyyy-mm-dd format, e.g. 2001-08-14.

### `requires` header

ERCs may have a `requires` header, indicating the ERC numbers that this ERC depends on. If such a dependency exists, this field is required.

A `requires` dependency is created when the current ERC cannot be understood or implemented without a concept or technical element from another ERC. Merely mentioning another ERC does not necessarily create such a dependency. This is particularly relevant for ERCs that inherit or extend functionality from other ERCs.

### ERC Taxonomy: Types, Categories, and Subcategories

ERCs are grouped according to a distinct taxonomy that helps organize them.

This convention enables application-level developers, contributors, and enthusiasts to clearly understand the precise scope of an ERC.

In descending order, this taxonomy consists of Types, Categories, and Subcategories.

Visual aide:
 
```
ERC
  |__Type: Standards Track | Meta | Informational
        |__Category: Wallet | Token | Registry | Interface | Package Format | DAO | Metadata Schema
              |__Subcategory: NFT | FT | SFT | SBT | RWA | Hardware Wallet | Software Wallet | UserOp | or | Account Abstraction
 
```

#### Types
There are three **Types** of ERC:

| Type              | Description                                                                                                                                                                                                                                                                                              |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Standards Track   | A **Standards Track ERC** describes any change that affects most or all applications within the Ethereum ecosystem. This includes, but is not limited to, contract standards such as token standards, name registries, URI schemes, library/package formats, and wallet formats.                                  |
| Meta              | A **Meta ERC** describes a process surrounding Ethereum application-level standards or proposes a change to (or an event in) a process. Meta ERCs are like Standards Track ERCs but apply to areas other than the Ethereum protocol itself. They often require community consensus; unlike **Informational ERCs**, they are more than recommendations, and users are typically not free to ignore them. Examples include procedures, guidelines, changes to the decision-making process, and changes to the tools or environment used in Ethereum application development. |
| Informational     | An **Informational ERC** describes an Ethereum app design issue or provides general guidelines or information to the Ethereum community but does not propose a new feature. Informational ERCs do not necessarily represent Ethereum community consensus, and they mostly serve as a recommendation, so users and implementers are free to ignore or follow their advice.                                            |

#### Categories
An ERC is grouped into a **Category** in addition to its **Type**.

Categories are meant to be flexible and evolve as new domains emerge.
 
At present, we consider the following set of initial Categories:

| Category         | Description                                                                                                                                                                                                                                                              |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Token            | Proposals for new types of tokens or improvements to existing token standards (e.g., ERC-20, ERC-721, ERC-1155, ERC-3643).                                                                                                                                                 |
| Registry          | Standards for name registries, identity systems, and other types of registries.                                                                                                                                                                                           |
| Interface         | Proposals for standardized interfaces, such as contract ABIs, API interfaces, and communication protocols between contracts.                                                                                                                                            |
| Package Format    | Standards for library and package formats, including guidelines for reusable contract code and modular design.                                                                                                                                                          |
| Wallet           | Proposals for wallet standards such as hardware or software wallets, program-managed accounts, and transaction signing rules.                                                                                                                                          |
| Metadata         | Proposals for on-chain/off-chain metadata standards used in apps, tokens, etc. (Eg: Digital Art, collectibles, RWAs, Voting, etc.)                                                                                                                                        |
| DAO              | Proposals for DAO standards and practices.                                                                                                                                                                                                                               |

#### Subcategories (Optional)
After being grouped under a **Type** and **Category**, an ERC may also be tagged with a Subcategory to indicate the precision of its scope.

Subcategories are **optional** and can be suggested by the proposer. ERC Editors will then review and decide whether to include in official list, or suggest refinements.

For now, we will suggest this initial set of Subcategories:

| Category           | Description                                                                                                                                                                                                                                            |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| NFT                | Proposals for Non-Fungible Tokens, which define unique digital assets like digital art and collectibles.                                                                                                                                               |
| FT                 | Proposals for Fungible Tokens, including standards for interchangeable digital tokens like governance tokens, LP tokens, stablecoins, etc.                                                                                                            |
| SFT                | Proposals for Semi-Fungible Tokens, which represent partially interchangeable digital assets, often used for things like in-game items for on-chain games.                                                                                             |
| SBT                | Proposals for Soulbound Tokens, which represent non-transferable tokens that are linked to a specific address or identity.                                                                                                                           |
| RWA                | Proposals for Real-World Assets, including standards for tokenizing and trading assets tied to the real world, like property or bonds.                                                                                                                |
| Hardware Wallet    | Proposals for hardware-based wallet standards in Ethereum, ensuring secure key management.                                                                                                                                                            |
| Software Wallet    | Proposals for software-based wallet standards in Ethereum, addressing user interface, APIs, and other functionality of wallet apps.                                                                                                                    |
| UserOp             | Proposals for User Operations in intent-driven applications such as CoW Swap, etc.                                                                                                                                                                       |
| Account Abstraction | Proposals for account abstraction solutions and management of program-managed accounts (a.k.a. smart accounts) within Ethereum.                                                                                                                       |


It is highly recommended that a single ERC contain a single key proposal or new idea. The more focused the ERC, the more successful it tends to be. A change to one application doesn't require an ERC; a change that affects multiple applications, or defines a standard for multiple apps to use, does.

An ERC must meet certain minimum criteria. It must be a clear and complete description of the proposed enhancement. The enhancement must represent a net improvement. The proposed implementation, if applicable, must be solid and must not complicate the application ecosystem unduly.

## ERC Work Flow

### Shepherding an ERC

Parties involved in the process are you, the champion or *ERC author*, the [*ERC editors*](#erc-editors), and the broader Ethereum community.

Before you begin drafting a formal ERC, it's crucial to validate your idea. Engage with the Ethereum community to ensure that your concept is original and to avoid spending time on something that may be rejected due to prior research or existing standards. It is recommended to initiate a discussion thread on [the Ethereum Magicians forum](https://ethereum-magicians.org/) or other relevant community platforms for this purpose.

Once your idea has been vetted, your next responsibility is to present it to the community through an ERC. This involves inviting feedback from editors, developers, and all interested parties through the aforementioned channels. Assess the level of interest in your ERC, considering both the effort required for its implementation and the number of parties that will need to adopt it. For instance, an ERC proposing a new token standard may require widespread adoption and significant effort from various project teams. Community feedback, both positive and negative, is crucial and will be taken into account. It may influence the progression of your ERC beyond the Draft stage.

### ERC Process Status

The following is the standardization process status tags for all ERCs:

![ERC Status Diagram](../assets/erc-1/ERC-process-update.jpeg)

**Idea** - An idea that is pre-draft. This is not tracked within the ERC Repository.

**Draft** - The first formally tracked stage of an ERC in development. An ERC is merged by an ERC Editor into the ERC repository when properly formatted.

**Review** - An ERC Author marks an ERC as ready for and requesting Peer Review.

**Last Call** - This is the final review window for an ERC before moving to `Final`. An ERC editor will assign `Last Call` status and set a review end date (`last-call-deadline`), typically 14 days later.

If this period results in necessary normative changes it will revert the ERC to `Review`.

**Final** - This ERC represents the final standard. A Final ERC exists in a state of finality and should only be updated to correct errata and add non-normative clarifications.

A PR moving an ERC from Last Call to Final SHOULD contain no changes other than the status update. Any content or editorial proposed change SHOULD be separate from this status-updating PR and committed prior to it.

**Stagnant** - Any ERC in `Draft` or `Review` or `Last Call` if inactive for a period of 6 months or greater is moved to `Stagnant`. An ERC may be resurrected from this state by Authors or ERC Editors through moving it back to `Draft` or its earlier status. If not resurrected, a proposal may stay forever in this status.

>*ERC Authors are notified of any algorithmic change to the status of their ERC*

**Withdrawn** - The ERC Author(s) have withdrawn the proposed ERC. This state has finality and can no longer be resurrected using this ERC number. If the idea is pursued at a later date it is considered a new proposal.

**Living** - A special status for ERCs that are designed to be continually updated and not reach a state of finality. This could include ERCs that serve as foundational or evolving standards.


## Linking to External Resources

Other than the specific exceptions listed below, links to external resources **SHOULD NOT** be included. External resources may disappear, move, or change unexpectedly.

The process governing permitted external resources is described in [ERC-5757](./erc-5757.md).

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

Although not recommended by WHATWG, ERCs must anchor to a particular commit so that future readers can refer to the exact version of the living standard that existed at the time the ERC was finalized. This gives readers sufficient information to maintain compatibility, if they so choose, with the version referenced by the ERC and the current living standard.

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

## Linking to other ERCs

References to other ERCs should follow the format `ERC-N` where `N` is the ERC number you are referring to.  Each ERC that is referenced in an ERC **MUST** be accompanied by a relative markdown link the first time it is referenced, and**MAY** be accompanied by a link on subsequent references.  The link **MUST** always be done via relative paths so that the links work in this GitHub repository, forks of this repository, the main ERCs site, mirrors of the main ERC site, etc.  For example, you would link to this ERC as `./erc-1.md`.

## Auxiliary Files

Images, diagrams and auxiliary files should be included in a subdirectory of the `assets` folder for that ERC as follows: `assets/erc-N` (where **N** is to be replaced with the ERC number). When linking to an image in the ERC, use relative links such as `../assets/erc-1/image.png`.

## Transferring ERC Ownership

It occasionally becomes necessary to transfer ownership of ERCs to a new champion. In general, we'd like to retain the original author as a co-author of the transferred ERC, but that's really up to the original author. A good reason to transfer ownership is because the original author no longer has the time or interest in updating it or following through with the ERC process, or has fallen off the face of the 'net (i.e. is unreachable or isn't responding to email). A bad reason to transfer ownership is because you don't agree with the direction of the ERC. We try to build consensus around an ERC, but if that's not possible, you can always submit a competing ERC.

If you are interested in assuming ownership of an ERC, send a message asking to take over, addressed to both the original author and the ERC editor. If the original author doesn't respond to the email in a timely manner, the ERC editor will make a unilateral decision (it's not like such decisions can't be reversed :)).

## ERC Editors

The current EIP editors are

- Alex Beregszaszi (@axic)
- Gavin John (@Pandapip1)
- Greg Colvin (@gcolvin)
- Matt Garnett (@lightclient)
- Sam Wilson (@SamWilsn)
- Zainan Victor Zhou (@xinbenlv)
- Gajinder Singh (@g11tech)

Emeritus ERC editors are

- Casey Detrio (@cdetrio)
- Hudson Jameson (@Souptacular)
- Martin Becze (@wanderer)
- Micah Zoltu (@MicahZoltu)
- Nick Johnson (@arachnid)
- Nick Savers (@nicksavers)
- Vitalik Buterin (@vbuterin)

If you would like to become an ERC editor, please check [ERC-5069](./erc-5069.md).

## ERC Editor Responsibilities

For each new ERC that comes in, an editor does the following:

- Read the ERC to check if it is ready: sound and complete. The ideas must make technical sense, even if they don't seem likely to get to final status.
- The title should accurately describe the content.
- Check the ERC for language (spelling, grammar, sentence structure, etc.), markup (GitHub flavored Markdown), code style

If the ERC isn't ready, the editor will send it back to the author for revision, with specific instructions.

Once the ERC is ready for the repository, the ERC editor will:

- Assign an ERC number (generally incremental; editors can reassign if number sniping is suspected)
- Merge the corresponding [pull request](https://github.com/ethereum/ERCs/pulls)
- Send a message back to the ERC author with the next step.

Many ERCs are written and maintained by developers with write access to the Ethereum codebase. The ERC editors monitor ERC changes, and correct any structure, grammar, spelling, or markup mistakes we see.

The editors don't pass judgment on ERCs. We merely do the administrative & editorial part.

## Style Guide

### Titles

The `title` field in the preamble:

- Should not include the word "standard" or any variation thereof; and
- Should not include the ERC's number.

### Descriptions

The `description` field in the preamble:

- Should not include the word "standard" or any variation thereof; and
- Should not include the ERC's number.

### ERC numbers

ERC numbers must be written in the hyphenated form `ERC-X` where `X` is that ERC's assigned number.

ERC numbers must be **odd** numbers.

### RFC 2119 and RFC 8174

ERCs are encouraged to follow [RFC 2119](https://www.ietf.org/rfc/rfc2119.html) and [RFC 8174](https://www.ietf.org/rfc/rfc8174.html) for terminology and to insert the following at the beginning of the Specification section:

> The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

## History

This document was derived heavily from the Ethereum Improvement Proposal [EIP-1](https://github.com/ethereum/EIPs) written by Martin Becze and Hudson Jameson. EIP-1 itself was influenced by [Bitcoin's BIP-0001](https://github.com/bitcoin/bips) authored by Amir Taaki, which in turn was derived from [Python's PEP-0001](https://peps.python.org/). In many places, text from these foundational documents was simply copied and modified to suit the context of Ethereum Request for Comments (ERCs).

Although the PEP-0001 text was written by Barry Warsaw, Jeremy Hylton, and David Goodger, and the EIP-1 text by Martin Becze and Hudson Jameson, they are not responsible for its use in the Ethereum Request for Comments process, and should not be bothered with technical questions specific to the ERCs. Please direct all comments and inquiries related to this document to the ERC editors.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
