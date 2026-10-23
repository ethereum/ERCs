// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/**
 * @title XML Representable State interface (ERC-8100)
 * @notice Exposes an XML template that an off-chain renderer evaluates at a
 *         fixed block to obtain a representation of the contract state.
 */
interface IXMLRepresentableState {
    function stateXmlTemplate() external view returns (string memory);
}

/// @notice Minimal ERC20 for local tests only.
/// @dev Unrestricted mint. Do not use in production.
contract ERC20TokenExample is IXMLRepresentableState {

    string public name;                  // The name of this token
    string public symbol;                // The symbol of this token
    uint8 public immutable decimals;     // The units

    uint256 public totalSupply;           // Increasing supply = mint; decreasing supply = burn

    // The actual mapping of who (address) owns how much (integer).
    mapping(address account => uint256 balance) public balanceOf;

    // The bookkeeping of allowances used by transferFrom.
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    /*
     * ERC-8100 representation support
     *
     * Solidity mappings are not enumerable. The arrays below track every key
     * touched through this contract's public operations, allowing the renderer
     * to expose all relevant balances and allowances as arrays of tuples.
     */

    struct BalanceEntry {
        address account;
        uint256 amount;
    }

    struct AllowanceEntry {
        address owner;
        address spender;
        uint256 amount;
    }

    address[] private balanceAccounts;
    mapping(address account => bool tracked) private isBalanceAccountTracked;

    AllowanceEntry[] private allowanceKeys;
    mapping(address owner => mapping(address spender => bool tracked))
        private isAllowanceKeyTracked;

    /*
     * Events
     */

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /*
     * Constructor - Create a token
     */

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    /*
     * ERC-20-style functions
     */

    function mint(address to, uint256 value) external returns (bool) {
        require(to != address(0), "mint to zero");

        _trackBalanceAccount(to);
        totalSupply += value;
        balanceOf[to] += value;

        emit Transfer(address(0), to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _trackAllowanceKey(msg.sender, spender);
        allowance[msg.sender][spender] = value;

        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 currentAllowance = allowance[from][msg.sender];
        require(currentAllowance >= value, "ERC20: insufficient allowance");

        _trackAllowanceKey(from, msg.sender);

        if (currentAllowance != type(uint256).max) {
            allowance[from][msg.sender] = currentAllowance - value;
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }

        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) private {
        require(to != address(0), "transfer to zero");

        uint256 fromBalance = balanceOf[from];
        require(fromBalance >= value, "ERC20: insufficient balance");

        _trackBalanceAccount(from);
        _trackBalanceAccount(to);

        balanceOf[from] = fromBalance - value;
        balanceOf[to] += value;

        emit Transfer(from, to, value);
    }

    /*
     * ERC-8100 views
     */

    /// @notice Returns decimals as uint256 for renderers using the common integer profile.
    function decimalsAsUint256() external view returns (uint256) {
        return uint256(decimals);
    }

    /// @notice Returns all tracked balance keys together with their current values.
    function balanceEntries() external view returns (BalanceEntry[] memory entries) {
        entries = new BalanceEntry[](balanceAccounts.length);

        for (uint256 i = 0; i < balanceAccounts.length; i++) {
            address account = balanceAccounts[i];
            entries[i] = BalanceEntry({account: account, amount: balanceOf[account]});
        }
    }

    /// @notice Returns all tracked allowance keys together with their current values.
    function allowanceEntries() external view returns (AllowanceEntry[] memory entries) {
        entries = new AllowanceEntry[](allowanceKeys.length);

        for (uint256 i = 0; i < allowanceKeys.length; i++) {
            AllowanceEntry storage key = allowanceKeys[i];
            entries[i] = AllowanceEntry({
                owner: key.owner,
                spender: key.spender,
                amount: allowance[key.owner][key.spender]
            });
        }
    }

    /**
     * @notice Returns the static ERC-8100 XML template for this token.
     * @dev Amounts are represented in the smallest token unit. `Decimals` is
     *      represented separately, avoiding a mutable/dynamic XML scale.
     */
    function stateXmlTemplate() external pure override returns (string memory) {
        return string.concat(
            "<?xml version='1.0' encoding='UTF-8'?>",
            "<ERC20TokenExample xmlns='urn:example:erc20-token' xmlns:evmstate='urn:evm:state:1.0' ",
            "  evmstate:chain-id='' evmstate:contract-address='' evmstate:block-number=''>",
            "  <Metadata>",
            "    <Name evmstate:call='name()(string)' evmstate:format='string'/>",
            "    <Symbol evmstate:call='symbol()(string)' evmstate:format='string'/>",
            "    <Decimals evmstate:call='decimalsAsUint256()(uint256)' evmstate:format='decimal'/>",
            "  </Metadata>",
            "  <TotalSupply unit='smallest-token-unit' evmstate:call='totalSupply()(uint256)' evmstate:format='decimal'/>",
            "  <Balances unit='smallest-token-unit' evmstate:call='balanceEntries()(tuple(address,uint256)[])' evmstate:item-element='Balance'>",
            "    <Balance>",
            "      <Account evmstate:item-field='0' evmstate:format='address'/>",
            "      <Amount evmstate:item-field='1' evmstate:format='decimal'/>",
            "    </Balance>",
            "  </Balances>",
            "  <Allowances unit='smallest-token-unit' evmstate:call='allowanceEntries()(tuple(address,address,uint256)[])' evmstate:item-element='Allowance'>",
            "    <Allowance>",
            "      <Owner evmstate:item-field='0' evmstate:format='address'/>",
            "      <Spender evmstate:item-field='1' evmstate:format='address'/>",
            "      <Amount evmstate:item-field='2' evmstate:format='decimal'/>",
            "    </Allowance>",
            "  </Allowances>",
            "</ERC20TokenExample>"
        );
    }

    function _trackBalanceAccount(address account) private {
        if (!isBalanceAccountTracked[account]) {
            isBalanceAccountTracked[account] = true;
            balanceAccounts.push(account);
        }
    }

    function _trackAllowanceKey(address owner, address spender) private {
        if (!isAllowanceKeyTracked[owner][spender]) {
            isAllowanceKeyTracked[owner][spender] = true;
            allowanceKeys.push(AllowanceEntry({owner: owner, spender: spender, amount: 0}));
        }
    }
}
