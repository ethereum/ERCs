
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;
interface IERC7738 {
    /// @dev This event emits when the scriptURI is updated, 
    /// so wallets implementing this interface can update a cached script
    event ScriptUpdate(address indexed contractAddress, address indexed setter, string[] newScriptURI);

    /// @notice Get the scriptURI for the contract
    /// @return The scriptURI
    function scriptURI(address contractAddress) external view returns (string[] memory);

    /// @notice Update the scriptURI 
    /// emits event ScriptUpdate(address indexed contractAddress, scriptURI memory newScriptURI);
<<<<<<< HEAD
    function setScriptURI(address contractAddress, string[] calldata scriptURIList) external;
=======
    function setScriptURI(address contractAddress, string[] memory scriptURIList) external;
>>>>>>> 4a582f5016fd4065b7a851531340835b2bad9bb6
}