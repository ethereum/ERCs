//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.27;

import {
    DUPLICATED_ROOT_NODE_ERR,
    MISSING_ROOT_NODE_ERR,
    INIT_NODES_LIST_IS_LARGER_THAN_MAX_LENGTH_ERR,
    GRAPH_ALREADY_INITIALIZED_ERR,
    GRAPH_NOT_INITIALIZED_ERR
} from "./Errors.sol";
import { Node, Variables, GraphInitParams, CacheRecord, NamedTypedVariables } from "./Types.sol";
import { ArtifactNodes } from "./ArtifactNodes.sol";
import { OwnerBase } from "./OwnerBase.sol";
import { MAX_NODES_LENGTH } from "./Constants.sol";
import "./Utilities.sol" as Utils;

contract PolicyHandler is OwnerBase {
    // todo: design to support ArtifactNodes[] list;
    ArtifactNodes private graph;
    bytes32 private rootNodeId;
    bool private isInitialized = false;

    event Evaluated(bool indexed result, bytes32 indexed rootNode);

    constructor(address _adminUser) OwnerBase(_adminUser) {}

    // todo: consider the scenario when explicit constructor is skipped
    // function init (address _adminUser) public {
    //     require(!isInited, "ERROR");
    //     adminUser = _adminUser;
    //     graph = new ArtifactNodes(adminUser);
    //     isInited = true;
    // }

    function set(GraphInitParams memory params) public onlyOwner returns (address) {
        require(!isInitialized, GRAPH_ALREADY_INITIALIZED_ERR);

        return _set(params);
    }

    function reset(GraphInitParams memory params) public onlyOwner returns (address) {
        require(isInitialized, GRAPH_NOT_INITIALIZED_ERR);

        return _set(params);
    }

    function evaluate(Variables[] memory variables) public onlyOwner returns (bool result) {
        Node memory rootNode = graph.getNodeById(rootNodeId);

        uint256 lastCacheRecord = 0;
        CacheRecord[] memory cache = new CacheRecord[](graph.nodesCount());

        bytes memory encodedResult = graph.evaluateRecursively(
            rootNode,
            variables,
            cache,
            lastCacheRecord
        );

        // note: implicitness
        bool decodedResult = abi.decode(encodedResult, (bool));

        result = decodedResult;

        emit Evaluated(result, rootNodeId);
    }

    // note: this should return what run-time arguments has to be supplied to Node;
    // the arguments consists of node.variables and node.substitutions
    function getVariablesList() public view returns (NamedTypedVariables[] memory) {
        return Utils.getVariablesListInternal(graph.getNodes());
    }

    function _set(GraphInitParams memory params) internal onlyOwner returns (address) {
        // note: solves https://ethereum.stackexchange.com/questions/142102/solidity-1024-call-stack-depth as ad-hoc
        // todo: bring instead sophisticated check
        require(
            params.nodes.length <= MAX_NODES_LENGTH,
            INIT_NODES_LIST_IS_LARGER_THAN_MAX_LENGTH_ERR
        );
        graph = new ArtifactNodes(address(this));

        _addNodes(params);

        // todo: add the way to validate graph.node[params.rootNode] evaluates as bool
        rootNodeId = params.rootNode;

        isInitialized = true;

        return address(graph);
    }

    function _addNodes(GraphInitParams memory params) private {
        uint256 rootNodeIncludeCount;

        for (uint256 i = 0; i < params.nodes.length; i++) {
            graph.addNode(params.nodes[i]);

            if (params.rootNode == params.nodes[i].id) {
                rootNodeIncludeCount++;
            }
        }

        require(rootNodeIncludeCount != 0, MISSING_ROOT_NODE_ERR);
        require(rootNodeIncludeCount == 1, DUPLICATED_ROOT_NODE_ERR);
    }
}
