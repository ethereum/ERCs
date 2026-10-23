// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IERC7621} from "./interfaces/IERC7621.sol";

/**
 * @title BasketToken
 * @notice Minimal reference implementation of ERC-7621.
 * @dev The basket contract IS the ERC-20 share token. Ownership follows ERC-173.
 *      Valuation uses sum-of-reserves (no oracle). First deposit mints dead shares
 *      to mitigate inflation attacks.
 */
contract BasketToken is ERC20, IERC7621, IERC165, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- Constants ---

    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant DEAD_SHARES = 1000;
    address public constant DEAD_ADDRESS = address(0xdead);

    // --- Storage ---

    address private _owner;
    address[] private _tokens;
    mapping(address => uint256) private _weights;
    mapping(address => uint256) private _reserves;
    mapping(address => bool) private _isConstituent;

    // --- ERC-173 Events ---

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // --- ERC-173 Errors ---

    error Unauthorized();

    // --- Constructor ---

    constructor(
        string memory name_,
        string memory symbol_,
        address initialOwner,
        address[] memory tokens,
        uint256[] memory weights
    ) ERC20(name_, symbol_) {
        if (tokens.length != weights.length) {
            revert LengthMismatch(tokens.length, weights.length);
        }

        _validateConstituents(tokens, weights);
        _setConstituents(tokens, weights);

        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    // --- ERC-173 ---

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external {
        if (msg.sender != _owner) revert Unauthorized();
        address previous = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(previous, newOwner);
    }

    // --- ERC-165 ---

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return
            interfaceId == 0xc9c80f73 || // IERC7621
            interfaceId == 0x7f5828d0 || // IERC173
            interfaceId == 0x01ffc9a7;   // IERC165
    }

    // --- View Functions ---

    function getConstituents()
        external view override returns (address[] memory tokens, uint256[] memory weights)
    {
        uint256 len = _tokens.length;
        tokens = new address[](len);
        weights = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            tokens[i] = _tokens[i];
            weights[i] = _weights[_tokens[i]];
        }
    }

    function totalConstituents() external view override returns (uint256) {
        return _tokens.length;
    }

    function getReserve(address token) external view override returns (uint256) {
        return _reserves[token];
    }

    function getWeight(address token) external view override returns (uint256) {
        if (!_isConstituent[token]) revert NotConstituent(token);
        return _weights[token];
    }

    function isConstituent(address token) external view override returns (bool) {
        return _isConstituent[token];
    }

    function totalBasketValue() public view override returns (uint256 value) {
        for (uint256 i = 0; i < _tokens.length; i++) {
            value += _reserves[_tokens[i]];
        }
    }

    // --- Actions ---

    function contribute(
        uint256[] calldata amounts,
        address receiver,
        uint256 minShares
    ) external override nonReentrant returns (uint256 lpAmount) {
        uint256 len = _tokens.length;
        if (amounts.length != len) revert LengthMismatch(len, amounts.length);

        lpAmount = _calculateContribution(amounts);
        if (lpAmount == 0) revert ZeroAmount();
        if (lpAmount < minShares) revert InsufficientShares(minShares, lpAmount);

        bool isFirst = totalSupply() == 0;

        // Transfer tokens in and update reserves
        for (uint256 i = 0; i < len; i++) {
            if (amounts[i] > 0) {
                IERC20(_tokens[i]).safeTransferFrom(msg.sender, address(this), amounts[i]);
                _reserves[_tokens[i]] += amounts[i];
            }
        }

        // Mint dead shares on first deposit to mitigate inflation attacks
        if (isFirst) {
            _mint(DEAD_ADDRESS, DEAD_SHARES);
        }

        _mint(receiver, lpAmount);

        emit Contributed(msg.sender, receiver, lpAmount, amounts);
    }

    function withdraw(
        uint256 lpAmount,
        address receiver,
        uint256[] calldata minAmounts
    ) external override nonReentrant returns (uint256[] memory amounts) {
        if (lpAmount == 0) revert ZeroAmount();
        uint256 len = _tokens.length;
        if (minAmounts.length != len) revert LengthMismatch(len, minAmounts.length);

        uint256 supply = totalSupply();
        amounts = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            amounts[i] = (_reserves[_tokens[i]] * lpAmount) / supply;
            if (amounts[i] < minAmounts[i]) {
                revert InsufficientAmount(i, minAmounts[i], amounts[i]);
            }
        }

        // Burn before transfer (checks-effects-interactions)
        _burn(msg.sender, lpAmount);

        for (uint256 i = 0; i < len; i++) {
            if (amounts[i] > 0) {
                _reserves[_tokens[i]] -= amounts[i];
                IERC20(_tokens[i]).safeTransfer(receiver, amounts[i]);
            }
        }

        emit Withdrawn(msg.sender, receiver, lpAmount, amounts);
    }

    function rebalance(
        address[] calldata newTokens,
        uint256[] calldata newWeights
    ) external override {
        if (msg.sender != _owner) revert Unauthorized();
        if (newTokens.length != newWeights.length) {
            revert LengthMismatch(newTokens.length, newWeights.length);
        }

        _validateConstituents(newTokens, newWeights);

        // Clear old constituent state
        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            delete _weights[token];
            delete _isConstituent[token];
        }
        delete _tokens;

        _setConstituents(newTokens, newWeights);

        emit Rebalanced(newTokens, newWeights);
    }

    // --- Preview Functions ---

    function previewContribute(uint256[] calldata amounts)
        external view override returns (uint256 lpAmount)
    {
        if (amounts.length != _tokens.length) {
            revert LengthMismatch(_tokens.length, amounts.length);
        }

        // Zero inputs return zero
        bool allZero = true;
        for (uint256 i = 0; i < amounts.length; i++) {
            if (amounts[i] > 0) { allZero = false; break; }
        }
        if (allZero) return 0;

        return _calculateContribution(amounts);
    }

    function previewWithdraw(uint256 lpAmount)
        external view override returns (uint256[] memory amounts)
    {
        uint256 len = _tokens.length;
        amounts = new uint256[](len);

        uint256 supply = totalSupply();
        if (supply == 0 || lpAmount == 0) return amounts;

        for (uint256 i = 0; i < len; i++) {
            amounts[i] = (_reserves[_tokens[i]] * lpAmount) / supply;
        }
    }

    // --- Internal ---

    function _calculateContribution(uint256[] calldata amounts)
        internal view returns (uint256 lpAmount)
    {
        uint256 supply = totalSupply();

        if (supply == 0) {
            // First deposit: shares = sum of amounts, minus dead shares
            uint256 total;
            for (uint256 i = 0; i < amounts.length; i++) {
                total += amounts[i];
            }
            if (total <= DEAD_SHARES) return 0;
            return total - DEAD_SHARES;
        }

        // Subsequent deposits: proportional to minimum ratio across constituents
        uint256 minRatio = type(uint256).max;
        bool hasRatio = false;

        for (uint256 i = 0; i < _tokens.length; i++) {
            uint256 reserve = _reserves[_tokens[i]];
            if (reserve > 0 && amounts[i] > 0) {
                uint256 ratio = (amounts[i] * 1e18) / reserve;
                if (ratio < minRatio) {
                    minRatio = ratio;
                }
                hasRatio = true;
            }
        }

        if (!hasRatio) return 0;

        lpAmount = (supply * minRatio) / 1e18;
    }

    function _validateConstituents(
        address[] memory tokens,
        uint256[] memory weights
    ) internal pure {
        uint256 totalWeight;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0)) revert ZeroAddress();
            for (uint256 j = 0; j < i; j++) {
                if (tokens[i] == tokens[j]) revert DuplicateConstituent(tokens[i]);
            }
            totalWeight += weights[i];
        }
        if (totalWeight != BASIS_POINTS) revert InvalidWeights(totalWeight);
    }

    function _setConstituents(
        address[] memory tokens,
        uint256[] memory weights
    ) internal {
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokens.push(tokens[i]);
            _weights[tokens[i]] = weights[i];
            _isConstituent[tokens[i]] = true;
        }
    }
}
