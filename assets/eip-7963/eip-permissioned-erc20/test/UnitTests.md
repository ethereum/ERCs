# Smart Contract Test Plan

This document outlines the test plan for the smart contracts in the EIP-Permissioned-ERC20 project. Tests will be designed for the Hardhat framework using TypeScript and Chai, focusing on correctness, security, and efficiency.

## General Testing Principles

*   **Comprehensive Coverage:** Ensure all public and external functions are tested, including their interactions.
*   **Core Functionality:** Validate that each contract fulfills its primary purpose as described.
*   **Permissioning & Access Control:** Rigorously test all role-based access controls (e.g., Ownable, custom roles like issuer/token).
*   **Edge Cases & Boundary Conditions:** Explore scenarios with zero values, maximum values, empty arrays, single-element arrays, etc.
*   **Failure Modes & Revert Reasons:** Verify that contracts revert correctly under invalid conditions and emit expected error messages/reasons.
*   **Event Emission:** Confirm that all specified events are emitted with the correct parameters upon successful operations.
*   **State Changes:** Assert correct updates to storage variables after transactions.
*   **Gas Considerations:** While full gas optimization is a separate audit, tests may include scenarios to highlight potentially expensive operations (e.g., unbounded loops, though not expected here).
*   **Fixtures:** Utilize Hardhat fixtures (`loadFixture`) for deploying contracts and setting up a consistent baseline state for tests, improving speed and readability.
*   **Mocking:** Employ mock contracts for external dependencies (e.g., a mock `Groth16Verifier` when testing `TransferOracle`, and a mock `TransferOracle` when unit testing `PermissionedERC20` specific oracle interactions) to isolate contract logic.
*   **No Untested Assumptions:** All critical logic paths and assumptions within the contracts should be covered by tests.

## Contracts Test Plan

### 1. `PermissionedERC20.sol`

**Primary Role:** An ERC20 token that delegates transfer authorization to a `TransferOracle`.

**Testing Strategy:**
*   Verify standard ERC20 behavior, ensuring the `_update` hook correctly interacts with the `TransferOracle`.
*   Test owner-specific functionalities like minting and burning.
*   Use a mock `TransferOracle` to control its responses during tests.

**Test Suites & Cases:**

#### 1.1. Constructor & Initial State
    - **`constructor(string name_, string symbol_, address oracle_, address initialOwner_)`**
        - Test: Deployment with valid parameters (name, symbol, mock oracle address, initial owner) correctly initializes state variables:
            - `name()` returns `name_`.
            - `symbol()` returns `symbol_`.
            - `decimals()` returns 18.
            - `transferOracle` state variable is set to `oracle_`.
            - `owner()` (from Ownable) is set to `initialOwner_`.
            - `totalSupply()` is initially 0.
        - Test: Deployment reverts with `PermissionedERC20__ZeroAddressOracle` if `oracle_` is `address(0)`.

#### 1.2. ERC20 Standard View Functions
    - **`name()`, `symbol()`, `decimals()`**
        - Test: Return the correct constant values set during construction.
    - **`totalSupply()`**
        - Test: Returns 0 initially.
        - Test: Correctly reflects total tokens after minting and burning operations.
    - **`balanceOf(address account)`**
        - Test: Returns 0 for any account initially.
        - Test: Correctly returns balance after mints, burns, and transfers.
    - **`allowance(address owner, address spender)`**
        - Test: Returns 0 initially.
        - Test: Correctly returns allowance after `approve()`.

#### 1.3. ERC20 Standard Mutative Functions (Non-Transfer)
    - **`approve(address spender, uint256 amount)`**
        - Test (Success): Caller can approve a spender for a given amount.
            - `allowance(owner, spender)` is updated to `amount`.
            - Emits `Approval(owner, spender, amount)` event.
        - Test (Success): Can update an existing approval (approve for a new amount).
        - Test (Success): Can approve `address(0)` as spender (standard OZ behavior).
        - Test (Success): Can approve `type(uint256).max` amount.

#### 1.4. Core Transfer Logic (`_update` Hook and its Callers)
    - Setup: Use a mock `TransferOracle` for these tests.
    - **`transfer(address recipient, uint256 amount)`**
        - Test (Success - Oracle Permits):
            - Mock `transferOracle.canTransfer(address(this), sender, recipient, amount)` returns a `proofId`.
            - Balances of sender and recipient are correctly updated.
            - Emits `TransferValidated(proofId)` with the `proofId` from the mock oracle.
            - Emits `Transfer(sender, recipient, amount)`.
        - Test (Failure - Oracle Denies):
            - Mock `transferOracle.canTransfer(...)` reverts.
            - The `transfer` call reverts (ideally with the same error or a specific token error).
            - Balances remain unchanged. No `TransferValidated` or `Transfer` events emitted.
        - Test (Failure - ERC20 Standard):
            - Insufficient balance: Reverts (e.g., "ERC20: transfer amount exceeds balance").
            - Transfer to `address(0)`: Reverts (e.g., "ERC20: transfer to the zero address").
        - Test (Edge Case): Transferring 0 amount when `from != address(0)` and `to != address(0)`.
            - Mock `transferOracle.canTransfer(...)` is called.
            - `TransferValidated` and `Transfer` events emitted for 0 amount. Balances unchanged.
        - Test (Edge Case): Transferring to self (`recipient == sender`).
            - Mock `transferOracle.canTransfer(...)` is called.
            - `TransferValidated` and `Transfer` events emitted. Balance unchanged.
    - **`transferFrom(address sender, address recipient, uint256 amount)`**
        - Test (Success - Oracle Permits & Sufficient Allowance):
            - Spender has sufficient allowance for `sender`.
            - Mock `transferOracle.canTransfer(address(this), sender, recipient, amount)` returns a `proofId`.
            - Balances of `sender` and `recipient` are updated.
            - Allowance for spender is reduced correctly.
            - Emits `TransferValidated(proofId)`.
            - Emits `Transfer(sender, recipient, amount)`.
            - Emits `Approval(sender, spender, newAllowance)`.
        - Test (Failure - Oracle Denies):
            - Spender has allowance.
            - Mock `transferOracle.canTransfer(...)` reverts.
            - The `transferFrom` call reverts. Balances and allowance unchanged.
        - Test (Failure - ERC20 Standard):
            - Insufficient allowance: Reverts (e.g., "ERC20: insufficient allowance").
            - Insufficient balance for `sender`: Reverts.
            - Transfer to `address(0)`: Reverts.

#### 1.5. Owner-Only Functions (Bypassing Oracle)
    - **`mint(address to, uint256 amount)`**
        - Test (Success - Owner):
            - `totalSupply()` increases by `amount`.
            - `balanceOf(to)` increases by `amount`.
            - Emits `Transfer(address(0), to, amount)`.
            - Does NOT call `transferOracle.canTransfer`. No `TransferValidated` event.
        - Test (Failure - Non-Owner): Call from non-owner account reverts (e.g., "Ownable: caller is not the owner").
        - Test (Failure - Mint to Zero Address): Reverts (e.g., "ERC20: mint to the zero address").
    - **`burnFrom(address from, uint256 amount)`**
        - Test (Success - Owner Burning from Own Account via `_burn`):
            - (Note: `burnFrom` is the only public burn function. Owner can call `burnFrom(owner_address, amount)`).
            - `totalSupply()` decreases by `amount`.
            - `balanceOf(from)` (owner's account) decreases by `amount`.
            - Emits `Transfer(from, address(0), amount)`.
            - Does NOT call `transferOracle.canTransfer`. No `TransferValidated` event.
        - Test (Success - Owner Burning from Another Account with Allowance):
            - Owner has been approved by `from` account for at least `amount`.
            - `totalSupply()` decreases.
            - `balanceOf(from)` decreases.
            - Allowance `allowance(from, owner)` decreases.
            - Emits `Transfer(from, address(0), amount)`.
            - Emits `Approval(from, owner, newAllowance)`.
            - Does NOT call `transferOracle.canTransfer`.
        - Test (Failure - Non-Owner): Reverts (e.g., "Ownable: caller is not the owner").
        - Test (Failure - Insufficient Balance): Reverts (e.g., "ERC20: burn amount exceeds balance").
        - Test (Failure - Owner Burning from Another Account without Sufficient Allowance): Reverts.

#### 1.6. Ownable Functionality
    - Test `owner()`: Returns the current owner.
    - Test `transferOwnership(address newOwner)`:
        - (Success - Owner): Transfers ownership to `newOwner`. `owner()` returns `newOwner`. Emits `OwnershipTransferred(oldOwner, newOwner)`.
        - (Failure - Non-Owner): Reverts.
        - (Failure - New Owner is Zero Address): Reverts (e.g., "Ownable: new owner is the zero address").

### 2. `TransferOracle.sol`

**Primary Role:** Manages transfer approvals based on ZK proofs, consuming them for one-time use.

**Testing Strategy:**
*   Test `approveTransfer` with a mock `Groth16Verifier` to control proof verification outcomes.
*   Test `canTransfer` by populating approvals and verifying correct selection and consumption.
*   Verify all permissioning (issuer-only, token-only) and error conditions.

**Test Suites & Cases:**

#### 2.1. Constructor & Initial State
    - **`constructor(address _verifier, address _token, address _initialIssuer)`**
        - Test: Deployment with valid mock verifier, mock token, and initial issuer addresses:
            - `verifier` state variable is set to `_verifier`.
            - `permissionedToken` state variable is set to `_token`.
            - `issuer` state variable (and `owner()`) is set to `_initialIssuer`.
        - Test: Deployment reverts if `_verifier` is `address(0)`.
        - Test: Deployment reverts if `_token` is `address(0)`.

#### 2.2. `approveTransfer(TransferApproval calldata approval, bytes calldata proof, bytes calldata publicInputs)`
    - Setup: Use a mock `Groth16Verifier`. Let `issuer` be the contract owner.
    - **Permissions & Reentrancy:**
        - Test (Success): Callable by `issuer` (owner).
        - Test (Failure): Reverts with `TransferOracle__CallerNotIssuer` if called by non-issuer.
        - Test (Reentrancy): Attempt reentrant call; expect it to be blocked by `nonReentrant` modifier.
    - **ZK Proof & Public Input Handling:**
        - Test (Success - Valid Proof & Data):
            - Mock `verifier.verifyProof(...)` returns `true`.
            - All `approval` data and `publicInputs` are consistent and valid.
            - `proofId` is not already used.
            - `_approvals` mapping is updated with a new `ApprovalStorage` entry.
            - `_consumedProofIds[approval.proofId]` is set to `true`.
            - Emits `TransferApproved(...)` with correct parameters.
            - Returns `approval.proofId`.
        - Test (Failure - Proof Verification Fails):
            - Mock `verifier.verifyProof(...)` returns `false`.
            - Reverts with `TransferOracle__ProofVerificationFailed`.
        - Test (Failure - Invalid `publicInputs` Length):
            - `decodedInputs.length != 7`.
            - Reverts with `TransferOracle__InvalidPublicInputs`.
        - Test (Failure - Input Consistency Checks):
            - `_scaleUp(approval.minAmt) != proofMinAmountScaled`: Reverts with `TransferOracle__InvalidPublicInputs`.
            - `_scaleUp(approval.maxAmt) != proofMaxAmountScaled`: Reverts with `TransferOracle__InvalidPublicInputs`.
            - `uint64(approval.expiry) != proofExpiry`: Reverts with `TransferOracle__InvalidPublicInputs`.
        - Test (Failure - Invalid `approval` Data Semantics):
            - `approval.sender == address(0)`: Reverts with `TransferOracle__InvalidApprovalData`.
            - `approval.recipient == address(0)`: Reverts with `TransferOracle__InvalidApprovalData`.
            - `approval.minAmt > approval.maxAmt`: Reverts with `TransferOracle__InvalidApprovalData`.
            - `approval.expiry <= block.timestamp`: Reverts with `TransferOracle__InvalidApprovalData` (use Hardhat time helpers).
            - `approval.expiry > type(uint40).max`: Reverts with `TransferOracle__InvalidApprovalData`.
        - Test (Failure - `proofId` Mismatch):
            - `calculatedProofId` (from `publicInputs`) `!= approval.proofId`.
            - Reverts with `TransferOracle__InvalidPublicInputs`.
        - Test (Failure - `proofId` Already Used):
            - `_consumedProofIds[approval.proofId]` is `true`.
            - Reverts with `TransferOracle__ProofAlreadyUsed`.
    - **State Changes:**
        - Test: Multiple approvals can be added for the same `(owner(), approval.sender, approval.recipient)` key.
        - Test: `ApprovalStorage` struct fields are correctly populated from `approval` data (including `toUint128`, `toUint40` casts).
    - **Amount Scaling (`_scaleUp` internal function via `approveTransfer`):**
        - Test (Failure - Overflow): Provide `approval.minAmt` or `approval.maxAmt` that would cause `amount * AMOUNT_SCALING_FACTOR` to overflow `uint256`.
            - Reverts with `TransferOracle__ScalingOverflow`. (This will be caught by the consistency check against `proofMinAmountScaled` if scaled inputs are within `uint256` range, or by the multiplication itself if not).

#### 2.3. `canTransfer(address tokenAddress, address sender, address recipient, uint256 amount)`
    - Setup: `issuer` (owner) first calls `approveTransfer` to populate some approvals.
    - **Permissions & Reentrancy:**
        - Test (Success): Callable by the `permissionedToken` address (impersonate or deploy from it).
        - Test (Failure): Reverts with `TransferOracle__CallerNotToken` if `msg.sender` is not `permissionedToken`.
        - Test (Failure): Reverts with `TransferOracle__CallerNotToken` if `tokenAddress` argument is not `permissionedToken` (due to `if (issuer != permissionedToken)` where `issuer` is the first argument to `canTransfer`).
        - Test (Reentrancy): Attempt reentrant call; expect it to be blocked by `nonReentrant` modifier.
    - **Approval Logic & Consumption:**
        - Test (Success - Single Valid Approval):
            - One approval exists that matches `sender`, `recipient`, `amount` range, and is not expired.
            - Approval is removed from `_approvals`.
            - Emits `ApprovalConsumed(...)` with correct parameters.
            - Returns the correct `proofId`.
        - Test (Success - Multiple Approvals, Best Fit):
            - Multiple valid approvals exist.
            - The one with the smallest range (`maxAmt - minAmt`) is chosen and consumed.
            - Events and return value are correct.
        - Test (Scenario - Approval at Start/Middle/End of List):
            - Verify correct removal logic (swap and pop) works for different positions.
        - Test (Failure - No Approval Found):
            - No approval matches the `keccak256(abi.encode(owner(), sender, recipient))` key.
            - Reverts with `TransferOracle__NoApprovalFound`.
        - Test (Failure - All Approvals Expired):
            - Approvals exist for the key, but all are expired (use Hardhat `time.increaseTo`).
            - Reverts with `TransferOracle__NoApprovalFound`.
        - Test (Failure - All Approvals Amount Out of Range):
            - Approvals exist, not expired, but `amount` is not within any `[minAmt, maxAmt]` range.
            - Reverts with `TransferOracle__NoApprovalFound`.
        - Test (Edge Case): `amount == approval.minAmt` or `amount == approval.maxAmt`.
    - **Gas Considerations (Informational):**
        - Test `canTransfer` after populating the `_approvals` array for a single key with many (e.g., 10, 50, 100) entries to observe gas trends.

#### 2.4. View Functions
    - **`getIssuer()`**
        - Test: Returns the address of the `issuer` (same as `owner()`).
    - **`getApprovalCount(address _sender, address _recipient)`**
        - Test: Returns 0 initially.
        - Test: Returns the correct number of active approvals for the given `_sender` and `_recipient` (keyed also by `owner()`).
    - **`isProofUsed(bytes32 _proofId)`**
        - Test: Returns `false` for an unused `proofId`.
        - Test: Returns `true` after `approveTransfer` consumes that `proofId`.

#### 2.5. Ownable Functionality (for `issuer` role management)
    - Test `owner()`: Returns current `issuer`.
    - Test `transferOwnership(address newOwner)`:
        - (Success - Current Issuer): Transfers `issuer` role. `getIssuer()` and `owner()` return `newOwner`. Emits `OwnershipTransferred`.
        - (Failure - Non-Issuer): Reverts.

### 3. `verifier/Groth16Verifier.sol`

**Primary Role:** Verifies Groth16 ZK-SNARK proofs. (Generated code)

**Testing Strategy:**
*   Focus on the interface: does `verifyProof` return expected results for known valid/invalid proofs related to the *specific circuit this verifier was generated for*?
*   Exhaustive cryptographic testing of the verifier's internals is out of scope for these unit tests and relies on the correctness of `snarkjs` and the underlying cryptographic primitives.

**Test Suites & Cases:**

#### 3.1. Deployment
    - Test: Contract deploys successfully.

#### 3.2. `verifyProof(uint[2] calldata _pA, uint[2][2] calldata _pB, uint[2] calldata _pC, uint[7] calldata _pubSignals)`
    - **Prerequisite:** Obtain a set of valid (_pA, _pB, _pC, _pubSignals) and a few intentionally invalid variations for the specific `iso_pain.circom` circuit and its corresponding trusted setup.
    - Test (Success): Given a known valid proof and corresponding public signals, returns `true`.
    - Test (Failure - Invalid Proof Component): Given slightly modified _pA, _pB, or _pC (but valid _pubSignals), returns `false`.
    - Test (Failure - Invalid Public Signal): Given valid proof components but slightly modified _pubSignals, returns `false`.
    - Test (Failure - Mismatched Proof and Signals): Given a proof for one set of signals, but different signals are provided, returns `false`.

### 4. `interfaces/ITransferOracle.sol`

**Primary Role:** Defines the interface for `TransferOracle`.

**Testing Strategy:**
*   No direct tests are written for an interface.
*   Its function signatures, struct definitions, and event definitions are implicitly tested through the comprehensive testing of `TransferOracle.sol` which implements it, and `PermissionedERC20.sol` which calls it.

This plan provides a solid foundation for developing a robust test suite.

