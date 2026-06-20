// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {IFrameValidator} from "./IFrameValidator.sol";

contract ECDSAFrameValidator is IFrameValidator {
    uint8 internal constant APPROVE_NONE = 0x0;
    uint256 internal constant MODULE_TYPE_VALIDATOR = 1;
    uint256 internal constant MODE_SENDER = 2;

    mapping(address => address) public ownerOf;

    function onInstall(bytes calldata data) external override {
        ownerOf[msg.sender] = address(bytes20(data[0:20]));
    }

    function onUninstall(bytes calldata) external override {
        delete ownerOf[msg.sender];
    }

    function isModuleType(uint256 moduleTypeId) external pure override returns (bool) {
        return moduleTypeId == MODULE_TYPE_VALIDATOR;
    }

    function validateFrame(bytes32, uint256, uint8 allowedScope, bytes calldata data)
        external
        view
        override
        returns (uint8 approvalMode)
    {
        address owner = ownerOf[msg.sender];
        if (owner == address(0) || data.length != 65) return APPROVE_NONE; // data: r(32) || s(32) || v(1)

        bytes32 r = bytes32(data[0:32]);
        bytes32 s = bytes32(data[32:64]);
        uint8 v = uint8(data[64]);

        address signer = ecrecover(_authDigest(), v, r, s);
        if (signer != address(0) && signer == owner) {
            return allowedScope; // account clamps this to the frame's allowed scope
        }
        return APPROVE_NONE;
    }

    // A signature in VERIFY-frame data cannot sign over TXPARAM(0x08) (that hash commits the
    // frame data, so it would be circular). Instead reconstruct the digest from the SENDER
    // frames plus chain id, nonce, and sender, excluding the VERIFY frame's own data.
    function _authDigest() internal view returns (bytes32) {
        uint256 nonce;
        uint256 sender;
        uint256 numFrames;
        assembly {
            nonce := verbatim_1i_1o(hex"b0", 0x01) // TXPARAM nonce
            sender := verbatim_1i_1o(hex"b0", 0x02) // TXPARAM sender
            numFrames := verbatim_1i_1o(hex"b0", 0x09) // TXPARAM len(frames)
        }

        bytes memory preimage = abi.encodePacked(block.chainid, nonce, sender);

        for (uint256 i = 0; i < numFrames; i++) {
            uint256 mode;
            assembly {
                mode := verbatim_2i_1o(hex"b3", i, 0x02) // FRAMEPARAM(frameIndex=i, param=0x02 mode)
            }
            if (mode != MODE_SENDER) continue;

            uint256 target;
            uint256 value;
            uint256 dataLen;
            assembly {
                target := verbatim_2i_1o(hex"b3", i, 0x00) // FRAMEPARAM(frameIndex=i, param=0x00 resolved_target)
                value := verbatim_2i_1o(hex"b3", i, 0x08) // FRAMEPARAM(frameIndex=i, param=0x08 value)
                dataLen := verbatim_2i_1o(hex"b3", i, 0x04) // FRAMEPARAM(frameIndex=i, param=0x04 len(data))
            }

            bytes memory frameData = new bytes(dataLen);
            assembly {
                // FRAMEDATACOPY(memOffset, dataOffset, length, frameIndex); memOffset is leftmost (top of stack)
                verbatim_4i_0o(hex"b2", add(frameData, 0x20), 0, dataLen, i)
            }

            // dataLen included so adjacent frames' calldata cannot collide in the packed preimage
            preimage = abi.encodePacked(preimage, target, value, dataLen, frameData);
        }

        return keccak256(preimage);
    }
}
