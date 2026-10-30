"""
@title ERC-8270: Canonical Validator Wrapper
@license CC0
@author bbjubjub.eth
"""

# pragma version ==0.4.3
# pragma evm-version prague
# pragma nonreentrancy on

from . import IWithdrawalReceiver

from ethereum.ercs import IERC721

from . import format_helpers as fmt


interface ERC721Receiver:
    def onERC721Received(
        sender: address, owner: address, token_id: uint256, data: Bytes[2**16]
    ) -> bytes4: nonpayable


implements: IERC721


event ConsolidationRequest:
    token_id: indexed(uint256)
    target_key_hi: bytes32
    target_key_lo: bytes16


event ArbitraryCall:
    token_id: indexed(uint256)
    target: address
    data: Bytes[2**16]


event PullNativeBalance:
    token_id: indexed(uint256)
    target: address
    data: Bytes[2**16]


# this is just to silence a warning since we will never mint this many.
MAX_ID: constant(uint256) = 2**64 - 1

# we store all the data associated with a token in an array of structs
# to increase locality and reduce hashing
# preemptive optimisation for state warming update and hash gas cost increases.
struct TokenData:
    index_and_owner: uint256
    approved: address
    withdrawal_address: address
    state_fingerprint: bytes32


next_id: uint256
image_url: String[128]  # 5 slots
tokens_by_owner: HashMap[address, DynArray[uint256, MAX_ID]]
approval_for_all: HashMap[address, HashMap[address, bool]]

# this puts the unused 0th element at 0xfc and the first NFT at 0x100
_padding: bytes32[244]
token_data: TokenData[MAX_ID]

WITHDRAWAL_RECEIVER_IMPL: immutable(address)


@pure
def _pack(index_by_owner: uint96, owner: address) -> uint256:
    return convert(index_by_owner, uint256) << 160 | convert(owner, uint256)


@pure
def _unpack(index_and_owner: uint256) -> (uint96, address):
    index_by_owner: uint96 = convert(index_and_owner >> 160, uint96)
    mask: uint256 = convert(max_value(uint160), uint256)
    owner: address = convert(index_and_owner & mask, address)
    return index_by_owner, owner


@deploy
def __init__(image_url: String[128], withdrawal_receiver_code: Bytes[49152]):
    """
    @dev we make this contract deploy the withdrawal receiver because both contracts need to know each other's addresses
    """
    WITHDRAWAL_RECEIVER_IMPL = raw_create(withdrawal_receiver_code)
    self.next_id = 1
    self.image_url = image_url


### ERC-165 ###

SUPPORTED_INTERFACES: constant(bytes4[5]) = [
    0x01ffc9a7,  # ERC-165
    0x80ac58cd,  # ERC-721
    0x780e9d63,  # ERC-721 enumeration
    0x5b5e139f,  # ERC-721 metadata
    0xf5112315,  # ERC-5646
]


@external
@view
def supportsInterface(interface_id: bytes4) -> bool:
    return interface_id in SUPPORTED_INTERFACES


### ERC-721 Metadata ###


@external
@pure
def name() -> String[29]:
    return "ERC-8270 Wrapped Beacon Stake"


@external
@pure
def symbol() -> String[7]:
    return "ERC8270"


@external
@view
def tokenURI(token_id: uint256) -> String[2**16]:
    """
    ERC-721 JSON metadata. The validator key and the withdrawal address are included as attributes.
    """
    receiver: IWithdrawalReceiver = self.withdrawal_receiver(token_id)
    key_hi: bytes32 = empty(bytes32)
    key_lo: bytes16 = empty(bytes16)
    key_hi, key_lo = staticcall receiver.validator_key()
    return concat(
        """data:application/json,{
    "name": "ERC-8270 Token #"""
        ,
        uint2str(token_id),
        '",',
        """
    "description": "Transferable Beacon Chain Withdrawal Credentials",
    "image":"""
        ,
        '"',
        self.image_url,
        '",',
        """ "attributes": [{
    "trait_type": "Validator Key",
    "value": "0x"""
        ,
        fmt.bytes32_to_hex(key_hi),
        fmt.bytes16_to_hex(key_lo),
        '"',
        """
    }, {
        "trait_type": "Withdrawal Address",
        "value": "0x"""
        ,
        fmt.address_to_hex_erc55(self.token_data[token_id].withdrawal_address),
        '"}]}',
    )


## ERC-721 ##

@view
def _owner(token_id: uint256) -> address:
    owner: address = self._unpack(self.token_data[token_id].index_and_owner)[1]
    assert owner != empty(address), "ERC-721: token does not exist"
    return owner


@view
def check_exists(token_id: uint256):
    assert self.token_data[token_id].index_and_owner != 0, "ERC-721: token does not exist"


@view
def check_allowed(token_id: uint256, owner: address):
    if msg.sender != owner and msg.sender != self.token_data[token_id].approved:
        assert self.approval_for_all[owner][msg.sender], "ERC-721: not owner or approved"


@view
def check_operator(owner: address):
    if msg.sender != owner:
        assert self.approval_for_all[owner][msg.sender], "ERC-721: not owner or operator"


@external
@view
def balanceOf(owner: address) -> uint256:
    return len(self.tokens_by_owner[owner])


@external
@view
def ownerOf(token_id: uint256) -> address:
    return self._owner(token_id)


@external
@view
def getApproved(token_id: uint256) -> address:
    self.check_exists(token_id)
    return self.token_data[token_id].approved


@external
@view
def isApprovedForAll(owner: address, operator: address) -> bool:
    return self.approval_for_all[owner][operator]


@external
@payable
def approve(approved: address, token_id: uint256):
    assert msg.value == 0, "ERC-721: unexpected value"
    owner: address = self._owner(token_id)
    self.check_operator(owner)
    self.token_data[token_id].approved = approved
    log IERC721.Approval(owner=owner, approved=approved, token_id=token_id)


@external
def setApprovalForAll(operator: address, approved: bool):
    assert operator != msg.sender, "ERC-721: approve to caller"
    self.approval_for_all[msg.sender][operator] = approved
    log IERC721.ApprovalForAll(owner=msg.sender, operator=operator, approved=approved)


def _transfer(expected_owner: address, receiver: address, token_id: uint256):
    index: uint96 = 0
    owner: address = empty(address)
    index, owner = self._unpack(self.token_data[token_id].index_and_owner)
    assert owner == expected_owner, "ERC-721: wrong owner"
    self.check_allowed(token_id, owner)
    assert receiver != empty(address), "ERC-721: transfer to zero"

    last_id: uint256 = self.tokens_by_owner[owner][len(self.tokens_by_owner[owner]) - 1]
    self.tokens_by_owner[owner][index] = last_id
    self.tokens_by_owner[owner].pop()
    self.token_data[last_id].index_and_owner = self._pack(index, owner)

    index = convert(len(self.tokens_by_owner[receiver]), uint96)
    self.tokens_by_owner[receiver].append(token_id)
    self.token_data[token_id].index_and_owner = self._pack(index, receiver)
    self.token_data[token_id].approved = empty(address)
    log IERC721.Transfer(sender=owner, receiver=receiver, token_id=token_id)


# caller must ensure the token_id is fresh
def _mint(receiver: address, token_id: uint256):
    assert receiver != empty(address), "ERC-721: mint to zero"
    index: uint96 = convert(len(self.tokens_by_owner[receiver]), uint96)
    self.tokens_by_owner[receiver].append(token_id)
    self.token_data[token_id].index_and_owner = self._pack(index, receiver)
    self.token_data[token_id].approved = empty(address)
    log IERC721.Transfer(sender=empty(address), receiver=receiver, token_id=token_id)


@external
@payable
def transferFrom(owner: address, receiver: address, token_id: uint256):
    assert msg.value == 0, "ERC-721: unexpected value"
    self._transfer(owner, receiver, token_id)


@external
@payable
def safeTransferFrom(
    owner: address,
    receiver: address,
    token_id: uint256,
    data: Bytes[2**16] = b"",
):
    assert msg.value == 0, "ERC-721: unexpected value"
    self._transfer(owner, receiver, token_id)

    if receiver.is_contract:
        assert (
            extcall ERC721Receiver(receiver).onERC721Received(msg.sender, owner, token_id, data)
            == 0x150b7a02
        ), "ERC-721: receiver rejected transfer"


## ERC-721 Enumerable ##

@external
@view
def totalSupply() -> uint256:
    return self.next_id - 1


@external
@view
def tokenByIndex(index: uint256) -> uint256:
    assert index < self.next_id - 1, "ERC-721: invalid index"
    return index + 1


@external
@view
def tokenOfOwnerByIndex(owner: address, index: uint256) -> uint256:
    assert index < len(self.tokens_by_owner[owner]), "ERC-721: invalid index"
    return self.tokens_by_owner[owner][index]


## ERC-5646 ##

@external
@view
def getStateFingerprint(token_id: uint256) -> bytes32:
    """
    @notice ERC-5646 state fingerprint. It changes when `requestConsolidation()`, `pullNativeBalance()`, and `arbitraryCall()` are used on the token.
    @dev the fingerprint is an EIP-712 hash which includes the previous hash. The following signatures are used:
        - `Minted()`
        - `ConsolidationRequested(bytes32 previousFingerprint,bytes32 targetKeyHi,bytes16 targetKeyLo)`
        - `NativeBalancePulled(bytes32 previousFingerprint,address target,bytes data)`
        - `ArbitraryCall(bytes32 previousFingerprint,address target,bytes data)`
    """
    state_fingerprint: bytes32 = self.token_data[token_id].state_fingerprint
    assert state_fingerprint != empty(bytes32), "ERC-721: token does not exist"
    return state_fingerprint


## ERC-8270 ##

@view
def withdrawal_receiver(token_id: uint256) -> IWithdrawalReceiver:
    withdrawal_address: address = self.token_data[token_id].withdrawal_address
    assert withdrawal_address != empty(address), "ERC-721: token does not exist"
    return IWithdrawalReceiver(withdrawal_address)


@external
def mint(
    validator_key_hi: bytes32,
    validator_key_lo: bytes16,
    initial_owner: address = msg.sender,
) -> uint256:
    """
    @notice Create a token intended to wrap the given validator.
    @dev The withdrawal address of the token depends only on the parameters of this function, hence it can be determined counterfactually.
    This function cannot guarantee that the validator will set its withdrawal credentials to the withdrawal address associated with this token.
    @param validator_key_hi The 256 most significant bits of the validator BLS12-381 public key.
    @param validator_key_lo The 128 least significant bits of the validator BLS12-381 public key.
    @param initial_owner The address that should receive the ERC-721 token upon mint.
    @return token_id The ERC-721 id of the new token.
    """
    withdrawal_address: address = create_minimal_proxy_to(
        WITHDRAWAL_RECEIVER_IMPL,
        revert_on_failure=False,
        salt=keccak256(abi_encode(validator_key_hi, validator_key_lo, initial_owner)),
    )
    assert withdrawal_address != empty(address), "ERC-8270: already minted"

    token_id: uint256 = self.next_id
    self.next_id = token_id + 1
    self._mint(initial_owner, token_id)
    self.token_data[token_id].withdrawal_address = withdrawal_address
    self.token_data[token_id].state_fingerprint = keccak256(keccak256("Minted()"))
    extcall IWithdrawalReceiver(withdrawal_address)._set_validator_key(
        validator_key_hi, validator_key_lo
    )
    return token_id


@external
@view
def validatorKeyOf(token_id: uint256) -> (bytes32, bytes16):
    """
    @return The 256 most significant bits of the validator BLS12-381 public key.
    @return The 128 least significant bits of the validator BLS12-381 public key.
    """
    return staticcall self.withdrawal_receiver(token_id).validator_key()


@external
@view
def withdrawalAddressOf(token_id: uint256) -> address:
    """
    @return The address that the validator should use as its withdrawal credential.
    """
    withdrawal_address: address = self.token_data[token_id].withdrawal_address
    assert withdrawal_address != empty(address), "ERC-721: token does not exist"
    return withdrawal_address


@external
@payable
def requestPartialWithdrawal(token_id: uint256, amount: uint64):
    """
    @notice Request an EIP-7002 partial withdrawal of the validator controlled by this token.
    @dev The fee will be paid using the withdrawal address balance. If necessary, the caller can add value to this function to cover it,
    @param token_id The ERC-721 id of the token.
    @param amount the amount to withdraw, in consensus layer units.
    """
    self.check_allowed(token_id, self._owner(token_id))
    assert amount != 0, "ERC-8270: zero partial withdrawal amount"
    extcall self.withdrawal_receiver(token_id)._request_withdrawal(
        convert(amount, bytes8),
        value=msg.value,
    )


@external
@payable
def requestFullWithdrawal(token_id: uint256):
    """
    @notice Request an EIP-7002 full withdrawal and exit of the validator controlled by this token.
    @dev The fee will be paid using the withdrawal address balance. If necessary, the caller can add value to this function to cover it,
    @param token_id The ERC-721 id of the token.
    """
    self.check_allowed(token_id, self._owner(token_id))
    extcall self.withdrawal_receiver(token_id)._request_withdrawal(
        empty(bytes8),
        value=msg.value,
    )


@external
@payable
def requestConsolidation(token_id: uint256, target_key_hi: bytes32, target_key_lo: bytes16):
    """
    @notice Request an EIP-7251 consolidation of the validator controlled by this token.
    @dev The fee will be paid using the withdrawal address balance. If necessary, the caller can add value to this function to cover it,
    @param token_id The ERC-721 id of the token.
    @param target_key_hi The 256 most significant bits of the BLS12-381 public key of the validator to consolidate into.
    @param target_key_lo The 128 least significant bits of the BLS12-381 public key of the validator to consolidate into.
    """
    self.check_allowed(token_id, self._owner(token_id))
    self.token_data[token_id].state_fingerprint = keccak256(
        abi_encode(
            keccak256(
                "ConsolidationRequested(bytes32 previousFingerprint,bytes32 targetKeyHi,bytes16 targetKeyLo)"
            ),
            self.token_data[token_id].state_fingerprint,
            target_key_hi,
            target_key_lo,
        )
    )
    extcall self.withdrawal_receiver(token_id)._request_consolidation(
        target_key_hi,
        target_key_lo,
        value=msg.value,
    )
    log ConsolidationRequest(
        token_id=token_id, target_key_hi=target_key_hi, target_key_lo=target_key_lo
    )


@external
@payable
def requestSwitchToCompounding(token_id: uint256):
    """
    @notice Use an EIP-7251 consolidation request to turn the validator into a compounding validator.
    @dev The fee will be paid using the withdrawal address balance. If necessary, the caller can add value to this function to cover it,
    @param token_id The ERC-721 id of the token.
    """
    self.check_allowed(token_id, self._owner(token_id))
    extcall self.withdrawal_receiver(token_id)._request_switch_to_compounding(value=msg.value)


@external
def pullNativeBalance(token_id: uint256, target: address = msg.sender, data: Bytes[2**16] = b""):
    """
    @notice Transfer the native balance of the withdrawal address.
    @param token_id The ERC-721 id of the token.
    @param target Address to receive the native balance.
    @param data calldata to pass along with the balance.
    """
    # check, effect, interaction
    self.check_allowed(token_id, self._owner(token_id))
    assert target != empty(address), "ERC-8270: pull native balance to zero"
    self.token_data[token_id].state_fingerprint = keccak256(
        abi_encode(
            keccak256("NativeBalancePulled(bytes32 previousFingerprint,address target,bytes data)"),
            self.token_data[token_id].state_fingerprint,
            target,
            keccak256(data),
        )
    )
    extcall self.withdrawal_receiver(token_id)._pull_native_balance(target, data)
    log PullNativeBalance(token_id=token_id, target=target, data=data)


@external
@payable
def arbitraryCall(token_id: uint256, target: address, data: Bytes[2**16]):
    """
    @notice Call a function from the withdrawal address.
    @dev value from this function will be forwarded to the arbitrary call.
    @param token_id The ERC-721 id of the token.
    @param target Address of the contract to call.
    @param data Calldata to use.
    """
    # check, effect, interaction
    self.check_allowed(token_id, self._owner(token_id))
    self.token_data[token_id].state_fingerprint = keccak256(
        abi_encode(
            keccak256("ArbitraryCall(bytes32 previousFingerprint,address target,bytes data)"),
            self.token_data[token_id].state_fingerprint,
            target,
            keccak256(data),
        )
    )
    extcall self.withdrawal_receiver(token_id)._arbitrary_call(target, data, value=msg.value)
    log ArbitraryCall(token_id=token_id, target=target, data=data)
