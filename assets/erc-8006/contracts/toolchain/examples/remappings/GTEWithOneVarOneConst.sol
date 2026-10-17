//SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import { GTE_ONE_VAR_ONE_CONSTANT } from "../../constants/DeployedArtifacts.sol";
import { ArtifactReflectionCore } from "../../client/ArtifactReflectionCore.sol";
import { ConstantArgument, SubstitutionArgument } from "../../../Types.sol";

// note: artifact that compares if variable value (left-hand operand) is greater
// than or equal to constant value (right-hand operand)
contract GTEWithOneVarOneConst is ArtifactReflectionCore {
    constructor() ArtifactReflectionCore(GTE_ONE_VAR_ONE_CONSTANT) {}

    // note: left-hand operand (supplied as substituion)
    // right-hand operand supplied as constant
    function takes(bytes32 substitutedArgId, uint256 constValue) public {
        addSubstitution(
            SubstitutionArgument({ supplierNodeId: substitutedArgId, index: uint256(0) })
        );
        addConstant(ConstantArgument({ value: abi.encode(constValue), index: uint256(1) }));
    }

    // function with(uint256 constValue) public {
    //     setInitData(abi.encode(constValue));
    // }
}
