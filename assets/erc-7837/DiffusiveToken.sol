// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

/**
 * @title DiffusiveToken
 * @author 
 * @notice An ERC-20-like token that mints new tokens to the recipient on each transfer, 
 *         does not reduce the sender's balance, requires a native fee per token transferred, 
 *         and caps the total supply at a maximum value. Holders can burn tokens to reduce supply.
 */

contract DiffusiveToken {
    // -----------------------------------------
    // State Variables
    // -----------------------------------------

    string public name;
    string public symbol;
    uint8 public decimals;

    uint256 public totalSupply;
    uint256 public maxSupply;
    uint256 public transferFee; // Fee per token transferred in wei

    address public owner;
    
    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;

    // -----------------------------------------
    // Events
    // -----------------------------------------

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Burn(address indexed burner, uint256 amount);
    event FeeUpdated(uint256 newFee);
    event MaxSupplyUpdated(uint256 newMaxSupply);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // -----------------------------------------
    // Modifiers
    // -----------------------------------------

    modifier onlyOwner() {
        require(msg.sender == owner, "DiffusiveToken: caller is not the owner");
        _;
    }

    // -----------------------------------------
    // Constructor
    // -----------------------------------------

    /**
     * @dev Constructor sets the initial parameters for the Diffusive Token.
     * @param _name Token name
     * @param _symbol Token symbol
     * @param _decimals Decimal places
     * @param _maxSupply The max supply of tokens that can ever exist
     * @param _transferFee Initial fee per token transferred in wei
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _maxSupply,
        uint256 _transferFee
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        maxSupply = _maxSupply;
        transferFee = _transferFee;
        owner = msg.sender;
        totalSupply = 0; // Initially, no tokens are minted
    }

    // -----------------------------------------
    // External and Public Functions
    // -----------------------------------------

    /**
     * @notice Returns the token balance of the given address.
     * @param account The address to query
     */
    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    /**
     * @notice Transfers `amount` tokens to address `to`, minting new tokens in the process.
     * @dev Requires payment of native currency: transferFee * amount.
     * @param to Recipient address
     * @param amount Number of tokens to transfer
     * @return True if successful
     */
    function transfer(address to, uint256 amount) external payable returns (bool) {
        require(to != address(0), "DiffusiveToken: transfer to zero address");
        require(amount > 0, "DiffusiveToken: amount must be greater than zero");

        uint256 requiredFee = transferFee * amount;
        require(msg.value >= requiredFee, "DiffusiveToken: insufficient fee");

        // Check max supply limit
        require(totalSupply + amount <= maxSupply, "DiffusiveToken: would exceed max supply");

        // Mint new tokens to `to`
        balances[to] += amount;
        totalSupply += amount;

        emit Transfer(msg.sender, to, amount);
        return true;
    }

    /**
     * @notice Burns `amount` tokens from the caller's balance, decreasing total supply.
     * @param amount The number of tokens to burn
     */
    function burn(uint256 amount) external {
        require(amount > 0, "DiffusiveToken: burn amount must be greater than zero");
        require(balances[msg.sender] >= amount, "DiffusiveToken: insufficient balance");

        balances[msg.sender] -= amount;
        totalSupply -= amount;

        emit Burn(msg.sender, amount);
    }

    /**
     * @notice Approves `spender` to transfer up to `amount` tokens on behalf of `msg.sender`.
     * @param spender The address authorized to spend
     * @param amount The max amount they can spend
     */
    function approve(address spender, uint256 amount) external returns (bool) {
        require(spender != address(0), "DiffusiveToken: approve to zero address");
        allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /**
     * @notice Returns the current allowance of `spender` for `owner`.
     * @param _owner The owner of the tokens
     * @param _spender The address allowed to spend the tokens
     */
    function allowance(address _owner, address _spender) external view returns (uint256) {
        return allowances[_owner][_spender];
    }

    /**
     * @notice Transfers `amount` tokens from `from` to `to` using the allowance mechanism.
     * @dev The `from` account does not lose tokens; this still mints to `to`.
     * @param from The address from which the allowance has been given
     * @param to The recipient address
     * @param amount The number of tokens to transfer (mint)
     */
    function transferFrom(address from, address to, uint256 amount) external payable returns (bool) {
        require(to != address(0), "DiffusiveToken: transfer to zero address");
        require(amount > 0, "DiffusiveToken: amount must be greater than zero");

        uint256 allowed = allowances[from][msg.sender];
        require(allowed >= amount, "DiffusiveToken: allowance exceeded");

        // Deduct from allowance
        allowances[from][msg.sender] = allowed - amount;

        uint256 requiredFee = transferFee * amount;
        require(msg.value >= requiredFee, "DiffusiveToken: insufficient fee");

        // Check max supply
        require(totalSupply + amount <= maxSupply, "DiffusiveToken: would exceed max supply");

        // Mint tokens to `to`
        balances[to] += amount;
        totalSupply += amount;

        emit Transfer(from, to, amount);
        return true;
    }

    // -----------------------------------------
    // Owner Functions
    // -----------------------------------------

    /**
     * @notice Updates the maximum supply of tokens. Must be >= current totalSupply.
     * @param newMaxSupply The new maximum supply
     */
    function setMaxSupply(uint256 newMaxSupply) external onlyOwner {
        require(newMaxSupply >= totalSupply, "DiffusiveToken: new max < current supply");
        maxSupply = newMaxSupply;
        emit MaxSupplyUpdated(newMaxSupply);
    }

    /**
     * @notice Updates the per-token transfer fee.
     * @param newFee The new fee in wei per token transferred
     */
    function setTransferFee(uint256 newFee) external onlyOwner {
        transferFee = newFee;
        emit FeeUpdated(newFee);
    }

    /**
     * @notice Allows the owner to withdraw accumulated native currency fees.
     * @param recipient The address that will receive the withdrawn fees
     */
    function withdrawFees(address payable recipient) external onlyOwner {
        require(recipient != address(0), "DiffusiveToken: withdraw to zero address");
        uint256 balance = address(this).balance;
        (bool success, ) = recipient.call{value: balance}("");
        require(success, "DiffusiveToken: withdrawal failed");
    }

    // -----------------------------------------
    // Fallback and Receive
    // -----------------------------------------

    // Allows the contract to receive Ether.
    receive() external payable {}
}