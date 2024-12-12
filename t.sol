/// @title Mailbox contract implementation for synchronous communication
contract Mailbox {
    // ... Constructor + other simple functions like chain_id().

    /// @notice nested map: blockNum -> metadataDigest -> payload
    /// @dev Easy cleanup by `delete inbox[block.number -1]`
    mapping(uint256 => mapping(bytes32 => bytes)) inbox;
    // Mapping to detect key collisions: metadataDigest -> writtenFlag
    mapping(bytes32 => bool) outboxNullifier;

    // These hash values are computed incrementally.
    /// @notice Nested map: blockNum -> srcChainId -> H(...H(m_2 | H(m_1))..)
    /// @dev Easy cleanup by `delete inboxDigest[block.number -1]`
    mapping(uint256 => mapping(uint32 => bytes32)) inboxDigest;
    /// @notice Nested map: blockNum -> destChainId -> H(...H(m_2 | H(m_1))..)
    /// @dev Easy cleanup by `delete outboxDigest[block.number -1]`
    mapping(uint256 => mapping(uint32 => bytes32)) outboxDigest;

    /// @dev Given the metadata (Message struct without payload field) of a message, derive the digest used as the dictionary key for inbox/outbox.
    function getMetadataDigest(
        uint32 srcChainId,
        uint32 destChainId,
        address srcAddress,
        address destAddress,
        uint256 uid
    ) pure public returns (bytes32) {
        return
            keccak(
                abi.encodePacked(
                    srcChainId,
                    destChainId,
                    srcAddress,
                    destAddress,
                    uid
                )
            );
    }

    /// @notice Conceptual "cleanup/reset" of mailbox after each block since sync msgs are received immediately.
    function _resetMailbox() private {
        delete inbox[block.number - 1];
        delete inboxDigest[block.number - 1];
        delete outboxDigest[block.number - 1];
    }

    /// @notice Send a message to another chain
    function send(
        uint32 destChainId,
        address destAddress,
        uint256 uid,
        bytes memory payload
    ) public {
        bytes32 key = getMetadataDigest(
            this.chain_id(),
            destChainId,
            bytes32(srcAddress),
            bytes32(msg.sender),
            uid
        );

        // Prevent overwriting the same key
        require(!outboxNullifier[key]);
        outboxNullifier[key] = true;

        // Update the outbox digest
        // digest' = H(digest | metadata | payload)
        outboxDigest[block.number][this.chain_id()] = keccak256(
            abi.encodePacked(
                outboxDigest[block.number][this.chain_id()],
                key,
                m.payload
            )
        );
    }

    /// @dev This function is called by the Coordinator. It can only be called once per block
    function populateInbox(Message[] calldata messages, bytes memory aux) public {
        // Before putting new inbox messages at the beginning of each block, "reset" the inbox/outbox
        _resetMailbox();

        for (uint i = 0; i < messages.length; i++) {
            Message memory m = messages[i];
            // Reject if the message was not sent to this chain
            require(m.destChainId == this.chain_id());

            bytes32 key = getMetadataDigest(
                m.srcChainid,
                m.srcAddr,
                this.chain_id(),
                m.destAddr,
                m.uid
            );
            inbox[key] = m.payload;

            // Update the inbox digest
            // digest' = H(digest | metadata | payload)
            inboxDigest[block.number][m.srcChainId] = keccak256(
                abi.encodePacked(
                    inboxDigest[block.number][m.srcChainId],
                    key,
                    m.payload
                )
            );
        }
    }

    /// @notice Receive a message from another chain
    function recv(
        uint32 srcChainId,
        address srcAddress,
        address destAddress,
        uint256 uid
    ) public returns (bytes32) {
        bytes32 key = getMetadataDigest(
            srcChainId,
            this.chain_id(),
            bytes32(srcAddress),
            bytes32(destAddress),
            uid
        );
        return inbox[block.number][key];
    }
}
