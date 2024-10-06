// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import "./IERC7092.sol";
import "./BondStorage.sol";

contract ERC7092 is IERC7092, BondStorage {
    constructor(
        string memory _bondISIN,
        Issuer memory _issuerInfo
    )  {
        bondISIN = _bondISIN;
        _bondManager = msg.sender;
        _issuer[_bondISIN] = _issuerInfo;
    }

    function issue(
        IssueData[] memory _issueData,
        Bond memory _bond
    ) external onlyBondManager {
        _issue(_issueData, _bond);
    }

    function redeem() external onlyBondManager {
        _redeem(_listOfInvestors);
    }

    function isin() external view returns(string memory) {
        return _bonds[bondISIN].isin;
    }

    function name() external view returns(string memory) {
        return _bonds[bondISIN].name;
    }

    function symbol() external view returns(string memory) {
        return _bonds[bondISIN].symbol;
    }

    function currency() external view returns(address) {
        return _bonds[bondISIN].currency;
    }

    function denomination() external view returns(uint256) {
        return _bonds[bondISIN].denomination;
    }

    function issueVolume() external view returns(uint256) {
        return _bonds[bondISIN].issueVolume;
    }

    function totalSupply() external view returns(uint256) {
        return _bonds[bondISIN].issueVolume / _bonds[bondISIN].denomination;
    }

    function couponRate() external view returns(uint256) {
        return _bonds[bondISIN].couponRate;
    }

    function issueDate() external view returns(uint256) {
        return _bonds[bondISIN].issueDate;
    }

    function maturityDate() external view returns(uint256) {
        return _bonds[bondISIN].maturityDate;
    }

    function principalOf(address _account) external view returns(uint256) {
        return _principals[_account];
    }

    function balanceOf(address _account) external view returns(uint256) {
        return _principals[_account] / _bonds[bondISIN].denomination;
    }

    function allowance(address _owner, address _spender) external view returns(uint256) {
        return _allowed[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount) external returns(bool) {
        address _owner = msg.sender;

        _approve(_owner, _spender, _amount);

        return true;
    }

    function decreaseAllowance(address _spender, uint256 _amount) external returns(bool) {
        address _owner = msg.sender;

        _decreaseAllowance(_owner, _spender, _amount);

        return true;
    }

    function transfer(address _to, uint256 _amount, bytes calldata _data) external returns(bool) {
        address _from = msg.sender;

        _transfer(_from, _to, _amount, _data);

        return true;
    }

    function transferFrom(address _from, address _to, uint256 _amount, bytes calldata _data) external returns(bool) {
        address _spender = msg.sender;

        _spendAllowance(_from, _spender, _amount);

        _transfer(_from, _to, _amount, _data);

        return true;
    }

    function batchApprove(address[] calldata _spender, uint256[] calldata _amount) external returns(bool) {
        address _owner = msg.sender;

        _batchApprove(_owner, _spender, _amount);

        return true;
    }

    function batchDecreaseAllowance(address[] calldata _spender, uint256[] calldata _amount) external returns(bool) {
        address _owner = msg.sender;

        _decreaseAllowance(_owner, _spender, _amount);

        return true;
    }

    function batchTransfer(address[] calldata _to, uint256[] calldata _amount, bytes[] calldata _data) external returns(bool) {
        address[] memory _from;

        for(uint256 i = 0; i < _from.length; i++) {
            _from[i] = msg.sender;
        }

        _batchTransfer(_from, _to, _amount, _data);

        return true;
    }

    function batchTransferFrom(address[] calldata _from, address[] calldata _to, uint256[] calldata _amount, bytes[] calldata _data) external returns(bool) {
        address _spender;

        _batchSpendAllowance(_from, _spender, _amount);

        _batchTransfer(_from, _to, _amount, _data);

        return true;
    }

    function bondStatus() external view returns(BondStatus) {
        return _bondStatus;
    }

    function listOfInvestors() external view returns(IssueData[] memory) {
        return _listOfInvestors;
    }

    function bondInfo() public view returns(Bond memory) {
        return _bonds[bondISIN];
    }
    
    function issuerInfo() public view returns(Issuer memory) {
        return _issuer[bondISIN];
    }

    function _issue(IssueData[] memory _issueData, Bond memory _bondInfo) internal virtual {
        uint256 volume;
        uint256 _issueVolume = _bondInfo.issueVolume;
      
        for(uint256 i; i < _issueData.length; i++) {
            address investor = _issueData[i].investor;
            uint256 principal = _issueData[i].principal;
            uint256 _denomination = _bondInfo.denomination;
            
            require(investor != address(0), "ERC7092: ZERO_ADDRESS_INVESTOR");
            require(principal != 0 && (principal * _denomination) % _denomination == 0, "ERC: INVALID_PRINCIPAL_AMOUNT");

            volume += principal;
            _principals[investor] = principal;
            _listOfInvestors.push(IssueData({investor:investor, principal:principal}));
        }
        
        _bonds[bondISIN] = _bondInfo;
        _bonds[bondISIN].issueDate = block.timestamp;
        _bondStatus = BondStatus.ISSUED;

        uint256 _maturityDate = _bonds[bondISIN].maturityDate;

        require(_maturityDate > block.timestamp, "ERC7092: INVALID_MATURITY_DATE");
        require(volume == _issueVolume, "ERC7092: INVALID_ISSUE_VOLUME");

        emit BondIssued(_issueData, _bondInfo);
    }

    function _redeem(IssueData[] memory _bondsData) internal virtual {
        uint256 _maturityDate = _bonds[bondISIN].maturityDate;
        require(block.timestamp > _maturityDate, "ERC2721: WAIT_MATURITY");

        for(uint256 i; i < _bondsData.length; i++) {
            if(_principals[_bondsData[i].investor] != 0) {
                _principals[_bondsData[i].investor] = 0;
            }
        }

        _bondStatus = BondStatus.REDEEMED;
        emit BondRedeemed();
    }

    function _approve(address _owner, address _spender, uint256 _amount) internal virtual {
        require(_owner != address(0), "ERC7092: OWNER_ZERO_ADDRESS");
        require(_spender != address(0), "ERC7092: SPENDER_ZERO_ADDRESS");
        require(_amount > 0, "ERC7092: INVALID_AMOUNT");
        require(block.timestamp < _bonds[bondISIN].maturityDate, "ERC7092: BONDS_MATURED");

        uint256 _balance = _principals[_owner] / _bonds[bondISIN].denomination;
        uint256 _denomination = _bonds[bondISIN].denomination;

        require(_amount <= _balance, "ERC7092: INSUFFICIENT_BALANCE");
        require((_amount * _denomination) % _denomination == 0, "ERC7092: INVALID_AMOUNT");

        uint256 _approval = _allowed[_owner][_spender];

        _allowed[_owner][_spender]  = _approval + _amount;

        emit Approval(_owner, _spender, _amount);
    }

    function _decreaseAllowance(address _owner, address _spender, uint256 _amount) internal virtual {
        require(_owner != address(0), "ERC7092: OWNER_ZERO_ADDRESS");
        require(_spender != address(0), "ERC7092: SPENDER_ZERO_ADDRESS");
        require(_amount > 0, "ERC7092: INVALID_AMOUNT");

        uint256 _allowance = _allowed[_owner][_spender];
        uint256 _denomination = _bonds[bondISIN].denomination;

        require(block.timestamp < _bonds[bondISIN].maturityDate, "ERC7092: BONDS_MATURED");
        require(_amount <= _allowance, "ERC7092: NOT_ENOUGH_APPROVAL");
        require((_amount * _denomination) % _denomination == 0, "ERC7092: INVALID_AMOUNT");

        _allowed[_owner][_spender]  = _allowance - _amount;

        emit Approval(_owner, _spender, _amount);
    }

    function _transfer(
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _data
    ) internal virtual {
        require(_from != address(0), "ERC7092: OWNER_ZERO_ADDRESS");
        require(_to != address(0), "ERC7092: SPENDER_ZERO_ADDRESS");
        require(_amount > 0, "ERC7092: INVALID_AMOUNT");

        uint256 principal = _principals[_from];
        uint256 _denomination = _bonds[bondISIN].denomination;
        uint256 _balance = principal / _denomination;

        require(block.timestamp < _bonds[bondISIN].maturityDate, "ERC7092: BONDS_MATURED");
        require(_amount <= _balance, "ERC7092: INSUFFICIENT_BALANCE");
        require((_amount * _denomination) % _denomination == 0, "ERC7092: INVALID_AMOUNT");

        _beforeBondTransfer(_from, _to, _amount, _data);

        uint256 principalTo = _principals[_to];

        unchecked {
            uint256 _principalToTransfer = _amount * _denomination;

            _principals[_from] = principal - _principalToTransfer;
            _principals[_to] = principalTo + _principalToTransfer;
        }

        emit Transfer(_from, _to, _amount);

        _afterBondTransfer(_from, _to, _amount, _data);
    }

    function _spendAllowance(address _from, address _spender, uint256 _amount) internal virtual {
        uint256 currentAllowance = _allowed[_from][_spender];
        require(_amount <= currentAllowance, "ERC7092: INSUFFICIENT_ALLOWANCE");

        unchecked {
            _allowed[_from][_spender] = currentAllowance - _amount;
        }
    }

    function _batchApprove(address _owner, address[] calldata _spender, uint256[] calldata _amount) internal virtual  {
        require(_owner != address(0), "ERC7092: OWNER_ZERO_ADDRESS");
        require(block.timestamp < _bonds[bondISIN].maturityDate, "ERC7092: BONDS_MATURED");
        require(_spender.length == _amount.length, "ARRAY_LENGTHS_MISMATCH");

        uint256 _balance = _principals[_owner] / _bonds[bondISIN].denomination;
        uint256 _denomination = _bonds[bondISIN].denomination;

        for(uint256 i = 0; i < _spender.length; i++) {
            require(_spender[i] != address(0), "ERC7092: SPENDER_ZERO_ADDRESS");
            require(_amount[i] > 0, "ERC7092: INVALID_AMOUNT");
            require(_balance >= _amount[i], "ERC7092: INSUFFICIENT_BALANCE");
            require((_amount[i] * _denomination) % _denomination == 0, "ERC7092: INVALID_AMOUNT");

            uint256 _approval = _allowed[_owner][_spender[i]];

            _allowed[_owner][_spender[i]]  = _approval + _amount[i];
        }

        emit ApprovalBatch(_owner, _spender, _amount);
    }

    function _decreaseAllowance(address _owner, address[] calldata _spender, uint256[] calldata _amount) internal virtual {
        require(_owner != address(0), "ERC7092: OWNER_ZERO_ADDRESS");
        require(block.timestamp < _bonds[bondISIN].maturityDate, "ERC7092: BONDS_MATURED");
        require(_spender.length == _amount.length, "ARRAY_LENGTHS_MISMATCH");

        uint256 _denomination = _bonds[bondISIN].denomination;

        for(uint256 i = 0; i < _spender.length; i++) {
            require(_spender[i] != address(0), "ERC7092: SPENDER_ZERO_ADDRESS");
            require(_amount[i] > 0, "ERC7092: INVALID_AMOUNT");
            require((_amount[i] * _denomination) % _denomination == 0, "ERC7092: INVALID_AMOUNT");

            uint256 _approval = _allowed[_owner][_spender[i]];
            require(_amount[i] <= _approval, "ERC7092: NOT_ENOUGH_APPROVAL");

            _allowed[_owner][_spender[i]]  = _approval - _amount[i];
        }

        emit ApprovalBatch(_owner, _spender, _amount);
    }

    function _batchTransfer(address[] memory _from, address[] calldata _to, uint256[] calldata _amount, bytes[] calldata _data) internal virtual {
        require(block.timestamp < _bonds[bondISIN].maturityDate, "ERC7092: BONDS_MATURED");
        require(_from.length == _to.length, "ARRAY_LENGTHS_MISMATCH");

        uint256 _denomination = _bonds[bondISIN].denomination;

        for(uint256 i = 0; i < _from.length; i++) {
            require(_from[i] != address(0), "ERC7092: OWNER_ZERO_ADDRESS");
            require(_to[i] != address(0), "ERC7092: SPENDER_ZERO_ADDRESS");
            require(_amount[i] > 0, "ERC7092: INVALID_AMOUNT");
    
            uint256 principal = _principals[_from[i]];
            uint256 _balance = principal / _denomination;

            require(_amount[i] <= _balance, "ERC7092: INSUFFICIENT_BALANCE");
            require((_amount[i] * _denomination) % _denomination == 0, "ERC7092: INVALID_AMOUNT");
    
            _beforeBondTransfer(_from[i], _to[i], _amount[i], _data[i]);
    
            uint256 principalTo = _principals[_to[i]];
    
            unchecked {
                uint256 _principalToTransfer = _amount[i] * _denomination;
    
                _principals[_from[i]] = principal - _principalToTransfer;
                _principals[_to[i]] = principalTo + _principalToTransfer;
            }

            _afterBondTransfer(_from[i], _to[i], _amount[i], _data[i]);
        }

        emit TransferBatch(_from, _to, _amount);
    }

    function _batchSpendAllowance(address[] calldata _from, address _spender, uint256[] calldata _amount) internal virtual {
        for(uint256 i = 0; i < _from.length; i++) {
            uint256 currentAllowance = _allowed[_from[i]][_spender];
            require(_amount[i] <= currentAllowance, "ERC7092: INSUFFICIENT_ALLOWANCE");
    
            unchecked {
                _allowed[_from[i]][_spender] = currentAllowance - _amount[i];
            }
        }
    } 

    function _beforeBondTransfer(
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _data
    ) internal virtual {}

    function _afterBondTransfer(
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _data
    ) internal virtual {}
}
