// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC721H} from "./ERC-721H.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

// ════════════════════════════════════════════════════════════════════════
//  ERC721HCollection — Production-Ready Historical NFT Collection
// ════════════════════════════════════════════════════════════════════════

/**
 * @title ERC721HCollection
 * @author Emiliano Solazzi — 2026
 * @notice Production wrapper around ERC-721H for turnkey NFT collections.
 *         Adds batch minting, batch historical queries, supply cap, public
 *         mint with price/limit controls, and configurable metadata.
 *
 * @dev Designed for L2 deployment (Arbitrum/Base/Optimism) where batch gas is negligible.
 *      All mint paths flow through ERC721H._mint(), preserving the full 3-layer history.
 *
 *      Mint paths:
 *        - mint(to)              → single owner mint (inherited, supply-capped)
 *        - batchMint(to, qty)    → batch owner mint to one address
 *        - batchMintTo(addrs[])  → airdrop to multiple addresses
 *        - publicMint(qty)       → public payable mint with per-wallet limits
 *
 *      Batch queries (view, zero gas for callers):
 *        - batchTokenSummary     → lightweight provenance for N tokens
 *        - batchOwnerAtBlock     → historical snapshot across N tokens
 *        - batchHasEverOwned     → ownership check across N tokens
 *        - batchOriginalCreator  → creator lookup for N tokens
 *        - batchTransferCount    → activity metric for N tokens
 *
 * @custom:version 2.0.0
 */
contract ERC721HCollection is ERC721H {
    using Strings for uint256;

    // ──────────────────────────────────────────────────
    //  Errors
    // ──────────────────────────────────────────────────

    error MaxSupplyExceeded();
    error InsufficientPayment();
    error PublicMintDisabled();
    error MaxPerWalletExceeded();
    error WithdrawFailed();
    error QuantityZero();

    // ──────────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────────

    event BaseURIUpdated(string newBaseURI);
    event PublicMintToggled(bool enabled);
    event MintPriceUpdated(uint256 newPrice);
    event MaxPerWalletUpdated(uint256 newMax);
    event FundsWithdrawn(address indexed to, uint256 amount);

    // ──────────────────────────────────────────────────
    //  Structs
    // ──────────────────────────────────────────────────

    /// @notice Lightweight provenance summary (no full history arrays).
    struct TokenSummary {
        uint256 tokenId;
        address creator;
        uint256 creationBlock;
        address currentOwner;   // address(0) if burned
        uint256 transferCount;
    }

    // ──────────────────────────────────────────────────
    //  Immutables & Storage
    // ──────────────────────────────────────────────────

    /// @notice Maximum number of tokens that can be minted.
    /// @dev Set to type(uint256).max when constructor receives 0 (= unlimited).
    uint256 public immutable MAX_SUPPLY;

    string private _baseTokenURI;
    uint256 public mintPrice;
    bool public publicMintEnabled;
    uint256 public maxPerWallet; // 0 = unlimited
    mapping(address => uint256) public publicMintCount;

    // ──────────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────────

    /// @param name_      Collection name  (ERC-721 metadata)
    /// @param symbol_    Collection symbol (ERC-721 metadata)
    /// @param maxSupply_ Max token supply  (0 = unlimited)
    /// @param baseURI_   Base URI for tokenURI (can be updated later)
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        string memory baseURI_
    ) ERC721H(name_, symbol_) {
        MAX_SUPPLY = maxSupply_ == 0 ? type(uint256).max : maxSupply_;
        _baseTokenURI = baseURI_;
    }

    // ════════════════════════════════════════════════════
    //  MINT OVERRIDE (adds supply cap)
    // ════════════════════════════════════════════════════

    /// @notice Single mint with maxSupply enforcement.
    /// @dev `virtual override` so inheriting contracts can add allowlist logic etc.
    ///      Subclasses MUST preserve the supply cap check.
    function mint(address to) public virtual override onlyOwner returns (uint256) {
        if (totalMinted() + 1 > MAX_SUPPLY) revert MaxSupplyExceeded();
        return _mint(to);
    }

    // ════════════════════════════════════════════════════
    //  BATCH MINTING
    // ════════════════════════════════════════════════════

    /// @notice Mint `quantity` tokens to `to` in one transaction.
    /// @dev Owner-only. Amortizes the ~21 000 gas TX base cost across all mints.
    ///      Each token gets its own Layer 1+2 initialization via _mint().
    /// @param to       Recipient of all minted tokens
    /// @param quantity Number of tokens to mint
    /// @return tokenIds Array of newly minted token IDs
    function batchMint(address to, uint256 quantity)
        external onlyOwner returns (uint256[] memory tokenIds)
    {
        if (quantity == 0) revert QuantityZero();
        if (totalMinted() + quantity > MAX_SUPPLY) revert MaxSupplyExceeded();
        tokenIds = new uint256[](quantity);
        for (uint256 i = 0; i < quantity;) {
            tokenIds[i] = _mint(to);
            unchecked { ++i; }
        }
    }

    /// @notice Airdrop: mint one token to each recipient address.
    /// @dev Owner-only. Useful for allowlist mints or promotional airdrops.
    /// @param recipients Array of addresses — each receives exactly one token
    /// @return tokenIds  Array of newly minted token IDs (parallel to recipients)
    function batchMintTo(address[] calldata recipients)
        external onlyOwner returns (uint256[] memory tokenIds)
    {
        uint256 len = recipients.length;
        if (len == 0) revert QuantityZero();
        if (totalMinted() + len > MAX_SUPPLY) revert MaxSupplyExceeded();
        tokenIds = new uint256[](len);
        for (uint256 i = 0; i < len;) {
            tokenIds[i] = _mint(recipients[i]);
            unchecked { ++i; }
        }
    }

    /// @notice Public mint — anyone can call when enabled. Requires payment.
    /// @dev Excess ETH stays in contract (owner-withdrawable via withdraw()).
    ///      No refund call → no reentrancy risk.
    ///      publicMintCount updated before minting (checks-effects-interactions).
    /// @param quantity Number of tokens to mint
    /// @return tokenIds Array of newly minted token IDs
    function publicMint(uint256 quantity)
        external payable returns (uint256[] memory tokenIds)
    {
        if (!publicMintEnabled) revert PublicMintDisabled();
        if (quantity == 0) revert QuantityZero();
        if (msg.value < mintPrice * quantity) revert InsufficientPayment();
        if (totalMinted() + quantity > MAX_SUPPLY) revert MaxSupplyExceeded();
        if (maxPerWallet > 0 && publicMintCount[msg.sender] + quantity > maxPerWallet) {
            revert MaxPerWalletExceeded();
        }

        publicMintCount[msg.sender] += quantity;
        tokenIds = new uint256[](quantity);
        for (uint256 i = 0; i < quantity;) {
            tokenIds[i] = _mint(msg.sender);
            unchecked { ++i; }
        }
    }

    // ════════════════════════════════════════════════════
    //  ADMIN CONTROLS
    // ════════════════════════════════════════════════════

    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    function setMintPrice(uint256 newPrice) external onlyOwner {
        mintPrice = newPrice;
        emit MintPriceUpdated(newPrice);
    }

    function setMaxPerWallet(uint256 newMax) external onlyOwner {
        maxPerWallet = newMax;
        emit MaxPerWalletUpdated(newMax);
    }

    function togglePublicMint() external onlyOwner {
        publicMintEnabled = !publicMintEnabled;
        emit PublicMintToggled(publicMintEnabled);
    }

    /// @notice Withdraw all ETH (from public mints) to the contract owner.
    function withdraw() external onlyOwner {
        uint256 bal = address(this).balance;
        if (bal == 0) revert WithdrawFailed();
        (bool ok,) = owner.call{value: bal}("");
        if (!ok) revert WithdrawFailed();
        emit FundsWithdrawn(owner, bal);
    }

    // ════════════════════════════════════════════════════
    //  BATCH HISTORICAL QUERIES (View — Zero Gas for Callers)
    // ════════════════════════════════════════════════════

    /// @notice Lightweight batch provenance for multiple tokens.
    /// @dev Reverts if any tokenId was never minted. Burned tokens return correctly
    ///      with currentOwner = address(0). Uses getProvenanceReport() internally.
    function batchTokenSummary(uint256[] calldata tokenIds)
        external view returns (TokenSummary[] memory summaries)
    {
        uint256 len = tokenIds.length;
        summaries = new TokenSummary[](len);
        for (uint256 i = 0; i < len;) {
            uint256 id = tokenIds[i];
            (address c, uint256 b, address o, uint256 t,,) = getProvenanceReport(id);
            summaries[i] = TokenSummary(id, c, b, o, t);
            unchecked { ++i; }
        }
    }

    /// @notice Batch owner-at-block for multiple tokens at the same historical block.
    /// @dev O(log n) binary search per token. Perfect for governance snapshots.
    ///      Returns address(0) for tokens not yet minted at `blockNumber`.
    function batchOwnerAtBlock(uint256[] calldata tokenIds, uint256 blockNumber)
        external view returns (address[] memory owners)
    {
        uint256 len = tokenIds.length;
        owners = new address[](len);
        for (uint256 i = 0; i < len;) {
            owners[i] = getOwnerAtBlock(tokenIds[i], blockNumber);
            unchecked { ++i; }
        }
    }

    /// @notice Batch check if `account` has ever owned each token.
    /// @dev O(1) per token via mapping lookup. Returns false for non-existent tokens.
    function batchHasEverOwned(uint256[] calldata tokenIds, address account)
        external view returns (bool[] memory results)
    {
        uint256 len = tokenIds.length;
        results = new bool[](len);
        for (uint256 i = 0; i < len;) {
            results[i] = hasEverOwned(tokenIds[i], account);
            unchecked { ++i; }
        }
    }

    /// @notice Batch get original creator for each token.
    /// @dev Returns address(0) for non-existent tokens.
    function batchOriginalCreator(uint256[] calldata tokenIds)
        external view returns (address[] memory creators)
    {
        uint256 len = tokenIds.length;
        creators = new address[](len);
        for (uint256 i = 0; i < len;) {
            creators[i] = originalCreator(tokenIds[i]);
            unchecked { ++i; }
        }
    }

    /// @notice Batch get transfer count for each token.
    /// @dev Reverts if any tokenId was never minted (consistent with getTransferCount).
    function batchTransferCount(uint256[] calldata tokenIds)
        external view returns (uint256[] memory counts)
    {
        uint256 len = tokenIds.length;
        counts = new uint256[](len);
        for (uint256 i = 0; i < len;) {
            counts[i] = getTransferCount(tokenIds[i]);
            unchecked { ++i; }
        }
    }

    // ════════════════════════════════════════════════════
    //  METADATA
    // ════════════════════════════════════════════════════

    /// @notice Returns baseURI + tokenId, or "" if no base URI set.
    /// @dev ERC-721H provenance permanence: works on burned tokens too.
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert TokenDoesNotExist();
        if (bytes(_baseTokenURI).length == 0) return "";
        return string.concat(_baseTokenURI, tokenId.toString());
    }
}


// ════════════════════════════════════════════════════════════════════════
//  ERC721HFactory — L2-Optimized Collection Deployment
// ════════════════════════════════════════════════════════════════════════

/**
 * @title ERC721HFactory
 * @author Emiliano Solazzi — 2026
 * @notice Permissionless factory for deploying ERC721HCollection instances.
 *         Uses CREATE2 for deterministic, cross-chain-consistent addresses.
 *
 * @dev L2 optimization strategy:
 *      1. CREATE2 — pre-compute collection addresses before deployment;
 *         same salt + args + factory address = same collection address on any chain.
 *      2. Deployer-mixed salt — `keccak256(deployer, salt)` prevents front-running.
 *      3. Full deployments (not clones) — maximum compatibility, no delegatecall risks,
 *         no initializer footguns. On L2 the extra deploy cost is pennies.
 *      4. Minimal factory state — only a registry of deployed collections.
 *
 *      Typical workflow:
 *        1. predictAddress(name, symbol, maxSupply, baseURI, salt, deployer) → address
 *        2. deployCollection(name, symbol, maxSupply, baseURI, salt)        → address
 *        3. Collection owner configures: setMintPrice, setMaxPerWallet, togglePublicMint
 *        4. Users call publicMint; owner can batchMint/batchMintTo for airdrops
 *
 * @custom:version 2.0.0
 */
contract ERC721HFactory {

    // ──────────────────────────────────────────────────
    //  Errors
    // ──────────────────────────────────────────────────

    error DeploymentFailed();

    // ──────────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────────

    event CollectionDeployed(
        address indexed collection,
        address indexed deployer,
        string  name,
        string  symbol,
        uint256 maxSupply,
        bytes32 salt
    );

    // ──────────────────────────────────────────────────
    //  Registry
    // ──────────────────────────────────────────────────

    /// @notice True if `addr` was deployed through this factory.
    mapping(address => bool) public isCollection;

    address[] private _collections;
    mapping(address => address[]) private _deployerCollections;

    /// @notice Total number of collections deployed through this factory.
    uint256 public totalDeployed;

    // ════════════════════════════════════════════════════
    //  DEPLOYMENT
    // ════════════════════════════════════════════════════

    /// @notice Deploy a new ERC721HCollection via CREATE2.
    /// @dev Ownership is automatically transferred from the factory to msg.sender.
    ///      Same (factory, deployer, salt, args) = same address on any EVM chain.
    /// @param name_      Collection name  (ERC-721 metadata)
    /// @param symbol_    Collection symbol (ERC-721 metadata)
    /// @param maxSupply_ Maximum token supply (0 = unlimited)
    /// @param baseURI_   Base URI for token metadata
    /// @param salt       Deployer-chosen salt for deterministic address
    /// @return collection The deployed collection address
    function deployCollection(
        string calldata name_,
        string calldata symbol_,
        uint256 maxSupply_,
        string calldata baseURI_,
        bytes32 salt
    ) external returns (address collection) {
        bytes32 effectiveSalt = _effectiveSalt(msg.sender, salt);

        collection = address(
            new ERC721HCollection{salt: effectiveSalt}(
                name_, symbol_, maxSupply_, baseURI_
            )
        );
        if (collection == address(0)) revert DeploymentFailed();

        // Transfer ownership from factory → actual deployer
        ERC721HCollection(collection).transferOwnership(msg.sender);

        // Registry
        isCollection[collection] = true;
        _collections.push(collection);
        _deployerCollections[msg.sender].push(collection);
        unchecked { ++totalDeployed; }

        emit CollectionDeployed(
            collection, msg.sender, name_, symbol_, maxSupply_, salt
        );
    }

    /// @notice Predict the CREATE2 address for a collection before deployment.
    /// @dev Returns the exact address that deployCollection() would produce
    ///      with the same arguments from the same deployer.
    /// @param name_      Collection name
    /// @param symbol_    Collection symbol
    /// @param maxSupply_ Max supply (pass the RAW value, same as to deployCollection)
    /// @param baseURI_   Base URI
    /// @param salt       Same salt that will be passed to deployCollection
    /// @param deployer   Address that will call deployCollection
    /// @return predicted  The deterministic collection address
    function predictAddress(
        string calldata name_,
        string calldata symbol_,
        uint256 maxSupply_,
        string calldata baseURI_,
        bytes32 salt,
        address deployer
    ) external view returns (address predicted) {
        bytes32 effectiveSalt = _effectiveSalt(deployer, salt);
        bytes32 codeHash = keccak256(
            abi.encodePacked(
                type(ERC721HCollection).creationCode,
                abi.encode(name_, symbol_, maxSupply_, baseURI_)
            )
        );
        predicted = address(uint160(uint256(keccak256(
            abi.encodePacked(bytes1(0xff), address(this), effectiveSalt, codeHash)
        ))));
    }

    // ════════════════════════════════════════════════════
    //  REGISTRY QUERIES
    // ════════════════════════════════════════════════════

    /// @notice Paginated list of all deployed collections.
    /// @param start Zero-based start index
    /// @param count Maximum number of addresses to return
    function getCollections(uint256 start, uint256 count)
        external view returns (address[] memory result)
    {
        uint256 len = _collections.length;
        if (start >= len) return new address[](0);
        uint256 end = start + count;
        if (end > len) end = len;
        uint256 sliceLen = end - start;
        result = new address[](sliceLen);
        for (uint256 i = 0; i < sliceLen;) {
            result[i] = _collections[start + i];
            unchecked { ++i; }
        }
    }

    /// @notice All collections deployed by a specific address.
    function getDeployerCollections(address deployer)
        external view returns (address[] memory)
    {
        return _deployerCollections[deployer];
    }

    /// @notice Total number of collections in the registry.
    function getCollectionCount() external view returns (uint256) {
        return _collections.length;
    }

    // ──────────────────────────────────────────────────
    //  Internal
    // ──────────────────────────────────────────────────

    /// @dev Mixes deployer address into salt to prevent front-running.
    ///      Different deployers always produce different addresses for the same salt.
    function _effectiveSalt(address deployer, bytes32 salt)
        internal pure returns (bytes32)
    {
        return keccak256(abi.encodePacked(deployer, salt));
    }
}
