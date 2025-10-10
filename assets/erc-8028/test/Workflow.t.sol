pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {DataAnchoringToken} from "../src/dat/DataAnchoringToken.sol";
import {DataRegistry} from "../src/dataRegistry/DataRegistry.sol";
import {IDataRegistry} from "../src/dataRegistry/interfaces/IDataRegistry.sol";
import {VerifiedComputing} from "../src/verifiedComputing/VerifiedComputing.sol";
import {IVerifiedComputing} from "../src/verifiedComputing/interfaces/IVerifiedComputing.sol";
import {AIProcess} from "../src/process/AIProcess.sol";
import {Settlement} from "../src/settlement/Settlement.sol";
import {Deploy} from "../script/Deploy.s.sol";

contract WorkflowTest is Test {
    Deploy public deployer;
    VerifiedComputing vc;
    DataRegistry registry;
    AIProcess query;
    AIProcess inference;
    AIProcess training;
    Settlement settlement;
    address contributor;
    address node;
    address admin;
    string nodeUrl;

    function setUp() public {
        deployer = new Deploy();
        deployer.run();
        vc = deployer.vc();
        registry = deployer.registry();
        query = deployer.query();
        inference = deployer.inference();
        training = deployer.training();
        settlement = deployer.settlement();
        contributor = address(0x112233);
        node = address(0x34d9E02F9bB4E4C8836e38DF4320D4a79106F194);
        admin = deployer.admin();
        nodeUrl = "http://localhost:8866";
    }

    function test_verifiedComputingInitParams() public view {
        assertTrue(vc.hasRole(vc.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_dataRegistry() public {
        assertTrue(registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), admin));
        assertEq(registry.publicKey(), deployer.publicKey());
        assertEq(registry.version(), 1);
        vm.startPrank(contributor);
        assertEq(registry.addFile("file1", "46af43ea5090cb4b13142010065bc0bcc1c88eaf9c64cf5ce9739d934d145a35"), 1);
        vm.stopPrank();

        vm.startPrank(admin);
        vc.addNode(node, nodeUrl, "node public key");
        vc.updateNodeFee(100);
        vm.stopPrank();

        assertEq(vc.nodeFee(), 100);

        vm.startPrank(contributor);
        vm.deal(contributor, 10 ether);
        vc.requestProof{value: 100}(1);
        uint256[] memory ids = vc.fileJobIds(1);
        uint256 jobId = ids[0];
        IVerifiedComputing.Job memory job = vc.getJob(jobId);
        IVerifiedComputing.NodeInfo memory nodeInfo = vc.getNode(job.nodeAddress);
        assertEq(nodeInfo.publicKey, "node public key");
        vm.stopPrank();
        // For privacy data proof
        vm.startPrank(node);
        IDataRegistry.ProofData memory data = IDataRegistry.ProofData({id: 1, score: 1, fileUrl: "", proofUrl: ""});
        // address 0x34d9E02F9bB4E4C8836e38DF4320D4a79106F194 signature
        bytes memory signature =
            hex"fd10d06dda9347726b73eabfa7565524090f1d259a799a580a61fc0f54a52b347f958e9efe2ea35193f6924acd796eb0cdd2eda415f18fe438cdb8a88b541d4e1b";
        // Finish the Job
        vc.completeJob(jobId);
        vc.claim();
        // Add proof to the data registry
        registry.addProof(1, IDataRegistry.Proof({signature: signature, data: data}));
        vm.stopPrank();

        vm.startPrank(contributor);
        registry.requestReward(1, 1);
        vm.stopPrank();
    }

    function test_DataAnchoringToken() public {
        DataAnchoringToken token = deployer.token();
        address registryAddr = address(deployer.registry());
        vm.startPrank(registryAddr);
        assertTrue(token.hasRole(token.MINTER_ROLE(), registryAddr));
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        address receiver = address(0x112233);
        uint256 mintAmount = 1;
        string memory fileUrl = "https://ipfs.file.url";
        uint256 initialCounter = token.currentTokenId();
        assertEq(initialCounter, 0, "Initial counter should be 0");
        token.mint(receiver, mintAmount, fileUrl, false);
        vm.stopPrank();
        uint256 newCounter = token.currentTokenId();
        assertEq(newCounter, initialCounter + 1, "Counter should increment");
        assertEq(token.balanceOf(receiver, newCounter), mintAmount, "Balance mismatch");
        assertEq(token.fileUrl(newCounter), fileUrl, "File Url mismatch");
        assertEq(token.uri(newCounter), "https://lazai.network/token/{id}.json", "Token URI mismatch");
    }

    function test_Settlement() public {
        assertTrue(settlement.hasRole(settlement.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(query.hasRole(query.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(training.hasRole(training.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(inference.hasRole(inference.DEFAULT_ADMIN_ROLE(), admin));
        // Test inference and training node register
        vm.startPrank(admin);
        inference.addNode(node, nodeUrl, "node public key");
        vm.stopPrank();
        // Test user
        vm.startPrank(contributor);
        vm.deal(contributor, 10 ether);
        settlement.addUser{value: 10000}();
        settlement.deposit{value: 10000}();
        settlement.withdraw(2000);
        settlement.depositInference(node, 2000);
        AIProcess.Account memory account = inference.getAccount(contributor, node);
        assertEq(account.node, node);
        vm.stopPrank();
    }
}
