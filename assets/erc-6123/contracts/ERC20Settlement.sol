// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.7.0 <0.9.0;

import "./ISDC.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./IERC20Settlement.sol";

contract ERC20Settlement is ERC20, IERC20Settlement{

/*------------------------------------------- DESCRIPTION ---------------------------------------------------------------------------------------
* @title Reference (example) Implementation for Settlement Token Interface
* @dev This token performs transfers on-chain.
* Token is tied to one SDC address
* Only SDC can call checkedTransfers
* Settlement Token calls back the referenced SDC by calling "afterTransfer" with a success flag. Depending on this SDC perfoms next state change
*/


    modifier onlySDC() {
        require(msg.sender == sdcAddress, "Only allowed to be called from SDC Address"); _;
    }

    using ERC165Checker for address;

    address sdcAddress;

    constructor() ERC20("SDCToken", "SDCT") {

    }

    function setSDCAddress(address _sdcAddress) public{
        sdcAddress = _sdcAddress;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function checkedTransfer(address to, uint256 value, uint256 transactionID) public onlySDC{
        if ( balanceOf(sdcAddress) < value)
            ISDC(sdcAddress).afterTransfer(false, Strings.toString(transactionID));
        else
            ISDC(sdcAddress).afterTransfer(true, Strings.toString(transactionID));
    }

    function checkedTransferFrom(address from, address to, uint256 value, uint256 transactionID) external view onlySDC {
        revert("not implemented");
    }

    function checkedBatchTransfer(address[] memory to, uint256[] memory values, uint256 transactionID ) public onlySDC{
        require (to.length == values.length, "Array Length mismatch");
        uint256 requiredBalance = 0;
        for(uint256 i = 0; i < values.length; i++)
            requiredBalance += values[i];
        if (balanceOf(msg.sender) < requiredBalance){
            ISDC(sdcAddress).afterTransfer(false, Strings.toString(transactionID));
            return;
        }
        else{
            for(uint256 i = 0; i < to.length; i++){
                _transfer(sdcAddress,to[i],values[i]);
            }
            ISDC(sdcAddress).afterTransfer(true, Strings.toString(transactionID));
        }
    }


    function checkedBatchTransferFrom(address[] memory from, address[] memory to, uint256[] memory values, uint256 transactionID ) public onlySDC{
        require (from.length == to.length, "Array Length mismatch");
        require (to.length == values.length, "Array Length mismatch");
        for(uint256 i = 0; i < from.length; i++){
            address fromAddress = from[i];
            uint256 totalRequiredBalance = 0;
            for(uint256 j = 0; j < from.length; j++){
                if (from[j] == fromAddress)
                    totalRequiredBalance += values[j];
            }
            if (balanceOf(fromAddress) <  totalRequiredBalance){
                ISDC(sdcAddress).afterTransfer(false, Strings.toString(transactionID));
                return;
            }

        }
        for(uint256 i = 0; i < to.length; i++){
            _transfer(from[i],to[i],values[i]);
        }
        ISDC(sdcAddress).afterTransfer(true, Strings.toString(transactionID));
    }

}