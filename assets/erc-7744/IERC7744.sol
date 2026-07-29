// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.8.0 <0.9.0;

interface IERC7744 {
    event Indexed(address indexed container, bytes32 indexed codeHash);
    error alreadyExists(bytes32 id, address source);

    function isEIP7702(address account) external view returns (bool);

    function register(address container) external;

    function get(bytes32 id) external view returns (address);
}
