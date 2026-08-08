// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IAgentExecutor} from "./interfaces/IAgentExecutor.sol";
import {IAgentMandate} from "./interfaces/IAgentMandate.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title AgentExecutor
/// @notice Reference IAgentExecutor bound to one principal. An agent calls execute; the executor reads the
///         gated amount from the forwarded calldata, gates it against the mandate, records it, then forwards.
contract AgentExecutor is IAgentExecutor, Ownable, ReentrancyGuard {
    /// @param supported Whether this selector may be executed.
    /// @param hasAmount False for value-less actions (gate at amount 0).
    /// @param amountIndex Index of the uint256 amount argument.
    struct ActionSpec {
        bool supported;
        bool hasAmount;
        uint8 amountIndex;
    }

    IAgentMandate public immutable rams;
    address public immutable principal;

    mapping(bytes4 selector => ActionSpec) public actions;

    error UnsupportedAction(bytes4 selector);
    error InvalidData();
    error CannotExecute(address agent, address target, bytes4 selector, uint256 amount);
    error CallFailed(bytes returnData);

    constructor(IAgentMandate _rams, address _principal, address owner_) Ownable(owner_) {
        rams = _rams;
        principal = _principal;
    }

    /// @notice Sets how an action's amount is read. A wrong amountIndex mis-gates the cap, so treat this
    ///         like the enforcer role.
    function setAction(bytes4 selector, bool supported, bool hasAmount, uint8 amountIndex) external onlyOwner {
        actions[selector] = ActionSpec({supported: supported, hasAmount: hasAmount, amountIndex: amountIndex});
    }

    /// @inheritdoc IAgentExecutor
    function execute(address target, bytes calldata data) external nonReentrant returns (bytes memory) {
        if (data.length < 4) revert InvalidData();

        address agent = msg.sender;
        bytes4 selector = bytes4(data[:4]);
        ActionSpec memory spec = actions[selector];
        if (!spec.supported) revert UnsupportedAction(selector);

        uint256 amount = spec.hasAmount ? _amountArg(data, spec.amountIndex) : 0;
        bytes32 action = bytes32(selector);

        if (!rams.canExecute(agent, principal, target, action, amount)) {
            revert CannotExecute(agent, target, selector, amount);
        }

        rams.recordExecution(agent, principal, action, amount);

        (bool ok, bytes memory ret) = target.call(data);
        if (!ok) revert CallFailed(ret);
        return ret;
    }

    /// @dev A uint256 argument sits at 4 + 32*index in calldata, so this reads the amount by index.
    function _amountArg(bytes calldata data, uint8 index) internal pure returns (uint256) {
        uint256 offset = 4 + uint256(index) * 32;
        if (data.length < offset + 32) revert InvalidData();
        return uint256(bytes32(data[offset:offset + 32]));
    }
}
