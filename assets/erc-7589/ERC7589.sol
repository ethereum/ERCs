// SPDX-License-Identifier: CC0-1.0

pragma solidity 0.8.9;

import { ISftRolesRegistry } from './interfaces/ISftRolesRegistry.sol';
import { ICommitTokensAndGrantRoleExtension } from './interfaces/ICommitTokensAndGrantRoleExtension.sol';
import { IERC165 } from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import { IERC1155 } from '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import { IERC1155Receiver } from '@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol';
import { ERC1155Holder, ERC1155Receiver } from '@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol';
import { ERC165Checker } from '@openzeppelin/contracts/utils/introspection/ERC165Checker.sol';

// Semi-fungible token (SFT) roles registry
contract SftRolesRegistry is ISftRolesRegistry, ERC1155Holder, ICommitTokensAndGrantRoleExtension {
    bytes32 public constant UNIQUE_ROLE = keccak256('UNIQUE_ROLE');

    uint256 public commitmentCount;

    // grantor => tokenAddress => operator => isApproved
    mapping(address => mapping(address => mapping(address => bool))) public roleApprovals;

    // commitmentId => Commitment
    mapping(uint256 => Commitment) public commitments;

    // commitmentId => role => RoleAssignment
    mapping(uint256 => mapping(bytes32 => RoleAssignment)) internal roleAssignments;

    modifier onlyOwnerOrApproved(address _account, address _tokenAddress) {
        require(
            _account == msg.sender || isRoleApprovedForAll(_tokenAddress, _account, msg.sender),
            'SftRolesRegistry: account not approved'
        );
        _;
    }

    modifier sameGrantee(
        uint256 _commitmentId,
        bytes32 _role,
        address _grantee
    ) {
        require(
            _grantee != address(0) && _grantee == roleAssignments[_commitmentId][_role].grantee,
            'SftRolesRegistry: grantee mismatch'
        );
        _;
    }

    /** External Functions **/

    function commitTokens(
        address _grantor,
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _tokenAmount
    ) external override onlyOwnerOrApproved(_grantor, _tokenAddress) returns (uint256 commitmentId_) {
        require(_tokenAmount > 0, 'SftRolesRegistry: tokenAmount must be greater than zero');
        commitmentId_ = _createCommitment(_grantor, _tokenAddress, _tokenId, _tokenAmount);
    }

    function grantRole(
        uint256 _commitmentId,
        bytes32 _role,
        address _grantee,
        uint64 _expirationDate,
        bool _revocable,
        bytes calldata _data
    )
    external
    override
    onlyOwnerOrApproved(commitments[_commitmentId].grantor, commitments[_commitmentId].tokenAddress)
    {
        require(_role == UNIQUE_ROLE, 'SftRolesRegistry: role not supported');
        require(_expirationDate > block.timestamp, 'SftRolesRegistry: expiration date must be in the future');
        _grantOrUpdateRole(_commitmentId, _role, _grantee, _expirationDate, _revocable, _data);
    }

    function revokeRole(
        uint256 _commitmentId,
        bytes32 _role,
        address _grantee
    ) external override sameGrantee(_commitmentId, _role, _grantee) {
        RoleAssignment storage roleAssignment = roleAssignments[_commitmentId][_role];
        Commitment storage commitment = commitments[_commitmentId];
        address caller = _findCaller(commitment.grantor, roleAssignment.grantee, commitment.tokenAddress);
        if (roleAssignment.expirationDate > block.timestamp && !roleAssignment.revocable) {
            // if role is not expired and is not revocable, only the grantee can revoke it
            require(caller == roleAssignment.grantee, 'SftRolesRegistry: role is not expired and is not revocable');
        }
        emit RoleRevoked(_commitmentId, _role, roleAssignment.grantee);
        delete roleAssignments[_commitmentId][_role];
    }

    function releaseTokens(
        uint256 _commitmentId
    ) external onlyOwnerOrApproved(commitments[_commitmentId].grantor, commitments[_commitmentId].tokenAddress) {
        require(
            roleAssignments[_commitmentId][UNIQUE_ROLE].expirationDate < block.timestamp ||
            roleAssignments[_commitmentId][UNIQUE_ROLE].revocable,
            'SftRolesRegistry: commitment has an active non-revocable role'
        );

        delete roleAssignments[_commitmentId][UNIQUE_ROLE];

        _transferFrom(
            address(this),
            commitments[_commitmentId].grantor,
            commitments[_commitmentId].tokenAddress,
            commitments[_commitmentId].tokenId,
            commitments[_commitmentId].tokenAmount
        );

        delete commitments[_commitmentId];
        emit TokensReleased(_commitmentId);
    }

    function setRoleApprovalForAll(address _tokenAddress, address _operator, bool _isApproved) external override {
        roleApprovals[msg.sender][_tokenAddress][_operator] = _isApproved;
        emit RoleApprovalForAll(_tokenAddress, _operator, _isApproved);
    }

    /** Optional External Functions **/

    function commitTokensAndGrantRole(
        address _grantor,
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _tokenAmount,
        bytes32 _role,
        address _grantee,
        uint64 _expirationDate,
        bool _revocable,
        bytes calldata _data
    ) external override onlyOwnerOrApproved(_grantor, _tokenAddress) returns (uint256 commitmentId_) {
        require(_tokenAmount > 0, 'SftRolesRegistry: tokenAmount must be greater than zero');
        require(_role == UNIQUE_ROLE, 'SftRolesRegistry: role not supported');
        require(_expirationDate > block.timestamp, 'SftRolesRegistry: expiration date must be in the future');
        commitmentId_ = _createCommitment(_grantor, _tokenAddress, _tokenId, _tokenAmount);
        _grantOrUpdateRole(commitmentId_, _role, _grantee, _expirationDate, _revocable, _data);
    }

    /** View Functions **/

    function grantorOf(uint256 _commitmentId) external view returns (address grantor_) {
        grantor_ = commitments[_commitmentId].grantor;
    }

    function tokenAddressOf(uint256 _commitmentId) external view returns (address tokenAddress_) {
        tokenAddress_ = commitments[_commitmentId].tokenAddress;
    }

    function tokenIdOf(uint256 _commitmentId) external view returns (uint256 tokenId_) {
        tokenId_ = commitments[_commitmentId].tokenId;
    }

    function tokenAmountOf(uint256 _commitmentId) external view returns (uint256 tokenAmount_) {
        tokenAmount_ = commitments[_commitmentId].tokenAmount;
    }

    function roleData(
        uint256 _commitmentId,
        bytes32 _role,
        address _grantee
    ) external view sameGrantee(_commitmentId, _role, _grantee) returns (bytes memory data_) {
        return roleAssignments[_commitmentId][_role].data;
    }

    function roleExpirationDate(
        uint256 _commitmentId,
        bytes32 _role,
        address _grantee
    ) external view sameGrantee(_commitmentId, _role, _grantee) returns (uint64 expirationDate_) {
        return roleAssignments[_commitmentId][_role].expirationDate;
    }

    function isRoleRevocable(
        uint256 _commitmentId,
        bytes32 _role,
        address _grantee
    ) external view sameGrantee(_commitmentId, _role, _grantee) returns (bool revocable_) {
        return roleAssignments[_commitmentId][_role].revocable;
    }

    function isRoleApprovedForAll(
        address _tokenAddress,
        address _grantor,
        address _operator
    ) public view override returns (bool) {
        return roleApprovals[_grantor][_tokenAddress][_operator];
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC1155Receiver, IERC165) returns (bool) {
        return
            interfaceId == type(ISftRolesRegistry).interfaceId ||
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(ICommitTokensAndGrantRoleExtension).interfaceId;
    }

    /** Helper Functions **/

    function _createCommitment(
        address _grantor,
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _tokenAmount
    ) internal returns (uint256 commitmentId_) {
        commitmentId_ = ++commitmentCount;
        commitments[commitmentId_] = Commitment(_grantor, _tokenAddress, _tokenId, _tokenAmount);
        _transferFrom(_grantor, address(this), _tokenAddress, _tokenId, _tokenAmount);
        emit TokensCommitted(_grantor, commitmentId_, _tokenAddress, _tokenId, _tokenAmount);
    }

    function _grantOrUpdateRole(
        uint256 _commitmentId,
        bytes32 _role,
        address _grantee,
        uint64 _expirationDate,
        bool _revocable,
        bytes calldata _data
    ) internal {
        roleAssignments[_commitmentId][_role] = RoleAssignment(_grantee, _expirationDate, _revocable, _data);
        emit RoleGranted(_commitmentId, _role, _grantee, _expirationDate, _revocable, _data);
    }

    function _transferFrom(
        address _from,
        address _to,
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _tokenAmount
    ) internal {
        IERC1155(_tokenAddress).safeTransferFrom(_from, _to, _tokenId, _tokenAmount, '');
    }

    // careful with the following edge case:
    // if grantee is approved by grantor, the first one checked is returned
    // if grantor is returned instead of grantee, the grantee won't be able
    // to revoke the role assignment before the expiration date
    function _findCaller(address _grantor, address _grantee, address _tokenAddress) internal view returns (address) {
        if (_grantee == msg.sender || isRoleApprovedForAll(_tokenAddress, _grantee, msg.sender)) {
            return _grantee;
        }
        if (_grantor == msg.sender || isRoleApprovedForAll(_tokenAddress, _grantor, msg.sender)) {
            return _grantor;
        }
        revert('SftRolesRegistry: sender must be approved');
    }
}
