// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IEligibility} from "../interfaces/IEligibility.sol";
import {ITrustAssertionRegistry} from "./interfaces/ITrustAssertionRegistry.sol";

/// @title  AssertionLevelEligibility — a member must hold a trust assertion of at least a level
///         (reference v0.2)
/// @notice Reads a know-your-agent trust-assertion registry: the account, as an `account` subject
///         on this chain, must hold an unexpired, binding-satisfied assertion of at least `minLevel`
///         under `schemeId` from one of the configured issuers. A revoked or expired assertion makes
///         a later `challenge` suspend the member; a registry that reverts makes the challenge report
///         the predicate as unevaluable.
contract AssertionLevelEligibility is IEligibility {
    bytes32 public constant SUBJECT_ACCOUNT = keccak256("account");

    ITrustAssertionRegistry public immutable assertions;
    bytes32 public immutable schemeId;
    uint8   public immutable minLevel;
    address[] private _issuers;

    constructor(ITrustAssertionRegistry assertions_, bytes32 schemeId_, uint8 minLevel_, address[] memory issuers_) {
        require(address(assertions_) != address(0) && schemeId_ != bytes32(0), "AssertionLevel: zero");
        require(minLevel_ > 0 && issuers_.length > 0, "AssertionLevel: threshold");
        assertions = assertions_;
        schemeId = schemeId_;
        minLevel = minLevel_;
        _issuers = issuers_;
    }

    function issuers() external view returns (address[] memory) { return _issuers; }

    function isEligible(bytes32, bytes32, address account) external view returns (bool) {
        ITrustAssertionRegistry.Subject memory subject =
            ITrustAssertionRegistry.Subject({subjectType: SUBJECT_ACCOUNT, subjectData: abi.encode(block.chainid, account)});
        return assertions.check(subject, schemeId, minLevel, _issuers);
    }
}
