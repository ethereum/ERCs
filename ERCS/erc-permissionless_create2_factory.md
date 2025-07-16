---
title: Permissionless CREATE2 Factory
description: A permissionless method for the cross-chain deployment of a universal CREATE2 factory.
author: Nicholas Rodrigues Lordello (@nlordell), Richard Meissner (@rmeissner), Valentin Seehausen (@vseehausen)
discussions-to: https://ethereum-magicians.org/t/multi-chain-deployment-process-for-a-permissionless-contract-factory/24318
status: Draft
type: Standards Track
category: ERC
created: 2025-05-15
requires: 1014, 7702
---

## Abstract

This ERC defines a permissionless and deterministic deployment mechanism across all EVM-compatible chains. It uses the [EIP-7702](./eip-7702.md) `Set Code for EOAs (0x4)` transaction type to deploy a universal CREATE2 factory contract to a fixed address (`0xC0DE207acb0888c5409E51F27390Dad75e4ECbe7`) with known bytecode. The factory can then create any new contract to a deterministic address using the [EIP-1014](./eip-1014.md) `CREATE2 (0xf5)` opcode. It does not require preinstalls, secret keys, or chain-specific infrastructure.

## Motivation

Ensuring that contracts share the same address and code on multiple chains is a hard problem. It is typically done by having a known CREATE2 factory contract at a specific address that can further deterministically deploy new contracts using the `CREATE2 (0xf5)` opcode.

However, there is a bootstrapping problem: how do you get a CREATE2 factory contract with a specific address and code?

### Existing Solutions

There are currently three main approaches to this problem:

#### 1. Nick's Method

Use Nick's method to randomly generate a signature for a transaction **without** [EIP-155](./eip-155.md) replay protection that deploys the CREATE2 factory. Nick's method ensures that there is no known private key for an account that deploys the CREATE2 factory, meaning that the resulting contract will have a deterministic address and code on all chains. This strategy is used by [Arachnid/deterministic-deployment-proxy](https://github.com/Arachnid/deterministic-deployment-proxy), one of the most widely used CREATE2 factory contracts.

**Downsides**:

- It does not work on chains that only accept EIP-155 replay-protected transactions.
- It is sensitive to changes in gas parameters on the target chain since the gas price and limit in the deployment transaction is sealed, and a new one cannot be signed without a private key.
- Reverts due to alternative gas schedules make the CREATE2 factory no longer deployable.

#### 2. Secret Private Key

Keep a carefully guarded secret key and use it to sign transactions to deploy CREATE2 factory contracts. The resulting contract will have a deterministic address and code on all chains where the first transaction of the deployer account is a CREATE2 factory deployment, which can be verified post-deployment to ensure trustlessness. Additionally, this method does not have the same gas sensitivity downsides as Nick's method, as the private key can sign a creation transaction with appropriate gas parameters at the time of execution. This is the strategy used by [safe-global/safe-singleton-factory](https://github.com/safe-global/safe-singleton-factory) and [pcaversaccio/createx](https://github.com/pcaversaccio/createx).

**Downsides**:

- It is permissioned: the party that holds the secret key has the ultimate say on which chains will get the CREATE2 factory deployments.
- This requires carefully guarding a secret key; if it is exposed or lost, deployments are no longer guaranteed on new chains.
- If the first transaction is not a successful CREATE2 factory deployment, then it is no longer possible to have a CREATE2 factory at the common address; this can happen by human error, for example.

#### 3. Preinstalls

Have popular CREATE2 deployment factories deployed on new chains by default. This is, for example, what OP Stack does as part of their [preinstalls](https://github.com/ethereum-optimism/optimism/blob/12c5398a1725a2aafc3e7abb0711cf761a2b20b1/packages/contracts-bedrock/src/libraries/Preinstalls.sol), including the CREATE2 factory contracts mentioned above. This ensures that the CREATE2 factory contracts have known addresses and codes.

**Downsides**:

- It is not standardized nor adopted by all chains.
- It is permissioned as a chain can choose not to include a specific CREATE2 factory contract preinstalled.
- Attempts to standardize this with [RIP-7740](https://github.com/ethereum/RIPs/blob/master/RIPS/rip-7740.md) have not been successful.

### Proposal: Using EIP-7702 Type `0x4` Transactions

This ERC proposes a permissionless alternative fourth mechanism to the existing ones described above with none of their downsides. Additionally, it standardizes a set of deployment parameters for a **universal** CREATE2 factory deployment. This ensures a common CREATE2 factory for the community instead of multiple competing copies with slightly different codes at different addresses. This single CREATE2 factory copy can bootstrap additional deterministic deployment infrastructure (such as the comprehensive CreateX universal contract deployer).

**Benefits**

- Universally applicable: It can be executed on any chain by any user and guarantees a reliable determination of smart contract deployments on any chain.
- Fault resistant: The method is secure against "out of gas" and other errors.
- Permissionless: The universal CREATE2 factory contract can be deployed by anyone.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Parameters

| Parameter                   | Value                                                                |
| --------------------------- | -------------------------------------------------------------------- |
| `DEPLOYER_PRIVATE_KEY`      | `0x942ba639ec667bdded6d727ad2e483648a34b584f916e6b826fdb7b512633731` |
| `CREATE2_FACTORY_INIT_CODE` | `0x7760203d3d3582360380843d373d34f580601457fd5b3d52f33d5260186008f3` |
| `CREATE2_FACTORY_SALT`      | `0x000000000000000000000000000000000000000000000000000000000019e078` |

### Derived Parameters

| Derived Parameter              | Value                                                                |
| ------------------------------ | -------------------------------------------------------------------- |
| `DEPLOYER_ADDRESS`             | `0x962560A0333190D57009A0aAAB7Bfa088f58461C`                         |
| `CREATE2_FACTORY_ADDRESS`      | `0xC0DE945918F144DcdF063469823a4C51152Df05D`                         |
| `CREATE2_FACTORY_RUNTIME_CODE` | `0x60203d3d3582360380843d373d34f580601457fd5b3d52f3`                 |
| `CREATE2_FACTORY_CODE_HASH`    | `0xeac13dde1a2c9b8dc8a7aded29ad0af5d57c811b746f7909ea841cbfc6ef3adc` |

### Definitions

- **Deployer**: The account corresponding to `DEPLOYER_PRIVATE_KEY` with address `DEPLOYER_ADDRESS`.
- **CREATE2 factory contract**: A contract that deploys other contracts with `CREATE2 (0xf5)` opcode, allowing smart contracts to be deployed to deterministic addresses.
- **Bootstrap contract**: The contract that the _deployer_ delegates to in order to deploy the _CREATE2 factory contract_.
- **Bootstrapping code**: The critical code in the _bootstrap contract_ that performs the `CREATE2 (0xf5)` deployment of the _CREATE2 factory contract_.

### Bootstrap Contract

The _bootstrap contract_ MUST execute the following or equivalent _bootstrapping code_ as an EIP-7702 delegation target for the _deployer_ account:

```solidity
bytes memory initCode = CREATE2_FACTORY_INIT_CODE;
bytes32 salt = CREATE2_FACTORY_SALT;
assembly ("memory-safe") {
    create2(0, add(initCode, 32), mload(initCode), salt)
}
```

The _bootstrap contract_ MAY implement additional features such as:

- Abort early if either _CREATE2 factory contract_ is already deployed or the _deployer_ is not correctly delegated to.
  - This can help mitigate gas griefing from the previously described front-running issue.
- Additional verification that the deployment succeeded as expected.
- Emit events to facilitate tracking of either the _bootstrap contract_ or _CREATE2 factory contract_ deployments.

### Deployment Process

1. Deploy a _bootstrap contract_ described in the previous section.
2. Sign an EIP-7702 authorization using the `DEPLOYER_PRIVATE_KEY` delegating to the _bootstrap contract_.
3. Execute an EIP-7702 type `0x4` transaction with the authorization from setup 2; the transaction MUST call `DEPLOYER_ADDRESS` (**either** directly or indirectly) which delegates to the _bootstrap contract_ and MUST perform the `CREATE2 (0xf5)` in the _bootstrapping code_.

Assuming successful execution of the _bootstrapping code_ without reverting in the context of the _deployer_, the _CREATE2 factory contract_ will be deployed to `CREATE2_FACTORY_ADDRESS` with code `CREATE2_FACTORY_RUNTIME_CODE` and code hash `CREATE2_FACTORY_CODE_HASH`.

## Rationale

### Deployment Mechanism

The deployment mechanism was chosen such that it is uniquely parameterized by the `DEPLOYER_ADDRESS` (which itself is derived from the `DEPLOYER_PRIVATE_KEY` and is therefore deterministic), the `CREATE2_FACTORY_INIT_CODE` and the `CREATE2_FACTORY_SALT` which are both fixed and deterministic. Additionally, since the `DEPLOYER_ADDRESS` will deploy the CREATE2 factory contract with the `CREATE2 (0xf5)` opcode, this guarantees that the address and code of the contract are deterministic.

The use of a publicly known private key enables this mechanism, as anyone can permissionlessly generate a delegation signature to **any** bootstrap contract that would cause the `DEPLOYER_ADDRESS` to execute the specified `CREATE2 (0xf5)` operation and deploy the factory contract to a completely deterministic address. Because of the use of `CREATE2 (0xf5)`, the CREATE2 factory will be deployed to `CREATE2_FACTORY_ADDRESS` if and only it is deployed with `CREATE2_FACTORY_INIT_CODE`, thus guaranteeing a deployed code hash of `CREATE2_FACTORY_CODE_HASH`. Additionally, the semantics of `CREATE2 (0xf5)` make it so no transaction executed by `DEPLOYER_ADDRESS` can permanently block the deployment of the CREATE2 factory contract.

One issue with this method is that because the `DEPLOYER_PRIVATE_KEY` is public, anyone can sign alternative delegations or transactions and front-run a legitimate CREATE2 factory deployment. We consider this to not be a serious issue however, as:

1. Doing so does not prevent future deployments - meaning that an attacker can only delay the deployment of the CREATE2 factory with a sustained attack at a gas cost to the attacker.
2. The damage is limited to gas griefing for accounts that are legitimately trying to deploy the CREATE2 factory contract. Furthermore, the reference implementation was coded to minimize the gas griefing damage.
3. In the case of a very persistent malicious actor, their attack can be circumvented by either making use of private transactions or working directly with block builders.

### Use of CREATE2 Factory Contract

This mechanism allows the `DEPLOYER_ADDRESS` to do any `CREATE2 (0xf5)` deployment, so it would be possible to forgo the intermediary CREATE2 factory contract and use the deployer technique for all deployments. There are multiple downsides to this, however:

- All contract deployments are subject to the front-running issue described above, which could become an annoyance
- Concurrent deployments from the deployer are subject to race conditions since EIP-7702 authorizations increase the account nonce. This means that if two deployments are submitted to the mem-pool without knowing about each other, only the first one will actually succeed, because the EIP-7702 authorization in the second transaction is for an outdated nonce. This is not an issue when deployers are trying to deploy the same contract as we propose in this ERC since even if the second delegation and transaction fails, the contract would have been deployed as desired.

### Multiple Transaction Procedure

Unfortunately, EIP-7702 type `0x4` transactions are restricted to `to` values that are not `null`, meaning that you cannot simultaneously deploy the _bootstrap contract_ and delegate to it in a single transaction.

### Choice of Deployer Private Key

The `DEPLOYER_PRIVATE_KEY` was chosen as the private key at derivation path `m/44'/60'/0'/0/0` for the mnemonic `make code code code code code code code code code code coconut`.

### Choice of Salt

The `CREATE2_FACTORY_SALT` was chosen as the **first** salt value starting from `0` such that the CREATE2 factory's [ERC-55](./eip-55.md) checksum address starts with the case sensitive `0xC0DE...` prefix. A verifiable method for mining a vanity address for the CREATE2 factory contract was chosen in order to ensure that the ERC authors did not find a CREATE2 hash collision on the `CREATE2_FACTORY_ADDRESS` that they can exploit at some point in the future.

### CREATE2 Factory Bytecode

The CREATE2 factory has a similar interface to existing implementations. Namely, it accepts `salt || init_code` as input, which is a 32-byte `salt` value concatenated with the `init_code` of the contract to deploy. It will execute a `CREATE2` with the specified `salt` and `init_code`, deploying a contract with `init_code` to `keccak256(0xff || CREATE2_FACTORY_ADDRESS || salt || keccak256(init_code))[12:]`.

Note that this contract returns the address of the created contract padded to 32 bytes. This differs from some existing implementations, but was done to maintain consistency with the 32-byte word size on the EVM (same encoding as `ecrecover` precompile for example). A product of this is that the return data from CREATE2 factory is compatible with the Solidity ABI.

Throughout both the CREATE2 factory contract initialization and runtime code, we use `RETURNDATASIZE (0x3d)` to push `0` onto the stack instead of the dedicated `PUSH0 (0x5f)` opcode. This is done to increase compatibility with chains that support EIP-7702 but not [EIP-3855](./eip-3855.md), while remaining a 1-byte and 2-gas opcode.

The `CREATE2_FACTORY_INIT_CODE` corresponds to the following assembly:

```
### Constructor Code ###

0x0000: PUSH24 0x60203d3d3582360380843d373d34f580601457fd5b3d52f3
                        # Stack: [runcode]                      | Push the CREATE2 factory runtime code
0x0019: RETURNDATASIZE  # Stack: [0; runcode]                   | Push the offset in memory to store the code
0x001a: MSTORE          # Stack: []                             | The runtime code is now in `memory[8:32]`
0x001b: PUSH1 25        # Stack: [24]                           | Push the code length
0x001d: PUSH1 7         # Stack: [8; 24]                        | Push the memory offset of the start of code
0x001f: RETURN          # Stack: []                             | Return the runtime code
```

The `CREATE2_FACTORY_RUNTIME_CODE` corresponds to the following assembly:

```
### Runtime Code ###

# Prepare our stack, push 32, a value we will use a lot and can summon with
# `DUP*` to save on one byte of code (over `PUSH1 32`), and a 0 which will
# be used by either the `RETURN` or `REVERT` branches at the end.
0x0000: PUSH1 32        # Stack: [32]
0x0002: RETURNDATASIZE  # Stack: [0; 32]

# First, load the salt value and compute the actual code size for the CREATE2
# call, this is the calldata length minus 32 for the salt prefix.
                        # Stack: [0; 32]
0x0003: RETURNDATASIZE  # Stack: [0; 0; 32]                     | Push the calldata offset 0 of the `salt` parameter
0x0004: CALLDATALOAD    # Stack: [salt; 0; 32]                  | Load the `salt` from calldata
0x0005: DUP3            # Stack: [32; salt; 0; 32]              | Push 32 to the stack
0x0006: CALLDATASIZE    # Stack: [msg.data.len; 32; salt; ...]  | Followed by the calldata length
0x0007: SUB             # Stack: [code.len; salt; 0; 32]        | Compute `msg.data.length - 32`, which is the length of
                                                                # the init `code`

# Copy the init code to memory offset 0.
                        # Stack: [code.len; salt; 0; 32]
0x0008: DUP1            # Stack: [code.len; .; salt; 0; 32]     | Duplicate the length of the init code
0x0009: DUP5            # Stack: [32; code.len; ...]            | Push the offset in calldata of the code, which is 32
                                                                # as it comes immediately after the 32-byte `salt`; use
                                                                # the 32 value at the bottom of the stack
0x000a: RETURNDATASIZE  # Stack: [0; 32; code.len; ...]         | Push the offset (0) in memory to copy the code to
0x000b: CALLDATACOPY    # Stack: [code.len; salt; 0; 32]        | Copy the init code, `memory[0:code.len]` contains the
                                                                # init `code`

# Deploy the contract.
                        # Stack: [code.len; salt; 0; 32]
0x000c: RETURNDATASIZE  # Stack: [0; code.len; salt; 0; 32]     | Push the offset in memory starting of the start of
                                                                # init `code`, which is 0
0x000d: CALLVALUE       # Stack: [v; 0; code.len; salt; 0; 32]  | Forward the call value to the contract constructor
0x000e: CREATE2         # Stack: [address; 0; 32]               | Do `create2(v, code, salt)`, which leaves the address
                                                                # of the contract on the stack, or 0 if the contract
                                                                # creation reverted

# Verify the deployment was successful and return the address.
                        # Stack: [address; 0; 32]
0x000f: DUP1            # Stack: [address; .; 0; 32]            | Duplicate the address value
0x0010: PUSH1 0x14      # Stack: [0x0014; address; .; 0; 32]    | Push the jump destination offset for the code which
                                                                # handles successful deployments
0x0012: JUMPI           # Stack: [address; 0; 32]               | Jump if `address != 0`, i.e. `CREATE2` succeeded

# CREATE2 reverted.
                        # Stack: [address = 0; 0; 32]
0x0013: REVERT          # Stack: []                             | Revert with empty data `memory[0:0]`

# CREATE2 succeeded.
0x0014: JUMPDEST        # Stack: [address; 0; 32]
0x0015: RETURNDATASIZE  # Stack: [0; address; 0; 32]            | Push the memory offset (0) to store return data at,
                                                                # we use `RETURNDATASIZE` becaues contract creation was
                                                                # successful, and therefore the return data has size 0
0x0016: MSTORE          # Stack: [0; 32]                        | Store the address in memory, `memory[0:32]` contains
                                                                # the `address` left padded to 32-bytes
0x0017: RETURN          # Stack: []                             | Return `memory[0:32]`, i.e. the address
```

## Backwards Compatibility

There are a few backwards compatibility considerations with the new proposal:

1. It requires an EVM chain with EIP-7702 enabled. This means not all chains can use this deployment method.
2. It would deploy yet another CREATE2 factory contract that would need to be adopted by tooling.
3. The proposed CREATE2 factory implementation returns the newly created contract address padded to 32 bytes. This is different to some existing contracts that return unpadded 20-byte address value.

## Forwards Compatibility

Additionally, if new EVM opcodes or transactions are introduced in the future that allow an account to permanently set its code, then this method will no longer work as the deployer account can permanently change its code to a contract that does not have the required bootstrapping code.

If this ERC would gain sufficient adoption, then this may not be an issue as:

- The deployment on Ethereum Mainnet would already exist, and the `DEPLOYER_PRIVATE_KEY` would no longer have any value on Ethereum Mainnet.
- An RIP can be adopted to ensure that `CREATE2_FACTORY_ADDRESS` has code `CREATE2_FACTORY_RUNTIME_CODE`.

## Reference Implementation

We include a reference implementation of a bootstrap contract to which the deployer account can delegate. The reference implementation expects a call to `Bootstrap` to the function `deploy()` in an EIP-7702 type `0x4` transaction including the EIP-7702 authorization delegating `DEPLOYER_ADDRESS` to `Bootstrap` (NOTE: the `Bootstrap` is called as an entry point, instead of calling `DEPLOYER_ADDRESS` directly which allows the contract to do some up-front checks to minimize gas griefing risk):

```solidity
// SPDX-License-Identifier: CC0
pragma solidity ^0.8.29;

contract Bootstrap {
    address private constant _DEPLOYER_ADDRESS = 0x962560A0333190D57009A0aAAB7Bfa088f58461C;
    address private constant _CREATE2_FACTORY_ADDRESS = 0xC0DE945918F144DcdF063469823a4C51152Df05D;
    bytes32 private constant _CREATE2_FACTORY_CODE_HASH = hex"eac13dde1a2c9b8dc8a7aded29ad0af5d57c811b746f7909ea841cbfc6ef3adc";
    bytes private constant _CREATE2_FACTORY_INIT_CODE = hex"7760203d3d3582360380843d373d34f580601457fd5b3d52f33d5260186008f3";
    bytes32 private constant _CREATE2_FACTORY_SALT = hex"000000000000000000000000000000000000000000000000000000000019e078";

    error InvalidDelegation();
    error CreationFailed();

    function deploy() external {
        if (_CREATE2_FACTORY_ADDRESS.codehash == _CREATE2_FACTORY_CODE_HASH) {
            return;
        }

        bytes32 delegation = keccak256(abi.encodePacked(hex"ef0100", this));
        require(_DEPLOYER_ADDRESS.codehash == delegation, InvalidDelegation());

        Bootstrap(_DEPLOYER_ADDRESS).bootstrap();
    }

    function bootstrap() external {
        bytes memory initCode = _CREATE2_FACTORY_INIT_CODE;
        bytes32 salt = _CREATE2_FACTORY_SALT;

        address factory;
        assembly ("memory-safe") {
            factory := create2(0, add(initCode, 32), mload(initCode), salt)
        }

        require(factory == _CREATE2_FACTORY_ADDRESS, CreationFailed());
    }
}
```

A minimal bootstrap contract implementation is also possible (although this has a higher potential for gas griefing). The minimal bootstrap contract expects a call directly to the `DEPLOYER_ADDRESS` in an EIP-7702 type `0x4` transaction including the EIP-7702 authorization delegating `DEPLOYER_ADDRESS` to `MiniBootstrap`:

```solidity
// SPDX-License-Identifier: CC0
pragma solidity ^0.8.29;

contract MiniBootstrap {
    bytes32 private constant _CREATE2_FACTORY_INIT_CODE = hex"7760203d3d3582360380843d373d34f580601457fd5b3d52f33d5260186008f3";
    bytes32 private constant _CREATE2_FACTORY_SALT = hex"000000000000000000000000000000000000000000000000000000000019e078";

    fallback() external {
        assembly ("memory-safe") {
            mstore(0, _CREATE2_FACTORY_INIT_CODE)
            pop(create2(0, 0, 32, _CREATE2_FACTORY_SALT))
        }
    }
}
```

## Security Considerations

It is possible to front-run transactions that invalidate the deployer's EIP-7702 delegation and cause the deployment to fail. This, however, comes at a gas cost to the attacker, with limited benefit beyond delaying the deployment of the CREATE2 factory. Additionally, persistent attackers can be circumvented by either using private transaction queues or working with block builders directly to ensure that the EIP-7702 bootstrapping transaction is not front-run.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
