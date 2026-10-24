//SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import { StatefulArtifactBase } from "../../erc-8006/StatefulArtifactBase.sol";
import { ADDRESS, BOOL, BYTES } from "../../erc-8006/constants/Export.sol";
import { DestinationBlacklistInternal } from "./DestinationBlacklistInternal.sol";

contract DestinationBlacklist is StatefulArtifactBase, DestinationBlacklistInternal {
    function getInitDescriptor()
        external
        pure
        override
        returns (string[] memory argsNames, string[] memory argsTypes)
    {
        uint256 argsLength = 1;

        argsNames = new string[](argsLength);
        argsNames[0] = "serializedBlacklist";

        argsTypes = new string[](argsLength);
        argsTypes[0] = BYTES;
    }

    function getExecDescriptor()
        external
        pure
        override
        returns (string[] memory argsNames, string[] memory argsTypes, string memory returnType)
    {
        uint256 argsLength = 1;

        argsNames = new string[](argsLength);
        argsNames[0] = "receiver";

        argsTypes = new string[](argsLength);
        argsTypes[0] = ADDRESS;
        returnType = BOOL;
    }

    function description() external pure override returns (string memory desc) {
        desc = _makeDescription(
            "used to check if an address is blacklisted. Parameter - receiver address to check. Returns bool representing whether the address is blacklisted."
        );
    }

    function _init(bytes memory data) internal override {
        // note: trigger base configuration & validations
        super._init(data);

        bytes memory serializedWhitelist = abi.decode(data, (bytes));

        address[] memory _whitelist = abi.decode(serializedWhitelist, (address[]));

        _initializeDestinationsMapping(_whitelist);
    }

    function _exec(bytes[] memory data) internal override returns (bytes memory encodedResult) {
        // note: trigger base validations
        super._exec(data);

        address receiverAddress = abi.decode(data[0], (address));

        bool isBlacklisted = checkDestination(receiverAddress);
        encodedResult = abi.encode(isBlacklisted);
    }
}
