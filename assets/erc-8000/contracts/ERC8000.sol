// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.6;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Context.sol";

import "./interfaces/IERC8000.sol";
import "./interfaces/IERC721Receiver.sol";
import "./interfaces/IERC8000Receiver.sol";
import "./extensions/IERC8000Metadata.sol";
import "./libs/TransferHelper.sol";

contract ERC8000 is Context, IERC8000Metadata, IERC721Enumerable {

    // --------------------------------------------------event----------------------------------------------------------
    event SlotUpdate(
        uint256 slotIndex,
        bool update,
        bool transferable,
        bool isToken,
        bool isNft,
        address tokenAddress,
        string name
    );

    // --------------------------------------------------struct---------------------------------------------------------

    // User holding and authorization data
    struct AddressData {
        uint256[] ownedTokens;
        mapping(uint256 => uint256) ownedTokensIndex;
        mapping(address => bool) approvals;
    }

    // token metadata
    struct TokenData {
        // Unique ID of the MFT
        uint256 id;
        // Level of MFT
        uint32 tokenLevel;
        // Type of MFT
        uint8 tokenType;
        // Whether the MFT can be transferred
        bool transferable;
        // The owner of MFT
        address owner;
        // Authorized address of the MFT
        address approved;
    }

    // Slot metadata
    struct Slot {
        // slot Whether the asset can be transferred
        bool transferable;
        // Token assets or not: Points, token assets
        bool isToken;
        // True indicates NFT
        bool isNft;
        // If isToken is true, it is the token address, otherwise it is the 0 address
        address tokenAddress;
        // Slot name
        string name;
    }

    // ---------------------------------------------------variable------------------------------------------------------

    // MFT token name
    string private _name;
    // MFT token symbol
    string private _symbol;

    // Currently supported slots
    Slot[] public slots;
    // All the MFT's that have been minted
    TokenData[] _allTokens;

    // --------------------------------------------------mapping--------------------------------------------------------

    // MFT index：tokenId => tokenIndex
    mapping(uint256 => uint256)  _allTokensIndex;
    // The approved value of slots：id =>(owner=> (slot => (approval => allowance)))
    mapping(uint256 => mapping(address => mapping(uint256 => mapping(address => uint256)))) private _approvedValues;
    // User data
    mapping(address => AddressData) _addressData;
    // tokenAddress => slotIndex
    mapping(address => uint256) public tokenSlot;
    // MFT-ID => (slot => balance)
    mapping(uint => mapping(uint => uint)) _balance;
    // MFT-ID => (slot => nftIds)
    mapping(uint => mapping(uint => uint[])) _nftTokens;
    // slot => (nftId => nftIndex)
    mapping(uint256 => mapping(uint => uint))  _nftTokensIndex;

    // --------------------------------------------------constructor----------------------------------------------------

    constructor(string memory name_, string memory symbol_){
        _name = name_;
        _symbol = symbol_;
        slots.push(Slot({
        transferable : false,
        isToken : false,
        isNft : false,
        tokenAddress : address(0),
        name : ''
        }));
    }

    // --------------------------------------------------function-------------------------------------------------------

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
        interfaceId == type(IERC165).interfaceId ||
        interfaceId == type(IERC8000).interfaceId ||
        interfaceId == type(IERC721).interfaceId ||
        interfaceId == type(IERC8000).interfaceId ||
        interfaceId == type(IERC721Enumerable).interfaceId ||
        interfaceId == type(IERC721Metadata).interfaceId;
    }

    /**
     * @dev Returns the token collection name.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the token collection symbol.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals the slot.
     */
    function slotDecimals(uint256 slotIndex_) public view virtual override returns (uint8) {
        _requireExisted(slotIndex_);
        if (!slots[slotIndex_].isToken) return 18;
        if (!slots[slotIndex_].isNft) return 1;
        return IERC20Metadata(slots[slotIndex_].tokenAddress).decimals();
    }

    /**
     * @notice Get the value of slot.
     * @param tokenId_ The token for which to query the balance
     * @param slotIndex_ The slot for which to query the balance
     */
    function balanceOf(uint256 tokenId_, uint256 slotIndex_) public view virtual override returns (uint256) {
        _requireMinted(tokenId_);
        _requireExisted(slotIndex_);
        return _balance[tokenId_][slotIndex_];
    }

    /**
    * @dev Gets the number of NFTS in the slot
    * @param tokenId_ MFT ID
    * @param slotIndex_ Slot index
    */
    function nftBalanceOf(uint256 tokenId_, uint256 slotIndex_) public view virtual override returns (uint256[] memory) {
        return _nftTokens[tokenId_][slotIndex_];
    }

    /**
      * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address owner_) public view virtual override returns (uint256) {
        return _addressData[owner_].ownedTokens.length;
    }

    /**
     * @dev Returns the owner of the `tokenId` token.
     */
    function ownerOf(uint256 tokenId_) public view virtual override returns (address owner_) {
        _requireMinted(tokenId_);
        owner_ = _allTokens[_allTokensIndex[tokenId_]].owner;
        require(owner_ != address(0), "ERC8000: invalid token ID");
    }

    function _baseURI() internal view virtual returns (string memory) {
        return "";
    }

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for contract.
     */
    function contractURI() public view virtual override returns (string memory) {
        string memory baseURI = _baseURI();
        return
        bytes(baseURI).length > 0 ?
        string(abi.encodePacked(baseURI, "contract/", address(this))) :
        "";
    }

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `slotIndex` slot.
     */
    function slotURI(uint256 slot_) public view virtual override returns (string memory) {
        return "";
    }

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(uint256 tokenId_) public view virtual override returns (string memory) {
        return "";
    }

    /**
    * @dev Update or add slot information
    * @param slotIndex_ Slot Index
    * @param update_ true for update
    * @param transferable_ true indicates transferable
    * @param isToken_ True indicates  token
    * @param isNft_ True indicates  NFT
    * @param tokenAddress_ ERC20 or ERC721 Token Address
    * @param name_ Slot Name
    */
    function _updateSlot(
        uint256 slotIndex_,
        bool update_,
        bool transferable_,
        bool isToken_,
        bool isNft_,
        address tokenAddress_,
        string memory name_
    ) internal virtual {
        Slot memory slot = Slot({
        transferable : transferable_,
        isToken : isToken_,
        isNft : isNft_,
        tokenAddress : tokenAddress_,
        name : name_
        });

        if (update_) {
            require(tokenSlot[tokenAddress_] == slotIndex_, "ERC8000: tokenAddress not exist");
            _requireExisted(slotIndex_);
            slots[slotIndex_] = slot;
        } else {
            require(tokenSlot[tokenAddress_] == 0, "ERC8000: tokenAddress already exist");
            slots.push(slot);
            slotIndex_ = slots.length - 1;
        }

        if (isToken_) {
            tokenSlot[tokenAddress_] = slotIndex_;
        } else {
            delete tokenSlot[tokenAddress_];
        }

        emit SlotUpdate(slotIndex_, update_, transferable_, isToken_, isNft_, tokenAddress_, name_);
    }

    /**
     * @notice Allow an operator to manage the value of a token, up to the `_value` amount.
     * @dev MUST revert unless caller is the current owner, an authorized operator, or the approved
     *  address for `_tokenId`.
     *  MUST emit ApprovalValue event.
     * @param tokenId_ The token to approve
     * @param slotIndex_ The slot to approve
     * @param operator_ The operator to be approved
     * @param value_ The maximum value of `_toTokenId` that `_operator` is allowed to manage
     */
    function approve(uint256 tokenId_, uint256 slotIndex_, address operator_, uint256 value_) public payable virtual override {
        address owner = ERC8000.ownerOf(tokenId_);
        require(operator_ != owner, "ERC8000: approval to current owner");

        require(_isApprovedOrOwner(_msgSender(), tokenId_), "ERC8000: owner! or approved!");

        _approveValue(tokenId_, slotIndex_, operator_, value_);
    }

    /**
     * @notice Get the maximum value of a token that an operator is allowed to manage.
     * @param tokenId_ The token for which to query the allowance
     * @param slotIndex_ The slot for which to query the allowance
     * @param operator_ The address of an operator
     * @return The current approval value of `_tokenId` that `_operator` is allowed to manage
     */
    function allowance(uint256 tokenId_, uint256 slotIndex_, address operator_) public view virtual override returns (uint256) {
        address owner = ERC8000.ownerOf(tokenId_);
        return _approvedValues[tokenId_][owner][slotIndex_][operator_];
    }

    /**
    * @dev Support ERC20 and ERC721 token deposit, after successful deposit, increase the balance of slot
    * @param tokenId_ MFT ID
    * @param slotIndex_ Slot index
    * @param valueOrNftId_ Number of ERC20 or ID of ERC721
    */
    function deposit(uint256 tokenId_, uint256 slotIndex_, uint256 valueOrNftId_) public payable virtual {
        address owner = _msgSender();
        _requireMinted(tokenId_);
        _requireExisted(slotIndex_);

        uint slotValue = slots[slotIndex_].isNft ? 1 : valueOrNftId_;
        _mintValue(tokenId_, slotIndex_, slotValue);

        if (slots[slotIndex_].isNft) {
            _nftTokensIndex[slotIndex_][valueOrNftId_] = _nftTokens[tokenId_][slotIndex_].length;
            _nftTokens[tokenId_][slotIndex_].push(valueOrNftId_);

            IERC721(slots[slotIndex_].tokenAddress).transferFrom(owner, address(this), valueOrNftId_);
        } else {
            TransferHelper.safeTransferFrom(slots[slotIndex_].tokenAddress, owner, address(this), valueOrNftId_);
        }
    }

    /**
    * @dev The MFT transfers slot value to other MFTS
    * @param fromTokenId_ MFT ID of the transaction initiator
    * @param toTokenId_ MSFT ID of the receiver
    * @param slotIndex_ Slot index
    * @param valueOrNftId_ Number of ERC20 or ID of ERC721
    */
    function transferFrom(
        uint256 fromTokenId_,
        uint256 toTokenId_,
        uint256 slotIndex_,
        uint256 valueOrNftId_
    ) public payable virtual override {
        _spendAllowance(_msgSender(), fromTokenId_, slotIndex_, valueOrNftId_);
        _transferValue(fromTokenId_, toTokenId_, slotIndex_, valueOrNftId_);
    }

    /**
    * @dev The MFT transfers slot value to other MFTS
    * @param fromTokenId_ MFT ID of the transaction initiator
    * @param toTokenId_ MFT ID of the receiver
    * @param tokenAddress_ ERC20 or ERC721 Token Address
    * @param valueOrNftId_ Number of ERC20 or ID of ERC721
    */
    function transferFrom(
        uint256 fromTokenId_,
        uint256 toTokenId_,
        address tokenAddress_,
        uint256 valueOrNftId_
    ) public payable virtual {
        transferFrom(fromTokenId_, toTokenId_, tokenSlot[tokenAddress_], valueOrNftId_);
    }

    /**
    * @dev slot transfers to EOA wallet address
    * @param fromTokenId_  MFT ID of the transaction initiator
    * @param toAddress_ The recipient's wallet address
    * @param slotIndex_ Slot index
    * @param valueOrNftId_ Number of ERC20 or ID of ERC721
    */
    function transferFrom(
        uint256 fromTokenId_,
        address toAddress_,
        uint256 slotIndex_,
        uint256 valueOrNftId_
    ) public payable virtual override {
        require(slots[slotIndex_].isToken, "ERC8000: isToken!");
        require(toAddress_ != address(0), "ERC8000: toAddress cannot be zero!");
        _requireSlotTransferable(slotIndex_);

        _spendAllowance(_msgSender(), fromTokenId_, slotIndex_, valueOrNftId_);
        _burnValue(fromTokenId_, slotIndex_, valueOrNftId_);

        if (slots[slotIndex_].isNft) {
            IERC721(slots[slotIndex_].tokenAddress).transferFrom(address(this), toAddress_, valueOrNftId_);
        } else {
            TransferHelper.safeTransfer(slots[slotIndex_].tokenAddress, toAddress_, valueOrNftId_);
        }
    }

    /**
    * @dev slot transfers to EOA wallet address
    * @param fromTokenId_  MFT ID of the transaction initiator
    * @param toAddress_ The recipient's wallet address
    * @param tokenAddress_ ERC20 or ERC721 Token Address
    * @param valueOrNftId_ Number of ERC20 or ID of ERC721
    */
    function transferFrom(
        uint256 fromTokenId_,
        address toAddress_,
        address tokenAddress_,
        uint256 valueOrNftId_
    ) public payable virtual {
        transferFrom(fromTokenId_, toAddress_, tokenSlot[tokenAddress_], valueOrNftId_);
    }

    /**
     * @dev Transfer MFT
     * @param from_ Sender
     * @param to_ Receiver
     * @param tokenId_ MFT ID
     */
    function transferFrom(
        address from_,
        address to_,
        uint256 tokenId_
    ) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId_), "ERC8000: owner! or approved!");
        _transferTokenId(from_, to_, tokenId_);
    }

    /**
     * @dev Securely transfer MFT
     * @param from_ Sender
     * @param to_ Receiver
     * @param tokenId_ MFT ID
     * @param data_ Transfer data
     */
    function safeTransferFrom(
        address from_,
        address to_,
        uint256 tokenId_,
        bytes memory data_
    ) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId_), "ERC8000: owner! or approved!");
        _safeTransferTokenId(from_, to_, tokenId_, data_);
    }

    /**
     * @dev Securely transfer MFT
     * @param from_ Sender
     * @param to_ Receiver
     * @param tokenId_ MFT ID
     */
    function safeTransferFrom(
        address from_,
        address to_,
        uint256 tokenId_
    ) public virtual override {
        safeTransferFrom(from_, to_, tokenId_, "");
    }

    /**
     * @dev Gives permission to `to` to transfer `tokenId_` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId_` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address to_, uint256 tokenId_) public virtual override {
        address owner = ERC8000.ownerOf(tokenId_);
        require(to_ != owner, "ERC8000: approval to current owner");

        require(
            _msgSender() == owner || ERC8000.isApprovedForAll(owner, _msgSender()), "ERC8000: owner! nor approved!"
        );

        _approve(to_, tokenId_);
    }

    function getApproved(uint256 tokenId_) public view virtual override returns (address) {
        _requireMinted(tokenId_);
        return _allTokens[_allTokensIndex[tokenId_]].approved;
    }

    function setApprovalForAll(address operator_, bool approved_) public virtual override {
        _setApprovalForAll(_msgSender(), operator_, approved_);
    }

    function isApprovedForAll(address owner_, address operator_) public view virtual override returns (bool) {
        return _addressData[owner_].approvals[operator_];
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _allTokens.length;
    }

    function tokenByIndex(uint256 index_) public view virtual override returns (uint256) {
        require(index_ < ERC8000.totalSupply(), "ERC8000: index!");
        return _allTokens[index_].id;
    }

    function tokenOfOwnerByIndex(address owner_, uint256 index_) public view virtual override returns (uint256) {
        require(index_ < ERC8000.balanceOf(owner_), "ERC8000: index!");
        return _addressData[owner_].ownedTokens[index_];
    }

    function _setApprovalForAll(
        address owner_,
        address operator_,
        bool approved_
    ) internal virtual {
        require(owner_ != operator_, "ERC8000: approve to caller");

        _addressData[owner_].approvals[operator_] = approved_;

        emit ApprovalForAll(owner_, operator_, approved_);
    }

    function _isApprovedOrOwner(address operator_, uint256 tokenId_) internal view virtual returns (bool) {
        address owner = ERC8000.ownerOf(tokenId_);
        return (
        operator_ == owner ||
        ERC8000.isApprovedForAll(owner, operator_) ||
        ERC8000.getApproved(tokenId_) == operator_
        );
    }

    function _spendAllowance(address operator_, uint256 tokenId_, uint256 slotIndex_, uint256 valueOrNftId_) internal virtual {
        uint value_ = slots[slotIndex_].isNft ? 1 : valueOrNftId_;
        uint256 currentAllowance = ERC8000.allowance(tokenId_, slotIndex_, operator_);
        if (!_isApprovedOrOwner(operator_, tokenId_) && currentAllowance != type(uint256).max) {
            require(currentAllowance >= value_, "ERC8000: insufficient allowance");
            _approveValue(tokenId_, slotIndex_, operator_, currentAllowance - value_);
        }
    }

    function _exists(uint256 tokenId_) internal view virtual returns (bool) {
        return tokenId_ > 0 && _allTokens.length != 0 && _allTokens[_allTokensIndex[tokenId_]].id == tokenId_;
    }

    function _requireExisted(uint256 slotIndex_) internal view virtual {
        require(slotIndex_ > 0 && slots.length - 1 >= slotIndex_, "ERC8000: invalid slot index");
    }

    function _requireSlotTransferable(uint256 slotIndex_) internal view virtual {
        _requireExisted(slotIndex_);
        require(slots[slotIndex_].transferable, "ERC8000: slot transferable!");
    }

    function _requireTransferable(uint256 tokenId_) internal view virtual {
        require(_exists(tokenId_), "ERC8000: invalid token ID");
        require(_allTokens[_allTokensIndex[tokenId_]].transferable, "ERC8000: token transferable!");
    }

    function _requireMinted(uint256 tokenId_) internal view virtual {
        require(_exists(tokenId_), "ERC8000: invalid token ID");
    }

    function _mint(
        address to_,
        uint tokenId_,
        uint32 tokenLevel_,
        uint8 tokenType_,
        bool transferable_
    ) internal virtual returns (uint256){
        require(to_ != address(0), "ERC8000: mint to the zero address");
        require(!_exists(tokenId_), "ERC8000: token already minted");

        _beforeTokenTransfer(address(0), to_, tokenId_, 0);

        _mintToken(to_, tokenId_, tokenLevel_, tokenType_, transferable_);

        _afterTokenTransfer(address(0), to_, tokenId_, 0);
        return tokenId_;
    }

    function _mintValue(uint256 tokenId_, uint256 slotIndex_, uint256 value_) internal virtual {
        _requireMinted(tokenId_);
        _requireExisted(slotIndex_);

        _beforeValueTransfer(address(0), _msgSender(), 0, tokenId_, slotIndex_, value_);

        _balance[tokenId_][slotIndex_] += value_;
        emit TransferValue(0, tokenId_, slotIndex_, value_);

        _afterValueTransfer(address(0), _msgSender(), 0, tokenId_, slotIndex_, value_);
    }

    function _mintToken(
        address to_,
        uint256 tokenId_,
        uint32 tokenLevel_,
        uint8 tokenType_,
        bool transferable_
    ) private {

        TokenData memory tokenData = TokenData({
        id : tokenId_,
        tokenLevel : tokenLevel_,
        tokenType : tokenType_,
        transferable : transferable_,
        owner : to_,
        approved : address(0)
        });

        _addTokenToAllTokensEnumeration(tokenData);
        _addTokenToOwnerEnumeration(to_, tokenId_);

        emit Transfer(address(0), to_, tokenId_);
    }

    function _burn(uint256 tokenId_) internal virtual {
        _requireMinted(tokenId_);

        TokenData storage tokenData = _allTokens[_allTokensIndex[tokenId_]];
        address owner = tokenData.owner;

        _beforeTokenTransfer(owner, address(0), tokenId_, 0);

        _removeTokenFromOwnerEnumeration(owner, tokenId_);
        _removeTokenFromAllTokensEnumeration(tokenId_);

        emit Transfer(owner, address(0), tokenId_);

        _afterTokenTransfer(owner, address(0), tokenId_, 0);
    }

    function _burnValue(uint256 tokenId_, uint256 slotIndex_, uint256 valueOrNftId_) internal virtual {
        _requireMinted(tokenId_);

        address owner = _allTokens[_allTokensIndex[tokenId_]].owner;
        uint burnValue_ = valueOrNftId_;

        _beforeValueTransfer(owner, address(0), tokenId_, 0, slotIndex_, valueOrNftId_);

        if (slots[slotIndex_].isNft) {
            burnValue_ = 1;
            _updateNftTokens(tokenId_, slotIndex_, valueOrNftId_);
        }

        uint256 value = _balance[tokenId_][slotIndex_];
        require(value >= burnValue_, "ERC8000: BurnValue : Insufficient balance");

        _balance[tokenId_][slotIndex_] -= burnValue_;
        emit TransferValue(tokenId_, 0, slotIndex_, burnValue_);

        _afterValueTransfer(owner, address(0), tokenId_, 0, slotIndex_, valueOrNftId_);

    }

    function _addTokenToOwnerEnumeration(address to_, uint256 tokenId_) private {
        _allTokens[_allTokensIndex[tokenId_]].owner = to_;

        _addressData[to_].ownedTokensIndex[tokenId_] = _addressData[to_].ownedTokens.length;
        _addressData[to_].ownedTokens.push(tokenId_);
    }

    function _removeTokenFromOwnerEnumeration(address from_, uint256 tokenId_) private {
        _allTokens[_allTokensIndex[tokenId_]].owner = address(0);

        AddressData storage ownerData = _addressData[from_];
        uint256 lastTokenIndex = ownerData.ownedTokens.length - 1;
        uint256 lastTokenId = ownerData.ownedTokens[lastTokenIndex];
        uint256 tokenIndex = ownerData.ownedTokensIndex[tokenId_];

        ownerData.ownedTokens[tokenIndex] = lastTokenId;
        ownerData.ownedTokensIndex[lastTokenId] = tokenIndex;

        delete ownerData.ownedTokensIndex[tokenId_];
        ownerData.ownedTokens.pop();
    }

    function _addTokenToAllTokensEnumeration(TokenData memory tokenData_) private {
        _allTokensIndex[tokenData_.id] = _allTokens.length;
        _allTokens.push(tokenData_);
    }

    function _removeTokenFromAllTokensEnumeration(uint256 tokenId_) private {

        uint256 lastTokenIndex = _allTokens.length - 1;
        uint256 tokenIndex = _allTokensIndex[tokenId_];

        TokenData memory lastTokenData = _allTokens[lastTokenIndex];

        _allTokens[tokenIndex] = lastTokenData;
        _allTokensIndex[lastTokenData.id] = tokenIndex;

        delete _allTokensIndex[tokenId_];
        _allTokens.pop();
    }

    function _approve(address to_, uint256 tokenId_) internal virtual {
        _allTokens[_allTokensIndex[tokenId_]].approved = to_;
        emit Approval(ERC8000.ownerOf(tokenId_), to_, tokenId_);
    }

    function _approveValue(
        uint256 tokenId_,
        uint256 slotIndex_,
        address to_,
        uint256 value_
    ) internal virtual {
        require(to_ != address(0), "ERC8000: approve value to the zero address");
        address owner = _allTokens[_allTokensIndex[tokenId_]].owner;
        _approvedValues[tokenId_][owner][slotIndex_][to_] = value_;

        emit ApprovalValue(tokenId_, owner, slotIndex_, to_, value_);
    }

    function _transferValue(
        uint256 fromTokenId_,
        uint256 toTokenId_,
        uint256 slotIndex_,
        uint256 valueOrNftId_
    ) internal virtual {
        _requireSlotTransferable(slotIndex_);
        require(_exists(fromTokenId_), "ERC8000: transfer from invalid token ID");
        require(_exists(toTokenId_), "ERC8000: transfer to invalid token ID");

        uint value = slots[slotIndex_].isNft ? 1 : valueOrNftId_;
        require(_balance[fromTokenId_][slotIndex_] >= value, "ERC8000: insufficient balance for transfer");

        TokenData storage fromTokenData = _allTokens[_allTokensIndex[fromTokenId_]];
        TokenData storage toTokenData = _allTokens[_allTokensIndex[toTokenId_]];

        _beforeValueTransfer(fromTokenData.owner, toTokenData.owner, fromTokenId_, toTokenId_, slotIndex_, valueOrNftId_);

        if (slots[slotIndex_].isNft) {
            _updateNftTokens(fromTokenId_, slotIndex_, valueOrNftId_);

            _nftTokensIndex[slotIndex_][valueOrNftId_] = _nftTokens[toTokenId_][slotIndex_].length;
            _nftTokens[toTokenId_][slotIndex_].push(valueOrNftId_);
        }

        _balance[fromTokenId_][slotIndex_] -= value;
        _balance[toTokenId_][slotIndex_] += value;

        emit TransferValue(fromTokenId_, toTokenId_, slotIndex_, value);

        _afterValueTransfer(fromTokenData.owner, toTokenData.owner, fromTokenId_, toTokenId_, slotIndex_, valueOrNftId_);

        require(
            _checkOnMFTReceived(fromTokenId_, toTokenId_, slotIndex_, valueOrNftId_, ""),
            "ERC8000: transfer to non MFTReceiver"
        );
    }

    function _updateNftTokens(uint tokenId_, uint slotIndex_, uint valueOrNftId_) private {
        uint nftIndex = _nftTokensIndex[slotIndex_][valueOrNftId_];
        uint nftId = _nftTokens[tokenId_][slotIndex_][nftIndex];

        require(valueOrNftId_ == nftId, "ERC8000: transfer to invalid NFT ID");

        uint lastTokenIndex = _nftTokens[tokenId_][slotIndex_].length - 1;
        uint lastTokenId = _nftTokens[tokenId_][slotIndex_][lastTokenIndex];

        _nftTokens[tokenId_][slotIndex_][nftIndex] = lastTokenId;
        _nftTokensIndex[slotIndex_][lastTokenId] = nftIndex;
        _nftTokens[tokenId_][slotIndex_].pop();
    }

    function _transferTokenId(
        address from_,
        address to_,
        uint256 tokenId_
    ) internal virtual {
        require(ERC8000.ownerOf(tokenId_) == from_, "ERC8000: transfer from invalid owner");
        require(to_ != address(0), "ERC8000: transfer to the zero address");
        require(_allTokens[_allTokensIndex[tokenId_]].transferable, "ERC8000: transferable!");

        _beforeTokenTransfer(from_, to_, tokenId_, 0);

        _approve(address(0), tokenId_);

        _removeTokenFromOwnerEnumeration(from_, tokenId_);
        _addTokenToOwnerEnumeration(to_, tokenId_);

        emit Transfer(from_, to_, tokenId_);

        _afterTokenTransfer(from_, to_, tokenId_, 0);
    }

    function _safeTransferTokenId(
        address from_,
        address to_,
        uint256 tokenId_,
        bytes memory data_
    ) internal virtual {
        _transferTokenId(from_, to_, tokenId_);
        require(
            _checkOnERC721Received(from_, to_, tokenId_, data_),
            "ERC8000: transfer to non ERC721Receiver"
        );
    }

    function _checkOnMFTReceived(
        uint256 fromTokenId_,
        uint256 toTokenId_,
        uint256 slotIndex_,
        uint256 valueOrNftId_,
        bytes memory data_
    ) internal virtual returns (bool) {
        address to = ERC8000.ownerOf(toTokenId_);
        if (_isContract(to)) {
            try IERC165(to).supportsInterface(type(IERC8000Receiver).interfaceId) returns (bool retval) {
                if (retval) {
                    bytes4 receivedVal = IERC8000Receiver(to).onERC8000Received(_msgSender(), fromTokenId_, toTokenId_, slotIndex_, valueOrNftId_, data_);
                    return receivedVal == IERC8000Receiver.onERC8000Received.selector;
                } else {
                    return true;
                }
            } catch (bytes memory /** reason */) {
                return true;
            }
        } else {
            return true;
        }
    }

    /**
         * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private returns (bool) {
        if (_isContract(to)) {
            try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("ERC721: transfer to non ERC721Receiver implementer");
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    function _isContract(address addr_) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(addr_)
        }
        return (size > 0);
    }

    function _beforeValueTransfer(
        address from_,
        address to_,
        uint256 fromTokenId_,
        uint256 toTokenId_,
        uint256 slot_,
        uint256 value_
    ) internal virtual {}

    function _afterValueTransfer(
        address from_,
        address to_,
        uint256 fromTokenId_,
        uint256 toTokenId_,
        uint256 slot_,
        uint256 value_
    ) internal virtual {}

    function _beforeTokenTransfer(
        address from_,
        address to_,
        uint256 firstTokenId_,
        uint256 batchSize_
    ) internal virtual {}

    function _afterTokenTransfer(
        address from_,
        address to_,
        uint256 firstTokenId_,
        uint256 batchSize_
    ) internal virtual {}
}

