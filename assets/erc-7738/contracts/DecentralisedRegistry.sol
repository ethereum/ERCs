// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IERC7738.sol";

contract DecentralisedRegistry is IERC7738 {
    struct ScriptEntry {
        mapping(address => string[]) scriptURIs;
        address[] addrList;
    }

    uint256 public constant MAX_PAGE_SIZE = 500;
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
        return scriptURI(contractAddress, 1, MAX_PAGE_SIZE);
    }

    function scriptURI(address contractAddress, uint256 page, uint256 pageSize) public view returns (string[] memory ownerScripts) {
        require(page > 0 && pageSize > 0 && pageSize <= MAX_PAGE_SIZE, "Page >= 1 and pageSize <= MAX_PAGE_SIZE");
        
        address contractOwner = Ownable(contractAddress).owner();
        address[] memory addrList = _scriptURIs[contractAddress].addrList;
        uint256 startPoint = pageSize * (page - 1);

        uint256 listLen = _scriptURIs[contractAddress].scriptURIs[contractOwner].length;
        for (uint256 i = 0; i < addrList.length; i++) {
            listLen += _scriptURIs[contractAddress].scriptURIs[addrList[i]].length;
        }

        uint256 arrayLen = listLen < pageSize ? listLen : pageSize;
        ownerScripts = new string[](arrayLen);
        uint256 scriptIndex = 0;
        uint256 currentIndex = 0;

        if (startPoint >= listLen) {
            return new string[](0) ;
        }

        // Add owner scriptURIs
        (scriptIndex, currentIndex) = _addScriptURIs(contractOwner, contractAddress, startPoint, scriptIndex, pageSize, ownerScripts, currentIndex);

        // Add remainder of scriptURIs
        for (uint256 i = 0; i < addrList.length && scriptIndex < pageSize; i++) {
            (scriptIndex, currentIndex) = _addScriptURIs(addrList[i], contractAddress, startPoint, scriptIndex, pageSize, ownerScripts, currentIndex);
        }
    }

    function _addScriptURIs(
        address user,
        address contractAddress,
        uint256 startPoint,
        uint256 scriptIndex,
        uint256 pageSize,
        string[] memory ownerScripts,
        uint256 currentIndex
    ) internal view returns (uint256, uint256) {
        for (uint256 j = 0; j < _scriptURIs[contractAddress].scriptURIs[user].length; j++) {
            string memory thisScriptURI = _scriptURIs[contractAddress].scriptURIs[user][j];
            if (bytes(thisScriptURI).length > 0) {
                if (currentIndex >= startPoint) {
                    ownerScripts[scriptIndex++] = thisScriptURI;
                }
                if (scriptIndex >= pageSize) {
                    break;
                }
            }
            currentIndex++;
        }
        return (scriptIndex, currentIndex);
    }
}
