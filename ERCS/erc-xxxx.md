---
eip: 8027
title: Manual & Recurring Subscription NFTs (SubNFTs)
description: A framework to enable manual and recurring subscription with auto expiration for ERC-721 tokens
author: ant (0xdevant), cygaar (@cygaar)
discussions-to: https://ethereum-magicians.org/t/erc-8027-manual-recurring-subscription-nfts-subnfts/25482
status: Draft
type: Standards Track
category: ERC
created: 2025-09-16
requires: 721
---

## Abstract

This standard is an extension of [EIP-721](./eip-721.md). It proposes a framework and interface for NFTs to enable manual and recurring subscription service with auto expiration i.e. Subscription NFTs (hereinafter SubNFTs). The interface includes functions to renew subscription, signal for recurring subscription by signing via Permit2, charge subscription fee automatically as service provider, and cancel the subscription by revoking Permit2 allowance.

## Motivation

NFTs are commonly used as identity verification on decentralized apps or membership passes to communities, events, and more. However, the current use case for NFTs often falls into either being a lifetime membership that have no expiration dates, or a one-off event ticket for verifying a reservation thus no recurring payments involved in both cases. However for many real-world applications that require paid subscription, they would prefer a middle ground - to keep an account or membership valid until a certain period, or the user stops paying for the subscription.

The most prevalent on-chain application that makes use of the renewable subscription model is the Ethereum Name Service (ENS). Each domain can be renewed for a certain period of time, and expires if payments are no longer made. But there exists no standard currently to allow users to approve a specified ERC20 amount in advance and get automatically charged by service provider periodically to keep their subscription active.

This should be a much more efficient way for both users and the platform - rather than forcing users to pay a huge lump sum to tie them into a long subscription plan, or having users lock a fixed amount of funds in advance waiting to be charged each month - users should just spend their funds as they please, and keep enough funds to be deducted by the service provider for the next cycle of subscription without going through a manual subscription process, basically like a debit card for recurring subscription, and more similar to how an auto subscription would work in web2.

Besides a common interface will make it easier for future projects to develop subscription-based NFTs. In the current Web2 world, it's hard for a user to see or manage all of their subscriptions in one place. With a common standard for subscriptions, it will be easy for a single application to determine the number of subscriptions a user has, see when they expire, and renew/cancel them as requested.

Additionally, as the prevalence of secondary royalties from NFT trading disappears, creators will need new models for generating recurring income. For NFTs that act as membership or access passes, pivoting to a subscription-based model is one way to provide income and also incentivizes issuers to keep providing value to their supporters.

## Specification

The key words “MUST”, “MUST NOT”, “REQUIRED”, “SHALL”, “SHALL NOT”, “SHOULD”, “SHOULD NOT”, “RECOMMENDED”, “MAY”, and “OPTIONAL” in this document are to be interpreted as described in RFC 2119.

```solidity
pragma solidity ^0.8.29;

interface ISubNFT {
    /// @param paymentToken Token to pay for the subscription, use address(0) for native token
    /// @param serviceProvider The address of the service provider to receive the payment
    /// @param interval The interval of each subscription e.g. 30 days in seconds
    /// @param planPrices Array of prices for different plans, the respective index of the price refers to `planIdx`,
    /// length > 1 indicates multiple plans available
    struct SubscriptionConfig {
        address paymentToken;
        address serviceProvider;
        uint64 intervalInSec;
        uint256[] planPrices;
    }

    /// @param planIdx The index of the subscription plan from `planPrices`
    /// @param expiryTs The latest timestamp which the subscription is valid until
    struct Subscription {
        uint128 planIdx;
        uint128 expiryTs;
    }

    /// @notice Emitted when a subscription is extended
    /// @dev When a subscription is extended, the expiration timestamp is extended for `interval * numOfIntervals`
    /// @param tokenId The NFT to extend the subscription for
    /// @param planIdx The plan index to indicate which plan to extend the subscription for
    /// @param expiryTs The new expiration timestamp of the subscription
    event SubscriptionExtended(uint256 indexed tokenId, uint128 planIdx, uint128 expiryTs);

    /// @notice Emitted when a user signals a subscription by signing a permit2 permit
    /// @param tokenId The NFT to signal the subscription for
    /// @param planIdx The plan index to indicate which plan to signal the subscription for
    /// @param numOfIntervals The number of `interval` the user intends to subscribe for
    event AutoSubscriptionSignaled(uint256 indexed tokenId, uint128 planIdx, uint64 numOfIntervals);

    /// @notice Emitted when service provider charges a user for an auto subscription
    /// @dev When a auto subscription is charged, the expiration timestamp is extended for ONE `interval` only
    /// @param tokenId The NFT to charge the auto subscription for
    event AutoSubscriptionCharged(uint256 indexed tokenId);

    /// @notice Emitted when a user cancels the upcoming subscription by revoking permit2 allowance
    /// @dev When a subscription is canceled, the subscription will last until the `expiryTs` timestamp
    /// @param tokenId The NFT to cancel the auto subscription for
    event AutoSubscriptionCancelled(uint256 indexed tokenId);

    /// @notice Manually renews a subscription for an NFT by directly transferring native token or ERC20 token to the service provider
    /// @dev Throws if `tokenId` does not exist
    /// @dev Throws if `planIdx` is not a valid plan index
    /// @dev Throws if `numOfIntervals` is not greater than 0
    /// @dev Throws if the payment is insufficient
    /// @param tokenId The NFT to renew the subscription for
    /// @param planIdx The plan index to indicate which plan to subscribe to
    /// @param numOfIntervals The number of `interval` to extend the subscription for
    function renewSubscription(uint256 tokenId, uint128 planIdx, uint64 numOfIntervals) external payable;

    /// @notice Signals an intent for recurring subscription for an NFT by signing a permit2 permit
    /// @dev When a subscription is signaled, the subscription is not active yet, it indicates the user has approved the contract
    /// to let the service provider charge subscription fee automatically by `interval * numOfIntervals`
    /// @dev Throws if `tokenId` does not exist
    /// @dev Throws if `planIdx` is not a valid plan index
    /// @dev Throws if `numOfIntervals` is not greater than 0
    /// @dev Throws if the expiration of the permit doesn't last until the current timestamp + `interval * numOfIntervals`
    /// @param tokenId The NFT to signal the subscription for
    /// @param planIdx The plan index to indicate which plan to signal the subscription for
    /// @param numOfIntervals The number of `interval` to signal the subscription for
    /// @param permit2Data Data that consists of details of the permit and its signature
    function signalAutoSubscription(
        uint256 tokenId,
        uint128 planIdx,
        uint64 numOfIntervals,
        Permit2Data calldata permit2Data
    ) external;

    /// @notice Charges the subscription for an NFT by transferring ERC20 payment token
    /// from user to the service provider via Permit2, usually called by the service provider automatically
    /// after a subscription is signaled by a user, and recurringly for each `interval`
    /// @dev No access control is required for this function as the spender is restricted to this contract
    /// and receiver is restricted to the service provider
    /// @dev Throws if `tokenId` does not exist
    /// @dev Throws if charges before the `expiryTs` of the subscriber's subscription
    /// @dev Throws if the payment token is not ERC20
    /// @param tokenId The NFT to charge the subscription for
    function chargeAutoSubscription(uint256 tokenId) external;

    /// @notice Cancels the subscription of an NFT by revoking permit2 allowance
    /// @dev Throws if `tokenId` does not exist
    /// @dev When a subscription is canceled, the subscription will last until the `expiryTs` timestamp
    /// @param tokenId The NFT to cancel the subscription for
    function cancelAutoSubscription(uint256 tokenId) external;

    /// @notice Determines whether a NFT's subscription can be renewed
    /// @dev Returns false if `tokenId` does not exist
    /// @param tokenId The NFT to check the renewability of
    /// @return The renewability of a NFT's subscription
    function isRenewable(uint256 tokenId) external view returns (bool);

    /// @notice Gets the expiration date of a NFT's subscription
    /// @dev Returns 0 if `tokenId` does not exist
    /// @param tokenId The NFT to get the expiration date of
    /// @return The `expiryTs` of the NFT's subscription
    function expiresAt(uint256 tokenId) external view returns (uint128);

    /// @notice Gets the price to renew a subscription for a number of `interval` for a given tokenId.
    /// @dev Returns 0 if `numOfIntervals` is 0
    /// @dev Returns 0 if `planIdx` is not a valid plan index
    /// @param planIdx The plan index to indicate which plan to subscribe to
    /// @param numOfIntervals The number of `interval` to renew the subscription for
    /// @return The price to renew the subscription
    function getRenewalPrice(uint128 planIdx, uint64 numOfIntervals) external view returns (uint256);

    /// @notice Gets the subscription details for a given tokenId
    /// @dev Returns empty `Subscription` if `tokenId` does not exist
    /// @param tokenId The NFT to get the subscription for
    /// @return The packed struct of `Subscription`
    function getSubscriptionDetails(uint256 tokenId) external view returns (Subscription memory);

    /// @notice Gets the subscription config
    /// @return The packed struct of `SubscriptionConfig`
    function getSubscriptionConfig() external view returns (SubscriptionConfig memory);
}
```

The `isRenewable(uint256 tokenId)` function MAY be implemented as `pure` or `view`.

The `expiresAt(uint256 tokenId)` function MAY be implemented as `pure` or `view`.

The `getRenewalPrice(uint256 tokenId)` function MAY be implemented as `pure` or `view`.

The `renewSubscription(uint256 tokenId, uint128 planIdx, uint64 numOfIntervals)` function MAY be implemented as `external` or `public`.

The `signalAutoSubscription( uint256 tokenId, uint128 planIdx, uint64 numOfIntervals, Permit2Data calldata permit2Data` function MAY be implemented as `external` or `public`.

The `chargeAutoSubscription(uint256 tokenId)` function MAY be implemented as `external` or `public`.

The `cancelSubscription(uint256 tokenId)` function MAY be implemented as `external` or `public`.

The `SubscriptionExtended` event MUST be emitted whenever a subscription is extended.

The `AutoSubscriptionSignaled` event MUST be emitted whenever a user signals a subscription by signing a permit2 permit.

The `AutoSubscriptionCharged` event MUST be emitted whenever the service provider charges a user for an auto subscription.

The `AutoSubscriptionCancelled` event MUST be emitted whenever a user cancels the upcoming subscription by revoking permit2 allowance.

The `supportsInterface` method MUST return `true` when called with `0xb6795b57`.

## Rationale

This standard aims to make on-chain manual and recurring subscriptions as generic and as easy to integrate with as possible by having minimal configurations for the subscription and compatible with any ERC20s for implementing on-chain subscriptions. It is important to note that in this interface, the service provider should be configuring the subscription during deployment - the standard supports multiple plans to enable tierd subscription plans and only using ERC20 as payment token will enable recurring subscription The NFT itself represents ownership of a subscription, there is no facilitation of how the NFT should be minted or transferred.

### Subscription Management

- **Manual subscription:** Users should be able to renew their subscriptions by directly transferring either native or ERC20 tokens to the service provider hence the `renewSubscription` function. Users will specify the index of subscription plan i.e. `planIdx` and the number of interval to subscribe for i.e. `numOfIntervals`.

- **Recurring subscription:** Users will start by signing a Permit2 permit to signal the service provider their intent for recurring subscription hence the `signalAutoSubscription` - at this stage the subscription is not active yet, it just indicates the user has approved this contract the total funds needed for the subscription. The service provider will then be able to charge subscription fee automatically by `interval` via `chargeAutoSubscription` to start the subscription for users, no extra subscription fee should be sent to service provider as per the standard's implementation. If the users don't want to continue the subscription they can use `cancelAutoSubscription` to revoke Permit2 allowance, or they can just directly move the funds out from the wallet they signed the permit with.

- `expiresAt` function allows users and applications to directly confirm the validity of a SubNFT by checking its expiration date, and `getSubscriptionDetails` function will get both the expiration date and the subscription plan the SubNFT belongs to.

- `getRenewalPrice` helps users and applications to calculate the price of the subscription given the plan it belongs and the number of intervals the subscription will continue for.

- `isRenewable` function gives users and applications the information whether a subscription for a certain NFT or all NFTs could be renewed once expired.

- `getSubscriptionConfig` will give users and applications the information about the configuration of the subscription such as which payment token, which service provider will receive the subscription fee, how long is each interval is, and the price for each plan.

- Finally it's important to know that only using ERC20s as payment token can enable recurring subscription as we cannot directly transfer native token on behalf of users without introducing external dependencies

### Easy Integration

Since this standard is fully EIP-721 compliant, existing protocols will be able to facilitate the transfer of SubNFTs out of the box. With only a minimal configuration and few functions to add, protocols will be able to enable manual or recurring subscription services, fully manage all SubNFTs' subscriptions, check whether a subscription is expired, and decide whether it can be renewed etc.

### Compatible with any ERC20s

In order to support any ERC20s for recurring subscription, this standard integrates with Permit2 - a mechanism introduced by Uniswap to integrate Permit-like token approval with any ERC20s to allow users approve the contract in advance by signing a EIP-712 signature that expires at a certain time the user desires to subscribe until.

## Backwards Compatibility

This standard can be fully EIP-721 compatible by adding an extension function set, and payment can be integrated with any ERC20s out of the box.

The new functions introduced in this standard add minimal overhead to the existing EIP-721 interface, which should make adoption straightforward and quick for developers.

## Test Cases

The following tests are based on Foundry.

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IPermit2} from "@permit2/interfaces/IPermit2.sol";

import {DeployPermit2} from "./utils/DeployPermit2.sol";
import {Permit2Utils} from "./utils/Permit2Utils.sol";
import {SubNFTMock} from "../src/mocks/SubNFTMock.sol";
import {ISubNFT} from "../src/ISubNFT.sol";

contract SubNFTTest is Test, Permit2Utils {
    address[] users = new address[](2);
    address serviceProvider = makeAddr("serviceProvider");

    // ...

    function setUp() public {
        uint256[] memory planPrices = new uint256[](1);
        planPrices[0] = defaultPrice;

        permit2 = IPermit2(deployPermit2.deployPermit2());
        PERMIT2_DOMAIN_SEPARATOR = permit2.DOMAIN_SEPARATOR();
        testERC20 = new TestERC20();

        ISubNFT.SubscriptionConfig memory subscriptionConfig = ISubNFT.SubscriptionConfig({
            paymentToken: address(testERC20),
            serviceProvider: serviceProvider,
            intervalInSec: defaultInterval,
            planPrices: planPrices
        });
        subNFT = new SubNFTMock("SubNFTMock", "SubNFT", subscriptionConfig, address(permit2));

        setUpUsers();
        vm.warp(0);
    }

    function testRenewSubscription_ERC20Payment() public {
        uint256 user1BalanceBefore = testERC20.balanceOf(users[0]);
        uint256 serviceProviderBalanceBefore = testERC20.balanceOf(serviceProvider);

        vm.startPrank(users[0]);
        testERC20.approve(address(subNFT), type(uint256).max);
        vm.expectEmit(true, true, false, true);
        emit ISubNFT.SubscriptionExtended(tokenId, defaultPlanIdx, defaultInterval * defaultNumOfIntervals);
        subNFT.renewSubscription(tokenId, defaultPlanIdx, defaultNumOfIntervals);
        vm.stopPrank();

        uint256 user1BalanceAfter = testERC20.balanceOf(users[0]);
        uint256 serviceProviderBalanceAfter = testERC20.balanceOf(serviceProvider);

        assertEq(subNFT.getSubscriptionDetails(tokenId).planIdx, defaultPlanIdx);
        assertEq(subNFT.expiresAt(tokenId), defaultInterval * defaultNumOfIntervals);
        assertEq(user1BalanceAfter, user1BalanceBefore - defaultPrice * defaultNumOfIntervals);
        assertEq(serviceProviderBalanceAfter, serviceProviderBalanceBefore + defaultPrice * defaultNumOfIntervals);
    }

    function testSignalAutoSubscription() public {
        uint256 totalAmount = defaultPrice * defaultNumOfIntervals;

        IPermit2.PermitSingle memory permitSingle = defaultERC20PermitAllowance(
            address(testERC20),
            uint160(totalAmount),
            uint48(block.timestamp + defaultInterval * defaultNumOfIntervals),
            uint48(defaultNonce),
            address(subNFT)
        );

        ISubNFT.Permit2Data memory permit2Data = ISubNFT.Permit2Data({
            permitSingle: permitSingle,
            signature: getPermitSignature(permitSingle, user1PrivateKey, PERMIT2_DOMAIN_SEPARATOR)
        });

        vm.prank(users[0]);
        vm.expectEmit(true, true, false, true);
        emit ISubNFT.AutoSubscriptionSignaled(tokenId, defaultPlanIdx, defaultNumOfIntervals);
        subNFT.signalAutoSubscription(tokenId, defaultPlanIdx, defaultNumOfIntervals, permit2Data);

        (uint160 amount, uint48 expiration, uint48 nonce) =
            permit2.allowance(users[0], address(testERC20), address(subNFT));
        assertEq(amount, totalAmount);
        assertEq(expiration, block.timestamp + defaultInterval * defaultNumOfIntervals);
        assertEq(nonce, defaultNonce + 1);
    }


    function testChargeAutoSubscription() public {
        testSignalAutoSubscription();
        vm.warp(1);

        uint256 user1BalanceBefore = testERC20.balanceOf(users[0]);
        uint256 serviceProviderBalanceBefore = testERC20.balanceOf(serviceProvider);

        vm.prank(users[1]);
        vm.expectEmit(true, true, false, true);
        emit ISubNFT.AutoSubscriptionCharged(tokenId);
        subNFT.chargeAutoSubscription(tokenId);

        uint256 user1BalanceAfter = testERC20.balanceOf(users[0]);
        uint256 serviceProviderBalanceAfter = testERC20.balanceOf(serviceProvider);

        assertEq(subNFT.expiresAt(tokenId), defaultInterval * 1 + 1);
        assertEq(user1BalanceAfter, user1BalanceBefore - defaultPrice);
        assertEq(serviceProviderBalanceAfter, serviceProviderBalanceBefore + defaultPrice);

        (uint160 amount, uint48 expiration, uint48 nonce) =
            permit2.allowance(users[0], address(testERC20), address(subNFT));
        // 1 month of subscription is charged so deduct 1 month
        assertEq(amount, defaultPrice * defaultNumOfIntervals - defaultPrice);
        assertEq(expiration, block.timestamp + defaultInterval * defaultNumOfIntervals - 1);
        assertEq(nonce, defaultNonce + 1);
    }
}
```

## Reference Implementation

### `SubNFT.sol`

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.29;

contract SubNFT is ERC721, ISubNFT {
    IPermit2 public immutable PERMIT2;

    mapping(uint256 tokenId => Subscription) internal _subscriptions;

    SubscriptionConfig internal _subscriptionConfig;

    constructor(
        string memory name_,
        string memory symbol_,
        SubscriptionConfig memory subscriptionConfig,
        address permit2
    ) ERC721(name_, symbol_) {
        _subscriptionConfig = subscriptionConfig;
        PERMIT2 = IPermit2(permit2);
    }

    /* ONE-OFF SUBSCRIPTION */

    function renewSubscription(uint256 tokenId, uint128 planIdx, uint64 numOfIntervals) external payable virtual {
        SubscriptionConfig memory config = _subscriptionConfig;
        _ensureValidInputs(tokenId, planIdx, config.planPrices.length, numOfIntervals);

        uint256 planPrice = _calcRenewalPrice(config.planPrices[planIdx], numOfIntervals);
        if (config.paymentToken == address(0)) {
            require(msg.value == planPrice, InsufficientPayment());
            payable(config.serviceProvider).transfer(planPrice);
        } else {
            IERC20(config.paymentToken).transferFrom(msg.sender, config.serviceProvider, planPrice);
        }

        _extendSubscription(tokenId, planIdx, config.intervalInSec, numOfIntervals);
    }

    /* RECURRING SUBSCRIPTION */

    function signalAutoSubscription(
        uint256 tokenId,
        uint128 planIdx,
        uint64 numOfIntervals,
        Permit2Data calldata permit2Data
    ) external virtual {
        SubscriptionConfig memory config = _subscriptionConfig;
        _ensureValidInputs(tokenId, planIdx, config.planPrices.length, numOfIntervals);

        _ensureValidPermit(
            permit2Data.permitSingle,
            config.paymentToken,
            _calcRenewalPrice(config.planPrices[planIdx], numOfIntervals),
            config.intervalInSec,
            numOfIntervals
        );

        PERMIT2.permit(msg.sender, permit2Data.permitSingle, permit2Data.signature);

        emit AutoSubscriptionSignaled(tokenId, planIdx, numOfIntervals);
    }

    function chargeAutoSubscription(uint256 tokenId) external virtual {
        require(_exists(tokenId), InvalidTokenId());
        Subscription memory subscription = _subscriptions[tokenId];
        require(block.timestamp > subscription.expiryTs, ChargeTooEarly());

        SubscriptionConfig memory config = _subscriptionConfig;
        require(config.paymentToken != address(0), OnlyERC20ForAutoRenewal());

        // NOTE: only charge for one interval to keep the subscription automatic
        try PERMIT2.transferFrom(
            ownerOf(tokenId),
            config.serviceProvider,
            uint160(config.planPrices[subscription.planIdx]),
            config.paymentToken
        ) {
            _extendSubscription(tokenId, subscription.planIdx, config.intervalInSec, 1);
            emit AutoSubscriptionCharged(tokenId);
        } catch {
            revert TransferFailed();
        }
    }

    function cancelAutoSubscription(uint256 tokenId) external virtual {
        require(_exists(tokenId), InvalidTokenId());
        SubscriptionConfig memory config = _subscriptionConfig;
        IPermit2.TokenSpenderPair[] memory approvals = new IPermit2.TokenSpenderPair[](1);
        approvals[0] = IAllowanceTransfer.TokenSpenderPair(config.paymentToken, config.serviceProvider);

        PERMIT2.lockdown(approvals);

        emit AutoSubscriptionCancelled(tokenId);
    }

    /* INTERNAL CHECKS */

    function _ensureValidPermit(
        IPermit2.PermitSingle memory permitSingle,
        address paymentToken,
        uint256 price,
        uint64 interval,
        uint64 numOfIntervals
    ) internal virtual {
        IPermit2.PermitSingle memory permit = permitSingle;
        require(permit.details.token == paymentToken, PaymentTokenMismatch());
        require(permit.details.amount == price, InsufficientPayment());
        require(permit.details.expiration >= block.timestamp + interval * numOfIntervals, AllowanceExpireTooEarly());
        require(permit.spender == address(this), InvalidSpender());
    }

    function _ensureValidInputs(uint256 tokenId, uint128 planIdx, uint256 numOfPlans, uint64 numOfIntervals) internal virtual {
        require(_exists(tokenId), InvalidTokenId());
        require(planIdx < numOfPlans, InvalidPlanIdx());
        require(numOfIntervals > 0, InvalidNumOfIntervals());
    }

    /* GETTERS */

    function isRenewable(uint256 tokenId) external view virtual returns (bool) {
        return true;
    }

    function expiresAt(uint256 tokenId) external view virtual returns (uint128) {
        return _subscriptions[tokenId].expiryTs;
    }

    function getRenewalPrice(uint128 planIdx, uint64 numOfIntervals) external view virtual returns (uint256) {
        return _calcRenewalPrice(_subscriptionConfig.planPrices[planIdx], numOfIntervals);
    }

    function getSubscriptionDetails(uint256 tokenId) external view virtual returns (Subscription memory) {
        return _subscriptions[tokenId];
    }

    function getSubscriptionConfig() external view virtual returns (SubscriptionConfig memory) {
        return _subscriptionConfig;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(ISubNFT).interfaceId || super.supportsInterface(interfaceId);
    }
}
```

## Security Considerations

- This EIP standard does not affect ownership of an NFT
- When integrating with permit-like token approval, to ensure no extra subscription fee would be sent to the service provider, caution should be taken to make sure the spender of the permit is restricted to the SubNFT contract, receiver is restricted to the service provider, and `chargeAutoSubscription` can only be called by each cycle of interval. (details of the implementation can be referenced from the `_ensureValidPermit` checking and `chargeAutoSubscription` above)
- In situation where service provider is charging but the user either has not enough allowance or not enough payment tokens after signing the permit, a graceful exit is suggested by using a try-catch in `chargeAutoSubscription` like above.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
