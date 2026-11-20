//SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import { StatelessArtifactBase } from "../../erc-8006/StatelessArtifactBase.sol";
import { UINT } from "../../erc-8006/constants/Export.sol";

/* Basic timesource: retrieved from blockchhain itself without timezone shift, etc; */
contract BasicTimeSource is StatelessArtifactBase {
    function getExecDescriptor()
        external
        pure
        override
        returns (string[] memory argsNames, string[] memory argsTypes, string memory returnType)
    {
        (argsNames, argsTypes);
        returnType = UINT;
    }

    function description() external pure override returns (string memory desc) {
        desc = _makeDescription(
            "used to get current block timestamp. Returns uint256 representing current block timestamp in seconds."
        );
    }

    function _exec(bytes[] memory data) internal override returns (bytes memory) {
        super._exec(data);

        return abi.encode(block.timestamp);
    }
}
