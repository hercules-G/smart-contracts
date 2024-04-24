import { deployAndVerify, getChainConfig, transactSafe } from "@icecreamswap/common";
import { writeFileSync } from "fs";

async function main() {
  const { chainConfig, chainName } = await getChainConfig();

  const v3PoolDeployer = await deployAndVerify("IceCreamSwapV3PoolDeployer", []);

  const v3Factory = await deployAndVerify("IceCreamSwapV3Factory", [v3PoolDeployer.target]);

  await transactSafe(v3PoolDeployer.setFactoryAddress, [v3Factory.target]);

  const contracts = {
    v3Factory: v3Factory.target,
    v3PoolDeployer: v3PoolDeployer.target,
  };
  writeFileSync(`./deployments/${chainName}.json`, JSON.stringify(contracts, null, 2));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
