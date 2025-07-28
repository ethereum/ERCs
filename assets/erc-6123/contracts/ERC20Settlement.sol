// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.7.0;

import "./ISDC.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./IAsyncTransfer.sol";

/*------------------------------------------- DESCRIPTION ---------------------------------------------------------------------------------------
* @title Reference (example) Implementation for Settlement Token Interface
* @dev This token performs transfers on-chain.
* Token is tied to one SDC address and only that SDC can call transfers.
* Settlement Token calls back the referenced IAsyncTransfer contract by calling "afterTransfer" with a success flag.
*/
contract ERC20Settlement is ERC20, IAsyncTransfer{

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

    function transferAndCallback(address to, uint256 value, uint256 transactionID, IAsyncTransferCallback callbackContract) public onlySDC{
        if ( balanceOf(msg.sender) < value) {
            callbackContract.afterTransfer(false, transactionID, Strings.toString(transactionID));
        }
        else {
            _transfer(msg.sender,to,value);
            callbackContract.afterTransfer(true, transactionID, Strings.toString(transactionID));
        }
    }

    function transferFromAndCallback(address from, address to, uint256 value, uint256 transactionID, IAsyncTransferCallback callbackContract) public onlySDC {
        if ( balanceOf(from) < value) {
            callbackContract.afterTransfer(false, transactionID, Strings.toString(transactionID));
        }
        else {
            _transfer(from,to,value);
            callbackContract.afterTransfer(true, transactionID, Strings.toString(transactionID));
        }
    }

    function transferBatchAndCallback(address[] memory to, uint256[] memory values, uint256 transactionID, IAsyncTransferCallback callbackContract) public onlySDC{
        require (to.length == values.length, "Array Length mismatch");
        uint256 requiredBalance = 0;
        for(uint256 i = 0; i < values.length; i++) {
            requiredBalance += values[i];
        }
        if (balanceOf(msg.sender) < requiredBalance){
            callbackContract.afterTransfer(false, transactionID, Strings.toString(transactionID));
            return;
        }
        else{
            for(uint256 i = 0; i < to.length; i++){
                _transfer(msg.sender,to[i],values[i]);
            }
            callbackContract.afterTransfer(true, transactionID, Strings.toString(transactionID));
        }
    }

    function transferBatchFromAndCallback(address[] memory from, address[] memory to, uint256[] memory values, uint256 transactionID, IAsyncTransferCallback callbackContract) public onlySDC{
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
                callbackContract.afterTransfer(false, transactionID, Strings.toString(transactionID));
                return;
            }

        }
        for(uint256 i = 0; i < to.length; i++){
            _transfer(from[i],to[i],values[i]);
        }
        callbackContract.afterTransfer(true, transactionID, Strings.toString(transactionID));
    }
}
