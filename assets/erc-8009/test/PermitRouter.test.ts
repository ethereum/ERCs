import { loadFixture } from '@nomicfoundation/hardhat-toolbox-viem/network-helpers';
import { expect } from 'chai';
import { viem, ignition } from 'hardhat';
import { encodeFunctionData, parseEther } from 'viem';

import BalanceProxyModule from '@/ignition/modules/balance-proxy';

const targetAbi = [
  {
    inputs: [{ internalType: 'address', name: '_erc20', type: 'address' }],
    stateMutability: 'nonpayable',
    type: 'constructor',
  },
  {
    inputs: [
      { internalType: 'uint256', name: 'take', type: 'uint256' },
      { internalType: 'uint256', name: 'give', type: 'uint256' },
    ],
    name: 'mint',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
] as const;

function encodeMint(take: bigint, give: bigint) {
  return encodeFunctionData({
    abi: targetAbi,
    functionName: 'mint',
    args: [take, give],
  });
}

describe('PermitRouter', function () {
  type PermitToken = {
    address: `0x${string}`;
    read: {
      name: () => Promise<string>;
      nonces: (args: [`0x${string}`]) => Promise<bigint>;
    };
  };
  type TestWallet = {
    account: { address: `0x${string}` };
    getChainId: () => Promise<number>;
    signTypedData: (args: {
      domain: {
        name: string;
        version: string;
        chainId: number;
        verifyingContract: `0x${string}`;
      };
      types: { Permit: Array<{ name: string; type: string }> };
      primaryType: 'Permit';
      message: {
        owner: `0x${string}`;
        spender: `0x${string}`;
        value: bigint;
        nonce: bigint;
        deadline: bigint;
      };
    }) => Promise<`0x${string}`>;
  };

  async function buildPermit(
    user: TestWallet,
    token: PermitToken,
    spender: `0x${string}`,
    value: bigint,
  ) {
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);
    const nonce = await token.read.nonces([user.account.address]);
    const domain = {
      name: await token.read.name(),
      version: '1',
      chainId: await user.getChainId(),
      verifyingContract: token.address,
    };
    const types = {
      Permit: [
        { name: 'owner', type: 'address' },
        { name: 'spender', type: 'address' },
        { name: 'value', type: 'uint256' },
        { name: 'nonce', type: 'uint256' },
        { name: 'deadline', type: 'uint256' },
      ],
    };
    const message = {
      owner: user.account.address,
      spender,
      value,
      nonce,
      deadline,
    };
    const signature = await user.signTypedData({
      domain,
      types,
      primaryType: 'Permit',
      message,
    });
    const r = `0x${signature.slice(2, 66)}` as `0x${string}`;
    const s = `0x${signature.slice(66, 130)}` as `0x${string}`;
    const v = parseInt(signature.slice(130, 132), 16);
    return { deadline, v, r, s };
  }

  async function deployFixture() {
    const [owner, user, other] = await viem.getWalletClients();

    const { balanceProxy } = await ignition.deploy(BalanceProxyModule, {
      defaultSender: owner.account.address,
    });

    const token = await viem.deployContract('ERC20Mock', ['MockToken', 'MTK'], {
      client: { wallet: owner },
    });

    const target = await viem.deployContract('TargetMock', [token.address], {
      client: { wallet: owner },
    });

    const permitRouter = await viem.deployContract('PermitRouter', [], {
      client: { wallet: owner },
    });

    return { owner, user, other, balanceProxy, token, target, permitRouter };
  }

  it('reverts on permits length mismatch in permitProxyCall', async () => {
    const { user, balanceProxy, token, target, permitRouter } =
      await loadFixture(deployFixture);

    const AMOUNT = parseEther('10');
    await token.write.mint([user.account.address, AMOUNT]);

    const approval = {
      balance: {
        target: target.address,
        token: token.address,
        balance: AMOUNT,
      },
      useTransfer: false,
    };

    await expect(
      permitRouter.write.permitProxyCall(
        [
          balanceProxy.address,
          [],
          [approval],
          [], // permits empty -> mismatch
          target.address,
          '0x',
          [],
        ],
        { account: user.account },
      ),
    ).to.be.rejectedWith('PermitsLengthMismatch');
  });

  it('reverts on permits length mismatch in permitProxyCallDiffs', async () => {
    const { user, balanceProxy, token, target, permitRouter } =
      await loadFixture(deployFixture);

    const AMOUNT = parseEther('10');
    await token.write.mint([user.account.address, AMOUNT]);

    const approval = {
      balance: {
        target: target.address,
        token: token.address,
        balance: AMOUNT,
      },
      useTransfer: false,
    };

    await expect(
      permitRouter.write.permitProxyCallDiffs(
        [
          balanceProxy.address,
          [],
          [approval],
          [], // permits empty -> mismatch
          target.address,
          '0x',
          [],
        ],
        { account: user.account },
      ),
    ).to.be.rejectedWith('PermitsLengthMismatch');
  });

  it('supports permitProxyCallDiffs success path (net positive diff)', async () => {
    const { user, balanceProxy, token, target, permitRouter } =
      await loadFixture(deployFixture);

    const TAKE = parseEther('10');
    const GIVE = parseEther('25');

    await token.write.mint([user.account.address, TAKE]);

    const permit = await buildPermit(
      user,
      token as unknown as PermitToken,
      permitRouter.address,
      TAKE,
    );

    await permitRouter.write.permitProxyCallDiffs(
      [
        balanceProxy.address,
        [
          {
            target: balanceProxy.address,
            token: token.address,
            balance: GIVE - TAKE, // expect at least GIVE - TAKE net increase
          },
        ],
        [
          {
            balance: {
              target: target.address,
              token: token.address,
              balance: TAKE,
            },
            useTransfer: false,
          },
        ],
        [permit],
        target.address,
        encodeMint(TAKE, GIVE),
        [],
      ],
      { account: user.account },
    );

    const bal = await token.read.balanceOf([balanceProxy.address]);
    expect(bal).to.equal(GIVE);
  });

  it('handles multiple approvals and permits', async () => {
    const { user, balanceProxy, token, target, permitRouter } =
      await loadFixture(deployFixture);

    const A1 = parseEther('7');
    const A2 = parseEther('5');
    await token.write.mint([user.account.address, A1 + A2]);

    // Build two permits with sequential nonces for the same owner/spender
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);
    const baseNonce = await (token as unknown as PermitToken).read.nonces([
      user.account.address,
    ]);
    const domain = {
      name: await (token as unknown as PermitToken).read.name(),
      version: '1',
      chainId: await user.getChainId(),
      verifyingContract: token.address as `0x${string}`,
    };
    const types: { Permit: Array<{ name: string; type: string }> } = {
      Permit: [
        { name: 'owner', type: 'address' },
        { name: 'spender', type: 'address' },
        { name: 'value', type: 'uint256' },
        { name: 'nonce', type: 'uint256' },
        { name: 'deadline', type: 'uint256' },
      ],
    };
    const sign = async (value: bigint, nonce: bigint) => {
      const signature = await user.signTypedData({
        domain,
        types,
        primaryType: 'Permit',
        message: {
          owner: user.account.address,
          spender: permitRouter.address,
          value,
          nonce,
          deadline,
        },
      });
      const r = `0x${signature.slice(2, 66)}` as `0x${string}`;
      const s = `0x${signature.slice(66, 130)}` as `0x${string}`;
      const v = parseInt(signature.slice(130, 132), 16);
      return { deadline, v, r, s };
    };

    const p1 = await sign(A1, baseNonce);
    const p2 = await sign(A2, baseNonce + 1n);

    await permitRouter.write.permitProxyCall(
      [
        balanceProxy.address,
        [],
        [
          {
            balance: {
              target: target.address,
              token: token.address,
              balance: A1,
            },
            useTransfer: false, // set allowance on proxy for target
          },
          {
            balance: {
              target: target.address,
              token: token.address,
              balance: A2,
            },
            useTransfer: true, // direct transfer to target
          },
        ],
        [p1, p2],
        target.address,
        '0x',
        [],
      ],
      { account: user.account },
    );

    const targetBal = await token.read.balanceOf([target.address]);
    expect(targetBal).to.equal(A2);

    const allowance = await token.read.allowance([
      balanceProxy.address,
      target.address,
    ]);
    expect(allowance).to.equal(A1);
  });
});
