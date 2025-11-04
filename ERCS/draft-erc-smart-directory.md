---
eip: TBD
title: Directory of certified smart-contracts
status: Draft
type: Standards Track
description: Allows a recognized entity to list the valid smart-contract addresses of the actors in its ecosystem.
author: Jose Luu <jose.luu@bpce.fr>, Cyril Vignet <cyril.vignet@bpce.fr>, Vincent Griffault <vincent.griffault@cera.caisse-epargne.fr>, Frederic Faure <frederic.faure@banque-france.fr>, Clement Delaneau <clement.delaneau@banque-france.fr>
created: 2025-9-2
---

## Preliminary note

The ERC presented here originates from a project: [SmartDirectory](https://github.com/BPCE/smart-directory), for convenience in the draft redaction the term "SmartDirectory" is used to designate the smart-contract model subject of this ERC.

## Abstract

The SmartDirectory is an **administered blockchain whitelist** that addresses the proliferation of addresses by ensuring their authenticity for important transactions. It allows an organisation, called a **registrant**, to list the valid smart contract addresses it has deployed. Once an administrator of the recognized authority approves a registrant, that registrant can then record their service-related smart contract addresses in the **"references" list**. Overall the "SmartDirectory" facilitates on-chain verification and the identification and management of smart contract ecosystems.

## Motivation

The rapid proliferation of smart contract addresses poses a critical challenge to users and other smart contracts, necessitating robust mechanisms for **authenticity verification** for any transactions using them. The SmartDirectory emerges as an essential **administered blockchain whitelist**, directly addressing this issue by providing a structured solution for managing trust on-chain.

Its core purpose is to enable organisations, known as **registrants**, to securely expose and maintain the valid smart contract addresses that they operate. Through a streamlined process, administrators of a regognized authority approve registrants, who then gain the ability to deploy and record their service-related smart contracts in a dedicated **"references" list**. The SmartDirectory is vital for enhancing security, transparency, and operational efficiency in an increasingly complex world. For newcommers as well as for seasonned users, it greatly facilitates and brings certainty to the "do your homework" address validation phase.

In terms of automation, the directory allows **on-chain verification** allowing:
* smart wallets to check and validate the addresses upon usage
* other smart contracts to perform addresses checks within their code

Information is maintained by the stake holders and therefore always uptodate.

## Specification

The following interface and rules are normative. The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Definitions

* **recognized authority**
  - An organisation which is well known by potential users who decides to deploy a SmartDirectory contract subject to this ERC. Such organisations can be major token issuers, exchanges, state regulators, non profit foundations, industry consortia ...
* **SmartDirectory**
  - An administered blockchain whitelist smart-contract that serves as a shared, on-chain repository for lists of addresses, which can be either Externally Owned Accounts (EOA) or smart contracts. 
  - It functions as a decentralized directory composed of references (smart contract addresses) and their issuers (registrants). 
* **Registrant**
  - A service provider who, after receiving approval from an administrator of the recognized authority, is registered by that administrator in the SmartDirectory.
  - The registrant must have blockchain access and signing capability in order to write address records into the SmartDirectory to build its references list. 
  - Once registered, a registrant can deploy smart contracts for the purpose of their services and record their addresses in the references list. 
  - The registrant must provide and keep updated its own URI for its clients to consult service terms and possibly register for services. 
  - The registrant's address can be an EOA or another smart contract. 
* **Reference**
  - A smart contract addresse issued by a registrant. 
  - The core data is held within the SmartDirectory's "references table," which contains all declared smart contract addresses; these can also be EOAs. 
  - Each reference includes: the registrant's address, the reference's address, a project ID, the reference type, the reference version, and a status.
* **Administrator**
  - The SmartDirectory contract is operated from one or several administrator addresses.
  - In its simple form the SmartDirectory contract administrator address is the contract deployer address usually called the "owner"
  - Provision is made to allow several distinct administrator addresses (see Optional Features)
  - Administrators have the authority to add or invalidate registrants on the "registrants list".
  - Administrators addresses are responsible for (de)activating, configuring, and managing the decentralized directory. 
* **ReferenceStatus**
  - A component within the statusHistory of a reference, tracking its evolution over time. 
  - It contains a status (a free-text string describing the current state, e.g., "in production," "pending," "abandoned") and a timeStamp (the exact time of the status update). 
- **SmartTokens**
  - A concept where a token (fungible or non-fungible) is programmed to consult a SmartDirectory to filter addresses for transactions (e.g., transfers, minting). 
  - This allows for access control mechanisms within token ecosystems; if the list of references in the SmartDirectory changes, the SmartToken does not need to be modified.
  - They are configured with smart\_directory and registrant\_address variables to enable this consultation functionality. 
* **URI**
  - A string that a registrant can provide and update to offer additional information about their services, accessible to clients (Web2 entry point). 
  - The SmartDirectory itself can have a contractUri at deployment, describing the contract. 


### Interface
#### constructor, creation and setter APIs
##### constructor parameters
- _contractUri (string):
    A non-modifiable string URI that describes the SmartDirectory contract itself. 
    This URI allows the recognized authority to provide descriptive information about itself to the users.

#####      setActivationCode(uint256 _activationCode)
 _activation code values: 
-  0 notActivated (initial value at deployment time)
-  1 activated
-  2 endOfLife
It is important to signal to the users that a SmartDirectory has reached end of life so that they don't inadvertently rely on outdated information

##### getContractUri() String
 Returns the URI given at contract deployment time
 This URI informs the user of the identity of the recognized authority managing the contract
 see also: **Security Considerations** for impersonation prevention

##### getActivationCode()
 If the contract became end of lived, it will report errors to any other calls.
 This call allows to ascertain that a valid contract address is used but that the contract is no longer in use.

##### createRegistrant(address registrantAddress)
 Creates a new registrant. This can only be called by one of the administrators.

##### disableRegistrant(address registrantAddress)
 Disables a registrant by setting its status to invalid, preventing them from creating new references. 
 This can only be called by one of the administrators
 Once disabled, the registrant cannot not be re-enabled unless the optional registrant status audit trail is implemented

##### updateRegistrantUri(string registrantUri):
 Allows a registrant (msg.sender) to update their registrant_uri.

##### createReference(address referenceAddress, string referenceDescription, string referenceType, string referenceVersion, string status)
 Creates a new reference by a registrant giving an initial status. 
 Registrant must have been created by the administrator, the msg.sender is implicitly used as registrantAddress
 The registrant must not be disabled for the reference to be created
 The intent for referenceDescription is to hold a JSON structure with fields such as title, metadata, codeHash, API, documentation URI ...
 referenceType, referenceVersion, status are meant to be predefined value strings such that they can be verified by a smart contract without parsing

#####     updateReferenceStatus(address referenceAddress, string newStatus)
 Adds a new status and timestamp to a reference status
 see also: **Options** for a possible audit trail

#### information API (getters)

##### getRegistrantUri(address _registrantAddress) external view returns (string memory);
 Returns the information URI from the given registrant, this allows a user to confirm
 the web identify of a contract owner.

##### getReferenceStatus(address referenceAddress)
 Returns the latest status and timestamp of a reference
 This is the simplest and main information entry for the public

##### getReference(address referenceAddress)
 Returns all the informations known about a reference:
 - address registrantAddress
 - string memory referenceDescription
 - string memory referenceType
 - string memory referenceVersion
 - string memory status


#### constant values

##### Contract Activation code
-  0 notActivated (initial value at deployment time)
-  1 activated
-  2 endOfLife

##### Registrant status
 - 0 registrant exists (initial value at registrant creation time)
 - 1 registrant is disabled

##### Reference status
 - 0 reference created but contract is not to be used
 - 1 contract in beta test
 - 2 contract is use
 - 3 contract being deprecated, can still be used
 - 4 contract end of life, should not be used

### Public Interface in solidity

[ISmartDirectoryERC.sol](https://github.com/BPCE/smart-directory/blob/main/contracts/ISmartDirectoryERC.sol)

###   Required Behavior

 The owner only can alter the registrant list.
 Each registrant can alter its own references.



###   Optional Features
####  distinct supplementary administrator addresses
 This feature allows the deployer to give adminstration power to other addresses specified at deployement time
 This may help if the organization of the recognized authority requires such separation
 In this case, the constructor receives the administration addresses as parameters:
- _parentAddress1 (address):
    ◦ The address of the first SmartDirectory administrator.
    ◦ One of two addresses designated as creators/administrators, with rights to add or invalidate registrants.
    ◦ Must be different from _parentAddress2 and not address(0).
- _parentAddress2 (address):
    ◦ The address of the second SmartDirectory administrator.
    ◦ Similar to _parentAddress1, it has administrative rights.
    ◦ Must be different from _parentAddress1 and not address(0).

####    consultable audit trail for the reference statuses
 This feature allows recording and exposing to the requesting user all the past status changes of a reference.
 This is meant to ease administration or for forensics
#####     getReference(address referenceAddress) see full description above
 when the optional audit trail is implemented getReference returns an additional information: the timestamp of the status
#####     getReferenceLastStatusIndex(address referenceAddress)
 when the optional audit trail is implemented, returning the last index
 allows to retrieve all the changes by iterating **getReferenceStatusAtIndex**
#####     getReferenceStatusAtIndex(address referenceAddress, uint256 statusIndex)
 Returns the status and timestamp at a specific index in the statusHistory


####    registrant status management
##### isValidRegistrant (_registrantAddress)
 An implementation may want to distinguish between non existent registrants and invalid registrants
 This returns wether the registrant is disabled, a non existent registrant will raise an error
##### registrant status audit trail
 In the optional case where an audit trail of the registrant status changes is recorded
 This feature is used if registrant drop out of compliance and needs to be reenacted later

#### getContractVersion
  This feature allows to track code versions of the contract

#### fonctions for enumerating the registrant and reference lists
##### getDisabledRegistrants() address[]
 Returns an address table listing all the registrants that are disabled
##### getRegistrantLastIndex()
 Returns the last index used in the registrants list
 This allows to retrieve all the registrants
##### getRegistrantAtIndex(uint256 index)
 Returns the address and URI of a declarant at a specific index
##### getReferencesList(address registrantAddress)
 Note: doit on passer par les index pour lister (par coherence) ?
 Returns an array of references for a given declarant


## Rationale
This contract ERC offers a solution to the growing complexity of blockchain interactions by providing a standardized, on-chain, and dynamically verifiable mechanism for managing trusted addresses and smart contracts, thereby enhancing security, flexibility, and operational efficiency within decentralized applications and tokenized economies.
### Administration Considerations
The deploying recognized authority needs to have an adminstrative off-chain process for organizations to apply and be vetted as registrants, as well as maintain the vetted registrant status. The registrant list must be updated acccordingly, possibly disabling registrants at some point when they no longer match the vetting requirements.

Each registrant organization is then sole responsible of its own references (contract addresses), this includes keeping each URI alive with user oriented information, keeping the version number and status updated to reflect the state of its publicly reachable contracts addresses.


## Reference Implementation

[SmartDirectoryERC.sol](https://github.com/BPCE/smart-directory/blob/main/contracts/SmartDirectoryERC.sol)

## Security Considerations
### URI cross references
#### recognized authority URI
When consulting the recognized authority URI, the data served should contain the address of the SmartDirectory contract as meta-data in machine readable format and possibly in human readable format. The purpose of this cross reference is to avoid a rogue contract claiming having been issued by a recognized authority.
example of cross reference data:
X-Blockchain-Addresses: {"1": "0x1234567890abcdef1234567890abcdef12345678", "56": "0xabcdef1234567890abcdef1234567890abcdef12"}
Addresses are indexed by their EIP-155 chainIDs
To avoid rogue deployements on newer blockchains, addresses from all blockchains IDs must be enumerated even if the contract is deployed at the same address on every blockchain known to the recognized authority.
In order to prevent alteration, the URI is supplied at contract deployment time to the solidity constructor and cannot be changed later.
#### registrant URI
When consulting the registrant URI, the data served at the URI should contain the address of the registrant as meta-data such as X-Blockchain-Address: "0x1234567890abcdef1234567890abcdef12345678"
#### reference owner
The declaring registrant of a reference may be coerced by the createReference function to also be
the owner of the reference. When needed, this extra check ensures that only contracts that are
controlled by the registrant can be listed. Note that this also prevents registrants to declare
"friendly" contracts that are not theirs as references.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).