// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {IPolicyEnforcedAccount} from "./IPolicyEnforcedAccount.sol";

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/**
 * @title PolicyEnforcedRegistry (v2)
 * @notice Reference registry for the draft ERC "Policy-Enforced Agent Accounts". Existing accounts
 *         (for example Safes) opt in by calling `declare` themselves; from then on only the publisher
 *         they named can post their policy commitments. Nobody can write another account's data.
 *
 *  - No owner, no admin, not upgradeable, holds no funds.
 *  - The registry only records what the account and its publisher state. It does not enforce the
 *    policy (the policy signer does) and does not prove the signer follows it (receipts are evidence).
 *  - Time rules. The registry cannot tell a tightening from a loosening, so the rules are about time:
 *    every policy the publisher posts waits at least the account's `minDelay` (`setPending`, then it
 *    decides from `effectiveAt`); every signer change after the first waits the current `minDelay`,
 *    except clearing to all zeros, which only removes the claim of enforcement. The account itself
 *    (its owners) may activate a policy at once, as it could change its signers anyway. The emergency
 *    stop only restricts, so the publisher or the account engages it at once.
 */
contract PolicyEnforcedRegistry is IPolicyEnforcedAccount, IERC165 {
    error NotPublisher();
    error NotPublisherOrAccount();
    error ZeroSigner();
    error BadSignerType();
    error DelayTooLong();
    error StaleVersion();
    error TooSoon();
    error NotDue();
    error NoPending();

    /// @notice Upper bound on `minDelay`, so an account can never lock its own signers away.
    uint32 public constant MAX_MIN_DELAY = 30 days;

    mapping(address account => Signers[]) private _signers;
    mapping(address account => PolicyCommitment) private _active;
    mapping(address account => PolicyCommitment) private _pending;
    mapping(address account => bool) private _hasPending;
    mapping(address account => bool) private _stopped;
    mapping(address account => string) private _mandateURI;
    mapping(address account => bytes32) private _mandateHash;

    // ----- signers (called by the account) -----

    /**
     * @notice Declare, rotate or clear (all zeros) the caller's signers. The first declaration, and any
     *         declaration while nothing is enforced, applies at once; clearing applies at once; any other
     *         change waits the current `minDelay` (lowering `minDelay` included). A newer request
     *         replaces a pending one.
     */
    function declare(address policySigner_, address publisher, address receiptSigner, uint32 minDelay, uint8 signerType) external {
        bool clearing = policySigner_ == address(0);
        if (clearing) {
            if (publisher != address(0) || receiptSigner != address(0) || signerType != 0) revert ZeroSigner();
            minDelay = 0;
        } else {
            if (publisher == address(0) || receiptSigner == address(0)) revert ZeroSigner();
            if (signerType == 0 || signerType > 4) revert BadSignerType();
        }
        if (minDelay > MAX_MIN_DELAY) revert DelayTooLong();
        _dropPendingSigners(msg.sender);
        Signers memory cur = _signersAt(msg.sender, uint64(block.timestamp));
        uint64 at = uint64(block.timestamp);
        if (!clearing && cur.policySigner != address(0)) at += cur.minDelay;
        _signers[msg.sender].push(Signers(policySigner_, publisher, receiptSigner, at, minDelay, signerType));
        if (at == block.timestamp) emit SignersDeclared(msg.sender, policySigner_, publisher, receiptSigner, minDelay, signerType);
        else emit SignersPending(msg.sender, policySigner_, publisher, receiptSigner, minDelay, signerType, at);
    }

    /// @notice Cancel the caller's pending signer change.
    function cancelSigners() external {
        if (!_dropPendingSigners(msg.sender)) revert NoPending();
    }

    // ----- commitments -----

    modifier onlyPublisher(address account) {
        Signers memory s = _signersAt(account, uint64(block.timestamp));
        if (s.policySigner == address(0) || s.publisher != msg.sender) revert NotPublisher();
        _;
    }

    modifier onlyPublisherOrAccount(address account) {
        if (msg.sender != account) {
            Signers memory s = _signersAt(account, uint64(block.timestamp));
            if (s.policySigner == address(0) || s.publisher != msg.sender) revert NotPublisherOrAccount();
        }
        _;
    }

    /**
     * @notice A policy that decides from now.
     *  - From the account: any newer version, at once (its owners hold that authority anyway).
     *  - From the publisher: only confirming a pending change at or after its effectiveAt (it keeps
     *    its effectiveAt). Earlier reverts with `NotDue`; anything else with `NoPending`.
     */
    function activate(address account, bytes32 policyHash, uint64 version, string calldata policyURI, string calldata schemaURI)
        external
        onlyPublisherOrAccount(account)
    {
        _settle(account);
        PolicyCommitment memory cur = _active[account];
        if (msg.sender != account) {
            if (cur.version == version && cur.policyHash == policyHash && cur.effectiveAt != 0) return; // confirmed (settled above)
            if (_hasPending[account] && _pending[account].version == version && _pending[account].policyHash == policyHash) revert NotDue();
            revert NoPending();
        }
        if (version < cur.version || (version == cur.version && policyHash != cur.policyHash)) revert StaleVersion();
        if (version == cur.version && cur.effectiveAt != 0) return; // already in effect
        if (_hasPending[account] && _pending[account].version <= version) _cancelPending(account, "superseded");
        uint64 at = uint64(block.timestamp);
        _active[account] = PolicyCommitment(policyHash, version, at, policyURI, schemaURI);
        emit PolicyActivated(account, policyHash, version, at, policyURI, schemaURI);
    }

    /// @notice A change that waits: it decides from `effectiveAt`, at least `minDelay` from now, unless cancelled first.
    function setPending(address account, bytes32 policyHash, uint64 version, uint64 effectiveAt, string calldata policyURI, string calldata schemaURI)
        external
        onlyPublisher(account)
    {
        _settle(account);
        Signers memory s = _signersAt(account, uint64(block.timestamp));
        if (effectiveAt <= block.timestamp || effectiveAt < block.timestamp + s.minDelay) revert TooSoon();
        if (version <= _active[account].version) revert StaleVersion();
        if (_hasPending[account]) _cancelPending(account, "superseded");
        _pending[account] = PolicyCommitment(policyHash, version, effectiveAt, policyURI, schemaURI);
        _hasPending[account] = true;
        emit PolicyPending(account, policyHash, version, effectiveAt, policyURI, schemaURI);
    }

    /// @notice Cancel the pending change before it becomes effective (publisher or account).
    function cancelPending(address account, string calldata reason) external onlyPublisherOrAccount(account) {
        _settle(account);
        if (!_hasPending[account]) revert NoPending();
        _cancelPending(account, reason);
    }

    /// @notice Engage or lift the emergency stop (publisher or account, both at once).
    function setStopped(address account, bool stopped, string calldata reason) external onlyPublisherOrAccount(account) {
        if (_stopped[account] == stopped) return;
        _stopped[account] = stopped;
        if (stopped) emit EmergencyStop(account, reason);
        else emit EmergencyStopLifted(account);
    }

    function setMandate(address account, string calldata mandateURI, bytes32 configHash) external onlyPublisher(account) {
        _mandateURI[account] = mandateURI;
        _mandateHash[account] = configHash;
        emit MandateSet(account, mandateURI, configHash);
    }

    // ----- reads -----

    function policySigner(address account) external view returns (Signers memory) {
        return _signersAt(account, uint64(block.timestamp));
    }

    function signersAt(address account, uint64 timestamp) external view returns (Signers memory) {
        return _signersAt(account, timestamp);
    }

    function pendingSignersOf(address account) external view returns (bool exists, Signers memory) {
        Signers[] storage s = _signers[account];
        if (s.length > 0 && s[s.length - 1].since > block.timestamp) return (true, s[s.length - 1]);
        return (false, Signers(address(0), address(0), address(0), 0, 0, 0));
    }

    function policyOf(address account) external view returns (PolicyCommitment memory) {
        if (_hasPending[account] && _pending[account].effectiveAt <= block.timestamp) return _pending[account];
        return _active[account];
    }

    function pendingPolicyOf(address account) external view returns (bool exists, PolicyCommitment memory) {
        if (_hasPending[account] && _pending[account].effectiveAt > block.timestamp) return (true, _pending[account]);
        return (false, PolicyCommitment(bytes32(0), 0, 0, "", ""));
    }

    function mandateOf(address account) external view returns (string memory, bytes32) {
        return (_mandateURI[account], _mandateHash[account]);
    }

    function isStopped(address account) external view returns (bool) {
        return _stopped[account];
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IPolicyEnforcedAccount).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    // ----- internal -----

    function _signersAt(address account, uint64 timestamp) private view returns (Signers memory) {
        Signers[] storage s = _signers[account];
        for (uint256 i = s.length; i > 0; i--) if (s[i - 1].since <= timestamp) return s[i - 1];
        return Signers(address(0), address(0), address(0), 0, 0, 0);
    }

    /// @dev Removes a not-yet-effective signer change (there is at most one, always the last entry).
    function _dropPendingSigners(address account) private returns (bool) {
        Signers[] storage s = _signers[account];
        if (s.length == 0 || s[s.length - 1].since <= block.timestamp) return false;
        Signers memory p = s[s.length - 1];
        s.pop();
        emit SignersCancelled(account, p.policySigner, p.publisher, p.receiptSigner, p.since);
        return true;
    }

    /// @dev A pending change whose time has come becomes the active one (it was announced by PolicyPending).
    function _settle(address account) private {
        if (_hasPending[account] && _pending[account].effectiveAt <= block.timestamp) {
            _active[account] = _pending[account];
            _hasPending[account] = false;
            PolicyCommitment storage a = _active[account];
            emit PolicyActivated(account, a.policyHash, a.version, a.effectiveAt, a.policyURI, a.schemaURI);
        }
    }

    function _cancelPending(address account, string memory reason) private {
        _hasPending[account] = false;
        emit PolicyCancelled(account, _pending[account].policyHash, _pending[account].version, reason);
    }
}
