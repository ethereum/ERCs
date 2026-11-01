# ERC-8226: Regulated Agent Mandate (RAMS) reference implementation

Reference implementation for ERC-8226. Under development.

## Layout

| Path | Contents |
|---|---|
| `contracts/interfaces/IAgentMandate.sol` | Mandate lifecycle, recording, freeze, and view interface |
| `contracts/interfaces/IComplianceProvider.sol` | Principal eligibility interface |
| `contracts/interfaces/IAgentExecutor.sol` | Optional account-side executor interface |
| `contracts/AgentMandate.sol` | RAMS registry (reference implementation) |
| `contracts/ComplianceProvider.sol` | Reference compliance provider |
| `contracts/AgentExecutor.sol` | Reference executor (optional venue) |
| `contracts/RamsGated.sol` | Reference base contract for the token gate venue |
| `contracts/mocks/IERC7943.sol` | ERC-7943 interface (vendored, used by the tests) |
| `contracts/mocks/uRWA20.sol` | ERC-7943 uRWA-20 regulated asset (vendored). Ungated: the target the executor venue forwards to |
| `contracts/mocks/RamsGatedURWA20.sol` | The same asset gated by RAMS, one action label per gated function |
| `test/` | Foundry tests |

## Build

```sh
forge build
forge test
```
