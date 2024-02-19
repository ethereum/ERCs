// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC7583Metadata.sol";
import "./IERC7583TokenReceiver.sol";

contract ERC7583 is IERC7583Metadata {
    struct WTW {
        uint256 insId;
        uint256 amount;
    }

    // Token name
    string private _name;
    // Token symbol
    string private _symbol;

	// ------- for mint -------
    uint64 public maxSupply;
    uint64 public mintLimit;
    // number of tickets minted
    uint64 public tickNumber;
    uint256 internal _totalSupply;

	// ------- for FT -------
    // the FT slot of users. user address => slotId(insId), the balances of slots are in _balancesOfIns
    mapping(address => uint256) public slotFT;
	// insId => balance
	mapping(uint256 => uint256) private _balancesOfIns;
    // Ins balance, include ins and slots
    mapping(address => mapping(address => uint256)) private _allowances;

	
	// ------- for NFT -------
	// user address => quantity of ins
    mapping(address => uint256) private _insBalances;
	// insId => owner address
	mapping(uint256 => address) private _owners;
	// Mapping from token ID to approved address
    mapping(uint256 => address) private _tokenApprovals;
	// Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    mapping(uint256 => bool) public inscribed;

    constructor(
        string memory name_,
        string memory symbol_,
        uint64 maxSupply_,
        uint64 mintLimit_
    ) {
        _name = name_;
        _symbol = symbol_;
        maxSupply = maxSupply_;
        mintLimit = mintLimit_;
    }

	function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

	function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

	/// @notice Returns the amount of inscriptions owned by `account`.
	function insBalance(address account) external view returns (uint256){
		return _insBalances[account];
	}

	/// @notice Returns the value of fungible tokens in the inscription(`indId`)
	function balanceOfIns(uint256 insId) external view returns (uint256){
		return _balancesOfIns[insId];
	}

    /// @notice Return the FT balance of owner's slot.
    function balanceOf(
        address owner
    ) public view returns (uint256) {
        require(
            owner != address(0),
            "ERC7583: address zero is not a valid owner"
        );
        return slotFT[owner] != 0 ? _balancesOfIns[slotFT[owner]] : 0;
    }

    /// @notice Return decimal.
    function decimals() public pure returns (uint8) {
        return 0;
    }

    /// @notice Return the owner of the inscription(`indId`).
	function ownerOf(uint256 insId) public view returns (address owner){
		return _owners[insId];
	}

    /// @notice Return the current supply of FT.
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

	/**
     *  --------- For NFT ---------
     */

    /// @notice Approve `to` to operate on `insId`
	function approveIns(address to, uint256 insId) external returns (bool){
		address owner = ERC7583.ownerOf(insId);
        require(to != owner, "ERC7583: approval to current owner");

        require(
            msg.sender == owner,
            "ERC7583: approve caller is not token owner"
        );

        _approveIns(to, insId);
		return true;
	}

	function _approveIns(address to, uint256 insId) internal virtual {
        _tokenApprovals[insId] = to;
        emit ApprovalIns(ERC7583.ownerOf(insId), to, insId);
    }

	/// @notice Approve `operator` to operate on all of `msg.sender` inscriptions
	function setApprovalForAll(address operator, bool approved) external {
		require(msg.sender != operator, "ERC7583: approve to caller");
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
	}

	/// @notice Return the operator address of `insId`
	function getApproved(uint256 insId) public view virtual override returns (address) {
        _requireMinted(insId);

        return _tokenApprovals[insId];
    }

	function _requireMinted(uint256 insId) internal view virtual {
        require(_exists(insId), "ERC7583: invalid inscription ID");
    }

	function _exists(uint256 insId) internal view virtual returns (bool) {
        return _owners[insId] != address(0);
    }

	/// @notice Return if `insId` has been minted
	function exists(uint256 insId) external view virtual returns (bool) {
        return _exists(insId);
    }

	/// @notice Return the `operator` of `owner`
	function isApprovedForAll(address owner, address operator) public view virtual override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

	function _isApprovedOrOwner(address spender, uint256 insId) internal view virtual returns (bool) {
        address owner = ERC7583.ownerOf(insId);
        return (spender == owner || isApprovedForAll(owner, spender) || getApproved(insId) == spender);
    }

	/// @notice Transfers `insId` from `from` to `to`.
	function transferInsFrom(
        address from,
        address to,
        uint256 insId
    ) public recordSlot(from, to, insId) {
        require(_isApprovedOrOwner(msg.sender, insId), "ERC7583: caller is not token owner nor approved");
        _transferIns(from, to, insId);
    }

	function _transferIns(
        address from,
        address to,
        uint256 insId
    ) internal virtual {
        require(ERC7583.ownerOf(insId) == from, "ERC7583: transfer from incorrect owner");
        require(to != address(0), "ERC7583: transfer to the zero address");

        // Clear approvals from the previous owner
        _approveIns(address(0), insId);

        _insBalances[from] -= 1;
        _insBalances[to] += 1;
        _owners[insId] = to;

        emit TransferIns(from, to, insId);
    }

	/// @notice Safely transfers `insId` inscription from `from` to `to`, checking first that contract recipients are aware of the ERC7583 protocol to prevent tokens from being forever locked.
    function safeTransferFrom(
        address from,
        address to,
        uint256 insId
    ) public override recordSlot(from, to, insId) {
        require(_isApprovedOrOwner(msg.sender, insId), "ERC7583: caller is not token owner nor approved");
		_transferIns(from, to, insId);
		require(_checkOnERC721Received(from, to, insId), "ERC7583: transfer to non ERC7583Receiver implementer");
    }

	function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

	function _checkOnERC721Received(
        address from,
        address to,
        uint256 insId
    ) private returns (bool) {
        if (isContract(to)) {
            try IERC7583TokenReceiver(to).onERC7583Received(msg.sender, from, insId) returns (bytes4 retval) {
                return retval == IERC7583TokenReceiver.onERC7583Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("ERC7583: transfer to non IERC7583TokenReceiver implementer");
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

    /// @notice This is the entry point for users to inscribe data into event data.
    /// @dev ECDSA (Elliptic Curve Digital Signature Algorithm) can be used to ensure that the inscribed data is correct.
    function inscribe(uint256 insId, bytes calldata data) external {
		require(_isApprovedOrOwner(msg.sender, insId), "ERC7583: caller is not token owner nor approved");
        require(!inscribed[insId], "This inscription has been inscribed");
		emit Inscribe(insId, data);
	}

    /// @notice This is the entry point for users to mint inscription.
	function mint(uint256 insId) external recordSlot(address(0), msg.sender, insId) {
		require(_totalSupply < maxSupply, "Exceeded mint limit");

    	_mint(msg.sender, tickNumber);
		tickNumber++;
    	_totalSupply+=mintLimit;

		emit Transfer(address(0), msg.sender, mintLimit);
        emit TransferInsToIns(0, insId, mintLimit);
	}

	function _mint(address to, uint256 insId) internal virtual {
        require(to != address(0), "ERC7583: mint to the zero address");
        require(!_exists(insId), "ERC7583: token already minted");

        _insBalances[to] += 1;
        _owners[insId] = to;

        emit TransferIns(address(0), to, insId);
    }

    /**
     *  --------- For FT ---------
     */

    /// @notice Obtain the authorized quantity of FT.
    function allowance(
        address owner,
        address spender
    ) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    /// @notice Check if the spender's authorized limit is sufficient and deduct the amount of this expenditure from the spender's limit.
    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(
                currentAllowance >= amount,
                "ERC7583: insufficient allowance"
            );
            unchecked {
                _approveFT(owner, spender, currentAllowance - amount);
            }
        }
    }

    /// @notice The approve function specifically provided for FT.
    /// @param owner The owner of the FT
    /// @param spender The authorized person
    /// @param amount The authorized amount
    function _approveFT(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC7583: approve from the zero address");
        require(spender != address(0), "ERC7583: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function approve(
        address spender,
        uint256 amount
    ) public returns (bool) {
        address owner = msg.sender;
        _approveFT(owner, spender, amount);
        return true;
    }

    /// @notice Only the balance in the slot can be transferred using this function.
    /// @param to Receiver address
    /// @return value The amount sent
    function transfer(address to, uint256 value) public virtual returns (bool) {
        address from = msg.sender;
        _transferFT(from, to, value);
        return true;
    }

    function _transferFT(address from, address to, uint256 value) internal {
        require(slotFT[from] != 0, "The sender must own a slot");

        // Slots can be minted.
        if (slotFT[to] == 0) {
            _mint(to, tickNumber);
            slotFT[to] = tickNumber;
            tickNumber++;
        }

        uint256 fromBalance = _balancesOfIns[slotFT[from]];
        require(fromBalance >= value, "Insufficient balance");

        unchecked {
            _balancesOfIns[slotFT[from]] = fromBalance - value;
        }
        _balancesOfIns[slotFT[to]] += value;

        emit Transfer(from, to, value);
        emit TransferInsToIns(slotFT[from], slotFT[to], value);
    }

    /// @notice You can freely transfer the balances of multiple inscriptions into one, including slots.
    /// @param froms Multiple inscriptions with a decreased balance
    /// @param to Inscription with a increased balance
    function waterToWine(WTW[] calldata froms, uint256 to) public {
        require(froms.length <= 500, "You drink too much!");
        require(ownerOf(to) == msg.sender, "Is not yours");

        uint256 increment;
        // for from
        for (uint256 i; i < froms.length; i++) {
            uint256 from = froms[i].insId;
            require(ownerOf(from) == msg.sender, "Is not yours");
            uint256 amount = froms[i].amount;
            uint256 fromBalance = _balancesOfIns[from];
            require(fromBalance >= amount, "Insufficient balance");
            unchecked {
                _balancesOfIns[from] = fromBalance - amount;
            }
            increment += amount;
            emit TransferInsToIns(from, to, amount);
        }

        _balancesOfIns[to] += increment;
    }

    /// @notice You can freely transfer the balances between any two of your inscriptions, including slots.
    /// @notice The inspiration comes from the first miracle of Jesus as described in John 2:1-12.
    /// @param from Inscription with a decreased balance
    /// @param to Inscription with a increased balance
    /// @param amount The value you gonna transfer
    function waterToWine(uint256 from, uint256 to, uint256 amount) public {
        require(
            ownerOf(from) == msg.sender && ownerOf(to) == msg.sender,
            "Is not yours"
        );

        uint256 fromBalance = _balancesOfIns[from];
        require(fromBalance >= amount, "Insufficient balance");
        unchecked {
            _balancesOfIns[from] = fromBalance - amount;
        }
        _balancesOfIns[to] += amount;

        emit TransferInsToIns(from, to, amount);
    }

    /// @notice Only the balance in the slot can be transferred using this function.
    /// @dev Embed Inscribe event into Transfer of ERC7583
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transferFT(from, to, amount);
        return true;
    }

    /**
     *  --------- modify ---------
     */

    /// @notice Slot can only be transferred at the end. If the user does not have a slot, then this insId will serve as his slot.
    /// @dev This modify is used only for the transfer of NFTs.
    /// @dev The balance of FT is only related to the slot.
    /// @param from Sender
    /// @param to Receiver
    /// @param insId TokenID of NFT
    modifier recordSlot(
        address from,
        address to,
        uint256 insId
    ) {
        // record the balance of the slot
        if (from == address(0)) _balancesOfIns[insId] = mintLimit;

        if (from != address(0) && slotFT[from] == insId) {
            require(
                _insBalances[from] == 1,
                "Slot can only be transferred at the end"
            );
            slotFT[from] = 0;
        }

        if (to != address(0) && slotFT[to] == 0) {
            slotFT[to] = insId;
        }
        _;
    }
}
