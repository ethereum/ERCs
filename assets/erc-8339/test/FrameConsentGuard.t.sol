// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FrameConsentGuard } from "../contracts/FrameConsentGuard.sol";
import { IFrameConsentGuard } from "../contracts/IFrameConsentGuard.sol";
import { MockFrameIntrospector } from "../contracts/MockFrameIntrospector.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/// @dev Frame layout under test (EIP-8141):
///        0  VERIFY   flags 0x3  target = sender      (sender's own auth)
///        1  DEFAULT  flags 0x4  target = guard       (guard.check, ATOMIC_BATCH)
///        2  SENDER   flags 0x0  target = token / R   (the transfer)
///      The mock reports these frames; tests call guard.check as frame 1 would.
contract FrameConsentGuardTest is Test {
    uint256 internal constant VERIFY = 1;
    uint256 internal constant DEFAULT = 0;
    uint256 internal constant SENDER = 2;
    uint256 internal constant ATOMIC = 0x4;

    FrameConsentGuard internal guard;
    MockFrameIntrospector internal frames;

    address internal alice = makeAddr("alice"); // sender
    uint256 internal bobKey = uint256(keccak256("bob"));
    address internal bob; // receiver
    uint256 internal eveKey = uint256(keccak256("eve"));
    address internal eve; // stranger at a mistyped address / third party

    address internal token = makeAddr("token");

    function setUp() public {
        bob = vm.addr(bobKey);
        eve = vm.addr(eveKey);
        frames = new MockFrameIntrospector();
        guard = new FrameConsentGuard(frames);
        vm.warp(1_800_000_000);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _consent(IFrameConsentGuard.AssetKind kind, address tok, uint256 id, uint256 amount)
        internal
        view
        returns (IFrameConsentGuard.Consent memory c)
    {
        c = IFrameConsentGuard.Consent({
            sender: alice,
            receiver: bob,
            kind: kind,
            token: tok,
            tokenId: id,
            amount: amount,
            challenge: keccak256("challenge-1"),
            deadline: uint64(block.timestamp + 1 hours)
        });
    }

    function _nativeConsent() internal view returns (IFrameConsentGuard.Consent memory) {
        return _consent(IFrameConsentGuard.AssetKind.Native, address(0), 0, 1 ether);
    }

    function _erc20Consent() internal view returns (IFrameConsentGuard.Consent memory) {
        return _consent(IFrameConsentGuard.AssetKind.ERC20, token, 0, 100e18);
    }

    function _sign(uint256 key, IFrameConsentGuard.Consent memory c)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, guard.consentDigest(c));
        return abi.encodePacked(r, s, v);
    }

    /// @dev Describe a frame tx from `txSender` whose frame 2 is (mode, target, value, data).
    function _layout(
        address txSender,
        uint256 guardFlags,
        uint256 transferMode,
        address target,
        uint256 value,
        bytes memory data
    ) internal {
        frames.clearFrames();
        frames.setTx(txSender, 1);
        frames.pushFrame(VERIFY, 0x3, txSender, 0, "");
        frames.pushFrame(DEFAULT, guardFlags, address(guard), 0, "");
        frames.pushFrame(transferMode, 0, target, value, data);
    }

    function _nativeTx(address txSender, address to, uint256 value) internal {
        _layout(txSender, ATOMIC, SENDER, to, value, "");
    }

    function _erc20Tx(address txSender, address to, uint256 amount) internal {
        _layout(txSender, ATOMIC, SENDER, token, 0, abi.encodeCall(IERC20.transfer, (to, amount)));
    }

    /*//////////////////////////////////////////////////////////////
                              HAPPY PATHS
    //////////////////////////////////////////////////////////////*/

    function test_native_happyPath() public {
        IFrameConsentGuard.Consent memory c = _nativeConsent();
        _nativeTx(alice, bob, 1 ether);
        bytes32 d = guard.consentDigest(c);

        vm.expectEmit(true, true, true, true);
        emit IFrameConsentGuard.ConsentUsed(d, alice, bob);
        guard.check(c, _sign(bobKey, c));

        assertTrue(guard.isUsed(d));
    }

    function test_erc20_happyPath() public {
        IFrameConsentGuard.Consent memory c = _erc20Consent();
        _erc20Tx(alice, bob, 100e18);

        guard.check(c, _sign(bobKey, c));

        assertTrue(guard.isUsed(guard.consentDigest(c)));
    }

    function test_digest_isEip712() public view {
        IFrameConsentGuard.Consent memory c = _nativeConsent();
        bytes32 domain = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256("FrameConsentGuard"),
                keccak256("1"),
                block.chainid,
                address(guard)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                guard.CONSENT_TYPEHASH(),
                c.sender,
                c.receiver,
                c.kind,
                c.token,
                c.tokenId,
                c.amount,
                c.challenge,
                c.deadline
            )
        );
        assertEq(
            guard.consentDigest(c), keccak256(abi.encodePacked("\x19\x01", domain, structHash))
        );
    }

    /*//////////////////////////////////////////////////////////////
                    WRONG RECEIVER / MALFORMED FRAMES
    //////////////////////////////////////////////////////////////*/

    /// Plan table row 1: consent names bob, but the signature came from eve's key.
    function test_revert_signatureFromWrongKey() public {
        IFrameConsentGuard.Consent memory c = _nativeConsent();
        _nativeTx(alice, bob, 1 ether);

        bytes memory sig = _sign(eveKey, c);
        vm.expectRevert(IFrameConsentGuard.BadConsent.selector);
        guard.check(c, sig);
    }

    /// Plan table row 4: the wallet built the transfer to a typo'd address.
    function test_revert_native_typoTo() public {
        IFrameConsentGuard.Consent memory c = _nativeConsent();
        _nativeTx(alice, eve, 1 ether);

        bytes memory sig = _sign(bobKey, c);
        vm.expectRevert(IFrameConsentGuard.BadTransferFrame.selector);
        guard.check(c, sig);
    }

    function test_revert_erc20_typoTo() public {
        IFrameConsentGuard.Consent memory c = _erc20Consent();
        _erc20Tx(alice, eve, 100e18);

        bytes memory sig = _sign(bobKey, c);
        vm.expectRevert(IFrameConsentGuard.BadTransferFrame.selector);
        guard.check(c, sig);
    }

    function test_revert_native_wrongAmount() public {
        IFrameConsentGuard.Consent memory c = _nativeConsent();
        _nativeTx(alice, bob, 2 ether);

        bytes memory sig = _sign(bobKey, c);
        vm.expectRevert(IFrameConsentGuard.BadTransferFrame.selector);
        guard.check(c, sig);
    }

    function test_revert_erc20_wrongAmount() public {
        IFrameConsentGuard.Consent memory c = _erc20Consent();
        _erc20Tx(alice, bob, 101e18);

        bytes memory sig = _sign(bobKey, c);
        vm.expectRevert(IFrameConsentGuard.BadTransferFrame.selector);
        guard.check(c, sig);
    }

    function test_revert_erc20_wrongToken() public {
        IFrameConsentGuard.Consent memory c = _erc20Consent();
        _layout(alice, ATOMIC, SENDER, eve, 0, abi.encodeCall(IERC20.transfer, (bob, 100e18)));

        bytes memory sig = _sign(bobKey, c);
        vm.expectRevert(IFrameConsentGuard.BadTransferFrame.selector);
        guard.check(c, sig);
    }

    function test_revert_native_withCalldata() public {
        IFrameConsentGuard.Consent memory c = _nativeConsent();
        _layout(alice, ATOMIC, SENDER, bob, 1 ether, hex"01");

        bytes memory sig = _sign(bobKey, c);
        vm.expectRevert(IFrameConsentGuard.BadTransferFrame.selector);
        guard.check(c, sig);
    }

    /// Without ATOMIC_BATCH a guard revert would NOT stop the transfer frame.
    function test_revert_missingAtomicFlag() public {
        IFrameConsentGuard.Consent memory c = _nativeConsent();
        _layout(alice, 0, SENDER, bob, 1 ether, "");

        bytes memory sig = _sign(bobKey, c);
        vm.expectRevert(IFrameConsentGuard.NotAtomic.selector);
        guard.check(c, sig);
    }

    function test_revert_transferFrameNotSenderMode() public {
        IFrameConsentGuard.Consent memory c = _nativeConsent();
        _layout(alice, ATOMIC, DEFAULT, bob, 1 ether, "");

        bytes memory sig = _sign(bobKey, c);
        vm.expectRevert(IFrameConsentGuard.BadTransferFrame.selector);
        guard.check(c, sig);
    }

    function test_revert_expired() public {
        IFrameConsentGuard.Consent memory c = _nativeConsent();
        _nativeTx(alice, bob, 1 ether);
        bytes memory sig = _sign(bobKey, c);

        vm.warp(c.deadline + 1);
        vm.expectRevert(IFrameConsentGuard.ConsentExpired.selector);
        guard.check(c, sig);
    }

    function test_revert_badAsset_nativeWithToken() public {
        IFrameConsentGuard.Consent memory c = _nativeConsent();
        c.token = token;
        _nativeTx(alice, bob, 1 ether);

        bytes memory sig = _sign(bobKey, c);
        vm.expectRevert(IFrameConsentGuard.BadAsset.selector);
        guard.check(c, sig);
    }

    function test_revert_badAsset_selfReceiver() public {
        IFrameConsentGuard.Consent memory c = _nativeConsent();
        c.receiver = alice;
        _nativeTx(alice, alice, 1 ether);

        bytes memory sig = _sign(bobKey, c);
        vm.expectRevert(IFrameConsentGuard.BadAsset.selector);
        guard.check(c, sig);
    }

    /*//////////////////////////////////////////////////////////////
                                REPLAY
    //////////////////////////////////////////////////////////////*/

    /// Sender's own second tx (new nonce) with the same consent.
    function test_revert_replay_sameSender() public {
        IFrameConsentGuard.Consent memory c = _nativeConsent();
        _nativeTx(alice, bob, 1 ether);
        bytes memory sig = _sign(bobKey, c);
        guard.check(c, sig);

        vm.expectRevert(IFrameConsentGuard.AlreadyUsed.selector);
        guard.check(c, sig);
    }

    /// Third party copies the consent into their own frame tx: rejected, and the
    /// consent is NOT burned, so the real sender's tx still succeeds.
    function test_thirdPartyReplay_rejectedAndCannotBurn() public {
        IFrameConsentGuard.Consent memory c = _nativeConsent();
        bytes memory sig = _sign(bobKey, c);
        bytes32 d = guard.consentDigest(c);

        _nativeTx(eve, bob, 1 ether);
        vm.expectRevert(IFrameConsentGuard.WrongSender.selector);
        guard.check(c, sig);
        assertFalse(guard.isUsed(d));

        _nativeTx(alice, bob, 1 ether);
        guard.check(c, sig);
        assertTrue(guard.isUsed(d));
    }

    /// The transfer frame fails, the atomic batch reverts the guard frame too, the stamp
    /// rolls back and the same consent can be retried.
    function test_failedTransfer_doesNotConsumeConsent() public {
        IFrameConsentGuard.Consent memory c = _nativeConsent();
        _nativeTx(alice, bob, 1 ether);
        bytes memory sig = _sign(bobKey, c);
        AtomicBatchSim sim = new AtomicBatchSim();

        vm.expectRevert(AtomicBatchSim.TransferFrameFailed.selector);
        sim.guardThenFailingTransfer(guard, c, sig);
        assertFalse(guard.isUsed(guard.consentDigest(c)));

        guard.check(c, sig);
        assertTrue(guard.isUsed(guard.consentDigest(c)));
    }

    /// A fresh challenge is a fresh consent: recurring payments each need one.
    function test_differentChallenges_eachPayOnce() public {
        IFrameConsentGuard.Consent memory c1 = _nativeConsent();
        IFrameConsentGuard.Consent memory c2 = _nativeConsent();
        c2.challenge = keccak256("challenge-2");
        _nativeTx(alice, bob, 1 ether);

        guard.check(c1, _sign(bobKey, c1));
        guard.check(c2, _sign(bobKey, c2));

        bytes memory sig1 = _sign(bobKey, c1);
        vm.expectRevert(IFrameConsentGuard.AlreadyUsed.selector);
        guard.check(c1, sig1);
    }

    /*//////////////////////////////////////////////////////////////
                        ERC-1271 SMART ACCOUNTS
    //////////////////////////////////////////////////////////////*/

    function test_erc1271Receiver_happyPath() public {
        Mock1271Wallet wallet = new Mock1271Wallet(bob);
        IFrameConsentGuard.Consent memory c = _nativeConsent();
        c.receiver = address(wallet);
        _nativeTx(alice, address(wallet), 1 ether);

        guard.check(c, _sign(bobKey, c)); // signed by the wallet's owner key

        assertTrue(guard.isUsed(guard.consentDigest(c)));
    }

    /// Plan table row 3: same address, but on this chain the account has another owner.
    function test_revert_erc1271Receiver_otherOwner() public {
        Mock1271Wallet wallet = new Mock1271Wallet(eve);
        IFrameConsentGuard.Consent memory c = _nativeConsent();
        c.receiver = address(wallet);
        _nativeTx(alice, address(wallet), 1 ether);

        bytes memory sig = _sign(bobKey, c);
        vm.expectRevert(IFrameConsentGuard.BadConsent.selector);
        guard.check(c, sig);
    }

    /// Plan table row 3: a contract receiver that cannot validate signatures at all.
    function test_revert_contractReceiverWithout1271() public {
        address notAWallet = address(frames); // has code, no isValidSignature
        IFrameConsentGuard.Consent memory c = _nativeConsent();
        c.receiver = notAWallet;
        _nativeTx(alice, notAWallet, 1 ether);

        bytes memory sig = _sign(bobKey, c);
        vm.expectRevert(IFrameConsentGuard.BadConsent.selector);
        guard.check(c, sig);
    }

    function test_supportsInterface() public view {
        assertTrue(guard.supportsInterface(type(IFrameConsentGuard).interfaceId));
        assertTrue(guard.supportsInterface(0x01ffc9a7)); // ERC-165
        assertFalse(guard.supportsInterface(0xffffffff));
    }
}

/// @dev Models EIP-8141 ATOMIC_BATCH: guard frame and transfer frame revert together.
contract AtomicBatchSim {
    error TransferFrameFailed();

    function guardThenFailingTransfer(
        FrameConsentGuard guard,
        IFrameConsentGuard.Consent calldata c,
        bytes calldata sig
    ) external {
        guard.check(c, sig); // frame 1 succeeds and writes the stamp...
        revert TransferFrameFailed(); // ...frame 2 fails, so the whole batch reverts
    }
}

/// @dev Minimal ERC-1271 smart account owned by one EOA key.
contract Mock1271Wallet is IERC1271 {
    address public immutable owner;

    constructor(address owner_) {
        owner = owner_;
    }

    function isValidSignature(bytes32 hash, bytes calldata sig) external view returns (bytes4) {
        (address signer,,) = ECDSA.tryRecover(hash, sig);
        return signer == owner ? IERC1271.isValidSignature.selector : bytes4(0xffffffff);
    }
}
