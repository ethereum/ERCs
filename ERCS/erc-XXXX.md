# Abstract
The following standard liberates the creators and holders of NFTs from the confines of a single domain — expanding their opportunity to embrace the plethora of innovation and experimentation happening across rollups in the Ethereum ecosystem.

# Motivation
Non-fungible tokens as defined by [ERC-721](./eip-721.md) have become one of the most important and widely used digital asset standards since the initial EIP proposal in 2017. However, at the time of the standard’s original introduction the Ethereum ecosystem roadmap did not include scaling through rollups. Since then, we have seen a majority of the activity in the Ethereum ecosystem migrate to rollups. This leaves existing and new NFT collections stuck in a singular domain.

As new applications for NFTs are built across varying rollups, it is becoming increasingly important that NFTs are able to securely migrate across rollup domains with minimal friction. In addition, it is essential that as these NFTs are upgraded to move across multiple domains that we do not introduce unnecessary risk or dependence on any privileged third party such as a specific interoperability network. Sovereignty should remain in the hands of the NFT communities themselves.

There has been both prior discussion and proposals around solving this problem:
- In September of 2021 Vitalik posted "Cross-rollup NFT wrapper and migration ideas" in the Ethereum Research forum. The concept of a "Wrapper NFT" that enable NFTs to expand to rollups was proposed that leverage "Wrapper Manager Contracts." In many ways, you can see that the token interfaces proposed below are directionally aligned with his proposal, but give the transport level greater liberties to minimize the complexity resulting from the receipt chaining concept he discusses.
- Later in September Pavel Sinelnikov similarly created a post in the Ethereum Research forum titled "Bridging NFTs across layers" iterating upon Vitalik's initial proposal. The core differentiator between the below proposal and these concepts proposed in 2021 are that we have made substantial improvements in both ZK rollups alongside fast finality mechanisms that empower us to define more abstract interfaces which do not overfit for the 7 day withdrawal delay that manifests from optimistic rollups.
- Most recently and importantly in 2023, the Connext team proposed xERC20 which strongly inspired the proposal below. xERC20 established the concept of "Sovereign Bridged Tokens." We agree strongly with the design decisions that were made in this EIP proposal, to the degree that we adhered directly to the bridge authorization interfaces that were utilized in this EIP. 

# Specification
The key words "MUST" and "SHOULD" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and RFC [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

## Token Interface
All xERC-721s MUST implement the following interface:
```ts
interface IXERC-721 {
    /**
     * @notice Emits when a lockbox is set
     *
     * @param _lockbox The address of the lockbox
     */
    event LockboxSet(address _lockbox);

    /**
     * @notice Emits when a limit is set
     *
     * @param _mintingLimit The updated minting limit we are setting to the bridge
     * @param _burningLimit The updated burning limit we are setting to the bridge
     * @param _bridge The address of the bridge we are setting the limit too
     */
    event BridgeLimitsSet(uint256 _mintingLimit, uint256 _burningLimit, address indexed _bridge);

    /**
     * @notice Reverts when a user with too low of a limit tries to call mint/burn
     */
    error IXERC-721_NotHighEnoughLimits();

    struct Bridge {
        BridgeParameters minterParams;
        BridgeParameters burnerParams;
    }

    struct BridgeParameters {
        uint256 timestamp;
        uint256 ratePerSecond;
        uint256 maxLimit;
        uint256 currentLimit;
    }

    /**
     * @notice Sets the lockbox address
     *
     * @param _lockbox The address of the lockbox (0x0 if no lockbox)
     */
    function setLockbox(address _lockbox) external;

    /**
     * @notice Updates the limits of any bridge
     * @dev Can only be called by the owner
     * @param _mintingLimit The updated minting limit we are setting to the bridge
     * @param _burningLimit The updated burning limit we are setting to the bridge
     * @param _bridge The address of the bridge we are setting the limits too
     */
    function setLimits(address _bridge, uint256 _mintingLimit, uint256 _burningLimit) external;

    /**
     * @notice Returns the max limit of a bridge
     *
     * @param _bridge The bridge we are viewing the limits of
     * @return _limit The limit the bridge has
     */
    function mintingMaxLimitOf(address _bridge) external view returns (uint256 _limit);

    /**
     * @notice Returns the max limit of a bridge
     *
     * @param _bridge the bridge we are viewing the limits of
     * @return _limit The limit the bridge has
     */
    function burningMaxLimitOf(address _bridge) external view returns (uint256 _limit);

    /**
     * @notice Returns the current limit of a bridge
     *
     * @param _bridge The bridge we are viewing the limits of
     * @return _limit The limit the bridge has
     */
    function mintingCurrentLimitOf(address _bridge) external view returns (uint256 _limit);

    /**
     * @notice Returns the current limit of a bridge
     *
     * @param _bridge the bridge we are viewing the limits of
     * @return _limit The limit the bridge has
     */
    function burningCurrentLimitOf(address _bridge) external view returns (uint256 _limit);

    /**
     * @notice Mints a non-fungible token to a user
     * @dev Can only be called by a bridge
     * @param _user The address of the user to receive the minted non-fungible token
     * @param _tokenId The specific non-fungible token to mint
     * @param _tokenURI The metadata corresponding to the non-fungible token
     */
    function mint(address _user, uint256 _tokenId, string _tokenURI) external;

    /**
     * @notice Mints batch of non-fungible tokens to a user
     * @dev Can only be called by a bridge
     * @param _user The address of the user who needs tokens minted
     * @param _tokenIdList The list of specific tokens to mint to a user
     * @param _tokenURIList The list of metadata for each individual token
     */
    function mintBatch(address _user, uint256[] calldata _tokenIdList, string[] calldata _tokenURIList) external;

    /**
     * @notice Burns a non-fungible token for a user
     * @dev Can only be called by a bridge
     * @param _user The address of the user who needs to burn the non-fungible token
     * @param _tokenId The non-fungible token to burn
     */
    function burn(address _user, uint256 _tokenId) external;

    /**
     * @notice Burns non-fungible tokens for a user
     * @dev Can only be called by a bridge
     * @param _user The address of the user who needs tokens burned
     * @param _tokenIdList The list of non-fungible tokens to burn
     */
    function burnBatch(address _user, uint256[] calldata _tokenIdList) external;
}
```
[ERC-721](./EIP-721) does not provide developers with batch transfer functionality -- this has been a point of pain for developers leading to the introduction of new standards like [ERC-1155](./EIP-1155). This problem is exacerbated even further when programming across multiple rollups as it introduces asynchrony and the cost of compensating an interoperability network for verifying and relaying the transaction. It is for this reason that we decided to extend the contract with additional `mintBatch` and `burnBatch` function interfaces.

In the mint functions the tokenURI data that is passed in SHOULD conform to the standard defined in [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986) or conform to the “ERC721 Metadata JSON Schema” as defined in [EIP-721](./EIP-721) and similarly shown below:

```json
{
  "title": "Asset Metadata",
  "type": "object",
  "properties": {
    "name": {
      "type": "string",
      "description": "Identifies the asset to which this NFT represents"
    },
    "description": {
      "type": "string",
      "description": "Describes the asset to which this NFT represents"
    },
    "image": {
      "type": "string",
      "description": "A URI pointing to a resource with mime type image/* representing the asset to which this NFT represents. Consider making any images at a width between 320 and 1080 pixels and aspect ratio between 1.91:1 and 4:5 inclusive."
    }
  }
}
```

## Lockbox Interface

```ts
interface IXERC-721Lockbox {
  /**
   * @notice Emitted when non-fungible tokens are deposited into the lockbox
   */
  event Deposit(address _sender, uint256[] _tokenIdList);

  /**
   * @notice Emitted when non-fungible tokens are withdrawn from the lockbox
   */
  event Withdraw(address _sender, uint256[] _tokenIdList);

  /**
   * @notice Reverts when a user tries to withdraw and the call fails
   */
  error IXERC-721Lockbox_WithdrawFailed();

  /**
   * @notice Deposit non-fungible tokens into the lockbox
   *
   * @param _tokenIdList The non-fungible tokens to deposit
   */
  function deposit(uint256[] calldata _tokenIdList) external;

  /**
   * @notice Withdraw non-fungible tokens from the lockbox
   *
   * @param _tokenIdList The non-fungible tokens to withdraw
   */
  function withdraw(uint256[] calldata _tokenIdList) external;
}
```

### Enumerable Extension
In addition, we propose an extension to the existing `ERC721Enumerable` interface to empower developers with the ability to query the amount of non-fungible tokens that have been minted on a singular domain. We point out as a note to developers of collections of non-fungible tokens with a mutable total supply that it will be important to propagate state updates for the totalSupply variable to included domains anytime that there is an update. This is similarly applicable to EIP-7281.
```ts
interface XERC721Enumerable /* is ERC721Enumerable */ {
  /**
   * @notice Returns the amount of non-fungible tokens on this domain
   */
  function localSupply() external view returns (uin256);
}
```

# Rationale

## Standardizing Sovereignty

This proposed standard was strongly influenced by the prior work done by the Connext team that is laid out in EIP-7281 (xERC20). All of the bridge authorization interfaces remain identical to EIP-7281 so that developer tooling that is built to empower asset issuers to manage bridges can be utilized both for multi domain ERC-20s as well as ERC-721s.

This EIP in combination with EIP-7281 are just the beginning of an open suite of standards for the Ethereum ecosystem as we embrace a truly rollup centric ecosystem. By utilizing standardized interfaces we can not only establish more rigorously tested developer tooling that can be used for all digital assets, we also open the opportunity for other standards to be introduced that further improve upon the functionality available to issuers of digital assets without requiring bespoke integrations.

As asset issuers are adopting this standard they should refer to the sections in EIP-7281 regarding rate limits and edge case considerations for limits when initializing any rate limit functionality.

## Data Structure Differences
Having said that, the data structures utilized for ERC-721s fundamentally differ from those of ERC-20s and therefore we needed to modify the interfaces to a degree. The necessary modifications exists in the mint and burn functions.

## Batch Mints and Burns
We have additionally extended the interface to include both mintBatch and mintBurn functions. Our goal in drafting this EIP is to conform to existing standards as closely as possible while promoting the safest mechanisms for transfers across domains. While ERC-721 does not contain a comparable transferBatch function, we believe it is important to expand the interface to include batch transfers across domains due to the introduction of the inherent cost and complexity when utilizing external interoperability networks to facilitate these transfers. To create the best developer experience, this opens up the opportunity for smart contract developers to implement transfers in a way that best positions them to isolate the risk of a cross domain transfer into a singular transaction whose failure case can be handled in a simpler manner than an array of these cross domain function calls.

# Backwards Compatibility
This EIP is designed specifically so that we can empower new NFT collections to launch by default in a manner that best prepares them for continual expansion of Ethereum’s rollup ecosystem while not excluding collections that have already launched. There is a simple and minimal mechanism for existing NFT collections to easily adopt this standard that places a focus on reducing any functionality to reduce this surface area for a compromise.

Existing NFT collections can simply upgrade to become xERC-721s through the deployment of a new portal contract that makes them accessible throughout the rest of the rollup ecosystem.

In addition — there are already large existing marketplaces that facilitate the exchange of NFTs among users and it is essential that xERC-721s comply with the interfaces that these exchanges use to facilitate seamless integration into the rest of the tooling that has been built around NFTs already. This similarly applies to NFTFi protocols.

# Security Considerations
Specific attention was paid to minimizing the code necessary to empower NFT communities with this functionality — we believe strongly that minimal standards are the best way to empower people to harness new opportunities in a manner that promotes composability while minimizing the risk of any security compromises.

Specifically, the most clear security consideration that teams should take into account as they upgrade collections to xERC-721s is the choice they make when selecting interoperability networks that facilitate the transfers of individual NFTs. We urge communities of high value xERC-721s to even consider utilizing additional security measures such as utilizing an m of n multi signature confirmation from multiple bridge providers.

# Reference Implementation
TODO: after receiving reviews & feedback

# Copyright
Copyright and related rights waived via [CC0](https://eips.ethereum.org/LICENSE).
