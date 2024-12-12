/// ERC20 token contract supporting cross-chain transfers
contract XChainToken is ERC20Burnable {
    /// @notice points to the Mailbox contract used
    Mailbox public mailbox;
    /// @notice bitmap for redeem-once control on inbox messages
    mapping(bytes32 => bool) private isRedeemed;
    /// @notice maps chainId to the canonical XChainToken address
    mapping(uint32 => address) public xChainTokenAddress;

    /// @notice use this function to transfer some amount of this token to another address on another chain
    /// @param destAddress receiver address
    /// @param amount amount to transfer
    /// @param destChainId identifier of the destination chain
    function xTransfer(
        uint32 destChainId,
        address destAddress,
        uint256 amount
    ) external returns (bool) {
        // Burn the token of the caller
        this.burn(amount);

        // Write a message to the Mailbox to notify the other chain that the token have been successfully burnt.
        bytes memory payload = abi.encodePacked(amount, destAddress); // Specify the amount to be minted and the recipient
        mailbox.send(
            Mailbox.Metadata(
                mailbox.chain_id(),
                destChainId,
                bytes32(address(this)),
                bytes32(xChainTokenAddress[destChainId]),
                mailbox.randSessionId(),
                0
            ),
            payload
        );
    }

    /// @notice This function must be called on the destination chain to mint the tokens. This function can be called by any participant.
    /// @param srcChainId identifier of the source chain the funds are sent from
    ///	@param sessionId unique identifier needed to fetch the message
    function xReceive(uint32 srcChainId, uint128 sessionId) public {
        /// Analoguous to crossTransfer except that this function can only be called once with the same parameters
        /// in order to avoid double minting. A mapping struct like isRedeemed can be used for this purpose.
        bytes memory payload = mailbox.recv(
            Mailbox.Metadata(
                srcChainId,
                mailbox.chain_id(),
                bytes32(xChainTokenAddress[srcChainId]),
                bytes32(address(this)),
                sessionId,
                0
            )
        );
        (uint256 amount, address destAddress) = abi.decode(
            payload,
            (uint256, address)
        );
        this.transfer(destAddress, amount);
    }
}
