// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC1404Restriction} from "./IERC1404Restriction.sol";

/// @title RestrictedToken — an ERC-20 token bound to an external ERC-1404 rule engine.
///
/// @notice A thin ERC-20 that delegates its address policy to an immutable
/// `WhitelistRuleEngine` (or any `IERC1404Restriction`), and keeps one restriction
/// of its own: a global transfer pause. Swap the address policy by pointing a new
/// token at a different engine, or share one engine across many tokens.
///
/// The engine is consulted in `_update`, the single chokepoint OpenZeppelin's
/// ERC-20 routes `transfer`, `transferFrom`, `_mint` and `_burn` through.
///
/// @dev This contract is the ERC-1404 *restricted token*; the engine is a
/// *restriction source*. The enforcement-consistency requirement binds this
/// contract, not the engine, because this is the contract an integrator queries
/// and the contract that performs the transfer. Two consequences are visible below:
///
///  1. `detectTransferRestriction` reports the *aggregate* outcome of every source
///     this token's transfer path consults (the pause flag held here and the
///     address policy held in the engine), rather than forwarding the engine's code
///     unchanged. A naive `return rules.detectTransferRestriction(...)` passthrough
///     would report `0` while a paused transfer reverts.
///  2. It also mirrors the *scope* of enforcement. `_update` skips the mint and burn
///     legs, so the predictor returns `TRANSFER_OK` for them too; forwarding the
///     engine's answer there would report `SENDER_NOT_WHITELISTED` for a mint that
///     this token does not gate.
///
/// Restriction codes:
///   0  No restriction              (engine)
///   1  Sender not whitelisted      (engine)
///   2  Recipient not whitelisted   (engine)
///   3  Transfers paused            (this token)
/// Code 3 is allocated by this token, which owns the aggregate code space and must
/// keep its own codes clear of the ones its sources can return.
contract RestrictedToken is ERC20, Ownable, IERC1404Restriction {
    /**
     * @notice The external compliance engine consulted on every holder-to-holder transfer.
     */
    IERC1404Restriction public immutable rules;

    /**
     * @notice Restriction code meaning the transfer is unrestricted.
     */
    uint8 public constant TRANSFER_OK = 0;
    /**
     * @notice Restriction code returned by this token while transfers are paused.
     */
    uint8 public constant TRANSFERS_PAUSED = 3;

    /**
     * @notice Human-readable message for `TRANSFERS_PAUSED`.
     */
    string public constant MESSAGE_TRANSFERS_PAUSED = "Transfers paused";

    /**
     * @notice True while holder-to-holder transfers are suspended by the owner.
     */
    bool public paused;

    /**
     * @notice Thrown when a transfer is blocked by the aggregate restriction policy.
     * @param code Restriction code reported by `detectTransferRestriction`.
     * @param message Human-readable explanation of the restriction.
     */
    error TransferRestricted(uint8 code, string message);
    /**
     * @notice Thrown when the engine address supplied at construction is the zero address.
     */
    error EngineAddressZero();

    /**
     * @notice Emitted when the global transfer pause is switched on or off.
     * @param status New pause status.
     */
    event PausedUpdated(bool status);

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
     * @notice Suspend or resume all holder-to-holder transfers.
     * @param status True to pause, false to resume.
     */
    function setPaused(bool status) external onlyOwner {
        paused = status;
        emit PausedUpdated(status);
    }

    /**
     * @notice Mint `amount` new tokens to `to`.
     * @dev Not gated by the engine; see `_update`.
     * @param to Recipient of the newly minted tokens.
     * @param amount Amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Burn `amount` tokens held by `from`.
     * @dev Not gated by the engine; see `_update`.
     * @param from Holder whose tokens are burned.
     * @param amount Amount of tokens to burn.
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    // -------------------------------------------------------------------------
    // ERC-1404 — the aggregate view of this token's transfer path
    // -------------------------------------------------------------------------

    /**
     * @notice Returns a restriction code for the proposed transfer, or 0 if unrestricted.
     * @dev Aggregates both restriction sources in the order `_update` applies them, so the
     *      reported code is the one enforcement would raise. Mint (`from == address(0)`) and
     *      burn (`to == address(0)`) legs are ungated by this token and report `TRANSFER_OK`.
     * @param from Sender address, or the zero address for a mint.
     * @param to Recipient address, or the zero address for a burn.
     * @param value Token amount to transfer.
     * @return Restriction code; 0 means the transfer is allowed.
     */
    function detectTransferRestriction(address from, address to, uint256 value)
        public
        view
        override
        returns (uint8)
    {
        if (from == address(0) || to == address(0)) return TRANSFER_OK;
        if (paused) return TRANSFERS_PAUSED;
        return rules.detectTransferRestriction(from, to, value);
    }

    /**
     * @notice Returns the human-readable message for a restriction code.
     * @dev This token surfaces codes from two sources, so it answers for both: its own code is
     *      resolved here and everything else is delegated to the engine, which supplies a message
     *      for its own codes and an unknown-code string otherwise. No code this token can return
     *      is left without a message.
     * @param restrictionCode Code returned by `detectTransferRestriction`.
     * @return Human-readable description of the restriction.
     */
    function messageForTransferRestriction(uint8 restrictionCode) public view override returns (string memory) {
        if (restrictionCode == TRANSFERS_PAUSED) return MESSAGE_TRANSFERS_PAUSED;
        return rules.messageForTransferRestriction(restrictionCode);
    }

    // -------------------------------------------------------------------------
    // ERC-20 hook — consult the aggregate policy on every transfer path
    // -------------------------------------------------------------------------

    /**
     * @notice Enforces the aggregate restriction on every holder-to-holder transfer.
     * @dev `_update` is the single chokepoint for transfer, transferFrom, mint and burn.
     *      Enforcement calls `detectTransferRestriction` directly, which is what keeps the
     *      reported code and the enforced one identical by construction. Mint (`from == 0`)
     *      and burn (`to == 0`) legs are skipped so issuance/redemption is not blocked;
     *      remove the zero-address guard in the predictor and here together if your policy
     *      must gate them too.
     * @param from Sender address, or the zero address on mint.
     * @param to Recipient address, or the zero address on burn.
     * @param value Token amount being moved.
     */
    function _update(address from, address to, uint256 value) internal override {
        uint8 code = detectTransferRestriction(from, to, value);
        if (code != TRANSFER_OK) {
            revert TransferRestricted(code, messageForTransferRestriction(code));
        }
        super._update(from, to, value);
    }
}
