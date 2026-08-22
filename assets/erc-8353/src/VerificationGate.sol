// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "./IVerificationGate.sol";

/// @title VerificationGate — minimal reference implementation
/// @notice Implements the four-state lifecycle and every MUST of the draft.
///         Policy (weight function, stake sizing, promotion threshold,
///         revocation authorization) is exposed as virtual hooks — see
///         examples/ for the market-side and identity-side adapters.
abstract contract VerificationGate is IVerificationGate {
    struct Claim {
        address subject;
        address offerer;
        bytes32 claimHash;
        uint256 stake;
        uint256 weight;
        Status  status;
    }

    /// Slashed stake is burned here — never redistributed, and in particular
    /// never to the party that triggered the revocation.
    address public constant BURN = address(0xdEaD);

    mapping(bytes32 => Claim) internal _claims;
    mapping(bytes32 => mapping(address => bool)) internal _verified;
    uint256 private _nonce;

    error BadStatus(bytes32 claimId, Status actual);
    error SelfVerification(bytes32 claimId, address caller);
    error AlreadyVerified(bytes32 claimId, address caller);
    error InsufficientStake(uint256 required, uint256 provided);
    error NotAuthorized(bytes32 claimId, address caller);
    error TransferFailed();

    // ── transitions ──────────────────────────────────────────────────────

    function offer(address subject, bytes32 claimHash, bytes calldata data)
        external payable returns (bytes32 claimId)
    {
        uint256 required = _requiredStake(subject, claimHash, data);
        if (msg.value < required) revert InsufficientStake(required, msg.value);

        claimId = keccak256(abi.encode(subject, msg.sender, claimHash, _nonce++));
        _claims[claimId] = Claim({
            subject:   subject,
            offerer:   msg.sender,
            claimHash: claimHash,
            stake:     msg.value,
            weight:    0,
            status:    Status.Offered
        });
        emit ClaimOffered(claimId, subject, msg.sender, claimHash, msg.value);
    }

    function verify(bytes32 claimId, bytes32 evidenceHash) external {
        Claim storage c = _claims[claimId];
        if (c.status != Status.Offered && c.status != Status.Verified)
            revert BadStatus(claimId, c.status);
        if (msg.sender == c.subject || msg.sender == c.offerer)
            revert SelfVerification(claimId, msg.sender);
        if (_verified[claimId][msg.sender])
            revert AlreadyVerified(claimId, msg.sender);

        _verified[claimId][msg.sender] = true;
        uint256 w = weightOf(msg.sender);
        c.weight += w;
        emit ClaimVerified(claimId, msg.sender, w, evidenceHash);

        if (c.status == Status.Offered && c.weight >= _promotionThreshold(claimId))
            c.status = Status.Verified;
    }

    function settle(bytes32 claimId) external {
        Claim storage c = _claims[claimId];
        if (c.status != Status.Verified) revert BadStatus(claimId, c.status);
        if (!_canSettle(claimId, msg.sender)) revert NotAuthorized(claimId, msg.sender);

        c.status = Status.Settled;               // effects before interaction
        emit ClaimSettled(claimId);
        _onSettled(claimId);
        _payout(c.offerer, _releaseStake(claimId));
    }

    function revoke(bytes32 claimId, bytes32 reasonHash) external {
        Claim storage c = _claims[claimId];
        if (c.status != Status.Offered && c.status != Status.Verified)
            revert BadStatus(claimId, c.status);   // Settled is terminal
        if (!_canRevoke(claimId, msg.sender)) revert NotAuthorized(claimId, msg.sender);

        c.status = Status.Revoked;               // record persists forever
        emit ClaimRevoked(claimId, msg.sender, reasonHash);
        _payout(BURN, _releaseStake(claimId));   // slash: burn, never redistribute
    }

    // ── views ────────────────────────────────────────────────────────────

    function statusOf(bytes32 claimId)
        external view returns (Status status, uint256 weight)
    {
        Claim storage c = _claims[claimId];
        return (c.status, c.weight);
    }

    /// @inheritdoc IVerificationGate
    function weightOf(address verifier) public view virtual returns (uint256);

    // ── policy hooks (implementation freedom per the draft) ──────────────

    /// Stake required at offer. Default: none (zero-stake gates conform).
    function _requiredStake(address, bytes32, bytes calldata)
        internal view virtual returns (uint256) { return 0; }

    /// Accumulated verifier weight needed for Offered → Verified.
    function _promotionThreshold(bytes32) internal view virtual returns (uint256) {
        return 1;
    }

    /// Who may finalize. Default: the offerer.
    function _canSettle(bytes32 claimId, address caller)
        internal view virtual returns (bool)
    {
        return caller == _claims[claimId].offerer;
    }

    /// Who may revoke. Default: the offerer.
    function _canRevoke(bytes32 claimId, address caller)
        internal view virtual returns (bool)
    {
        return caller == _claims[claimId].offerer;
    }

    /// Post-settlement hook (e.g. update the settled party's depth).
    function _onSettled(bytes32 claimId) internal virtual {}

    // ── internals ────────────────────────────────────────────────────────

    function _releaseStake(bytes32 claimId) private returns (uint256 amount) {
        amount = _claims[claimId].stake;
        _claims[claimId].stake = 0;
    }

    function _payout(address to, uint256 amount) private {
        if (amount == 0) return;
        (bool ok, ) = payable(to).call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
