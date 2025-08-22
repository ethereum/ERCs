//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.30;

import { ArtifactBase } from "./ArtifactBase.sol";

abstract contract StatelessArtifactBase is ArtifactBase {
    function _init(bytes memory data) internal virtual override {
        (data);
    }

    function _exec(
        bytes[] memory data
    ) internal virtual override returns (bytes memory encodedResult) {
        (encodedResult);
        validateExecArgumentsLength(data);
    }

    function _makeDescription(string memory suffix) internal pure returns (string memory desc) {
        desc = string.concat("Stateless artifact: ", suffix);
    }
}
