import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";

/**
 * Security Features Test Suite for ERC-7893 Solvency Proof Standard
 * Demonstrates how users can protect themselves using the security features
 */

describe("ERC-7893 Security Features & User Protection", function () {
    
    async function deploySecurityFixture() {
        const [owner, oracle1, oracle2, oracle3, attacker, guardian] = await ethers.getSigners();
        
        // Deploy mock tokens
        const MockToken = await ethers.getContractFactory("MockToken");
        const weth = await MockToken.deploy("Wrapped Ether", "WETH");
        const usdc = await MockToken.deploy("USD Coin", "USDC");
        
        // Deploy solvency proof with security features
        const SolvencyProof = await ethers.getContractFactory("SolvencyProof");
        const solvencyProof = await SolvencyProof.deploy();
        
        // Deploy multi-oracle system for consensus testing
        const MockMultiOracle = await ethers.getContractFactory("MockMultiOracle");
        const multiOracle = await MockMultiOracle.deploy();
        
        // Setup roles and permissions (DO NOT enable test mode - test real security)
        await solvencyProof.setOracle(oracle1.address, true);
        await solvencyProof.setOracle(oracle2.address, true);
        await solvencyProof.setOracle(oracle3.address, true);
        await solvencyProof.setEmergencyGuardian(guardian.address);
        
        // Setup multi-oracle
        await multiOracle.authorizeOracle(oracle1.address, true);
        await multiOracle.authorizeOracle(oracle2.address, true);
        await multiOracle.authorizeOracle(oracle3.address, true);
        
        return {
            solvencyProof,
            multiOracle,
            weth, usdc,
            owner, oracle1, oracle2, oracle3, attacker, guardian
        };
    }

    // Helper function to mine blocks for rate limiting tests
    async function mineBlocks(count: number) {
        for (let i = 0; i < count; i++) {
            await ethers.provider.send("evm_mine", []);
        }
    }

    describe("🔒 User Protection: Rate Limiting", function() {
        it("Should protect against spam attacks with rate limiting", async function() {
            const { solvencyProof, weth, oracle1 } = await loadFixture(deploySecurityFixture);
            
            console.log("✅ Testing rate limiting protection...");
            
            // First update should succeed
            await solvencyProof.connect(oracle1).updateAssets(
                [weth.target],
                [ethers.parseEther("100")],
                [ethers.parseEther("100")]
            );
            
            console.log("   ✓ First update successful");
            
            // Immediate second update should fail (protection active)
            await expect(
                solvencyProof.connect(oracle1).updateAssets(
                    [weth.target],
                    [ethers.parseEther("200")],
                    [ethers.parseEther("200")]
                )
            ).to.be.revertedWith("Update too frequent");
            
            console.log("   ✓ Spam attack prevented by rate limiting");
            
            // After cooldown period, should work again
            await mineBlocks(6); // Exceed 5-block cooldown
            
            await expect(
                solvencyProof.connect(oracle1).updateAssets(
                    [weth.target],
                    [ethers.parseEther("200")],
                    [ethers.parseEther("200")]
                )
            ).to.not.be.reverted;
            
            console.log("   ✓ Normal operation restored after cooldown");
        });
    });

    describe("🔒 User Protection: Access Control", function() {
        it("Should protect against unauthorized oracle access", async function() {
            const { solvencyProof, weth, attacker } = await loadFixture(deploySecurityFixture);
            
            console.log("✅ Testing access control protection...");
            
            // Unauthorized user cannot update data
            await expect(
                solvencyProof.connect(attacker).updateAssets(
                    [weth.target],
                    [ethers.parseEther("100")],
                    [ethers.parseEther("100")]
                )
            ).to.be.revertedWith("Not authorized oracle");
            
            console.log("   ✓ Unauthorized access blocked");
            
            // Check role-based security
            const oracleRole = await solvencyProof.ORACLE_ROLE();
            const hasRole = await solvencyProof.hasRole(oracleRole, attacker.address);
            expect(hasRole).to.be.false;
            
            console.log("   ✓ Role-based access control working");
            
            // Only admin can authorize new oracles
            await expect(
                solvencyProof.connect(attacker).setOracle(attacker.address, true)
            ).to.be.reverted;
            
            console.log("   ✓ Oracle authorization protected");
        });
    });

    describe("🔒 User Protection: Circuit Breaker", function() {
        it("Should protect against market manipulation with circuit breaker", async function() {
            const { solvencyProof, weth, oracle1, oracle2 } = await loadFixture(deploySecurityFixture);
            
            console.log("✅ Testing circuit breaker protection...");
            
            // Setup normal state
            await solvencyProof.connect(oracle1).updateAssets(
                [weth.target],
                [ethers.parseEther("100")],
                [ethers.parseEther("100")]
            );
            
            await mineBlocks(6);
            
            await solvencyProof.connect(oracle2).updateLiabilities(
                [weth.target],
                [ethers.parseEther("50")],
                [ethers.parseEther("50")]
            );
            
            console.log("   ✓ Normal state established");
            
            await mineBlocks(6);
            
            // Attempt large price movement (should trigger circuit breaker)
            await expect(
                solvencyProof.connect(oracle1).updateAssets(
                    [weth.target],
                    [ethers.parseEther("100")],
                    [ethers.parseEther("70")] // 30% drop - exceeds 20% threshold
                )
            ).to.emit(solvencyProof, "CircuitBreakerTriggered");
            
            console.log("   ✓ Circuit breaker triggered on large price movement");
            
            // System should be paused
            const [isPaused] = await solvencyProof.getEmergencyStatus();
            expect(isPaused).to.be.true;
            
            console.log("   ✓ System automatically paused for protection");
        });
    });

    describe("🔒 User Protection: Emergency Controls", function() {
        it("Should provide emergency pause capabilities", async function() {
            const { solvencyProof, guardian, attacker, oracle1 } = await loadFixture(deploySecurityFixture);
            
            console.log("✅ Testing emergency control protection...");
            
            // Only authorized guardian can pause
            await expect(
                solvencyProof.connect(attacker).emergencyPause()
            ).to.be.revertedWith("Not emergency guardian");
            
            console.log("   ✓ Emergency pause protected from unauthorized access");
            
            // Guardian can pause in emergency
            await expect(
                solvencyProof.connect(guardian).emergencyPause()
            ).to.emit(solvencyProof, "EmergencyPaused");
            
            console.log("   ✓ Guardian can trigger emergency pause");
            
            // All operations blocked during pause
            await expect(
                solvencyProof.connect(oracle1).updateAssets([], [], [])
            ).to.be.revertedWith("Emergency paused");
            
            console.log("   ✓ Operations blocked during emergency pause");
            
            // Guardian can restore operations
            await expect(
                solvencyProof.connect(guardian).emergencyUnpause()
            ).to.emit(solvencyProof, "EmergencyUnpaused");
            
            console.log("   ✓ Guardian can restore normal operations");
        });
    });

    describe("🔒 User Protection: DoS Prevention", function() {
        it("Should protect against DoS attacks", async function() {
            const { solvencyProof, oracle1, weth } = await loadFixture(deploySecurityFixture);
            
            console.log("✅ Testing DoS protection...");
            
            // Test maximum tokens limit
            const tooManyTokens: string[] = [];
            const amounts: bigint[] = [];
            const values: bigint[] = [];
            
            // Create 51 tokens (exceeds 50 limit)
            for (let i = 0; i < 51; i++) {
                tooManyTokens.push(ethers.Wallet.createRandom().address);
                amounts.push(ethers.parseEther("1"));
                values.push(ethers.parseEther("1"));
            }
            
            await expect(
                solvencyProof.connect(oracle1).updateAssets(tooManyTokens, amounts, values)
            ).to.be.revertedWith("Too many tokens");
            
            console.log("   ✓ DoS attack prevented (too many tokens)");
            
            // Test array mismatch protection
            await expect(
                solvencyProof.connect(oracle1).updateAssets(
                    [weth.target, weth.target], // 2 tokens
                    [ethers.parseEther("100")], // 1 amount
                    [ethers.parseEther("100")]  // 1 value
                )
            ).to.be.revertedWith("Array lengths mismatch");
            
            console.log("   ✓ Array mismatch attack prevented");
        });
    });

    describe("🔒 User Protection: Critical Solvency Monitoring", function() {
        it("Should auto-protect when solvency becomes critical", async function() {
            const { solvencyProof, weth, oracle1, oracle2 } = await loadFixture(deploySecurityFixture);
            
            console.log("✅ Testing critical solvency protection...");
            
            // Setup position near critical threshold
            await solvencyProof.connect(oracle1).updateAssets(
                [weth.target],
                [ethers.parseEther("102")],
                [ethers.parseEther("102")]
            );
            
            await mineBlocks(6);
            
            await solvencyProof.connect(oracle2).updateLiabilities(
                [weth.target],
                [ethers.parseEther("100")],
                [ethers.parseEther("100")]
            );
            
            const ratio = await solvencyProof.getSolvencyRatio();
            expect(ratio).to.equal(10200); // 102%
            
            console.log("   ✓ Position set at 102% (just above critical)");
            
            await mineBlocks(6);
            
            // Push below critical threshold
            await expect(
                solvencyProof.connect(oracle1).updateAssets(
                    [weth.target],
                    [ethers.parseEther("101")],
                    [ethers.parseEther("101")]
                )
            ).to.emit(solvencyProof, "RiskAlert");
            
            console.log("   ✓ Critical alert triggered");
            
            // Should auto-pause for protection
            const [isPaused] = await solvencyProof.getEmergencyStatus();
            expect(isPaused).to.be.true;
            
            console.log("   ✓ System auto-paused for critical protection");
        });
    });

    describe("🔒 User Protection: Oracle Staleness Detection", function() {
        it("Should detect and flag stale oracle data", async function() {
            const { solvencyProof, oracle1 } = await loadFixture(deploySecurityFixture);
            
            console.log("✅ Testing oracle staleness detection...");
            
            // Check initial status (no updates yet)
            let [isAuthorized, lastUpdate, isStale] = await solvencyProof.getOracleStatus(oracle1.address);
            expect(isAuthorized).to.be.true;
            expect(isStale).to.be.true; // No update yet, so stale
            
            console.log("   ✓ Initial state correctly shows stale data");
            
            // Update to make fresh
            await solvencyProof.connect(oracle1).updateAssets([], [], []);
            
            [isAuthorized, lastUpdate, isStale] = await solvencyProof.getOracleStatus(oracle1.address);
            expect(isStale).to.be.false; // Should be fresh now
            
            console.log("   ✓ After update, data is fresh");
            
            // Fast forward beyond staleness threshold
            await time.increase(3601); // > 1 hour
            
            [isAuthorized, lastUpdate, isStale] = await solvencyProof.getOracleStatus(oracle1.address);
            expect(isStale).to.be.true; // Should be stale again
            
            console.log("   ✓ After 1 hour, data correctly flagged as stale");
        });
    });

    describe("🔒 User Protection: Multi-Oracle Consensus", function() {
        it("Should demonstrate oracle consensus for price validation", async function() {
            const { multiOracle, weth, oracle1, oracle2, oracle3 } = await loadFixture(deploySecurityFixture);
            
            console.log("✅ Testing multi-oracle consensus protection...");
            
            const basePrice = ethers.parseEther("2000");
            
            // Good scenario: All oracles agree (within 5%)
            await multiOracle.connect(oracle1).updatePrice(weth.target, basePrice, oracle1.address);
            await multiOracle.connect(oracle2).updatePrice(weth.target, ethers.parseEther("2050"), oracle2.address); // +2.5%
            await multiOracle.connect(oracle3).updatePrice(weth.target, ethers.parseEther("1950"), oracle3.address); // -2.5%
            
            let [consensusPrice, consensusReached] = await multiOracle.getConsensusPrice(weth.target);
            expect(consensusReached).to.be.true;
            
            console.log("   ✓ Consensus reached when oracles agree");
            
            // Bad scenario: One oracle tries manipulation
            await multiOracle.connect(oracle3).updatePrice(weth.target, ethers.parseEther("4000"), oracle3.address); // 100% increase
            
            [consensusPrice, consensusReached] = await multiOracle.getConsensusPrice(weth.target);
            expect(consensusReached).to.be.false; // Should fail consensus
            
            console.log("   ✓ Consensus fails when oracle attempts manipulation");
        });
    });

    describe("🔒 User Protection: Security Parameters Transparency", function() {
        it("Should provide transparent access to all security parameters", async function() {
            const { solvencyProof } = await loadFixture(deploySecurityFixture);
            
            console.log("✅ Testing security parameter transparency...");
            
            const [
                maxPriceDeviation,
                maxTokensPerUpdate,
                stalenessThreshold,
                circuitBreakerThreshold,
                updateCooldown
            ] = await solvencyProof.getSecurityParameters();
            
            // Users can verify the security parameters
            expect(maxPriceDeviation).to.equal(500); // 5%
            expect(maxTokensPerUpdate).to.equal(50);
            expect(stalenessThreshold).to.equal(3600); // 1 hour
            expect(circuitBreakerThreshold).to.equal(2000); // 20%
            expect(updateCooldown).to.equal(5); // 5 blocks
            
            console.log("   ✓ All security parameters are transparent:");
            console.log(`      • Max Price Deviation: ${Number(maxPriceDeviation) / 100}%`);
            console.log(`      • Max Tokens per Update: ${maxTokensPerUpdate}`);
            console.log(`      • Staleness Threshold: ${stalenessThreshold}s`);
            console.log(`      • Circuit Breaker: ${Number(circuitBreakerThreshold) / 100}%`);
            console.log(`      • Update Cooldown: ${updateCooldown} blocks`);
        });
    });

    describe("🎯 Complete User Protection Summary", function() {
        it("Should demonstrate all security features working together", async function() {
            const { solvencyProof, weth, oracle1, guardian } = await loadFixture(deploySecurityFixture);
            
            console.log("\n🛡️  ERC-7893 SECURITY FEATURES SUMMARY");
            console.log("=====================================");
            
            // 1. Access Control
            const oracleRole = await solvencyProof.ORACLE_ROLE();
            const hasRole = await solvencyProof.hasRole(oracleRole, oracle1.address);
            expect(hasRole).to.be.true;
            console.log("✅ Role-based Access Control: ACTIVE");
            
            // 2. Rate Limiting
            const [,,,,updateCooldown] = await solvencyProof.getSecurityParameters();
            expect(updateCooldown).to.equal(5);
            console.log("✅ Rate Limiting (5 blocks): ACTIVE");
            
            // 3. DoS Protection
            const [,maxTokens,,,] = await solvencyProof.getSecurityParameters();
            expect(maxTokens).to.equal(50);
            console.log("✅ DoS Protection (50 token limit): ACTIVE");
            
            // 4. Circuit Breaker
            const [,,,circuitThreshold,] = await solvencyProof.getSecurityParameters();
            expect(circuitThreshold).to.equal(2000);
            console.log("✅ Circuit Breaker (20% threshold): ACTIVE");
            
            // 5. Emergency Controls
            const [,,guardianAddr] = await solvencyProof.getEmergencyStatus();
            expect(guardianAddr).to.equal(guardian.address);
            console.log("✅ Emergency Controls: ACTIVE");
            
            // 6. Oracle Staleness Detection
            const [,,stalenessThreshold,,] = await solvencyProof.getSecurityParameters();
            expect(stalenessThreshold).to.equal(3600);
            console.log("✅ Oracle Staleness Detection (1 hour): ACTIVE");
            
            // 7. Historical Data Bounds
            await solvencyProof.connect(oracle1).updateAssets(
                [weth.target],
                [ethers.parseEther("100")],
                [ethers.parseEther("100")]
            );
            const history = await solvencyProof.getSolvencyHistory(0, await time.latest());
            expect(history.timestamps.length).to.be.greaterThan(0);
            console.log("✅ Bounded Historical Data: ACTIVE");
            
            console.log("\n🎉 ALL SECURITY FEATURES ARE OPERATIONAL");
            console.log("   Users are protected against:");
            console.log("   • Oracle manipulation attacks");
            console.log("   • Spam/DoS attacks");
            console.log("   • Market manipulation");
            console.log("   • Unauthorized access");
            console.log("   • Critical solvency situations");
            console.log("   • Stale data usage");
            console.log("   • Unbounded gas consumption");
            console.log("=====================================\n");
        });
    });
});
