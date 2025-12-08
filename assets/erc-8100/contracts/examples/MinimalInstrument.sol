// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.23;

import {
    IXMLRepresentableStateVersionedHashed,
    IXMLRepresentableState, IRepresentableStateVersioned, IRepresentableStateHashed     // needed for @inheritdoc
} from "../IRepresentableState.sol";

/**
 * @title Example XML-representable contract
 * @notice Simple "instrument" with state fields owner, notional, maturity, and active flag and
 *         and XML representation of its internal state using the generic IRepresentableState.sol
 *         schema.
 * @author Christian Fries
 */
contract MinimalInstrument is IXMLRepresentableStateVersionedHashed {
    address public owner;

    uint256 public notional;
    string  public currency;
    uint256 public maturityDate;
    bool    public active;

    uint256 private _stateVersion;

    event Updated(address indexed updater, uint256 newNotional, uint256 newMaturity, bool newActive);

    constructor(address _owner, uint256 _notional, uint256 _maturityDate) {
        owner = _owner;
        notional = _notional;
        currency = "EUR";
        maturityDate = _maturityDate;
        active = true;
        _stateVersion = 1;
    }

    function update(uint256 _notional, uint256 _maturityDate, bool _active) external {
        require(msg.sender == owner, "not owner");
        notional = _notional;
        maturityDate = _maturityDate;
        active = _active;
        _stateVersion += 1;
        emit Updated(msg.sender, _notional, _maturityDate, _active);
    }

    // --- IRepresentableState.sol ---

    /// @inheritdoc IXMLRepresentableState
    function xmlTemplate() external pure override returns (string memory) {
        // Note: formatted as a single string for simplicity; newlines are optional.
        return
            "<Contract xmlns='urn:example:contract'"
                " xmlns:evmstate='urn:evm:state:1.0'"
                " evmstate:chain-id=''"
                " evmstate:contract-address=''"
                " evmstate:block-number=''>"

                "<Instrument xmlns='urn:example:format-showcase'>"
                    " xmlns:evmstate='urn:evm:state:1.0'>"
                    "<Owner evmstate:call='owner()(address)' evmstate:format='address'/>"
                    "<Notional"
                    " evmstate:calls='notional()(uint256);currency()(string)'"
                    " evmstate:formats='decimal;string'"
                    " evmstate:targets=';currency'/>"
                    "<MaturityDate evmstate:call='maturityDate()(uint256)' evmstate:format='iso8601-date'/>"
                    "<Active evmstate:call='active()(bool)' evmstate:format='boolean'/>"
                "</Instrument>"
            "</Contract>";
    }

    /// @inheritdoc IRepresentableStateVersioned
    function stateVersion() external view override returns (uint256) {
        return _stateVersion;
    }

    /// @inheritdoc IRepresentableStateHashed
    function stateHash() external view override returns (bytes32) {
        // Canonical encoding of the state relevant to the XML representation.
        return keccak256(abi.encode(owner, notional, maturityDate, active));
    }
}

