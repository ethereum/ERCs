// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.26;

/// @title InvoiceCommitmentTypes
/// @notice Shared struct definitions for ERC-8342 (Verifiable Invoice Commitment).
/// @dev Kept in a separate library to avoid circular imports between the registrar
///      and the hashing library.
library InvoiceCommitmentTypes {
    enum PayloadMode {
        OffChain,
        EncryptedOnChain
    }

    struct TaxIdentity {
        string scheme;
        string id;
    }

    struct TaxEntry {
        string  taxType;
        string  taxScheme;
        uint256 rateBps;
        uint256 baseAmountMilliUnits;
        uint256 taxAmountMilliUnits;
    }

    struct LineItem {
        string  description;
        uint256 quantityScaled;
        string  unit;
        uint256 unitPriceMilliUnits;
        uint256 lineTotalMilliUnits;
        uint256 taxRefIndex;
    }

    struct Invoice {
        string       invoiceId;
        uint256      issueDate;
        uint256      dueDate;
        string       paymentTerms;
        string       purchaseOrderRef;

        address      issuer;
        TaxIdentity  issuerTaxId;
        address      recipient;
        TaxIdentity  recipientTaxId;

        address      paymentToken;
        uint256      paymentAmount;
        string       fiatCurrency;
        uint256      fiatAmountMilliUnits;
        uint256      fxRateScaled;
        address      fxOracle;
        uint256      fxTimestamp;

        TaxEntry[]   taxes;
        LineItem[]   lineItems;

        string       jurisdiction;
        bytes        regulatoryData;

        uint256      nonce;
    }
}
