// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ISmartDirectoryERC} from "./ISmartDirectoryERC.sol";

contract SmartDirectoryERC is ISmartDirectoryERC {

    string private constant VERSION = "ERC 0.1";



    /// @dev Structure packing to optimize storage space and gas costs.
    struct Reference {
        uint96 latestStatusIndex;
        address registrantAddress;
        address referenceAddress;
        string referenceDescription;
        string referenceType;
        string referenceVersion;
        string status;
    }

    struct Registrant {
        string uri;
        uint256 index;
        address[] references;
    }

    // EVENTS

    event SmartDirectoryCreated(
    );

    event SmartDirectoryActivationUpdated(
        address indexed from,
        ActivationCode activationCode
    );

    event ReferenceCreated(
        address indexed registrant,
        address indexed referenceAddress
    );

    event ReferenceStatusUpdated(
        address indexed registrant,
        address indexed referenceAddress
    );

    event RegistrantCreated(
        address indexed registrant,
        address createdBy
    );

    event RegistrantUriUpdated(
        address indexed registrant,
        string indexed registrantUri
    );

    event RegistrantDisabled(
        address indexed registrant
    );

    // contract DATA
    address owner;
    string URI;
    address[] registrants;
    mapping(address => Registrant) registrantData;
    mapping(address => Reference) referenceData;
    ActivationCode activationCode;

    constructor (
        string memory _contractUri)  {
        owner = msg.sender;
        URI = _contractUri;
        activationCode = ActivationCode.pending;
    }

    // MODIFIERS

    modifier onlyActive() {
        require(activationCode == ActivationCode.active, "SmartDirectory is not active");
        _;
    }

    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "unauthorized access: only the owner may call this function"
        );
        _;
    }

    function isValidRegistrant(
        address _registrantAddress
    ) public view returns (bool) {
        return registrantData[_registrantAddress].index != 0;
    }

    function isDeclaredReference(
        address _referenceAddress
    ) internal view returns (bool) {
        return referenceData[_referenceAddress].registrantAddress != address(0);
    }

//  SmartDirectory Management

    function setActivationCode(ActivationCode _activationCode) external{
        activationCode = _activationCode;
    }

    function getContractUri() public view returns (string memory) {
        return URI;
    }

    function getContractVersion() public pure returns (string memory) {
        return VERSION;
    }

    function getActivationCode() external view returns(ActivationCode){
        return activationCode;
    }

    
//  registrant Management
    function createRegistrant(address _registrantAddress) public onlyOwner() onlyActive() {

       require(registrantData[_registrantAddress].index == 0, "registrant already known");

        Registrant memory registrant = Registrant("", 0, new address[](0));
        registrant.index = registrants.length;

        registrants.push(_registrantAddress);
        registrantData[_registrantAddress] = registrant;
        emit RegistrantCreated(_registrantAddress, msg.sender);
    }

    function disableRegistrant(
        address _registrantAddress
    ) public onlyOwner() onlyActive(){

        uint256 registrantIndex = getRegistrantIndex(_registrantAddress);
        require(registrantIndex <= registrants.length, "Inconsistent: index too large");
        require(isValidRegistrant(_registrantAddress), "Registrant not found or disabled");

        registrantData[_registrantAddress].index = 0;
        emit RegistrantDisabled(_registrantAddress);
    }

    function updateRegistrantUri(
        string memory _registrantUri
    ) public onlyActive() {

        require(isValidRegistrant(msg.sender), "unknown registrant");

        registrantData[msg.sender].uri = _registrantUri;
        emit RegistrantUriUpdated(msg.sender, _registrantUri);
    }

    function getRegistrantUri(
        address _registrantAddress
    ) public view returns(string memory) {

        require (registrantData[_registrantAddress].index > 0, "unknown registrant");

        return registrantData[_registrantAddress].uri;
    }

    function getRegistrantIndex(
        address _registrantAddress
    ) internal view returns(uint256) {
        return registrantData[_registrantAddress].index;
    }

    function getDisabledRegistrants() external view 
                returns (address[] memory disabledRegistrantsList){
        uint256 disabledCount = 0;
        for (uint256 i = 1; i < registrants.length; i++) {
            if (registrantData[registrants[i]].index == 0) {
                disabledCount++;
            }
        }

        address[] memory disabledRegistrants = new address[](disabledCount);
        uint256 index = 0;

        for (uint256 i = 1; i < registrants.length; i++) {
            if (registrantData[registrants[i]].index == 0) {
                disabledRegistrants[index] = registrants[i];
                index++;
            }
        }

        return disabledRegistrants;
    }

// Reference Management

    function createReference(
        address _referenceAddress,
        string memory _referenceDescription,
        string memory _referenceType,
        string memory _referenceVersion,
        string memory _status
    )  public onlyActive() {
        require(_referenceAddress != address(0x0), "reference must not be address 0");
        require(!isDeclaredReference(_referenceAddress), "reference already known");

        Reference storage ref = referenceData[_referenceAddress];

        ref.registrantAddress = msg.sender;
        ref.referenceAddress = _referenceAddress;
        ref.referenceDescription = _referenceDescription;
        ref.referenceType = _referenceType;
        ref.referenceVersion = _referenceVersion;

        ref.status = _status;

        emit ReferenceCreated(msg.sender, _referenceAddress);
    }

    function updateReferenceStatus(
        address _referenceAddress,
        string memory _newStatus
    ) public onlyActive() {
        require(isValidRegistrant(msg.sender), "unknown or disabled registrant");
        require(isDeclaredReference(_referenceAddress), "unknown reference");

        Reference storage ref = referenceData[_referenceAddress];

        require(
            msg.sender == ref.registrantAddress ||
            msg.sender == owner, 
            "Unauthorized access: only reference owner or contract owner can call this function"
        );

        ref.status = _newStatus;

        emit ReferenceStatusUpdated(msg.sender, _referenceAddress);
    }


    function getReference(
        address _referenceAddress
    ) public onlyActive() view returns (
        address registrantAddress,
        address referenceAddress,
        string memory referenceDescription,
        string memory referenceType,
        string memory referenceVersion,
        string memory status) {

        Reference storage ref = referenceData[_referenceAddress];

        require(ref.referenceAddress != address(0), "unknown reference");

        return (
            ref.registrantAddress,
            ref.referenceAddress,
            ref.referenceDescription,
            ref.referenceType,
            ref.referenceVersion,
            ref.status
        );
    }


    function getReferenceStatus(
        address _referenceAddress
    ) public onlyActive() view returns
        (string memory status) {

        Reference storage ref = referenceData[_referenceAddress];

        require(isDeclaredReference(_referenceAddress), "unknown reference");

        return (ref.status);
    }

    function getReferencesLists(
        address _registrantAddress
    ) public view returns(address[] memory referenceAddressesList, 
                          string[] memory referenceDescriptionsList) {

        require(isValidRegistrant(_registrantAddress), "Unknown or disabled registrant");

        address[] storage references = registrantData[_registrantAddress].references;
        uint256 count = references.length;

        address[] memory referenceAddressesResult = new address[](count);
        string[] memory referenceDescriptionsResult = new string[](count);

        for (uint256 i = 0; i < count; i++) {
            address referenceAddress = references[i];

            require(
                referenceData[referenceAddress].registrantAddress == _registrantAddress,
                "Reference does not belong to the given registrant"
            );

            referenceAddressesResult[i] = referenceAddress;
            referenceDescriptionsResult[i] = referenceData[referenceAddress].referenceDescription;
        }

        return (referenceAddressesResult, referenceDescriptionsResult);
    }


}