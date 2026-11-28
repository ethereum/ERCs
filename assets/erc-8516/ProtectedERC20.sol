// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin-contracts-5/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin-contracts-5/token/ERC20/extensions/ERC20Permit.sol";
import {ERC165} from "@openzeppelin-contracts-5/utils/introspection/ERC165.sol";
import {SignatureChecker} from "@openzeppelin-contracts-5/utils/cryptography/SignatureChecker.sol";
import {IERCProtectedReceive} from "./interfaces/IERCProtectedReceive.sol";
import {IERCProtectedReceiveCore} from "./interfaces/IERCProtectedReceiveCore.sol";
import {IERCProtectedReceiveOptIn} from "./interfaces/IERCProtectedReceiveOptIn.sol";
import {IERCProtectedReceiveLevel} from "./interfaces/IERCProtectedReceiveLevel.sol";
import {IERCProtectedReceiveSig} from "./interfaces/IERCProtectedReceiveSig.sol";
import {IERCProtectedReceiveAllowlist} from "./interfaces/IERCProtectedReceiveAllowlist.sol";
import {IERCProtectedReceiveDenylist} from "./interfaces/IERCProtectedReceiveDenylist.sol";
import {IERCProtectedReceivePermit} from "./interfaces/IERCProtectedReceivePermit.sol";
import {IERCProtectedReceivePolicy} from "./interfaces/IERCProtectedReceivePolicy.sol";
import {IReceivePolicy} from "./interfaces/IReceivePolicy.sol";

/**
 * @title ProtectedERC20
 * @notice Proof-of-concept reference ERC-20 implementation demonstrating opt-in, recipient-gated
 *         incoming transfer protection.
 * @dev Combines a per-token persistent allowlist, optional external `IReceivePolicy` delegation,
 *      EIP-712 one-time receive permits (`permitReceive`), and atomic dual-permit helpers.
 *      Note: This is an illustrative example to demonstrate the ERC options and is not gas-optimized
 *      or audited for production deployment.
 */
abstract contract ProtectedERC20 is ERC20, ERC20Permit, ERC165, IERCProtectedReceive {
    /**
     * @notice Reverted when a zero address is passed where a non-zero account is required.
     * @dev Used by `setReceiveProtectionWithSig` and `permitReceive`.
     */
    error ZeroAddress();

    /**
     * @notice EIP-2612 spend permit parameters for `transferFromWithPermits`.
     * @dev Bundled into a struct to keep stack depth shallow without requiring `via-ir`.
     */
    struct SpendPermit {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /**
     * @notice EIP-712 receive permit parameters for `transferFromWithPermits`.
     * @dev Bundled into a struct to keep stack depth shallow without requiring `via-ir`.
     */
    struct ReceivePermit {
        uint256 maxAmount;
        uint256 nonce;
        uint256 deadline;
        bytes signature;
    }
    /**
     * @notice Default `bytes32` protection level set when enabling via `setReceiveProtection(true)`.
     * @dev Non-zero sentinel representing standard receive gating.
     */
    bytes32 public constant DEFAULT_PROTECTION_LEVEL = bytes32(uint256(1));

    /**
     * @notice Protection level enabling denylist-only (default-allow) mode.
     * @dev When active, transfers are allowed unless the sender is actively denylisted.
     */
    bytes32 public constant DENYLIST_PROTECTION_LEVEL = bytes32(uint256(2));

    /**
     * @notice EIP-712 typehash for `permitReceive`.
     * @dev Binds `from`, `to`, `maxAmount`, `nonce`, and `deadline`.
     */
    bytes32 public constant RECEIVE_PERMIT_TYPEHASH =
        keccak256("PermitReceive(address from,address to,uint256 maxAmount,uint256 nonce,uint256 deadline)");

    /**
     * @notice EIP-712 typehash for `setReceiveProtectionWithSig`.
     * @dev Binds `account`, `protectionLevel`, `nonce`, and `deadline` using `receiveProtectionSetupNonces`.
     */
    bytes32 public constant SET_PROTECTION_TYPEHASH =
        keccak256("SetReceiveProtection(address account,bytes32 protectionLevel,uint256 nonce,uint256 deadline)");

    mapping(address account => bytes32) private _protectionLevels;
    mapping(address account => mapping(address sender => uint40)) private _receiveSenderAllowlistedUntil;
    mapping(address account => mapping(address sender => uint40)) private _receiveSenderDenylistedUntil;
    mapping(address account => address) private _policies;
    mapping(address recipient => mapping(address sender => uint256)) private _oneTimeReceiveLimits;
    mapping(address account => mapping(uint248 wordPos => uint256)) private _receiveNonceBitmap;
    mapping(address account => uint256) private _protectionSetupNonces;

    /**
     * @notice Initializes the ERC-20 token and EIP-712 domain via `ERC20Permit`.
     * @dev Sets `name_` and `symbol_` for both `ERC20` and `EIP712`.
     * @param name_ Token name.
     * @param symbol_ Token symbol.
     */
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) ERC20Permit(name_) {}

    /**
     * @inheritdoc ERC165
     * @dev Declares support for `IERCProtectedReceiveCore`, `IERCProtectedReceiveOptIn`,
     *      `IERCProtectedReceiveLevel`, `IERCProtectedReceiveSig`, `IERCProtectedReceiveAllowlist`,
     *      `IERCProtectedReceiveDenylist`, `IERCProtectedReceivePermit`, `IERCProtectedReceivePolicy`,
     *      and `IERC165`.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERCProtectedReceiveCore).interfaceId
            || interfaceId == type(IERCProtectedReceiveOptIn).interfaceId
            || interfaceId == type(IERCProtectedReceiveLevel).interfaceId
            || interfaceId == type(IERCProtectedReceiveSig).interfaceId
            || interfaceId == type(IERCProtectedReceiveAllowlist).interfaceId
            || interfaceId == type(IERCProtectedReceiveDenylist).interfaceId
            || interfaceId == type(IERCProtectedReceivePermit).interfaceId
            || interfaceId == type(IERCProtectedReceivePolicy).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @inheritdoc IERCProtectedReceiveCore
     */
    function isReceiveProtected(address account) public view virtual override returns (bool) {
        return _protectionLevels[account] != bytes32(0);
    }

    /**
     * @inheritdoc IERCProtectedReceiveLevel
     */
    function receiveProtectionLevel(address account) public view virtual override returns (bytes32) {
        return _protectionLevels[account];
    }

    /**
     * @inheritdoc IERCProtectedReceiveAllowlist
     */
    function receiveSenderAllowlistedUntil(address from, address to) public view virtual override returns (uint40) {
        return _receiveSenderAllowlistedUntil[to][from];
    }

    /**
     * @inheritdoc IERCProtectedReceiveDenylist
     */
    function receiveSenderDenylistedUntil(address from, address to) public view virtual override returns (uint40) {
        return _receiveSenderDenylistedUntil[to][from];
    }

    /**
     * @inheritdoc IERCProtectedReceivePolicy
     */
    function receivePolicy(address account) public view virtual override returns (address) {
        return _policies[account];
    }

    /**
     * @inheritdoc IERCProtectedReceivePermit
     */
    function oneTimeReceiveLimit(address from, address to) public view virtual override returns (uint256) {
        return _oneTimeReceiveLimits[to][from];
    }

    /**
     * @inheritdoc IERCProtectedReceivePermit
     */
    function isReceiveNonceUsed(address account, uint256 nonce) public view virtual override returns (bool) {
        return (_receiveNonceBitmap[account][uint248(nonce >> 8)] & (1 << uint8(nonce))) != 0;
    }

    /**
     * @notice Returns the sequential EIP-712 nonce for `setReceiveProtectionWithSig` for `account`.
     * @dev Incremented on each valid `setReceiveProtectionWithSig` call.
     * @param account The account to query.
     * @return The next expected protection-setup nonce.
     */
    function receiveProtectionSetupNonces(address account) public view virtual returns (uint256) {
        return _protectionSetupNonces[account];
    }

    /**
     * @inheritdoc IERCProtectedReceiveCore
     */
    function canReceive(address from, address to, uint256 amount) public view virtual override returns (bool) {
        bytes32 level = _protectionLevels[to];
        if (to == address(0) || from == to || level == bytes32(0)) {
            return true;
        }
        if (_receiveSenderDenylistedUntil[to][from] > block.timestamp) {
            return false;
        }
        if (level == DENYLIST_PROTECTION_LEVEL) {
            return true;
        }
        uint256 oneTimeLimit = _oneTimeReceiveLimits[to][from];
        if (oneTimeLimit > 0 && amount <= oneTimeLimit) {
            return true;
        }
        if (_receiveSenderAllowlistedUntil[to][from] > block.timestamp) {
            return true;
        }
        address policy = _policies[to];
        if (policy != address(0)) {
            return _checkPolicy(policy, from, to, amount);
        }
        return false;
    }

    /**
     * @inheritdoc IERCProtectedReceiveOptIn
     */
    function setReceiveProtection(bool enabled) external virtual override {
        _setReceiveProtectionLevel(msg.sender, enabled ? DEFAULT_PROTECTION_LEVEL : bytes32(0));
    }

    /**
     * @inheritdoc IERCProtectedReceiveLevel
     */
    function setReceiveProtection(bytes32 protectionLevel) external virtual override {
        _setReceiveProtectionLevel(msg.sender, protectionLevel);
    }

    /**
     * @inheritdoc IERCProtectedReceiveSig
     */
    function setReceiveProtectionWithSig(
        address account,
        bytes32 protectionLevel,
        uint256 deadline,
        bytes calldata signature
    ) external virtual override {
        if (account == address(0)) revert ZeroAddress();
        if (block.timestamp > deadline) revert ExpiredReceiveProtectionSetupSignature(deadline);

        uint256 nonce = _protectionSetupNonces[account];
        bytes32 structHash = keccak256(abi.encode(SET_PROTECTION_TYPEHASH, account, protectionLevel, nonce, deadline));
        bytes32 digest = _hashTypedDataV4(structHash);

        if (!SignatureChecker.isValidSignatureNow(account, digest, signature)) {
            revert InvalidReceiveProtectionSetupSignature(account);
        }

        unchecked {
            _protectionSetupNonces[account] = nonce + 1;
        }
        _setReceiveProtectionLevel(account, protectionLevel);
    }

    /**
     * @notice Sets a `uint40` expiration timestamp for `sender` on `msg.sender`'s embedded allowlist.
     * @dev Reference helper (`0` revokes, `type(uint40).max` grants permanent access). Emits {ReceiveSenderAllowlistUpdated}.
     * @param sender The sender address to update (`address(0)` for mints).
     * @param expiry Unix timestamp until which `sender` is allowed (`expiry > block.timestamp`).
     */
    function setReceiveAllowed(address sender, uint40 expiry) external virtual {
        _receiveSenderAllowlistedUntil[msg.sender][sender] = expiry;
        emit ReceiveSenderAllowlistUpdated(sender, msg.sender, expiry);
    }

    /**
     * @notice Batch-updates `uint40` expiration timestamps for multiple senders on `msg.sender`'s
     *         embedded allowlist.
     * @dev Reference helper emitting {ReceiveSenderAllowlistUpdated} for each element in `senders`.
     * @param senders Array of sender addresses to update.
     * @param expiry Unix timestamp until which all listed senders are allowed.
     */
    function setReceiveAllowedBatch(address[] calldata senders, uint40 expiry) external virtual {
        uint256 length = senders.length;
        for (uint256 i = 0; i < length; ++i) {
            address sender = senders[i];
            _receiveSenderAllowlistedUntil[msg.sender][sender] = expiry;
            emit ReceiveSenderAllowlistUpdated(sender, msg.sender, expiry);
        }
    }

    /**
     * @notice Sets a `uint40` expiration timestamp for `sender` on `msg.sender`'s embedded denylist.
     * @dev Reference helper (`0` unblocks, `type(uint40).max` blocks permanently). Emits {ReceiveSenderDenylistUpdated}.
     * @param sender The sender address to update (`address(0)` for mints).
     * @param expiry Unix timestamp until which `sender` is denylisted (`expiry > block.timestamp`).
     */
    function setReceiveDenied(address sender, uint40 expiry) external virtual {
        _receiveSenderDenylistedUntil[msg.sender][sender] = expiry;
        emit ReceiveSenderDenylistUpdated(sender, msg.sender, expiry);
    }

    /**
     * @notice Batch-updates `uint40` expiration timestamps for multiple senders on `msg.sender`'s
     *         embedded denylist.
     * @dev Reference helper emitting {ReceiveSenderDenylistUpdated} for each element in `senders`.
     * @param senders Array of sender addresses to update.
     * @param expiry Unix timestamp until which all listed senders are denylisted.
     */
    function setReceiveDeniedBatch(address[] calldata senders, uint40 expiry) external virtual {
        uint256 length = senders.length;
        for (uint256 i = 0; i < length; ++i) {
            address sender = senders[i];
            _receiveSenderDenylistedUntil[msg.sender][sender] = expiry;
            emit ReceiveSenderDenylistUpdated(sender, msg.sender, expiry);
        }
    }

    /**
     * @inheritdoc IERCProtectedReceivePolicy
     */
    function setReceivePolicy(address policy) external virtual override {
        _policies[msg.sender] = policy;
        emit ReceivePolicyUpdated(msg.sender, policy);
    }

    /**
     * @inheritdoc IERCProtectedReceivePermit
     */
    function permitReceive(
        address from,
        address to,
        uint256 maxAmount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) public virtual override {
        if (to == address(0)) revert ZeroAddress();
        if (block.timestamp > deadline) revert ExpiredReceivePermit(deadline);

        uint248 wordPos = uint248(nonce >> 8);
        uint256 bit = 1 << uint8(nonce);
        if ((_receiveNonceBitmap[to][wordPos] & bit) != 0) {
            revert InvalidReceiveNonce(to, nonce);
        }

        bytes32 structHash = keccak256(abi.encode(RECEIVE_PERMIT_TYPEHASH, from, to, maxAmount, nonce, deadline));
        bytes32 digest = _hashTypedDataV4(structHash);

        if (!SignatureChecker.isValidSignatureNow(to, digest, signature)) {
            revert InvalidReceivePermitSignature(to);
        }

        _receiveNonceBitmap[to][wordPos] |= bit;
        _oneTimeReceiveLimits[to][from] = maxAmount;

        emit OneTimeReceivePermitted(from, to, nonce, maxAmount, deadline);
    }

    /**
     * @notice Atomically registers a recipient's one-time receive permit and transfers `amount` from `msg.sender`.
     * @dev Convenience helper combining `permitReceive` and `ERC20.transfer` in a single transaction.
     * @param to The protected recipient address.
     * @param amount The token amount to transfer.
     * @param maxAmount The maximum amount signed in the receive permit.
     * @param nonce The unordered bitmap nonce signed in the receive permit.
     * @param deadline The expiration timestamp of the receive permit.
     * @param receiveSignature The recipient's EIP-712 signature.
     * @return True if the transfer succeeded.
     */
    function transferWithReceivePermit(
        address to,
        uint256 amount,
        uint256 maxAmount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata receiveSignature
    ) external virtual returns (bool) {
        permitReceive(msg.sender, to, maxAmount, nonce, deadline, receiveSignature);
        return transfer(to, amount);
    }

    /**
     * @notice Atomically executes an EIP-2612 spend `permit`, a `permitReceive`, and `transferFrom`.
     * @dev Allows a relayer to settle a transfer between a sender and a protected recipient in one transaction.
     * @param from The token owner signing the EIP-2612 spend permit.
     * @param to The protected recipient signing the receive permit.
     * @param amount The token amount to transfer (also used as the EIP-2612 spend allowance).
     * @param spendPermit The EIP-2612 spend permit signed by `from`.
     * @param receivePermit The EIP-712 receive permit signed by `to`.
     * @return True if the transfer succeeded.
     */
    function transferFromWithPermits(
        address from,
        address to,
        uint256 amount,
        SpendPermit calldata spendPermit,
        ReceivePermit calldata receivePermit
    ) external virtual returns (bool) {
        permit(from, msg.sender, amount, spendPermit.deadline, spendPermit.v, spendPermit.r, spendPermit.s);
        permitReceive(
            from, to, receivePermit.maxAmount, receivePermit.nonce, receivePermit.deadline, receivePermit.signature
        );
        return transferFrom(from, to, amount);
    }

    /**
     * @notice Enforces recipient protection on mints and transfers before updating balances.
     * @dev Skips checks for burns (`to == address(0)`), self-transfers (`from == to`), and unprotected recipients.
     * @param from The economic sender (`address(0)` for mints).
     * @param to The recipient (`address(0)` for burns).
     * @param value The token amount being moved.
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        if (to != address(0) && from != to && _protectionLevels[to] != bytes32(0)) {
            _enforceAndConsumeReceivePermission(from, to, value);
        }
        super._update(from, to, value);
    }

    /**
     * @notice Updates `account`'s protection level and emits transition events.
     * @dev Always emits {ReceiveProtectionLevelUpdated} on change; emits {ReceiveProtectionUpdated}
     *      only when transitioning between protected (`!= 0`) and unprotected (`== 0`).
     * @param account The account whose protection level is being updated.
     * @param newLevel The new `bytes32` protection level.
     */
    function _setReceiveProtectionLevel(address account, bytes32 newLevel) internal virtual {
        bytes32 oldLevel = _protectionLevels[account];
        if (oldLevel == newLevel) return;

        _protectionLevels[account] = newLevel;
        emit ReceiveProtectionLevelUpdated(account, newLevel);

        bool wasProtected = oldLevel != bytes32(0);
        bool nowProtected = newLevel != bytes32(0);
        if (wasProtected != nowProtected) {
            emit ReceiveProtectionUpdated(account, nowProtected);
        }
    }

    /**
     * @notice Verifies incoming transfer authorization for a protected `to` and consumes one-time permits.
     * @dev Precedence: (0) embedded denylist hard veto, (0b) `DENYLIST_PROTECTION_LEVEL` default-allow,
     *      (1) embedded one-time permit, (2) embedded persistent allowlist, (3) external policy.
     *      Reverts with {RecipientTransferNotAllowed} if denied or unauthorized.
     * @param from The economic sender (`address(0)` for mints).
     * @param to The protected recipient.
     * @param amount The token amount being transferred.
     */
    function _enforceAndConsumeReceivePermission(address from, address to, uint256 amount) internal virtual {
        if (_receiveSenderDenylistedUntil[to][from] > block.timestamp) {
            revert RecipientTransferNotAllowed(from, to, amount);
        }
        if (_protectionLevels[to] == DENYLIST_PROTECTION_LEVEL) {
            return;
        }
        uint256 oneTimeLimit = _oneTimeReceiveLimits[to][from];
        if (oneTimeLimit > 0 && amount <= oneTimeLimit) {
            _oneTimeReceiveLimits[to][from] = 0;
            return;
        }
        if (_receiveSenderAllowlistedUntil[to][from] > block.timestamp) {
            return;
        }
        address policy = _policies[to];
        if (policy != address(0) && _checkPolicy(policy, from, to, amount)) {
            return;
        }
        revert RecipientTransferNotAllowed(from, to, amount);
    }

    /**
     * @notice Safely queries an external `IReceivePolicy` contract in fail-closed mode.
     * @dev Catches reverts from untrusted or buggy policy contracts and returns `false`.
     * @param policy The `IReceivePolicy` contract address.
     * @param from The economic sender.
     * @param to The protected recipient.
     * @param amount The transfer amount.
     * @return True only if the policy call succeeds and returns `true`.
     */
    function _checkPolicy(address policy, address from, address to, uint256 amount)
        internal
        view
        virtual
        returns (bool)
    {
        try IReceivePolicy(policy).canReceive(address(this), from, to, amount, _policyData(from, to, amount)) returns (
            bool allowed
        ) {
            return allowed;
        } catch {
            return false;
        }
    }

    /**
     * @notice Returns optional context bytes forwarded to `IReceivePolicy.canReceive`.
     * @dev Returns empty bytes by default; subclasses may override to pass `msg.sender`,
     *      allowance, token-specific flags, or sender/recipient account context (e.g., tiers
     *      or compliance attributes).
     * @param from The economic sender.
     * @param to The protected recipient.
     * @param amount The transfer amount.
     * @return Arbitrary ABI-encoded context bytes for the policy.
     */
    function _policyData(address from, address to, uint256 amount) internal view virtual returns (bytes memory) {
        (from, to, amount);
        return "";
    }
}
