//SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import { NOW } from "../../constants/DeployedArtifacts.sol";
import { ArtifactReflectionCore } from "../../client/ArtifactReflectionCore.sol";

contract Now1 is ArtifactReflectionCore {
    constructor() ArtifactReflectionCore(NOW) {}
}
