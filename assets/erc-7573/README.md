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

#### Decryption Oracle

- `contracts/IDecryptionOracle.sol` - Interface implemented by a decryption oracle proxy contract.
- `contracts/IDecryptionOracleCallback.sol` - Interface to be implemented by a callback receiving the decrypted key.

### Documentation

- `doc/DvP-Seq-Diag.png` - Sequence diagram of the DvP
- `doc/multi-party-dvp.svg` - Sequence diagram of a multi-party-dvp.

