import { deployAndVerify, getChainConfig } from "@icecreamswap/common";
import { writeFileSync } from "fs";

async function main() {
  const { chainName } = await getChainConfig();

  const multicall = await deployAndVerify("Multicall3", []);

  const contracts = {
    multicall: multicall.target,
  };
  writeFileSync(`./deployments/${chainName}.json`, JSON.stringify(contracts, null, 2));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
