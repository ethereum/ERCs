// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IPaymentAuth} from "../interfaces/IPaymentAuth.sol";

/**
 * @title ISignatureTransfer (minimal subset)
 * @dev Inline interface to avoid a hard Permit2 package dependency in the
 *      reference implementation. Production deployments SHOULD import from
 *      the official Permit2 package (github.com/Uniswap/permit2).
 */
interface ISignatureTransfer {
    struct TokenPermissions {
        address token;
        uint256 amount;
    }
    struct PermitTransferFrom {
        TokenPermissions permitted;
        uint256 nonce;
        uint256 deadline;
    }
    struct SignatureTransferDetails {
        address to;
        uint256 requestedAmount;
    }
    function permitTransferFrom(
        PermitTransferFrom memory permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external;
}

/**
 * @title Permit2Auth
 * @notice IPaymentAuth strategy using Uniswap Permit2 SignatureTransfer.
 *
 * @dev Leverages the canonical Permit2 deployment to support signature-based
 *      transfers for any ERC-20 token, including tokens that do not implement
 *      ERC-2612. Each signature is single-use and replay-proof by construction
 *      — Permit2 stores a consumed-nonce bitmap.
 *
 *      Payer prerequisite: call token.approve(PERMIT2, type(uint256).max)
 *      once. This one-time approval is shared across all Permit2-integrated
 *      protocols.
 *
 *      Canonical Permit2 address (same across Ethereum mainnet, Arbitrum,
 *      Optimism, Base, Polygon, and other major networks):
 *      0x000000000022D473030F116dDEE9F6B43aC78BA3
 *
 *      Typical use: downPaymentAuthStrategy — gasless signature-based checkout
 *      for any ERC-20 token.
 *
 *      authData: abi.encode(uint256 nonce, uint256 deadline, bytes signature)
 *        where signature is the EIP-712 sig over the PermitTransferFrom struct.
 */
contract Permit2Auth is IPaymentAuth, ReentrancyGuard {

    bytes4 public constant AUTH_TYPE_ID = bytes4(keccak256("Permit2Auth"));

    /// @notice Canonical Permit2 deployment address.
    address public constant PERMIT2 =
        0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // ============ IPaymentAuth ============

    function authType() external pure override returns (bytes4) {
        return AUTH_TYPE_ID;
    }

    function pullPayment(
        address payer,
        address recipient,
        address token,
        uint256 amount,
        bytes calldata authData
    ) external override nonReentrant returns (bool) {
        (uint256 nonce, uint256 deadline, bytes memory signature) =
            abi.decode(authData, (uint256, uint256, bytes));

        ISignatureTransfer(PERMIT2).permitTransferFrom(
            ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: token,
                    amount: amount
                }),
                nonce: nonce,
                deadline: deadline
            }),
            ISignatureTransfer.SignatureTransferDetails({
                to: recipient,
                requestedAmount: amount
            }),
            payer,
            signature
        );

        // Permit2 handles the transfer internally — no transferFrom call needed
        return true;
    }

    // ============ ERC-165 ============

    function supportsInterface(bytes4 interfaceId)
        external pure override returns (bool)
    {
        return interfaceId == type(IPaymentAuth).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
}
