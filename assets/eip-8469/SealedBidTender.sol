// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./ISealedBidTender.sol";
import "./IAwardMechanism.sol";

interface IERC20Minimal {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

interface IERC165Minimal {
    function supportsInterface(bytes4 id) external view returns (bool);
}

/// @title SealedBidTender
/// @notice Reference implementation of ISealedBidTender. Dependency-free.
/// @dev The contract never acts on the target: it produces an award, and the target standard
///      decides what to do with it.
///      - Bidders per tender are capped (`maxBidders`, at most MAX_BIDDERS) so `finalize` always
///        fits in a block: it sorts revealed bids and loops over committers.
///      - Slashed bonds are credited at `finalize` and paid out by `claimSlashed`, so a
///        `slashRecipient` that rejects payment cannot block the award.
///      - ERC-20 bonds are moved with calls that accept tokens returning no value (USDT-style).
///      Fee-on-transfer and rebasing bond assets are rejected (see Security Considerations).
contract SealedBidTender is ISealedBidTender {
    struct Commitment {
        bytes32 hash;
        bool revealed;
        uint256 amount; // set on reveal
    }

    struct Tender {
        TenderTerms terms;
        address requester;
        Phase phase;
        address[] committers; // commit order
        mapping(address => Commitment) commitments;
        uint256 revealCount;
        IAwardMechanism.Award[] awards;
        uint256 slashed; // credited at finalize, paid by claimSlashed
        bytes32 mechanismCodehash; // pinned at open, re-checked at finalize
    }

    /// @notice Upper bound on `maxBidders`. At 256 revealed bids `finalize` costs about 8M gas.
    uint256 public constant MAX_BIDDERS = 256;

    mapping(bytes32 => Tender) private _tenders;
    mapping(address => uint256) public nonceOf;

    uint256 private _lock = 1;

    modifier nonReentrant() {
        require(_lock == 1, "reentrant");
        _lock = 2;
        _;
        _lock = 1;
    }

    modifier exists(bytes32 tenderId) {
        require(_tenders[tenderId].phase != Phase.None, "no such tender");
        _;
    }

    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == type(ISealedBidTender).interfaceId || id == 0x01ffc9a7;
    }

    /// @notice Canonical target commitment per the ERC. `targetId` is the target's
    ///         identifier normalised to bytes32 (uint256 ids are left-padded).
    function targetRefOf(uint256 chainId, address targetContract, bytes32 targetId) external pure returns (bytes32) {
        return keccak256(abi.encode(chainId, targetContract, targetId));
    }

    // ─── Lifecycle ────────────────────────────────────────────────────────────

    function openTender(TenderTerms calldata terms) external returns (bytes32 tenderId) {
        require(terms.reserve > 0, "reserve must be > 0");
        require(terms.units >= 1, "units must be >= 1");
        require(terms.commitDeadline > block.timestamp, "commit deadline passed");
        require(terms.revealDeadline > terms.commitDeadline, "reveal must follow commit");
        require(
            IERC165Minimal(terms.mechanism).supportsInterface(type(IAwardMechanism).interfaceId),
            "not an award mechanism"
        );
        require(terms.maxBidders >= 1 && terms.maxBidders <= MAX_BIDDERS, "maxBidders out of range");
        if (terms.integrationProfile == AwardProfiles.ALLOCATION_ONLY) {
            // With the payment fixed by the target, only a posted price is incentive compatible.
            require(
                IAwardMechanism(terms.mechanism).mechanismId() == AwardProfiles.POSTED_PRICE,
                "allocation-only requires award.posted-price"
            );
        } else {
            require(terms.integrationProfile == AwardProfiles.PRICE_BINDING, "unknown integration profile");
        }
        if (terms.bond > 0) {
            require(terms.slashRecipient != address(0), "slash recipient required");
            require(terms.slashRecipient != msg.sender, "requester cannot receive slashes");
        }
        if (terms.bondAsset != address(0)) {
            require(terms.bondAsset.code.length > 0, "bond asset is not a contract");
        }

        tenderId = keccak256(abi.encode(block.chainid, address(this), msg.sender, nonceOf[msg.sender]++));
        Tender storage t = _tenders[tenderId];
        t.terms = terms;
        t.requester = msg.sender;
        t.phase = Phase.Commit;
        t.mechanismCodehash = terms.mechanism.codehash;

        emit TenderOpened(
            tenderId,
            terms.targetRef,
            msg.sender,
            terms.mechanism,
            terms.reserve,
            terms.units,
            terms.commitDeadline,
            terms.revealDeadline,
            terms.integrationProfile,
            t.mechanismCodehash
        );
    }

    /// @dev Public/virtual permits an optional admission extension to check its resource
    ///      reservation before calling super. The standard ABI and default behavior are unchanged.
    function commitBid(bytes32 tenderId, bytes32 commitment) public payable virtual exists(tenderId) nonReentrant {
        Tender storage t = _tenders[tenderId];
        require(t.phase == Phase.Commit, "not in commit phase");
        require(block.timestamp <= t.terms.commitDeadline, "commit window closed");
        require(t.commitments[msg.sender].hash == bytes32(0), "already committed");
        require(commitment != bytes32(0), "empty commitment");
        require(t.committers.length < t.terms.maxBidders, "tender full");

        _takeBond(t.terms, msg.sender);

        t.commitments[msg.sender] = Commitment({hash: commitment, revealed: false, amount: 0});
        t.committers.push(msg.sender);
        emit BidCommitted(tenderId, msg.sender, commitment);
    }

    function revealBid(bytes32 tenderId, uint256 amount, bytes32 salt) external exists(tenderId) nonReentrant {
        Tender storage t = _tenders[tenderId];
        require(t.phase == Phase.Commit || t.phase == Phase.Reveal, "not open for reveal");
        require(block.timestamp > t.terms.commitDeadline, "commit window still open");
        require(block.timestamp <= t.terms.revealDeadline, "reveal window closed");

        Commitment storage c = t.commitments[msg.sender];
        require(c.hash != bytes32(0), "no commitment");
        require(!c.revealed, "already revealed");
        require(keccak256(abi.encode(tenderId, msg.sender, amount, salt)) == c.hash, "commitment mismatch");

        c.revealed = true;
        c.amount = amount;
        t.revealCount++;
        if (t.phase == Phase.Commit) t.phase = Phase.Reveal;
        emit BidRevealed(tenderId, msg.sender, amount);

        _payBond(t.terms, msg.sender);
    }

    function finalize(bytes32 tenderId)
        external
        exists(tenderId)
        nonReentrant
        returns (IAwardMechanism.Award[] memory result)
    {
        Tender storage t = _tenders[tenderId];
        require(t.phase == Phase.Commit || t.phase == Phase.Reveal, "already finalized");
        require(block.timestamp > t.terms.revealDeadline, "reveal window still open");

        // Bids reach the mechanism in commit order, not reveal order: the tie rule (and the
        // posted-price rule) must not depend on who managed to reveal first.
        require(t.terms.mechanism.codehash == t.mechanismCodehash, "mechanism code changed");
        result = IAwardMechanism(t.terms.mechanism).award(_bidsInCommitOrder(t), t.terms.reserve, t.terms.units);
        _checkAward(result, t);

        if (result.length == 0) {
            t.phase = Phase.Void;
            emit TenderVoid(tenderId);
        } else {
            bytes4 id = IAwardMechanism(t.terms.mechanism).mechanismId();
            for (uint256 i = 0; i < result.length; i++) {
                t.awards.push(result[i]);
                emit TenderAwarded(tenderId, result[i].winner, result[i].price, id);
            }
            t.phase = Phase.Awarded;
        }

        // Slash everyone who committed but did not reveal.
        uint256 slashed;
        for (uint256 i = 0; i < t.committers.length; i++) {
            address who = t.committers[i];
            if (!t.commitments[who].revealed) {
                slashed += t.terms.bond;
                emit BidSlashed(tenderId, who, t.terms.bond);
            }
        }
        t.slashed += slashed;
    }

    function claimSlashed(bytes32 tenderId) external exists(tenderId) nonReentrant returns (uint256 amount) {
        Tender storage t = _tenders[tenderId];
        amount = t.slashed;
        require(amount > 0, "nothing to claim");
        t.slashed = 0;
        _payBondAmount(t.terms, t.terms.slashRecipient, amount);
        emit SlashClaimed(tenderId, t.terms.slashRecipient, amount);
    }

    // ─── Views ────────────────────────────────────────────────────────────────

    function termsOf(bytes32 tenderId) external view exists(tenderId) returns (TenderTerms memory) {
        return _tenders[tenderId].terms;
    }

    function requesterOf(bytes32 tenderId) external view exists(tenderId) returns (address) {
        return _tenders[tenderId].requester;
    }

    function phaseOf(bytes32 tenderId) external view exists(tenderId) returns (Phase) {
        return _tenders[tenderId].phase;
    }

    function awardOf(bytes32 tenderId) external view exists(tenderId) returns (IAwardMechanism.Award[] memory) {
        Tender storage t = _tenders[tenderId];
        if (t.phase != Phase.Awarded) return new IAwardMechanism.Award[](0);
        return t.awards;
    }

    function mechanismCodehashOf(bytes32 tenderId) external view exists(tenderId) returns (bytes32) {
        return _tenders[tenderId].mechanismCodehash;
    }

    function slashedOf(bytes32 tenderId) external view exists(tenderId) returns (uint256) {
        return _tenders[tenderId].slashed;
    }

    /// @notice Revealed bids in commit order, as passed to the mechanism.
    function revealedBids(bytes32 tenderId) external view exists(tenderId) returns (IAwardMechanism.Bid[] memory) {
        return _bidsInCommitOrder(_tenders[tenderId]);
    }

    // ─── Internals ────────────────────────────────────────────────────────────

    function _bidsInCommitOrder(Tender storage t) private view returns (IAwardMechanism.Bid[] memory bids) {
        bids = new IAwardMechanism.Bid[](t.revealCount);
        uint256 k;
        for (uint256 i = 0; i < t.committers.length; i++) {
            address who = t.committers[i];
            Commitment storage c = t.commitments[who];
            if (c.revealed) bids[k++] = IAwardMechanism.Bid({bidder: who, amount: c.amount});
        }
    }

    /// @dev Defensive re-check of the mechanism's output against the conditions the
    ///      ERC places on `award`. A mechanism that violates them cannot be trusted,
    ///      and a bad award must not reach the escrow.
    ///      Every check here is independent of the pricing rule: each winner must be a bidder
    ///      who revealed, with a bid within the reserve, paid at least its own bid and at most
    ///      the reserve. (The first two were missing until Revinand pointed it out on the
    ///      Ethereum Magicians thread, post #15.)
    function _checkAward(IAwardMechanism.Award[] memory a, Tender storage t) private view {
        TenderTerms storage terms = t.terms;
        require(a.length <= terms.units, "too many awards");
        for (uint256 i = 0; i < a.length; i++) {
            require(a[i].price <= terms.reserve, "price above reserve");
            require(a[i].winner != address(0), "zero winner");
            Commitment storage c = t.commitments[a[i].winner];
            require(c.revealed, "winner did not reveal");
            require(c.amount <= terms.reserve, "winner bid above reserve");
            require(a[i].price >= c.amount, "price below winner's bid");
            for (uint256 j = 0; j < i; j++) {
                require(a[j].winner != a[i].winner, "duplicate winner");
            }
        }
    }

    function _takeBond(TenderTerms storage terms, address from) private {
        if (terms.bond == 0) {
            require(msg.value == 0, "no bond expected");
            return;
        }
        if (terms.bondAsset == address(0)) {
            require(msg.value == terms.bond, "wrong bond value");
        } else {
            require(msg.value == 0, "native value not accepted");
            IERC20Minimal token = IERC20Minimal(terms.bondAsset);
            uint256 before = token.balanceOf(address(this));
            _erc20Call(terms.bondAsset, abi.encodeCall(IERC20Minimal.transferFrom, (from, address(this), terms.bond)));
            require(token.balanceOf(address(this)) - before == terms.bond, "bond asset not supported");
        }
    }

    function _payBond(TenderTerms storage terms, address to) private {
        if (terms.bond == 0) return;
        _payBondAmount(terms, to, terms.bond);
    }

    function _payBondAmount(TenderTerms storage terms, address to, uint256 amount) private {
        if (terms.bondAsset == address(0)) {
            (bool ok,) = to.call{value: amount}("");
            require(ok, "bond return failed");
        } else {
            _erc20Call(terms.bondAsset, abi.encodeCall(IERC20Minimal.transfer, (to, amount)));
        }
    }

    /// @dev Calls an ERC-20 and accepts either no return data or `true`, so tokens that do not
    ///      return a value (USDT and others) work. Reverts on failure or on `false`.
    function _erc20Call(address token, bytes memory data) private {
        (bool ok, bytes memory ret) = token.call(data);
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "bond transfer failed");
    }
}
