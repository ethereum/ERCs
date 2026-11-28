import { loadFixture } from '@nomicfoundation/hardhat-toolbox-viem/network-helpers';
import { expect } from 'chai';
import { viem, ignition } from 'hardhat';
import { encodeFunctionData, erc20Abi, parseEther } from 'viem';

import BalanceProxyModule from '@/ignition/modules/balance-proxy';

// TargetMock ABI subset used for encoding
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
  {
    inputs: [
      { internalType: 'uint256', name: 'take', type: 'uint256' },
      { internalType: 'uint256', name: 'give', type: 'uint256' },
    ],
    name: 'mintEth',
    outputs: [],
    stateMutability: 'payable',
    type: 'function',
  },
] as const;

// ReenterTargetMock ABI subset
const reenterAbi = [
  {
    inputs: [],
    name: 'attack',
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

function encodeMintEth(take: bigint, give: bigint) {
  return encodeFunctionData({
    abi: targetAbi,
    functionName: 'mintEth',
    args: [take, give],
  });
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
  const approveRouter = await viem.deployContract('ApproveRouter', [], {
    client: { wallet: owner },
  });
  const permitRouter = await viem.deployContract('PermitRouter', [], {
    client: { wallet: owner },
  });
  const publicClient = await viem.getPublicClient();
  return {
    owner,
    user,
    other,
    balanceProxy,
    token,
    target,
    approveRouter,
    permitRouter,
    publicClient,
  };
}

describe('BalanceProxy + Routers (updated API)', function () {
  this.timeout(120000);
  it('deploys core & routers', async () => {
    const { balanceProxy, approveRouter, permitRouter } =
      await loadFixture(deployFixture);
    expect(balanceProxy.address).to.be.a('string');
    expect(approveRouter.address).to.be.a('string');
    expect(permitRouter.address).to.be.a('string');
  });

  it('reverts InsufficientBalance when postBalance (ETH) expects more than actual', async () => {
    const { owner, user, token, target, balanceProxy, approveRouter } =
      await loadFixture(deployFixture);
    const TAKE = parseEther('5');
    const GIVE_ETH = parseEther('2');
    await token.write.mint([user.account.address, TAKE]);
    await owner.sendTransaction({ to: target.address, value: GIVE_ETH });
    await token.write.approve([approveRouter.address, TAKE], {
      account: user.account,
    });
    await expect(
      approveRouter.write.approveProxyCall(
        [
          balanceProxy.address,
          [
            {
              target: balanceProxy.address,
              token: '0x0000000000000000000000000000000000000000',
              balance: GIVE_ETH + 1n,
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
          target.address,
          encodeMintEth(TAKE, GIVE_ETH),
          [],
        ],
        { account: user.account },
      ),
    ).to.be.rejected;
  });

  it('withdraws ETH and checks postBalance for ETH', async () => {
    const { owner, user, other, token, target, balanceProxy, approveRouter } =
      await loadFixture(deployFixture);
    const TAKE = parseEther('10');
    const GIVE_ETH = parseEther('3');
    await token.write.mint([user.account.address, TAKE]);
    // fund target so it can pay ETH to proxy
    await owner.sendTransaction({ to: target.address, value: GIVE_ETH });
    await token.write.approve([approveRouter.address, TAKE], {
      account: user.account,
    });
    await approveRouter.write.approveProxyCall(
      [
        balanceProxy.address,
        [
          {
            target: balanceProxy.address,
            token: '0x0000000000000000000000000000000000000000',
            balance: 0n,
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
        target.address,
        encodeMintEth(TAKE, GIVE_ETH),
        [
          {
            target: other.account.address,
            token: '0x0000000000000000000000000000000000000000',
            balance: GIVE_ETH,
          },
        ],
      ],
      { account: user.account },
    );
    const pc = await viem.getPublicClient();
    const proxyEth = await pc.getBalance({ address: balanceProxy.address });
    expect(proxyEth).to.equal(0n);
  });
});

describe('PermitRouter.permitProxyCall', () => {
  // Narrow interfaces to avoid using `any`
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
      types: {
        Permit: Array<{ name: string; type: string }>;
      };
      primaryType: 'Permit';
      message: {
        owner: `0x${string}`;
        spender: `0x${string}`;
        value: bigint;
        nonce: bigint;
        deadline: bigint;
      };
    }) => Promise<`0x${string}`>; // viem wallet client signature helper
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

  it('approve mode with permit pulls tokens & sets allowance', async () => {
    const { user, token, target, balanceProxy, permitRouter } =
      await loadFixture(deployFixture);
    const AMOUNT = parseEther('25');
    await token.write.mint([user.account.address, AMOUNT]);
    const permit = await buildPermit(user, token, permitRouter.address, AMOUNT);
    await permitRouter.write.permitProxyCall(
      [
        balanceProxy.address,
        [],
        [
          {
            balance: {
              target: target.address,
              token: token.address,
              balance: AMOUNT,
            },
            useTransfer: false,
          },
        ],
        [permit],
        target.address,
        '0x',
        [],
      ],
      { account: user.account },
    );
    const proxyBal = await token.read.balanceOf([balanceProxy.address]);
    expect(proxyBal).to.equal(AMOUNT);
    const allowance = await token.read.allowance([
      balanceProxy.address,
      target.address,
    ]);
    expect(allowance).to.equal(AMOUNT);
  });

  it('transfer mode with permit moves tokens to target', async () => {
    const { user, token, target, balanceProxy, permitRouter } =
      await loadFixture(deployFixture);
    const AMOUNT = parseEther('40');
    await token.write.mint([user.account.address, AMOUNT]);
    const permit = await buildPermit(user, token, permitRouter.address, AMOUNT);
    await permitRouter.write.permitProxyCall(
      [
        balanceProxy.address,
        [],
        [
          {
            balance: {
              target: target.address,
              token: token.address,
              balance: AMOUNT,
            },
            useTransfer: true,
          },
        ],
        [permit],
        target.address,
        '0x',
        [],
      ],
      { account: user.account },
    );
    const targetBal = await token.read.balanceOf([target.address]);
    expect(targetBal).to.equal(AMOUNT);
  });
});

describe('Error: CallFailed', () => {
  it('reverts when calling non-existent function on target', async () => {
    const { user, token, target, balanceProxy, approveRouter } =
      await loadFixture(deployFixture);
    const AMOUNT = parseEther('5');
    await token.write.mint([user.account.address, AMOUNT]);
    await token.write.approve([approveRouter.address, AMOUNT], {
      account: user.account,
    });
    // encode ERC20 transfer (target does not implement) => should revert
    const data = encodeFunctionData({
      abi: erc20Abi,
      functionName: 'transfer',
      args: [target.address, AMOUNT],
    });
    await expect(
      approveRouter.write.approveProxyCall(
        [
          balanceProxy.address,
          [],
          [
            {
              balance: {
                target: target.address,
                token: token.address,
                balance: AMOUNT,
              },
              useTransfer: false,
            },
          ],
          target.address,
          data,
          [],
        ],
        { account: user.account },
      ),
    ).to.be.rejectedWith('CallFailed');
  });

  it('reverts when calling non-existent function on target via proxyCallDiffs', async () => {
    const { user, target, balanceProxy, approveRouter } =
      await loadFixture(deployFixture);
    const data = encodeFunctionData({
      abi: erc20Abi,
      functionName: 'transfer',
      args: [target.address, 1n],
    });
    await expect(
      approveRouter.write.approveProxyCallDiffs(
        [
          balanceProxy.address,
          [], // diffs
          [], // approvals
          target.address,
          data,
          [],
        ],
        { account: user.account },
      ),
    ).to.be.rejectedWith('CallFailed');
  });
});

describe('proxyCallDiffs via ApproveRouter', () => {
  it('checks expected diffs (positive balance increase)', async () => {
    const { user, token, target, balanceProxy, approveRouter } =
      await loadFixture(deployFixture);
    const TAKE = parseEther('10');
    const GIVE = parseEther('15');
    await token.write.mint([user.account.address, TAKE]);
    await token.write.approve([approveRouter.address, TAKE], {
      account: user.account,
    });
    // Expect proxy balance diff >= GIVE (after mint it receives GIVE tokens)
    await approveRouter.write.approveProxyCallDiffs(
      [
        balanceProxy.address,
        [
          {
            target: balanceProxy.address,
            token: token.address,
            balance: GIVE - TAKE, // net balance increase expected (GIVE - TAKE)
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
        target.address,
        encodeMint(TAKE, GIVE),
        [],
      ],
      { account: user.account },
    );
    const bal = await token.read.balanceOf([balanceProxy.address]);
    expect(bal).to.equal(GIVE); // TAKE was spent, GIVE minted
  });

  it('handles ETH diff zero success path', async () => {
    const { user, other, balanceProxy, approveRouter } =
      await loadFixture(deployFixture);
    // Target an EOA with empty data so the low-level call succeeds; no state change => diff 0
    await approveRouter.write.approveProxyCallDiffs(
      [
        balanceProxy.address,
        [
          {
            target: balanceProxy.address,
            token: '0x0000000000000000000000000000000000000000',
            balance: 0n,
          },
        ],
        [],
        other.account.address,
        '0x',
        [],
      ],
      { account: user.account },
    );
  });
});

describe('ApproveRouter WithMeta', () => {
  it('approveProxyCallWithMeta: pulls tokens and sets allowance (meta ignored)', async () => {
    const { user, token, target, balanceProxy, approveRouter } =
      await loadFixture(deployFixture);
    const AMOUNT = parseEther('33');
    await token.write.mint([user.account.address, AMOUNT]);
    await token.write.approve([approveRouter.address, AMOUNT], {
      account: user.account,
    });

    const meta = [
      {
        symbol: 'MTK',
        decimals: 18,
      },
    ];

    const balances = [
      {
        target: balanceProxy.address,
        token: token.address,
        balance: AMOUNT,
      },
    ];

    await approveRouter.write.approveProxyCallWithMeta(
      [
        balanceProxy.address,
        meta,
        balances,
        [
          {
            balance: {
              target: target.address,
              token: token.address,
              balance: AMOUNT,
            },
            useTransfer: false,
          },
        ],
        target.address,
        encodeMint(0n, 0n),
        [],
      ],
      { account: user.account },
    );

    const proxyBal = await token.read.balanceOf([balanceProxy.address]);
    expect(proxyBal).to.equal(AMOUNT);
    const allowance = await token.read.allowance([
      balanceProxy.address,
      target.address,
    ]);
    expect(allowance).to.equal(AMOUNT);
  });

  it('approveProxyCallDiffsWithMeta: transfer mode sends tokens to EOA target', async () => {
    const { user, token, other, balanceProxy, approveRouter } =
      await loadFixture(deployFixture);
    const AMOUNT = parseEther('21');
    await token.write.mint([user.account.address, AMOUNT]);
    await token.write.approve([approveRouter.address, AMOUNT], {
      account: user.account,
    });

    const meta = [
      {
        symbol: 'MTK',
        decimals: 18,
      },
    ];

    const diffs = [
      {
        target: other.account.address,
        token: token.address,
        balance: AMOUNT,
      },
    ];

    await approveRouter.write.approveProxyCallDiffsWithMeta(
      [
        balanceProxy.address,
        meta,
        diffs,
        [
          {
            balance: {
              target: other.account.address,
              token: token.address,
              balance: AMOUNT,
            },
            useTransfer: true,
          },
        ],
        other.account.address, // EOA target, empty data succeeds
        '0x',
        [],
      ],
      { account: user.account },
    );

    const targetBal = await token.read.balanceOf([other.account.address]);
    expect(targetBal).to.equal(AMOUNT);
  });
});

describe('withdrawals loop executes (direct proxyCall)', () => {
  it('sends ETH via withdrawals and reduces proxy balance', async () => {
    const { owner, user, other, balanceProxy } =
      await loadFixture(deployFixture);
    // fund proxy with 5 wei
    await owner.sendTransaction({ to: balanceProxy.address, value: 5n });
    // withdraw 3 wei to `other`
    await balanceProxy.write.proxyCall(
      [
        [],
        [],
        other.account.address,
        '0x',
        [
          {
            target: other.account.address,
            token: '0x0000000000000000000000000000000000000000',
            balance: 3n,
          },
        ],
      ],
      { account: user.account },
    );
    const pc = await viem.getPublicClient();
    const proxyEth = await pc.getBalance({ address: balanceProxy.address });
    expect(proxyEth).to.equal(2n);
  });

  it('sends ERC20 via withdrawals from proxy balance', async () => {
    const { owner, user, token, other, balanceProxy } =
      await loadFixture(deployFixture);
    const AMT = parseEther('10');
    const OUT = parseEther('4');
    await token.write.mint([balanceProxy.address, AMT], {
      account: owner.account,
    });
    await balanceProxy.write.proxyCall(
      [
        [],
        [],
        other.account.address,
        '0x',
        [
          {
            target: user.account.address,
            token: token.address,
            balance: OUT,
          },
        ],
      ],
      { account: user.account },
    );
    const proxyBal = await token.read.balanceOf([balanceProxy.address]);
    const userBal = await token.read.balanceOf([user.account.address]);
    expect(proxyBal).to.equal(AMT - OUT);
    expect(userBal).to.equal(OUT);
  });
});

describe('withdrawals loop executes (proxyCallDiffs path)', () => {
  it('sends ETH via withdrawals inside proxyCallDiffs', async () => {
    const { owner, user, other, balanceProxy } =
      await loadFixture(deployFixture);
    const pc = await viem.getPublicClient();
    // fund proxy with 5 wei
    await owner.sendTransaction({ to: balanceProxy.address, value: 5n });
    const beforeProxy = await pc.getBalance({
      address: balanceProxy.address,
    });
    const beforeOther = await pc.getBalance({
      address: other.account.address,
    });

    await balanceProxy.write.proxyCallDiffs(
      [
        [], // diffs
        [], // approvals
        other.account.address, // target: EOA call succeeds
        '0x',
        [
          {
            target: other.account.address,
            token: '0x0000000000000000000000000000000000000000',
            balance: 3n,
          },
        ],
      ],
      { account: user.account },
    );

    const afterProxy = await pc.getBalance({
      address: balanceProxy.address,
    });
    const afterOther = await pc.getBalance({
      address: other.account.address,
    });
    expect(beforeProxy - afterProxy).to.equal(3n);
    expect(afterOther - beforeOther).to.equal(3n);
  });
});

describe('PermitRouter WithMeta', () => {
  // Local helper duplicating buildPermit to keep scope self-contained
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
      types: {
        Permit: Array<{ name: string; type: string }>;
      };
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

  it('permitProxyCallWithMeta: pulls tokens and sets allowance (meta ignored)', async () => {
    const { user, token, target, balanceProxy, permitRouter } =
      await loadFixture(deployFixture);
    const AMOUNT = parseEther('19');
    await token.write.mint([user.account.address, AMOUNT]);
    const permit = await buildPermit(
      user as unknown as TestWallet,
      token as unknown as PermitToken,
      permitRouter.address,
      AMOUNT,
    );

    const meta = [
      {
        symbol: 'MTK',
        decimals: 18,
      },
    ];

    const balances = [
      {
        target: balanceProxy.address,
        token: token.address,
        balance: AMOUNT,
      },
    ];

    await permitRouter.write.permitProxyCallWithMeta(
      [
        balanceProxy.address,
        meta,
        balances,
        [
          {
            balance: {
              target: target.address,
              token: token.address,
              balance: AMOUNT,
            },
            useTransfer: false,
          },
        ],
        [permit],
        target.address,
        '0x',
        [],
      ],
      { account: user.account },
    );

    const proxyBal = await token.read.balanceOf([balanceProxy.address]);
    expect(proxyBal).to.equal(AMOUNT);
    const allowance = await token.read.allowance([
      balanceProxy.address,
      target.address,
    ]);
    expect(allowance).to.equal(AMOUNT);
  });

  it('permitProxyCallDiffsWithMeta: transfer mode sends tokens to EOA target', async () => {
    const { user, token, other, balanceProxy, permitRouter } =
      await loadFixture(deployFixture);
    const AMOUNT = parseEther('13');
    await token.write.mint([user.account.address, AMOUNT]);
    const permit = await buildPermit(
      user as unknown as TestWallet,
      token as unknown as PermitToken,
      permitRouter.address,
      AMOUNT,
    );

    const meta = [
      {
        symbol: 'MTK',
        decimals: 18,
      },
    ];

    const diffs = [
      {
        target: other.account.address,
        token: token.address,
        balance: AMOUNT,
      },
    ];

    await permitRouter.write.permitProxyCallDiffsWithMeta(
      [
        balanceProxy.address,
        meta,
        diffs,
        [
          {
            balance: {
              target: other.account.address,
              token: token.address,
              balance: AMOUNT,
            },
            useTransfer: true,
          },
        ],
        [permit],
        other.account.address,
        '0x',
        [],
      ],
      { account: user.account },
    );

    const targetBal = await token.read.balanceOf([other.account.address]);
    expect(targetBal).to.equal(AMOUNT);
  });

  it('permitProxyCallWithMeta: reverts on PermitsLengthMismatch', async () => {
    const { user, token, target, balanceProxy, permitRouter } =
      await loadFixture(deployFixture);
    const AMOUNT = parseEther('7');
    await token.write.mint([user.account.address, AMOUNT]);

    const meta = [
      {
        symbol: 'MTK',
        decimals: 18,
      },
    ];

    const balances = [
      {
        target: balanceProxy.address,
        token: token.address,
        balance: AMOUNT,
      },
    ];

    await expect(
      permitRouter.write.permitProxyCallWithMeta(
        [
          balanceProxy.address,
          meta,
          balances,
          [
            {
              balance: {
                target: target.address,
                token: token.address,
                balance: AMOUNT,
              },
              useTransfer: false,
            },
          ],
          [], // permits empty => mismatch
          target.address,
          '0x',
          [],
        ],
        { account: user.account },
      ),
    ).to.be.rejectedWith('PermitsLengthMismatch');
  });

  it('permitProxyCallDiffsWithMeta: reverts on PermitsLengthMismatch', async () => {
    const { user, token, other, balanceProxy, permitRouter } =
      await loadFixture(deployFixture);
    const AMOUNT = parseEther('5');
    await token.write.mint([user.account.address, AMOUNT]);

    const meta = [
      {
        symbol: 'MTK',
        decimals: 18,
      },
    ];

    const diffs = [
      {
        target: other.account.address,
        token: token.address,
        balance: AMOUNT,
      },
    ];

    await expect(
      permitRouter.write.permitProxyCallDiffsWithMeta(
        [
          balanceProxy.address,
          meta,
          diffs,
          [
            {
              balance: {
                target: other.account.address,
                token: token.address,
                balance: AMOUNT,
              },
              useTransfer: true,
            },
          ],
          [], // permits empty => mismatch
          other.account.address,
          '0x',
          [],
        ],
        { account: user.account },
      ),
    ).to.be.rejectedWith('PermitsLengthMismatch');
  });
});

describe('internal _balanceCheckCalldata via tester', () => {
  it('covers ETH path (sufficient balance: no revert)', async () => {
    const { owner, user } = await loadFixture(deployFixture);
    // deploy tester
    const tester = await viem.deployContract('BalanceProxyTester', [], {
      client: { wallet: owner },
    });
    // fund user with a bit of ETH
    await owner.sendTransaction({ to: user.account.address, value: 10n });
    // call with token=address(0), target=user, expected <= actual
    await tester.read.exposeBalanceCheckCalldata([
      {
        target: user.account.address,
        token: '0x0000000000000000000000000000000000000000',
        balance: 1n,
      },
    ]);
  });

  it('covers ETH path (insufficient balance: revert)', async () => {
    const { owner } = await loadFixture(deployFixture);
    const tester = await viem.deployContract('BalanceProxyTester', [], {
      client: { wallet: owner },
    });
    // tester has 0 ETH; expect revert when requiring > 0
    await expect(
      tester.read.exposeBalanceCheckCalldata([
        {
          target: tester.address,
          token: '0x0000000000000000000000000000000000000000',
          balance: 1n,
        },
      ]),
    ).to.be.rejected;
  });

  it('covers ERC20 path (insufficient balance: revert)', async () => {
    const { owner, user, token } = await loadFixture(deployFixture);
    const tester = await viem.deployContract('BalanceProxyTester', [], {
      client: { wallet: owner },
    });
    await expect(
      tester.read.exposeBalanceCheckCalldata([
        {
          target: user.account.address,
          token: token.address,
          balance: 1n, // user has 0 tokens
        },
      ]),
    ).to.be.rejected;
  });

  it('covers ERC20 path (sufficient balance: no revert)', async () => {
    const { owner, user, token } = await loadFixture(deployFixture);
    const tester = await viem.deployContract('BalanceProxyTester', [], {
      client: { wallet: owner },
    });
    // mint token to user so balance >= expected
    await token.write.mint([user.account.address, 5n]);
    await tester.read.exposeBalanceCheckCalldata([
      {
        target: user.account.address,
        token: token.address,
        balance: 1n,
      },
    ]);
  });
});

describe('BalanceProxy core error paths', () => {
  it('reverts on NegativeApprovalAmount via direct proxyCall', async () => {
    const { user, balanceProxy, target } = await loadFixture(deployFixture);
    await expect(
      balanceProxy.write.proxyCall(
        [
          [],
          [
            {
              balance: {
                target: target.address,
                token: '0x0000000000000000000000000000000000000000',
                balance: -1n,
              },
              useTransfer: false,
            },
          ],
          target.address,
          '0x',
          [],
        ],
        { account: user.account },
      ),
    ).to.be.rejected;
  });

  it('reverts UnexpectedBalanceDiff when expected diff not met', async () => {
    const { user, balanceProxy, target } = await loadFixture(deployFixture);
    await expect(
      balanceProxy.write.proxyCallDiffs(
        [
          [
            {
              target: balanceProxy.address,
              token: '0x0000000000000000000000000000000000000000',
              balance: 1n,
            },
          ],
          [],
          target.address,
          '0x',
          [],
        ],
        { account: user.account },
      ),
    ).to.be.rejected;
  });

  it('reverts when ETH withdrawal cannot be paid (negative withdrawal from empty proxy)', async () => {
    const { user, other, balanceProxy } = await loadFixture(deployFixture);
    // Call succeeds (EOA target), then withdrawal tries to send 1 wei from proxy (has 0) => revert
    await expect(
      balanceProxy.write.proxyCall(
        [
          [],
          [],
          other.account.address,
          '0x',
          [
            {
              target: user.account.address,
              token: '0x0000000000000000000000000000000000000000',
              balance: -1n,
            },
          ],
        ],
        { account: user.account },
      ),
    ).to.be.rejected;
  });

  it('reverts on reentrancy (nonReentrant guard)', async () => {
    const { owner, user, balanceProxy } = await loadFixture(deployFixture);
    const reenter = await viem.deployContract(
      'ReenterTargetMock',
      [balanceProxy.address],
      {
        client: { wallet: owner },
      },
    );
    const attackData = encodeFunctionData({
      abi: reenterAbi,
      functionName: 'attack',
      args: [],
    });
    await expect(
      balanceProxy.write.proxyCall(
        [
          [], // postBalances
          [], // approvals
          reenter.address,
          attackData,
          [],
        ],
        { account: user.account },
      ),
    ).to.be.rejectedWith('CallFailed');
  });

  it('reverts on reentrancy in proxyCallDiffs (nonReentrant guard)', async () => {
    const { owner, user, balanceProxy } = await loadFixture(deployFixture);
    const reenter = await viem.deployContract(
      'ReenterDiffsTargetMock',
      [balanceProxy.address],
      {
        client: { wallet: owner },
      },
    );
    const attackData = encodeFunctionData({
      abi: reenterAbi,
      functionName: 'attack',
      args: [],
    });
    await expect(
      balanceProxy.write.proxyCallDiffs(
        [
          [], // diffs
          [], // approvals
          reenter.address,
          attackData,
          [],
        ],
        { account: user.account },
      ),
    ).to.be.rejectedWith('CallFailed');
  });
});
