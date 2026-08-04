import { loadFixture } from '@nomicfoundation/hardhat-toolbox-viem/network-helpers';
import safeProxyArtifact from '@safe-global/safe-smart-account/build/artifacts/contracts/proxies/SafeProxy.sol/SafeProxy.json';
import safeArtifact from '@safe-global/safe-smart-account/build/artifacts/contracts/Safe.sol/Safe.json';
import { expect } from 'chai';
import { ignition, viem } from 'hardhat';
import {
  encodeFunctionData,
  padHex,
  parseEther,
  type Abi,
  type Address,
  type GetContractReturnType,
  type Hex,
  zeroAddress,
} from 'viem';

import BalanceProxyModule from '@/ignition/modules/balance-proxy';

const ZERO_ADDRESS = zeroAddress;

const mintAbi = [
  {
    name: 'mint',
    type: 'function',
    inputs: [
      { type: 'uint256', name: 'take' },
      { type: 'uint256', name: 'give' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
] as const;

const mintEthAbi = [
  {
    name: 'mintEth',
    type: 'function',
    inputs: [
      { type: 'uint256', name: 'take' },
      { type: 'uint256', name: 'give' },
    ],
    outputs: [],
    stateMutability: 'payable',
  },
] as const;

type SafeTx = {
  to: Address;
  value: bigint;
  data: Hex;
  operation: number;
  safeTxGas: bigint;
  baseGas: bigint;
  gasPrice: bigint;
  gasToken: Address;
  refundReceiver: Address;
  signatures: Hex;
  routerSigPosition: bigint;
};

function safeTx(params: {
  to: Address;
  data: Hex;
  value?: bigint;
  operation?: number;
  signatures?: Hex;
  routerSigPosition?: bigint;
  safeTxGas?: bigint;
  baseGas?: bigint;
  gasPrice?: bigint;
  gasToken?: Address;
  refundReceiver?: Address;
}): SafeTx {
  return {
    to: params.to,
    value: params.value ?? 0n,
    data: params.data,
    operation: params.operation ?? 0,
    safeTxGas: params.safeTxGas ?? 0n,
    baseGas: params.baseGas ?? 0n,
    gasPrice: params.gasPrice ?? 0n,
    gasToken: params.gasToken ?? ZERO_ADDRESS,
    refundReceiver: params.refundReceiver ?? ZERO_ADDRESS,
    signatures: params.signatures ?? '0x',
    routerSigPosition: params.routerSigPosition ?? 0n,
  };
}

function approvedHashSignature(owner: Address): Hex {
  return `${padHex(owner, { size: 32 })}${'0'.repeat(64)}01` as Hex;
}

function sortOwners(owners: Address[]): Address[] {
  return [...owners].sort((left, right) =>
    BigInt(left) < BigInt(right) ? -1 : 1,
  );
}

function routerSignaturePosition(humanOwners: Address[], router: Address) {
  const routerValue = BigInt(router);
  return BigInt(
    humanOwners.filter((owner) => BigInt(owner) < routerValue).length,
  );
}

function approvedHashSignatures(owners: Address[]): Hex {
  return `0x${sortOwners(owners)
    .map((owner) => approvedHashSignature(owner).slice(2))
    .join('')}` as Hex;
}

async function getSafeTxHash(
  safe: GetContractReturnType<Abi>,
  tx: SafeTx,
): Promise<Hex> {
  const nonce = await safe.read.nonce();
  return await safe.read.getTransactionHash([
    tx.to,
    tx.value,
    tx.data,
    tx.operation,
    tx.safeTxGas,
    tx.baseGas,
    tx.gasPrice,
    tx.gasToken,
    tx.refundReceiver,
    nonce,
  ]);
}

async function safeTxWithApprovals(
  safe: GetContractReturnType<Abi>,
  tx: SafeTx,
  router: Address,
  owners: Array<{ account: { address: Address } }>,
): Promise<SafeTx> {
  const safeTxHash = await getSafeTxHash(safe, tx);
  for (const owner of owners) {
    await safe.write.approveHash([safeTxHash], { account: owner.account });
  }

  const ownerAddresses = owners.map((owner) => owner.account.address);
  const requiredHumanSignatures = Number((await safe.read.getThreshold()) - 1n);
  const selectedOwners = sortOwners(ownerAddresses).slice(
    0,
    requiredHumanSignatures,
  );

  return {
    ...tx,
    signatures: approvedHashSignatures(ownerAddresses),
    routerSigPosition: routerSignaturePosition(selectedOwners, router),
  };
}

async function deployFixture() {
  const [owner, signer, executor, stranger] = await viem.getWalletClients();
  const publicClient = await viem.getPublicClient();

  const { balanceProxy } = await ignition.deploy(BalanceProxyModule, {
    defaultSender: owner.account.address,
  });

  const token = await viem.deployContract('ERC20Mock', ['MockToken', 'MTK']);
  const target = await viem.deployContract('TargetMock', [token.address]);
  const safe = await viem.deployContract('SafeMock', []);
  const safeRouter = await viem.deployContract('SafeRouter', []);

  await safe.write.addOwner([owner.account.address]);
  await safe.write.addOwner([signer.account.address]);
  await safe.write.addOwner([safeRouter.address]);
  await safe.write.setThreshold([2n]);

  return {
    owner,
    signer,
    executor,
    stranger,
    publicClient,
    balanceProxy,
    token,
    target,
    safe,
    safeRouter,
  };
}

async function deployRealSafeFixture() {
  const base = await deployFixture();
  const { owner, signer, executor, publicClient, safeRouter } = base;

  const singletonHash = await owner.deployContract({
    abi: safeArtifact.abi,
    bytecode: safeArtifact.bytecode as Hex,
  });
  const singletonReceipt = await publicClient.waitForTransactionReceipt({
    hash: singletonHash,
  });
  if (!singletonReceipt.contractAddress) {
    throw new Error('Safe singleton deployment did not return an address');
  }

  const proxyHash = await owner.deployContract({
    abi: safeProxyArtifact.abi,
    bytecode: safeProxyArtifact.bytecode as Hex,
    args: [singletonReceipt.contractAddress],
  });
  const proxyReceipt = await publicClient.waitForTransactionReceipt({
    hash: proxyHash,
  });
  if (!proxyReceipt.contractAddress) {
    throw new Error('Safe proxy deployment did not return an address');
  }

  const realSafe = await viem.getContractAt(
    'ISafe',
    proxyReceipt.contractAddress,
  );

  await realSafe.write.setup(
    [
      [signer.account.address, executor.account.address, safeRouter.address],
      3n,
      ZERO_ADDRESS,
      '0x',
      ZERO_ADDRESS,
      ZERO_ADDRESS,
      0n,
      ZERO_ADDRESS,
    ],
    { account: owner.account },
  );

  return { ...base, realSafe };
}

describe('SafeRouter', function () {
  this.timeout(120_000);

  it('executes original tx via Safe then verifies post-balances via BalanceProxy', async () => {
    const { owner, balanceProxy, token, target, safe, safeRouter } =
      await loadFixture(deployFixture);

    const GIVE = parseEther('100');
    const swapData = encodeFunctionData({
      abi: mintAbi,
      functionName: 'mint',
      args: [0n, GIVE],
    });

    await safeRouter.write.safeExecuteWithPostBalances(
      [
        balanceProxy.address,
        [{ target: safe.address, token: token.address, balance: GIVE }],
        safe.address,
        await safeTxWithApprovals(
          safe,
          safeTx({ to: target.address, data: swapData }),
          safeRouter.address,
          [owner],
        ),
      ],
      { account: owner.account },
    );

    expect(await token.read.balanceOf([safe.address])).to.equal(GIVE);
    expect(await safe.read.lastSignaturesLength()).to.equal(130n);
  });

  it('trims over-threshold human signatures before adding the router marker', async () => {
    const { owner, signer, balanceProxy, token, target, safe, safeRouter } =
      await loadFixture(deployFixture);

    const GIVE = parseEther('5');
    const swapData = encodeFunctionData({
      abi: mintAbi,
      functionName: 'mint',
      args: [0n, GIVE],
    });

    await safeRouter.write.safeExecuteWithPostBalances(
      [
        balanceProxy.address,
        [{ target: safe.address, token: token.address, balance: GIVE }],
        safe.address,
        await safeTxWithApprovals(
          safe,
          safeTx({ to: target.address, data: swapData }),
          safeRouter.address,
          [owner, signer],
        ),
      ],
      { account: owner.account },
    );

    expect(await token.read.balanceOf([safe.address])).to.equal(GIVE);
    expect(await safe.read.lastSignaturesLength()).to.equal(130n);
  });

  it('executes original tx via Safe then verifies balance diffs for that tx', async () => {
    const { owner, balanceProxy, token, target, safe, safeRouter } =
      await loadFixture(deployFixture);

    const GIVE = parseEther('25');
    const swapData = encodeFunctionData({
      abi: mintAbi,
      functionName: 'mint',
      args: [0n, GIVE],
    });

    await safeRouter.write.safeExecuteWithDiffs(
      [
        balanceProxy.address,
        [{ target: safe.address, token: token.address, balance: GIVE }],
        safe.address,
        await safeTxWithApprovals(
          safe,
          safeTx({ to: target.address, data: swapData }),
          safeRouter.address,
          [owner],
        ),
      ],
      { account: owner.account },
    );

    expect(await token.read.balanceOf([safe.address])).to.equal(GIVE);
  });

  it('executes ETH flow: Safe receives ETH, BalanceProxy verifies post-balance', async () => {
    const { owner, balanceProxy, publicClient, target, safe, safeRouter } =
      await loadFixture(deployFixture);

    const GIVE_ETH = parseEther('2');
    await owner.sendTransaction({ to: target.address, value: GIVE_ETH });

    const swapData = encodeFunctionData({
      abi: mintEthAbi,
      functionName: 'mintEth',
      args: [0n, GIVE_ETH],
    });

    await safeRouter.write.safeExecuteWithPostBalances(
      [
        balanceProxy.address,
        [{ target: safe.address, token: ZERO_ADDRESS, balance: GIVE_ETH }],
        safe.address,
        await safeTxWithApprovals(
          safe,
          safeTx({ to: target.address, data: swapData }),
          safeRouter.address,
          [owner],
        ),
      ],
      { account: owner.account },
    );

    expect(await publicClient.getBalance({ address: safe.address })).to.equal(
      GIVE_ETH,
    );
  });

  it('reverts and rolls back original tx when post-balance check fails', async () => {
    const { owner, balanceProxy, token, target, safe, safeRouter } =
      await loadFixture(deployFixture);

    const GIVE = parseEther('100');
    const swapData = encodeFunctionData({
      abi: mintAbi,
      functionName: 'mint',
      args: [0n, GIVE],
    });

    await expect(
      safeRouter.write.safeExecuteWithPostBalances(
        [
          balanceProxy.address,
          [{ target: safe.address, token: token.address, balance: GIVE + 1n }],
          safe.address,
          await safeTxWithApprovals(
            safe,
            safeTx({ to: target.address, data: swapData }),
            safeRouter.address,
            [owner],
          ),
        ],
        { account: owner.account },
      ),
    ).to.be.rejectedWith('ERC8009BalanceConstraintViolation');

    expect(await token.read.balanceOf([safe.address])).to.equal(0n);
  });

  it('reverts and rolls back original tx when diff check fails', async () => {
    const { owner, balanceProxy, token, target, safe, safeRouter } =
      await loadFixture(deployFixture);

    const GIVE = parseEther('100');
    const swapData = encodeFunctionData({
      abi: mintAbi,
      functionName: 'mint',
      args: [0n, GIVE],
    });

    await expect(
      safeRouter.write.safeExecuteWithDiffs(
        [
          balanceProxy.address,
          [{ target: safe.address, token: token.address, balance: GIVE + 1n }],
          safe.address,
          await safeTxWithApprovals(
            safe,
            safeTx({ to: target.address, data: swapData }),
            safeRouter.address,
            [owner],
          ),
        ],
        { account: owner.account },
      ),
    ).to.be.rejectedWith('ERC8009BalanceDiffConstraintViolation');

    expect(await token.read.balanceOf([safe.address])).to.equal(0n);
  });

  it('reverts with NotSafeOwner when caller is not a Safe owner', async () => {
    const { stranger, balanceProxy, token, target, safe, safeRouter } =
      await loadFixture(deployFixture);

    const swapData = encodeFunctionData({
      abi: mintAbi,
      functionName: 'mint',
      args: [0n, parseEther('1')],
    });

    await expect(
      safeRouter.write.safeExecuteWithPostBalances(
        [
          balanceProxy.address,
          [
            {
              target: safe.address,
              token: token.address,
              balance: parseEther('1'),
            },
          ],
          safe.address,
          safeTx({ to: target.address, data: swapData }),
        ],
        { account: stranger.account },
      ),
    ).to.be.rejectedWith('NotSafeOwner');
  });

  it('reverts with RouterNotSafeOwner when Safe did not install the router owner', async () => {
    const { owner, token, target, balanceProxy } =
      await loadFixture(deployFixture);
    const safeWithoutRouter = await viem.deployContract('SafeMock', []);
    const safeRouter = await viem.deployContract('SafeRouter', []);
    await safeWithoutRouter.write.addOwner([owner.account.address]);

    const swapData = encodeFunctionData({
      abi: mintAbi,
      functionName: 'mint',
      args: [0n, parseEther('1')],
    });

    await expect(
      safeRouter.write.safeExecuteWithPostBalances(
        [
          balanceProxy.address,
          [
            {
              target: safeWithoutRouter.address,
              token: token.address,
              balance: parseEther('1'),
            },
          ],
          safeWithoutRouter.address,
          await safeTxWithApprovals(
            safeWithoutRouter,
            safeTx({ to: target.address, data: swapData }),
            safeRouter.address,
            [owner],
          ),
        ],
        { account: owner.account },
      ),
    ).to.be.rejectedWith('RouterNotSafeOwner');

    expect(await token.read.balanceOf([safeWithoutRouter.address])).to.equal(
      0n,
    );
  });

  it('reverts before Safe execution when only one human approved a 2-human Safe', async () => {
    const { owner, balanceProxy, token, target, safe, safeRouter } =
      await loadFixture(deployFixture);
    await safe.write.setThreshold([3n]);

    const swapData = encodeFunctionData({
      abi: mintAbi,
      functionName: 'mint',
      args: [0n, parseEther('1')],
    });

    await expect(
      safeRouter.write.safeExecuteWithPostBalances(
        [
          balanceProxy.address,
          [
            {
              target: safe.address,
              token: token.address,
              balance: parseEther('1'),
            },
          ],
          safe.address,
          await safeTxWithApprovals(
            safe,
            safeTx({ to: target.address, data: swapData }),
            safeRouter.address,
            [owner],
          ),
        ],
        { account: owner.account },
      ),
    ).to.be.rejectedWith('InsufficientSafeSignatures');
  });

  it('reverts through Safe when the router marker is used as a human signature', async () => {
    const { owner, balanceProxy, token, target, safe, safeRouter } =
      await loadFixture(deployFixture);

    const swapData = encodeFunctionData({
      abi: mintAbi,
      functionName: 'mint',
      args: [0n, parseEther('1')],
    });

    await expect(
      safeRouter.write.safeExecuteWithPostBalances(
        [
          balanceProxy.address,
          [
            {
              target: safe.address,
              token: token.address,
              balance: parseEther('1'),
            },
          ],
          safe.address,
          safeTx({
            to: target.address,
            data: swapData,
            signatures: approvedHashSignature(safeRouter.address),
          }),
        ],
        { account: owner.account },
      ),
    ).to.be.rejectedWith('ERC8009CallFailed');
  });

  it('reverts before Safe execution when signatures are not 65-byte aligned', async () => {
    const { owner, balanceProxy, token, target, safe, safeRouter } =
      await loadFixture(deployFixture);

    const swapData = encodeFunctionData({
      abi: mintAbi,
      functionName: 'mint',
      args: [0n, parseEther('1')],
    });
    const approvedTx = await safeTxWithApprovals(
      safe,
      safeTx({ to: target.address, data: swapData }),
      safeRouter.address,
      [owner],
    );

    await expect(
      safeRouter.write.safeExecuteWithPostBalances(
        [
          balanceProxy.address,
          [
            {
              target: safe.address,
              token: token.address,
              balance: parseEther('1'),
            },
          ],
          safe.address,
          {
            ...approvedTx,
            signatures: `${approvedTx.signatures}00` as Hex,
          },
        ],
        { account: owner.account },
      ),
    ).to.be.rejectedWith('InvalidSignaturesLength');
  });

  it('reverts before Safe execution when router signature position is outside the used human signatures', async () => {
    const { owner, balanceProxy, token, target, safe, safeRouter } =
      await loadFixture(deployFixture);

    const swapData = encodeFunctionData({
      abi: mintAbi,
      functionName: 'mint',
      args: [0n, parseEther('1')],
    });

    await expect(
      safeRouter.write.safeExecuteWithPostBalances(
        [
          balanceProxy.address,
          [
            {
              target: safe.address,
              token: token.address,
              balance: parseEther('1'),
            },
          ],
          safe.address,
          {
            ...(await safeTxWithApprovals(
              safe,
              safeTx({ to: target.address, data: swapData }),
              safeRouter.address,
              [owner],
            )),
            routerSigPosition: 2n,
          },
        ],
        { account: owner.account },
      ),
    ).to.be.rejectedWith('InvalidRouterSignaturePosition');
  });

  it('reverts before Safe execution when operation is not Call', async () => {
    const { owner, balanceProxy, token, target, safe, safeRouter } =
      await loadFixture(deployFixture);

    const GIVE = parseEther('1');
    const swapData = encodeFunctionData({
      abi: mintAbi,
      functionName: 'mint',
      args: [0n, GIVE],
    });

    await expect(
      safeRouter.write.safeExecuteWithPostBalances(
        [
          balanceProxy.address,
          [{ target: safe.address, token: token.address, balance: GIVE }],
          safe.address,
          safeTx({ to: target.address, data: swapData, operation: 1 }),
        ],
        { account: owner.account },
      ),
    ).to.be.rejectedWith('UnsupportedSafeOperation');

    expect(await token.read.balanceOf([safe.address])).to.equal(0n);
  });

  it('validates metadata, executes tx, verifies via BalanceProxy', async () => {
    const { owner, balanceProxy, token, target, safe, safeRouter } =
      await loadFixture(deployFixture);

    const GIVE = parseEther('50');
    const swapData = encodeFunctionData({
      abi: mintAbi,
      functionName: 'mint',
      args: [0n, GIVE],
    });

    await safeRouter.write.safeExecuteWithPostBalancesMeta(
      [
        balanceProxy.address,
        [{ symbol: 'MTK', decimals: 18 }],
        [{ target: safe.address, token: token.address, balance: GIVE }],
        safe.address,
        await safeTxWithApprovals(
          safe,
          safeTx({ to: target.address, data: swapData }),
          safeRouter.address,
          [owner],
        ),
      ],
      { account: owner.account },
    );

    expect(await token.read.balanceOf([safe.address])).to.equal(GIVE);
  });

  it('reverts with InvalidMetadata on symbol mismatch', async () => {
    const { owner, balanceProxy, token, target, safe, safeRouter } =
      await loadFixture(deployFixture);

    const swapData = encodeFunctionData({
      abi: mintAbi,
      functionName: 'mint',
      args: [0n, parseEther('1')],
    });

    await expect(
      safeRouter.write.safeExecuteWithPostBalancesMeta(
        [
          balanceProxy.address,
          [{ symbol: 'WRONG', decimals: 18 }],
          [
            {
              target: safe.address,
              token: token.address,
              balance: parseEther('1'),
            },
          ],
          safe.address,
          await safeTxWithApprovals(
            safe,
            safeTx({ to: target.address, data: swapData }),
            safeRouter.address,
            [owner],
          ),
        ],
        { account: owner.account },
      ),
    ).to.be.rejectedWith('InvalidMetadata');
  });

  it('reverts with InvalidMetadata on decimals mismatch', async () => {
    const { owner, balanceProxy, token, target, safe, safeRouter } =
      await loadFixture(deployFixture);

    const swapData = encodeFunctionData({
      abi: mintAbi,
      functionName: 'mint',
      args: [0n, parseEther('1')],
    });

    await expect(
      safeRouter.write.safeExecuteWithPostBalancesMeta(
        [
          balanceProxy.address,
          [{ symbol: 'MTK', decimals: 6 }],
          [
            {
              target: safe.address,
              token: token.address,
              balance: parseEther('1'),
            },
          ],
          safe.address,
          await safeTxWithApprovals(
            safe,
            safeTx({ to: target.address, data: swapData }),
            safeRouter.address,
            [owner],
          ),
        ],
        { account: owner.account },
      ),
    ).to.be.rejectedWith('InvalidMetadata');
  });

  it('ETH metadata flow via BalanceProxy skip', async () => {
    const { owner, balanceProxy, publicClient, target, safe, safeRouter } =
      await loadFixture(deployFixture);

    const GIVE_ETH = parseEther('1');
    await owner.sendTransaction({ to: target.address, value: GIVE_ETH });

    const swapData = encodeFunctionData({
      abi: mintEthAbi,
      functionName: 'mintEth',
      args: [0n, GIVE_ETH],
    });

    await safeRouter.write.safeExecuteWithPostBalancesMeta(
      [
        balanceProxy.address,
        [{ symbol: 'ETH', decimals: 18 }],
        [{ target: safe.address, token: ZERO_ADDRESS, balance: GIVE_ETH }],
        safe.address,
        await safeTxWithApprovals(
          safe,
          safeTx({ to: target.address, data: swapData }),
          safeRouter.address,
          [owner],
        ),
      ],
      { account: owner.account },
    );

    expect(await publicClient.getBalance({ address: safe.address })).to.equal(
      GIVE_ETH,
    );
  });

  it('reverts through the real Safe when only one human approved before wrapping', async () => {
    const {
      signer,
      executor,
      balanceProxy,
      token,
      target,
      safeRouter,
      realSafe,
    } = await loadFixture(deployRealSafeFixture);

    const GIVE = parseEther('77');
    const swapData = encodeFunctionData({
      abi: mintAbi,
      functionName: 'mint',
      args: [0n, GIVE],
    });
    const nonce = await realSafe.read.nonce();
    const safeTxHash = await realSafe.read.getTransactionHash([
      target.address,
      0n,
      swapData,
      0,
      0n,
      0n,
      0n,
      ZERO_ADDRESS,
      ZERO_ADDRESS,
      nonce,
    ]);

    await realSafe.write.approveHash([safeTxHash], {
      account: signer.account,
    });

    await expect(
      safeRouter.write.safeExecuteWithDiffs(
        [
          balanceProxy.address,
          [{ target: realSafe.address, token: token.address, balance: GIVE }],
          realSafe.address,
          safeTx({
            to: target.address,
            data: swapData,
            signatures: approvedHashSignature(signer.account.address),
            routerSigPosition: routerSignaturePosition(
              [signer.account.address],
              safeRouter.address,
            ),
          }),
        ],
        { account: executor.account },
      ),
    ).to.be.rejectedWith('InsufficientSafeSignatures');

    expect(await token.read.balanceOf([realSafe.address])).to.equal(0n);
    expect(await realSafe.read.nonce()).to.equal(nonce);
  });

  it('prevents leaked human signatures from executing directly through Safe', async () => {
    const {
      signer,
      executor,
      stranger,
      balanceProxy,
      token,
      target,
      safeRouter,
      realSafe,
    } = await loadFixture(deployRealSafeFixture);

    const GIVE = parseEther('33');
    const swapData = encodeFunctionData({
      abi: mintAbi,
      functionName: 'mint',
      args: [0n, GIVE],
    });
    const nonce = await realSafe.read.nonce();
    const safeTxHash = await realSafe.read.getTransactionHash([
      target.address,
      0n,
      swapData,
      0,
      0n,
      0n,
      0n,
      ZERO_ADDRESS,
      ZERO_ADDRESS,
      nonce,
    ]);

    await realSafe.write.approveHash([safeTxHash], {
      account: signer.account,
    });
    await realSafe.write.approveHash([safeTxHash], {
      account: executor.account,
    });

    const humanOwners = [signer.account.address, executor.account.address];
    const humanSignatures = approvedHashSignatures(humanOwners);

    await expect(
      realSafe.write.execTransaction(
        [
          target.address,
          0n,
          swapData,
          0,
          0n,
          0n,
          0n,
          ZERO_ADDRESS,
          ZERO_ADDRESS,
          humanSignatures,
        ],
        { account: stranger.account },
      ),
    ).to.be.rejected;

    await expect(
      safeRouter.write.safeExecuteWithDiffs(
        [
          balanceProxy.address,
          [
            {
              target: realSafe.address,
              token: token.address,
              balance: GIVE + 1n,
            },
          ],
          realSafe.address,
          safeTx({
            to: target.address,
            data: swapData,
            signatures: humanSignatures,
            routerSigPosition: routerSignaturePosition(
              humanOwners,
              safeRouter.address,
            ),
          }),
        ],
        { account: executor.account },
      ),
    ).to.be.rejectedWith('ERC8009BalanceDiffConstraintViolation');

    expect(await token.read.balanceOf([realSafe.address])).to.equal(0n);
    expect(await realSafe.read.nonce()).to.equal(nonce);

    await expect(
      realSafe.write.execTransaction(
        [
          target.address,
          0n,
          swapData,
          0,
          0n,
          0n,
          0n,
          ZERO_ADDRESS,
          ZERO_ADDRESS,
          humanSignatures,
        ],
        { account: stranger.account },
      ),
    ).to.be.rejected;

    await safeRouter.write.safeExecuteWithDiffs(
      [
        balanceProxy.address,
        [{ target: realSafe.address, token: token.address, balance: GIVE }],
        realSafe.address,
        safeTx({
          to: target.address,
          data: swapData,
          signatures: humanSignatures,
          routerSigPosition: routerSignaturePosition(
            humanOwners,
            safeRouter.address,
          ),
        }),
      ],
      { account: executor.account },
    );

    expect(await token.read.balanceOf([realSafe.address])).to.equal(GIVE);
    expect(await realSafe.read.nonce()).to.equal(nonce + 1n);
  });

  it('supports a 3-of-5 Safe policy without counting the router owner as a human approval', async () => {
    const {
      owner,
      signer,
      executor,
      stranger,
      publicClient,
      balanceProxy,
      token,
      target,
      safeRouter,
    } = await loadFixture(deployFixture);
    const [, , , , fifthOwner] = await viem.getWalletClients();

    const singletonHash = await owner.deployContract({
      abi: safeArtifact.abi,
      bytecode: safeArtifact.bytecode as Hex,
    });
    const singletonReceipt = await publicClient.waitForTransactionReceipt({
      hash: singletonHash,
    });
    if (!singletonReceipt.contractAddress) {
      throw new Error('Safe singleton deployment did not return an address');
    }

    const proxyHash = await owner.deployContract({
      abi: safeProxyArtifact.abi,
      bytecode: safeProxyArtifact.bytecode as Hex,
      args: [singletonReceipt.contractAddress],
    });
    const proxyReceipt = await publicClient.waitForTransactionReceipt({
      hash: proxyHash,
    });
    if (!proxyReceipt.contractAddress) {
      throw new Error('Safe proxy deployment did not return an address');
    }

    const realSafe = await viem.getContractAt(
      'ISafe',
      proxyReceipt.contractAddress,
    );
    const humanOwners = [
      owner.account.address,
      signer.account.address,
      executor.account.address,
      stranger.account.address,
      fifthOwner.account.address,
    ];

    await realSafe.write.setup(
      [
        [...humanOwners, safeRouter.address],
        4n,
        ZERO_ADDRESS,
        '0x',
        ZERO_ADDRESS,
        ZERO_ADDRESS,
        0n,
        ZERO_ADDRESS,
      ],
      { account: owner.account },
    );

    const GIVE = parseEther('19');
    const swapData = encodeFunctionData({
      abi: mintAbi,
      functionName: 'mint',
      args: [0n, GIVE],
    });
    const nonce = await realSafe.read.nonce();
    const safeTxHash = await realSafe.read.getTransactionHash([
      target.address,
      0n,
      swapData,
      0,
      0n,
      0n,
      0n,
      ZERO_ADDRESS,
      ZERO_ADDRESS,
      nonce,
    ]);

    for (const account of [owner.account, signer.account]) {
      await realSafe.write.approveHash([safeTxHash], { account });
    }

    const twoHumanOwners = [owner.account.address, signer.account.address];
    await expect(
      safeRouter.write.safeExecuteWithDiffs(
        [
          balanceProxy.address,
          [{ target: realSafe.address, token: token.address, balance: GIVE }],
          realSafe.address,
          safeTx({
            to: target.address,
            data: swapData,
            signatures: approvedHashSignatures(twoHumanOwners),
            routerSigPosition: routerSignaturePosition(
              twoHumanOwners,
              safeRouter.address,
            ),
          }),
        ],
        { account: owner.account },
      ),
    ).to.be.rejectedWith('InsufficientSafeSignatures');

    await realSafe.write.approveHash([safeTxHash], {
      account: executor.account,
    });

    const threeHumanOwners = [
      owner.account.address,
      signer.account.address,
      executor.account.address,
    ];

    await safeRouter.write.safeExecuteWithDiffs(
      [
        balanceProxy.address,
        [{ target: realSafe.address, token: token.address, balance: GIVE }],
        realSafe.address,
        safeTx({
          to: target.address,
          data: swapData,
          signatures: approvedHashSignatures(threeHumanOwners),
          routerSigPosition: routerSignaturePosition(
            threeHumanOwners,
            safeRouter.address,
          ),
        }),
      ],
      { account: owner.account },
    );

    expect(await token.read.balanceOf([realSafe.address])).to.equal(GIVE);
    expect(await realSafe.read.nonce()).to.equal(nonce + 1n);

    const EXTRA_GIVE = parseEther('7');
    const extraSwapData = encodeFunctionData({
      abi: mintAbi,
      functionName: 'mint',
      args: [0n, EXTRA_GIVE],
    });
    const extraNonce = await realSafe.read.nonce();
    const extraSafeTxHash = await realSafe.read.getTransactionHash([
      target.address,
      0n,
      extraSwapData,
      0,
      0n,
      0n,
      0n,
      ZERO_ADDRESS,
      ZERO_ADDRESS,
      extraNonce,
    ]);

    for (const account of [
      owner.account,
      signer.account,
      executor.account,
      stranger.account,
    ]) {
      await realSafe.write.approveHash([extraSafeTxHash], { account });
    }

    const fourHumanOwners = [
      owner.account.address,
      signer.account.address,
      executor.account.address,
      stranger.account.address,
    ];
    const selectedOwners = sortOwners(fourHumanOwners).slice(0, 3);

    await safeRouter.write.safeExecuteWithDiffs(
      [
        balanceProxy.address,
        [
          {
            target: realSafe.address,
            token: token.address,
            balance: EXTRA_GIVE,
          },
        ],
        realSafe.address,
        safeTx({
          to: target.address,
          data: extraSwapData,
          signatures: approvedHashSignatures(fourHumanOwners),
          routerSigPosition: routerSignaturePosition(
            selectedOwners,
            safeRouter.address,
          ),
        }),
      ],
      { account: owner.account },
    );

    expect(await token.read.balanceOf([realSafe.address])).to.equal(
      GIVE + EXTRA_GIVE,
    );
    expect(await realSafe.read.nonce()).to.equal(nonce + 2n);
  });
});
