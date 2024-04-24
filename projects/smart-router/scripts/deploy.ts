import { writeFileSync } from "fs";
import { deployAndVerify, getChainConfig } from "@icecreamswap/common";

async function main() {
  // Remember to update the init code hash in SC for different chains before deploying
  const { chainName, chainConfig } = await getChainConfig();

  const v2DeployedContracts = await import(`@icecreamswap/dex/deployments/${chainName}.json`);
  const v3DeployedContracts = await import(`@icecreamswap/dex-v3-core/deployments/${chainName}.json`);
  const v3PeripheryDeployedContracts = await import(`@icecreamswap/dex-v3-periphery/deployments/${chainName}.json`);

  const v2Factory_address = v2DeployedContracts.factory;
  const v3PoolDeployer_address = v3DeployedContracts.v3PoolDeployer;
  const v3Factory_address = v3DeployedContracts.v3Factory;
  const positionManager_address = v3PeripheryDeployedContracts.NonfungiblePositionManager;

  const smartRouterHelper = await deployAndVerify("SmartRouterHelper", []);

  const smartRouter = await deployAndVerify(
    "IceCreamSwapSmartRouter",
    [
      v2Factory_address,
      v3PoolDeployer_address,
      v3Factory_address,
      positionManager_address,
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      chainConfig.weth,
    ],
    { SmartRouterHelper: smartRouterHelper.target },
  );

  const mixedRouteQuoterV1 = await deployAndVerify(
    "MixedRouteQuoterV1",
    [
      v3PoolDeployer_address,
      v3Factory_address,
      v2Factory_address,
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
    ],
    { SmartRouterHelper: smartRouterHelper.target },
  );

  const contracts = {
    SmartRouter: smartRouter.target,
    SmartRouterHelper: smartRouterHelper.target,
    MixedRouteQuoterV1: mixedRouteQuoterV1.target,
  };

  writeFileSync(`./deployments/${chainName}.json`, JSON.stringify(contracts, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
