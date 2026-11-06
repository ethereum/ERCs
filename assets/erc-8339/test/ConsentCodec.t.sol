// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { ConsentCodec } from "../contracts/ConsentCodec.sol";
import { IFrameConsentGuard } from "../contracts/IFrameConsentGuard.sol";

/// @dev Exposes the calldata-taking decoders to tests.
contract CodecHarness {
    function decodeRequest(bytes calldata b)
        external
        pure
        returns (ConsentCodec.ConsentRequest memory)
    {
        return ConsentCodec.decodeRequest(b);
    }

    function decodeResponse(bytes calldata b)
        external
        pure
        returns (ConsentCodec.ConsentResponse memory)
    {
        return ConsentCodec.decodeResponse(b);
    }
}

contract ConsentCodecTest is Test {
    CodecHarness internal h = new CodecHarness();

    function _request() internal returns (ConsentCodec.ConsentRequest memory) {
        return ConsentCodec.ConsentRequest({
            chainId: block.chainid,
            guard: makeAddr("guard"),
            sender: makeAddr("alice"),
            kind: IFrameConsentGuard.AssetKind.ERC20,
            token: makeAddr("token"),
            tokenId: 0,
            amount: 100e18,
            challenge: keccak256("challenge"),
            deadline: 1_800_003_600
        });
    }

    function test_request_roundTrip() public {
        ConsentCodec.ConsentRequest memory r = _request();
        bytes memory b = ConsentCodec.encodeRequest(r);

        assertEq(uint8(b[0]), 0x01);
        assertEq(uint8(b[1]), 0x01);
        assertEq(keccak256(abi.encode(h.decodeRequest(b))), keccak256(abi.encode(r)));
    }

    function test_response_roundTrip() public {
        ConsentCodec.ConsentResponse memory r =
            ConsentCodec.ConsentResponse({ receiver: makeAddr("bob"), sig: hex"aabbcc" });
        bytes memory b = ConsentCodec.encodeResponse(r);

        ConsentCodec.ConsentResponse memory out = h.decodeResponse(b);
        assertEq(out.receiver, r.receiver);
        assertEq(out.sig, r.sig);
    }

    /// Pins the wire format to the ERC text: version || type || abi.encode(fields...).
    function test_wireFormat_isFlatAbiEncoding() public {
        ConsentCodec.ConsentRequest memory q = _request();
        assertEq(
            ConsentCodec.encodeRequest(q),
            abi.encodePacked(
                bytes2(0x0101),
                abi.encode(
                    q.chainId,
                    q.guard,
                    q.sender,
                    q.kind,
                    q.token,
                    q.tokenId,
                    q.amount,
                    q.challenge,
                    q.deadline
                )
            )
        );

        address bob = makeAddr("bob");
        ConsentCodec.ConsentResponse memory r =
            ConsentCodec.ConsentResponse({ receiver: bob, sig: hex"aabbcc" });
        assertEq(
            ConsentCodec.encodeResponse(r),
            abi.encodePacked(bytes2(0x0102), abi.encode(bob, bytes(hex"aabbcc")))
        );
    }

    function test_revert_wrongType() public {
        bytes memory b = ConsentCodec.encodeRequest(_request());
        vm.expectRevert(ConsentCodec.BadType.selector);
        h.decodeResponse(b);
    }

    function test_revert_wrongVersion() public {
        bytes memory b = ConsentCodec.encodeRequest(_request());
        b[0] = 0x02;
        vm.expectRevert(ConsentCodec.BadVersion.selector);
        h.decodeRequest(b);
    }

    function test_toConsent_copiesFieldsAndAddsReceiver() public {
        ConsentCodec.ConsentRequest memory r = _request();
        address bob = makeAddr("bob");
        IFrameConsentGuard.Consent memory c = ConsentCodec.toConsent(r, bob);

        assertEq(c.sender, r.sender);
        assertEq(c.receiver, bob);
        assertEq(uint8(c.kind), uint8(r.kind));
        assertEq(c.token, r.token);
        assertEq(c.amount, r.amount);
        assertEq(c.challenge, r.challenge);
        assertEq(c.deadline, r.deadline);
    }
}
