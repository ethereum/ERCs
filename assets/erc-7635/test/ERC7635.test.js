const {expect} = require("chai");
const {ethers} = require('hardhat');

describe("MFT", function () {
    let TestERC7635;
    let TestERC20;
    let TestERC721;

    before('deploy', async () => {
        const [deployer] = await ethers.getSigners();

        // ERC20 deploy
        const TestTokenFactory = await ethers.getContractFactory("TestERC20");
        TestERC20 = await TestTokenFactory.connect(deployer).deploy('TEST', 'TEST');

        // ERC721 deploy
        const TestNftFactory = await ethers.getContractFactory("TestERC721");
        TestERC721 = await TestNftFactory.connect(deployer).deploy('TEST', 'TEST');

        // MFT deploy
        const TestERC7635Factory = await ethers.getContractFactory("TestERC7635");
        TestERC7635 = await TestERC7635Factory.connect(deployer).deploy('TestERC7635', 'TestERC7635');

    })

    it('MFT-update', async () => {
        const [deployer, user1, user2] = await ethers.getSigners();

        await TestERC7635.connect(deployer).setMaxSupply(10000);

        // add slot-TestERC20
        await TestERC7635.connect(deployer).updateSlot(1, false, true, true, false, TestERC20.address, 'TEST-TOKEN');
        const slot1 = await TestERC7635.slots(1);
        expect(slot1.tokenAddress).to.eq(TestERC20.address);

        // add slot-TestERC721
        await TestERC7635.connect(deployer).updateSlot(2, false, true, true, true, TestERC721.address, 'TEST-NFT');
        const slot2 = await TestERC7635.slots(2);
        expect(slot2.tokenAddress).to.eq(TestERC721.address);

        // mint MFT
        await TestERC7635.mint(deployer.address, 1, 1, true);
        expect(await TestERC7635.ownerOf(1)).to.eq(deployer.address);

        await TestERC7635.mint(user1.address, 1, 1, true);
        expect(await TestERC7635.ownerOf(2)).to.eq(user1.address);

        await TestERC7635.mint(user2.address, 1, 1, false);
        expect(await TestERC7635.ownerOf(3)).to.eq(user2.address);
    })

    it('mintSoltValue', async () => {
        const [deployer, user1, user2] = await ethers.getSigners();

        // mint erc20
        await TestERC20.connect(deployer).mint(user1.address, 100);

        // mint erc721
        await TestERC721.connect(deployer).mint(user1.address);
        for (let i = 0; i < 5; i++) {
            await TestERC721.connect(deployer).mint(user2.address);
        }

        // erc20 approve
        await TestERC20.connect(user1).approve(TestERC7635.address, 100);
        // deposit
        await TestERC7635.connect(user1).deposit(2, 1, 100);
        expect(await TestERC7635['balanceOf(uint256,uint256)'](2, 1)).to.eq(100);

        // ERC721 approve
        await TestERC721.connect(user1).setApprovalForAll(TestERC7635.address, true);
        // deposit
        await TestERC7635.connect(user1).deposit(2, 2, 1);
        expect(await TestERC7635['balanceOf(uint256,uint256)'](2, 2)).to.eq(1);
        // nftBalanceOf
        const nftBalanceOf = await TestERC7635.nftBalanceOf(2, 2)
        console.log('nftBalanceOf', nftBalanceOf)

        // ERC721 approve
        await TestERC721.connect(user2).setApprovalForAll(TestERC7635.address, true);
        for (let i = 2; i <7; i++) {
            await TestERC7635.connect(user2).deposit(3, 2, i);
        }

        expect(await TestERC7635['balanceOf(uint256,uint256)'](3, 2)).to.eq(5);
        // nftBalanceOf
        const nftTokensOf2 = await TestERC7635.nftBalanceOf(3, 2)
        console.log('nftTokensOf2', nftTokensOf2)

    })

    it('transferFrom', async () => {
        const [deployer, user1, user2] = await ethers.getSigners();

        // transferFrom user1 to user2
        await TestERC7635.connect(user1)['transferFrom(address,address,uint256)'](user1.address, user2.address, 2);
        expect(await TestERC7635.ownerOf(2)).to.eq(user2.address);

        //  ERC20

        // slotIdex
        await TestERC7635.connect(user2)['transferFrom(uint256,uint256,uint256,uint256)'](2, 3, 1, 10);
        expect(await TestERC7635['balanceOf(uint256,uint256)'](2, 1)).to.eq(100 - 10);
        expect(await TestERC7635['balanceOf(uint256,uint256)'](3, 1)).to.eq(10);

        // tokenAddress_
        await TestERC7635.connect(user2)['transferFrom(uint256,uint256,address,uint256)'](2, 3, TestERC20.address, 10);
        expect(await TestERC7635['balanceOf(uint256,uint256)'](2, 1)).to.eq(100 - 10 - 10);
        expect(await TestERC7635['balanceOf(uint256,uint256)'](3, 1)).to.eq(10 + 10);

        // slot
        expect(await TestERC20['balanceOf(address)'](user2.address)).to.eq('0');
        await TestERC7635.connect(user2)['transferFrom(uint256,address,address,uint256)'](2, user2.address, TestERC20.address, 10);
        expect(await TestERC7635['balanceOf(uint256,uint256)'](2, 1)).to.eq(100 - 10 - 10 - 10);
        await TestERC7635.connect(user2)['transferFrom(uint256,address,uint256,uint256)'](2, user2.address, 1, 10);
        expect(await TestERC7635['balanceOf(uint256,uint256)'](2, 1)).to.eq(100 - 10 - 10 - 10 - 10);

        expect(await TestERC20['balanceOf(address)'](user2.address)).to.eq('20');

        // ERC721
        // slotIdex
        await TestERC7635.connect(user2)['transferFrom(uint256,uint256,uint256,uint256)'](3, 2, 2, 2);
        expect(await TestERC7635['balanceOf(uint256,uint256)'](3, 2)).to.eq(5 - 1);
        expect(await TestERC7635['balanceOf(uint256,uint256)'](2, 2)).to.eq(1 + 1);

        // tokenAddress_
        await TestERC7635.connect(user2)['transferFrom(uint256,uint256,address,uint256)'](3, 2, TestERC721.address, 3);
        expect(await TestERC7635['balanceOf(uint256,uint256)'](3, 2)).to.eq(5 - 1 - 1);
        expect(await TestERC7635['balanceOf(uint256,uint256)'](2, 2)).to.eq(1 + 1 + 1);
        const nftTokensO3 = await TestERC7635.nftBalanceOf(2, 2)
        console.log('nftTokensO3', nftTokensO3)

        // slot
        expect(await TestERC721['balanceOf(address)'](user2.address)).to.eq('0');

        await TestERC7635.connect(user2)['transferFrom(uint256,address,address,uint256)'](2, user2.address, TestERC721.address, 2);
        expect(await TestERC7635['balanceOf(uint256,uint256)'](2, 2)).to.eq(3 - 1);
        await TestERC7635.connect(user2)['transferFrom(uint256,address,uint256,uint256)'](2, user2.address, 2, 3);
        expect(await TestERC7635['balanceOf(uint256,uint256)'](2, 2)).to.eq(3 - 1 - 1);

        expect(await TestERC721['balanceOf(address)'](user2.address)).to.eq('2');
    })

    it('Approved', async () => {
        const [deployer, user1, user2] = await ethers.getSigners();

        // approve
        await TestERC7635.connect(user2)['approve(uint256,uint256,address,uint256)'](3, 2, user1.address, 6);
        const getApproved = await TestERC7635['getApproved(uint256,uint256,uint256)'](3, 2,6)
        console.log('getApproved', getApproved)
        await TestERC7635.connect(user1)['transferFrom(uint256,uint256,address,uint256)'](3, 2, TestERC721.address, 6);

    })
});
