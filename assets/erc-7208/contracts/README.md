# Reference implementation of ERC-7208 and usage examples
## List of contracts
### Interfaces
- [IDataIndex](./interfaces/IDataIndex.sol) - Interface of **DataIndex**
- [IDataObject](./interfaces/IDataObject.sol) - Interface of **DataObject**
- [IDataPointRegistry](./interfaces/IDataPointRegistry.sol) - Interface of Data Point Registry
- [IIDManager](./interfaces/IIDManager.sol) - Interface for building and querying Data Index user identifiers

### Implementation
- [DataIndex](./DataIndex.sol) - Data Index (implements `IDataIndex` and `IIDManager`)
- [DataPointRegistry](./DataPointRegistry.sol) - Data Point Registry (implements `IDataPointRegistry`)
- [DataPoints](./utils/DataPoints.sol) - Library implementing DataPoint type and its encode/decode functions
- [ChainidTools](./utils/ChainidTools.sol) - Library implementing utility functions to work with chain ids

### Usage examples
- [IFractionTransferEventEmitter](./interfaces/IFractionTransferEventEmitter.sol) - Interface used for **DataManagers** communication to emit ERC20 Transfer events
- [IFungibleFractionsOperations](./interfaces/IFungibleFractionsOperations.sol) - Interface defines **DataObject** operations, which can be called by **DataManager**
- [MinimalisticFungibleFractionsDO](./dataobjects/MinimalisticFungibleFractionsDO.sol) - **DataObject** implements data storage and related logic for token  with Fungible Fractions (like ERC1155)
- [MinimalisticERC1155WithERC20FractionsDataManager](./datamanagers/MinimalisticERC1155WithERC20FractionsDataManager.sol) - **DataManager** implements token with fungible fractions with ERC1155 interface, linked to a DataManager which implements ERC20 interface for same token
- [MinimalisticERC20FractionDataManager](./datamanagers/MinimalisticERC20FractionDataManager.sol) - implements token with ERC20 interface, linked to a **DataManager** which implements ERC1155 interface for same token
- [MinimalisticERC20FractionDataManagerFactory](./datamanagers/MinimalisticERC20FractionDataManagerFactory.sol) - factory of **DataManagers** implementing ERC20 interface for token with fungible fractions

---

An audited implementation can be found [here](https://github.com/Nexera-Foundation/Minimalistic-ERC-7208/).