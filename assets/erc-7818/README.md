# ERC-7818

This is reference implementation of ERC-7818

## Implementation Describe

#### Sliding Window Algorithm to look for expiration balance

This contract creates an abstract implementation that adopts the `Sliding Window Algorithm` to maintain a window over a period of time (block height). This efficient approach allows for the look back and calculation of `usable balances` for each account within that window period. With this approach, the contract does not require a variable acting as a `counter` or a `state` to keep updating the latest state, nor does it need any interaction calls to keep updating the current period, which is an effortful and costly design.

<p align="center">
    <img src="implementation.svg" alt="Sliding Window Maintain Balance is Epoch">
</p>

#### `epoch` and `list` for storing data in vertical and horizontal way

```solidity
    // skipping

    struct Epoch {
        uint256 totalBalance;
        mapping(uint256 => uint256) blockBalances;
        SortedList.List list;
    }

    // skipping

    // O(n→) fot traversal each epoch.
    // O(n↓) for traversal each element in list.
    mapping(uint256 => mapping(address => Epoch))) private _balances;
    mapping(uint256 => uint256) private _worldStateBalance;
```

With `epoch` it provides an abstract loop in a horizontal way more efficient for calculating the usable balance of the account because it provides `totalBalance` which acts as suffix balance, so you don't need to get to iterate or traversal over the `list` in vertical to calculate the entire balance if the `epoch` can presume not to expire.
The `_worldStateBalance` mapping tracks the total token balance across all accounts that minted tokens within a particular block. This structure allows the contract to trace expired balances easily. By consolidating balance data for each block.

#### Buffering 1 `epoch` rule for ensuring safety

In this design, the buffering slot is the critical element that requires careful calculation to ensure accurate handling of balances nearing expiration. By incorporating this buffer, the contract guarantees that any expiring balance is correctly accounted for within the sliding window mechanism, ensuring reliability and preventing premature expiration or missed balances.

#### First-In-First-Out (FIFO) priority to enforce token expiration rules

Enforcing `FIFO` priority ensures that tokens nearing expiration are processed before newer ones, aligning with the token lifecycle and expiration rules. This method eliminates the need for additional `off-chain` computation and ensures that all token processing occurs efficiently `on-chain`, fully compliant with the ERC20 interface.
A **sorted** list is integral to this approach. Each `epoch` maintains its own list, sorted by token creation which is can be `block.timestamp` or `blocknumber`, preventing any overlap with other `epoch`. This separation ensures that tokens in one `epoch` do not interfere with the balance handling in another. The contract can then independently manage token expirations within each `epoch`, minimizing computation while maintaining accuracy and predictability in processing balances.

---

#### Token Receipt and Transaction Likelihood across various blocktime

Assuming each year contains 4 `epoch`, which aligns with familiar time-based divisions like a year being divided into four quarters, the following table presents various scenarios based on block time and token receipt intervals. It illustrates the potential transaction frequency and likelihood of receiving tokens within a given period.

| Block Time (ms) | Receive Token Every (ms) | Index/Epoch | Frequency           | Likelihood    |
| --------------- | ------------------------ | ----------- | ------------------- | ------------- |
| 100             | 100                      | 78,892,315  | 864,000 _times/day_ | Very Unlikely |
| 500             | 500                      | 15,778,463  | 172,800 _times/day_ | Very Unlikely |
| 1000            | 1000                     | 7,889,231   | 86,400 _times/day_  | Very Unlikely |
| 1000            | 28,800,000               | 273         | 3 _times/day_       | Unlikely      |
| 1000            | 86,400,000               | 91          | 1 _times/day_       | Possible      |
| 5000            | 86,400,000               | 18          | 1 _times/month_     | Very Likely   |
| 10000           | 86,400,000               | 9           | 3 _times/month_     | Very Likely   |

> [!IMPORTANT]  
> - Transactions per day are assumed based on loyalty point earnings.
> - Likelihood varies depending on the use case; for instance, gaming use cases may have higher transaction volumes than the given estimates.

## Security Considerations in The Reference Implementation

- Solidity Division Rounding Down This implementation contract may encounter scenarios where the calculated expiration block is shorter than the actual expiration block. However, contract mitigates this risk by enforcing valid block times within the defined limits of `MINIMUM_BLOCK_TIME` and `MAXIMUM_BLOCK_TIME`.

## Usage

#### Install Dependencies
```bash
yarn install
```

#### Compile the Contract
Compile the reference implementation
```bash
yarn compile
```

#### Run Tests
Execute the provided test suite to verify the contract's functionality and integrity
```bash
yarn test
```

### Cleaning Build Artifacts
To clean up compiled files and artifacts generated during testing or deployment
```bash
yarn clean
```