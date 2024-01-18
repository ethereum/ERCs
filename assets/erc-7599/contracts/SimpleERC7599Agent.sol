// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.16;

import "./interfaces/IERC7599.sol";

/**
 * @title SimpleERC7594Agent
 * Used for tests
 */
contract SimpleERC7599Agent is IERC7594 {
    uint256 public nonce;

    string public _abilityURI;

    uint256 public _index;

    address public _serviceAddress;

    mapping(uint256 => bytes) public responses;

    error AmountNotEnoughFailed();

    error RequestHadHandled();

    receive() external payable {}

    function executeCall( address to, uint256 value, bytes calldata data ) external payable returns (bytes memory result) {
        require(msg.sender == owner(), "Not token owner");
        ++nonce;
        emit TransactionExecuted(to, value, data);
        bool success;
        (success, result) = to.call{value: value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    function token() external view returns ( uint256, address, uint256 ) {
        bytes memory footer = new bytes(0x60);

        assembly {
            // copy 0x60 bytes from end of footer
            extcodecopy(address(), add(footer, 0x20), 0x4d, 0xad)
        }

        return abi.decode(footer, (uint256, address, uint256));
    }

    function owner() public view returns (address) {
        (uint256 chainId, address tokenContract, uint256 tokenId) = this.token();
        if (chainId != block.chainid) return address(0);

        return IERC721(tokenContract).ownerOf(tokenId);
    }


    modifier onlyService() {
        require(msg.sender == _serviceAddress, "Not the agent service");
        _;
    }

    function abilityURI() external view returns(string memory) {
        return _abilityURI;
    }

    function setAbilityURI(string memory uri) external {
        _abilityURI = uri;

        emit AbilityURIUpdated(uri);
    }

    function requestAgent(bytes memory input) payable public {
        if (msg.value < 0.001 ether) {
            revert AmountNotEnoughFailed();
        }

        emit AgentRequested(_index++, input);
    }

    function handleAgentResponse(uint256 index, bytes response) public onlyService {
        if (responses[index].length > 0) {
            revert RequestHadHandled();
        }
        responses[index] = response;
    }
}
