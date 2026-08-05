// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC1404Restriction} from "./IERC1404Restriction.sol";

/// @title RestrictedToken — an ERC-20 token bound to an external ERC-1404 rule engine.
///
/// @notice A thin ERC-20 that delegates all transfer-restriction logic to an
/// immutable `WhitelistRuleEngine` (or any `IERC1404Restriction`). The token
/// itself holds no compliance state — swap the policy by pointing a new token
/// at a different engine, or share one engine across many tokens.
///
/// The engine is consulted in `_update`, the single chokepoint OpenZeppelin's
/// ERC-20 routes `transfer`, `transferFrom`, `_mint` and `_burn` through.
contract RestrictedToken is ERC20, Ownable {
    /**
     * @notice The external compliance engine consulted on every holder-to-holder transfer.
     */
    IERC1404Restriction public immutable rules;

    /**
     * @notice Thrown when a transfer is blocked by the engine's restriction policy.
     * @param code Restriction code returned by the engine.
     * @param message Human-readable explanation of the restriction.
     */
    error TransferRestricted(uint8 code, string message);
    /**
     * @notice Thrown when the engine address supplied at construction is the zero address.
     */
    error EngineAddressZero();

    /**
     * @notice Deploys the token, binds it to `rules_` and mints the initial supply to the deployer.
     * @param name_ Token name.
     * @param symbol_ Token symbol.
     * @param initialSupply Amount minted to the deployer at construction.
     * @param rules_ Compliance engine consulted on every holder-to-holder transfer.
     */
    constructor(string memory name_, string memory symbol_, uint256 initialSupply, IERC1404Restriction rules_)
        ERC20(name_, symbol_)
        Ownable(msg.sender)
    {
        if (address(rules_) == address(0)) revert EngineAddressZero();
        rules = rules_;
        // Mint bypasses the engine (see `_update`); the deployer must be whitelisted
        // in the engine before it can move these tokens on.
        _mint(msg.sender, initialSupply);
    }

    /**
     * @notice Mint `amount` new tokens to `to`. Subject to the engine's recipient rule.
     * @param to Recipient of the newly minted tokens.
     * @param amount Amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Burn `amount` tokens held by `from`. Subject to the engine's sender rule.
     * @param from Holder whose tokens are burned.
     * @param amount Amount of tokens to burn.
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    // -------------------------------------------------------------------------
    // ERC-20 hook — consult the engine on every transfer path
    // -------------------------------------------------------------------------

    /**
     * @notice Enforces the engine's restriction on every holder-to-holder transfer.
     * @dev `_update` is the single chokepoint for transfer, transferFrom, mint and burn.
     *      Only holder-to-holder transfers are gated; mint (`from == 0`) and burn
     *      (`to == 0`) legs are skipped so issuance/redemption is not blocked by the
     *      whitelist. Remove the zero-address guard if your policy must gate them too.
     * @param from Sender address, or the zero address on mint.
     * @param to Recipient address, or the zero address on burn.
     * @param value Token amount being moved.
     */
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            uint8 code = rules.detectTransferRestriction(from, to, value);
            if (code != 0) {
                revert TransferRestricted(code, rules.messageForTransferRestriction(code));
            }
        }
        super._update(from, to, value);
    }
}
