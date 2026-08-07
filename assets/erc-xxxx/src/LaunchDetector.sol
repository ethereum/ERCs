// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ILaunchDetector} from "./ILaunchDetector.sol";
import {LaunchEscrow} from "./LaunchEscrow.sol";
import {ILaunchDirectory} from "./ILaunchDirectory.sol";
import {SignalProbe} from "./SignalProbe.sol";
import {IERC20} from "./IERC20.sol";
import {SignalVector} from "./LaunchAbuseTypes.sol";

/// @title Reference detector.
/// @notice Derives every signal it can from chain state and carries the rest
///         through from the off-chain service, marked unavailable where the
///         service could not establish them.
/// @dev This is the half of a detection service that anyone can re-run. The
///      other half, funding-ancestry clustering over historical transfers, is
///      an indexing problem and is out of scope for a contract.
contract LaunchDetector is ILaunchDetector {
    /// @dev Domain tags keeping leaf hashes and internal node hashes disjoint.
    bytes1 internal constant LEAF_DOMAIN = 0x00;
    bytes1 internal constant NODE_DOMAIN = 0x01;
    /// @dev SCSTG "Detecting Unbounded Loops": the fold is bounded so a caller
    ///      cannot turn it into a gas exhaustion vector.
    uint256 internal constant MAX_LEAVES = 1024;

    uint16 internal constant NA16 = type(uint16).max;
    uint32 internal constant NA32 = type(uint32).max;

    ILaunchDirectory public immutable directory;

    constructor(ILaunchDirectory directory_) {
        require(address(directory_) != address(0), "zero directory");
        directory = directory_;
    }

    /// @inheritdoc ILaunchDetector
    function observe(
        bytes32 launchId,
        address token,
        ChainInputs calldata c,
        OffChainInputs calldata o
    ) external view returns (SignalVector memory v) {
        // Carried through untouched: the service is accountable for these, and
        // a sentinel here means it did not establish them rather than that it
        // checked and found nothing.
        v.insiderAllocationShare = o.insiderAllocationShare;
        v.sniperConcentration    = o.sniperConcentration;
        v.priorUpheldClaims      = o.priorUpheldClaims;
        v.washTradeRatio         = o.washTradeRatio;

        // Derived from the token contract.
        v.privilegedPowers = SignalProbe.privilegedPowers(token);

        // Derived from the deployer's remaining holdings.
        v.deployerSupplyShare = _supplyShare(token, c.deployerWallets);
        v.deployerSellRatio = c.deployerAllocation == 0
            ? NA16
            : SignalProbe.sellRatio(token, c.deployerWallets, c.deployerAllocation);

        // Derived from the pool.
        v.lpLockedShare = c.lpToken == address(0)
            ? NA16
            : SignalProbe.lockedShare(c.lpToken, c.lockSinks);
        v.lpLockRemaining = c.lpToken == address(0) ? NA32 : c.lpLockRemaining;
        v.liquidityRemoved = SignalProbe.liquidityRemoved(c.peakLiquidity, c.currentLiquidity);

        // Supply minted after launch, which is dilution actually exercised
        // rather than a mint function merely retained.
        v.supplyInflation = _inflation(token, c.initialSupply);

        // Derived from the escrow that holds the launch.
        v.proceedsWithdrawnShare = _withdrawnShare(launchId);
    }

    /// @dev Supply expansion since the window opened, in bps of the original.
    ///      A contraction reads as no dilution rather than as a negative.
    function _inflation(address token, uint256 initialSupply) internal view returns (uint16) {
        if (initialSupply == 0) return NA16;
        uint256 now_ = IERC20(token).totalSupply();
        if (now_ <= initialSupply) return 0;
        return SignalProbe.toBps(now_ - initialSupply, initialSupply);
    }

    /// @dev Reads the escrow the directory attributes the launch to, so the
    ///      figure cannot be supplied by the party under examination.
    function _withdrawnShare(bytes32 launchId) internal view returns (uint16) {
        address escrow = directory.escrowOf(launchId);
        if (escrow == address(0)) return NA16;

        // Only the release ratio is scored; the other fields are deliberately
        // discarded rather than read into unused locals.
        // slither-disable-next-line unused-return
        (, , uint256 proceeds, uint256 released, ) =
            LaunchEscrow(payable(escrow)).launchInfo(launchId);
        if (proceeds == 0) return NA16;
        return SignalProbe.toBps(released, proceeds);
    }

    /// @dev The external reads inside the loop are bounded at 32 wallets, which
    ///      is what keeps a caller from turning this view into a gas bomb.
    // slither-disable-next-line calls-loop
    function _supplyShare(address token, address[] calldata wallets) internal view returns (uint16) {
        if (wallets.length == 0) return NA16;
        require(wallets.length <= 32, "too many wallets");

        uint256 supply = IERC20(token).totalSupply();
        if (supply == 0) return NA16;

        uint256 held = 0;
        for (uint256 i = 0; i < wallets.length; ++i) {
            held += IERC20(token).balanceOf(wallets[i]);
        }
        return SignalProbe.toBps(held, supply);
    }

    /// @inheritdoc ILaunchDetector
    /// @dev The `0x00` prefix separates the leaf domain from the internal-node
    ///      domain. Without it both are bare 32-byte keccak outputs, and an
    ///      internal node can be presented as a leaf: the classic Merkle
    ///      second-preimage attack, which would let a detector prove membership
    ///      of evidence that was never in the set.
    function evidenceLeaf(
        uint256 blockNumber,
        bytes32 txHash,
        uint256 logIndex,
        bytes32 fieldId,
        bytes32 value
    ) external view returns (bytes32) {
        return keccak256(
            abi.encode(LEAF_DOMAIN, block.chainid, blockNumber, txHash, logIndex, fieldId, value)
        );
    }

    /// @inheritdoc ILaunchDetector
    /// @dev Ordered pairwise fold. Order is part of the commitment, so a report
    ///      and its verifier must agree on it; an unordered fold would let a
    ///      detector permute leaves to reach a different root from the same set.
    function evidenceRoot(bytes32[] calldata leaves) external pure returns (bytes32) {
        require(leaves.length > 0, "no evidence");
        require(leaves.length <= MAX_LEAVES, "too many leaves");
        uint256 n = leaves.length;
        bytes32[] memory level = new bytes32[](n);
        for (uint256 i = 0; i < n; ++i) level[i] = leaves[i];

        while (n > 1) {
            uint256 w = 0;
            for (uint256 i = 0; i < n; i += 2) {
                level[w++] = (i + 1 < n)
                    ? keccak256(abi.encode(NODE_DOMAIN, level[i], level[i + 1]))
                    : level[i]; // odd leaf is promoted, never duplicated
            }
            n = w;
        }
        return level[0];
    }
}
