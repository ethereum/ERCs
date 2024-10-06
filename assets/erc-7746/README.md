# References for ERC-7746

In this directory you can find a reference implementation of the ILayer interface and a sample MockERC20 contract.

In this test, a [Protected.sol](./test/Protected.sol) contract is protected by a [RateLimitLayer.sol](./test/RateLimitLayer.sol) layer. The RateLimitLayer implements the ILayer interface and enforces a rate which client has configured.
The Drainer simulates a vulnerable contract that acts in a malicious way. In the `test.ts` The Drainer contract is trying to drain the funds from the Protected contract. It is assumed that Protected contract has bug that allows partial unauthorized access to the state.
The RateLimitLayer is configured to allow only 10 transactions per block from same sender. The test checks that the Drainer contract is not able to drain the funds from the Protected contract.