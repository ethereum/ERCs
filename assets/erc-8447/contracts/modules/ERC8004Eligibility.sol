// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IEligibility} from "../interfaces/IEligibility.sol";
import {IERC8004Identity} from "./interfaces/IERC8004Identity.sol";

/// @title  ERC8004Eligibility — a member must be a registered agent it holds (reference v0.4)
/// @notice An account declares the agent it acts for and posts a bond with the declaration. The
///         declaration is accepted only if the account is the agent's owner or its agent wallet at
///         that moment, and it counts only once it has stood for `maturity` seconds. `isEligible`
///         also re-reads the predicate live, so a transfer of the agent or a change of its wallet
///         makes a later `challenge` suspend the member.
///
///         The bond is what gives the period a meaning. An agent is an ERC-721 token: it can be lent
///         for one transaction, and ownership keeps no history, so a predicate read at declaration
///         and again at admission is met by borrowing the agent twice, and nothing in between shows.
///         While a declaration stands, anyone who finds the predicate failing may void it
///         (`voidDeclaration`): the voider is paid `tip` and the module keeps the rest for good
///         (`forfeited`, paid to no one), so a lapse costs the declarer the bond less the tip even
///         when it voids its own declaration. The bond comes back only through a withdrawal in two
///         steps: after `requestWithdrawal` the declaration no longer counts, but it stands, and can
///         be voided, until `completeWithdrawal`, `maturity` seconds later, returns the bond to an
///         account that holds the agent then. Holding the agent through the maturity and through
///         any withdrawal is the only way to be sure of keeping the bond against anyone who looks;
///         a borrower that is not looked at during those windows gets it back. What the bond does
///         not do is bind a seat after the declaration ends: that remains the work of `challenge`,
///         as for any module whose answer turns false.
///
///         One standing declaration per account and per agent. A read the module cannot interpret
///         is "unknown": `isEligible` reverts (the registry reads that as unevaluable) and voiding
///         and withdrawal refuse. Only the registry's own report that an agent does not exist
///         (`ERC721NonexistentToken`, as the ERC-8004 reference registry raises it) counts as an
///         answer among failed reads, and a read naming someone else counts only if at least one
///         eighth of the gas it started with is left — the registry's remainder rule, applied here
///         so that a starved lookup can neither take a holder's bond nor suspend it. A registry that
///         never answers again therefore freezes every declaration on it: no bond moves and no
///         member is suspended through this module, which leaves removal to the swarm's `REMOVE`
///         authority; a registry that reports nonexistence differently needs a module that
///         recognizes its report.
///         The module stores no claim about trust: it binds a seat to an identity and nothing more.
///         Compose it with assertion or state modules for trust conditions.
/// @dev    v0.3: a declaration is a flag of its own, not the value of the agent id (ERC-8004
///         registries number agents from 0; Agent #0 exists on the official Sepolia deployment).
///         v0.4 (ERC-8447 revision 2.3): bond, tip, maturity, two-step withdrawal, voiding, one
///         declaration per agent, three-valued reads; the forfeited remainder stays in the module.
contract ERC8004Eligibility is IEligibility {
    /// Same divisor as the registry's gas-remainder rule (ERC-8447 Section 6.4).
    uint256 private constant GAS_RESERVE_DIVISOR = 8;
    /// `ERC721NonexistentToken(uint256)` of OpenZeppelin 5, which the ERC-8004 reference registry uses.
    bytes4 private constant NONEXISTENT_TOKEN = 0x7e273289;

    enum Hold { HELD, NOT_HELD, UNKNOWN }

    IERC8004Identity public immutable identity;

    /// @notice Wei held with every declaration.
    uint256 public immutable bond;

    /// @notice Wei paid to whoever voids a lapsed declaration; the module keeps the rest for good.
    uint256 public immutable tip;

    /// @notice Seconds a declaration must stand before it counts, and a withdrawal before it
    ///         completes; at least one, so a declaration never counts in the block it was made in.
    uint64 public immutable maturity;

    /// @notice The agent an account declared; 0 when it declared none, and also when it declared
    ///         agent 0 — read `declared` to tell the two apart.
    mapping(address => uint256) public agentOf;

    /// @notice Whether a declaration of the account stands.
    mapping(address => bool) public declared;

    /// @notice When the account's standing declaration was made.
    mapping(address => uint64) public declaredAt;

    /// @notice When the account asked for its bond back; 0 when it has not.
    mapping(address => uint64) public withdrawalRequestedAt;

    /// @notice The account whose standing declaration names the agent; zero when none does.
    mapping(uint256 => address) public declarantOf;

    /// @notice Wei kept from voided declarations (each bond less its tip). No function pays it out.
    uint256 public forfeited;

    event AgentDeclared(address indexed account, uint256 indexed agentId);
    event WithdrawalRequested(address indexed account, uint256 indexed agentId);
    event DeclarationWithdrawn(address indexed account, uint256 indexed agentId, address to);
    event DeclarationVoided(address indexed account, uint256 indexed agentId, address indexed voider);

    constructor(IERC8004Identity identity_, uint256 bond_, uint256 tip_, uint64 maturity_) {
        require(address(identity_) != address(0), "ERC8004Eligibility: zero registry");
        require(tip_ != 0 && tip_ < bond_, "ERC8004Eligibility: tip must be non-zero and below the bond");
        require(maturity_ != 0, "ERC8004Eligibility: zero maturity");
        identity = identity_;
        bond = bond_;
        tip = tip_;
        maturity = maturity_;
    }

    /// @notice Declare the agent this account acts for, with the bond. Any id the registry knows is
    ///         accepted, agent 0 included; the account must be the agent's owner or its agent wallet
    ///         now, and neither the account nor the agent may have another standing declaration.
    function declareAgent(uint256 agentId) external payable {
        require(!declared[msg.sender], "ERC8004Eligibility: declaration standing");
        require(declarantOf[agentId] == address(0), "ERC8004Eligibility: agent declared by another account");
        require(msg.value == bond, "ERC8004Eligibility: wrong bond");
        Hold h = _hold(msg.sender, agentId);
        require(h != Hold.UNKNOWN, "ERC8004Eligibility: unevaluable");
        require(h == Hold.HELD, "ERC8004Eligibility: not the agent's owner or wallet");
        agentOf[msg.sender] = agentId;
        declared[msg.sender] = true;
        declaredAt[msg.sender] = uint64(block.timestamp);
        declarantOf[agentId] = msg.sender;
        emit AgentDeclared(msg.sender, agentId);
    }

    /// @notice Ask for the bond back. The declaration stops counting at once; it still stands, and
    ///         can be voided, until the withdrawal completes. A request cannot be taken back.
    function requestWithdrawal() external {
        require(declared[msg.sender], "ERC8004Eligibility: no declaration");
        require(withdrawalRequestedAt[msg.sender] == 0, "ERC8004Eligibility: withdrawal requested");
        Hold h = _hold(msg.sender, agentOf[msg.sender]);
        require(h != Hold.UNKNOWN, "ERC8004Eligibility: unevaluable");
        require(h == Hold.HELD, "ERC8004Eligibility: not held");
        withdrawalRequestedAt[msg.sender] = uint64(block.timestamp);
        emit WithdrawalRequested(msg.sender, agentOf[msg.sender]);
    }

    /// @notice Recover the bond, `maturity` seconds after the request, while still holding the
    ///         agent. The bond goes to `to`, so an account that cannot receive value names one that can.
    function completeWithdrawal(address payable to) external {
        uint64 requested = withdrawalRequestedAt[msg.sender];
        require(declared[msg.sender] && requested != 0, "ERC8004Eligibility: no withdrawal requested");
        require(block.timestamp >= uint256(requested) + maturity, "ERC8004Eligibility: withdrawal not yet due");
        uint256 agentId = agentOf[msg.sender];
        Hold h = _hold(msg.sender, agentId);
        require(h != Hold.UNKNOWN, "ERC8004Eligibility: unevaluable");
        require(h == Hold.HELD, "ERC8004Eligibility: not held");
        _clear(msg.sender, agentId);
        emit DeclarationWithdrawn(msg.sender, agentId, to);
        _send(to, bond);
    }

    /// @notice Void a standing declaration whose predicate no longer holds — the agent moved, its
    ///         wallet changed, it no longer exists — including while a withdrawal is pending. Anyone
    ///         may call, the account itself included; the caller is paid the tip and the module keeps
    ///         the rest.
    function voidDeclaration(address account) external {
        require(declared[account], "ERC8004Eligibility: no declaration");
        uint256 agentId = agentOf[account];
        Hold h = _hold(account, agentId);
        require(h != Hold.UNKNOWN, "ERC8004Eligibility: unevaluable");
        require(h == Hold.NOT_HELD, "ERC8004Eligibility: still held");
        _clear(account, agentId);
        emit DeclarationVoided(account, agentId, msg.sender);
        forfeited += bond - tip;
        _send(payable(msg.sender), tip);
    }

    /// @notice `true` iff the account's declaration has matured, no withdrawal has been requested
    ///         and the account is still the agent's owner or its agent wallet. Reverts when the
    ///         registry's answer cannot be read: unknown is not `false`.
    function isEligible(bytes32, bytes32, address account) external view returns (bool) {
        if (!declared[account] || withdrawalRequestedAt[account] != 0) return false;
        if (block.timestamp < uint256(declaredAt[account]) + maturity) return false;
        Hold h = _hold(account, agentOf[account]);
        require(h != Hold.UNKNOWN, "ERC8004Eligibility: unevaluable");
        return h == Hold.HELD;
    }

    /// Whether the account is the agent's owner or its wallet: HELD, NOT_HELD, or UNKNOWN when the
    /// registry's answer cannot be read. A nonexistent agent is held by nobody, whatever its wallet
    /// entry says; any other failed read is unknown; a read that names someone else is an answer
    /// only if at least one eighth of the gas it started with is left.
    function _hold(address account, uint256 agentId) private view returns (Hold) {
        uint256 g0 = gasleft();
        (bool ok, bytes memory ret) = address(identity).staticcall(abi.encodeWithSelector(IERC8004Identity.ownerOf.selector, agentId));
        if (!ok) {
            if (keccak256(ret) != keccak256(abi.encodeWithSelector(NONEXISTENT_TOKEN, agentId))) return Hold.UNKNOWN;
            return gasleft() < g0 / GAS_RESERVE_DIVISOR ? Hold.UNKNOWN : Hold.NOT_HELD;
        }
        if (ret.length != 32) return Hold.UNKNOWN;
        if (abi.decode(ret, (address)) == account) return Hold.HELD;
        if (gasleft() < g0 / GAS_RESERVE_DIVISOR) return Hold.UNKNOWN;
        uint256 g1 = gasleft();
        (ok, ret) = address(identity).staticcall(abi.encodeWithSelector(IERC8004Identity.getAgentWallet.selector, agentId));
        if (!ok || ret.length != 32) return Hold.UNKNOWN;
        if (abi.decode(ret, (address)) == account) return Hold.HELD;
        return gasleft() < g1 / GAS_RESERVE_DIVISOR ? Hold.UNKNOWN : Hold.NOT_HELD;
    }

    function _clear(address account, uint256 agentId) private {
        delete agentOf[account];
        delete declared[account];
        delete declaredAt[account];
        delete withdrawalRequestedAt[account];
        delete declarantOf[agentId];
    }

    function _send(address payable to, uint256 amount) private {
        (bool ok,) = to.call{value: amount}("");
        require(ok, "ERC8004Eligibility: payment failed");
    }
}
