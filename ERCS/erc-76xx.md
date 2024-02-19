---
eip: 7627
title: Secure Messaging Protocol
description: A solution for users to securely send encrypted messages to each other.
author: Chen Liaoyuan (@chenly) <cly@kip.pro>
discussions-to: https://ethereum-magicians.org/t/erc-7627-secure-messaging-protocol/18761
status: Draft
type: Standards Track
category: ERC
created: 2024-02-19
---

## Abstract

This proposal implements the capability to securely exchange encrypted messages on-chain. Users can register their public keys and encryption algorithms by registration and subsequently send encrypted messages to other users using their addresses. The interface also includes enumerations for public key algorithms and a structure for user information to support various encryption algorithms and user information management.

## Objectives

1. Provide a standardized interface for implementing messaging systems in smart contracts, including user registration and message sending functionalities.
2. Enhance flexibility and scalability for messaging systems by defining enumerations for public key algorithms and a structure for user information.
3. Define events for tracking message sending to enhance the observability and auditability of the contract.
4. Using a custom sessionId allows messages to be organized into a conversation.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

Implementers of this standard **MUST** have all of the following functions:

``` solidity
pragma solidity ^0.8.0;

interface MessagingSystem {

    // Enums

    /**
     * @dev Enum defining different public key algorithms supported for encryption.
     */
    enum PublicKeyAlgorithm { RSA, ECDSA, ED25519, DSA, DH, ECDH, X25519 }

    // Structs

    /**
     * @dev Struct representing user information including their public key and algorithm.
     */
    struct UserInfo {
        bytes publicKey;
        PublicKeyAlgorithm algorithm;
    }

    // Events

    /**
     * @dev Event emitted when a message is sent.
     * @param from The address of the sender.
     * @param to The address of the recipient.
     * @param sessionId The session ID of the message.
     * @param encryptedMessage The encrypted message.
     */
    event MessageSent(address indexed from, address indexed to, string sessionId, bytes encryptedMessage);

    // Functions

    /**
     * @dev Function to register a user with their public key.
     * @param _publicKey The public key of the user.
     * @param _algorithm The algorithm used for the public key.
     */
    function registerUser(bytes memory _publicKey, PublicKeyAlgorithm _algorithm) external;

    /**
     * @dev Function to send an encrypted message from one user to another.
     * @param _to The address of the recipient.
     * @param _sessionId The session ID of the message.
     * @param _encryptedMessage The encrypted message.
     */
    function sendMessage(address _to, string memory _sessionId, bytes memory _encryptedMessage) external;
}
```

## Rationale

Traditional messaging lacks security and transparency for blockchain communication. A common interface allows easy integration into smart contracts, fostering innovation. Encrypted messaging ensures confidentiality and integrity, promoting data security best practices. The interface supports various encryption methods, enhancing adaptability. Event tracking improves observability and auditability, aiding compliance. Standardization promotes interoperability, enabling seamless communication across platforms.

## Reference Implementation

```solidity
pragma solidity ^0.8.0;

contract MessagingSystem {

    enum PublicKeyAlgorithm { RSA, ECDSA, ED25519, DSA, DH, ECDH, X25519 }

    struct UserInfo {
        bytes publicKey;
        PublicKeyAlgorithm algorithm;
    }

    mapping(address => UserInfo) public users;

    event MessageSent(address indexed from, address indexed to, string sessionId, bytes encryptedMessage);

    // Function to register a user with their public key
    function registerUser(bytes memory _publicKey, PublicKeyAlgorithm _algorithm) public {
        users[msg.sender].publicKey = _publicKey;
        users[msg.sender].algorithm = _algorithm;
    }

    // Function to send an encrypted message from one user to another
    function sendMessage(address _to, string memory _sessionId, bytes memory _encryptedMessage) public {
        emit MessageSent(msg.sender, _to, _sessionId, _encryptedMessage);
    }
}
```

## Security Considerations

### User Authentication

One critical security consideration is user authentication during the registration process. Since the messaging system deals with sensitive information such as encrypted messages, ensuring that only authorized users can register and send messages is paramount. Contracts implementing this interface should employ robust authentication mechanisms, possibly integrating with existing authentication protocols or utilizing cryptographic techniques like digital signatures to verify user identity.

### Encryption and Decryption

Another crucial aspect is the encryption and decryption process used for message transmission. While the contract facilitates encrypted message exchange, it's essential to ensure the confidentiality and integrity of messages. Contracts should utilize well-established cryptographic algorithms and best practices for encryption and decryption operations. Moreover, developers should stay vigilant against potential cryptographic vulnerabilities, such as side-channel attacks or weak key generation, by implementing the latest secure encryption standards.

### Input Validation

Proper input validation is essential to prevent malicious actors from exploiting vulnerabilities in the contract. Contracts should validate user inputs rigorously, including public keys, session IDs, and encrypted messages, to ensure they meet specified criteria and do not contain malicious payloads. Additionally, developers should implement fail-safe mechanisms to handle invalid inputs gracefully, preventing potential contract vulnerabilities such as denial-of-service attacks or unauthorized access.

### Event Log Privacy

While event logs are valuable for contract observability, developers should be cautious about exposing sensitive information through event logs, especially in the context of encrypted messaging. Contracts should avoid logging sensitive message content or personally identifiable information directly in event logs to preserve user privacy. Instead, consider logging only essential metadata or implementing off-chain solutions for auditing and monitoring purposes while maintaining user confidentiality.

### Continuous Security Audits

Lastly, maintaining the security of the messaging system requires continuous security audits and proactive vulnerability management. Regular code reviews, penetration testing, and third-party security audits can help identify and mitigate potential security risks. Additionally, developers should stay informed about emerging security threats and industry best practices, promptly addressing any vulnerabilities or weaknesses identified during the development and deployment lifecycle.


## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md)
