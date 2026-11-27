// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {IAgentMandate} from "./interfaces/IAgentMandate.sol";
import {IComplianceProvider} from "./interfaces/IComplianceProvider.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title AgentMandate
/// @notice Reference RAMS registry. Holds one mandate per (agent, principal, target). A mandate enables actions,
///         each with constraints on its calldata, and holds one limit per asset and direction shared by all of its actions.
///         canExecute gates an execution and recordExecution counts its flows. Supports role-based freeze.
contract AgentMandate is IAgentMandate, AccessControl, EIP712 {
    struct LimitKey {
        address asset;
        Direction direction;
    }

    struct ActionRules {
        bool enabled;
        Constraint[] constraints;
    }

    /// @dev The mappings serve the per-execution checks. The arrays list their keys, for getLimits and for clearing
    ///      a mandate on a new grant.
    struct MandateRecord {
        Mandate mandate;
        mapping(bytes32 action => ActionRules) rules;
        mapping(address asset => mapping(Direction => Limit)) limits;
        bytes32[] actions;
        LimitKey[] limitKeys;
    }

    bytes32 public constant ENFORCER_ROLE = keccak256("ENFORCER_ROLE");
    bytes32 public constant RECORDER_ROLE = keccak256("RECORDER_ROLE");

    bytes32 private constant GRANT_MANDATE_TYPEHASH = keccak256(
        "GrantMandate(address agent,uint48 validFrom,uint48 validUntil,"
        "address principal,address complianceProvider,bytes32 identityRef,"
        "address target,Action[] actions,Limit[] limits,bytes32 metadata,uint256 nonce,uint256 deadline)"
        "Action(bytes32 action,Constraint[] constraints)" "Constraint(uint8 index,uint8 check,bytes32 value)"
        "Limit(address asset,uint8 direction,uint256 maxTransactionValue,uint256 maxCumulativeValue,uint256 cumulativeUsed)"
    );
    bytes32 private constant ACTION_TYPEHASH =
        keccak256("Action(bytes32 action,Constraint[] constraints)Constraint(uint8 index,uint8 check,bytes32 value)");
    bytes32 private constant CONSTRAINT_TYPEHASH = keccak256("Constraint(uint8 index,uint8 check,bytes32 value)");
    bytes32 private constant LIMIT_TYPEHASH = keccak256(
        "Limit(address asset,uint8 direction,uint256 maxTransactionValue,uint256 maxCumulativeValue,uint256 cumulativeUsed)"
    );
    bytes32 private constant REVOKE_MANDATE_TYPEHASH =
        keccak256("RevokeMandate(address agent,address principal,address target,uint256 nonce,uint256 deadline)");
    bytes32 private constant EXTEND_MANDATE_TYPEHASH = keccak256(
        "ExtendMandate(address agent,address principal,address target,uint48 newValidUntil,uint256 nonce,uint256 deadline)"
    );
    bytes32 private constant SET_OPERATOR_TYPEHASH =
        keccak256("SetOperator(address principal,address operator,bool approved,uint256 nonce,uint256 deadline)");

    mapping(bytes32 mandateKey => MandateRecord) private _records;
    mapping(address principal => mapping(address operator => bool)) private _operatorApproved;
    mapping(address agent => bool) private _frozenAgent;
    mapping(address principal => bool) private _frozenPrincipal;
    mapping(address principal => uint256) public nonces;

    error ZeroComplianceProvider();
    error ZeroAction();
    error ZeroAsset();
    error DuplicateLimit(address asset, Direction direction);
    error MandateAlreadyActive();
    error NoActiveMandate();
    error PrincipalNotEligible();
    error InvalidExpiry();
    error NotPrincipal();
    error NotAuthorized();
    error SignatureExpired();
    error InvalidSignature();
    error UnauthorizedRecorder();
    error CumulativeUsedAboveCap(address asset, Direction direction);
    error AdminEnforcerOverlap();

    constructor(address admin) EIP712("RAMS", "1") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @inheritdoc IAgentMandate
    function grantMandate(GrantMandateParams calldata params, bytes calldata signature) external {
        if (params.complianceProvider == address(0)) revert ZeroComplianceProvider();
        if (params.validUntil <= block.timestamp || params.validUntil <= params.validFrom) revert InvalidExpiry();

        MandateRecord storage record = _records[_mandateKey(params.agent, params.principal, params.target)];
        Mandate storage existing = record.mandate;
        if (existing.principal != address(0) && !existing.revoked && block.timestamp <= existing.validUntil) {
            revert MandateAlreadyActive();
        }

        _authOperator(params.principal, _grantStructHash(params), params.deadline, signature);

        (bool eligible,, uint48 expiresAt) =
            IComplianceProvider(params.complianceProvider).checkPrincipal(params.principal, params.identityRef);
        if (!eligible) revert PrincipalNotEligible();
        if (expiresAt != 0 && params.validUntil > expiresAt) revert InvalidExpiry();

        _clear(record);

        record.mandate = Mandate({
            agent: params.agent,
            validFrom: params.validFrom,
            validUntil: params.validUntil,
            principal: params.principal,
            revoked: false,
            complianceProvider: params.complianceProvider,
            identityRef: params.identityRef,
            target: params.target,
            metadata: params.metadata
        });

        emit MandateGranted(
            params.agent,
            params.principal,
            params.target,
            params.complianceProvider,
            params.validFrom,
            params.validUntil,
            params.metadata
        );

        for (uint256 index = 0; index < params.actions.length; index++) {
            Action calldata action = params.actions[index];
            if (action.action == bytes32(0)) revert ZeroAction();
            ActionRules storage rules = record.rules[action.action];
            rules.enabled = true;
            record.actions.push(action.action);
            for (uint256 position = 0; position < action.constraints.length; position++) {
                rules.constraints.push(action.constraints[position]);
            }
            emit ActionEnabled(params.agent, params.principal, action.action, params.target);
        }

        for (uint256 index = 0; index < params.limits.length; index++) {
            Limit calldata limit = params.limits[index];
            if (limit.asset == address(0)) revert ZeroAsset();
            if (record.limits[limit.asset][limit.direction].asset != address(0)) {
                revert DuplicateLimit(limit.asset, limit.direction);
            }
            if (limit.cumulativeUsed > limit.maxCumulativeValue) {
                revert CumulativeUsedAboveCap(limit.asset, limit.direction);
            }
            record.limits[limit.asset][limit.direction] = limit;
            record.limitKeys.push(LimitKey(limit.asset, limit.direction));
            emit LimitSet(
                params.agent,
                params.principal,
                limit.asset,
                params.target,
                limit.direction,
                limit.maxTransactionValue,
                limit.maxCumulativeValue,
                limit.cumulativeUsed
            );
        }
    }

    /// @inheritdoc IAgentMandate
    function revokeMandate(address agent, address principal, address target, uint256 deadline, bytes calldata signature)
        external
    {
        Mandate storage mandate = _records[_mandateKey(agent, principal, target)].mandate;
        if (mandate.principal == address(0) || mandate.revoked) revert NoActiveMandate();

        bytes32 structHash =
            keccak256(abi.encode(REVOKE_MANDATE_TYPEHASH, agent, principal, target, nonces[principal], deadline));
        _authOperator(principal, structHash, deadline, signature);

        mandate.revoked = true;
        emit MandateRevoked(agent, principal, target, msg.sender);
    }

    /// @inheritdoc IAgentMandate
    function extendMandate(
        address agent,
        address principal,
        address target,
        uint48 newValidUntil,
        uint256 deadline,
        bytes calldata signature
    ) external {
        Mandate storage mandate = _records[_mandateKey(agent, principal, target)].mandate;
        if (mandate.principal == address(0) || mandate.revoked || block.timestamp > mandate.validUntil) {
            revert NoActiveMandate();
        }
        if (newValidUntil <= mandate.validUntil) revert InvalidExpiry();

        bytes32 structHash = keccak256(
            abi.encode(EXTEND_MANDATE_TYPEHASH, agent, principal, target, newValidUntil, nonces[principal], deadline)
        );
        _authOperator(principal, structHash, deadline, signature);

        (bool eligible,, uint48 expiresAt) =
            IComplianceProvider(mandate.complianceProvider).checkPrincipal(mandate.principal, mandate.identityRef);
        if (!eligible) revert PrincipalNotEligible();
        if (expiresAt != 0 && newValidUntil > expiresAt) revert InvalidExpiry();

        mandate.validUntil = newValidUntil;
        emit MandateExtended(agent, principal, target, newValidUntil);
    }

    /// @inheritdoc IAgentMandate
    function setOperator(address principal, address operator, bool approved, uint256 deadline, bytes calldata signature)
        external
    {
        if (signature.length != 0 || approved || !hasRole(ENFORCER_ROLE, msg.sender)) {
            bytes32 structHash = keccak256(
                abi.encode(SET_OPERATOR_TYPEHASH, principal, operator, approved, nonces[principal], deadline)
            );
            _authPrincipal(principal, structHash, deadline, signature);
        }

        _operatorApproved[principal][operator] = approved;
        emit OperatorSet(principal, operator, approved);
    }

    /// @inheritdoc IAgentMandate
    function freezeAgent(address agent) external onlyRole(ENFORCER_ROLE) {
        _frozenAgent[agent] = true;
        emit AgentFrozen(agent, msg.sender);
    }

    /// @inheritdoc IAgentMandate
    function unfreezeAgent(address agent) external onlyRole(ENFORCER_ROLE) {
        _frozenAgent[agent] = false;
        emit AgentUnfrozen(agent, msg.sender);
    }

    /// @inheritdoc IAgentMandate
    function freezePrincipal(address principal) external onlyRole(ENFORCER_ROLE) {
        _frozenPrincipal[principal] = true;
        emit PrincipalFrozen(principal, msg.sender);
    }

    /// @inheritdoc IAgentMandate
    function unfreezePrincipal(address principal) external onlyRole(ENFORCER_ROLE) {
        _frozenPrincipal[principal] = false;
        emit PrincipalUnfrozen(principal, msg.sender);
    }

    /// @inheritdoc IAgentMandate
    function recordExecution(
        address agent,
        address principal,
        address target,
        bytes32 action,
        bytes calldata data,
        Flow[] calldata flows
    ) external {
        if (msg.sender != target && msg.sender != principal && !hasRole(RECORDER_ROLE, msg.sender)) {
            revert UnauthorizedRecorder();
        }
        MandateRecord storage record = _records[_mandateKey(agent, principal, target)];
        MandateReason reason = _evaluate(record, agent, principal, action, data, flows);
        if (reason != MandateReason.OK) revert MandateBlocked(reason);
        for (uint256 index = 0; index < flows.length; index++) {
            if (flows[index].amount == 0) continue;
            Flow calldata flow = flows[index];
            Limit storage limit = record.limits[flow.asset][flow.direction];
            uint256 used = limit.cumulativeUsed + flow.amount;
            limit.cumulativeUsed = used;
            emit ExecutionRecorded(agent, principal, action, target, flow.asset, flow.direction, flow.amount, used);
        }
    }

    /// @inheritdoc IAgentMandate
    function canExecute(
        address agent,
        address principal,
        address target,
        bytes32 action,
        bytes calldata data,
        Flow[] calldata flows
    ) external view returns (bool ok, MandateReason reason) {
        reason = _evaluate(_records[_mandateKey(agent, principal, target)], agent, principal, action, data, flows);
        ok = reason == MandateReason.OK;
    }

    /// @inheritdoc IAgentMandate
    function isActionEnabled(address agent, address principal, address target, bytes32 action)
        external
        view
        returns (bool)
    {
        return _records[_mandateKey(agent, principal, target)].rules[action].enabled;
    }

    /// @inheritdoc IAgentMandate
    function getMandate(address agent, address principal, address target) external view returns (Mandate memory) {
        return _records[_mandateKey(agent, principal, target)].mandate;
    }

    /// @inheritdoc IAgentMandate
    function getActions(address agent, address principal, address target) external view returns (bytes32[] memory) {
        return _records[_mandateKey(agent, principal, target)].actions;
    }

    /// @inheritdoc IAgentMandate
    function getLimits(address agent, address principal, address target) external view returns (Limit[] memory limits) {
        MandateRecord storage record = _records[_mandateKey(agent, principal, target)];
        limits = new Limit[](record.limitKeys.length);
        for (uint256 index = 0; index < record.limitKeys.length; index++) {
            limits[index] = record.limits[record.limitKeys[index].asset][record.limitKeys[index].direction];
        }
    }

    /// @inheritdoc IAgentMandate
    function getConstraints(address agent, address principal, address target, bytes32 action)
        external
        view
        returns (Constraint[] memory)
    {
        return _records[_mandateKey(agent, principal, target)].rules[action].constraints;
    }

    /// @inheritdoc IAgentMandate
    function isOperator(address principal, address operator) external view returns (bool) {
        return _operatorApproved[principal][operator];
    }

    /// @inheritdoc IAgentMandate
    function isAgentFrozen(address agent) external view returns (bool) {
        return _frozenAgent[agent];
    }

    /// @inheritdoc IAgentMandate
    function isPrincipalFrozen(address principal) external view returns (bool) {
        return _frozenPrincipal[principal];
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
            _verifySignature(principal, structHash, deadline, signature, false);
        }
    }

    /// @dev Principal or approved operator: a direct call by either, or a valid signature by either.
    function _authOperator(address principal, bytes32 structHash, uint256 deadline, bytes calldata signature) private {
        if (signature.length == 0) {
            if (msg.sender != principal && !_operatorApproved[principal][msg.sender]) revert NotAuthorized();
        } else {
            _verifySignature(principal, structHash, deadline, signature, true);
        }
    }

    /// @dev The principal signs as an EOA or through ERC-1271. An operator signs as an EOA: a contract operator
    ///      calls directly. Every signature uses the principal's nonce.
    function _verifySignature(
        address principal,
        bytes32 structHash,
        uint256 deadline,
        bytes calldata signature,
        bool operatorAllowed
    ) private {
        if (block.timestamp > deadline) revert SignatureExpired();
        bytes32 digest = _hashTypedDataV4(structHash);
        if (!SignatureChecker.isValidSignatureNow(principal, digest, signature)) {
            (address signer, ECDSA.RecoverError recoverError,) = ECDSA.tryRecover(digest, signature);
            if (!operatorAllowed || recoverError != ECDSA.RecoverError.NoError || !_operatorApproved[principal][signer])
            {
                revert InvalidSignature();
            }
        }
        unchecked {
            nonces[principal]++;
        }
    }

    function _clear(MandateRecord storage record) private {
        for (uint256 index = 0; index < record.actions.length; index++) {
            delete record.rules[record.actions[index]];
        }
        delete record.actions;
        for (uint256 index = 0; index < record.limitKeys.length; index++) {
            delete record.limits[record.limitKeys[index].asset][record.limitKeys[index].direction];
        }
        delete record.limitKeys;
    }

    /// @dev One mandate per (agent, principal, target). Derived rather than chosen, so a gated token can compute
    ///      it from (msg.sender, holder, address(this)).
    function _mandateKey(address agent, address principal, address target) private pure returns (bytes32) {
        return keccak256(abi.encode(agent, principal, target));
    }

    function _grantStructHash(GrantMandateParams calldata params) private view returns (bytes32) {
        return keccak256(
            bytes.concat(
                abi.encode(
                    GRANT_MANDATE_TYPEHASH,
                    params.agent,
                    params.validFrom,
                    params.validUntil,
                    params.principal,
                    params.complianceProvider,
                    params.identityRef,
                    params.target
                ),
                abi.encode(
                    _hashActions(params.actions),
                    _hashLimits(params.limits),
                    params.metadata,
                    nonces[params.principal],
                    params.deadline
                )
            )
        );
    }

    function _hashActions(Action[] calldata actions) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](actions.length);
        for (uint256 index = 0; index < actions.length; index++) {
            Constraint[] calldata constraints = actions[index].constraints;
            bytes32[] memory constraintHashes = new bytes32[](constraints.length);
            for (uint256 position = 0; position < constraints.length; position++) {
                constraintHashes[position] = keccak256(
                    abi.encode(
                        CONSTRAINT_TYPEHASH,
                        constraints[position].index,
                        uint8(constraints[position].check),
                        constraints[position].value
                    )
                );
            }
            hashes[index] = keccak256(
                abi.encode(ACTION_TYPEHASH, actions[index].action, keccak256(abi.encodePacked(constraintHashes)))
            );
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function _hashLimits(Limit[] calldata limits) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](limits.length);
        for (uint256 index = 0; index < limits.length; index++) {
            hashes[index] = keccak256(
                abi.encode(
                    LIMIT_TYPEHASH,
                    limits[index].asset,
                    uint8(limits[index].direction),
                    limits[index].maxTransactionValue,
                    limits[index].maxCumulativeValue,
                    limits[index].cumulativeUsed
                )
            );
        }
        return keccak256(abi.encodePacked(hashes));
    }

    /// @dev Single source of truth for canExecute and recordExecution, so the read check and the state mutation
    ///      cannot drift. Returns MandateReason.OK when the action may execute, otherwise the first failing check.
    ///      A zero-amount flow needs no limit. Reverts first on a flow list that repeats an asset and direction.
    function _evaluate(
        MandateRecord storage record,
        address agent,
        address principal,
        bytes32 action,
        bytes calldata data,
        Flow[] calldata flows
    ) private view returns (MandateReason) {
        for (uint256 index = 0; index < flows.length; index++) {
            for (uint256 previous = 0; previous < index; previous++) {
                if (flows[previous].asset == flows[index].asset && flows[previous].direction == flows[index].direction)
                {
                    revert DuplicateLimit(flows[index].asset, flows[index].direction);
                }
            }
        }
        Mandate storage mandate = record.mandate;
        if (mandate.principal == address(0)) return MandateReason.NONEXISTENT;
        if (_frozenAgent[agent]) return MandateReason.AGENT_FROZEN;
        if (_frozenPrincipal[principal]) return MandateReason.PRINCIPAL_FROZEN;
        if (block.timestamp < mandate.validFrom) return MandateReason.NOT_YET_VALID;
        if (block.timestamp > mandate.validUntil) return MandateReason.EXPIRED;
        if (mandate.revoked) return MandateReason.REVOKED;
        ActionRules storage rules = record.rules[action];
        if (!rules.enabled) return MandateReason.ACTION_NOT_ENABLED;
        if (!_constraintsPass(rules.constraints, data)) return MandateReason.CONSTRAINT_FAILED;
        for (uint256 index = 0; index < flows.length; index++) {
            if (flows[index].amount == 0) continue;
            Limit storage limit = record.limits[flows[index].asset][flows[index].direction];
            if (limit.asset == address(0)) return MandateReason.NO_LIMIT;
            if (limit.maxTransactionValue != type(uint256).max && flows[index].amount > limit.maxTransactionValue) {
                return MandateReason.OVER_TX_CAP;
            }
            if (
                limit.maxCumulativeValue != type(uint256).max
                    && flows[index].amount > limit.maxCumulativeValue - limit.cumulativeUsed
            ) {
                return MandateReason.OVER_CUMULATIVE_CAP;
            }
        }
        return MandateReason.OK;
    }

    /// @dev An EQUALS constraint passes if any EQUALS constraint on the same index matches. A word past the end of
    ///      the calldata fails.
    function _constraintsPass(Constraint[] storage constraints, bytes calldata data) private view returns (bool) {
        for (uint256 index = 0; index < constraints.length; index++) {
            Constraint storage constraint = constraints[index];
            if (data.length < 4 + 32 * (uint256(constraint.index) + 1)) return false;
            bytes32 word = _word(data, constraint.index);
            if (constraint.check == Check.EQUALS) {
                bool matched;
                for (uint256 other = 0; other < constraints.length && !matched; other++) {
                    matched = constraints[other].check == Check.EQUALS && constraints[other].index == constraint.index
                        && constraints[other].value == word;
                }
                if (!matched) return false;
            } else if (constraint.check == Check.NOT_EQUALS) {
                if (word == constraint.value) return false;
            } else if (constraint.check == Check.AT_MOST) {
                if (uint256(word) > uint256(constraint.value)) return false;
            } else if (uint256(word) < uint256(constraint.value)) {
                return false;
            }
        }
        return true;
    }

    function _word(bytes calldata data, uint8 index) private pure returns (bytes32) {
        uint256 offset = 4 + uint256(index) * 32;
        return bytes32(data[offset:offset + 32]);
    }
}
