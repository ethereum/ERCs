// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.26;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA}  from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {InvoiceCommitmentTypes} from "./InvoiceCommitmentTypes.sol";
import {InvoiceHasher}          from "./InvoiceHasher.sol";

/// @title InvoiceCommitmentRegistry
/// @notice Singleton registrar that commits EIP-712-signed invoice metadata to on-chain payments.
/// @dev Reference implementation of ERC-8342 (Verifiable Invoice Commitment).
contract InvoiceCommitmentRegistry is EIP712 {
    struct CommitmentRecord {
        address issuer;
        address recipient;
        bytes32 paymentTxRef;
    }

    mapping(bytes32 invoiceHash => CommitmentRecord) private _commitments;
    mapping(address issuer => mapping(uint256 nonce => bool used)) private _nonceUsed;

    event InvoiceCommitted(
        bytes32 indexed invoiceHash,
        address indexed issuer,
        address indexed recipient,
        bytes32 paymentTxRef,
        InvoiceCommitmentTypes.PayloadMode payloadMode,
        string  uri,
        bytes   encryptedPayload,
        bytes   issuerSignature
    );

    error InvalidSignature();
    error UnauthorizedCaller(address caller);
    error NonceAlreadyUsed(address issuer, uint256 nonce);
    error InvoiceAlreadyCommitted(bytes32 invoiceHash);
    error EncryptedPayloadRequired();
    error EncryptedPayloadForbidden();

    constructor() EIP712("VerifiableInvoiceCommitment", "1") {}

    /// @notice Commits an invoice after validating its EIP-712 signature.
    /// @dev Only the issuer or the recipient may commit: the signature does not cover
    ///      paymentTxRef, payloadMode, uri or encryptedPayload, so a third party holding
    ///      a signed invoice must not be able to choose them.
    function commitInvoice(
        InvoiceCommitmentTypes.Invoice calldata invoice,
        bytes32 paymentTxRef,
        InvoiceCommitmentTypes.PayloadMode payloadMode,
        string calldata uri,
        bytes calldata encryptedPayload,
        bytes calldata issuerSignature
    ) external returns (bytes32 invoiceHash) {
        if (msg.sender != invoice.issuer && msg.sender != invoice.recipient) {
            revert UnauthorizedCaller(msg.sender);
        }

        invoiceHash = _hashTypedDataV4(InvoiceHasher.hashInvoiceStruct(invoice));

        if (_nonceUsed[invoice.issuer][invoice.nonce]) {
            revert NonceAlreadyUsed(invoice.issuer, invoice.nonce);
        }
        if (_commitments[invoiceHash].issuer != address(0)) {
            revert InvoiceAlreadyCommitted(invoiceHash);
        }
        if (
            payloadMode == InvoiceCommitmentTypes.PayloadMode.EncryptedOnChain &&
            encryptedPayload.length == 0
        ) {
            revert EncryptedPayloadRequired();
        }
        if (
            payloadMode == InvoiceCommitmentTypes.PayloadMode.OffChain &&
            encryptedPayload.length != 0
        ) {
            revert EncryptedPayloadForbidden();
        }

        address recovered = ECDSA.recover(invoiceHash, issuerSignature);
        if (recovered != invoice.issuer) {
            revert InvalidSignature();
        }

        _nonceUsed[invoice.issuer][invoice.nonce] = true;
        _commitments[invoiceHash] = CommitmentRecord({
            issuer:       invoice.issuer,
            recipient:    invoice.recipient,
            paymentTxRef: paymentTxRef
        });

        emit InvoiceCommitted(
            invoiceHash,
            invoice.issuer,
            invoice.recipient,
            paymentTxRef,
            payloadMode,
            uri,
            encryptedPayload,
            issuerSignature
        );
    }

    function isNonceUsed(address issuer, uint256 nonce) external view returns (bool) {
        return _nonceUsed[issuer][nonce];
    }

    function getCommitment(bytes32 invoiceHash) external view returns (
        address issuer,
        address recipient,
        bytes32 paymentTxRef
    ) {
        CommitmentRecord storage rec = _commitments[invoiceHash];
        return (rec.issuer, rec.recipient, rec.paymentTxRef);
    }

    /// @notice Exposes the EIP-712 domain separator for off-chain signers.
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice Computes the EIP-712 digest of an invoice without committing it.
    /// @dev Useful for off-chain signers to verify they produce the same hash.
    function hashInvoice(InvoiceCommitmentTypes.Invoice calldata invoice)
        external
        view
        returns (bytes32)
    {
        return _hashTypedDataV4(InvoiceHasher.hashInvoiceStruct(invoice));
    }
}
