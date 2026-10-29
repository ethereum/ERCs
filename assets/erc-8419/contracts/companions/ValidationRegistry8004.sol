// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IERC8004ValidationRegistry, IERC8004IdentityRegistry} from "../interfaces/IERC8004Validation.sol";

/// @title ValidationRegistry8004 — minimal, non-upgradeable ERC-8004 Validation Registry
/// @notice Spec-conforming reference used by the KYA companion deployments. The canonical
///         ERC-8004 Validation Registry deployment is still pending on public networks; this
///         contract binds to any ERC-721 Identity Registry (for Sepolia: the official one at
///         0x8004A818BFB912233c491871b3d84c89A494BD9e) and implements the same
///         request/response/status surface, so KYABridge8004 can be exercised end to end.
///         Access rules mirror the 8004 reference: only the agent owner or an approved operator
///         may file a request; only the named validator may respond.
contract ValidationRegistry8004 is IERC8004ValidationRegistry {
    struct Rec {
        address validator;
        uint256 agentId;
        uint8 response;
        bytes32 responseHash;
        string tag;
        uint256 lastUpdate;
        bool hasResponse;
    }

    address private immutable _identity;
    mapping(bytes32 => Rec) private _recs;
    mapping(uint256 => bytes32[]) private _byAgent;
    mapping(address => bytes32[]) private _byValidator;

    constructor(address identityRegistry_) {
        require(identityRegistry_ != address(0), "bad identity");
        _identity = identityRegistry_;
    }

    function getIdentityRegistry() external view returns (address) {
        return _identity;
    }

    function validationRequest(address validatorAddress, uint256 agentId, string calldata requestURI, bytes32 requestHash) external {
        require(validatorAddress != address(0), "bad validator");
        require(_recs[requestHash].validator == address(0), "exists");
        IERC8004IdentityRegistry reg = IERC8004IdentityRegistry(_identity);
        address owner = reg.ownerOf(agentId);
        require(
            msg.sender == owner || reg.isApprovedForAll(owner, msg.sender) || reg.getApproved(agentId) == msg.sender,
            "Not authorized"
        );
        _recs[requestHash] = Rec(validatorAddress, agentId, 0, bytes32(0), "", block.timestamp, false);
        _byAgent[agentId].push(requestHash);
        _byValidator[validatorAddress].push(requestHash);
        emit ValidationRequest(validatorAddress, agentId, requestURI, requestHash);
    }

    function validationResponse(bytes32 requestHash, uint8 response, string calldata responseURI, bytes32 responseHash, string calldata tag) external {
        Rec storage r = _recs[requestHash];
        require(r.validator != address(0), "unknown");
        require(msg.sender == r.validator, "not validator");
        require(response <= 100, "resp>100");
        r.response = response;
        r.responseHash = responseHash;
        r.tag = tag;
        r.lastUpdate = block.timestamp;
        r.hasResponse = true;
        emit ValidationResponse(r.validator, r.agentId, requestHash, response, responseURI, responseHash, tag);
    }

    function getValidationStatus(bytes32 requestHash)
        external
        view
        returns (address validatorAddress, uint256 agentId, uint8 response, bytes32 responseHash, string memory tag, uint256 lastUpdate)
    {
        Rec storage r = _recs[requestHash];
        return (r.validator, r.agentId, r.response, r.responseHash, r.tag, r.lastUpdate);
    }

    function getAgentValidations(uint256 agentId) external view returns (bytes32[] memory) {
        return _byAgent[agentId];
    }

    function getValidatorRequests(address validatorAddress) external view returns (bytes32[] memory) {
        return _byValidator[validatorAddress];
    }

    /// @notice Aggregate over a validator set and optional tag (ERC-8004 getSummary).
    function getSummary(uint256 agentId, address[] calldata validatorAddresses, string calldata tag)
        external
        view
        returns (uint64 count, uint8 averageResponse)
    {
        bytes32 tagHash = keccak256(bytes(tag));
        bool anyTag = bytes(tag).length == 0;
        uint256 sum;
        bytes32[] storage hs = _byAgent[agentId];
        for (uint256 i = 0; i < hs.length; i++) {
            Rec storage r = _recs[hs[i]];
            if (!r.hasResponse) continue;
            if (!anyTag && keccak256(bytes(r.tag)) != tagHash) continue;
            bool ok = validatorAddresses.length == 0;
            for (uint256 j = 0; j < validatorAddresses.length && !ok; j++) ok = validatorAddresses[j] == r.validator;
            if (!ok) continue;
            sum += r.response;
            count++;
        }
        averageResponse = count == 0 ? 0 : uint8(sum / count);
    }
}
