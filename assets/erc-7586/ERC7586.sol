// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import "./IERC7586.sol";
import "./Tokens/ERC20.sol";

contract ERC7586 is IERC7586, ERC20 {
    constructor(string memory _name, string memory _symbol, IRS memory _irs) ERC20(_name, _symbol) {
        irsSymbol = _symbol;
        irs = _irs;

        _isActive = true;

        _balanceOf[_irs.payer] = _irs.paymentDates.length * 1 ether;
        _balanceOf[_irs.receiver] = _irs.paymentDates.length * 1 ether;
        _totalSupply = _irs.paymentDates.length * 2 * 1 ether;
    }

    function fixedInterestPayer() external view returns(address) {
        return irs.payer;
    }

    function floatingInterestPayer() external view returns(address) {
        return irs.receiver;
    }

    function ratesDecimals() external view returns(uint8) {
        return irs.ratesDecimals;
    }

    function swapRate() external view returns(uint256) {
        return irs.swapRate;
    }

    function spread() external view returns(uint256) {
        return irs.spread;
    }

    function assetContract() external view returns(address) {
        return irs.assetContract;
    }

    function notionalAmount() external view returns(uint256) {
        return irs.notionalAmount;
    }

    function paymentFrequency() external view returns(uint256) {
        return irs.paymentFrequency;
    }

    function paymentDates() external view returns(uint256[] memory) {
        return irs.paymentDates;
    }

    function startingDate() external view returns(uint256) {
        return irs.startingDate;
    }

    function maturityDate() external view returns(uint256) {
        return irs.maturityDate;
    }

    function benchmark() external view returns(uint256) {
        // This should be fetched from an oracle contract
        return irs.benchmark;
    }

    function oracleContractForBenchmark() external view returns(address) {
        return irs.oracleContractForBenchmark;
    }

    function isActive() public view returns(bool) {
        return _isActive;
    }

    function swap() external returns(bool) {
        require(_isActive, "Contract not Active");
        require(_hasAgreed[irs.payer], "Missing Agreement");
        require(_hasAgreed[irs.receiver], "Missing Agreement");

        uint256 fixedRate = irs.swapRate;
        uint256 floatingRate = irs.benchmark + irs.spread;
        uint256 notional = irs.notionalAmount;

        uint256 fixedInterest = notional * fixedRate;
        uint256 floatingInterest = notional * floatingRate;

        uint256 interestToTransfer;
        address _recipient;
        address _payer;

        if(fixedInterest == floatingInterest) {
            revert("Nothing to swap");
        } else if(fixedInterest > floatingInterest) {
            interestToTransfer = fixedInterest - floatingInterest;
            _recipient = irs.receiver;
            _payer = irs.payer;
        } else {
            interestToTransfer = floatingInterest - fixedInterest;
            _recipient = irs.payer;
            _payer = irs.receiver;
        }

        burn(irs.payer, 1 ether);
        burn(irs.receiver, 1 ether);

        uint256 _paymentCount = paymentCount;
        paymentCount = _paymentCount + 1;

        IERC20(irs.assetContract).transferFrom(_payer, _recipient, interestToTransfer * 1 ether / 10_000);

        if(paymentCount == irs.paymentDates.length) {
            _isActive = false;
        }

        return true;
    }

    function terminateSwap() external {
        require(_isActive, "Contract not Active");

        _isActive = false;
    }
}
