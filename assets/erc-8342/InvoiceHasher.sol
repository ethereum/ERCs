// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.26;

import {InvoiceCommitmentTypes} from "./InvoiceCommitmentTypes.sol";

/// @title InvoiceHasher
/// @notice EIP-712 struct-hash computation for the Invoice typed data of ERC-8342.
/// @dev Type strings here MUST stay byte-identical to those used by off-chain signers,
///      otherwise computed digests will diverge.
library InvoiceHasher {
    bytes32 internal constant TAX_IDENTITY_TYPEHASH = keccak256(
        "TaxIdentity(string scheme,string id)"
    );

    bytes32 internal constant TAX_ENTRY_TYPEHASH = keccak256(
        "TaxEntry(string taxType,string taxScheme,uint256 rateBps,uint256 baseAmountMilliUnits,uint256 taxAmountMilliUnits)"
    );

    bytes32 internal constant LINE_ITEM_TYPEHASH = keccak256(
        "LineItem(string description,uint256 quantityScaled,string unit,uint256 unitPriceMilliUnits,uint256 lineTotalMilliUnits,uint256 taxRefIndex)"
    );

    /// @dev Composite type string follows EIP-712 ordering: the primary type is
    ///      written first, then referenced types in alphabetical order.
    bytes32 internal constant INVOICE_TYPEHASH = keccak256(
        "Invoice(string invoiceId,uint256 issueDate,uint256 dueDate,string paymentTerms,string purchaseOrderRef,address issuer,TaxIdentity issuerTaxId,address recipient,TaxIdentity recipientTaxId,address paymentToken,uint256 paymentAmount,string fiatCurrency,uint256 fiatAmountMilliUnits,uint256 fxRateScaled,address fxOracle,uint256 fxTimestamp,TaxEntry[] taxes,LineItem[] lineItems,string jurisdiction,bytes regulatoryData,uint256 nonce)"
        "LineItem(string description,uint256 quantityScaled,string unit,uint256 unitPriceMilliUnits,uint256 lineTotalMilliUnits,uint256 taxRefIndex)"
        "TaxEntry(string taxType,string taxScheme,uint256 rateBps,uint256 baseAmountMilliUnits,uint256 taxAmountMilliUnits)"
        "TaxIdentity(string scheme,string id)"
    );

    function hashInvoiceStruct(InvoiceCommitmentTypes.Invoice calldata inv)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                INVOICE_TYPEHASH,
                keccak256(bytes(inv.invoiceId)),
                inv.issueDate,
                inv.dueDate,
                keccak256(bytes(inv.paymentTerms)),
                keccak256(bytes(inv.purchaseOrderRef)),
                inv.issuer,
                hashTaxIdentity(inv.issuerTaxId),
                inv.recipient,
                hashTaxIdentity(inv.recipientTaxId),
                inv.paymentToken,
                inv.paymentAmount,
                keccak256(bytes(inv.fiatCurrency)),
                inv.fiatAmountMilliUnits,
                inv.fxRateScaled,
                inv.fxOracle,
                inv.fxTimestamp,
                hashTaxArray(inv.taxes),
                hashLineItemArray(inv.lineItems),
                keccak256(bytes(inv.jurisdiction)),
                keccak256(inv.regulatoryData),
                inv.nonce
            )
        );
    }

    function hashTaxIdentity(InvoiceCommitmentTypes.TaxIdentity calldata t)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(
            TAX_IDENTITY_TYPEHASH,
            keccak256(bytes(t.scheme)),
            keccak256(bytes(t.id))
        ));
    }

    function hashTaxEntry(InvoiceCommitmentTypes.TaxEntry calldata t)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(
            TAX_ENTRY_TYPEHASH,
            keccak256(bytes(t.taxType)),
            keccak256(bytes(t.taxScheme)),
            t.rateBps,
            t.baseAmountMilliUnits,
            t.taxAmountMilliUnits
        ));
    }

    function hashLineItem(InvoiceCommitmentTypes.LineItem calldata l)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(
            LINE_ITEM_TYPEHASH,
            keccak256(bytes(l.description)),
            l.quantityScaled,
            keccak256(bytes(l.unit)),
            l.unitPriceMilliUnits,
            l.lineTotalMilliUnits,
            l.taxRefIndex
        ));
    }

    function hashTaxArray(InvoiceCommitmentTypes.TaxEntry[] calldata arr)
        internal
        pure
        returns (bytes32)
    {
        bytes32[] memory hashes = new bytes32[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            hashes[i] = hashTaxEntry(arr[i]);
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function hashLineItemArray(InvoiceCommitmentTypes.LineItem[] calldata arr)
        internal
        pure
        returns (bytes32)
    {
        bytes32[] memory hashes = new bytes32[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            hashes[i] = hashLineItem(arr[i]);
        }
        return keccak256(abi.encodePacked(hashes));
    }
}
