import * as General from "./General.test";
import * as Mint from "./Mint.test";
import * as Burn from "./Burn.test";
import * as Transfer from "./Transfer.test";
import * as TransferFrom from "./TransferFrom.test";

export const run = async () => {
  describe("ERC7818", async function () {
    General.run();
    Mint.run();
    Burn.run();
    Transfer.run();
    TransferFrom.run();
  });
};
