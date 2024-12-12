export async function minimalAttestationSample() {
    // #################################### ACCOUNTS
  // Alice shall get the NFT, oracle signs the attestation off-chain 
  // Oracle needs to be a trusted Oracle of the smart-contract that shall accept the generated attestation
  const [alice, oracle] = await ethers.getSigners();

  // #################################### CREATE AN ATTESTATION
  const to = alice.address;
  const anchor = '0x4cc52563699fb1e3333b8aab3ecf016f8fd084e6fc48edf8603d83d4c5b97536'

  const attestationTime = Math.floor(Date.now() / 1000.0); // Now in seconds UTC
  const validStartTime = 0;
  const validEndTime = attestationTime + 15 * 60; // 15 minutes valid from attestation

  const messageHash = ethers.utils.solidityKeccak256(
    ["address", "bytes32", "uint256", 'uint256', "uint256"], 
    [to, anchor, attestationTime, validStartTime, validEndTime]
  );
  const sig = await signer.signMessage(ethers.utils.arrayify(messageHash));

  return ethers.utils.defaultAbiCoder.encode(
    ['address', 'bytes32', 'uint256', 'uint256', 'uint256', 'bytes'], 
    [to, anchor, attestationTime,  validStartTime, validEndTime, sig]
  );
}