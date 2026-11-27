// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {IAgentExecutor} from "./interfaces/IAgentExecutor.sol";
import {IAgentMandate} from "./interfaces/IAgentMandate.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {SignerEIP7702} from "@openzeppelin/contracts/utils/cryptography/signers/SignerEIP7702.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title AgentExecutor
/// @notice Reference IAgentExecutor, run as EIP-7702 delegate code. An agent calls execute on the principal's
///         account; the executor gates the call against the mandate, forwards it, then records as flows the change
///         of the principal's balance in each token that the mandate limits: the decrease for an OUTFLOW limit, the
///         increase for an INFLOW limit.
/// @dev One deployment per chain and registry serves every account: the principal is the account that runs the code.
///      It has no configuration: the mandate alone decides what the agent may do.
contract AgentExecutor is IAgentExecutor, IERC1271, SignerEIP7702, ReentrancyGuard, ERC721Holder {
    IAgentMandate public immutable rams;

    error InvalidData();
    error CannotExecute(address agent, address target, bytes4 selector, IAgentMandate.MandateReason reason);
    error CallFailed(bytes returnData);

    constructor(IAgentMandate ramsRegistry) {
        rams = ramsRegistry;
    }

    /// @notice Accepts ETH, so a principal that delegates its account to this code can still receive it.
    receive() external payable {}

    /// @inheritdoc IAgentExecutor
    function execute(address target, bytes calldata data) external nonReentrant returns (bytes memory returnData) {
        if (data.length < 4) revert InvalidData();

        address agent = msg.sender;
        bytes32 action = bytes32(bytes4(data[:4]));
        _check(agent, target, action, data);

        IAgentMandate.Limit[] memory limits = rams.getLimits(agent, address(this), target);
        uint256[] memory held = new uint256[](limits.length);
        for (uint256 index = 0; index < limits.length; index++) {
            held[index] = IERC20(limits[index].asset).balanceOf(address(this));
        }

        bool ok;
        (ok, returnData) = target.call(data);
        if (!ok) revert CallFailed(returnData);

        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](limits.length);
        for (uint256 index = 0; index < limits.length; index++) {
            uint256 remaining = IERC20(limits[index].asset).balanceOf(address(this));
            (uint256 start, uint256 end) = limits[index].direction == IAgentMandate.Direction.OUTFLOW
                ? (held[index], remaining)
                : (remaining, held[index]);
            flows[index] =
                IAgentMandate.Flow(limits[index].asset, limits[index].direction, start > end ? start - end : 0);
        }
        rams.recordExecution(agent, address(this), target, action, data, flows);
    }

    /// @notice Lets the delegated account keep signing: a signature is valid when the account's own key signed the hash.
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        return _rawSignatureValidation(hash, signature) ? IERC1271.isValidSignature.selector : bytes4(0xffffffff);
    }

    function _check(address agent, address target, bytes32 action, bytes calldata data) private view {
        (bool allowed, IAgentMandate.MandateReason reason) =
            rams.canExecute(agent, address(this), target, action, data, new IAgentMandate.Flow[](0));
        if (!allowed) revert CannotExecute(agent, target, bytes4(action), reason);
    }
}
