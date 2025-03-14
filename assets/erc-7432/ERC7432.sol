// SPDX-License-Identifier: CC0-1.0

pragma solidity 0.8.9;

import { IERC7432 } from "./interfaces/IERC7432.sol";
import { IERC721 } from '@openzeppelin/contracts/token/ERC721/IERC721.sol';

contract ERC7432 is IERC7432 {
    struct RoleData {
        address recipient;
        uint64 expirationDate;
        bool revocable;
        bytes data;
    }

    bytes32[] public allowedRoles;

    // roleId => isAllowed
    mapping(bytes32 => bool) public isRoleAllowed;

    // tokenAddress => tokenId => owner
    mapping(address => mapping(uint256 => address)) public originalOwners;

    // tokenAddress => tokenId => roleId => struct(recipient, expirationDate, revocable, data)
    mapping(address => mapping(uint256 => mapping(bytes32 => RoleData))) public roles;

    // owner => tokenAddress => operator => isApproved
    mapping(address => mapping(address => mapping(address => bool))) public tokenApprovals;

    constructor() {
        allowedRoles = [keccak256('UNIQUE_ROLE')];
        for (uint256 i = 0; i < allowedRoles.length; i++) {
            isRoleAllowed[allowedRoles[i]] = true;
        }
    }

    modifier onlyAllowedRole(bytes32 _roleId) {
        require(isRoleAllowed[_roleId], 'NftRolesRegistryVault: role is not allowed');
        _;
    }

    /** External Functions **/

    function grantRole(IERC7432.Role calldata _role) external override onlyAllowedRole(_role.roleId) {
        require(_role.expirationDate > block.timestamp, 'NftRolesRegistryVault: expiration date must be in the future');

        // deposit NFT if necessary
        // reverts if sender is not approved or original owner
        address _originalOwner = _depositNft(_role.tokenAddress, _role.tokenId);

        // role must be expired or revocable
        RoleData storage _roleData = roles[_role.tokenAddress][_role.tokenId][_role.roleId];
        require(
            _roleData.revocable || _roleData.expirationDate < block.timestamp,
            'NftRolesRegistryVault: role must be expired or revocable'
        );

        roles[_role.tokenAddress][_role.tokenId][_role.roleId] = RoleData(
            _role.recipient,
            _role.expirationDate,
            _role.revocable,
            _role.data
        );

        emit RoleGranted(
            _role.tokenAddress,
            _role.tokenId,
            _role.roleId,
            _originalOwner,
            _role.recipient,
            _role.expirationDate,
            _role.revocable,
            _role.data
        );
    }

    function revokeRole(
        address _tokenAddress,
        uint256 _tokenId,
        bytes32 _roleId
    ) external override onlyAllowedRole(_roleId) {
        address _recipient = roles[_tokenAddress][_tokenId][_roleId].recipient;
        address _caller = _getApprovedCaller(_tokenAddress, _tokenId, _recipient);

        // if caller is recipient, the role can be revoked regardless of its state
        if (_caller != _recipient) {
            // if caller is owner, the role can only be revoked if revocable or expired
            require(
                roles[_tokenAddress][_tokenId][_roleId].revocable ||
                roles[_tokenAddress][_tokenId][_roleId].expirationDate < block.timestamp,
                'NftRolesRegistryVault: role is not revocable nor expired'
            );
        }

        delete roles[_tokenAddress][_tokenId][_roleId];
        emit RoleRevoked(_tokenAddress, _tokenId, _roleId);
    }

    function unlockToken(address _tokenAddress, uint256 _tokenId) external override {
        address originalOwner = originalOwners[_tokenAddress][_tokenId];

        require(!_hasNonRevocableRole(_tokenAddress, _tokenId), 'NftRolesRegistryVault: NFT is locked');

        require(
            originalOwner == msg.sender || isRoleApprovedForAll(_tokenAddress, originalOwner, msg.sender),
            'NftRolesRegistryVault: sender must be owner or approved'
        );

        delete originalOwners[_tokenAddress][_tokenId];
        IERC721(_tokenAddress).transferFrom(address(this), originalOwner, _tokenId);
        emit TokenUnlocked(originalOwner, _tokenAddress, _tokenId);
    }

    function setRoleApprovalForAll(address _tokenAddress, address _operator, bool _approved) external override {
        tokenApprovals[msg.sender][_tokenAddress][_operator] = _approved;
        emit RoleApprovalForAll(_tokenAddress, _operator, _approved);
    }

    /** ERC-7432 View Functions **/

    function ownerOf(address _tokenAddress, uint256 _tokenId) external view returns (address owner_) {
        return originalOwners[_tokenAddress][_tokenId];
    }

    function recipientOf(
        address _tokenAddress,
        uint256 _tokenId,
        bytes32 _roleId
    ) external view returns (address recipient_) {
        if (roles[_tokenAddress][_tokenId][_roleId].expirationDate > block.timestamp) {
            return roles[_tokenAddress][_tokenId][_roleId].recipient;
        }
        return address(0);
    }

    function roleData(
        address _tokenAddress,
        uint256 _tokenId,
        bytes32 _roleId
    ) external view returns (bytes memory data_) {
        if (roles[_tokenAddress][_tokenId][_roleId].expirationDate > block.timestamp) {
            data_ = roles[_tokenAddress][_tokenId][_roleId].data;
        }
        return data_;
    }

    function roleExpirationDate(
        address _tokenAddress,
        uint256 _tokenId,
        bytes32 _roleId
    ) external view returns (uint64 expirationDate_) {
        if (roles[_tokenAddress][_tokenId][_roleId].expirationDate > block.timestamp) {
            return roles[_tokenAddress][_tokenId][_roleId].expirationDate;
        }
        return 0;
    }

    function isRoleRevocable(
        address _tokenAddress,
        uint256 _tokenId,
        bytes32 _roleId
    ) external view returns (bool revocable_) {
        return
            roles[_tokenAddress][_tokenId][_roleId].expirationDate > block.timestamp &&
            roles[_tokenAddress][_tokenId][_roleId].revocable;
    }

    function isRoleApprovedForAll(address _tokenAddress, address _owner, address _operator) public view returns (bool) {
        return tokenApprovals[_owner][_tokenAddress][_operator];
    }

    /** ERC-165 Functions **/

    function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
        return interfaceId == type(IERC7432).interfaceId;
    }

    /** Internal Functions **/

    /// @notice Updates originalOwner, validates the sender and deposits NFT (if not deposited yet).
    /// @param _tokenAddress The token address.
    /// @param _tokenId The token identifier.
    /// @return originalOwner_ The original owner of the NFT.
    function _depositNft(address _tokenAddress, uint256 _tokenId) internal returns (address originalOwner_) {
        address _currentOwner = IERC721(_tokenAddress).ownerOf(_tokenId);

        if (_currentOwner == address(this)) {
            // if the NFT is already on the contract, check if sender is approved or original owner
            originalOwner_ = originalOwners[_tokenAddress][_tokenId];
            require(
                originalOwner_ == msg.sender || isRoleApprovedForAll(_tokenAddress, originalOwner_, msg.sender),
                'NftRolesRegistryVault: sender must be owner or approved'
            );
        } else {
            // if NFT is not in the contract, deposit it and store the original owner
            require(
                _currentOwner == msg.sender || isRoleApprovedForAll(_tokenAddress, _currentOwner, msg.sender),
                'NftRolesRegistryVault: sender must be owner or approved'
            );
            IERC721(_tokenAddress).transferFrom(_currentOwner, address(this), _tokenId);
            originalOwners[_tokenAddress][_tokenId] = _currentOwner;
            originalOwner_ = _currentOwner;
            emit TokenLocked(_currentOwner, _tokenAddress, _tokenId);
        }
    }

    /// @notice Returns the account approved to call the revokeRole function. Reverts otherwise.
    /// @param _tokenAddress The token address.
    /// @param _tokenId The token identifier.
    /// @param _recipient The user that received the role.
    /// @return caller_ The approved account.
    function _getApprovedCaller(
        address _tokenAddress,
        uint256 _tokenId,
        address _recipient
    ) internal view returns (address caller_) {
        if (msg.sender == _recipient || isRoleApprovedForAll(_tokenAddress, _recipient, msg.sender)) {
            return _recipient;
        }
        address originalOwner = originalOwners[_tokenAddress][_tokenId];
        if (msg.sender == originalOwner || isRoleApprovedForAll(_tokenAddress, originalOwner, msg.sender)) {
            return originalOwner;
        }
        revert('NftRolesRegistryVault: role does not exist or sender is not approved');
    }

    /// @notice Checks whether an NFT has at least one non-revocable role.
    /// @param _tokenAddress The token address.
    /// @param _tokenId The token identifier.
    /// @return true if the NFT is locked.
    function _hasNonRevocableRole(address _tokenAddress, uint256 _tokenId) internal view returns (bool) {
        for (uint256 i = 0; i < allowedRoles.length; i++) {
            if (
                !roles[_tokenAddress][_tokenId][allowedRoles[i]].revocable &&
            roles[_tokenAddress][_tokenId][allowedRoles[i]].expirationDate > block.timestamp
            ) {
                return true;
            }
        }
        return false;
    }
}
