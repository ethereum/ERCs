//SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import { StatelessArtifactBase } from "../../erc-8006/StatelessArtifactBase.sol";
import { BOOL } from "../../erc-8006/constants/Export.sol";

contract XOR is StatelessArtifactBase {
    function getExecDescriptor()
        external
        pure
        override
        returns (string[] memory argsNames, string[] memory argsTypes, string memory returnType)
    {
        uint256 argsLength = 2;

        argsNames = new string[](argsLength);
        argsNames[0] = "argA";
        argsNames[1] = "argB";

        argsTypes = new string[](argsLength);
        argsTypes[0] = BOOL;
        argsTypes[1] = BOOL;

        returnType = BOOL;
    }

    function description() external pure override returns (string memory desc) {
        desc = _makeDescription(
            "used to perform logical XOR operation on two boolean values. First parameter - argA, second one - argB. Returns bool representing exclusive OR (true when exactly one argument is true)."
        );
    }

    function _exec(bytes[] memory data) internal override returns (bytes memory encodedResult) {
        super._exec(data);

        bool argA = abi.decode(data[0], (bool));
        bool argB = abi.decode(data[1], (bool));

        bool result = xor(argA, argB);
        encodedResult = abi.encode(result);
    }

    function xor(bool argA, bool argB) internal pure returns (bool result) {
        result = (argA || argB) && !(argA && argB);
    }
}
