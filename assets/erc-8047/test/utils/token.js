import {solidityPackedKeccak256, getBytes} from "ethers";

export const getTransactionOutput = async (txn) => {
  return txn.logs[0].args[0];
};

export const signTransactionInput = async (signer, txnOutput) => {
  const hashed = solidityPackedKeccak256(["bytes32"], [txnOutput]);
  return await signer.signMessage(getBytes(hashed));
};

export const getCreatedTokenId = async (txn) => {
  return txn.logs[0].args[1];
};

export const mint = async (tokenContract, address, amount) => {
  let tx = await tokenContract.mint(address, amount);
  tx = await tx.wait();
  const tokenId = tx.logs[0].args[1];
  return tokenId;
};
