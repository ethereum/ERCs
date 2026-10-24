const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules")

const MAX_ACCOUNTS = 20
const MINTED_TOKENS = 1_000_000_000_000_000n

module.exports = buildModule("Token", (m) => {
  let token

  if (process.env.TOKEN_ADDRESS) {
    console.log(
      "Using existing TestToken on address: ",
      process.env.TOKEN_ADDRESS,
    )
    token = m.contractAt("TestToken", process.env.TOKEN_ADDRESS, {})
  } else {
    token = m.contract("TestToken", [], {})
  }

  const config = hre.network.config

  if (config && config.tags && config.tags.includes("local")) {
    for (let i = 0; i < MAX_ACCOUNTS; i++) {
      const account = m.getAccount(i)
      m.call(token, "mint", [account, MINTED_TOKENS], {
        id: `SendingTestTokens_${i}`,
      })
    }
  }

  return { token }
})
