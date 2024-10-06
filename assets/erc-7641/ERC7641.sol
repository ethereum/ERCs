// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IERC7641.sol";

contract ERC7641 is ERC20Snapshot, IERC7641 {
    /**
     * @dev last snapshotted block
     */
    uint256 private _lastSnapshotBlock;

    /**
     * @dev percentage claimable
     */
    uint256 immutable public percentClaimable;

    /**
     * @dev mapping from snapshot id to address to the amount of ETH claimable at the snapshot.
     */
    mapping (uint256 => uint256) private _claimableAtSnapshot;

    /**
     * @dev mapping from snapshot id to a boolean indicating whether the address has claimed the revenue.
     */
    mapping (uint256 => mapping (address => bool)) private _claimedAtSnapshot;

    /**
     * @dev claim pool
     */
    uint256 private _claimPool;

    /**
     * @dev burn pool
     */
    uint256 private _burnPool;

    /**
     * @dev burned from new revenue
     */
    uint256 private _burned;

    /**
     * @dev Constructor for the ERC7641 contract, premint the total supply to the contract creator.
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param supply The total supply of the token
     */
    constructor(string memory name, string memory symbol, uint256 supply, uint256 _percentClaimable) ERC20(name, symbol) {
        require(_percentClaimable <= 100, "ERC7641: percentage claimable should be less than 100");
        percentClaimable = _percentClaimable;
        _lastSnapshotBlock = block.number;
        _mint(msg.sender, supply);
    }

    /**
     * @dev A function to calculate the amount of ETH claimable by a token holder at certain snapshot.
     * @param account The address of the token holder
     * @param snapshotId The snapshot id
     * @return The amount of revenue token claimable
     */
    function claimableRevenue(address account, uint256 snapshotId) public view returns (uint256) {
        uint256 balance = balanceOfAt(account, snapshotId);
        uint256 totalSupply = totalSupplyAt(snapshotId);
        uint256 ethClaimable = _claimableAtSnapshot[snapshotId];
        return _claimedAtSnapshot[snapshotId][account] ? 0 : balance * ethClaimable / totalSupply;
    }

    /**
     * @dev A function for token holder to claim revenue token based on the token balance at certain snapshot.
     * @param snapshotId The snapshot id
     */
    function claim(uint256 snapshotId) public {
        uint256 claimableETH = claimableRevenue(msg.sender, snapshotId);
        require(claimableETH > 0, "ERC7641: no claimable ETH");

        _claimedAtSnapshot[snapshotId][msg.sender] = true;
        _claimPool -= claimableETH;
        (bool success, ) = msg.sender.call{value: claimableETH}("");
        require(success, "ERC7641: claim failed");
    }
    
    /**
     * @dev A function to claim by a list of snapshot ids.
     * @param snapshotIds The list of snapshot ids
     */
    function claimBatch(uint256[] memory snapshotIds) public {
        for (uint256 i = 0; i < snapshotIds.length; i++) {
            claim(snapshotIds[i]);
        }
    }
    
    /**
     * @dev A snapshot function that also records the deposited ETH amount at the time of the snapshot.
     * @return The snapshot id
     * @notice example requirement: only 1000 blocks after the last snapshot
     */
    function snapshot() public returns (uint256) {
        require(block.number - _lastSnapshotBlock > 1000, "ERC7641: snapshot interval is too short");
        uint256 snapshotId = _snapshot();
        _lastSnapshotBlock = block.number;
        
        uint256 newRevenue = address(this).balance + _burned - _claimPool - _burnPool;

        uint256 claimableETH = newRevenue * percentClaimable / 100;
        _claimableAtSnapshot[snapshotId] = claimableETH;
        _claimPool += claimableETH;
        _burnPool += newRevenue - claimableETH - _burned;
        _burned = 0;

        return snapshotId;
    }

    /**
     * @dev A function to calculate the amount of ETH redeemable by a token holder upon burn
     * @param amount The amount of token to burn
     * @return The amount of revenue ETH redeemable
     */
    function redeemableOnBurn(uint256 amount) public view returns (uint256) {
        uint256 totalSupply = totalSupply();
        uint256 newRevenue = address(this).balance + _burned - _claimPool - _burnPool;
        uint256 burnableFromNewRevenue = amount * (newRevenue * (100 - percentClaimable) - _burned * 100) / 100 / totalSupply;
        uint256 burnableFromPool = amount * _burnPool / totalSupply;
        return burnableFromNewRevenue + burnableFromPool;
    }

    /**
     * @dev A function to burn tokens and redeem the corresponding amount of revenue token
     * @param amount The amount of token to burn
     */
    function burn(uint256 amount) public {
        uint256 totalSupply = totalSupply();
        uint256 newRevenue = address(this).balance + _burned - _claimPool - _burnPool;
        uint256 burnableFromNewRevenue = amount * (newRevenue * (100 - percentClaimable) - _burned * 100)  / 100 / totalSupply;
        uint256 burnableFromPool = amount * _burnPool / totalSupply;
        _burnPool -= burnableFromPool;
        _burned += burnableFromNewRevenue;
        _burn(msg.sender, amount);
        (bool success, ) = msg.sender.call{value: burnableFromNewRevenue + burnableFromPool}("");
        require(success, "ERC7641: burn failed");
    }

    receive() external payable {}
}