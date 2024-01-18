interface IERC6551Account {
    event TransactionExecuted(address indexed target, uint256 indexed value, bytes data);
    receive() external payable;
    function executeCall( address to, uint256 value, bytes calldata data ) external payable returns (bytes memory);
    function token() external view returns ( uint256 chainId, address tokenContract, uint256 tokenId );
    function owner() external view returns (address);
    function nonce() external view returns (uint256);
}

interface IERC7599 is IERC6551Account {
    /**
     * @notice This event emits when the agent is requested, The off-chain service needs to listen, perform the task, and return the result
     */
    event AgentRequested(uint256 index, bytes input);

    /**
     * @notice This event emits when the abilityURI is updated
     */
    event AbilityURIUpdated(string uri);

    /**
     * @notice Get the abilityURI for the AI Agent
     * @return The abilityURI
     */
    function abilityURI() external view returns(string memory);

    /**
     * @notice Update the abilityURI
     */
    function setAbilityURI(string memory uri) external;

    /**
     * @notice Request agent with input
     */
    function requestAgent(bytes memory input) payable external;

    /**
     * @notice Handle agent response with index
     */
    function handleAgentResponse(uint256 index, bytes response) external;
}
