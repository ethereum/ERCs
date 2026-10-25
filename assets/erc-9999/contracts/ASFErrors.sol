// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title ASFErrors — custom errors of the reference implementation
library ASFErrors {
    // specification registry
    error SpecificationExists();
    error UnknownSpecification();
    error UnknownVersion();
    error NotPublisher();
    error SpecificationFrozen();
    error ZeroContentHash();
    error ZeroPublisher();

    // binding registry
    error BindingExists();
    error UnknownBinding();
    error NotAdopter();
    error NotAuthorized();
    error InvalidState();
    error InvalidRestriction();
    error InvalidValidity();
    error SpecRegistryNotSupported();
    error ContentHashMismatch();
    error ParentNotActive();
    error ParentMismatch();
    error ParentWindowExceeded();
    error DepthExceeded();
    error ZeroIntervener();
    error DuplicateIntervener();
    error InvalidRights();
    error TooManyInterveners();
    error LengthMismatch();
    error InvalidRequirement();
}
