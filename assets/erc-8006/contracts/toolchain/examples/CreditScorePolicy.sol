//SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import { AND1 } from "./remappings/AND1.sol";
import { GTEWithOneVarOneConst } from "./remappings/GTEWithOneVarOneConst.sol";
import { Now1 } from "./remappings/Now1.sol";
import { BasicPolicyWrapper } from "../client/BasicPolicyWrapper.sol";
import { AND } from "../../core-primitives/logical/AndBool.sol";
import { GteUint } from "../../core-primitives/comparison/GteUint.sol";
import { BasicTimeSource } from "../../core-primitives/time/BasicTimeSource.sol";

/* POLICY RULES: (now >= uint256-const) && bool-variable;

    can be depicted as tree:
                    and_artifact
                    /            \
    greater_than_equal_artifact   bool variable
                /       \
        now_time_atifact   contant_value
 */
contract CreditScorePolicy is BasicPolicyWrapper {
    bool private runTimeVariable;
    // Friday, 29 May 2026 at 22:26:35
    uint256 private constant CONSTANT_PARAMETER_TIMESTAMP = 1780093595;

    constructor() {
        isCreated = false;
    }

    function create() public override returns (address) {
        // note: create artifact instances

        AND1 and1 = new AND1();
        // new AND() is ad hoc
        and1.updateArtifactAddress(address(new AND()));

        GTEWithOneVarOneConst gte = new GTEWithOneVarOneConst();
        // ad hoc
        gte.updateArtifactAddress(address(new GteUint()));

        Now1 now1 = new Now1();
        // ad hoc
        now1.updateArtifactAddress(address(new BasicTimeSource()));

        // note: add artifacts to list
        artifactsList.push(and1);
        artifactsList.push(gte);
        artifactsList.push(now1);

        // note: "gte artifact" compares variable and constant;
        // note: there are 2 execution arguments;
        // 1st is substitution (because relies on result of now1 artifact);
        // 2nd is constant value
        gte.takes(now1.self(), CONSTANT_PARAMETER_TIMESTAMP);

        // note: "and artifact" calculate boolean expression between two args; each argument is supplied as variable
        // there are exec 2 args;
        // 1st is substitution
        // 2nd is is variable (retrieved via getter func)
        and1.takes(gte.self(), this.getSecondVarEncoded);

        ROOT_NODE = and1.self();

        // note: MANDATORY call to parent method
        return super.create();
    }

    function assignExecVariables(bool value) public {
        runTimeVariable = value;
    }

    // todo: check allowed caller is this(address)
    function getSecondVarEncoded() public view returns (bytes memory) {
        // runTimeVariable is second argument for "and" artifact
        return abi.encode(runTimeVariable);
    }
}
