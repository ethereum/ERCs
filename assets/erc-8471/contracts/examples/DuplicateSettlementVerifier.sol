// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "../ADRFTypes.sol";
import {IADRFVerifier} from "../interfaces/IADRFVerifier.sol";

/// Minimal ledger view a settlement contract exposes for formal verification.
interface ISettlementLedger {
    function settlementCount(uint256 callId) external view returns (uint32);
}

/// The canonical statement of the duplicate-settlement verifier, shared with the sources that recognize it:
/// "settlement number `ordinal` of call `callId` on `ledger` exceeds the limit of one charge". One proposition
/// per settlement, so that every charge beyond the first is its own contested point.
library DuplicateSettlementStatement {
    bytes32 internal constant STATEMENT = keccak256("adrf:prop/duplicate-settlement/v2");

    function propositionFor(address ledger, uint256 callId, uint32 ordinal) internal pure returns (bytes32) {
        return keccak256(abi.encode(STATEMENT, ledger, callId, ordinal));
    }
}

/// @title  DuplicateSettlementVerifier — FORMAL method: "settlement n of the call exceeds the one-charge limit"
/// @notice A deterministic verifier over on-chain state. The proposition must be the canonical hash of the
///         statement for the ledger, call and settlement ordinal it names; otherwise the verifier returns
///         UNDETERMINED rather than answering a question it was not asked. The finding says only that, under this
///         ledger's records, settlement `ordinal` of the call exists and is not the first: TRUE for the second
///         and every later settlement, FALSE for the first or for a settlement that does not exist.
contract DuplicateSettlementVerifier is IADRFVerifier {
    bytes32 public constant STATEMENT = DuplicateSettlementStatement.STATEMENT;

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == type(IADRFVerifier).interfaceId;
    }

    function propositionFor(address ledger, uint256 callId, uint32 ordinal) public pure returns (bytes32) {
        return DuplicateSettlementStatement.propositionFor(ledger, callId, ordinal);
    }

    /// `params` names the ledger; `inputs` is abi.encode(uint256 callId, uint32 ordinal).
    function verify(bytes32 proposition, bytes32 params, bytes calldata inputs)
        external view returns (T.Value value, bytes32 resultHash)
    {
        address ledger = address(uint160(uint256(params)));
        (uint256 callId, uint32 ordinal) = abi.decode(inputs, (uint256, uint32));
        if (ordinal == 0 || proposition != propositionFor(ledger, callId, ordinal)) return (T.Value.UNDETERMINED, bytes32(0));
        uint32 count = ISettlementLedger(ledger).settlementCount(callId);
        value = (ordinal > 1 && count >= ordinal) ? T.Value.TRUE : T.Value.FALSE;
        resultHash = keccak256(abi.encode(ledger, callId, ordinal, count));
    }
}
