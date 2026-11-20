// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.27;

import {IBalanceProxy} from "./interfaces/IBalanceProxy.sol";
import {BalanceMetadata} from "./interfaces/IMetadata.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ISafe} from "@safe-global/safe-smart-account/contracts/interfaces/ISafe.sol";
import {Enum} from "@safe-global/safe-smart-account/contracts/libraries/Enum.sol";

contract SafeRouter {
    bytes32 private _activeSafeExecution;

    struct SafeTx {
        address to;
        uint256 value;
        bytes data;
        Enum.Operation operation;
        uint256 safeTxGas;
        uint256 baseGas;
        uint256 gasPrice;
        address gasToken;
        address payable refundReceiver;
        bytes signatures;
        uint256 routerSigPosition;
    }

    error NotSafeOwner(address caller, address safe);
    error RouterNotSafeOwner(address router, address safe);
    error SafeExecutionFailed(address safe, address target);
    error UnsupportedSafeOperation(Enum.Operation operation);
    error UnauthorizedSafeExecution();
    error InvalidSignaturesLength(uint256 length);
    error InvalidRouterSignaturePosition(
        uint256 position,
        uint256 signatureCount
    );
    error InsufficientSafeSignatures(uint256 provided, uint256 threshold);
    error InvalidSafeThreshold(uint256 threshold);
    error MetadataBalancesLengthMismatch(
        uint256 metaLength,
        uint256 balancesLength
    );
    error InvalidMetadata(
        address token,
        string expectedSymbol,
        uint8 expectedDecimals,
        string actualSymbol,
        uint8 actualDecimals
    );

    function safeExecuteWithPostBalances(
        IBalanceProxy balanceProxy,
        IBalanceProxy.Balance[] calldata postBalances,
        ISafe safe,
        SafeTx calldata safeTx
    ) external {
        _verifySafeContext(safe);
        _validateSafeTx(safe, safeTx);
        _executeWithBalanceProxy(
            balanceProxy,
            safe,
            postBalances,
            safeTx,
            false
        );
    }

    function safeExecuteWithDiffs(
        IBalanceProxy balanceProxy,
        IBalanceProxy.Balance[] calldata diffs,
        ISafe safe,
        SafeTx calldata safeTx
    ) external {
        _verifySafeContext(safe);
        _validateSafeTx(safe, safeTx);
        _executeWithBalanceProxy(balanceProxy, safe, diffs, safeTx, true);
    }

    function safeExecuteWithPostBalancesMeta(
        IBalanceProxy balanceProxy,
        BalanceMetadata[] calldata meta,
        IBalanceProxy.Balance[] calldata postBalances,
        ISafe safe,
        SafeTx calldata safeTx
    ) external {
        _verifySafeContext(safe);
        _validateSafeTx(safe, safeTx);
        _checkMetadata(meta, postBalances);
        _executeWithBalanceProxy(
            balanceProxy,
            safe,
            postBalances,
            safeTx,
            false
        );
    }

    function safeExecuteWithDiffsMeta(
        IBalanceProxy balanceProxy,
        BalanceMetadata[] calldata meta,
        IBalanceProxy.Balance[] calldata diffs,
        ISafe safe,
        SafeTx calldata safeTx
    ) external {
        _verifySafeContext(safe);
        _validateSafeTx(safe, safeTx);
        _checkMetadata(meta, diffs);
        _executeWithBalanceProxy(balanceProxy, safe, diffs, safeTx, true);
    }

    function executeSafeTransaction(
        ISafe safe,
        SafeTx calldata safeTx
    ) external {
        bytes memory data = abi.encodeCall(
            this.executeSafeTransaction,
            (safe, safeTx)
        );
        if (_activeSafeExecution != _safeExecutionHash(msg.sender, data)) {
            revert UnauthorizedSafeExecution();
        }
        _execOriginalTx(safe, safeTx);
    }

    function _verifySafeContext(ISafe safe) internal view {
        if (!safe.isOwner(msg.sender))
            revert NotSafeOwner(msg.sender, address(safe));
        if (!safe.isOwner(address(this))) {
            revert RouterNotSafeOwner(address(this), address(safe));
        }
    }

    function _execOriginalTx(ISafe safe, SafeTx calldata safeTx) internal {
        bytes memory signatures = _buildSignatures(
            safeTx.signatures,
            safeTx.routerSigPosition,
            safe.getThreshold() - 1
        );

        bool success = safe.execTransaction(
            safeTx.to,
            safeTx.value,
            safeTx.data,
            safeTx.operation,
            safeTx.safeTxGas,
            safeTx.baseGas,
            safeTx.gasPrice,
            safeTx.gasToken,
            safeTx.refundReceiver,
            signatures
        );
        if (!success) revert SafeExecutionFailed(address(safe), safeTx.to);
    }

    function _validateSafeTx(ISafe safe, SafeTx calldata safeTx) internal view {
        if (safeTx.operation != Enum.Operation.Call) {
            revert UnsupportedSafeOperation(safeTx.operation);
        }

        uint256 threshold = safe.getThreshold();
        if (threshold < 2) {
            revert InvalidSafeThreshold(threshold);
        }

        if (safeTx.signatures.length % 65 != 0) {
            revert InvalidSignaturesLength(safeTx.signatures.length);
        }

        uint256 requiredHumanSignatures = threshold - 1;
        uint256 provided = safeTx.signatures.length / 65;
        if (safeTx.routerSigPosition > requiredHumanSignatures) {
            revert InvalidRouterSignaturePosition(
                safeTx.routerSigPosition,
                provided
            );
        }
        if (provided < requiredHumanSignatures) {
            revert InsufficientSafeSignatures(
                provided,
                requiredHumanSignatures
            );
        }
    }

    function _executeWithBalanceProxy(
        IBalanceProxy balanceProxy,
        ISafe safe,
        IBalanceProxy.Balance[] calldata balances,
        SafeTx calldata safeTx,
        bool useDiffs
    ) internal {
        bytes memory data = abi.encodeCall(
            this.executeSafeTransaction,
            (safe, safeTx)
        );
        _activeSafeExecution = _safeExecutionHash(address(balanceProxy), data);
        if (useDiffs) {
            balanceProxy.proxyCallDiffs(
                balances,
                new IBalanceProxy.Approval[](0),
                address(this),
                data,
                new IBalanceProxy.Balance[](0)
            );
        } else {
            balanceProxy.proxyCall(
                balances,
                new IBalanceProxy.Approval[](0),
                address(this),
                data,
                new IBalanceProxy.Balance[](0)
            );
        }
        _activeSafeExecution = bytes32(0);
    }

    function _safeExecutionHash(
        address caller,
        bytes memory data
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(caller, data));
    }

    function _checkMetadata(
        BalanceMetadata[] calldata meta,
        IBalanceProxy.Balance[] calldata balances
    ) internal view {
        if (meta.length != balances.length) {
            revert MetadataBalancesLengthMismatch(meta.length, balances.length);
        }
        for (uint256 i = 0; i < meta.length; i++) {
            string memory actualSymbol;
            uint8 actualDecimals;
            if (balances[i].token == address(0)) {
                actualSymbol = "ETH";
                actualDecimals = 18;
            } else {
                actualSymbol = IERC20Metadata(balances[i].token).symbol();
                actualDecimals = IERC20Metadata(balances[i].token).decimals();
            }
            if (
                keccak256(abi.encodePacked(actualSymbol)) !=
                keccak256(abi.encodePacked(meta[i].symbol)) ||
                actualDecimals != meta[i].decimals
            ) {
                revert InvalidMetadata(
                    balances[i].token,
                    meta[i].symbol,
                    meta[i].decimals,
                    actualSymbol,
                    actualDecimals
                );
            }
        }
    }

    function _buildSignatures(
        bytes calldata existingSigs,
        uint256 routerSigPosition,
        uint256 requiredHumanSignatures
    ) internal view returns (bytes memory) {
        bytes memory routerSig = abi.encodePacked(
            bytes32(uint256(uint160(address(this)))),
            bytes32(0),
            uint8(1)
        );

        uint256 humanSignaturesLength = requiredHumanSignatures * 65;
        return
            abi.encodePacked(
                existingSigs[:routerSigPosition * 65],
                routerSig,
                existingSigs[routerSigPosition * 65:humanSignaturesLength]
            );
    }
}
