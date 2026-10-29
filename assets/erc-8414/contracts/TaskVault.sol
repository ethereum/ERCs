// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

interface IERC20Payout {
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @title  TaskVault — per-token locked bounty vault (TASK-KERNEL v3.0).
/// @notice One vault per task token, deployed at mint. The vault is the reverse
///         asset's credit foundation: its balance is directly visible to any
///         explorer, anyone can deposit (deposits count as escrow), and funds can
///         leave ONLY at the instruction of the controlling task contract, which
///         itself only instructs payouts through settlement and refund.
///         There is no owner, no upgrade path, and no other exit.
/// @dev    Reference mechanism satisfying the standard's vault invariants; an
///         ERC-6551 token-bound account with a locked implementation (owner
///         execution stripped) satisfies them equally and is the recommended
///         profile for token-bound-account composability.
contract TaskVault {
    address public immutable controller;

    constructor() {
        controller = msg.sender; // the TaskToken contract deploying this vault
    }

    /// @notice Anyone may deposit native assets directly; such deposits are
    ///         unattributed bounty gifts (see the standard's refund rules).
    receive() external payable {}

    /// @notice Release funds on a PULL path -- a refund, a residual, or a credited
    ///         payout being withdrawn. The beneficiary asked for this money, so all
    ///         remaining gas is forwarded and failure reverts: there is no third party
    ///         whose settlement could be held hostage by the recipient's receive hook,
    ///         and capping the gas here would strand exactly the contracts the credit
    ///         mechanism exists to rescue.
    function payout(address asset, address to, uint256 amount) external {
        require(msg.sender == controller, "TaskVault: not controller");
        bool ok;
        if (asset == address(0)) {
            (ok, ) = payable(to).call{value: amount}("");
        } else {
            ok = _erc20(asset, to, amount);
        }
        require(ok, "TaskVault: payout failed");
    }

    /// @dev Gas forwarded to a native recipient on the push path. See tryPayout.
    uint256 internal constant PUSH_GAS = 150_000;

    /// @notice Attempt a payout and report the outcome instead of reverting on a
    ///         recipient that will not take the money. A settlement must not be made
    ///         to depend on the recipient's willingness to receive: a contract with a
    ///         reverting fallback would otherwise wedge the submission forever and,
    ///         with it, every refund behind it. The controller credits the amount for
    ///         later withdrawal when this returns false.
    ///
    ///         The forwarded budget is bounded but generous. A hostile recipient on
    ///         this PUSH path can burn what it is given and gains nothing -- the
    ///         amount is credited either way -- but an unbounded forward would let it
    ///         consume the settling party's whole transaction. 30_000 was too tight:
    ///         an ordinary receiver that records the payment already exceeds it, and a
    ///         team split contract sits right on the edge.
    function tryPayout(address asset, address to, uint256 amount) public returns (bool) {
        require(msg.sender == controller, "TaskVault: not controller");
        if (asset == address(0)) {
            (bool ok, ) = payable(to).call{value: amount, gas: PUSH_GAS}("");
            return ok;
        }
        return _erc20(asset, to, amount);
    }

    /// @dev Transfer an ERC-20 without ever reverting on the token's reply. A token
    ///      that answers with a malformed word -- too short, or a "bool" outside
    ///      {0,1} -- would revert inside abi.decode and wedge the submission that the
    ///      non-reverting path exists to protect, so the reply is read as a number and
    ///      anything unreadable is reported as a failed transfer rather than thrown.
    function _erc20(address asset, address to, uint256 amount) private returns (bool) {
        (bool called, bytes memory data) =
            asset.call(abi.encodeWithSelector(IERC20Payout.transfer.selector, to, amount));
        if (!called) return false;
        if (data.length == 0) return true;
        if (data.length < 32) return false;
        return abi.decode(data, (uint256)) != 0;
    }
}
