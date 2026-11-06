// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

// AUF errors: custom errors shared by the AIFi Unit Framework registries.

// Unit Registry
error AUF_UnitNotFound(uint256 unitId);
error AUF_VersionNotFound(uint256 unitId, uint32 version);
error AUF_NotController(uint256 unitId, address account);
error AUF_Frozen(uint256 unitId);
error AUF_ZeroHash();
error AUF_SelfContainment(uint256 unitId);
error AUF_InvalidAckKind();
error AUF_NoAcknowledgment();

// Assertion Registry
error AUF_InvalidKind();
error AUF_InvalidValidity();
error AUF_InvalidPayload();
error AUF_InvalidResultKind(uint8 resultKind);
error AUF_MethodMismatch(bytes32 profileId, bytes32 methodId);
error AUF_ValueNotAllowed(uint8 resultKind);
error AUF_InvalidWindow();
error AUF_AssertionNotFound(bytes32 assertionId);
error AUF_NotAsserter(bytes32 assertionId, address account);
error AUF_NotActive(bytes32 assertionId);
error AUF_SupersedeMismatch(bytes32 assertionId);
error AUF_DescriptorExists(bytes32 descriptorHash);
error AUF_DescriptorNotFound(bytes32 descriptorHash);
error AUF_Expired(uint256 deadline);
error AUF_InvalidSignature();
