// Importing necessary libraries
const express = require('express');
const Web3 = require('web3');
const ethUtil = require('ethereumjs-util');

// Initializing web3 to connect to the Ethereum node
const web3 = new Web3('YOUR_ETH_NODE_URL');

// Loading the smart contract ABI
const contractABI = require('./ABI.json');

// Instantiating the smart contract object
const contractAddress = 'CONTRACT_ADDRESS';
const contract = new web3.eth.Contract(contractABI, contractAddress);

// Creating an Express app
const app = express();
const port = 3000;

// API endpoint to check authorization and get file download URIs
app.get('/api/access', async (req, res) => {
    try {
        const userAddress = req.query.address;
        const signature = req.query.signature;
        const message = 'Authorization check for download access';

        // Verifying the signature
        const messageHash = web3.utils.sha3(message);
        const sigParams = ethUtil.fromRpcSig(signature);
        const publicKey = ethUtil.ecrecover(ethUtil.toBuffer(messageHash), sigParams.v, sigParams.r, sigParams.s);
        const recoveredAddress = ethUtil.bufferToHex(ethUtil.pubToAddress(publicKey));

        if (recoveredAddress.toLowerCase() !== userAddress.toLowerCase()) {
            throw new Error('Signature verification failed');
        }

        // Calling the isUserAuthorized function of the smart contract to check authorization status
        const authorized = await contract.methods.isUserAuthorized(userAddress).call();

        if (authorized) {
            // If user is authorized, return a JSON containing file download URIs
            const fileDownloadURIs = {
                "files": [
                    "https://example.com/download/file1",
                    "https://example.com/download/file2"
                ]
            };
            res.json(fileDownloadURIs);
        } else {
            res.status(401).send("User is not authorized to access the asset.");
        }
    } catch (error) {
        console.error("Error checking authorization:", error);
        res.status(500).send("Internal Server Error");
    }
});

// Starting the server
app.listen(port, () => {
    console.log(`Server is running on http://localhost:${port}`);
});
