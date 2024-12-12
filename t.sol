/// @title Metadata type
/// @notice Metadata for a cross-chain message
struct Metadata {
    /// @notice The chain identifier of the source chain
    uint32 srcChainId;
    /// @notice The chain identifier of the destination chain
    uint32 destChainId;
    /// @notice The address of the sending party
    /// @dev 32 bytes are used to encode the address. In the case of an Ethereum address, the last 12 bytes can be padded with zeros
    bytes32 srcAddress;
    /// @notice The address of the recipient
    /// @dev 32 bytes are used to encode the address. In the case of an Ethereum address, the last 12 bytes can be padded with zeros
    bytes32 destAddress;
    /// @notice The identifier for a cross-chain interaction session
    /// @dev SHOULD be unique for every new cross-chain calls
    uint128 sessionId;
    /// @notice The message counter within an interaction session 
    /// @dev SHOULD be unique within a session
    /// @dev OPTIONAL for most asynchronous bridges where every message has a distinct sessionId, simply set to 0 if unused
    /// @dev E.g. In a cross-chain call: ChainA.func1 -m1-> ChainB.func2 -m2-> ChainC.func3 -m3-> ChainB.func4, the subscript i in m_i is the nonce
    uint128 nonce;
}

/// @title Message type
/// @notice A cross-chain message
struct Message {
    /// @notice The message metadata 
    Metadata metadata;
    /// @notice Message payload encoded using RLP serialization
    /// @dev It may be ABI-encoded function calls, info about bridged assets, or arbitrary message data
    bytes payload;
}