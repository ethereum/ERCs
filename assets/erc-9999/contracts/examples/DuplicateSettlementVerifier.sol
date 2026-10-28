// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "../ADRFTypes.sol";
import {IADRFVerifier} from "../interfaces/IADRFVerifier.sol";

/// Minimal ledger view a settlement contract exposes for formal verification.
interface ISettlementLedger {
    function settlementCount(uint256 callId) external view returns (uint32);
}

/// @title  DuplicateSettlementVerifier — FORMAL method: "the obligation was settled more than once"
/// @notice A deterministic verifier over on-chain state. The proposition must be the canonical hash of the
///         statement for the ledger and call it names; otherwise the verifier returns UNDETERMINED rather than
///         answering a question it was not asked. The finding says only that, under this ledger's records,
///         the settlement count of the call exceeds one.
contract DuplicateSettlementVerifier is IADRFVerifier {
    bytes32 public constant STATEMENT = keccak256("adrf:prop/duplicate-settlement/v1");

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == type(IADRFVerifier).interfaceId;
    }

    function propositionFor(address ledger, uint256 callId) public pure returns (bytes32) {
        return keccak256(abi.encode(STATEMENT, ledger, callId));
    }

    /// `params` names the ledger; `inputs` is abi.encode(uint256 callId).
    function verify(bytes32 proposition, bytes32 params, bytes calldata inputs)
        external view returns (T.Value value, bytes32 resultHash)
    {
        address ledger = address(uint160(uint256(params)));
        uint256 callId = abi.decode(inputs, (uint256));
        if (proposition != propositionFor(ledger, callId)) return (T.Value.UNDETERMINED, bytes32(0));
        uint32 count = ISettlementLedger(ledger).settlementCount(callId);
        value = count > 1 ? T.Value.TRUE : T.Value.FALSE;
        resultHash = keccak256(abi.encode(ledger, callId, count));
    }
}
