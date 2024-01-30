---
eip: X
title: Quantum Supremacy Oracle
author: Nicholas Papadopoulos (@nikojpapa), Danny Ryan (@djrtwo)
discussions-to: 
status: Draft
type: Standards Track
category: ERC
created: 2023-06-26
requires: [ERC-2470]
---

## Abstract

This proposal introduces a smart contract containing a classically intractable puzzle that is expected to only be able to be solved using quantum computers.
The contract is funded with ETH, which can only be retrieved by solving the problem.
On-chain applications can then watch this contract to be aware of the quantum advantage milestone of solving this puzzle.
For example, Ethereum smart contract wallets can, using custom verification schemes such as those based on [ERC-4337](./eip-4337.md), watch this contract and fall back to a quantum secure signature verification scheme if and when it is solved.

The contract, then, serves the two purposes of (1) showing proof of a strict quantum supremacy[^1] that is strong enough to 
indicate concerns in RSA and ECDSA security, and (2) acting as an indicator to protect Ethereum assets by triggering quantum-secure 
signature verification schemes.

## Motivation

Quantum supremacy[^1] is a demonstration of a quantum computer solving a problem that would take a classical computer an infeasible amount of time to solve.
Previous attempts have been made to demonstrate quantum supremacy, e.g. Kim[^2], Arute[^3] and Morvan[^4], 
but they have been refuted or at least claimed to have no practical benefit, e.g. Begusic and Chan[^5], Pednault[^6], 
and a quote from Sebastian Weidt (The Telegraph, "Supercomputer makes calculations in blink of an eye that take rivals 47 years", 2023).
Quantum supremacy, by its current definition, is irrespective of the usefulness of the problem.
This EIP, however, focuses on a stricter definition of a problem that indicates when an adversary may soon or already be able to bypass current Ethereum cryptography standards.
This contract serves as trustless, unbiased proof of this strong quantum supremacy by generating a classically intractable problem on chain, 
to which even the creator does not know the solution.

Since quantum computers are expected[^7] to break current security standards,
Ethereum assets are at risk. However, implementing quantum-secure
protocols can be costly and complicated.
In order to delay unnecessary costs, Ethereum assets can continue using current cryptographic standards and only fall back
to a quantum-secure scheme when there is reasonable risk of security failure due to quantum computers.
Therefore, this contract can serve to protect one's funds on Ethereum by acting as a trigger that activates when 
strong quantum supremacy has been achieved by solving the classically intractable puzzle.

## Specification

### Parameters

- In this contract, a "lock" refers to a generated puzzle for which a solution must be provided 
in order to withdraw funds and mark the contract as solved.

| Parameter                 | Value         |
|---------------------------|---------------|
| `BIT_SIZE_OF_PRIMES`      | `1,024`       |
| `EIP_X_SINGLETON_ADDRESS` | `TBD`         |
| `MINIMUM_GAS_PAYOUT`      | `600,000,000` |
| `NUMBER_OF_LOCKS`         | `119`         |

### Puzzle

The puzzles that this contract generates are of prime factorization,
where given a positive integer _n_, the objective is to find the set of prime numbers whose product is equal to _n_.

### Requirements

- This contract MUST generate each of the `NUMBER_OF_LOCKS` locks by generating an integer of exactly `3 * BIT_SIZE_OF_PRIMES` random bits.
- This contract MUST allow someone to provide the prime factorization of any lock.
  If it is the correct solution and solves the last unsolved lock, then this contract MUST send all of its ETH to the solver and mark a publicly readable flag to indicate that this contract has been solved.

### Deployment method

- The contract MUST be deployed as a Singleton ([ERC-2470]).
- After deploying the contract with parameters of `NUMBER_OF_LOCKS` locks, each probabilistically generating an integer composed
  of at least two `BIT_SIZE_OF_PRIMES`-bit primes, the contract's `triggerLockAccumulation()` method SHALL be called repeatedly until `generationIsDone == true`, i.e. all bits have been generated.

### Providing solutions

- The solution for each lock SHALL be provided separately.
- Providing solutions MUST follow a commit-reveal scheme to prevent front running.
- This scheme MUST require one day between commit and reveal.

### Rewarding the solver

Upon solving the final solution,
  - All funds in the contract MUST be sent to the solver
  - The `solved` flag MUST be set to `true`
  - Subsequent transactions to commit, reveal, or add funds to the contract MUST be reverted.

### Bounty funds

- Funds covering at least `MINIMUM_GAS_PAYOUT` gas SHALL be sent to the contract as a bounty. As a rough estimate for an example, if the current market price is 23.80 Gwei per gas, the contract SHALL have at least 14.28 ETH as a bounty. 
  The funds must be updated to cover this amount as the value of gas increases.
- The contract MUST accept any additional funds from any account as a donation to the bounty.

## Rationale

### Puzzle

Prime factorization has a known, efficient, quantum solution[^8]
but is widely believed to be intractable for classical computers. This, then, reliably serves as a test for strong quantum supremacy since
finding a solution to this problem should only be doable by a quantum computer.

### Bounty Funds

The solver SHALL be reimbursed at least the cost of verifying the puzzle solutions. Therefore, to estimate the cost, an estimate
can be calculated by providing the solution of a known factorization. 
The expected number of prime factors is on the order of log(log(_n_))[^9],
so the expected number of prime factors of a 3072-bit integer is less than 12. 

Deploying a contract with 119 locks of a provided 3072-bit integer having 16 factors, then providing that solution for
each of them, resulted in a cost of 583,338,223 gas. Providing a solution for a single lock cost 4,959,717 gas.
The majority of the cost comes from verifying that the provided factors are indeed prime with the Miller-Rabin primality test.

Since the number of factors in this [test](../assets/eip-X/test/bounty-contracts/prime-factoring-bounty/cost-of-solving-primes.test.ts) is greater than the expected number of factors of any integer, this may serve as an initial estimate of the cost to verify the solutions for randomly generated integers. Therefore, since the total cost is less than
`MINIMUM_GAS_PAYOUT` gas, a bounty covering at least `MINIMUM_GAS_PAYOUT` should be funded to the contract. Note, this minimum viable incentive in terms of ETH is a moving target, as a function of the current Ethereum gas market. To help ensure incentive compatability of this bounty contract, the bounty funded should be at least many multiples over the current gas prices. 

## Test Cases

- [Random Bytes Accumulator](../assets/eip-X/test/bounty-contracts/support/random-bytes-accumulator.test.ts)
- [RSA-UFO Generation](../assets/eip-X/test/bounty-contracts/prime-factoring-bounty/prime-factoring-bounty-with-rsa-ufo/prime-factoring-bounty-with-rsa-ufo.test.ts)
- [Prime Factoring Bounty](../assets/eip-X/test/bounty-contracts/prime-factoring-bounty/prime-factoring-bounty-with-predetermined-locks/prime-factoring-bounty-with-predetermined-locks.test.ts)

## Reference Implementation

- [Quantum Supremacy Contract](../assets/eip-X/contracts/bounty-contracts/prime-factoring-bounty/prime-factoring-bounty-with-rsa-ufo/PrimeFactoringBountyWithRsaUfo.sol)

- Example proof-of-concept [account](../assets/eip-X/contracts/bounty-fallback-account/BountyFallbackAccount.sol) 
  having a quantum secure verification scheme after quantum supremacy trigger

## Security Considerations

### Bit-length of the integers
Sander[^11] proves that difficult to factor numbers without a known factorization, called RSA-UFOs, can be generated.
Using logic based on that described by Anoncoin using this method, this contract shall generate `NUMBER_OF_LOCKS` integers of `3 * BIT_SIZE_OF_PRIMES` bits each to achieve a one in a billion chance of being insecure.

#### Predicted security
##### Classical
Burt Kaliski and RSA Laboratories ("TWIRL and RSA Key Size", 2003) recommends 3072-bit key sizes for RSA to be secure beyond 2030.

##### Quantum
Breaking 256-bit elliptic curve encryption is expected[^12] to require 2,330 qubits, although with current fault-tolerant regime, it is expected[^13] that 13 * 10^6 physical qubits would be required to break this encryption within one day.

### Front running and censorship

One day is required before one can reveal a commitment. It is largely infeasible to censor an economically viable transaction for such a period of time.

Assuming the reveal transaction is willing to pay market rate for transaction fees, the 1559 fee mechanism and its exponential adjustment makes it infeasible for an economic attacker to spam costly transactions to artifically increase the base-fee for an extended period of time.

Additionally, even if a large percentage of the proposers collude to censor, the inclusion of the reveal transaction on chain will be delayed but only as a function of the ratio of censoring to non-censoring proposers. E.g., if 90% of proposers censor, then the reveal transaction will take 10x as long as expected to be included -- on the order of 120s given mainnet block times. If, instead, 99% of proposers censor, then the transaction will take ~100x as long to be included -- on the order of 1200s. Still in these extreme regimes, reveal times on the order of a day are safe.

### Choosing the puzzle
The following are other options that were considered as the puzzle to be used along with the reasoning for not using them.

#### Order-finding

Order-finding can be defined as follows: given a positive integer _n_ and an integer _a_ coprime to _n_, 
find the smallest positive integer _k_ such that _a_ ^ _k_ = 1 (mod _n_).

Order-finding can be reduced[^10] to factoring, and vice-versa. Therefore, the puzzle must first generate hard-to-factor numbers with high probability as a modulus and then generate random numbers coprime to those moduli.

To compare costs with the factoring puzzle, we may compare the contracts using these puzzles in two ways: (1) verifying known solutions and (2) deploying.

To verify submitted solutions, an order-finding contract was [deployed](../assets/eip-X/test/bounty-contracts/order-finding-bounty/cost-of-solving-order.test.ts) with a lock having a random 3072-bit
modulus and a random 3071-bit base. Cleve[^14] defines the quantum order-finding problem to have an order no greater than twice the bit size of the modulus, 
i.e. 768 bytes. Therefore, 768 random solutions of byte size equal to its iteration were sent to the contract. 
The maximum gas cost from these iterations was 4,835,737 gas, the minimum was 108,948, the mean was 2,472,370, and the median was 2,478,643.

[Deploying](../assets/eip-X/deploy/2_deploy_order_finding_bounty.ts) an order-finding contract with 119 locks at 3,072 bits resulted in a cost of 4,029,364,172 gas, which includes testing that the generated base was neither 1
nor -1 and was coprime with the modulus. Alternatively, deploying without checking for being coprime could also use a
probabilistic method. Deploying the contract at 119 locks without checking for coprimality resulted in a cost of 242,370,598 gas. However,
since two randomly generated integers have about 0.61 chance of being coprime[^15], 
one would need to generate 23 random pairs to have a one in a billion chance of having no coprime pairs. So, this probabilistic method
would also cost a large amount, possibly more, depending on the satisfactory probability.

[Deploying](../assets/eip-X/deploy/1_deploy_prime_factoring_bounty.ts) the prime factorization puzzle, on the other hand, resulted in a cost of 150,994,811 gas when generating 119 locks of size 3,072 bits.

This opens up a debatable question as to which puzzle should be used based on which would be less costly and for which party. Order-finding has a much
higher deployment cost but also has a chance of costing far less to the solver, which would decrease the barrier to entry of
providing solutions to the problem. However, prime factorization likely costs less to deploy and, in the worst case of order-finding, 
costs about the same to verify solutions.

#### Sign a message without the secret key
The solver would need to sign a message, which the contract would verify to have been 
correctly signed by the public key.

Since quantum computers are not currently expected to be able to reverse hash functions, one could not sign a message with only the public address alone. 
Hence, the contract could not simply randomly generate a public address with which the solver could sign a message. 
Rather, it would need to generate a secret key in order to generate and sign messages that the solver could use to sign their own message.
This opens up trust issues, as the minter of the contract has the capability to see the secret key and therefore could provide the solution without needing a quantum computer.

#### Factor a product of large, generated primes
Instead of generating an RSA-UFO, the contract could implement current RSA key generation protocols and first generate 
two large primes to produces the product of the primes. 
This method again has the flaw that the minter has the capability to see the primes, 
and therefore some level of trust would need to be given that the minter would throw the values away.

#### A Cryptographic Test of Quantumness
A paper in 2018[^16] provides a proof of quantumness protocol based on cryptographic methods and randomness.
However, this method requires a trapdoor, or information that is kept secret from the verifier. This cannot be guaranteed in a blockchain context and is therefore unsecure in the same way that factoring a product of large, generated primes is unsecure.

#### Sampling problems
Harrow and Montanaro[^17] survey sampling problems, which have been proposed as a form of quantum supremacy verification. 
The challenge for these is verifying that the given samples were indeed sampled from the desired probability distribution.
This contract must use a problem that is verifiable, and therefore sampling problems will not suffice.

#### Decentralized trusted setup
This inherently has a trust factor, albeit very small. It requires that at least one person in the party is honest.
A fully trustless setup is preferred. However, further investigation may be done to potentially uncover a valid puzzle that uses a 
decentralized setup and has an advantage (perhaps with a lower cost or a greater leading indicator) worth the additional trust.

#### Verifiable Quantum Advantage without Structure
Yamakawa and Zhandry[^18] analyze a problem that seems promising as an option for this puzzle in which all that needs to be decided are the parameters for a suitable Folded Reed-Solomon code, as described in the paper. 
This seems promising as a sooner leading indicator, as it would likely require fewer qubits to solve and therefore likely be solved before the integer factoring puzzle, allowing ETH funds to be protected with lower risk.
Furthermore, it would likely cost far less to deploy and verify solutions since the problem would not need to be generated probabilistically using many large numbers.

This actually opens up the idea of puzzle advancement or alternatives in general.
There could be many puzzles developed in the future with different security levels or other advantages and tradeoffs. 
These would provide a scale of warnings, where there would be a tradeoff for users. 
On one end of the scale, the tradeoff would be a shorter risk of theft of their ETH but a sooner implementation of costly verification schemes. 
On the other end, the tradeoff would be a longer risk of theft of their ETH but a later implementation of costly verification schemes.

Hence, this integer factoring puzzle may serve as the latter of the extremes.
If this puzzle is solved, then one may assume that the power of quantum computers has already surpassed the ability to break ECDSA verification schemes.
This allows users to watch this contract as an extreme safeguard in the case that they want to save more ETH with a greater risk of theft by a quantum advantage. 

## Copyright
Copyright and related rights waived via [CC0](../LICENSE.md).

[^1]:
    ```csl-json
    {
      "type": "misc"
      "id": 1,
      "author"=[{"family": "Preskill", "given": "John"}],
      "DOI": "10.48550/arXiv.1203.5813",
      "title": "Quantum computing and the entanglement frontier", 
      "original-date": {
        "date-parts": [
          [2012, 11, 10]
        ]
      },
      "URL": "https://doi.org/10.48550/arXiv.1203.5813"
    }
    ```
[^2]:
    ```csl-json
    {
      "type": "article"
      "id": 2,
      "author"=[{'family': 'Kim', 'given': 'Youngseok'}, {'family': 'Eddins', 'given': 'Andrew'}, {'family': 'Anand', 'given': 'Sajant'}, {'family': 'Wei', 'given': 'Ken Xuan'}, {'family': 'van den Berg', 'given': 'Ewout'}, {'family': 'Rosenblatt', 'given': 'Sami'}, {'family': 'Nayfeh', 'given': 'Hasan'}, {'family': 'Wu', 'given': 'Yantao'}, {'family': 'Zaletel', 'given': 'Michael'}, {'family': 'Temme', 'given': 'Kristan'}, {'family': 'Kandala', 'given': 'Abhinav'}],
      "DOI": "10.1038/s41586-023-06096-3",
      "title": "Evidence for the utility of quantum computing before fault tolerance", 
      "original-date": {
        "date-parts": [
          [2023, 06, 15]
        ]
      },
      "URL": "https://doi.org/10.1038/s41586-023-06096-3"
    }
    ```
[^3]:
    ```csl-json
    {
      "type": "article"
      "id": 3,
      "author"=[{"family": "Arute", "given": "Frank"}, {"family": "Arya", "given": "Kunal"}, {"family": "Babbush", "given": "Ryan"}, {"family": "Bacon", "given": "Dave"}, {"family": "Bardin", "given": "Joseph C."}, {"family": "Barends", "given": "Rami"}, {"family": "Biswas", "given": "Rupak"}, {"family": "Boixo", "given": "Sergio"}, {"family": "Brandao", "given": "Fernando G. S. L."}, {"family": "Buell", "given": "David A."}, {"family": "Burkett", "given": "Brian"}, {"family": "Chen", "given": "Yu"}, {"family": "Chen", "given": "Zijun"}, {"family": "Chiaro", "given": "Ben"}, {"family": "Collins", "given": "Roberto"}, {"family": "Courtney", "given": "William"}, {"family": "Dunsworth", "given": "Andrew"}, {"family": "Farhi", "given": "Edward"}, {"family": "Foxen", "given": "Brooks"}, {"family": "Fowler", "given": "Austin"}, {"family": "Gidney", "given": "Craig"}, {"family": "Giustina", "given": "Marissa"}, {"family": "Graff", "given": "Rob"}, {"family": "Guerin", "given": "Keith"}, {"family": "Habegger", "given": "Steve"}, {"family": "Harrigan", "given": "Matthew P."}, {"family": "Hartmann", "given": "Michael J."}, {"family": "Ho", "given": "Alan"}, {"family": "Hoffmann", "given": "Markus"}, {"family": "Huang", "given": "Trent"}, {"family": "Humble", "given": "Travis S."}, {"family": "Isakov", "given": "Sergei V."}, {"family": "Jeffrey", "given": "Evan"}, {"family": "Jiang", "given": "Zhang"}, {"family": "Kafri", "given": "Dvir"}, {"family": "Kechedzhi", "given": "Kostyantyn"}, {"family": "Kelly", "given": "Julian"}, {"family": "Klimov", "given": "Paul V."}, {"family": "Knysh", "given": "Sergey"}, {"family": "Korotkov", "given": "Alexander"}, {"family": "Kostritsa", "given": "Fedor"}, {"family": "Landhuis", "given": "David"}, {"family": "Lindmark", "given": "Mike"}, {"family": "Lucero", "given": "Erik"}, {"family": "Lyakh", "given": "Dmitry"}, {"family": "Mandr{\\`a}", "given": "Salvatore"}, {"family": "McClean", "given": "Jarrod R."}, {"family": "McEwen", "given": "Matthew"}, {"family": "Megrant", "given": "Anthony"}, {"family": "Mi", "given": "Xiao"}, {"family": "Michielsen", "given": "Kristel"}, {"family": "Mohseni", "given": "Masoud"}, {"family": "Mutus", "given": "Josh"}, {"family": "Naaman", "given": "Ofer"}, {"family": "Neeley", "given": "Matthew"}, {"family": "Neill", "given": "Charles"}, {"family": "Niu", "given": "Murphy Yuezhen"}, {"family": "Ostby", "given": "Eric"}, {"family": "Petukhov", "given": "Andre"}, {"family": "Platt", "given": "John C."}, {"family": "Quintana", "given": "Chris"}, {"family": "Rieffel", "given": "Eleanor G."}, {"family": "Roushan", "given": "Pedram"}, {"family": "Rubin", "given": "Nicholas C."}, {"family": "Sank", "given": "Daniel"}, {"family": "Satzinger", "given": "Kevin J."}, {"family": "Smelyanskiy", "given": "Vadim"}, {"family": "Sung", "given": "Kevin J."}, {"family": "Trevithick", "given": "Matthew D."}, {"family": "Vainsencher", "given": "Amit"}, {"family": "Villalonga", "given": "Benjamin"}, {"family": "White", "given": "Theodore"}, {"family": "Yao", "given": "Z. Jamie"}, {"family": "Yeh", "given": "Ping"}, {"family": "Zalcman", "given": "Adam"}, {"family": "Neven", "given": "Hartmut"}, {"family": "Martinis", "given": "John M."}],
      "DOI": "10.1038/s41586-019-1666-5",
      "title": "Quantum supremacy using a programmable superconducting processor", 
      "original-date": {
        "date-parts": [
          [2019, 08, 24]
        ]
      },
      "URL": "https://doi.org/10.1038/s41586-019-1666-5"
    }
    ```
[^4]:
    ```csl-json
    {
      "type": "misc"
      "id": 4,
      "author"=[{"family": "Morvan", "given": "A."}, {"family": "Villalonga", "given": "B."}, {"family": "Mi", "given": "X."}, {"family": "Mandr\u00e0", "given": "S."}, {"family": "Bengtsson", "given": "A."}, {"family": "V.", "given": "P."}, {"family": "Chen", "given": "Z."}, {"family": "Hong", "given": "S."}, {"family": "Erickson", "given": "C."}, {"family": "K.", "given": "I."}, {"family": "Chau", "given": "J."}, {"family": "Laun", "given": "G."}, {"family": "Movassagh", "given": "R."}, {"family": "Asfaw", "given": "A."}, {"family": "T.", "given": "L."}, {"family": "Peralta", "given": "R."}, {"family": "Abanin", "given": "D."}, {"family": "Acharya", "given": "R."}, {"family": "Allen", "given": "R."}, {"family": "I.", "given": "T."}, {"family": "Anderson", "given": "K."}, {"family": "Ansmann", "given": "M."}, {"family": "Arute", "given": "F."}, {"family": "Arya", "given": "K."}, {"family": "Atalaya", "given": "J."}, {"family": "C.", "given": "J."}, {"family": "Bilmes", "given": "A."}, {"family": "Bortoli", "given": "G."}, {"family": "Bourassa", "given": "A."}, {"family": "Bovaird", "given": "J."}, {"family": "Brill", "given": "L."}, {"family": "Broughton", "given": "M."}, {"family": "B.", "given": "B."}, {"family": "A.", "given": "D."}, {"family": "Burger", "given": "T."}, {"family": "Burkett", "given": "B."}, {"family": "Bushnell", "given": "N."}, {"family": "Campero", "given": "J."}, {"family": "S.", "given": "H."}, {"family": "Chiaro", "given": "B."}, {"family": "Chik", "given": "D."}, {"family": "Chou", "given": "C."}, {"family": "Cogan", "given": "J."}, {"family": "Collins", "given": "R."}, {"family": "Conner", "given": "P."}, {"family": "Courtney", "given": "W."}, {"family": "L.", "given": "A."}, {"family": "Curtin", "given": "B."}, {"family": "M.", "given": "D."}, {"family": "Del", "given": "A."}, {"family": "Demura", "given": "S."}, {"family": "Di", "given": "A."}, {"family": "Dunsworth", "given": "A."}, {"family": "Faoro", "given": "L."}, {"family": "Farhi", "given": "E."}, {"family": "Fatemi", "given": "R."}, {"family": "S.", "given": "V."}, {"family": "Flores", "given": "L."}, {"family": "Forati", "given": "E."}, {"family": "G.", "given": "A."}, {"family": "Foxen", "given": "B."}, {"family": "Garcia", "given": "G."}, {"family": "Genois", "given": "E."}, {"family": "Giang", "given": "W."}, {"family": "Gidney", "given": "C."}, {"family": "Gilboa", "given": "D."}, {"family": "Giustina", "given": "M."}, {"family": "Gosula", "given": "R."}, {"family": "Grajales", "given": "A."}, {"family": "A.", "given": "J."}, {"family": "Habegger", "given": "S."}, {"family": "C.", "given": "M."}, {"family": "Hansen", "given": "M."}, {"family": "P.", "given": "M."}, {"family": "D.", "given": "S."}, {"family": "Heu", "given": "P."}, {"family": "R.", "given": "M."}, {"family": "Huang", "given": "T."}, {"family": "Huff", "given": "A."}, {"family": "J.", "given": "W."}, {"family": "B.", "given": "L."}, {"family": "V.", "given": "S."}, {"family": "Iveland", "given": "J."}, {"family": "Jeffrey", "given": "E."}, {"family": "Jiang", "given": "Z."}, {"family": "Jones", "given": "C."}, {"family": "Juhas", "given": "P."}, {"family": "Kafri", "given": "D."}, {"family": "Khattar", "given": "T."}, {"family": "Khezri", "given": "M."}, {"family": "Kieferov\u00e1", "given": "M."}, {"family": "Kim", "given": "S."}, {"family": "Kitaev", "given": "A."}, {"family": "R.", "given": "A."}, {"family": "N.", "given": "A."}, {"family": "Kostritsa", "given": "F."}, {"family": "M.", "given": "J."}, {"family": "Landhuis", "given": "D."}, {"family": "Laptev", "given": "P."}, {"family": "-M.", "given": "K."}, {"family": "Laws", "given": "L."}, {"family": "Lee", "given": "J."}, {"family": "W.", "given": "K."}, {"family": "D.", "given": "Y."}, {"family": "J.", "given": "B."}, {"family": "T.", "given": "A."}, {"family": "Liu", "given": "W."}, {"family": "Locharla", "given": "A."}, {"family": "D.", "given": "F."}, {"family": "Martin", "given": "O."}, {"family": "Martin", "given": "S."}, {"family": "R.", "given": "J."}, {"family": "McEwen", "given": "M."}, {"family": "C.", "given": "K."}, {"family": "Mieszala", "given": "A."}, {"family": "Montazeri", "given": "S."}, {"family": "Mruczkiewicz", "given": "W."}, {"family": "Naaman", "given": "O."}, {"family": "Neeley", "given": "M."}, {"family": "Neill", "given": "C."}, {"family": "Nersisyan", "given": "A."}, {"family": "Newman", "given": "M."}, {"family": "H.", "given": "J."}, {"family": "Nguyen", "given": "A."}, {"family": "Nguyen", "given": "M."}, {"family": "Yuezhen", "given": "M."}, {"family": "E.", "given": "T."}, {"family": "Omonije", "given": "S."}, {"family": "Opremcak", "given": "A."}, {"family": "Petukhov", "given": "A."}, {"family": "Potter", "given": "R."}, {"family": "P.", "given": "L."}, {"family": "Quintana", "given": "C."}, {"family": "M.", "given": "D."}, {"family": "Rocque", "given": "C."}, {"family": "Roushan", "given": "P."}, {"family": "C.", "given": "N."}, {"family": "Saei", "given": "N."}, {"family": "Sank", "given": "D."}, {"family": "Sankaragomathi", "given": "K."}, {"family": "J.", "given": "K."}, {"family": "F.", "given": "H."}, {"family": "Schuster", "given": "C."}, {"family": "J.", "given": "M."}, {"family": "Shorter", "given": "A."}, {"family": "Shutty", "given": "N."}, {"family": "Shvarts", "given": "V."}, {"family": "Sivak", "given": "V."}, {"family": "Skruzny", "given": "J."}, {"family": "C.", "given": "W."}, {"family": "D.", "given": "R."}, {"family": "Sterling", "given": "G."}, {"family": "Strain", "given": "D."}, {"family": "Szalay", "given": "M."}, {"family": "Thor", "given": "D."}, {"family": "Torres", "given": "A."}, {"family": "Vidal", "given": "G."}, {"family": "Vollgraff", "given": "C."}, {"family": "White", "given": "T."}, {"family": "W.", "given": "B."}, {"family": "Xing", "given": "C."}, {"family": "J.", "given": "Z."}, {"family": "Yeh", "given": "P."}, {"family": "Yoo", "given": "J."}, {"family": "Young", "given": "G."}, {"family": "Zalcman", "given": "A."}, {"family": "Zhang", "given": "Y."}, {"family": "Zhu", "given": "N."}, {"family": "Zobrist", "given": "N."}, {"family": "G.", "given": "E."}, {"family": "Biswas", "given": "R."}, {"family": "Babbush", "given": "R."}, {"family": "Bacon", "given": "D."}, {"family": "Hilton", "given": "J."}, {"family": "Lucero", "given": "E."}, {"family": "Neven", "given": "H."}, {"family": "Megrant", "given": "A."}, {"family": "Kelly", "given": "J."}, {"family": "Aleiner", "given": "I."}, {"family": "Smelyanskiy", "given": "V."}, {"family": "Kechedzhi", "given": "K."}, {"family": "Chen", "given": "Y."}, {"family": "Boixo", "given": "S."}],
      "DOI": "10.48550/arXiv.2304.11119",
      "title": "Phase transition in Random Circuit Sampling", 
      "original-date": {
        "date-parts": [
          [2023, 04, 21]
        ]
      },
      "URL": "https://doi.org/10.48550/arXiv.2304.11119"
    }
    ```
[^5]:
    ```csl-json
    {
      "type": "misc"
      "id": 5,
      "author"=[{"family": "Begušić", "given": "Tomislav"}, {"family": "Kin-Lic Chan", "given": "Garnet"}],
      "DOI": "10.48550/arXiv.2306.16372",
      "title": "Fast classical simulation of evidence for the utility of quantum computing before fault tolerance", 
      "original-date": {
        "date-parts": [
          [2023, 06, 28]
        ]
      },
      "URL": "https://doi.org/10.48550/arXiv.2306.16372"
    }
    ```
[^6]:
    ```csl-json
    {
      "type": "misc"
      "id": 6,
      "author"=[{"family": "Pednault", "given": "Edwin"}, {"family": "Gunnels", "given": "John A."}, {"family": "Nannicini", "given": "Giacomo"}, {"family": "Horesh", "given": "Lior"}, {"family": "Wisnieff", "given": "Robert"}],
      "DOI": "10.48550/arXiv.1910.09534",
      "title": "Leveraging Secondary Storage to Simulate Deep 54-qubit Sycamore Circuits", 
      "original-date": {
        "date-parts": [
          [2019, 08, 22]
        ]
      },
      "URL": "https://doi.org/10.48550/arXiv.1910.09534",
      "custom": {
        "additional-urls": [
          "https://api.semanticscholar.org/CorpusID:204800933"
        ]
      }
    ```
[^7]:
    ```csl-json
    {
      "type": "article"
      "id": 7,
      "author"=[{"family": "Castelvecchi", "given": "Davide"}],
      "DOI": "10.1038/d41586-023-00017-0",
      "title": "Are quantum computers about to break online privacy?", 
      "original-date": {
        "date-parts": [
          [2023, 01, 06]
        ]
      },
      "URL": "https://doi.org/10.1038/d41586-023-00017-0"
    ```
[^8]:
    ```csl-json
    {
      "type": "article"
      "id": 8,
      "author"=[{"family": "Shor", "given": "Peter W."}],
      "DOI": "10.1137/S0097539795293172",
      "title": "Polynomial-Time Algorithms for Prime Factorization and Discrete Logarithms on a Quantum Computer", 
      "original-date": {
        "date-parts": [
          [1995, 01, 25]
        ]
      },
      "URL": "https://doi.org/10.1137/S0097539795293172"
    ```
[^9]:
    ```csl-json
    {
      "type": "article"
      "id": 9,
      "author"=[{"family": "Erdös", "given": "P."}, {"family": "Kac", "given": "M."}],
      "DOI": "10.2307/2371483",
      "title": "The Gaussian Law of Errors in the Theory of Additive Number Theoretic Functions", 
      "original-date": {
        "date-parts": [
          [1940, 04]
        ]
      },
      "URL": "https://www.semanticscholar.org/paper/The-Gaussian-Law-of-Errors-in-the-Theory-of-Number-Erd%C3%B6s-Kac/261864821aa770542be65dbe16640684ab786fa9",
      "custom": {
        "additional-urls": [
          "https://doi.org/10.2307/2371483"
        ]
      }
    ```
[^10]:
    ```csl-json
    {
      "type": "article"
      "id": 10,
      "author"=[{"family": "Woll", "given": "Heather"}],
      "DOI": "10.1016/0890-5401(87)90030-7",
      "title": "Reductions among number theoretic problems", 
      "original-date": {
        "date-parts": [
          [1986, 07, 02]
        ]
      },
      "URL": "https://doi.org/10.1016/0890-5401(87)90030-7"
    ```
[^11]:
    ```csl-json
    {
      "type": "inproceedings"
      "id": 11,
      "author"=[{"family": "Sander", "given": "Tomas"}],
      "DOI": "10.1007/978-3-540-47942-0_21",
      "title": "Efficient Accumulators without Trapdoor Extended Abstract", 
      "original-date": {
        "date-parts": [
          [1999, 09, 11]
        ]
      },
      "custom": {
        "additional-urls": [
          "https://doi.org/10.1007/978-3-540-47942-0_21"
        ]
      }
    ```
[^12]:
    ```csl-json
    {
      "type": "misc"
      "id": 12,
      "author"=[{"family": "Roetteler", "given": "Martin"}, {"family": "Naehrig", "given": "Michael"}, {"family": "Svore", "given": "Krysta M."}, {"family": "Lauter", "given": "Kristin"}],
      "DOI": "10.48550/arXiv.1706.06752",
      "title": "Quantum resource estimates for computing elliptic curve discrete logarithms", 
      "original-date": {
        "date-parts": [
          [2017, 08, 31]
        ]
      },
      "URL": "https://doi.org/10.48550/arXiv.1706.06752"
    ```
[^13]:
    ```csl-json
    {
      "type": "article"
      "id": 13,
      "author"=[{"family": "Webber", "given": "Mark"}, {"family": "Elfving", "given": "Vincent"}, {"family": "Weidt", "given": "Sebastian"}, {"family": "Hensinger", "given": "Winfried K."}],
      "DOI": "10.1116/5.0073075",
      "title": "The impact of hardware specifications on reaching quantum advantage in the fault tolerant regime", 
      "original-date": {
        "date-parts": [
          [2022, 01, 15]
        ]
      },
      "URL": "https://doi.org/10.1116/5.0073075"
    ```
[^14]:
    ```csl-json
    {
      "type": "misc"
      "id": 14,
      "author"=[{"family": "Cleve", "given": "Richard"}],
      "DOI": "10.1016/j.ic.2004.04.001",
      "title": "The query complexity of order-finding", 
      "original-date": {
        "date-parts": [
          [1999, 11, 30]
        ]
      },
      "URL": "https://doi.org/10.1016/j.ic.2004.04.001"
      "custom": {
        "additional-urls": [
          "https://doi.org/10.48550/arXiv.quant-ph/9911124"
        ]
      }
    ```
[^15]:
    ```csl-json
    {
      "type": "inproceedings"
      "id": 15,
      "author"=[{"family": "Collins", "given": "George E."}, {"family": "Johnson", "given": "Jeremy R."}],
      "DOI": "10.1007/3-540-51084-2_23",
      "title": "The probability of relative primality of Gaussian integers", 
      "original-date": {
        "date-parts": [
          [2005, 05, 27]
        ]
      },
      "custom": {
        "additional-urls": [
          "https://doi.org/10.1007/3-540-51084-2_23"
        ]
      }
    ```
[^16]:
    ```csl-json
    {
      "type": "inproceedings"
      "id": 16,
      "author"=[{"family": "Brakerski", "given": "Zvika"}, {"family": "Christiano", "given": "Paul"}, {"family": "Mahadev", "given": "Urmila"}, {"family": "Vazirani", "given": "Umesh"}, {"family": "Vidick", "given": "Thomas"}],
      "DOI": "10.1109/FOCS.2018.00038",
      "title": "A Cryptographic Test of Quantumness and Certifiable Randomness from a Single Quantum Device", 
      "original-date": {
        "date-parts": [
          [2018, 07, 09]
        ]
      },
      "URL": "https://doi.org/10.48550/arXiv.1804.00640",
      "custom": {
        "additional-urls": [
          "https://doi.org/10.1109/FOCS.2018.00038"
        ]
      }
    ```
[^17]:
    ```csl-json
    {
      "type": "inproceedings"
      "id": 17,
      "author"=[{"family": "Harrow", "given": "Aram W."}, {"family": "Montanaro", "given": "Ashley"}],
      "DOI": "10.1038/nature23458",
      "title": "Quantum computational supremacy", 
      "original-date": {
        "date-parts": [
          [2018, 07, 09]
        ]
      },
      "URL": "https://doi.org/10.48550/arXiv.1809.07442",
      "custom": {
        "additional-urls": [
          "https://doi.org/10.1038/nature23458"
        ]
      }
    ```
[^18]:
    ```csl-json
    {
      "type": "inproceedings"
      "id": 18,
      "author"=[{"family": "Yamakawa", "given": "T."}, {"family": "Zhandry", "given": "M."}],
      "DOI": "10.1109/FOCS54457.2022.00014",
      "title": "Verifiable Quantum Advantage without Structure", 
      "original-date": {
        "date-parts": [
          [2022, 11]
        ]
      },
      "URL": "https://doi.org/10.48550/arXiv.2204.02063",
      "custom": {
        "additional-urls": [
          "https://doi.ieeecomputersociety.org/10.1109/FOCS54457.2022.00014"
        ]
      }
    ```
[ERC-2470]: ./eip-2470.md
