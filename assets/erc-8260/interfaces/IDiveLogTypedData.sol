// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "./IDiveLogTypes.sol";

library DiveLogTypedData {
    bytes32 internal constant DOMAIN_NAME = keccak256("DiveLog");
    bytes32 internal constant DOMAIN_VERSION = keccak256("1");

    bytes32 internal constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    bytes32 internal constant ATTESTATION_TYPEHASH = keccak256(
        "Attestation(uint256 diveId,address verifyingContract,uint256 nonce)"
    );

    bytes32 internal constant DIVE_DATA_TYPEHASH = keccak256(
        "DiveData(uint32 leaveSurfaceTime,uint32 leaveBottomTime,uint32 reachSurfaceTime,uint32 bottomTimeMinutes,uint32 maxDepth,int32 averageDepth,uint8 mode,uint8 purpose,uint8 suit)"
    );

    bytes32 internal constant ENVIRONMENT_TYPEHASH = keccak256(
        "Environment(int32 airTemp,int32 waterTemp,int16 currentKnots,string location,string bottomType,string weatherConditions)"
    );

    bytes32 internal constant DECOMPRESSION_TYPEHASH = keccak256(
        "Decompression(uint8 decompType,uint32 totalDecompTimeMinutes,int32 maxDepthAttained,bytes32 tableSchedule,bytes1 repetitiveGroup,uint32 surfaceIntervalMinutes,bytes1 newRepetitiveGroup)"
    );

    bytes32 internal constant GAS_DATA_TYPEHASH = keccak256(
        "GasData(uint8 gasType,uint16 o2Percent,uint16 hePercent,uint16 n2Percent,uint32 cylinderPressureIn,uint32 cylinderPressureOut,uint32 gasConsumed,uint32 bailoutPressure)"
    );

    bytes32 internal constant DIVE_LOG_TYPEHASH = keccak256(
        "DiveLog(uint256 id,uint64 diveDate,uint8 units,DiveData data,Environment env,Decompression decomp,GasData gas,string remarks)"
    );

    function domainSeparator(uint256 chainId, address verifyingContract) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            EIP712_DOMAIN_TYPEHASH,
            DOMAIN_NAME,
            DOMAIN_VERSION,
            chainId,
            verifyingContract
        ));
    }

    function attestationDigest(
        uint256 diveId,
        address verifyingContract,
        uint256 chainId,
        uint256 nonce
    ) internal pure returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(
            ATTESTATION_TYPEHASH,
            diveId,
            verifyingContract,
            nonce
        ));

        return keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator(chainId, verifyingContract),
            structHash
        ));
    }

    function hashDiveData(DiveData calldata d) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            DIVE_DATA_TYPEHASH,
            d.leaveSurfaceTime,
            d.leaveBottomTime,
            d.reachSurfaceTime,
            d.bottomTimeMinutes,
            d.maxDepth,
            d.averageDepth,
            uint8(d.mode),
            uint8(d.purpose),
            uint8(d.suit)
        ));
    }

    function hashEnvironment(Environment calldata e) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            ENVIRONMENT_TYPEHASH,
            e.airTemp,
            e.waterTemp,
            e.currentKnots,
            keccak256(bytes(e.location)),
            keccak256(bytes(e.bottomType)),
            keccak256(bytes(e.weatherConditions))
        ));
    }

    function hashDecompression(Decompression calldata d) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            DECOMPRESSION_TYPEHASH,
            uint8(d.decompType),
            d.totalDecompTimeMinutes,
            d.maxDepthAttained,
            d.tableSchedule,
            d.repetitiveGroup,
            d.surfaceIntervalMinutes,
            d.newRepetitiveGroup
        ));
    }

    function hashGasData(GasData calldata g) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            GAS_DATA_TYPEHASH,
            uint8(g.gasType),
            g.o2Percent,
            g.hePercent,
            g.n2Percent,
            g.cylinderPressureIn,
            g.cylinderPressureOut,
            g.gasConsumed,
            g.bailoutPressure
        ));
    }

    function hashDiveLog(DiveLog calldata dive) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            DIVE_LOG_TYPEHASH,
            dive.id,
            dive.diveDate,
            uint8(dive.units),
            hashDiveData(dive.data),
            hashEnvironment(dive.env),
            hashDecompression(dive.decomp),
            hashGasData(dive.gas),
            keccak256(bytes(dive.remarks))
        ));
    }
}
