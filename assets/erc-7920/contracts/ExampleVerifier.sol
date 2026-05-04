// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

error Unauthorized();
error NotInTree();

contract ExampleVerifier {
    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 private constant MESSAGE_TYPEHASH =
        keccak256("PlaceOrder(bytes32 orderId, address user)");

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("MyApp")),
                keccak256(bytes("1.0.0")),
                block.chainid,
                address(this)
            )
        );
    }

    function placeOrder(
        bytes32 orderId,
        address user,
        bytes calldata signature,
        bytes32 merkleRoot,
        bytes32[] calldata proof
    ) public {
        bytes32 message = keccak256(
            abi.encode(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(MESSAGE_TYPEHASH, orderId, user))
            )
        );

        if (
            !_verifyCompositeSignature(
                message,
                proof,
                merkleRoot,
                signature,
                user
            )
        ) {
            revert Unauthorized();
        }

        // DO STUFF
    }

    function _verifyCompositeSignature(
        bytes32 message,
        bytes32[] calldata proof,
        bytes32 merkleRoot,
        bytes calldata signature,
        address expectedSigner
    ) internal view returns (bool) {
        if (!_verifyMerkleProof(message, proof, merkleRoot)) {
            revert NotInTree();
        }

        return _recover(merkleRoot, signature) == expectedSigner;
    }

    function _verifyMerkleProof(
        bytes32 leaf,
        bytes32[] calldata proof,
        bytes32 root
    ) internal pure returns (bool) {
        bytes32 computedRoot = leaf;
        for (uint256 i = 0; i < proof.length; ++i) {
            if (computedRoot < proof[i]) {
                computedRoot = keccak256(abi.encode(computedRoot, proof[i]));
            } else {
                computedRoot = keccak256(abi.encode(proof[i], computedRoot));
            }
        }

        return computedRoot == root;
    }

    function _recover(
        bytes32 digest,
        bytes memory signature
    ) internal pure returns (address) {
        require(signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        return ecrecover(digest, v, r, s);
    }

    // Debug function to generate message
    function debugGenerateMessageHash(
        bytes32 orderId,
        address user
    ) public view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    keccak256(abi.encode(MESSAGE_TYPEHASH, orderId, user))
                )
            );
    }
}
