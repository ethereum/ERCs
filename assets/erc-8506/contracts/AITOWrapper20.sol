// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IAITOInstrument} from "./interfaces/IAITOInstrument.sol";
import {IAITOBinding} from "./interfaces/IAITOBinding.sol";
import {IAITOWrapper20} from "./interfaces/IAITOWrapper20.sol";
import {SeriesTerms, BindingType, ConsumptionPath} from "./interfaces/AITOTypes.sol";

/// @title Reference ERC-20 wrapper for one series of AI inference entitlements
/// @notice Wrapped tokens are minted only against native units locked here and burned when
/// those units leave. The wrapper holds no consumption authority: it never signs or registers
/// an authorization, so locked units cannot be consumed through any path while wrapped.
contract AITOWrapper20 is ERC20, IERC1155Receiver, IAITOBinding, IAITOWrapper20 {
    address public immutable ledger;
    uint256 public immutable seriesId;
    uint256 public immutable unitScale;
    uint8 private immutable _decimals;

    error NotAnAITOLedger();
    error NotTransferable();
    error UnknownCriticalExtension(bytes32 extension);
    error UnexpectedToken();
    error MissingRecipient();
    error BatchNotSupported();
    error DecimalsTooLarge();

    constructor(address ledger_, uint256 seriesId_, string memory name_, string memory symbol_, uint8 decimals_)
        ERC20(name_, symbol_)
    {
        if (decimals_ > 36) revert DecimalsTooLarge();
        if (
            !IERC165(ledger_).supportsInterface(type(IAITOInstrument).interfaceId)
                || !IERC165(ledger_).supportsInterface(type(IERC1155).interfaceId)
        ) revert NotAnAITOLedger();

        // Reverts for an unknown series.
        SeriesTerms memory t = IAITOInstrument(ledger_).seriesOf(seriesId_);
        if (!t.transferable) revert NotTransferable();
        // This wrapper understands no extension. A series with a critical one cannot be wrapped here.
        for (uint256 i; i < t.extensions.length; ++i) {
            if (t.extensions[i].critical) revert UnknownCriticalExtension(t.extensions[i].id);
        }

        ledger = ledger_;
        seriesId = seriesId_;
        _decimals = decimals_;
        unitScale = 10 ** uint256(decimals_);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @inheritdoc IAITOWrapper20
    function lockedUnits() public view returns (uint256) {
        return IERC1155(ledger).balanceOf(address(this), seriesId);
    }

    /// @inheritdoc IAITOWrapper20
    function expired() external view returns (bool) {
        return block.timestamp > IAITOInstrument(ledger).seriesOf(seriesId).validUntil;
    }

    /// @inheritdoc IAITOWrapper20
    function wrap(uint256 units, address to) external {
        // Minting happens in onERC1155Received, so a direct safeTransferFrom to the wrapper
        // and this function behave the same.
        IERC1155(ledger).safeTransferFrom(msg.sender, address(this), seriesId, units, abi.encode(to));
    }

    /// @inheritdoc IAITOWrapper20
    function unwrap(uint256 units, address to) external {
        _burn(msg.sender, units * unitScale);
        emit Unwrapped(msg.sender, to, units);
        IERC1155(ledger).safeTransferFrom(address(this), to, seriesId, units, "");
    }

    /// @notice Mints wrapped tokens for native units received from the ledger.
    /// @param data Empty to mint to `from`, or `abi.encode(address recipient)`.
    function onERC1155Received(address, address from, uint256 id, uint256 value, bytes calldata data)
        external
        returns (bytes4)
    {
        if (msg.sender != ledger || id != seriesId) revert UnexpectedToken();
        address to = data.length == 32 ? abi.decode(data, (address)) : from;
        if (to == address(0)) revert MissingRecipient();
        _mint(to, value * unitScale);
        emit Wrapped(from, to, value);
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        revert BatchNotSupported();
    }

    /// @inheritdoc IAITOBinding
    function aitoBinding(uint256)
        external
        view
        returns (address, uint256, BindingType, uint256, ConsumptionPath)
    {
        return (ledger, seriesId, BindingType.Wrap, unitScale, ConsumptionPath.UnwrapFirst);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IAITOBinding).interfaceId || interfaceId == type(IAITOWrapper20).interfaceId
            || interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
