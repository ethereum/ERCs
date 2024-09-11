// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IERC7738.sol";

contract DecentralisedRegistryPermissioned is IERC7738 {
    struct ScriptEntry {
        string[] scriptURIs;
        address[] delegateSigners; // list of authenticated addresses approved by owner
        address owner; // provides a latch so that 3rd parties can create TokenScript entries
    }

    mapping(address => ScriptEntry) private _scriptURIs;

<<<<<<< HEAD
    uint256 ll = 0;

=======
>>>>>>> 4a582f5016fd4065b7a851531340835b2bad9bb6
    event RegisterOwner(
        address indexed contractAddress,
        address indexed newOwner
    );
    event AddDelegateSigner(
        address indexed contractAddress,
        address indexed newDelegate
    );
    event RevokeDelegateSigner(
        address indexed contractAddress,
        address indexed revokedDelegate
    );

    function scriptURI(
        address contractAddress
    ) public view returns (string[] memory) {
        return _scriptURIs[contractAddress].scriptURIs;
    }

    function setScriptURI(
        address contractAddress,
        string[] memory scriptURIList
    ) public {
        // in order to set scriptURI array, the sender must adhere to the following rules:
        require(
            isDelegateOrOwner(contractAddress, msg.sender),
            "Not authorized"
        );

        emit ScriptUpdate(contractAddress, msg.sender, scriptURIList);
        _scriptURIs[contractAddress].scriptURIs = scriptURIList;
    }

    function registerOwner(address contractAddress) public {
        ScriptEntry storage existingEntry = _scriptURIs[contractAddress];
        address contractOwner = Ownable(contractAddress).owner();
        address sender = msg.sender;
        require(existingEntry.owner != sender, "Already set to this owner");
        require(
            existingEntry.owner == address(0) || sender == contractOwner,
            "Not authorized"
        );
        emit RegisterOwner(contractAddress, sender);
        existingEntry.owner = sender;
<<<<<<< HEAD
        ll++;
=======
>>>>>>> 4a582f5016fd4065b7a851531340835b2bad9bb6
    }

    function isDelegateOrOwner(
        address contractAddress,
        address check
    ) public view returns (bool) {
        ScriptEntry memory existingEntry = _scriptURIs[contractAddress];
        if (check == Ownable(contractAddress).owner()) {
            return true;
        }
        uint256 length = existingEntry.delegateSigners.length;
        for (uint256 i = 0; i < length; ) {
            if (existingEntry.delegateSigners[i] == check) {
                return true;
            }
            unchecked {
                i++;
            }
        }
        return false;
    }

    function getDelegateIndex(
        address contractAddress,
        address check
    ) public view returns (int256) {
        ScriptEntry memory existingEntry = _scriptURIs[contractAddress];
        uint256 length = existingEntry.delegateSigners.length;
        for (uint256 i = 0; i < length; ) {
            if (existingEntry.delegateSigners[i] == check) {
                return int256(i);
            }
            unchecked {
                i++;
            }
        }
        return -1;
    }

    function addDelegateSigner(
        address contractAddress,
        address newSigner
    ) public {
        require(
            msg.sender == Ownable(contractAddress).owner(),
            "Contract Owner only"
        );
        require(
            getDelegateIndex(contractAddress, newSigner) < 0,
            "Already a delegate signer"
        );
        emit AddDelegateSigner(contractAddress, newSigner);
        _scriptURIs[contractAddress].delegateSigners.push(newSigner);
    }

    function revokeDelegateSigner(
        address contractAddress,
        address signer
    ) public {
        int256 delegateIndex = getDelegateIndex(contractAddress, signer);
        require(
            msg.sender == Ownable(contractAddress).owner(),
            "Contract Owner only"
        );
        require(delegateIndex > -1, "Unable to revoke unknown signer");
        emit RevokeDelegateSigner(contractAddress, signer);
        delete _scriptURIs[contractAddress].delegateSigners[
            uint256(delegateIndex)
        ];
    }
}
