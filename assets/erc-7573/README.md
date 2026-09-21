# DvP Solidity implementation

## Description

The interfaces in this proposal model a functional transaction scheme to establish a secure *delivery-versus-payment*
across two blockchains, where a) no intermediary is required and b) one of the two chains
can securely interact with a stateless "decryption oracle". Here, *delivery-versus-payment* refers to the exchange of,
e.g., an asset against a payment; however, the concept is generic to make a transfer of one token on one
chain (e.g., the payment) conditional to the successful transfer of another token on another chain (e.g., the asset).

The scheme is realized by two smart contracts, one on each chain.
One smart contract implements the `ILockingContract` interface on one chain (e.g. the "asset chain"), and another smart contract implements the `IDecryptionContract` interface on the other chain (e.g., the "payment chain").
The smart contract implementing `ILockingContract` locks a token (e.g., the asset) on its chain until a presented key's hash or other locking representation matches one of two committed values.
The smart contract implementing `IDecryptionContract`, decrypts one of two keys (via the decryption oracle) conditional to the success or failure of the token transfer (e.g., the payment). A stateless decryption oracle is attached to the chain running `IDecryptionContract` for the decryption.

### Provided Contracts

#### DvP

- `contracts/ILockingContract.sol` - Contract locking transfer with given encrypted keys or hashes.
- `contracts/ILockingContractWithKeyGeneration.sol` - Optional same-chain locking extension that authorizes a decryption contract as the generated-key source.
- `contracts/IDecryptionContract.sol` - Contract performing conditional upon transfer decryption (possibly based on an external oracle).
- `contracts/IDecryptionContractWithKeyGeneration.sol` - Optional extension for asynchronous generation of the encrypted success and failure keys.
- `contracts/IDecryptionContractInceptionCallback.sol` - Optional on-chain notification when asynchronous inception completes.

ERC-7573 does not standardize an application-level `initTransfer` method. Before the first
ERC-7573 call, the application workflow allocates an identifier for each transfer leg and binds
its arbitrary application data as `transaction`. Each implementation treats that `id` as
lifetime-unique and rejects its reuse. Corresponding locking and decryption contracts may use
the same numeric `id` for the two sides of one DvP operation. A group or multi-party identifier
belongs in `transaction`; distinct legs on one implementation still require distinct IDs.

Every transfer term-bearing call supplies `from` and `to` explicitly. `msg.sender` identifies only
the caller and MUST NOT, by itself, determine either participant. Implementations MAY require the
caller to be a participant or an authorized operator. Decryption confirmation and cancellation
repeat the complete context, including the asynchronous callback (or zero), and both key
references. Locking confirmation repeats the transfer context and adds the
other party's outcome-key material. These explicit arguments let each contract require exact
agreement with its immutable inception, so separate inception and confirmation hashes are
unnecessary.

The asynchronous extension uses one `inceptTransfer` signature with an optional callback parameter.
After storing the generated keys and emitting `TransferIncepted`, the decryption contract
passes the unique transfer `id` to a nonzero callback. The callback reads the immutable context
and semantically ordered H/E material through getters keyed by `id`; explicit `exists` and
`available` values distinguish lifecycle state from
empty data. Passing `address(0)` selects an event-driven workflow, but a generated-key
asset lock requires an inception whose callback is that exact asset contract.
After terminal key release, a same-chain decryption contract may best-effort relay the key to
that locking contract. The released-key event remains the recovery path if the relay fails.

#### Decryption Oracle

- `contracts/IKeyDecryptionOracle.sol` - Interface implemented by a decryption oracle proxy contract.
- `contracts/IKeyDecryptionOracleCallback.sol` - Interface to be implemented by a callback receiving the decrypted key.

Oracle request methods return a proxy-scoped `requestId`, and callbacks use that identifier.
The caller-supplied DvP `id` remains request-event context and is not used to route callbacks.

Key generation and verification are atomic, role-tagged batch operations. A verification
request supplies a non-empty `EncryptedKey[]`, where each entry contains a semantic `keyId`
and its encrypted key. A successful callback returns the exact complete set as
`EncryptedHashedKey[]`, under one common receiver and transaction; array position has no
meaning and partial success is forbidden. A one-element batch covers the singular case.
The explicit verification result distinguishes rejection from empty data. Decryption remains
single-key because settlement releases exactly one outcome key.

Batch verification is not, by itself, replay protection. Every key reference in the batch
must authenticate the same unique, one-use settlement context (for example the chain,
decryption contract and lifetime-unique transfer id), the same external transaction/batch id,
and its own key role. A verifier needs verification-only access to every reference; this must
not grant authority to request or fulfill decryption of the failure key.

Despite the historical `encryptedKey` name, a reference need not be confidential ciphertext.
It may be a publicly readable, versioned and signed byte sequence representing an external
settlement. This allows each participant to verify every outcome through its own adapter;
possession or readability of the reference must never itself authorize release of the key.

### Documentation

- `doc/DvP-Seq-Diag.png` - Sequence diagram of the DvP
- `doc/multi-party-dvp.svg` - Sequence diagram of a multi-party-dvp.
