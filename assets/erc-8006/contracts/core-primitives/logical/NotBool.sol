//SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import { StatelessArtifactBase } from "../../erc-8006/StatelessArtifactBase.sol";
import { BOOL } from "../../erc-8006/constants/Export.sol";

contract NOT is StatelessArtifactBase {
    function getExecDescriptor()
        external
        pure
        override
        returns (string[] memory argsNames, string[] memory argsTypes, string memory returnType)
    {
        uint256 argsLength = 1;

        argsNames = new string[](argsLength);
        argsNames[0] = "argA";

        argsTypes = new string[](argsLength);
        argsTypes[0] = BOOL;

        returnType = BOOL;
    }

    function description() external pure override returns (string memory desc) {
        desc = _makeDescription(
            "used to perform logical NOT operation on a boolean value. Parameter - argA. Returns bool representing (!argA)."
        );
    }

    function _exec(bytes[] memory data) internal override returns (bytes memory) {
        super._exec(data);

        bool argA = abi.decode(data[0], (bool));

        return abi.encode(!argA);
    }
}
