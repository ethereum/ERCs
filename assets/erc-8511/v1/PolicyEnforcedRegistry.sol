// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {IPolicyEnforcedAccount} from "./IPolicyEnforcedAccount.sol";

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/**
 * @title PolicyEnforcedRegistry
 * @notice Reference registry for the draft ERC "Policy-Enforced Agent Accounts". Existing accounts
 *         (for example Safes) opt in by calling `declare` themselves; from then on only the publisher
 *         they named can post their policy commitments. Nobody can write another account's data.
 *
 *  - No owner, no admin, not upgradeable, holds no funds.
 *  - The registry only records what the account and its publisher state. It does not enforce the
 *    policy (the policy signer does) and does not prove the signer follows it (receipts are evidence).
 */
contract PolicyEnforcedRegistry is IPolicyEnforcedAccount, IERC165 {
    error NotPublisher();
    error ZeroSigner();
    error StaleVersion();
    error NotInFuture();
    error NoPending();

    mapping(address account => Signers[]) private _signers;
    mapping(address account => PolicyCommitment) private _active;
    mapping(address account => PolicyCommitment) private _pending;
    mapping(address account => bool) private _hasPending;
    mapping(address account => bool) private _stopped;
    mapping(address account => string) private _mandateURI;
    mapping(address account => bytes32) private _mandateHash;

    // ----- opt in (called by the account) -----

    /// @notice Declare (or rotate, or clear with all zeros) the caller's signers.
    function declare(address policySigner_, address publisher, address receiptSigner) external {
        if (policySigner_ != address(0) && (publisher == address(0) || receiptSigner == address(0))) revert ZeroSigner();
        _signers[msg.sender].push(Signers(policySigner_, publisher, receiptSigner, uint64(block.timestamp)));
        emit SignersDeclared(msg.sender, policySigner_, publisher, receiptSigner);
    }

    // ----- commitments (called by the account's publisher) -----

    modifier onlyPublisher(address account) {
        Signers[] storage s = _signers[account];
        if (s.length == 0 || s[s.length - 1].publisher != msg.sender || s[s.length - 1].policySigner == address(0)) revert NotPublisher();
        _;
    }

    /// @notice A policy that decides from now (a tightening, or a pending change that has become effective).
    function activate(address account, bytes32 policyHash, uint64 version, string calldata policyURI, string calldata schemaURI)
        external
        onlyPublisher(account)
    {
        PolicyCommitment memory cur = _current(account);
        if (version < cur.version || (version == cur.version && policyHash != cur.policyHash)) revert StaleVersion();
        if (_hasPending[account] && _pending[account].version <= version) {
            _hasPending[account] = false;
            PolicyCommitment storage p = _pending[account];
            if (p.policyHash != policyHash || p.version != version) emit PolicyCancelled(account, p.policyHash, p.version, "superseded");
        }
        uint64 at = uint64(block.timestamp);
        if (version == cur.version && cur.effectiveAt != 0) at = cur.effectiveAt; // a due pending change, now confirmed
        _active[account] = PolicyCommitment(policyHash, version, at, policyURI, schemaURI);
        emit PolicyActivated(account, policyHash, version, at, policyURI, schemaURI);
    }

    /// @notice A loosening that waits: it decides from `effectiveAt`, unless cancelled first.
    function setPending(address account, bytes32 policyHash, uint64 version, uint64 effectiveAt, string calldata policyURI, string calldata schemaURI)
        external
        onlyPublisher(account)
    {
        if (effectiveAt <= block.timestamp) revert NotInFuture();
        if (version <= _current(account).version) revert StaleVersion();
        if (_hasPending[account]) emit PolicyCancelled(account, _pending[account].policyHash, _pending[account].version, "superseded");
        _pending[account] = PolicyCommitment(policyHash, version, effectiveAt, policyURI, schemaURI);
        _hasPending[account] = true;
        emit PolicyPending(account, policyHash, version, effectiveAt, policyURI, schemaURI);
    }

    /// @notice Cancel the pending change before it becomes effective.
    function cancelPending(address account, string calldata reason) external onlyPublisher(account) {
        PolicyCommitment memory p = _pending[account];
        if (!_hasPending[account] || p.effectiveAt <= block.timestamp) revert NoPending();
        _hasPending[account] = false;
        emit PolicyCancelled(account, p.policyHash, p.version, reason);
    }

    function setStopped(address account, bool stopped, string calldata reason) external onlyPublisher(account) {
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
        Signers[] storage s = _signers[account];
        return s.length == 0 ? Signers(address(0), address(0), address(0), 0) : s[s.length - 1];
    }

    function signersAt(address account, uint64 timestamp) external view returns (Signers memory) {
        Signers[] storage s = _signers[account];
        for (uint256 i = s.length; i > 0; i--) if (s[i - 1].since <= timestamp) return s[i - 1];
        return Signers(address(0), address(0), address(0), 0);
    }

    function policyOf(address account) external view returns (PolicyCommitment memory) {
        return _current(account);
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

    function _current(address account) private view returns (PolicyCommitment memory) {
        if (_hasPending[account] && _pending[account].effectiveAt <= block.timestamp) return _pending[account];
        return _active[account];
    }
}
