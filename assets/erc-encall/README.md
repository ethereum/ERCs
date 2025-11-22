# Encrypted Hashed Argument Call - Decryption Oracle Solidity Implementation

## Description

The interfaces in this proposal model a generic **function execution with encrypted arguments** using a stateless
*Call Decryption Oracle*.

The scheme separates

1. a reusable, verifiable container for **encrypted-hashed arguments**, and
2. a **call descriptor** specifying who may trigger the execution, which contract and function are called, and which
   arguments are bound via a hash commitment.

A user (or contract) submits

- an `EncryptedHashedArguments` blob (ciphertext + `argsHash`), and
- either a transparent or encrypted `CallDescriptor`,

to a `CallDecryptionOracle` contract. An off-chain operator (the call decryption oracle) then

1. decrypts the call descriptor (if encrypted) and the arguments,
2. verifies that the plaintext arguments match the committed `argsHash`, and
3. calls back into the `CallDecryptionOracle`, which executes the target function with the decrypted arguments.

The receiving contract can verify that the arguments it sees correspond to a previously stored `argsHash`, and may pass
these arguments on to other contracts which can repeat this verification.

This ERC is designed to be compatible with the ERC-7573 **Key Decryption Oracle** pattern: an existing keys oracle
implementation can be extended with this call decryption functionality, or both can be operated as separate services.

### Provided Contracts

#### Call Decryption Oracle

- `contracts/ICallDecryptionOracle.sol`  
  Interface of the call decryption oracle. Defines:
    - `EncryptedHashedArguments`
    - `CallDescriptor`
    - `EncryptedCallDescriptor`
      as well as the events and methods

    - `requestCall`
    - `fulfillCall`.
    - `requestEncryptedCall`
    - `fulfillEncryptedCall`

- `contracts/CallDecryptionOracle.sol`  
  Reference implementation of `ICallDecryptionOracle`. Stores pending requests, emits
  `EncryptedCallRequested` / `TransparentCallRequested` events, and on fulfillment performs a low-level call

  ```solidity
  targetContract.call(abi.encodePacked(selector, argsPlain))
  ```

  after verifying that `keccak256(argsPlain) == argsHash`.

#### Example Target Contract

- `contracts/DummyExecutionTarget.sol`  
  Example target contract that illustrates how a receiver verifies the arguments:

```solidity
  function executeWithVerification(
      bytes32 argsHash,
      uint256 amount,
      address beneficiary
  ) external {
      bytes32 computed = keccak256(abi.encode(amount, beneficiary));
      require(computed == argsHash, "Encrypted args mismatch");

      // Safe use of amount and beneficiary
  }
```

This contract is intended for documentation, testing, and demonstration of integration patterns.

### Documentation

- `doc/encrypted-arguments-transparent-call-flow.svg`  
  Sequence diagram of the encrypted-arguments + transparent-call flow, showing how a contract can store an `argsHash`,
  later resolve it via the call decryption oracle, and verify the arguments in the receiving function.

- `doc/encrypted-arguments-encrypted-call-flow.svg`  
  Sequence diagram of the encrypted-arguments + encrypted-call flow (request/fulfill using `CallDecryptionOracle`).
