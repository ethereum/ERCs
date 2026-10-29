// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "../ADRFTypes.sol";
import {IADRFVerifier} from "../interfaces/IADRFVerifier.sol";

/// Minimal view a service contract exposes for the version commitment of a call.
interface IVersionedService {
    function versionsOf(uint256 callId) external view returns (bytes32 committed, bytes32 declared);
}

/// The canonical statement of the declared-version verifier, shared with the sources that recognize it:
/// "the version the provider declared for call `callId` of `service` differs from the version the terms committed".
library DeclaredVersionStatement {
    bytes32 internal constant STATEMENT = keccak256("adrf:prop/declared-version-differs/v1");

    function propositionFor(address service, uint256 callId) internal pure returns (bytes32) {
        return keccak256(abi.encode(STATEMENT, service, callId));
    }
}

/// @title  DeclaredVersionVerifier — FORMAL method: "the declared version differs from the committed version"
/// @notice Compares two on-chain statements of a service call: the version the terms committed and the version
///         the provider declared at delivery. A TRUE finding means the provider's own declaration departs from
///         its commitment; a FALSE finding means the declaration matches, which says nothing about the version
///         that actually ran — that is a fact for an evidence rule, never for this verifier. UNDETERMINED when the
///         call was not delivered or the proposition is not the canonical one for this service and call.
contract DeclaredVersionVerifier is IADRFVerifier {
    bytes32 public constant STATEMENT = DeclaredVersionStatement.STATEMENT;

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == type(IADRFVerifier).interfaceId;
    }

    function propositionFor(address service, uint256 callId) public pure returns (bytes32) {
        return DeclaredVersionStatement.propositionFor(service, callId);
    }

    /// `params` names the service; `inputs` is abi.encode(uint256 callId).
    function verify(bytes32 proposition, bytes32 params, bytes calldata inputs)
        external view returns (T.Value value, bytes32 resultHash)
    {
        address service = address(uint160(uint256(params)));
        uint256 callId = abi.decode(inputs, (uint256));
        if (proposition != propositionFor(service, callId)) return (T.Value.UNDETERMINED, bytes32(0));
        (bytes32 committed, bytes32 declared) = IVersionedService(service).versionsOf(callId);
        if (declared == bytes32(0)) return (T.Value.UNDETERMINED, keccak256(abi.encode(service, callId, committed, declared)));
        value = declared != committed ? T.Value.TRUE : T.Value.FALSE;
        resultHash = keccak256(abi.encode(service, callId, committed, declared));
    }
}
