# ERC-7738 Script Registry Contracts, deployment and test harness scripts

This folder contains sample (and actual deployed) ERC-7738 registry contracts and tapp scripts

## Test suite

- Init hardhat in this directory
```bash
npm install --save-dev hardhat
```

- Run the test harness
```bash
npx hardhat test
```

# Test a script on the registry

## Deploy Example Token

Deploy a test token, let's use a simple ERC-721 with a custom mint function:

```Solidity
// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyToken is ERC721, Ownable {
    uint256 private _tokenId;
    constructor()
        ERC721("MyToken", "MTK")
        Ownable(msg.sender)
    {
        _tokenId = 1;
    }

    function mint() public {
        _safeMint(msg.sender, _tokenId);
        _tokenId++;
    }
}
```
Deploy this NFT using eg Remix and make a note of the contract address.

## Create Simple TokenScript, emulate and Deploy

First install the TokenScript CLI tool

1. Install the TokenScript build tool (see [TokenScript Quickstart](https://launchpad-doc.vercel.app/quick-start/tokenscript-cli/quick-start-tokenscript-cli))
```bash
npm install -g @tokenscript/cli
```

Here is a minimal example minting tokenscript object file: [Basic NFT TokenScript](./tokenscript/examples/tokenscript.xml). 

2. Copy or clone this code to a directory, ensure it is called tokenscript.xml.
3. Locate the following line in the TokenScript:
```xml
<ts:address network="ChainId">CONTRACT_ADDRESS</ts:address>
```
Replace the ChainId and CONTRACT_ADDRESS with the contract you deployed in the previous step.
4. Use Emulation to test (in the same directory as you put the examples/tokenscript.xml file):
```bash
tokenscript emulate
```
This will let you test the TokenScript functionality before deploying on the registry. The generated page will allow you to mint new tokens.

5. Upload the TokenScript to an FTP or IPFS and make a note of the URL or IPFS hash.

## Add script to the registry

1. Open the registry page:
[Holesky Registry Page](https://viewer-staging.tokenscript.org/?chain=17000&contract=0x0077380bCDb2717C9640e892B9d5Ee02Bb5e0682&scriptId=7738_2)
[Sepolia Registry Page](https://viewer-staging.tokenscript.org/?chain=11155111&contract=0x0077380bCDb2717C9640e892B9d5Ee02Bb5e0682&scriptId=7738_1)
[Base Sepolia Registry Page](https://viewer-staging.tokenscript.org/?chain=84532&contract=0x0077380bCDb2717C9640e892B9d5Ee02Bb5e0682&scriptId=7738_2)

Click on the onboarding button "Set ScriptURI". Set the contract address and scriptURI in the card.

2. Test onboarding. Switch wallets, go to the token page of your token (eg for Holesky):

`https://viewer-staging.tokenscript.org/?chain=17000&contract=<YOUR CONTRACT ADDRESS>`

This will open the TokenScript for your deployed contract. Click on the Mint onboarding button to generate new Tokens.


## Deploy your own registry on a testnet
For this test we will use Holesky, but you can also use Sepolia, or any testnet on which the ENS contracts has been deployed.

Add some test eth on 2 wallets (0.1 -> 0.5 depending on gas price on the testnet)
Create a .env file which contains the following three keys:
```
PRIVATE_KEY_DEPLOY = "0x<PRIVATE KEY 1>"
PRIVATE_KEY_2DEPLOY = "0x<PRIVATE KEY 2>"
PRIVATE_KEY_ENS = "0x<PRIVATE KEY ENS>"
```

Create an ENS domain on Holesky using the PRIVATE_KEY_ENS wallet. Obtain a `.eth` domain, not `.box` or any other. Go to the ENS app https://app.ens.domains/ and obtain a new ENS using your Holesky.
Using the app, unwrap the domain. Click on "More" then "Unwrap".

Now, use the script to transfer ownership of the ENS to where the ENSAssigner contract will be written:

1. Add the ENS name to your .env file (don't add the .eth suffix).
```
ENS_NAME="<YOUR ENS>"
```

eg, if the domain you picked was "kilkennycat.eth":
```
ENS_NAME="kilkennycat"
```

2. Run the script (note this script changes ownership of the domain to the ENSAssigner contract that will soon be deployed)

```bash
npx hardhat run ./scripts/changeENSOwner.ts --network holesky
```

Now, ensure the change ownership transaction is written (check the console log of first deployment), and run the deploy script:

```bash
npx hardhat run ./scripts/deploy.ts --network holesky
```

Congrats your registry is deployed. Now to issue a bootstrap script for the registry.

## Generate TokenScript and upload to IPFS

1. Open the `./tokenscript` folder in your favourite editor, and find the `tokenscript.xml` file.
2. Locate the Origin contract definition line: 
```xml
<ts:contract interface="erc721" name="RegistryContract">
```
3. Edit the contract network and address on the line below this.
4. Build the TokenScript object file (use commandline from the ./)
```bash
tokenscript build
```
5. Upload the `tokenscript.tsml` file in the `./tokenscript/out` directory to IPFS, or your publicly accessible FTP.

## Set the TokenScript entry on the Script Registry

Set the tokenscript for your registry via a script entry on the registry contract itself, using the script itself. This is akin to 'bootstrapping' your registry. You could just as easily accomplish this by using an `ethers.js` script or verifying the contract on `https://etherscan.io` and then using etherscan's write menu.

use the tokenscript CLI `emulate` feature:
```bash
tokenscript emulate
```
This will automatically open an emulator browser page. Connect your Ethereum wallet which is holding the key you used to deploy the registry contract.
Now use the 'Onboarding card' which is defined in the TokenScript xml - click the `Set ScriptURI` button.

This will open the card defined in `./onboard.html`. This card invites you to set the contract address - which in this case is your registry contract - and the URI of the Tokenscript TSML you uploaded in step 5. (eg `ipfs://QmRaVBN4NBevk1j4HHfCLrMjjLrYNnsnJS2caJs9smYAtq`).

Once you click on the `Set Script URI` button your wallet will ask permission to call the `setScriptURI(address contractAddress, string[] uri)` function.

## Test your regsitry

1. switch to a new directory and clone the tokenscript viewer repo:
```bash
git clone https://github.com/SmartTokenLabs/tokenscript-engine.git
```
```bash
cd ./tokenscript-engine/javascript/tokenscript-viewer
```
2. update the registry contract address: open `javascript/engine-js/src/repo/sources/RegistryScriptURI.ts` and change `const REGISTRY_7738` to your deployed registry address.
3. Add your Infura API key to the .env (you will have to create the .env file):
```
INFURA_API_KEY=1234567890ABCDEF1234567890ABCDEF
```
4. Install dependencies and run
```bash
npm i
```
```bash
npm run start
```
4. On the opened webpage, open your deployed registry script:
`http://localhost:3333/?chain=17000&contract=<YOUR DEPLOYED REGISTRY CONTRACT ADDRESS>`
5. Set the ScriptURI for the NFT contract you deployed in the first step, by clicking the "Set ScriptURI" button from your deployed tokenscript. Set the NFT contract address and URI path you uploaded to.
6. (Optional) Set a name and icon for the registry script, by clicking on the 'Set Name' and 'Set Icon' buttons on the token that is now displayed.
7. Use the script served from your new registry:
`http://localhost:3333/?chain=17000&contract=<YOUR NFT Contract address>`