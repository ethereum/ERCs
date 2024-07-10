// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IERC7738.sol";

contract DecentralisedRegistry is IERC7738 {
    struct ScriptEntry {
        mapping(address => string[]) scriptURIs;
        address[] addrList;
    }

    mapping(address => ScriptEntry) private _scriptURIs;

    function setScriptURI(
        address contractAddress,
        string[] memory scriptURIList
    ) public {
        require (scriptURIList.length > 0, "> 0 entries required in scriptURIList");
        bool isOwnerOrExistingEntry = Ownable(contractAddress).owner() == msg.sender 
            || _scriptURIs[contractAddress].scriptURIs[msg.sender].length > 0;
        _scriptURIs[contractAddress].scriptURIs[msg.sender] = scriptURIList;
        if (!isOwnerOrExistingEntry) {
            _scriptURIs[contractAddress].addrList.push(msg.sender);
        }
        
        emit ScriptUpdate(contractAddress, msg.sender, scriptURIList);
    }

    function scriptURI(
        address contractAddress
    ) public view returns (string[] memory) {
        //build scriptURI return list, owner first
        address contractOwner = Ownable(contractAddress).owner();
        address[] memory addrList = _scriptURIs[contractAddress].addrList;
        uint256 i;

        //now calculate list length
        uint256 listLen = _scriptURIs[contractAddress].scriptURIs[contractOwner].length;
        for (i = 0; i < addrList.length; i++) {
            listLen += _scriptURIs[contractAddress].scriptURIs[addrList[i]].length;
        }

        string[] memory ownerScripts = new string[](listLen);
        uint256 scriptIndex = 0;

        // Add owner strings
        for (i = 0; i < _scriptURIs[contractAddress].scriptURIs[contractOwner].length; i++) {
            ownerScripts[scriptIndex++] = _scriptURIs[contractAddress].scriptURIs[contractOwner][i];
        }

        // remainder
        for (i = 0; i < addrList.length; i++) {
            for (uint256 j = 0; j < _scriptURIs[contractAddress].scriptURIs[addrList[i]].length; j++) {
                string memory thisScriptURI = _scriptURIs[contractAddress].scriptURIs[addrList[i]][j];
                if (bytes(thisScriptURI).length > 0) {
                    ownerScripts[scriptIndex++] = thisScriptURI;
                }
            }
        }

        //fill remainder of any removed strings
        for (i = scriptIndex; i < listLen; i++) {
            ownerScripts[scriptIndex++] = "";
        }

        return ownerScripts;
    }
}
