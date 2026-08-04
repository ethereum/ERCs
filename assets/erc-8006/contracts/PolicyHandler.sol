//SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import { ExecVariables, InitParams as PolicyInitParams } from "./Types.sol";
import { ExecVarsMetadata } from "./UtilTypes.sol";
import { OwnerBaseInitializable } from "./OwnerBaseInitializable.sol";
import { MAX_NODES_LENGTH } from "./Constants.sol";
import { PolicyMetadata } from "./PolicyMetadata.sol";
import "./Utilities.sol" as Utils;
import {
    POLICY_DOES_NOT_HAVE_ANY_ARTIFACT_ERR,
    INIT_NODES_LIST_IS_LARGER_THAN_MAX_LENGTH_ERR,
    POLICY_ALREADY_INITIALIZED_ERR,
    POLICY_NOT_INITIALIZED_ERR
} from "./Errors.sol";
import { IPolicyHandler } from "./Interfaces.sol";

contract PolicyHandler is IPolicyHandler, OwnerBaseInitializable {
    PolicyMetadata internal dag;
    bool private isPolicyInitialized = false;

    constructor(address _adminUser) {
        initializeOwnable(_adminUser);
    }

    // note: initialises policy handler with rules (list of linked artifacts)
    function set(PolicyInitParams memory params) public onlyOwner {
        require(!isPolicyInitialized, POLICY_ALREADY_INITIALIZED_ERR);

        _set(params);

        emit Set(dag.rootNodeId(), params.nodes.length);
    }

    // note: re-initialises policy handler with rules (list of linked artifacts);
    // at the same time previous configuraion is abandoned
    function reset(PolicyInitParams memory params) public onlyOwner {
        require(isPolicyInitialized, POLICY_NOT_INITIALIZED_ERR);

        // todo: consider pros/cons of the optimised approach (where the existing graph modified), instead of creating of new instance
        _set(params);

        emit Upgraded(dag.rootNodeId(), params.nodes.length);
    }

    // note: evaluates the policy check result by traversing all graph starring from root node;
    // artifcats input params "variables" are forwareded to respective artifcats
    function evaluate(ExecVariables[] memory variables) public onlyOwner returns (bool result) {
        // todo: validate 'variableValues' contains only known node-ids
        // todo: validate 'variableValues' does not contain duplicates

        bytes memory encodedResult = dag.evaluateRecursively(dag.rootNodeId(), variables);

        // note: decoded ==> result
        result = abi.decode(encodedResult, (bool));

        emit Evaluated(result, dag.rootNodeId());
    }

    // note: this should return arguments list for only these args that have are run-time supplied (to a particular Node)
    function getVariablesListDecoded() public view returns (ExecVarsMetadata[] memory list) {
        require(isPolicyInitialized, POLICY_NOT_INITIALIZED_ERR);

        list = Utils.getVarsDesriptionList(dag.getNodes());
    }

    // note: this should return arguments list as bytes list for only these args that have are run-time supplied (to a particular Node)
    function getVariablesList() public view returns (bytes[] memory list) {
        ExecVarsMetadata[] memory vars = getVariablesListDecoded();

        list = new bytes[](vars.length);
        for (uint256 i = 0; i < vars.length; i++) {
            list[i] = abi.encode(vars[i]);
        }
    }

    function _set(PolicyInitParams memory params) internal onlyOwner {
        require(params.nodes.length > 0, POLICY_DOES_NOT_HAVE_ANY_ARTIFACT_ERR);
        // todo: work out a robust check to verify the number of nodes is allowed number
        // note: solves https://ethereum.stackexchange.com/questions/142102/solidity-1024-call-stack-depth as ad-hoc
        require(
            params.nodes.length <= MAX_NODES_LENGTH,
            INIT_NODES_LIST_IS_LARGER_THAN_MAX_LENGTH_ERR
        );

        dag = new PolicyMetadata(address(this));
        dag.init(params);

        isPolicyInitialized = true;
    }
}
