
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import "./IERC7586.sol";
import "./Tokens/ERC20.sol";

contract ERC7586 is IERC7586, ERC20 {
    constructor(string memory _name, string memory _symbol, IRS memory _irs) ERC20(_name, _symbol) {
        irsSymbol = _symbol;
        irs[irsSymbol] = _irs;

        _isActive = true;

        _balanceOf[_irs.payer] = _irs.paymentDates.length * 1 ether;
        _balanceOf[_irs.receiver] = _irs.paymentDates.length * 1 ether;
        _totalSupply = _irs.paymentDates.length * 2 * 1 ether;
    }

    function payer() external view returns(address) {
        return irs[irsSymbol].payer;
    }

    function receiver() external view returns(address) {
        return irs[irsSymbol].receiver;
    }

    function swapRate() external view returns(uint256) {
        return irs[irsSymbol].swapRate;
    }

    function spread() external view returns(uint256) {
        return irs[irsSymbol].spread;
    }

    function assetContract() external view returns(address) {
        return irs[irsSymbol].assetContract;
    }

    function notionalAmount() external view returns(uint256) {
        return irs[irsSymbol].notionalAmount;
    }

    function paymentFrequency() external view returns(uint256) {
        return irs[irsSymbol].paymentFrequency;
    }

    function paymentDates() external view returns(uint256[] memory) {
        return irs[irsSymbol].paymentDates;
    }

    function startingDate() external view returns(uint256) {
        return irs[irsSymbol].startingDate;
    }

    function maturityDate() external view returns(uint256) {
        return irs[irsSymbol].maturityDate;
    }

    function benchmark() external view returns(uint256) {
        // This should be fetched from an oracle contract
        return irs[irsSymbol].benchmark;
    }

    function oracleContractForBenchmark() external view returns(address) {
        return irs[irsSymbol].oracleContractForBenchmark;
    }

    function isActive() public view returns(bool) {
        return _isActive;
    }

    function agree() external {
        require(_hasAgreed[msg.sender] == false, "Already agreed");
        require(msg.sender == irs[irsSymbol].payer || msg.sender == irs[irsSymbol].receiver);
        require(block.timestamp < irs[irsSymbol].paymentDates[0], "delay expired");

        _hasAgreed[msg.sender] = true;
    }

    function swap() external returns(bool) {
        require(_isActive, "Contract not Active");
        require(_hasAgreed[irs[irsSymbol].payer], "Missing Agreement");
        require(_hasAgreed[irs[irsSymbol].receiver], "Missing Agreement");

        uint256 fixedRate = irs[irsSymbol].swapRate;
        uint256 floatingRate = irs[irsSymbol].benchmark + irs[irsSymbol].spread;
        uint256 notional = irs[irsSymbol].notionalAmount;

        uint256 fixedInterest = notional * fixedRate;
        uint256 floatingInterest = notional * floatingRate;

        uint256 interestToTransfer;
        address _recipient;
        address _payer;

        if(fixedInterest == floatingInterest) {
            revert("Nothing to swap");
        } else if(fixedInterest > floatingInterest) {
            interestToTransfer = fixedInterest - floatingInterest;
            _recipient = irs[irsSymbol].receiver;
            _payer = irs[irsSymbol].payer;
        } else {
            interestToTransfer = floatingInterest - fixedInterest;
            _recipient = irs[irsSymbol].payer;
            _payer = irs[irsSymbol].receiver;
        }

        burn(irs[irsSymbol].payer, 1 ether);
        burn(irs[irsSymbol].receiver, 1 ether);

        uint256 _paymentCount = paymentCount;
        paymentCount = _paymentCount + 1;

        IERC20(irs[irsSymbol].assetContract).transferFrom(_payer, _recipient, interestToTransfer * 1 ether / 10_000);

        if(paymentCount == irs[irsSymbol].paymentDates.length) {
            _isActive = false;
        }

        return true;
    }

    function terminateSwap() external {
        require(_isActive, "Contract not Active");

        _isActive = false;
    }
}
