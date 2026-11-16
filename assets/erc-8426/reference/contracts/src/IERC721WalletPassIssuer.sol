// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

/// @title ERC-721 Wallet Pass Extension, issuer identity commitment
/// @dev The ERC-165 identifier for this interface is 0x470be7e9.
///  OPTIONAL: a contract implements it to commit on chain to the platform
///  signer its passes come from, so a client can check the signer of a pass
///  against something the contract, not the endpoint, asserts.
interface IERC721WalletPassIssuer {
    /// @notice The platform signer identity the pass manifests of this
    ///  contract carry, as the JSON `issuer` object defined under
    ///  Pass manifest.
    function passIssuer() external view returns (string memory);
}
