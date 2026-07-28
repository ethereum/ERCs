# DvP Solidity implementation

## Description

The interfaces in this proposal model a functional transaction scheme to establish a secure *delivery-versus-payment*
across two blockchains, where a) no intermediary is required and b) one of the two chains
can securely interact with a stateless "decryption oracle". Here, *delivery-versus-payment* refers to the exchange of,
e.g., an asset against a payment; however, the concept is generic to make a transfer of one token on one
chain (e.g., the payment) conditional to the successful transfer of another token on another chain (e.g., the asset).

The scheme is realized by two smart contracts, one on each chain.
One smart contract implements the `ILockingContract` interface on one chain (e.g. the "asset chain"), and another smart contract implements the `IDecryptionContract` interface on the other chain (e.g., the "payment chain").
The smart contract implementing `ILockingContract` locks a token (e.g., the asset) on its chain until a key is presented to encrypt to one of two given values.
The smart contract implementing `IDecryptionContract`, decrypts one of two keys (via the decryption oracle) conditional to the success or failure of the token transfer (e.g., the payment). A stateless decryption oracle is attached to the chain running `IDecryptionContract` for the decryption.

### Provided Contracts

#### DvP

- `contracts/ILockingContract.sol` - Contract locking transfer with given encrypted keys or hashes.
- `contracts/IDecryptionContract.sol` - Contract performing conditional upon transfer decryption (possibly based on an external oracle).
- `contracts/IDecryptionContractWithKeyGeneration.sol` - Optional extension for asynchronous generation of the encrypted success and failure keys.
- `contracts/IDecryptionContractInceptionCallback.sol` - Optional on-chain notification when asynchronous inception completes.

Both decryption-contract inception variants return an `inceptionHash` of the canonical inception call.
Once the encrypted success and failure keys are immutable, the decryption contract derives a
`confirmationHash` from the inception hash and both keys. Confirmation supplies this
second hash without repeating the transfer parameters. Finalization uses the confirmed DvP
identifier, while cancellation retains the original `inceptionHash` as its exact-inception guard.

The asynchronous extension uses one `inceptTransfer` signature with an optional callback parameter.
After storing the generated keys and `confirmationHash` and emitting `TransferIncepted`,
the decryption contract passes both hashes to a nonzero callback. Passing `address(0)`
selects an event-driven off-chain workflow without callback delivery.

#### Decryption Oracle

- `contracts/IKeyDecryptionOracle.sol` - Interface implemented by a decryption oracle proxy contract.
- `contracts/IKeyDecryptionOracleCallback.sol` - Interface to be implemented by a callback receiving the decrypted key.

Oracle request methods return a proxy-scoped `requestId`, and callbacks use that identifier.
The caller-supplied DvP `id` remains request-event context and is not used to route callbacks.

### Documentation

- `doc/DvP-Seq-Diag.png` - Sequence diagram of the DvP
- `doc/multi-party-dvp.svg` - Sequence diagram of a multi-party-dvp.
