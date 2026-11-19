/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.24",
};
require("@nomiclabs/hardhat-waffle"); 
require('solidity-coverage');

const path = require("path");
const { subtask } = require("hardhat/config");
const { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } = require("hardhat/builtin-tasks/task-names");

// The FX example is excluded from this SDC build.
subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS).setAction(async (_, __, runSuper) => {
  const fxExample = path.join(__dirname, "contracts", "examples", "FxAtomicSwap") + path.sep;
  return (await runSuper()).filter((sourcePath) => !sourcePath.startsWith(fxExample));
});
