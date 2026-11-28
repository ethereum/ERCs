// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {EIP712} from "@openzeppelin-contracts-5/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin-contracts-5/utils/cryptography/SignatureChecker.sol";
import {IReceivePolicy} from "./interfaces/IReceivePolicy.sol";

/**
 * @title MultiTokenAllowlistPolicy
 * @notice Example `IReceivePolicy` registry supporting both on-chain allowlists and scalable
 *         off-chain Signed Allowlist Tickets cached via EIP-1153 transient storage (`TSTORE`).
 * @dev Accounts can manage a persistent on-chain allowlist for frequent counterparties while
 *      issuing 65-byte EIP-712 tickets via a delegated `signer` for large (10,000+) sets
 *      with only a single packed storage slot (`signer` + `epoch`) per recipient.
 */
contract MultiTokenAllowlistPolicy is IReceivePolicy, EIP712 {
    /**
     * @notice Packed per-recipient ticket configuration (fits in one 32-byte storage slot).
     * @dev `signer` is the delegated key issuing tickets; `epoch` enables O(1) mass invalidation.
     */
    struct TicketConfig {
        address signer;
        uint64 epoch;
    }

    /**
     * @notice EIP-712 typehash for `proveTransientTicket`.
     * @dev Binds `from`, `to`, `epoch`, and `expiry` across all tokens using this policy.
     */
    bytes32 public constant ALLOWLIST_TICKET_TYPEHASH =
        keccak256("AllowlistTicket(address from,address to,uint64 epoch,uint40 expiry)");

    /**
     * @notice Emitted when an account updates a sender's allowlist status in the shared registry.
     * @dev Applies across all tokens pointing `to`'s policy to this contract.
     * @param from The sender address (`address(0)` for mints) whose status changed.
     * @param to The recipient account updating its shared allowlist.
     * @param allowed True if `from` is allowed, false otherwise.
     */
    event MultiTokenAllowlistUpdated(address indexed from, address indexed to, bool allowed);

    /**
     * @notice Emitted when an account sets a timed `uint40` expiry for a sender in the shared registry.
     * @dev `0` revokes access; `type(uint40).max` grants permanent access.
     * @param from The sender address (`address(0)` for mints) whose expiry changed.
     * @param to The recipient account updating its shared allowlist.
     * @param expiry Unix timestamp until which `from` is allowed (`expiry > block.timestamp`).
     */
    event MultiTokenAllowlistExpiryUpdated(address indexed from, address indexed to, uint40 expiry);

    /**
     * @notice Emitted when an account sets or rotates its delegated ticket `signer`.
     * @dev Updating the signer automatically increments `epoch` to invalidate prior tickets.
     * @param account The recipient account.
     * @param signer The new delegated ticket signer (`address(0)` disables ticket issuance).
     * @param newEpoch The new active ticket epoch.
     */
    event TicketSignerUpdated(address indexed account, address indexed signer, uint64 newEpoch);

    /**
     * @notice Emitted when an account increments its ticket `epoch` for O(1) mass revocation.
     * @dev Invalidates all tickets issued under previous epochs.
     * @param account The recipient account.
     * @param newEpoch The new active ticket epoch.
     */
    event TicketEpochIncremented(address indexed account, uint64 newEpoch);

    /**
     * @notice Emitted when an account revokes a specific sender's ticket within the active epoch.
     * @dev Avoids rotating the global `epoch` for all other counterparties.
     * @param from The revoked sender address.
     * @param to The recipient account.
     * @param epoch The epoch in which `from` was revoked.
     */
    event TicketRevoked(address indexed from, address indexed to, uint64 indexed epoch);

    /**
     * @notice Emitted when a signed allowlist ticket is verified and cached in transient storage.
     * @dev Valid only for the remainder of the current transaction.
     * @param from The authorized sender.
     * @param to The protected recipient.
     * @param epoch The ticket epoch verified.
     */
    event TransientTicketProven(address indexed from, address indexed to, uint64 epoch);

    /**
     * @notice Reverted when a recipient has not configured a delegated ticket signer.
     * @dev Triggered if `ticketConfig(to).signer == address(0)`.
     * @param to The recipient address.
     */
    error TicketSignerNotConfigured(address to);

    /**
     * @notice Reverted when a ticket's `epoch` does not match the recipient's active `epoch`.
     * @dev Indicates the ticket was invalidated by signer or epoch rotation.
     * @param expected The recipient's current active epoch.
     * @param actual The epoch provided in the ticket.
     */
    error InvalidTicketEpoch(uint64 expected, uint64 actual);

    /**
     * @notice Reverted when a ticket's `expiry` timestamp has passed.
     * @dev Checked against `block.timestamp > expiry`.
     * @param expiry The expired ticket timestamp.
     */
    error ExpiredAllowlistTicket(uint40 expiry);

    /**
     * @notice Reverted when a sender's ticket has been explicitly revoked in the current epoch.
     * @dev Set via `revokeTicket`.
     * @param from The revoked sender address.
     * @param to The recipient address.
     * @param epoch The active epoch.
     */
    error TicketAlreadyRevoked(address from, address to, uint64 epoch);

    /**
     * @notice Reverted when a ticket signature fails ECDSA or ERC-1271 verification for `signer`.
     * @dev Ensures only the recipient's configured `signer` can issue valid tickets.
     * @param signer The expected delegated signer address.
     */
    error InvalidTicketSignature(address signer);

    mapping(address account => mapping(address sender => uint40)) private _allowedUntil;
    mapping(address account => TicketConfig) private _ticketConfigs;
    mapping(address account => mapping(uint64 epoch => mapping(address sender => bool))) private _revokedTickets;

    /**
     * @notice Initializes the EIP-712 domain for `AllowlistTicket` verification.
     * @dev Uses name `"MultiTokenAllowlistPolicy"` and version `"1"`.
     */
    constructor() EIP712("MultiTokenAllowlistPolicy", "1") {}

    /**
     * @notice Adds or removes `sender` on `msg.sender`'s shared allowlist.
     * @dev Sets expiry to `type(uint40).max` when `allowed` is true, or `0` when false. Emits {MultiTokenAllowlistUpdated}.
     * @param sender The sender address to update.
     * @param allowed True to allow permanently, false to revoke.
     */
    function setAllowed(address sender, bool allowed) external {
        _allowedUntil[msg.sender][sender] = allowed ? type(uint40).max : 0;
        emit MultiTokenAllowlistUpdated(sender, msg.sender, allowed);
    }

    /**
     * @notice Sets a `uint40` expiration timestamp for `sender` on `msg.sender`'s shared allowlist.
     * @dev Pass `0` to revoke, `type(uint40).max` for permanent access, or a future timestamp.
     *      Emits {MultiTokenAllowlistExpiryUpdated}.
     * @param sender The sender address to update.
     * @param expiry Unix timestamp until which `sender` is allowed (`expiry > block.timestamp`).
     */
    function setAllowedUntil(address sender, uint40 expiry) external {
        _allowedUntil[msg.sender][sender] = expiry;
        emit MultiTokenAllowlistExpiryUpdated(sender, msg.sender, expiry);
    }

    /**
     * @notice Batch-updates multiple senders on `msg.sender`'s shared allowlist.
     * @dev Emits {MultiTokenAllowlistUpdated} for each element in `senders`.
     * @param senders Array of sender addresses to update.
     * @param allowed True to allow all listed senders permanently, false to revoke all.
     */
    function setAllowedBatch(address[] calldata senders, bool allowed) external {
        uint40 expiry = allowed ? type(uint40).max : 0;
        uint256 length = senders.length;
        for (uint256 i = 0; i < length; ++i) {
            address sender = senders[i];
            _allowedUntil[msg.sender][sender] = expiry;
            emit MultiTokenAllowlistUpdated(sender, msg.sender, allowed);
        }
    }

    /**
     * @notice Sets or rotates `msg.sender`'s delegated ticket `signer` and increments `epoch`.
     * @dev Auto-incrementing `epoch` invalidates all prior tickets in O(1) with a single `SSTORE`.
     * @param signer The new delegated ticket signer (`address(0)` disables ticket issuance).
     */
    function setTicketSigner(address signer) external {
        TicketConfig storage config = _ticketConfigs[msg.sender];
        uint64 newEpoch = config.epoch + 1;
        config.signer = signer;
        config.epoch = newEpoch;
        emit TicketSignerUpdated(msg.sender, signer, newEpoch);
    }

    /**
     * @notice Increments `msg.sender`'s active ticket `epoch` for O(1) mass revocation.
     * @dev Keeps the current `signer` while invalidating all tickets from prior epochs.
     */
    function incrementEpoch() external {
        TicketConfig storage config = _ticketConfigs[msg.sender];
        uint64 newEpoch = config.epoch + 1;
        config.epoch = newEpoch;
        emit TicketEpochIncremented(msg.sender, newEpoch);
    }

    /**
     * @notice Revokes `sender`'s ticket within `msg.sender`'s current active epoch.
     * @dev Leaves all other counterparties' tickets valid.
     * @param sender The sender address to revoke.
     */
    function revokeTicket(address sender) external {
        uint64 currentEpoch = _ticketConfigs[msg.sender].epoch;
        _revokedTickets[msg.sender][currentEpoch][sender] = true;
        emit TicketRevoked(sender, msg.sender, currentEpoch);
    }

    /**
     * @notice Verifies an off-chain `AllowlistTicket` and caches authorization in EIP-1153 transient storage.
     * @dev Intended to be batched (e.g., via Multicall, ERC-4337, or EIP-7702) immediately before
     *      `token.transfer` / `transferFrom` so `canReceive` reads the transient flag via `TLOAD`
     *      without incurring any permanent `SSTORE`.
     * @param from The authorized sender (`address(0)` for mints).
     * @param to The protected recipient.
     * @param epoch The ticket epoch matching `ticketConfig(to).epoch`.
     * @param expiry Unix timestamp after which the ticket is invalid.
     * @param signature EIP-712 signature from `ticketConfig(to).signer` (ECDSA or ERC-1271).
     */
    function proveTransientTicket(address from, address to, uint64 epoch, uint40 expiry, bytes calldata signature)
        external
    {
        TicketConfig memory config = _ticketConfigs[to];
        if (config.signer == address(0)) revert TicketSignerNotConfigured(to);
        if (epoch != config.epoch) revert InvalidTicketEpoch(config.epoch, epoch);
        if (block.timestamp > expiry) revert ExpiredAllowlistTicket(expiry);
        if (_revokedTickets[to][epoch][from]) revert TicketAlreadyRevoked(from, to, epoch);

        bytes32 structHash = keccak256(abi.encode(ALLOWLIST_TICKET_TYPEHASH, from, to, epoch, expiry));
        bytes32 digest = _hashTypedDataV4(structHash);
        if (!SignatureChecker.isValidSignatureNow(config.signer, digest, signature)) {
            revert InvalidTicketSignature(config.signer);
        }

        bytes32 slot = _transientSlot(to, from);
        assembly {
            tstore(slot, 1)
        }

        emit TransientTicketProven(from, to, epoch);
    }

    /**
     * @notice Returns whether `from` is currently allowlisted by `to` in this shared registry.
     * @dev Returns `allowedUntil(from, to) > block.timestamp`. Does not reflect transient tickets.
     * @param from The sender address.
     * @param to The recipient account.
     * @return True if `from` is currently allowed by `to`.
     */
    function isAllowed(address from, address to) external view returns (bool) {
        return _allowedUntil[to][from] > block.timestamp;
    }

    /**
     * @notice Returns the `uint40` expiration timestamp for `from` on `to`'s shared allowlist.
     * @dev `0` means not allowed; `type(uint40).max` means permanently allowed.
     * @param from The sender address.
     * @param to The recipient account.
     * @return The Unix timestamp until which `from` is allowed.
     */
    function allowedUntil(address from, address to) external view returns (uint40) {
        return _allowedUntil[to][from];
    }

    /**
     * @notice Returns the delegated ticket `signer` and active `epoch` for `account`.
     * @dev Both fields are packed into a single storage slot.
     * @param account The recipient account.
     * @return signer The delegated ticket signer address.
     * @return epoch The active ticket epoch.
     */
    function ticketConfig(address account) external view returns (address signer, uint64 epoch) {
        TicketConfig memory config = _ticketConfigs[account];
        return (config.signer, config.epoch);
    }

    /**
     * @notice Returns whether `from`'s ticket has been explicitly revoked in `epoch` for `to`.
     * @dev Only reflects explicit `revokeTicket` calls, not expired timestamps or rotated epochs.
     * @param from The sender address.
     * @param to The recipient account.
     * @param epoch The epoch to query.
     * @return True if `from` was explicitly revoked in `epoch`.
     */
    function isTicketRevoked(address from, address to, uint64 epoch) external view returns (bool) {
        return _revokedTickets[to][epoch][from];
    }

    /**
     * @inheritdoc IReceivePolicy
     * @dev Checks persistent allowlist first, then EIP-1153 transient ticket authorization
     *      (while re-checking `_revokedTickets` in case a ticket was revoked mid-transaction).
     */
    function canReceive(
        address,
        /* token */
        address from,
        address to,
        uint256,
        /* amount */
        bytes calldata /* data */
    )
        external
        view
        override
        returns (bool allowed)
    {
        if (_allowedUntil[to][from] > block.timestamp) {
            return true;
        }
        bytes32 slot = _transientSlot(to, from);
        uint256 proven;
        assembly {
            proven := tload(slot)
        }
        if (proven != 0) {
            uint64 epoch = _ticketConfigs[to].epoch;
            return !_revokedTickets[to][epoch][from];
        }
        return false;
    }

    /**
     * @notice Computes the EIP-1153 transient storage slot for `(to, from)`.
     * @dev Namespaced with a domain string to avoid collisions.
     * @param to The protected recipient.
     * @param from The authorized sender.
     * @return The derived transient storage slot.
     */
    function _transientSlot(address to, address from) private pure returns (bytes32) {
        return keccak256(abi.encode("MultiTokenAllowlistPolicy.transient", to, from));
    }
}
