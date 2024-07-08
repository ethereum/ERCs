---
eip: -
title: Custom data access model
description: Custom data access model is a design model that supports any form of access to the contract's storage to obtain the corresponding data.
author: Elon Lee (@1999321)
discussions-to: https://ethereum-magicians.org/t/custom-data-access-model/20337
status: Draft
type: Standards Track
category: ERC
created: 2024-06
---

## Abstract

The custom data access model uses solidity's delegate mode to obtain the contract's data read permissions. Corresponding reading logic can be developed through any third-party contract to obtain the desired data form. This model can save gas costs when it requires multiple accesses to the memory of a contract to obtain the final data form. It can even embed the required data processing logic directly into the agent contract, which is equivalent to native execution of data. Access and compute without making external calls.

## Motivation

When you need to access the data of other contracts, you are often limited by the data access logic customized by the contract. If you only need to access the data once, then this will not have a big impact, but when you need to access the data of other contracts in a function, When data is accessed multiple times, each access needs to consume the gas of an external call, which is a huge consumption compared to accessing data. In order to save the cost of external calls when frequently accessing the same contract data, and to have more freedom to perform customized data logic processing on native data,  custom data access model was introduced.

When developing a contract, there is no need to reserve a large amount of code specifically for data access (such as numerous `public` variables and `view` functions), which can also greatly expand the logic code that a contract can accommodate.

## Specification

Two contracts need to be implemented：

1. `StaticCallTransfer`:This is a global contract, which is the entrance contract for obtaining data. All contracts that implement custom data access models can be accessed through this entrance. The functions forwarded by this contract are all static calls.

   

   ```solidity
   // CC0 1.0 Universal (CC0 1.0) Public Domain Dedication
   pragma solidity ^0.8.24;
   
   interface IStaticCallTransfer {
   
       /**
        * @dev Retrieves custom data from a data contract using a static call to a logic contract.
        * @param dataContract The address of the data contract.
        * @param logicContract The address of the logic contract.
        * @param _data The data to be passed to the logic contract.
        * @return _re The result of the static call to the logic contract.
        */
       function getCustomData(
           address dataContract,
           address logicContract,
           bytes memory _data
       ) external returns (bytes memory _re);
   }
   ```

   

   `getCustomData`：Data processing logic can be embedded through this interface to obtain the data form of any contract.

2. `_Data`:The contract implements a custom data access model by inheriting `_Data`.

   

   ```solidity
   // CC0 1.0 Universal (CC0 1.0) Public Domain Dedication
   pragma solidity ^0.8.24;
   
   interface I_Data {
       /**
        * @dev Executes a data function on a logic contract.
        * @param logicContract The address of the logic contract.
        * @param _data The data to be executed on the logic contract.
        * @return _re The result of executing the data function.
        */
       function _data_(address logicContract, bytes memory _data) external returns (bytes memory _re);
   }
   ```

   

   `_data_`：The function accessed by `StaticCallTransfer` uses this function to make proxy calls to achieve the purpose of embedding data processing logic.

## Rationale

The subsequent `_data_` function access controlled through `StaticCallTransfer` can only be a proxy with read permissions, but not write permissions. Embed data processing logic through proxy mode.

## Backwards Compatibility

Fully compatible.

## Reference Implementation

```solidity
// CC0 1.0 Universal (CC0 1.0) Public Domain Dedication
pragma solidity ^0.8.24;

import "./interfaces/IStaticCallTransfer.sol";
import {I_Data} from "./interfaces/I_Data.sol";

contract StaticCallTransfer is IStaticCallTransfer {
    function transferStaticCall(address to, bytes memory data) public view returns (bytes memory _re) {

        assembly {
            let size := mload(data)
            let ptr := add(data, 0x20)
            let result := staticcall(gas(), to, ptr, size, 0, 0)
            let size2 := returndatasize()
            _re := mload(0x40)
            mstore(0x40, add(_re, add(size2, 0x20)))
            mstore(_re, size2)
            returndatacopy(add(_re, 0x20), 0, size2)
            switch result
            case 0 {
                revert(0, 0)
            }
        }
        _re = abi.decode(_re, (bytes));
    }

    function getCustomData(address dataContract, address logicContract, bytes memory _data) external view returns (bytes memory _re) {
        bytes memory data = abi.encodeWithSelector(I_Data._data_.selector, logicContract, _data);
        return transferStaticCall(dataContract, data);
    }
}
```



```solidity
// CC0 1.0 Universal (CC0 1.0) Public Domain Dedication
pragma solidity ^0.8.24;

import {I_Data} from "./interfaces/I_Data.sol";

contract _Data {
	address immutable staticCallTransfer;
	
	constructor(address _staticCallTransfer) {
		staticCallTransfer = _staticCallTransfer;
	}
	
    function _data_(address logicContract, bytes memory _data) external returns (bytes memory _re) {
    	require(msg.sender == staticCallTransfer,"_Data: only Static Call");
        (bool success, bytes memory result) = logicContract.delegatecall(
            abi.encodeWithSelector(
                I_Data._data_.selector, _data)
            );
        require(success, "_Data: _data_ failed");
        return result;
    }
}
```



The contract `Dapp` inherits `_Data` to implement a custom data access model:



```solidity
// CC0 1.0 Universal (CC0 1.0) Public Domain Dedication
pragma solidity ^0.8.24;

import {_Data} from "./_Data.sol";

contract Dapp is _Data {

    address private private_data;
    
    constructor(address _staticCallTransfer) _Data(_staticCallTransfer) {}


}
```



Although `private_data` is declared `private`, it can also be accessed through the following `AccessDapp` contract:



```solidity
// CC0 1.0 Universal (CC0 1.0) Public Domain Dedication
pragma solidity ^0.8.24;

contract AccessDapp {

    address public private_data;

}
```



## Security Considerations

Data security is ensured through `staticcall`. It only has read permission and cannot pose any threat to the contract.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).

