// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.24;

import { IFrameIntrospector } from "./IFrameIntrospector.sol";

/// @title MockFrameIntrospector: settable stand-in for the EIP-8141 introspector.
/// @dev Test/demo mock only. Lets Foundry tests describe a frame transaction (sender,
///      current frame, and each frame's mode/flags/target/value/data) on today's EVM.
contract MockFrameIntrospector is IFrameIntrospector {
    struct Frame {
        uint256 mode;
        uint256 flags;
        address target;
        uint256 value;
        bytes data;
    }

    address public sender;
    uint256 public current;
    Frame[] internal _frames;

    error FrameOutOfBounds();

    function setTx(address sender_, uint256 current_) external {
        sender = sender_;
        current = current_;
    }

    function clearFrames() external {
        delete _frames;
    }

    function pushFrame(
        uint256 mode,
        uint256 flags,
        address target,
        uint256 value,
        bytes calldata data
    ) external {
        _frames.push(Frame(mode, flags, target, value, data));
    }

    function currentFrameIndex() external view returns (uint256) {
        return current;
    }

    function txSender() external view returns (address) {
        return sender;
    }

    function frameMode(uint256 i) external view returns (uint256) {
        return _frame(i).mode;
    }

    function frameFlags(uint256 i) external view returns (uint256) {
        return _frame(i).flags;
    }

    function frameTarget(uint256 i) external view returns (address) {
        return _frame(i).target;
    }

    function frameValue(uint256 i) external view returns (uint256) {
        return _frame(i).value;
    }

    function frameData(uint256 i) external view returns (bytes memory) {
        return _frame(i).data;
    }

    /// @dev Mirrors EIP-8141: an out-of-bounds frame index halts.
    function _frame(uint256 i) private view returns (Frame storage) {
        if (i >= _frames.length) revert FrameOutOfBounds();
        return _frames[i];
    }
}
