//SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import { ArtifactReflectionCore } from "./ArtifactReflectionCore.sol";
import { PolicyHandler } from "../../PolicyHandler.sol";
import { NodeInitData, InitParams as PolicyInitParams, ExecVariables } from "../../Types.sol";

uint256 constant NOT_ENFORCED_ERR = 1;

/* solhint-disable var-name-mixedcase */
contract BasicPolicyWrapper {
    bytes32 internal ROOT_NODE;
    bool internal isCreated;

    // note: set of artifacts defyining a policy
    ArtifactReflectionCore[] internal artifactsList;

    PolicyHandler internal policyHandler;

    error PolicyEnforcementError(uint256 errotType);

    // todo: make called one time;
    // obsolete, because "policyHandler.set" function allows one call to itself only
    function create() public virtual returns (address policyHandlerAddress) {
        require(isCreated == false, "A;ready created");

        // note: all work with 'artifactsList' and adding artifacts to the 'artifactsList' has to be implmemented
        // in child contract in ovveriden "create" method;
        // then super.create() must be called; and also ROOT_NODE must be set in child contract
        // todo: artifactsList.length > 0
        // todo: ROOT_NODE != bytes32(0);

        NodeInitData[] memory nodeInitDatas = new NodeInitData[](artifactsList.length);

        for (uint256 i = 0; i < artifactsList.length; i++) {
            nodeInitDatas[i] = artifactsList[i].compile();
        }

        policyHandler = new PolicyHandler(address(this));
        policyHandler.set(PolicyInitParams({ nodes: nodeInitDatas, rootNode: ROOT_NODE }));

        isCreated = true;

        return address(policyHandler);
    }

    // todo: authorize caller to the method
    function enforce() public virtual {
        require(isCreated == true, "Policy not created");

        ExecVariables[] memory variables = new ExecVariables[](artifactsList.length);

        for (uint256 i = 0; i < artifactsList.length; i++) {
            variables[i] = artifactsList[i].getVariablesFilled();
        }

        bool result = policyHandler.evaluate(variables);

        // note: policy is enforced
        require(result, PolicyEnforcementError(NOT_ENFORCED_ERR));
    }

    // todo: authorize caller to the method
    function updatePolicy() public virtual {
        require(isCreated == true, "Policy not created");

        // policyHandler.reset(params);
    }
}
