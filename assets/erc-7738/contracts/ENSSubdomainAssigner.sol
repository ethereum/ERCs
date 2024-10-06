// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./RegistryENSName.sol";

interface ENS {
    function owner(bytes32 node) external view returns (address);

    function setOwner(bytes32 node, address owner) external;

    function setSubnodeRecord(
        bytes32 node,
        bytes32 label,
        address owner,
        address resolver,
        uint64 ttl
    ) external;

    function resolver(bytes32 node) external view returns (address);
}

interface Resolver {
    function setAddr(bytes32 node, address destination) external;
}

interface IENSSubdomainAssigner {
    function createSubdomain(
        string calldata name,
        address tokenContract,
        address receiver,
        uint256 order
    ) external;

    function getOwner(bytes32 baseLabelHash) external view returns (address);

    function releaseOwnership(bytes32 baseLabelHash, address newOwner) external;

    function setBaseLabel(string calldata label) external;

    function getENSInfo()
        external
        view
        returns (bytes32 baseLabel, address resolver);

    function updateResolverAddress(
        string calldata name,
        address tokenContract,
        address receiver,
        uint256 order
    ) external;
}

contract ENSSubdomainAssigner is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    RegistryENSName
{
    error RegistryOnly();

    // Fixed values which are constant across all chains
    bytes32 private constant ETH_NODE =
        0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae;
    address private _ensRegistry;
    bytes32 private _subHash;
    address private _registry;

    address private _resolver;
    string private _baseLabel;
    bytes32 private _baseLabelHash;

    modifier onlyRegistry() {
        if (msg.sender != _registry) {
            revert RegistryOnly();
        }

        _;
    }

    function initialize(address ens) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        _ensRegistry = ens;
    }

    function setRegistry(address registry) external onlyOwner {
        _registry = registry;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function setBaseLabel(string calldata label) public onlyRegistry {
        bytes32 node = keccak256(
            abi.encodePacked(bytes32(0), keccak256(abi.encodePacked("eth")))
        );
        _subHash = keccak256(
            abi.encodePacked(node, keccak256(abi.encodePacked(label)))
        );
        _baseLabelHash = getName(label);
        _baseLabel = label;

        bytes memory labelBytes = bytes(label);
        // Note, starting the basedomain with "7" switches off subdomain creation: when no ENS is present use domain name "7738"
        if (labelBytes.length > 0 && labelBytes[0] != "7") { 
            _resolver = ENS(_ensRegistry).resolver(_baseLabelHash);
        } else {
            _resolver = address(0);
        }
    }

    // Create subdomain for the label
    // Note: Permissions managed by ENS contract
    function createSubdomain(
        string calldata name,
        address tokenContract,
        address receiver,
        uint256 order
    ) external {
        if (_resolver != address(0)) {
            bytes32 labelhash = keccak256(
                bytes(_formENSName(order, name, tokenContract))
            );

            ENS(_ensRegistry).setSubnodeRecord(
                _baseLabelHash,
                labelhash,
                address(this),
                _resolver,
                0
            );
            updateResolverAddress(name, tokenContract, receiver, order);
        }
    }

    function getENSInfo()
        external
        view
        returns (bytes32 baseLabel, address resolver)
    {
        baseLabel = _baseLabelHash;
        resolver = _resolver;
    }

    function updateResolverAddress(
        string calldata name,
        address tokenContract,
        address receiver,
        uint256 order
    ) public {
        bytes32 subDomainHash = keccak256(
            abi.encodePacked(
                _subHash,
                keccak256(
                    abi.encodePacked(_formENSName(order, name, tokenContract))
                )
            )
        );
        Resolver(_resolver).setAddr(subDomainHash, receiver);
    }

    // Get the owner of base domain
    function getOwner(string memory baseName) external view returns (address) {
        bytes32 labelhash = keccak256(bytes(baseName));
        bytes32 node = keccak256(abi.encodePacked(ETH_NODE, labelhash));
        return ENS(_ensRegistry).owner(node);
    }

    // Get owner of hashed name
    function getHashOwner(
        bytes32 baseLabelHash
    ) external view returns (address) {
        return ENS(_ensRegistry).owner(baseLabelHash);
    }

    // Release ENS name back to the contract owner
    function releaseOwnership(
        bytes32 baseLabelHash,
        address newOwner
    ) external onlyOwner {
        ENS(_ensRegistry).setOwner(baseLabelHash, newOwner);
    }

    // Helper function to form name label
    function getName(string calldata name) public pure returns (bytes32) {
        bytes32 labelhash = keccak256(bytes(name));
        bytes32 node = keccak256(abi.encodePacked(ETH_NODE, labelhash));
        return node;
    }

    // function computeNamehash(string memory label1Str, string memory label2Str) public pure returns (bytes32) {
    //     bytes32 node = keccak256(
    //         abi.encodePacked(bytes32(0), keccak256(abi.encodePacked('eth')))
    //     );
    //     node = keccak256(abi.encodePacked(node, keccak256(abi.encodePacked(label2Str))));
    //     //bytes32 node = keccak256(abi.encodePacked(_nameHashStart, keccak256(abi.encodePacked(label2Str))));
    //     return keccak256(abi.encodePacked(node, keccak256(abi.encodePacked(label1Str))));
    // }
}
