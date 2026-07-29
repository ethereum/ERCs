// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Modified from https://github.com/erc6551/reference/tree/main/src/lib

library ERC7656ServiceLib {
  function implementation(address service) internal view returns (address implementation_) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      // copy proxy implementation (0x14 bytes)
      extcodecopy(service, 0xC, 0xA, 0x14)
      implementation_ := mload(0x00)
    }
  }

  function implementation() internal view returns (address _implementation) {
    return implementation(address(this));
  }

  function linkedData(address service) internal view returns (uint256, bytes12, address, uint256) {
    bytes memory encodedData = new bytes(0x60);
    // solhint-disable-next-line no-inline-assembly
    assembly {
      // Copy 0x60 bytes from end of context
      extcodecopy(service, add(encodedData, 0x20), 0x4d, 0x60)
    }

    uint256 chainId;
    bytes32 linkedContract;
    uint256 linkedId;

    // solhint-disable-next-line no-inline-assembly
    assembly {
      chainId := mload(add(encodedData, 0x20))
      linkedContract := mload(add(encodedData, 0x40))
      linkedId := mload(add(encodedData, 0x60))
    }

    bytes12 mode = bytes12(linkedContract);

    address extractedAddress = address(uint160(uint256(linkedContract)));
    return (chainId, mode, extractedAddress, linkedId);
  }

  function salt(address service) internal view returns (bytes32) {
    bytes memory encodedData = new bytes(0x20);
    // solhint-disable-next-line no-inline-assembly
    assembly {
      // copy 0x20 bytes from beginning of context
      extcodecopy(service, add(encodedData, 0x20), 0x2d, 0x20)
    }

    return abi.decode(encodedData, (bytes32));
  }

  function salt() internal view returns (bytes32) {
    return salt(address(this));
  }

}
