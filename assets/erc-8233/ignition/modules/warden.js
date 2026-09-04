const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules")
const TokenModule = require("./token.js")

module.exports = buildModule("Warden", (m) => {
  const { token } = m.useModule(TokenModule)

  const warden = m.contract("Warden", [token], {})

  return { warden, token }
})
