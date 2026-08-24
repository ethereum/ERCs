// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SlippageBoundedSwap} from "../src/SlippageBoundedSwap.sol";
import {ISlippageBoundedSwap, SlippagePolicy} from "../src/ISlippageBoundedSwap.sol";
import {ChainlinkQuoteOracle} from "../src/adapters/ChainlinkQuoteOracle.sol";

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @dev Test router with a live reference. `_route` delivers `nextOut` of the real output token to the
/// recipient from a pre-funded source, so the guard measures a genuine balance delta on the fork.
contract ForkTestSwap is SlippageBoundedSwap {
    uint256 public nextOut;
    address public source;

    function configure(uint256 out, address src) external {
        nextOut = out;
        source = src;
    }

    function _route(address, address tokenOut, uint256, address recipient, bytes calldata)
        internal
        override
    {
        IERC20(tokenOut).transferFrom(source, recipient, nextOut);
    }
}

/// Run with a mainnet RPC:  ETH_RPC_URL=<url> forge test --match-contract ForkSlippageBoundedTest -vv
/// A free public endpoint works, e.g. https://ethereum-rpc.publicnode.com
contract ForkSlippageBoundedTest is Test {
    address constant RECIPIENT = address(0xBEEF);
    address constant ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; // Chainlink ETH/USD, mainnet
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USD side (USD ~ USDC), 6 decimals

    ForkTestSwap internal swapc;
    ChainlinkQuoteOracle internal oracle;
    address internal source = address(0x5011);

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        swapc = new ForkTestSwap();
        // WETH 18 decimals, USD side 6 decimals, tolerate a 1 day feed lag.
        oracle = new ChainlinkQuoteOracle(ETH_USD_FEED, WETH, USDC, 18, 6, 1 days);
        // Fund the venue source with USDC and let the router pull the settled fill.
        deal(USDC, source, 1_000_000e6);
        vm.prank(source);
        IERC20(USDC).approve(address(swapc), type(uint256).max);
    }

    function _policy(uint32 maxDeviationBps, uint256 hardFloor) internal view returns (SlippagePolicy memory) {
        return SlippagePolicy({
            quoteOracle: address(oracle),
            expectedCostBps: 0,
            maxDeviationBps: maxDeviationBps,
            hardFloor: hardFloor
        });
    }

    function test_fork_floorDerivedFromLiveChainlinkPrice() public {
        // Live reference: 1 WETH priced by the real Chainlink ETH/USD feed, in 6-decimal USD.
        uint256 ref = oracle.getQuote(1e18, WETH, USDC);
        assertGt(ref, 0, "no live reference");
        emit log_named_uint("live 1 WETH reference (1e6 USD)", ref);

        uint256 floor = ref * 9900 / 10000; // 1% tolerance, computed from the live reference

        // Exactly at the floor passes, and the guard measured a real USDC balance delta at the
        // recipient rather than at the executor.
        swapc.configure(floor, source);
        uint256 out = swapc.swapWithPolicy(WETH, USDC, 1e18, RECIPIENT, _policy(100, 0), "");
        assertEq(out, floor);
        assertEq(IERC20(USDC).balanceOf(RECIPIENT), floor);
        assertEq(IERC20(USDC).balanceOf(address(swapc)), 0);

        // One unit below the live-derived floor reverts.
        swapc.configure(floor - 1, source);
        vm.expectRevert(abi.encodeWithSelector(ISlippageBoundedSwap.SlippageExceeded.selector, floor - 1, floor));
        swapc.swapWithPolicy(WETH, USDC, 1e18, RECIPIENT, _policy(100, 0), "");
    }
}
