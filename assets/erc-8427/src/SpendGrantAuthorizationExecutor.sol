// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {ISpendGrantRegistry, NATIVE, SpendGrant} from "./SpendGrantTypes.sol";
import {SpendGrantHash} from "./SpendGrantHash.sol";
import {SpendGrantSignature} from "./SpendGrantSignature.sol";
import {SpendGrantExecutor} from "./SpendGrantExecutor.sol";

/// @notice An executor that also accepts delegate-signed authorizations that anyone may submit.
/// @dev The delegate signs an EIP-712 `SpendAuthorization` naming the grant hash, asset, amount,
/// recipient, a nonce, and a deadline, with this executor as `verifyingContract`. A relayer submits it
/// with the grant. The executor computes the grant hash itself under the registry it trusts, never from
/// the submitter, validates the signature under the Signatures rules applied to the delegate and the
/// authorization digest, records the nonce under the authenticated signer before `consume` and before
/// moving funds, and lets the delegate cancel an unused nonce. The direct-call `spend` is inherited.
contract SpendGrantAuthorizationExecutor is SpendGrantExecutor {
    error AuthorizationExpired();
    error NonceAlreadyUsed();
    error BadAuthorization();

    event AuthorizationUsed(address indexed authorizer, uint256 indexed nonce);
    event NonceCancelled(address indexed authorizer, uint256 indexed nonce);

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant NAME_HASH = keccak256("SpendGrantAuthorizationExecutor");
    bytes32 internal constant VERSION_HASH = keccak256("1");
    bytes32 internal constant AUTHORIZATION_TYPEHASH = keccak256(
        "SpendAuthorization(bytes32 grantHash,address asset,uint256 amount,address recipient,uint256 nonce,uint256 deadline)"
    );

    /// @notice Nonces consumed or cancelled, in the namespace of the authenticated signer.
    mapping(address authorizer => mapping(uint256 nonce => bool)) public nonceUsed;

    constructor(ISpendGrantRegistry registry_) SpendGrantExecutor(registry_) {}

    function domainSeparator() public view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, NAME_HASH, VERSION_HASH, block.chainid, address(this)));
    }

    /// @notice The digest the delegate signs for one spend.
    function authorizationDigest(
        bytes32 grantHash,
        address asset,
        uint256 amount,
        address recipient,
        uint256 nonce,
        uint256 deadline
    ) public view returns (bytes32) {
        bytes32 structHash =
            keccak256(abi.encode(AUTHORIZATION_TYPEHASH, grantHash, asset, amount, recipient, nonce, deadline));
        return keccak256(abi.encodePacked(hex"1901", domainSeparator(), structHash));
    }

    /// @notice Spends under `grant` on the strength of the delegate's signed authorization. Anyone may call.
    /// @param deadline Unix seconds; the authorization is rejected at or after it.
    /// @param authorization The delegate's signature over `authorizationDigest(...)`.
    function spendWithAuthorization(
        SpendGrant calldata grant,
        bytes calldata grantSignature,
        address asset,
        uint256 amount,
        address recipient,
        uint256 nonce,
        uint256 deadline,
        bytes calldata authorization
    ) external {
        if (asset == NATIVE) revert NativeRequiresAccountAdapter();
        if (block.timestamp >= deadline) revert AuthorizationExpired();
        // A submitter that lost the race learns it here, before paying for the delegate's ERC-1271 call.
        // Only the delegate's nonces can ever succeed, so this is the check that matters.
        if (nonceUsed[grant.delegate][nonce]) revert NonceAlreadyUsed();

        // The grant hash is computed here, under the trusted registry, so the signed message binds this
        // grant and not whatever the submitter claims.
        bytes32 grantHash = SpendGrantHash.digest(block.chainid, address(REGISTRY), grant);
        bytes32 digest = authorizationDigest(grantHash, asset, amount, recipient, nonce, deadline);
        address authorizer = _authenticate(grant.delegate, digest, authorization);

        // Recorded before consume and before movement: either can call out and reenter.
        if (nonceUsed[authorizer][nonce]) revert NonceAlreadyUsed();
        nonceUsed[authorizer][nonce] = true;
        emit AuthorizationUsed(authorizer, nonce);

        REGISTRY.consume(grant, grantSignature, authorizer, asset, amount, recipient);
        _move(asset, grant.principal, recipient, amount);
    }

    /// @notice Invalidates one of the caller's unused nonces, so an authorization it signed can no longer
    /// succeed. A nonce that already executed or was already cancelled is rejected, so a successful call
    /// proves that the authorization did not run and never will.
    function cancelNonce(uint256 nonce) external {
        if (nonceUsed[msg.sender][nonce]) revert NonceAlreadyUsed();
        nonceUsed[msg.sender][nonce] = true;
        emit NonceCancelled(msg.sender, nonce);
    }

    /// @notice The EIP-712 type hash of `SpendAuthorization`, for conformance checks against the vectors.
    function authorizationTypehash() external pure returns (bytes32) {
        return AUTHORIZATION_TYPEHASH;
    }

    /// @dev The Signatures rules applied to `delegate` and the authorization digest, through the same
    /// library function the registry uses for the principal. With no code the recovered signer is the
    /// authorizer, whoever it is; the registry then compares it with the grant's delegate. With code, the
    /// delegate is the authorizer only if its own key (EIP-7702) or its ERC-1271 accepts. Nothing
    /// authenticated is a revert, never a placeholder.
    function _authenticate(address delegate, bytes32 digest, bytes calldata sig) internal view returns (address) {
        address authorizer = SpendGrantSignature.authenticate(delegate, digest, sig);
        if (authorizer == address(0)) revert BadAuthorization();
        return authorizer;
    }
}
