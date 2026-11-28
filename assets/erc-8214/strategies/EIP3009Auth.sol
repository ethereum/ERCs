// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IPaymentAuth} from "../interfaces/IPaymentAuth.sol";

/**
 * @title IEIP3009 (minimal subset)
 * @dev Interface for tokens implementing EIP-3009 transferWithAuthorization.
 *      Primary implementation: USDC v2+, EURC.
 */
interface IEIP3009 {
    /**
     * @notice Execute a transfer with a signed authorization.
     * @dev receiveWithAuthorization enforces msg.sender == to, preventing
     *      front-running attacks where an attacker extracts the authorization
     *      from the mempool and redirects the transfer.
     *      Use this function (not transferWithAuthorization) when calling
     *      from a smart contract.
     */
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        bytes calldata signature
    ) external;

    /**
     * @notice Returns the state of an authorization nonce.
     * @param authorizer  The authorizer's address.
     * @param nonce       The nonce to check.
     * @return True if the nonce has been used.
     */
    function authorizationState(
        address authorizer,
        bytes32 nonce
    ) external view returns (bool);
}

/**
 * @title EIP3009Auth
 * @notice IPaymentAuth strategy using EIP-3009 receiveWithAuthorization.
 *
 * @dev Uses receiveWithAuthorization (not transferWithAuthorization) to
 *      prevent front-running. The token transfer is atomic with the
 *      authorization submission — no allowance is created at any point.
 *
 *      Token support: USDC v2+, EURC, and other EIP-3009 tokens.
 *      Not compatible with USDT, WETH, or tokens lacking EIP-3009 support.
 *
 *      EIP-3009 remains in Draft status. Monitor for spec changes.
 *
 *      IMPORTANT: receiveWithAuthorization requires msg.sender == to at the
 *      token contract level. Since this contract calls the token directly,
 *      the `to` field in the signed authorization MUST equal this contract's
 *      address. The contract then forwards tokens to the actual recipient.
 *      This design preserves front-running protection while enabling the
 *      BNPL payment flow.
 *
 *      authData encoding: abi.encode(
 *          uint256 validAfter,    // timestamp after which auth is valid (0 = immediately)
 *          uint256 validBefore,   // timestamp before which auth is valid (use deadline)
 *          bytes32 nonce,         // random 32-byte nonce, unique per authorization
 *          bytes   signature      // EIP-712 sig over ReceiveWithAuthorization struct
 *      )
 *
 * ReceiveWithAuthorization EIP-712 type string:
 *   "ReceiveWithAuthorization(address from,address to,uint256 value,
 *    uint256 validAfter,uint256 validBefore,bytes32 nonce)"
 *
 * Domain separator uses the token's own domain (name, version, chainId,
 * verifyingContract = token address) — NOT this contract's domain.
 * The customer must sign using the token's EIP-712 domain.
 */
contract EIP3009Auth is IPaymentAuth, ReentrancyGuard {

    bytes4 public constant AUTH_TYPE_ID = bytes4(keccak256("EIP3009Auth"));

    // ============ IPaymentAuth ============

    function authType() external pure override returns (bytes4) {
        return AUTH_TYPE_ID;
    }

    /**
     * @notice Pull tokens using EIP-3009 receiveWithAuthorization.
     *
     * @dev The authorization must have `to` set to this contract's address
     *      (satisfies msg.sender == to). After receiving the tokens, this
     *      contract transfers them to the actual recipient.
     *
     *      authData MUST be abi.encode(
     *          uint256 validAfter,
     *          uint256 validBefore,
     *          bytes32 nonce,
     *          bytes   signature
     *      )
     *
     * @param payer      Address that signed the authorization (the `from` field).
     * @param recipient  Address receiving tokens (merchant). Tokens are forwarded here.
     * @param token      EIP-3009 token address (e.g. USDC).
     * @param amount     Exact transfer amount — must match the `value` in the authorization.
     * @param authData   ABI-encoded (validAfter, validBefore, nonce, signature).
     */
    function pullPayment(
        address payer,
        address recipient,
        address token,
        uint256 amount,
        bytes calldata authData
    ) external override nonReentrant returns (bool) {
        (
            uint256 validAfter,
            uint256 validBefore,
            bytes32 nonce,
            bytes memory signature
        ) = abi.decode(authData, (uint256, uint256, bytes32, bytes));

        // receiveWithAuthorization requires msg.sender == to.
        // The authorization's `to` field must be this contract's address.
        // We then forward the tokens to the actual recipient.
        IEIP3009(token).receiveWithAuthorization(
            payer,
            address(this),  // to = this contract (satisfies msg.sender == to)
            amount,
            validAfter,
            validBefore,
            nonce,
            signature
        );

        // Forward tokens to the actual recipient (merchant)
        // Using a low-level call to handle non-standard ERC20 returns
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                recipient,
                amount
            )
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "EIP3009Auth: transfer to recipient failed"
        );

        return true;
    }

    // ============ View Functions ============

    /**
     * @notice Check whether an authorization nonce has been consumed.
     * @dev Delegates to the token contract's authorizationState.
     *      Use this to verify a nonce is still valid before attempting collection.
     * @param token       The EIP-3009 token address.
     * @param authorizer  The address that signed the authorization.
     * @param nonce       The nonce to check.
     * @return True if the nonce has already been used.
     */
    function isNonceUsed(
        address token,
        address authorizer,
        bytes32 nonce
    ) external view returns (bool) {
        return IEIP3009(token).authorizationState(authorizer, nonce);
    }

    // ============ ERC-165 ============

    function supportsInterface(bytes4 interfaceId)
        external pure override returns (bool)
    {
        return interfaceId == type(IPaymentAuth).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
}
