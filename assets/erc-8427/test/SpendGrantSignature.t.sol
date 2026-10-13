// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {SpendGrantSignature} from "../src/SpendGrantSignature.sol";
import {
    Allowlist1271, LongMagic1271, RawMagic1271, Rejecting1271, RevertMagic1271
} from "./SpendGrantAuthorization.t.sol";

/// @dev Applies the library's Signatures rules to calldata.
contract SignatureRulesHarness {
    function recover(bytes32 digest, bytes calldata sig) external pure returns (address) {
        return SpendGrantSignature.recover(digest, sig);
    }

    function authenticate(address expected, bytes32 digest, bytes calldata sig) external view returns (address) {
        return SpendGrantSignature.authenticate(expected, digest, sig);
    }

    function isValid(address signer, bytes32 digest, bytes calldata sig) external view returns (bool) {
        return SpendGrantSignature.isValid(signer, digest, sig);
    }

    function isValidErc1271(address signer, bytes32 digest, bytes calldata sig) external view returns (bool) {
        return SpendGrantSignature.isValidErc1271(signer, digest, sig);
    }
}

/// @notice The Signatures rules in the library itself: the strict 65-byte secp256k1 form, which code gets ECDSA, the
/// exact ERC-1271 answer, and `isValid`.
contract SpendGrantSignatureTest is Test {
    uint256 internal constant SIGNER_PK = 0xB0B;
    uint256 internal constant HALF_ORDER = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;
    bytes32 internal constant DIGEST = keccak256("a digest to sign");

    SignatureRulesHarness internal harness;
    address internal signer;

    function setUp() public {
        harness = new SignatureRulesHarness();
        signer = vm.addr(SIGNER_PK);
    }

    // ---------------------------------------------------------------- secp256k1, for a signer without code

    /// `s` is nonzero and in the lower half of the curve order,
    /// `s <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0`. With a real signature's `r` and `v`,
    /// each of the three values of `s` here recovers some address under `ecrecover`: the bound and 1 are accepted and
    /// give that address, and the bound plus one is rejected.
    function test_recover_lowSIsInclusiveOfTheBound() public view {
        (uint8 v, bytes32 r,) = vm.sign(SIGNER_PK, DIGEST);
        bytes32 atBound = bytes32(HALF_ORDER);
        bytes32 one = bytes32(uint256(1));
        bytes32 aboveBound = bytes32(HALF_ORDER + 1);
        address atBoundSigner = ecrecover(DIGEST, v, r, atBound);
        address oneSigner = ecrecover(DIGEST, v, r, one);
        address aboveBoundSigner = ecrecover(DIGEST, v, r, aboveBound);
        assertTrue(atBoundSigner != address(0), "ecrecover at the bound");
        assertTrue(oneSigner != address(0), "ecrecover of 1");
        assertTrue(aboveBoundSigner != address(0), "ecrecover above the bound");

        assertEq(harness.recover(DIGEST, abi.encodePacked(r, atBound, v)), atBoundSigner, "s at the bound");
        assertEq(harness.authenticate(atBoundSigner, DIGEST, abi.encodePacked(r, atBound, v)), atBoundSigner);
        assertEq(harness.recover(DIGEST, abi.encodePacked(r, one, v)), oneSigner, "s of 1");
        assertEq(harness.recover(DIGEST, abi.encodePacked(r, aboveBound, v)), address(0), "s above the bound");
        assertEq(harness.authenticate(aboveBoundSigner, DIGEST, abi.encodePacked(r, aboveBound, v)), address(0));
    }

    /// The signature is exactly 65 bytes `r || s || v`: the same valid signature with one trailing byte, or in its
    /// 64-byte compact form, recovers nobody.
    function test_recover_signatureIsExactly65Bytes() public view {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, DIGEST);
        (bytes32 compactR, bytes32 vs) = vm.signCompact(SIGNER_PK, DIGEST);
        bytes memory trailing = abi.encodePacked(r, s, v, uint8(0));
        bytes memory compact = abi.encodePacked(compactR, vs);
        assertEq(harness.recover(DIGEST, abi.encodePacked(r, s, v)), signer);

        assertEq(harness.recover(DIGEST, trailing), address(0), "66 bytes");
        assertEq(harness.authenticate(signer, DIGEST, trailing), address(0), "66 bytes");
        assertEq(harness.recover(DIGEST, compact), address(0), "64 bytes");
        assertEq(harness.authenticate(signer, DIGEST, compact), address(0), "64 bytes");
    }

    /// `v` is 27 or 28. Any other `v`, each from 0 through 30 and 255, recovers nobody: zero, never a placeholder
    /// address that a grant could name.
    function test_recover_badVRecoversNobody() public view {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, DIGEST);
        assertEq(harness.recover(DIGEST, abi.encodePacked(r, s, v)), signer);
        for (uint8 badV = 0; badV <= 30; badV++) {
            if (badV != 27 && badV != 28) _assertRecoversNobody(abi.encodePacked(r, s, badV));
        }
        _assertRecoversNobody(abi.encodePacked(r, s, uint8(255)));
    }

    // ---------------------------------------------------------------- which code gets ECDSA

    /// No ECDSA fallback for a code-bearing signer: only an EIP-7702 designator, exactly 23 bytes beginning with
    /// `0xef0100`, lets the account's own key sign for it. The same key's valid signature does not authenticate the
    /// address once its code is 23 bytes of ordinary code instead.
    function test_authenticate_noEcdsaFor23ByteCodeThatIsNotADesignator() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, DIGEST);
        bytes memory sig = abi.encodePacked(r, s, v);
        vm.etch(signer, abi.encodePacked(hex"ef0100", address(new Rejecting1271())));
        assertEq(harness.authenticate(signer, DIGEST, sig), signer, "a designator's own key");

        vm.etch(signer, new bytes(23));
        assertEq(signer.code.length, 23);
        assertEq(harness.recover(DIGEST, sig), signer);
        assertEq(harness.authenticate(signer, DIGEST, sig), address(0), "23 bytes of ordinary code");
    }

    // ---------------------------------------------------------------- the ERC-1271 answer

    /// The ERC-1271 call must return exactly 32 bytes equal to the left-aligned magic value. A revert carrying that
    /// word, 64 bytes starting with it, and its raw four bytes are each invalid, and authenticate nobody.
    function test_authenticate_erc1271NeedsExactlyOneSuccessfulWord() public {
        Allowlist1271 wallet = new Allowlist1271();
        wallet.allow(DIGEST);
        assertTrue(harness.isValidErc1271(address(wallet), DIGEST, hex"00"));
        assertEq(harness.authenticate(address(wallet), DIGEST, hex"00"), address(wallet));

        address[3] memory validators =
            [address(new RevertMagic1271()), address(new LongMagic1271()), address(new RawMagic1271())];
        for (uint256 i = 0; i < validators.length; i++) {
            assertFalse(harness.isValidErc1271(validators[i], DIGEST, hex"00"));
            assertEq(harness.authenticate(validators[i], DIGEST, hex"00"), address(0));
        }
    }

    // ---------------------------------------------------------------- isValid

    /// `isValid(signer, digest, sig)` holds when the Signatures rules authenticate that signer: a valid signature by an
    /// address without code is valid for its signer and for no other address.
    function test_isValid_eoaSignatureIsValidForItsSignerOnly() public view {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, DIGEST);
        bytes memory sig = abi.encodePacked(r, s, v);
        assertTrue(harness.isValid(signer, DIGEST, sig));
        assertFalse(harness.isValid(vm.addr(0xBAD), DIGEST, sig));
    }

    /// A zero signer is never valid. A malformed signature authenticates zero, so the comparison with the signer alone
    /// would accept it.
    function test_isValid_zeroSignerIsNeverValid() public view {
        assertEq(harness.authenticate(address(0), DIGEST, hex"1234"), address(0));
        assertFalse(harness.isValid(address(0), DIGEST, hex"1234"));
    }

    /// A signer whose code is not a delegation designator is valid exactly when its ERC-1271 accepts.
    function test_isValid_erc1271SignerFollowsItsAnswer() public {
        Allowlist1271 wallet = new Allowlist1271();
        wallet.allow(DIGEST);
        assertTrue(harness.isValid(address(wallet), DIGEST, hex"00"));
        assertFalse(harness.isValid(address(wallet), keccak256("another digest"), hex"00"));
    }

    /// `sig` recovers nobody, and so authenticates nobody for the signer, which has no code.
    function _assertRecoversNobody(bytes memory sig) internal view {
        assertEq(harness.recover(DIGEST, sig), address(0));
        assertEq(harness.authenticate(signer, DIGEST, sig), address(0));
    }
}
