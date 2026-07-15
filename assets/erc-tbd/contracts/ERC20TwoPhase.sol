// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IERC20TwoPhase } from "./IERC20TwoPhase.sol";

/// @title ERC20TwoPhase — abstract opt-in two-phase transfer extension over OZ ERC20.
/// @notice Adds `initiateTransfer` / `acceptTransfer` / `revokeTransfer` /
///         `reclaimExpired` on top of a standard ERC-20. Plain `transfer` /
///         `transferFrom` are untouched and remain atomic (opt-in extension).
///
/// @dev Escrow model (design decision):
///      A pending transfer moves the amount from the sender to the token contract's
///      OWN balance via `_transfer(from, address(this), amount)`. This is chosen over
///      a separate `pending` ledger deliberately:
///        - The accounting invariant `totalSupply == sum(balanceOf) + sum(pending)`
///          holds by construction, because escrowed amounts already sit inside
///          `balanceOf(address(this))` — no parallel bookkeeping to drift out of sync.
///        - Settlement reuses OZ's audited `_transfer`, so balances/events are correct
///          and reentrancy-safe by OZ's own checks-effects-interactions.
///      Consequently the token's own address must never be a legitimate holder for
///      other reasons; `initiateTransfer`/`acceptTransfer` are the only movers of the
///      escrow balance.
abstract contract ERC20TwoPhase is ERC20, IERC20TwoPhase {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Minimum receiver window, relative to now. Same rationale as
    ///         PendingTransfers: long enough for a genuine hand-off, short enough
    ///         that a mis-click doesn't lock funds. Sender can revoke anytime while
    ///         pending, so this is a "receiver gets at least N minutes" guarantee.
    uint64 public constant MIN_EXPIRY = 10 minutes;

    /// @notice Maximum receiver window. Prevents accidental decade-long lockups.
    uint64 public constant MAX_EXPIRY = 7 days;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Monotonic id → pending transfer. Ids never reused (see `_nextId`).
    mapping(uint256 id => PendingTransfer) private _pending;

    /// @dev Monotonic counter feeding `initiateTransfer`. First id is 1 (0 is a
    ///      sentinel meaning "no id").
    uint256 private _nextId;

    /*//////////////////////////////////////////////////////////////
                              INITIATE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC20TwoPhase
    function initiateTransfer(address to, uint256 amount, uint64 expiry)
        external
        virtual
        returns (uint256 id)
    {
        return _initiate(to, amount, expiry, address(0));
    }

    /// @inheritdoc IERC20TwoPhase
    function initiateTransferWithCommit(address to, uint256 amount, uint64 expiry, address commit)
        external
        virtual
        returns (uint256 id)
    {
        if (commit == address(0)) revert BadCommit();
        return _initiate(to, amount, expiry, commit);
    }

    /// @dev Shared initiate path. `commit == address(0)` means plain mode (accept
    ///      needs only the receiver key); non-zero means committed mode (receiver key
    ///      AND a signature by the secret key).
    function _initiate(address to, uint256 amount, uint64 expiry, address commit)
        private
        returns (uint256 id)
    {
        if (amount == 0) revert BadAmount();
        if (to == address(0) || to == msg.sender) revert BadReceiver();
        if (expiry < block.timestamp + MIN_EXPIRY) revert BadExpiry();
        if (expiry > block.timestamp + MAX_EXPIRY) revert BadExpiry();

        id = ++_nextId;

        // Effects: record pending state before moving funds.
        _pending[id] = PendingTransfer({
            from: msg.sender,
            to: to,
            amount: amount,
            expiry: expiry,
            status: Status.Pending,
            commit: commit
        });

        // Escrow: sender balance -> token contract balance. Reverts on insufficient
        // balance inside OZ `_update`. This is the interaction, but it only touches
        // internal accounting (no external call), so CEI is respected.
        _transfer(msg.sender, address(this), amount);

        emit TransferInitiated(id, msg.sender, to, amount, expiry, commit);
    }

    /*//////////////////////////////////////////////////////////////
                               ACCEPT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC20TwoPhase
    function acceptTransfer(uint256 id) external virtual {
        PendingTransfer storage t = _pending[id];
        if (t.status != Status.Pending) revert NotPending();
        if (msg.sender != t.to) revert NotReceiver();
        if (t.commit != address(0)) revert SecretRequired();

        _settle(id, t);
    }

    /// @inheritdoc IERC20TwoPhase
    /// @dev The secret key never touches the chain: the receiver proves knowledge by
    ///      signing a digest that binds chainid, this token, the transfer id, AND the
    ///      caller. Consequences:
    ///        - A mistaken submission from the wrong account leaks only a signature
    ///          over that wrong address — worthless to everyone, including the
    ///          submitter (NotReceiver), and non-replayable by others (digest binds
    ///          msg.sender).
    ///        - Mempool observation of a valid accept reveals nothing reusable.
    ///      Receiver check still runs BEFORE the signature check, so a non-receiver
    ///      learns nothing about signature validity.
    function acceptTransfer(uint256 id, bytes calldata secretSig) external virtual {
        PendingTransfer storage t = _pending[id];
        if (t.status != Status.Pending) revert NotPending();
        if (msg.sender != t.to) revert NotReceiver();

        (address recovered,,) = ECDSA.tryRecover(_acceptDigest(id, msg.sender), secretSig);
        if (t.commit == address(0) || recovered != t.commit) revert BadSecret();

        _settle(id, t);
    }

    /// @notice Digest the secret key must sign for `caller` to accept transfer `id`.
    /// @dev Exposed so clients can build the exact preimage without replicating the
    ///      encoding. Layout: abi.encode(block.chainid, address(this), id, caller).
    function _acceptDigest(uint256 id, address caller) internal view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, address(this), id, caller));
    }

    /// @notice Public helper for clients: the digest to sign with the secret key.
    function acceptDigest(uint256 id, address caller) external view returns (bytes32) {
        return _acceptDigest(id, caller);
    }

    /// @dev Shared settlement: escrow -> receiver, standard ERC-20 Transfer event.
    function _settle(uint256 id, PendingTransfer storage t) private {
        t.status = Status.Accepted;

        _transfer(address(this), t.to, t.amount);

        emit TransferAccepted(id);
    }

    /*//////////////////////////////////////////////////////////////
                               REVOKE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC20TwoPhase
    /// @dev Permitted any time while Pending (mirrors PendingTransfers: optimize for
    ///      the "wrong recipient, let me fix it" case over an irrevocable window).
    function revokeTransfer(uint256 id) external virtual {
        PendingTransfer storage t = _pending[id];
        if (t.status != Status.Pending) revert NotPending();
        if (msg.sender != t.from) revert NotSender();

        t.status = Status.Revoked;

        _transfer(address(this), t.from, t.amount);

        emit TransferRevoked(id);
    }

    /*//////////////////////////////////////////////////////////////
                              RECLAIM
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC20TwoPhase
    /// @dev Sender-only after expiry — the sole recovery path for unaccepted funds.
    function reclaimExpired(uint256 id) external virtual {
        PendingTransfer storage t = _pending[id];
        if (t.status != Status.Pending) revert NotPending();
        if (msg.sender != t.from) revert NotSender();
        if (block.timestamp <= t.expiry) revert NotExpired();

        t.status = Status.Reclaimed;

        _transfer(address(this), t.from, t.amount);

        emit TransferReclaimed(id);
    }

    /*//////////////////////////////////////////////////////////////
                                VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC20TwoPhase
    function pendingTransfer(uint256 id) external view returns (PendingTransfer memory) {
        return _pending[id];
    }

    /// @notice ERC-165: advertise both IERC165 and IERC20TwoPhase support.
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return
            interfaceId == type(IERC20TwoPhase).interfaceId
                || interfaceId == type(IERC165).interfaceId;
    }
}
