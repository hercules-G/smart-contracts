import { deployAndVerify, getChainConfig } from "@icecreamswap/common";
import { writeFileSync } from "fs";

async function main() {
  const { chainConfig, chainName } = await getChainConfig();
  const v3PeripheryDeployedContracts = await import(`@icecreamswap/dex-v3-periphery/deployments/${chainName}.json`);
  const bridgeDeployedContracts = await import(`@icecreamswap/bridge/deployments/${chainName}.json`);

  const positionManager = v3PeripheryDeployedContracts.NonfungiblePositionManager;
  const ice = bridgeDeployedContracts.tokens.ICE;

  const farmV3 = await deployAndVerify("IceCreamSwapLiquidityFarmV3", [ice, positionManager, chainConfig.weth]);

  const contracts = {
    farmV3: farmV3.target,
  };
  writeFileSync(`./deployments/${chainName}.json`, JSON.stringify(contracts, null, 2));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
