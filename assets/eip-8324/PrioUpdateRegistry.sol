// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {EIP712} from "solady/utils/EIP712.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

contract PrioUpdateRegistry is EIP712 {
    /// @notice Thrown when the caller or signer is not authorized to update state on behalf of `target`.
    error NotAuthorized();
    /// @notice Thrown when `slots` has length zero.
    error EmptySlots();
    /// @notice Thrown when `slots[0]` does not fit in 27 bytes (its top 5 bytes are non-zero).
    /// @dev The top 5 bytes of slot 0 are reserved for `updateTimestamp` (4 bytes) and slot count (1 byte).
    error Slot0Exceeds27Bytes();
    /// @notice Thrown when `slots` has more than 255 entries.
    /// @dev The slot count is packed into a single byte.
    error TooManySlots();
    /// @notice Thrown when `updateTimestamp` lies outside
    /// `[block.timestamp - MAX_UPDATE_AGE, block.timestamp + MAX_UPDATE_LEAD_TIME]`.
    error InvalidUpdateTimestamp();
    /// @notice Thrown on writes when `updateTimestamp` is older than the timestamp currently
    /// stored for the lane, or on reads when the stored timestamp lies outside the
    /// `[minTimestamp, maxTimestamp]` window the caller supplied to `getState`.
    error StaleUpdate();

    event UpdaterAdded(address indexed target, address indexed updater);
    event UpdaterRemoved(address indexed target, address indexed updater);

    /// @notice Tracks whether `updater` is authorized to write state on behalf of `target`.
    /// @dev Each target manages its own set of updaters via `addUpdater` / `removeUpdater`.
    mapping(address target => mapping(address updater => bool)) public isUpdater;

    /// @notice Maximum age (in seconds) by which `updateTimestamp` may lag `block.timestamp` on writes.
    /// @dev A write is accepted iff
    /// `block.timestamp - MAX_UPDATE_AGE <= updateTimestamp <= block.timestamp + MAX_UPDATE_LEAD_TIME`.
    /// Inclusive and fixed at construction time.
    // SCREAMING_SNAKE_CASE matches the convention for constant-like immutables; not mixedCase by design.
    // slither-disable-next-line naming-convention
    uint256 public immutable MAX_UPDATE_AGE;

    /// @notice Maximum lead time (in seconds) by which `updateTimestamp` may exceed `block.timestamp` on writes.
    /// @dev See `MAX_UPDATE_AGE` for the full accepted range. Inclusive and fixed at construction time.
    // slither-disable-next-line naming-convention
    uint256 public immutable MAX_UPDATE_LEAD_TIME;

    constructor(uint256 _maxUpdateAge, uint256 _maxUpdateLeadTime) {
        MAX_UPDATE_AGE = _maxUpdateAge;
        MAX_UPDATE_LEAD_TIME = _maxUpdateLeadTime;
    }

    /// @notice Authorizes `updater` to write state on behalf of `msg.sender`.
    /// @dev No-op if `updater` is already authorized for `msg.sender`.
    /// @param updater The address being granted write authorization.
    function addUpdater(address updater) external {
        if (isUpdater[msg.sender][updater]) return;
        isUpdater[msg.sender][updater] = true;
        emit UpdaterAdded(msg.sender, updater);
    }

    /// @notice Revokes authorization for `updater` to write state on behalf of `msg.sender`.
    /// @dev No-op if `updater` is not currently authorized for `msg.sender`.
    /// @param updater The address whose write authorization is being revoked.
    function removeUpdater(address updater) external {
        if (!isUpdater[msg.sender][updater]) return;
        isUpdater[msg.sender][updater] = false;
        emit UpdaterRemoved(msg.sender, updater);
    }

    /*
     * State
     */

    /// @notice Returns the stored state for `msg.sender` at the given `laneIndex`, enforcing
    /// that the stored `updateTimestamp` lies within `[minTimestamp, maxTimestamp]` (inclusive).
    /// @dev Reverts with `StaleUpdate` if the stored timestamp falls outside the supplied window.
    /// A lane that has never been written has a stored timestamp of `0`
    /// The number of slots returned matches the number that were written.
    /// @param laneIndex The lane to read state for, scoped to `msg.sender`.
    /// @param minTimestamp Minimum acceptable stored `updateTimestamp` (inclusive).
    /// @param maxTimestamp Maximum acceptable stored `updateTimestamp` (inclusive).
    /// @return updateTimestamp The timestamp the lane was last written for.
    /// @return slots The stored slot values for the lane.
    // Assembly is used to read the packed slot-0 layout (updateTimestamp | numSlots | slots[0])
    // and to bulk-load subsequent slots without per-iteration bounds checks.
    // slither-disable-next-line assembly
    function getState(uint256 laneIndex, uint32 minTimestamp, uint32 maxTimestamp)
        external
        view
        returns (uint32 updateTimestamp, uint256[] memory slots)
    {
        uint256 base = _laneSlot0Index(msg.sender, laneIndex);
        uint256 first;
        assembly {
            first := sload(base)
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        updateTimestamp = uint32(first >> 224);
        if (updateTimestamp < minTimestamp || updateTimestamp > maxTimestamp) revert StaleUpdate();
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 numSlots = uint8(first >> 216);
        slots = new uint256[](numSlots);
        if (numSlots == 0) return (updateTimestamp, slots);
        // forge-lint: disable-next-line(unsafe-typecast)
        slots[0] = uint216(first);
        for (uint256 i = 1; i < numSlots; i++) {
            assembly {
                mstore(add(add(slots, 32), mul(i, 32)), sload(add(base, i)))
            }
        }
    }

    function _laneSlot0Index(address target, uint256 laneIndex) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(target, laneIndex)));
    }

    /// @notice Validates and writes a state update for `target` at `laneIndex`.
    /// @dev Does not perform authorization checks; callers must ensure the writer is authorized.
    /// Reverts with `EmptySlots`, `TooManySlots`, or `Slot0Exceeds27Bytes` if `slots` is malformed.
    /// Reverts with `InvalidUpdateTimestamp` if `updateTimestamp` is outside
    /// `[block.timestamp - MAX_UPDATE_AGE, block.timestamp + MAX_UPDATE_LEAD_TIME]`.
    /// Reverts with `StaleUpdate` if `updateTimestamp` is older than the timestamp currently stored.
    /// Slot 0 packs `updateTimestamp` (top 4 bytes), `slots.length` (next byte), and `slots[0]` (low 27 bytes);
    /// subsequent slots are written verbatim from calldata.
    /// @param target The address whose state is being updated.
    /// @param laneIndex The lane to write, scoped to `target`.
    /// @param updateTimestamp The timestamp associated with this update.
    /// @param slots The slot values to write. Length must be in `[1, 255]` and `slots[0]`
    /// must fit in 27 bytes.
    // Assembly is used to load/store the packed slot-0 layout and to bulk-write the remaining
    // slots directly from calldata without per-iteration bounds checks.
    // slither-disable-next-line assembly
    function _writeState(address target, uint256 laneIndex, uint32 updateTimestamp, uint256[] calldata slots) internal {
        if (slots.length == 0) revert EmptySlots();
        if (slots.length > 255) revert TooManySlots();
        if (slots[0] >> 216 != 0) revert Slot0Exceeds27Bytes();

        uint256 ts = updateTimestamp;
        // Comparing a user-supplied timestamp against `block.timestamp` within a configurable
        // window is the intended freshness check, not a vulnerability to miner manipulation.
        // slither-disable-next-line timestamp
        if (ts + MAX_UPDATE_AGE < block.timestamp) revert InvalidUpdateTimestamp();
        // slither-disable-next-line timestamp
        if (ts > block.timestamp + MAX_UPDATE_LEAD_TIME) revert InvalidUpdateTimestamp();

        uint256 base = _laneSlot0Index(target, laneIndex);
        uint256 storedFirst;
        assembly {
            storedFirst := sload(base)
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        if (uint32(storedFirst >> 224) > updateTimestamp) revert StaleUpdate();

        uint256 first = (uint256(updateTimestamp) << 224) | (slots.length << 216) | slots[0];
        assembly {
            sstore(base, first)
        }
        for (uint256 i = 1; i < slots.length; i++) {
            assembly {
                sstore(add(base, i), calldataload(add(slots.offset, mul(i, 32))))
            }
        }
    }

    /// @notice Writes a state update for `target` at `laneIndex`, with `msg.sender` acting as the updater.
    /// @dev Reverts with `NotAuthorized` if `msg.sender` is not an authorized updater for `target`.
    /// Reverts with `EmptySlots`, `TooManySlots`, `Slot0Exceeds27Bytes`, or `InvalidUpdateTimestamp`
    /// if the input fails validation. Reverts with `StaleUpdate` if `updateTimestamp` is older
    /// than the timestamp currently stored for this lane.
    /// @param target The address whose state is being updated.
    /// @param laneIndex The lane to write, scoped to `target`.
    /// @param updateTimestamp The timestamp associated with this update; must lie within
    /// `[block.timestamp - MAX_UPDATE_AGE, block.timestamp + MAX_UPDATE_LEAD_TIME]`.
    /// @param slots The slot values to write. Length must be in `[1, 255]` and `slots[0]`
    /// must fit in 27 bytes (its top 5 bytes must be zero).
    function updateState(address target, uint256 laneIndex, uint32 updateTimestamp, uint256[] calldata slots) external {
        if (!isUpdater[target][msg.sender]) revert NotAuthorized();
        _writeState(target, laneIndex, updateTimestamp, slots);
    }

    /*
     * Signed Update
     */

    /// @notice EIP-712 type hash for a `SignedUpdate` message.
    /// @dev Used as the first field of the EIP-712 struct hash for signed updates.
    bytes32 public constant UPDATE_TYPEHASH =
        keccak256("UpdateState(address target,uint256 laneIndex,uint32 updateTimestamp,uint256[] slots)");

    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "PrioUpdateRegistry";
        version = "1";
    }

    /// @notice Returns the EIP-712 domain separator used for signed updates.
    /// @return The current EIP-712 domain separator for this contract.
    // Name follows the EIP-2612 / ERC-20 Permit ecosystem convention; not mixedCase by design.
    // slither-disable-next-line naming-convention
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparator();
    }

    /// @notice A signed state update relayed via `batchUpdateStateWithSignature`.
    /// @dev `signer` is NOT part of the EIP-712 hash: it is supplied alongside the signature so
    /// the contract knows which address's authorization to check and, for non-`target` signers,
    /// which address to compare against the ECDSA-recovered key. If `signer == target`, the
    /// signature is verified against `target` via ERC-1271; otherwise it must ECDSA-recover to
    /// `signer`, and `signer` must be an authorized updater for `target`.
    /// @param target The address whose state is being updated.
    /// @param signer The address whose signature authorizes this update. Not part of the signed payload.
    /// @param laneIndex The lane to write, scoped to `target`.
    /// @param updateTimestamp The timestamp associated with this update.
    /// @param slots The slot values to write.
    /// @param signature The EIP-712 signature over `(target, laneIndex, updateTimestamp, slots)`.
    struct SignedUpdate {
        address target;
        address signer;
        uint256 laneIndex;
        uint32 updateTimestamp;
        uint256[] slots;
        bytes signature;
    }

    /// @notice Applies a batch of signed state updates.
    /// @dev Anyone may relay the batch. Each update is validated independently and the whole
    /// call reverts on the first invalid signature or invalid input. If `signer == target`,
    /// the signature is verified via ERC-1271 against `target`; otherwise, `signer` must be
    /// an authorized updater for `target` and the ECDSA-recovered address of the signature.
    ///
    /// Replay note: signatures are not single-use. A valid `SignedUpdate` can be re-relayed
    /// by any address as long as (a) the lane's stored timestamp is `<= u.updateTimestamp`
    /// and (b) `u.updateTimestamp` still lies within the `MAX_UPDATE_AGE` / `MAX_UPDATE_LEAD_TIME`
    /// window. A replay always produces the same on-chain state as the original write, so it
    /// cannot corrupt state, but it can be used to consume gas / write quota attributable to
    /// the signer. Revoking `signer` via `removeUpdater` immediately invalidates further
    /// replays (non-`target` signers only).
    /// @param updates The signed updates to apply, in order.
    function batchUpdateStateWithSignature(SignedUpdate[] calldata updates) external {
        for (uint256 i = 0; i < updates.length; i++) {
            SignedUpdate calldata u = updates[i];
            bytes32 structHash = keccak256(
                abi.encode(
                    UPDATE_TYPEHASH, u.target, u.laneIndex, u.updateTimestamp, keccak256(abi.encodePacked(u.slots))
                )
            );
            bytes32 digest = _hashTypedData(structHash);
            if (u.signer == u.target) {
                if (!SignatureCheckerLib.isValidERC1271SignatureNowCalldata(u.target, digest, u.signature)) {
                    revert NotAuthorized();
                }
            } else {
                if (!isUpdater[u.target][u.signer]) revert NotAuthorized();
                if (ECDSA.recoverCalldata(digest, u.signature) != u.signer) revert NotAuthorized();
            }
            _writeState(u.target, u.laneIndex, u.updateTimestamp, u.slots);
        }
    }
}
