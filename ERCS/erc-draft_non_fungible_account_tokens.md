---
eip: TBD
title: Non‑Fungible Account Tokens
description: Smart accounts as tradable NFT assets with embedded wallet metadata
author: Mike Liu (@mikelxc)
discussions-to: https://ethereum-magicians.org/t/non-fungible-account-tokens/24612
status: Draft
type: Standards Track
category: ERC
created: 2025-06-19
requires: 165,721,1271,4337,7579
---

## Abstract

A Non‑Fungible Account Token (NFAT) is an [ERC‑721](https://eips.ethereum.org/EIPS/eip-721) whose metadata embeds the address of a smart‑account wallet; transferring the NFT transfers full control of that [ERC‑7579](https://eips.ethereum.org/EIPS/eip-7579) wallet through an immutable validator, making smart‑contract accounts visible and tradable with existing NFT infrastructure.

## Motivation

Smart-contract wallets ([ERC-4337](https://eips.ethereum.org/EIPS/eip-4337) / [7579](https://eips.ethereum.org/EIPS/eip-7579)) are gaining traction, yet today they are hard to display, share, or trade. At the same time, most NFTs are static receipts with limited utility. NFATs address both sides of the equation:
	1.	Turn the wallet owner / signer into an NFT
1.1 Visibility – The wallet address is embedded in tokenURI; explorers can fetch balances in one call.
1.2 Tradability – Because the signer is an ERC-721 token, existing NFT marketplaces can list or escrow wallet ownership without new code.
1.3 Atomic onboarding – One transaction mints the NFT and deploys (or references) the wallet, forwarding remaining ETH as start-up gas.
	2.	Upgrade NFTs into real vault-like containers
2.1 Bundle of assets – DeFi positions, game items, or social-identity proofs live inside the wallet and move with the NFT.
2.2 Wallet-agnostic utility – Creators choose any audited ERC-7579 implementation (Kernel, Nexus, Safe-7579), gaining modular features such as guardians or session keys.
2.3 Future extensibility – Additional modules can unlock new mechanics (subscriptions, lending) without changing the NFAT spec.

Together, these two directions make wallet ownership tangible and give NFTs functional value beyond static metadata.

## Definitions

1. **Non-Fungible Account Token** – the [ERC‑721](https://eips.ethereum.org/EIPS/eip-721) token that represents the ownership of a smart‑account wallet.
2. **NFT‑Bound Account (NBA)** – [ERC‑7579](https://eips.ethereum.org/EIPS/eip-7579) wallet owned by the NFAT.
3. **NFAT Factory** – [ERC‑721](https://eips.ethereum.org/EIPS/eip-721) contract that mints the token and links the wallet.
4. **NFT‑Bound Validator** – validator module that authorises actions only for the current NFT holder.
5. **Self‑Transfer Lock** – rule forbidding an NFAT to be sent to its own wallet.

## Core Components

1. **NFAT Factory** – mints the token and deterministically initialize (or deploys) its wallet.
2. **NFT‑Bound Account (NBA)** – an [ERC‑7579](https://eips.ethereum.org/EIPS/eip-7579) compliant modular smart account controlled by the NFAT.
3. **NFT‑Bound Validator** – immutable validator module that checks NFAT ownership.

## Specification

The key words **MUST**, **SHOULD**, etc. are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119.html) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174.html).

### 1 NFAT Factory

```solidity
interface INFATFactory is IERC721 {
    /// @notice Emitted when a new NFAT and its associated NBA are created
    event AccountCreated(
        uint256 indexed tokenId,
        address indexed wallet,
        address indexed owner
    );

    /// @notice Error thrown when invalid token ID is provided
    error InvalidTokenId();

    /// @notice Error thrown when wallet deployment fails
    error AccountDeploymentFailed();

    /**
     * @notice Mints a new NFAT and deploys its associated NBA
     * @dev MUST deploy NBA using CREATE2 for deterministic addresses
     * @dev MUST initialize the NBA with the NFT Bound Validator
     * @dev MUST emit AccountCreated event
     * @param walletData Deployment configuration:
     *   - empty bytes: deploy embedded wallet byte‑code with custom logic
     *   - abi.encode(walletFactory, initCalldata, extraSalt): delegate creation to walletFactory
     * @return tokenId The ID of the minted NFAT
     * @return wallet The address of the deployed NBA
     */
    function mint(bytes calldata walletData)
        external
        payable
        returns (uint256 tokenId, address wallet);

    /**
     * @notice Computes the NBA address for a given token ID
     * @dev MUST return the same address whether deployed or not
     * @param tokenId The NFAT token ID
     * @return The deterministic NBA address
     */
    function getAccountAddress(uint256 tokenId) external view returns (address);

    /**
     * @notice Returns the NFAT token ID associated with an NBA address
     * @param wallet The NBA address
     * @return The associated NFAT token ID (or revert if not found)
     */
    function getTokenId(address wallet) external view returns (uint256);

    /**
     * @notice Returns whether an NBA has been deployed for a token ID
     * @param tokenId The NFAT token ID
     * @return True if the NBA is deployed
     */
    function isAccountDeployed(uint256 tokenId) external view returns (bool);
}
```

* `supportsInterface(type(INFATFactory).interfaceId)` **MUST** return `true`.
* `msg.value` **SHOULD** be forwarded to `wallet` minus any optional fee.
* **Self‑Transfer Lock** – the factory **MUST** revert transfers where `to == getAccountAddress(tokenId)`.
* **Module reset** – the `_beforeTokenTransfer` hook **SHOULD** uninstall every module except the NFT‑Bound Validator when ownership changes.
* **Factory upgradeability** – factories MAY be proxy‑upgradeable; implementations SHOULD emit `FactoryUpgraded(oldImpl,newImpl)`.

### 2 Wallet Deployment Modes

* **Internal** – deploy embedded ERC‑7579 byte‑code with validator pre‑installed.
* **External** – call `walletFactory` with `initCalldata`; factory verifies validator installation.
* **Salt formula** – `keccak256(abi.encode(address(this), tokenId, block.chainid, extraSalt))` (extraSalt MAY be empty).
* If the external factory cannot predict the wallet address, this factory MUST store it so `getAccountAddress()` stays deterministic.

### 3 NFT‑Bound Validator

```solidity
interface INFTBoundValidator is IERC7579Module {
    /// @notice Emitted when a validator is initialized for an NBA
    event ValidatorInitialized(
        address indexed account,
        address indexed nftContract,
        uint256 indexed tokenId
    );

    /**
     * @notice Validates that the transaction signer owns the controlling NFAT
     * @dev MUST check current NFAT ownership
     * @dev MUST support ERC-4337 validation flow
     * @dev Accepts a UserOperation or ERC‑1271 signature only when ownerOf(tokenId) == signer
     * @param userOp The user operation to validate
     * @param userOpHash The hash of the user operation
     * @return validationData ERC-4337 validation data (0 for success)
     */
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) external returns (uint256 validationData);

    /**
     * @notice Validates a signature according to ERC-1271
     * @dev MUST check that the signer owns the controlling NFAT
     * @param hash The hash of the data to validate
     * @param signature The signature to validate
     * @return magicValue ERC-1271 magic value (0x1626ba7e) if valid, 0xffffffff if invalid
     */
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4 magicValue);

    /**
     * @notice Returns the NFAT that controls this NBA
     * @param account The NBA address
     * @return nftContract The NFAT contract address
     * @return tokenId The controlling NFAT token ID
     */
    function getNFAT(address account) external view returns (address nftContract, uint256 tokenId);
}
```

* Installed during account initialisation; `onUninstall` MUST revert.
* Validators MAY proxy‑upgrade; upgrades SHOULD emit `ValidatorUpgraded` and MUST preserve the invariant.
* **Validator namespace** – each collection SHOULD deploy its own validator instance or pass `(nftContract, tokenId)` as init data to avoid collisions.

### 4 Metadata Requirements

`tokenURI(tokenId)` **MUST** include exactly one required attribute:

```json
{
  "attributes": [
    { "trait_type": "Account Address", "value": "0x…" }
  ]
}
```

Other fields (image, Chain ID, Deployment Status, etc.) are optional.

### 5 Security Considerations

* **Lost NFAT ⇒ Lost NBA** – losing or burning the NFT forfeits wallet control; UIs MUST warn users.
* **Cross‑chain replay** – bridging without burn can duplicate control; bridge implementations MUST lock originals.
* **Module reset on transfer** – wallet MUST uninstall all modules except the validator when ownership changes to ensure the previous owner cannot access the wallet through additional validators or other modules.
* **Initial gas** – forwarding `msg.value` provides first‑transaction funding.
* **Recovery** – guardian or social‑recovery modules are out of scope.

### 6 Backwards Compatibility

* **Wrapping** – legacy NFTs may mint an NFAT wrapper that references the original token and installs the validator in the wallet.
* **Coexistence with [ERC-6551](https://eips.ethereum.org/EIPS/eip-6551)** – registry‑based TBAs can remain; NFAT adds marketplace tradability without disrupting existing logic.

## Reference Implementation

A complete reference implementation including factory, validator, and tests is available at [https://github.com/mikelxc/Non-Fungible-Account-Token](https://github.com/mikelxc/Non-Fungible-Account-Token).

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
