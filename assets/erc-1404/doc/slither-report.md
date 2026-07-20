<!-- ============================ SUMMARY (prepended) ============================ -->
# Slither Report — Summary

**Tool**: Slither `0.11.5` · **Date**: 2026-07-20 · **Scope**: `src/` (mocks & tests **excluded**)

**Command**

```bash
slither . --checklist \
  --filter-paths "node_modules,submodules,test,forge-std,mocks" \
  > doc/slither-report.md
```

**Severity tally: `0 High · 0 Medium · 0 Low · 5 Informational`** (5 results, 17 contracts analyzed)

| Detector | Severity | Instances | Assessment |
|---|---|---|---|
| `pragma` | Informational | 1 | **By design** — the multiple version constraints (`>=0.4.16`, `>=0.6.2`, `>=0.8.4`) are all OpenZeppelin library headers; every first-party file (including the new `ERC1404SpenderAware.sol` / `IERC1404SpenderAware.sol`) pins `^0.8.20`. |
| `solc-version` | Informational | 4 | **By design** — flagged constraints belong to OZ dependencies; the exact compiler (`0.8.34`) is pinned in `foundry.toml`. |

**Verdict: nothing to fix.** No High/Medium/Low results; only dependency-driven informational notes, unchanged in nature since the previous run (the two new spender-aware files add no new detector categories). Full triage: [`slither-feedback.md`](./slither-feedback.md)

<!-- ===================== RAW SLITHER OUTPUT BELOW ===================== -->

**THIS CHECKLIST IS NOT COMPLETE**. Use `--show-ignored-findings` to show all the results.
Summary
 - [pragma](#pragma) (1 results) (Informational)
 - [solc-version](#solc-version) (4 results) (Informational)
## pragma
Impact: Informational
Confidence: High
 - [ ] ID-0
4 different versions of Solidity are used:
	- Version constraint ^0.8.20 is used by:
		-[^0.8.20](lib/openzeppelin-contracts/contracts/access/Ownable.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/utils/Context.sol#L4)
		-[^0.8.20](lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol#L4)
		-[^0.8.20](src/ERC1404.sol#L2)
		-[^0.8.20](src/ERC1404SpenderAware.sol#L2)
		-[^0.8.20](src/IERC1404.sol#L2)
		-[^0.8.20](src/IERC1404SpenderAware.sol#L2)
		-[^0.8.20](src/engine/IERC1404Restriction.sol#L2)
		-[^0.8.20](src/engine/RestrictedToken.sol#L2)
		-[^0.8.20](src/engine/WhitelistRuleEngine.sol#L2)
	- Version constraint >=0.8.4 is used by:
		-[>=0.8.4](lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol#L4)
	- Version constraint >=0.4.16 is used by:
		-[>=0.4.16](lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol#L4)
		-[>=0.4.16](lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol#L4)
	- Version constraint >=0.6.2 is used by:
		-[>=0.6.2](lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol#L4)

lib/openzeppelin-contracts/contracts/access/Ownable.sol#L4


## solc-version
Impact: Informational
Confidence: High
 - [ ] ID-1
Version constraint ^0.8.20 contains known severe issues (https://solidity.readthedocs.io/en/latest/bugs.html)
	- VerbatimInvalidDeduplication
	- FullInlinerNonExpressionSplitArgumentEvaluationOrder
	- MissingSideEffectsOnSelectorAccess.
It is used by:
	- [^0.8.20](lib/openzeppelin-contracts/contracts/access/Ownable.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/utils/Context.sol#L4)
	- [^0.8.20](lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol#L4)
	- [^0.8.20](src/ERC1404.sol#L2)
	- [^0.8.20](src/ERC1404SpenderAware.sol#L2)
	- [^0.8.20](src/IERC1404.sol#L2)
	- [^0.8.20](src/IERC1404SpenderAware.sol#L2)
	- [^0.8.20](src/engine/IERC1404Restriction.sol#L2)
	- [^0.8.20](src/engine/RestrictedToken.sol#L2)
	- [^0.8.20](src/engine/WhitelistRuleEngine.sol#L2)

lib/openzeppelin-contracts/contracts/access/Ownable.sol#L4


 - [ ] ID-2
Version constraint >=0.6.2 contains known severe issues (https://solidity.readthedocs.io/en/latest/bugs.html)
	- MissingSideEffectsOnSelectorAccess
	- AbiReencodingHeadOverflowWithStaticArrayCleanup
	- DirtyBytesArrayToStorage
	- NestedCalldataArrayAbiReencodingSizeValidation
	- ABIDecodeTwoDimensionalArrayMemory
	- KeccakCaching
	- EmptyByteArrayCopy
	- DynamicArrayCleanup
	- MissingEscapingInFormatting
	- ArraySliceDynamicallyEncodedBaseType
	- ImplicitConstructorCallvalueCheck
	- TupleAssignmentMultiStackSlotComponents
	- MemoryArrayCreationOverflow.
It is used by:
	- [>=0.6.2](lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol#L4)

lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol#L4


 - [ ] ID-3
Version constraint >=0.8.4 contains known severe issues (https://solidity.readthedocs.io/en/latest/bugs.html)
	- FullInlinerNonExpressionSplitArgumentEvaluationOrder
	- MissingSideEffectsOnSelectorAccess
	- AbiReencodingHeadOverflowWithStaticArrayCleanup
	- DirtyBytesArrayToStorage
	- DataLocationChangeInInternalOverride
	- NestedCalldataArrayAbiReencodingSizeValidation
	- SignedImmutables.
It is used by:
	- [>=0.8.4](lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol#L4)

lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol#L4


 - [ ] ID-4
Version constraint >=0.4.16 contains known severe issues (https://solidity.readthedocs.io/en/latest/bugs.html)
	- DirtyBytesArrayToStorage
	- ABIDecodeTwoDimensionalArrayMemory
	- KeccakCaching
	- EmptyByteArrayCopy
	- DynamicArrayCleanup
	- ImplicitConstructorCallvalueCheck
	- TupleAssignmentMultiStackSlotComponents
	- MemoryArrayCreationOverflow
	- privateCanBeOverridden
	- SignedArrayStorageCopy
	- ABIEncoderV2StorageArrayWithMultiSlotElement
	- DynamicConstructorArgumentsClippedABIV2
	- UninitializedFunctionPointerInConstructor_0.4.x
	- IncorrectEventSignatureInLibraries_0.4.x
	- ExpExponentCleanup
	- NestedArrayFunctionCallDecoder
	- ZeroFunctionSelector.
It is used by:
	- [>=0.4.16](lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol#L4)
	- [>=0.4.16](lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol#L4)

lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol#L4


