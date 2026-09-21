// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IComplianceProvider} from "./interfaces/IComplianceProvider.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title ComplianceProvider
/// @notice Reference implementation of IComplianceProvider. The owner is the compliance operator
///         who grants and revokes principal eligibility.
contract ComplianceProvider is IComplianceProvider, ERC165, Ownable {
    struct Record {
        bytes32 identityRef;
        uint48 expiresAt;
        bool revoked;
        ReasonCode reason;
    }

    mapping(address principal => Record) private _records;

    error ZeroIdentityRef();
    error NotActive(address principal);

    constructor(address operator) Ownable(operator) {}

    /// @inheritdoc IComplianceProvider
    function grantPrincipal(address principal, bytes32 identityRef, uint48 expiresAt) external onlyOwner {
        if (identityRef == bytes32(0)) revert ZeroIdentityRef();
        _records[principal] =
            Record({identityRef: identityRef, expiresAt: expiresAt, revoked: false, reason: ReasonCode.COMPLIANT});
        emit PrincipalGranted(principal, identityRef);
    }

    /// @inheritdoc IComplianceProvider
    function revokePrincipal(address principal, ReasonCode reason) external onlyOwner {
        Record storage record = _records[principal];
        if (record.identityRef == bytes32(0) || record.revoked) revert NotActive(principal);
        record.revoked = true;
        record.reason = reason;
        emit PrincipalRevoked(principal, record.identityRef, reason);
    }

    /// @inheritdoc IComplianceProvider
    function checkPrincipal(address principal, bytes32 identityRef)
        external
        view
        returns (bool eligible, ReasonCode reason, uint48 expiresAt)
    {
        Record memory record = _records[principal];

        if (record.identityRef == bytes32(0)) return (false, ReasonCode.IDENTITY_NOT_FOUND, 0);
        if (record.revoked) return (false, record.reason, 0);
        if (record.identityRef != identityRef) return (false, ReasonCode.IDENTITY_NOT_FOUND, 0);
        if (record.expiresAt != 0 && block.timestamp > record.expiresAt) {
            return (false, ReasonCode.KYC_EXPIRED, record.expiresAt);
        }
        return (true, ReasonCode.COMPLIANT, record.expiresAt);
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IComplianceProvider).interfaceId || super.supportsInterface(interfaceId);
    }
}
