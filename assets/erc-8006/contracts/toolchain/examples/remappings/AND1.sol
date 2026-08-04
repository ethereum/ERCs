//SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import { AND } from "../../constants/DeployedArtifacts.sol";
import { ArtifactReflectionCore } from "../../client/ArtifactReflectionCore.sol";
import { SubstitutionArgument } from "../../../Types.sol";

// note left-hand operand is variable, right-hand operand is variable
// result = left-hand operand & right-hand operand
contract AND1 is ArtifactReflectionCore {
    constructor() ArtifactReflectionCore(AND) {}

    // note: left-hand operand (supplied as substituion);
    // right-hand operand supplied as variable
    function takes(
        bytes32 substitutedVarA,
        function() external view returns (bytes memory) getVarB // getter to retrieve second variable
    ) public {
        // note: substition expects res of <node> on pos 1
        addSubstitution(
            SubstitutionArgument({ supplierNodeId: substitutedVarA, index: uint256(0) })
        );

        // note: expect var on 2nd pos (retrieved from getVarB), which has index 1
        addVariableGetter(uint256(1), getVarB);
    }

    // note: no constant operand supplied for the artifact
    // function with() public {
    //     // setInitData(abi.encode(constValue));
    // }
}
