pragma solidity ^0.8.1;

/// @title ERC-4824: DAO Registration
contract ERC-4824Registration is IERC-4824, AccessControl {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    string private _daoURI;

    address daoAddress;

    constructor() {
        daoAddress = address(0xdead);
    }

    /// @notice Set the initial DAO URI and offer manager role to an address
    /// @dev Throws if initialized already
    /// @param _daoAddress The primary address for a DAO
    /// @param _manager The address of the URI manager
    /// @param daoURI_ The URI which will resolve to the governance docs
    function initialize(
        address _daoAddress,
        address _manager,
        string memory daoURI_,
        address _ERC-4824Index
    ) external {
        initialize(_daoAddress, daoURI_, _ERC-4824Index);
        _grantRole(MANAGER_ROLE, _manager);
    }

    /// @notice Set the initial DAO URI
    /// @dev Throws if initialized already
    /// @param _daoAddress The primary address for a DAO
    /// @param daoURI_ The URI which will resolve to the governance docs
    function initialize(
        address _daoAddress,
        string memory daoURI_,
        address _ERC-4824Index
    ) public {
        if (daoAddress != address(0)) revert AlreadyInitialized();
        daoAddress = _daoAddress;
        _setURI(daoURI_);

        _grantRole(DEFAULT_ADMIN_ROLE, _daoAddress);
        _grantRole(MANAGER_ROLE, _daoAddress);

        ERC-4824Index(_ERC-4824Index).logRegistration(address(this));
    }

    /// @notice Update the URI for a DAO
    /// @dev Throws if not called by dao or manager
    /// @param daoURI_ The URI which will resolve to the governance docs
    function setURI(string memory daoURI_) public onlyRole(MANAGER_ROLE) {
        _setURI(daoURI_);
    }

    function _setURI(string memory daoURI_) internal {
        _daoURI = daoURI_;
        emit DAOURIUpdate(daoAddress, daoURI_);
    }

    function daoURI() external view returns (string memory daoURI_) {
        return _daoURI;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC-4824).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
