//SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {
    SubstitutionArgument,
    ConstantArgument,
    NodeInitData,
    ExecVariables
} from "../../Types.sol";

// note: onchain representation of artifact data/info/params
contract ArtifactReflectionCore {
    // init data of artifact-instance (can be "0x")
    bytes internal initData;

    NodeInitData internal unInitedNode; // artifact init data

    mapping(uint256 => function() external view returns (bytes memory)) internal variableGetters;

    // todo: validate artifactAddress not nil
    constructor(address artifactAddress) {
        unInitedNode.artifactAddress = artifactAddress;
    }

    // todo: authentication
    // todo: run only before "compile"
    function updateArtifactAddress(address artifactAddress) public {
        // todo: verify artifactAddress satisfies required interface
        unInitedNode.artifactAddress = artifactAddress;
    }

    // note: return complete artifact init data
    function compile() public returns (NodeInitData memory) {
        uint256 totalArgs = unInitedNode.variableExecArgs.length +
            unInitedNode.constantExecArgs.length +
            unInitedNode.substitutedExecArgs.length;
        unInitedNode.id = self();
        unInitedNode.argsCount = totalArgs;
        // note: redundant; unInitedNode.injections storage array is already empty
        // unInitedNode.injections = new InjectionMetadata[](0); // not required while pure run time policy creation

        return unInitedNode;
    }

    function getVariablesFilled() public view returns (ExecVariables memory) {
        uint256[] memory argsIndexes = unInitedNode.variableExecArgs;
        bytes[] memory values = new bytes[](argsIndexes.length);

        for (uint256 i = 0; i < argsIndexes.length; i++) {
            values[i] = variableGetters[argsIndexes[i]](); // todo: encode
        }

        ExecVariables memory variables = ExecVariables({ nodeId: self(), values: values });

        return variables;
    }

    // note: consumed as unique node-id
    function self() public view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this)));
    }

    // todo: authentication
    // note: if called then needsInitialization=true (only for Stateful artifact-instance)
    function setInitData(bytes memory _initData) public virtual {
        unInitedNode.needsInitialization = true;

        // note: at this point artifact consume constructor params
        if (_initData.length > 0) {
            unInitedNode.initData = _initData;
        }
    }

    // todo: authentication
    function addConstant(ConstantArgument memory constValue) public virtual {
        unInitedNode.constantExecArgs.push(constValue);
    }

    // todo: authentication
    function addSubstitution(SubstitutionArgument memory substitution) public virtual {
        unInitedNode.substitutedExecArgs.push(substitution);
    }

    // todo: authentication
    function addVariableGetter(
        uint256 index, // variableIndex
        function() external view returns (bytes memory) getterFunc
    ) public virtual {
        unInitedNode.variableExecArgs.push(index);
        variableGetters[index] = getterFunc;
    }
}
