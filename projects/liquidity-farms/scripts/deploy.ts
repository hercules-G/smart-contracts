import { deployAndVerify, farmConfig, getChainConfig, transactSafe } from "@icecreamswap/common";
import { writeFileSync } from "fs";

async function main() {
  const { chainName } = await getChainConfig();

  const bridgeDeployedContracts = await import(`@icecreamswap/bridge/deployments/${chainName}.json`);
  const ice = bridgeDeployedContracts.tokens.ICE;

  const farm = await deployAndVerify("IceCreamFarm", [ice, 0, farmConfig.iceTreasury]);

  await transactSafe(farm.transferOwnership, [farmConfig.farmAdmin]);

  const contracts = {
    farm: farm.target,
  };
  writeFileSync(`./deployments/${chainName}.json`, JSON.stringify(contracts, null, 2));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
