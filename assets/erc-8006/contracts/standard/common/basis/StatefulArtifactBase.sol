//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.30;

import { ArtifactBase } from "./ArtifactBase.sol";
import { ARTIFACT_NOT_INITED_ERR, ARTIFACT_IS_INITED_ERR } from "../../constants/ErrorCodes.sol";

abstract contract StatefulArtifactBase is ArtifactBase {
    bool internal isInited;

    function _init(bytes memory data) internal virtual override {
        (data);
        validateArtifactNotInitalized();
        isInited = true;
    }

    function _exec(
        bytes[] memory data
    ) internal virtual override returns (bytes memory encodedResult) {
        (encodedResult);
        validateArtifactIsInitalized();
        validateExecArgumentsLength(data);
    }

    function validateArtifactIsInitalized() internal view {
        require(isInited, ARTIFACT_NOT_INITED_ERR);
    }

    function validateArtifactNotInitalized() internal view {
        require(isInited == false, ARTIFACT_IS_INITED_ERR);
    }

    function _makeDescription(string memory suffix) internal pure returns (string memory desc) {
        desc = string.concat("Stateful artifact: ", suffix);
    }
}
