// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IAgentIdentityRegistry} from "./IAgentIdentityRegistry.sol";

interface VmExpiry {
    function warp(uint256 timestamp) external;
    function prank(address sender) external;
}

/// Reusable T5/T8 checks. Override deployRegistry to test an implementation, with this
/// test contract authorized to update reputation and verification. Fees must be zero.
abstract contract TrustScoreExpiryChecks {
    VmExpiry internal constant vm = VmExpiry(address(uint160(uint256(keccak256("hevm cheat code")))));
    IAgentIdentityRegistry internal registry;
    address internal constant VERIFIED = address(0x825901);
    address internal constant CONTROL = address(0x825902);

    function deployRegistry() internal virtual returns (IAgentIdentityRegistry);

    function setUp() public {
        vm.warp(1_800_000_000);
        registry = deployRegistry();
        vm.prank(VERIFIED);
        registry.registerAgent("did:agent:31337:0x0000000000000000000000000000000000825901", keccak256("a"), "ipfs://a");
        vm.prank(CONTROL);
        registry.registerAgent("did:agent:31337:0x0000000000000000000000000000000000825902", keccak256("b"), "ipfs://b");
    }

    function setEqualReputation(uint16 reputation) internal {
        registry.updateReputationScore(VERIFIED, reputation, "test observation");
        registry.updateReputationScore(CONTROL, reputation, "test observation");
    }

    function expiry() internal view returns (uint256) {
        return registry.getAgentIdentity(VERIFIED).verificationExpiry;
    }

    function assertExpired(uint16 reputation, uint256 originalExpiry) internal view {
        IAgentIdentityRegistry.AgentIdentity memory record = registry.getAgentIdentity(VERIFIED);
        require(registry.getEffectiveTier(VERIFIED) == 0 && !registry.isVerified(VERIFIED), "expired verification");
        require(record.verificationExpiry == originalExpiry, "expiry changed without renewal");
        require(record.reputationScore == reputation, "expiry changed reputation");
        require(registry.getEffectiveTier(CONTROL) == 0, "control must be unverified");
        require(registry.getAgentIdentity(CONTROL).reputationScore == reputation, "control reputation differs");
        require(
            registry.calculateTrustScore(VERIFIED) == registry.calculateTrustScore(CONTROL),
            "expired tier still contributes to score"
        );
    }

    function test_T8_expiryThenReputationUpdateUsesEqualReputationControl() public {
        setEqualReputation(500);
        registry.updateVerificationTier(VERIFIED, 3, 1 days);
        uint256 end = expiry();
        vm.warp(end + 1);
        assertExpired(500, end);
        // Both subjects receive the same new score. Comparing against the old score
        // would mix reputation changes with expiry, and would fail for saturated scores.
        setEqualReputation(750);
        assertExpired(750, end);
    }

    function test_expiryBoundaryIsStrictlyAfterDeadline() public {
        setEqualReputation(500);
        registry.updateVerificationTier(VERIFIED, 3, 10);
        uint256 end = expiry();
        vm.warp(end);
        require(registry.getEffectiveTier(VERIFIED) == 3 && registry.isVerified(VERIFIED), "expired too early");
        vm.warp(end + 1);
        assertExpired(500, end);
    }

    function test_reputationUpdateBeforeExpiryCannotExtendDeadline() public {
        registry.updateVerificationTier(VERIFIED, 3, 10);
        uint256 end = expiry();
        vm.warp(end - 1);
        setEqualReputation(750);
        require(expiry() == end, "reputation renewed verification");
        vm.warp(end + 1);
        assertExpired(750, end);
    }

    function test_explicitVerificationCanRenewAfterExpiry() public {
        setEqualReputation(750);
        registry.updateVerificationTier(VERIFIED, 3, 10);
        uint256 end = expiry();
        vm.warp(end + 1);
        assertExpired(750, end);
        registry.updateVerificationTier(VERIFIED, 2, 20);
        require(expiry() == block.timestamp + 20, "renewal deadline");
        require(registry.getEffectiveTier(VERIFIED) == 2 && registry.isVerified(VERIFIED), "renewal ineffective");
    }

    function test_T8_doesNotRequireStrictScoreDecrease() public {
        // A bounded scoring formula may saturate, so expiry need not strictly reduce
        // the numerical score. Equality with the same-reputation tier-0 control is T8.
        setEqualReputation(1000);
        registry.updateVerificationTier(VERIFIED, 3, 10);
        uint256 end = expiry();
        vm.warp(end + 1);
        assertExpired(1000, end);
    }

    function testFuzz_T8_noTierBoostAfterReputationUpdate(uint16 score, uint8 tier) public {
        uint16 reputation = score % 1001;
        registry.updateVerificationTier(VERIFIED, 1 + tier % 4, 10);
        uint256 end = expiry();
        vm.warp(end + 1);
        setEqualReputation(reputation);
        assertExpired(reputation, end);
    }
}

/// Inactive-agent checks for the rules added in ethereum/ERCs#2142. Deactivation
/// is implementation-specific; no deactivation method is added to the interface.
abstract contract InactiveAgentChecks is TrustScoreExpiryChecks {
    function deactivateForTest(address agent) internal virtual;

    function assertInactive() internal view {
        require(!registry.getAgentIdentity(VERIFIED).isActive, "adapter did not deactivate agent");
        require(registry.getEffectiveTier(VERIFIED) == 0, "inactive tier must be zero");
        require(!registry.isVerified(VERIFIED), "inactive agent must be unverified");
        require(registry.calculateTrustScore(VERIFIED) == 0, "inactive score must be zero");
    }

    function test_inactiveAgentWithUnexpiredTierHasNoTrustScore() public {
        setEqualReputation(750);
        registry.updateVerificationTier(VERIFIED, 3, 1 days);
        uint16 controlScore = registry.calculateTrustScore(CONTROL);
        require(registry.isVerified(VERIFIED), "active verification missing");
        deactivateForTest(VERIFIED);
        assertInactive();
        require(registry.getAgentIdentity(CONTROL).isActive, "control was deactivated");
        require(registry.calculateTrustScore(CONTROL) == controlScore, "unrelated score changed");
    }

    function test_inactiveUnverifiedAgentLosesBaseReputationScore() public {
        setEqualReputation(1000);
        require(registry.getEffectiveTier(VERIFIED) == 0, "expected unverified agent");
        deactivateForTest(VERIFIED);
        assertInactive();
    }

    function test_inactivityOverridesExactExpiryBoundary() public {
        setEqualReputation(500);
        registry.updateVerificationTier(VERIFIED, 2, 10);
        uint256 end = expiry();
        vm.warp(end);
        require(registry.getEffectiveTier(VERIFIED) == 2 && registry.isVerified(VERIFIED), "expired too early");
        deactivateForTest(VERIFIED);
        assertInactive();
        vm.warp(end + 1);
        assertInactive();
    }

    function test_deactivationAfterExpiryRemovesRemainingBaseScore() public {
        setEqualReputation(750);
        registry.updateVerificationTier(VERIFIED, 4, 10);
        uint256 end = expiry();
        vm.warp(end + 1);
        assertExpired(750, end);
        deactivateForTest(VERIFIED);
        assertInactive();
    }

    function testFuzz_inactiveAgentNeverKeepsTierOrScore(uint16 score, uint8 tier, uint8 elapsed) public {
        setEqualReputation(score % 1001);
        registry.updateVerificationTier(VERIFIED, tier % 5, 10);
        // Exercise deactivation before, exactly at and after the expiry boundary.
        vm.warp(block.timestamp + elapsed % 12);
        deactivateForTest(VERIFIED);
        assertInactive();
    }
}

/// Minimal test double, NOT a full ERC-8259 implementation. Its scoring formula is
/// illustrative only. An adapter can run the same checks against another registry.
contract ExpiryRegistryFixture {
    mapping(address => IAgentIdentityRegistry.AgentIdentity) private identities;
    address private immutable verifier = msg.sender;
    uint256 private nextId;

    modifier authorized() {
        require(msg.sender == verifier, "verifier only");
        _;
    }

    function registerAgent(string calldata did, bytes32 publicKey, string calldata metadataURI)
        external
        payable
        returns (uint256)
    {
        require(identities[msg.sender].registrationTime == 0, "already registered");
        IAgentIdentityRegistry.AgentIdentity storage i = identities[msg.sender];
        i.did = did;
        i.publicKey = publicKey;
        i.metadataURI = metadataURI;
        i.reputationScore = 500;
        i.registrationTime = block.timestamp;
        i.lastUpdate = block.timestamp;
        i.isActive = true;
        return ++nextId;
    }

    function updateVerificationTier(address agent, uint8 tier, uint256 validity) external payable authorized {
        require(identities[agent].isActive && tier <= 4);
        identities[agent].verificationTier = tier;
        identities[agent].verificationExpiry = block.timestamp + validity;
        identities[agent].lastUpdate = block.timestamp;
    }

    function updateReputationScore(address agent, uint16 score, string calldata) external authorized {
        require(identities[agent].isActive && score <= 1000);
        identities[agent].reputationScore = score;
        identities[agent].lastUpdate = block.timestamp;
    }

    function getAgentIdentity(address agent) external view returns (IAgentIdentityRegistry.AgentIdentity memory) {
        return identities[agent];
    }

    function deactivateForTest(address agent) external authorized {
        identities[agent].isActive = false;
    }

    function getEffectiveTier(address agent) public view returns (uint8) {
        if (!identities[agent].isActive || block.timestamp > identities[agent].verificationExpiry) return 0;
        return identities[agent].verificationTier;
    }

    function isVerified(address agent) external view returns (bool) {
        return getEffectiveTier(agent) > 0;
    }

    function calculateTrustScore(address agent) external view returns (uint16) {
        if (!identities[agent].isActive) return 0;
        uint256 score = uint256(identities[agent].reputationScore) + uint256(getEffectiveTier(agent)) * 100;
        return uint16(score > 1000 ? 1000 : score);
    }
}

contract TrustScoreExpiryFixtureTest is InactiveAgentChecks {
    function deployRegistry() internal override returns (IAgentIdentityRegistry) {
        return IAgentIdentityRegistry(address(new ExpiryRegistryFixture()));
    }

    function deactivateForTest(address agent) internal override {
        ExpiryRegistryFixture(address(registry)).deactivateForTest(agent);
    }

    function test_fixtureRetainsHistoryWhileInactiveViewsReturnZero() public {
        setEqualReputation(1000);
        registry.updateVerificationTier(VERIFIED, 4, 10);
        uint256 end = expiry();
        deactivateForTest(VERIFIED);
        IAgentIdentityRegistry.AgentIdentity memory record = registry.getAgentIdentity(VERIFIED);
        require(record.verificationTier == 4 && record.reputationScore == 1000, "fixture erased history");
        require(record.verificationExpiry == end, "fixture changed expiry");
        assertInactive();
    }

    function test_fixtureKeepsStoredTierButDropsItsContribution() public {
        setEqualReputation(500);
        registry.updateVerificationTier(VERIFIED, 3, 10);
        uint256 end = expiry();
        vm.warp(end + 1);
        require(registry.getAgentIdentity(VERIFIED).verificationTier == 3, "fixture should retain raw tier");
        assertExpired(500, end);
    }
}
