"""
@title ERC-8270: Canonical Validator Wrapper — Withdrawal Receiver
@license CC0
@author bbjubjub.eth
"""

# pragma version ==0.4.3
# pragma evm-version prague
# pragma nonreentrancy off

from . import IWithdrawalReceiver

implements: IWithdrawalReceiver

WITHDRAWAL_REQUESTS: constant(address) = 0x00000961Ef480Eb55e80D19ad83579A64c007002
CONSOLIDATION_REQUESTS: constant(address) = 0x0000BBdDc7CE488642fb579F8B00f3a590007251

CONTROLLER: public(immutable(address))

validator_key_hi: bytes32
validator_key_lo: bytes16


@deploy
def __init__():
    CONTROLLER = msg.sender


@internal
@view
def _query_fee(target: address) -> uint256:
    out: Bytes[32] = raw_call(target, b"", max_outsize=32, is_static_call=True)
    return extract32(out, 0, output_type=uint256)


@external
@view
def validator_key() -> (bytes32, bytes16):
    return self.validator_key_hi, self.validator_key_lo


@external
def _set_validator_key(hi: bytes32, lo: bytes16):
    assert msg.sender == CONTROLLER
    self.validator_key_hi = hi
    self.validator_key_lo = lo


@external
@payable
def _request_withdrawal(amount: bytes8):
    assert msg.sender == CONTROLLER
    fee: uint256 = self._query_fee(WITHDRAWAL_REQUESTS)
    raw_call(
        WITHDRAWAL_REQUESTS, concat(self.validator_key_hi, self.validator_key_lo, amount), value=fee
    )


@external
@payable
def _request_consolidation(target_key_hi: bytes32, target_key_lo: bytes16):
    assert msg.sender == CONTROLLER
    fee: uint256 = self._query_fee(CONSOLIDATION_REQUESTS)
    raw_call(
        CONSOLIDATION_REQUESTS,
        concat(self.validator_key_hi, self.validator_key_lo, target_key_hi, target_key_lo),
        value=fee,
    )


@external
@payable
def _request_switch_to_compounding():
    assert msg.sender == CONTROLLER
    fee: uint256 = self._query_fee(CONSOLIDATION_REQUESTS)
    raw_call(
        CONSOLIDATION_REQUESTS,
        concat(
            self.validator_key_hi,
            self.validator_key_lo,
            self.validator_key_hi,
            self.validator_key_lo,
        ),
        value=fee,
    )


@external
def _pull_native_balance(target: address, data: Bytes[2**16]):
    assert msg.sender == CONTROLLER
    raw_call(target, data, value=self.balance)


@external
@payable
def _arbitrary_call(target: address, data: Bytes[2**16]):
    assert msg.sender == CONTROLLER
    raw_call(target, data, value=msg.value)


@external
@payable
def __default__():
    # accept transfers. This could be useful for MEV payments
    assert len(msg.data) == 0
