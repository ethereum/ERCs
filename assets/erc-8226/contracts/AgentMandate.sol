// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IAgentMandate} from "./interfaces/IAgentMandate.sol";
import {IComplianceProvider} from "./interfaces/IComplianceProvider.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title AgentMandate
/// @notice Reference RAMS registry. Holds one mandate per (agent, principal), gates agent actions via
///         canExecute, records use via recordExecution, and supports role-based freeze.
contract AgentMandate is IAgentMandate, AccessControl, EIP712 {
    bytes32 public constant ENFORCER_ROLE = keccak256("ENFORCER_ROLE");
    bytes32 public constant RECORDER_ROLE = keccak256("RECORDER_ROLE");

    bytes32 private constant GRANT_MANDATE_TYPEHASH = keccak256(
        "GrantMandate(address agent,uint48 validFrom,uint48 validUntil,"
        "address principal,address complianceProvider,bytes32 identityRef,"
        "address asset,uint256 maxTransactionValue,uint256 maxCumulativeValue,"
        "bytes32 metadata,bytes32[] actions,uint256 nonce,uint256 deadline)"
    );
    bytes32 private constant REVOKE_MANDATE_TYPEHASH =
        keccak256("RevokeMandate(address agent,address principal,uint256 nonce,uint256 deadline)");
    bytes32 private constant EXTEND_MANDATE_TYPEHASH =
        keccak256("ExtendMandate(address agent,address principal,uint48 newValidUntil,uint256 nonce,uint256 deadline)");
    bytes32 private constant SET_OPERATOR_TYPEHASH =
        keccak256("SetOperator(address principal,address operator,bool approved,uint256 nonce,uint256 deadline)");

    mapping(address agent => mapping(address principal => Mandate)) private _mandates;
    mapping(address agent => mapping(address principal => mapping(bytes32 action => bool))) private _actionEnabled;
    mapping(address agent => mapping(address principal => bytes32[])) private _enabledList;
    mapping(address principal => mapping(address operator => bool)) private _operatorApproved;
    mapping(address agent => bool) private _frozen;
    mapping(address principal => uint256) public nonces;

    error ZeroComplianceProvider();
    error MandateAlreadyActive();
    error NoActiveMandate();
    error PrincipalNotEligible();
    error InvalidExpiry();
    error NotPrincipal();
    error NotAuthorized();
    error SignatureExpired();
    error InvalidSignature();
    error UnauthorizedRecorder();
    error NotExecutable();
    error ExceedsTransactionCap();
    error ExceedsCumulativeCap();
    error AdminEnforcerOverlap();

    constructor(address admin) EIP712("RAMS", "1") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IAgentMandate
    function grantMandate(GrantMandateParams calldata params, bytes calldata signature) external {
        if (params.complianceProvider == address(0)) revert ZeroComplianceProvider();
        if (params.validUntil <= block.timestamp || params.validUntil <= params.validFrom) revert InvalidExpiry();

        Mandate storage existing = _mandates[params.agent][params.principal];
        if (existing.principal != address(0) && !existing.revoked && block.timestamp <= existing.validUntil) {
            revert MandateAlreadyActive();
        }

        _authPrincipal(params.principal, _grantStructHash(params), params.deadline, signature);

        (bool eligible,, uint48 expiresAt) =
            IComplianceProvider(params.complianceProvider).checkPrincipal(params.principal, params.identityRef);
        if (!eligible) revert PrincipalNotEligible();
        if (expiresAt != 0 && params.validUntil > expiresAt) revert InvalidExpiry();

        _clearActions(params.agent, params.principal);

        _mandates[params.agent][params.principal] = Mandate({
            agent: params.agent,
            validFrom: params.validFrom,
            validUntil: params.validUntil,
            principal: params.principal,
            revoked: false,
            complianceProvider: params.complianceProvider,
            identityRef: params.identityRef,
            asset: params.asset,
            maxTransactionValue: params.maxTransactionValue,
            maxCumulativeValue: params.maxCumulativeValue,
            cumulativeUsed: 0,
            metadata: params.metadata
        });

        emit MandateGranted(
            params.agent,
            params.principal,
            params.complianceProvider,
            params.asset,
            params.validFrom,
            params.validUntil,
            params.metadata
        );

        for (uint256 i = 0; i < params.actions.length; i++) {
            _actionEnabled[params.agent][params.principal][params.actions[i]] = true;
            _enabledList[params.agent][params.principal].push(params.actions[i]);
            emit ActionEnabled(params.agent, params.principal, params.actions[i]);
        }
    }

    /// @inheritdoc IAgentMandate
    function revokeMandate(address agent, address principal, uint256 deadline, bytes calldata signature) external {
        Mandate storage mandate = _mandates[agent][principal];
        if (mandate.principal == address(0) || mandate.revoked) revert NoActiveMandate();

        bytes32 structHash =
            keccak256(abi.encode(REVOKE_MANDATE_TYPEHASH, agent, principal, nonces[principal], deadline));
        _authOperator(principal, structHash, deadline, signature);

        mandate.revoked = true;
        emit MandateRevoked(agent, principal, msg.sender);
    }

    /// @inheritdoc IAgentMandate
    function extendMandate(
        address agent,
        address principal,
        uint48 newValidUntil,
        uint256 deadline,
        bytes calldata signature
    ) external {
        Mandate storage mandate = _mandates[agent][principal];
        if (mandate.principal == address(0) || mandate.revoked || block.timestamp > mandate.validUntil) {
            revert NoActiveMandate();
        }
        if (newValidUntil <= mandate.validUntil) revert InvalidExpiry();

        bytes32 structHash = keccak256(
            abi.encode(EXTEND_MANDATE_TYPEHASH, agent, principal, newValidUntil, nonces[principal], deadline)
        );
        _authOperator(principal, structHash, deadline, signature);

        (bool eligible,, uint48 expiresAt) =
            IComplianceProvider(mandate.complianceProvider).checkPrincipal(mandate.principal, mandate.identityRef);
        if (!eligible) revert PrincipalNotEligible();
        if (expiresAt != 0 && newValidUntil > expiresAt) revert InvalidExpiry();

        mandate.validUntil = newValidUntil;
        emit MandateExtended(agent, principal, newValidUntil);
    }

    /// @inheritdoc IAgentMandate
    function setOperator(address principal, address operator, bool approved, uint256 deadline, bytes calldata signature)
        external
    {
        bytes32 structHash =
            keccak256(abi.encode(SET_OPERATOR_TYPEHASH, principal, operator, approved, nonces[principal], deadline));
        _authPrincipal(principal, structHash, deadline, signature);

        _operatorApproved[principal][operator] = approved;
        emit OperatorSet(principal, operator, approved);
    }

    /// @inheritdoc IAgentMandate
    function freezeAgent(address agent) external onlyRole(ENFORCER_ROLE) {
        _frozen[agent] = true;
        emit AgentFrozen(agent, msg.sender);
    }

    /// @inheritdoc IAgentMandate
    function unfreezeAgent(address agent) external onlyRole(ENFORCER_ROLE) {
        _frozen[agent] = false;
        emit AgentUnfrozen(agent, msg.sender);
    }

    /// @inheritdoc IAgentMandate
    function recordExecution(address agent, address principal, bytes32 action, uint256 amount) external {
        Mandate storage mandate = _mandates[agent][principal];
        if (msg.sender != mandate.asset && msg.sender != principal && !hasRole(RECORDER_ROLE, msg.sender)) {
            revert UnauthorizedRecorder();
        }
        MandateReason reason = _evaluate(mandate, agent, principal, mandate.asset, action, amount);
        if (reason == MandateReason.OVER_TX_CAP) revert ExceedsTransactionCap();
        if (reason == MandateReason.OVER_CUMULATIVE_CAP) revert ExceedsCumulativeCap();
        if (reason != MandateReason.OK) revert NotExecutable();
        uint256 used = mandate.cumulativeUsed + amount;
        mandate.cumulativeUsed = used;
        emit ExecutionRecorded(agent, principal, action, amount, used);
    }

    /// @inheritdoc IAgentMandate
    function canExecute(address agent, address principal, address asset, bytes32 action, uint256 amount)
        external
        view
        returns (bool ok, MandateReason reason)
    {
        reason = _evaluate(_mandates[agent][principal], agent, principal, asset, action, amount);
        ok = reason == MandateReason.OK;
    }

    /// @inheritdoc IAgentMandate
    function isActionEnabled(address agent, address principal, bytes32 action) external view returns (bool) {
        return _actionEnabled[agent][principal][action];
    }

    /// @inheritdoc IAgentMandate
    function getMandate(address agent, address principal) external view returns (Mandate memory) {
        return _mandates[agent][principal];
    }

    /// @inheritdoc IAgentMandate
    function isOperator(address principal, address operator) external view returns (bool) {
        return _operatorApproved[principal][operator];
    }

    /// @inheritdoc IAgentMandate
    function isFrozen(address agent) external view returns (bool) {
        return _frozen[agent];
    }

    /// @inheritdoc IAgentMandate
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControl, IERC165) returns (bool) {
        return interfaceId == type(IAgentMandate).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @dev Keeps the admin role and the enforcer role on disjoint accounts, preventing self-escalation.
    function _grantRole(bytes32 role, address account) internal override returns (bool) {
        if (role == ENFORCER_ROLE && hasRole(DEFAULT_ADMIN_ROLE, account)) revert AdminEnforcerOverlap();
        if (role == DEFAULT_ADMIN_ROLE && hasRole(ENFORCER_ROLE, account)) revert AdminEnforcerOverlap();
        return super._grantRole(role, account);
    }

    /// @dev Principal-only: direct call by the principal, or a valid principal signature.
    function _authPrincipal(address principal, bytes32 structHash, uint256 deadline, bytes calldata signature) private {
        if (signature.length == 0) {
            if (msg.sender != principal) revert NotPrincipal();
        } else {
            _verifySignature(principal, structHash, deadline, signature);
        }
    }

    /// @dev Operator-allowed: principal, an approved operator, or a valid principal signature.
    function _authOperator(address principal, bytes32 structHash, uint256 deadline, bytes calldata signature) private {
        if (signature.length == 0) {
            if (msg.sender != principal && !_operatorApproved[principal][msg.sender]) revert NotAuthorized();
        } else {
            _verifySignature(principal, structHash, deadline, signature);
        }
    }

    function _verifySignature(address principal, bytes32 structHash, uint256 deadline, bytes calldata signature)
        private
    {
        if (block.timestamp > deadline) revert SignatureExpired();
        bytes32 digest = _hashTypedDataV4(structHash);
        if (!SignatureChecker.isValidSignatureNow(principal, digest, signature)) revert InvalidSignature();
        unchecked {
            nonces[principal]++;
        }
    }

    /// @dev Isolated so the 14-field encode has its own stack frame (avoids stack-too-deep without via-IR).
    function _grantStructHash(GrantMandateParams calldata params) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                GRANT_MANDATE_TYPEHASH,
                params.agent,
                params.validFrom,
                params.validUntil,
                params.principal,
                params.complianceProvider,
                params.identityRef,
                params.asset,
                params.maxTransactionValue,
                params.maxCumulativeValue,
                params.metadata,
                keccak256(abi.encodePacked(params.actions)),
                nonces[params.principal],
                params.deadline
            )
        );
    }

    /// @dev Single source of truth for canExecute and recordExecution (existence, asset, validity window,
    ///      revocation, action, freeze, and caps) so the read check and the state mutation cannot drift.
    ///      Returns MandateReason.OK when the action may execute, otherwise the first failing check.
    function _evaluate(
        Mandate storage mandate,
        address agent,
        address principal,
        address asset,
        bytes32 action,
        uint256 amount
    ) private view returns (MandateReason) {
        if (mandate.principal == address(0)) return MandateReason.NONEXISTENT;
        if (asset != mandate.asset) return MandateReason.WRONG_ASSET;
        if (block.timestamp < mandate.validFrom) return MandateReason.NOT_YET_VALID;
        if (block.timestamp > mandate.validUntil) return MandateReason.EXPIRED;
        if (mandate.revoked) return MandateReason.REVOKED;
        if (!_actionEnabled[agent][principal][action]) return MandateReason.ACTION_NOT_ENABLED;
        if (_frozen[agent]) return MandateReason.FROZEN;
        if (mandate.maxTransactionValue != type(uint256).max && amount > mandate.maxTransactionValue) {
            return MandateReason.OVER_TX_CAP;
        }
        if (
            mandate.maxCumulativeValue != type(uint256).max
                && mandate.cumulativeUsed + amount > mandate.maxCumulativeValue
        ) {
            return MandateReason.OVER_CUMULATIVE_CAP;
        }
        return MandateReason.OK;
    }

    function _clearActions(address agent, address principal) private {
        bytes32[] storage prev = _enabledList[agent][principal];
        for (uint256 i = 0; i < prev.length; i++) {
            _actionEnabled[agent][principal][prev[i]] = false;
        }
        delete _enabledList[agent][principal];
    }
}
