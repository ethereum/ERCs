// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {IERC8118AgentAuthorizationBase, BatchAuthorization} from "./interfaces/IERC8118AgentAuthorizationBase.sol";
import {AuthorizationTypes} from "./libraries/AuthorizationTypes.sol";
import {AuthorizationErrors} from "./libraries/AuthorizationErrors.sol";

/**
 * @title AgentAuthorizationBase
 * @notice Reference implementation of ERC-XXXX Agent Authorization Interface
 * @dev Provides secure, time-bound, and usage-limited delegation of on-chain actions
 *      to autonomous agents.
 *
 * Key Features:
 * - EIP-712 typed data signatures for agent consent
 * - EIP-1271 support for smart contract agents
 * - Single-principal constraint per agent
 * - Time-bound authorizations with optional start/end times
 * - Usage-limited authorizations with call counting
 * - Auto-revoke when usage limit is exhausted
 *
 * Inheriting contracts should:
 * 1. Call the constructor with contract name and version
 * 2. Use `onlyAuthorizedAgent` modifier on protected functions
 * 3. Use `_resolvePrincipal` to get the delegating principal
 *
 * @custom:security-contact security@world3.ai
 */
abstract contract AgentAuthorizationBase is IERC8118AgentAuthorizationBase, EIP712, ERC165 {
    using AuthorizationTypes for AuthorizationTypes.AuthorizationData;

    // ============ Constants ============

    /**
     * @notice EIP-712 typehash for agent consent signatures
     * @dev keccak256("AgentConsent(address principal,address agent,bytes4 selector,uint256 startTime,uint256 endTime,uint256 allowedCalls,uint256 nonce,uint256 deadline)")
     */
    bytes32 public constant AGENT_CONSENT_TYPEHASH =
        keccak256(
            "AgentConsent(address principal,address agent,bytes4 selector,uint256 startTime,uint256 endTime,uint256 allowedCalls,uint256 nonce,uint256 deadline)"
        );

    // ============ Storage ============

    /**
     * @notice Authorization data: principal => agent => selector => AuthorizationData
     * @dev Uses nested mappings for O(1) lookup and gas-efficient storage
     */
    mapping(address principal => mapping(address agent => mapping(bytes4 selector => AuthorizationTypes.AuthorizationData)))
        internal _authorizations;

    /**
     * @notice Agent to principal binding: agent => principal
     * @dev Enforces single-principal constraint. address(0) means unbound.
     */
    mapping(address agent => address principal) internal _agentToPrincipal;

    /**
     * @notice Nonces for signature replay protection: agent => nonce
     * @dev Incremented after each successful authorization
     */
    mapping(address agent => uint256 nonce) internal _nonces;

    /**
     * @notice Count of active authorizations per agent: agent => count
     * @dev Used to determine when to unbind agent from principal
     */
    mapping(address agent => uint256 count) internal _authorizationCount;

    /**
     * @notice Temporary storage for the principal during function execution
     * @dev Set by onlyAuthorizedAgent modifier before consuming authorization.
     *      This allows _resolvePrincipal to work even after auto-revoke unbinds the agent.
     *      Reset to address(0) after each call.
     */
    address private _currentPrincipal;

    // ============ Constructor ============

    /**
     * @notice Initialize the contract with EIP-712 domain parameters
     * @param name_ The contract name for EIP-712 domain
     * @param version_ The contract version for EIP-712 domain
     */
    constructor(string memory name_, string memory version_) EIP712(name_, version_) {}

    // ============ Modifiers ============

    /**
     * @notice Restrict function access to authorized agents only
     * @dev Validates authorization, time bounds, and decrements usage counter.
     *      Auto-revokes when usage limit is exhausted.
     *
     *      PRINCIPAL CONTEXT PRESERVATION:
     *      The _currentPrincipal variable ensures that _resolvePrincipal works correctly
     *      even after auto-revoke unbinds the agent mid-execution. This handles:
     *      1. Multiple _resolvePrincipal calls within a single protected function
     *      2. External callbacks that return to the same function
     *      3. Auto-revoke occurring before _resolvePrincipal is called
     *
     *      NOTE: True nested protected calls (funcA calls this.funcB) are NOT supported
     *      because this.funcB() changes msg.sender to the contract address.
     *
     * @param selector The function selector being protected
     */
    modifier onlyAuthorizedAgent(bytes4 selector) {
        // Get principal from binding, or fall back to stored context
        address principal = _agentToPrincipal[msg.sender];
        if (principal == address(0)) {
            // Agent may be unbound due to auto-revoke - use stored context
            principal = _currentPrincipal;
        }
        if (principal == address(0)) {
            revert AuthorizationErrors.NotAuthorized();
        }

        // Save previous state for stack-based restoration
        address previousPrincipal = _currentPrincipal;
        _currentPrincipal = principal;

        _consumeAuthorization(msg.sender, selector);
        _;

        // Restore previous state (ensures callback isolation)
        _currentPrincipal = previousPrincipal;
    }

    // ============ External Write Functions ============

    /// @inheritdoc IERC8118AgentAuthorizationBase
    function authorizeAgent(
        address agent,
        bytes4 selector,
        uint256 startTime,
        uint256 endTime,
        uint256 allowedCalls,
        uint256 deadline,
        bytes calldata signature
    ) external {
        _authorizeAgent(msg.sender, agent, selector, startTime, endTime, allowedCalls, deadline, signature);
    }

    /// @inheritdoc IERC8118AgentAuthorizationBase
    function batchAuthorizeAgent(BatchAuthorization[] calldata batch) external {
        uint256 length = batch.length;
        for (uint256 i = 0; i < length;) {
            BatchAuthorization calldata auth = batch[i];
            _authorizeAgent(
                msg.sender,
                auth.agent,
                auth.selector,
                auth.startTime,
                auth.endTime,
                auth.allowedCalls,
                auth.deadline,
                auth.signature
            );
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IERC8118AgentAuthorizationBase
    function revokeAgent(address agent, bytes4 selector) external {
        _removeAuthorization(msg.sender, agent, selector);
    }

    /// @inheritdoc IERC8118AgentAuthorizationBase
    function batchRevokeAgent(address agent, bytes4[] calldata selectors) external {
        uint256 length = selectors.length;
        for (uint256 i = 0; i < length;) {
            _removeAuthorization(msg.sender, agent, selectors[i]);
            unchecked {
                ++i;
            }
        }
    }

    // ============ External View Functions ============

    /// @inheritdoc IERC8118AgentAuthorizationBase
    function isAuthorizedAgent(address principal, address agent, bytes4 selector) external view returns (bool) {
        return _authorizations[principal][agent][selector].isValid();
    }

    /// @inheritdoc IERC8118AgentAuthorizationBase
    function getAgentAuthorization(
        address principal,
        address agent,
        bytes4 selector
    ) external view returns (uint256 startTime, uint256 endTime, uint256 remainingCalls) {
        AuthorizationTypes.AuthorizationData storage data = _authorizations[principal][agent][selector];
        return (data.startTime, data.endTime, data.allowedCalls);
    }

    /// @inheritdoc IERC8118AgentAuthorizationBase
    function principalOf(address agent) external view returns (address) {
        return _agentToPrincipal[agent];
    }

    /// @inheritdoc IERC8118AgentAuthorizationBase
    function nonces(address agent) external view returns (uint256) {
        return _nonces[agent];
    }

    /// @inheritdoc IERC8118AgentAuthorizationBase
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // ============ ERC-165 Support ============

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC8118AgentAuthorizationBase).interfaceId || super.supportsInterface(interfaceId);
    }

    // ============ Internal Functions ============

    /**
     * @notice Core authorization logic
     * @param principal The principal delegating authority
     * @param agent The agent receiving authorization
     * @param selector The function selector to authorize
     * @param startTime The start timestamp (0 = immediate)
     * @param endTime The end timestamp (0 = no expiry)
     * @param allowedCalls The number of calls allowed
     * @param deadline The signature deadline
     * @param signature The agent's consent signature
     */
    function _authorizeAgent(
        address principal,
        address agent,
        bytes4 selector,
        uint256 startTime,
        uint256 endTime,
        uint256 allowedCalls,
        uint256 deadline,
        bytes calldata signature
    ) internal {
        // Input validation
        if (agent == address(0)) revert AuthorizationErrors.InvalidAgentAddress();
        if (selector == bytes4(0)) revert AuthorizationErrors.InvalidSelector();
        if (allowedCalls == 0) revert AuthorizationErrors.ZeroCallsNotAllowed();
        if (block.timestamp > deadline) revert AuthorizationErrors.SignatureExpired();

        // Single-principal constraint check
        address boundPrincipal = _agentToPrincipal[agent];
        if (boundPrincipal != address(0) && boundPrincipal != principal) {
            revert AuthorizationErrors.AgentAlreadyBound();
        }

        // Verify agent consent signature
        _verifyAgentConsent(principal, agent, selector, startTime, endTime, allowedCalls, deadline, signature);

        // Increment nonce after successful signature verification
        unchecked {
            ++_nonces[agent];
        }

        // Bounds checks to prevent silent truncation
        if (startTime > type(uint48).max || endTime > type(uint48).max) {
            revert AuthorizationErrors.ValueExceedsBounds();
        }
        if (allowedCalls > type(uint64).max) {
            revert AuthorizationErrors.ValueExceedsBounds();
        }

        // Check if this is a new authorization (for count tracking)
        bool isNewAuth = !_authorizations[principal][agent][selector].exists();

        // Store authorization data
        AuthorizationTypes.AuthorizationData storage data = _authorizations[principal][agent][selector];
        data.startTime = uint48(startTime);
        data.endTime = uint48(endTime);
        data.allowedCalls = uint64(allowedCalls);

        // Bind agent to principal if not already bound
        if (boundPrincipal == address(0)) {
            _agentToPrincipal[agent] = principal;
        }

        // Increment authorization count for new authorizations
        if (isNewAuth) {
            unchecked {
                ++_authorizationCount[agent];
            }
        }

        emit AgentAuthorized(principal, agent, selector, startTime, endTime, allowedCalls);
    }

    /**
     * @notice Verify agent consent signature (EIP-712 + EIP-1271)
     * @dev Uses current nonce from storage for replay protection
     * @param principal The principal address
     * @param agent The agent address
     * @param selector The function selector
     * @param startTime The start timestamp
     * @param endTime The end timestamp
     * @param allowedCalls The allowed calls count
     * @param deadline The signature deadline
     * @param signature The signature to verify
     */
    function _verifyAgentConsent(
        address principal,
        address agent,
        bytes4 selector,
        uint256 startTime,
        uint256 endTime,
        uint256 allowedCalls,
        uint256 deadline,
        bytes calldata signature
    ) internal view {
        bytes32 structHash = _computeConsentHash(principal, agent, selector, startTime, endTime, allowedCalls, deadline);
        bytes32 hash = _hashTypedDataV4(structHash);

        // Use SignatureChecker for both EOA (ECDSA) and contract (EIP-1271) support
        if (!SignatureChecker.isValidSignatureNow(agent, hash, signature)) {
            revert AuthorizationErrors.InvalidSignature();
        }
    }

    /**
     * @notice Compute the EIP-712 struct hash for agent consent
     * @dev Separated to avoid stack depth issues
     */
    function _computeConsentHash(
        address principal,
        address agent,
        bytes4 selector,
        uint256 startTime,
        uint256 endTime,
        uint256 allowedCalls,
        uint256 deadline
    ) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                AGENT_CONSENT_TYPEHASH,
                principal,
                agent,
                selector,
                startTime,
                endTime,
                allowedCalls,
                _nonces[agent],
                deadline
            )
        );
    }

    /**
     * @notice Remove an authorization and handle agent unbinding
     * @param principal The principal revoking the authorization
     * @param agent The agent being revoked
     * @param selector The function selector being revoked
     */
    function _removeAuthorization(address principal, address agent, bytes4 selector) internal {
        AuthorizationTypes.AuthorizationData storage data = _authorizations[principal][agent][selector];

        if (!data.exists()) {
            revert AuthorizationErrors.NoAuthorizationExists();
        }

        // Clear the authorization
        data.clear();

        // Decrement authorization count and unbind if zero
        unchecked {
            --_authorizationCount[agent];
        }

        if (_authorizationCount[agent] == 0) {
            delete _agentToPrincipal[agent];
        }

        emit AgentRevoked(principal, agent, selector);
    }

    /**
     * @notice Consume one authorization call and handle auto-revoke
     * @param agent The agent calling the function
     * @param selector The function selector being called
     */
    function _consumeAuthorization(address agent, bytes4 selector) internal {
        address principal = _agentToPrincipal[agent];
        if (principal == address(0)) {
            revert AuthorizationErrors.NotAuthorized();
        }

        AuthorizationTypes.AuthorizationData storage data = _authorizations[principal][agent][selector];

        if (!data.isValid()) {
            revert AuthorizationErrors.NotAuthorized();
        }

        // Decrement allowed calls
        unchecked {
            --data.allowedCalls;
        }

        // Auto-revoke if no calls remaining
        if (data.allowedCalls == 0) {
            // Clear remaining fields (allowedCalls is already 0)
            data.startTime = 0;
            data.endTime = 0;

            // Decrement authorization count and unbind if this was the last authorization
            unchecked {
                --_authorizationCount[agent];
            }

            if (_authorizationCount[agent] == 0) {
                delete _agentToPrincipal[agent];
            }

            emit AgentRevoked(principal, agent, selector);
        }
    }

    /**
     * @notice Resolve the principal for the current agent caller
     * @dev Use this in protected functions to identify on whose behalf the agent acts.
     *      Uses _currentPrincipal if set (during onlyAuthorizedAgent execution),
     *      otherwise falls back to _agentToPrincipal mapping.
     * @param agent The agent address (typically msg.sender)
     * @return The principal address
     */
    function _resolvePrincipal(address agent) internal view returns (address) {
        // Use stored principal if available (handles auto-revoke case)
        if (_currentPrincipal != address(0)) {
            return _currentPrincipal;
        }

        address principal = _agentToPrincipal[agent];
        if (principal == address(0)) {
            revert AuthorizationErrors.NotAuthorized();
        }
        return principal;
    }
}
