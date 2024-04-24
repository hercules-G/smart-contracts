import { writeFileSync } from "fs";
import { deployAndVerify, getChainConfig } from "@icecreamswap/common";

async function main() {
  // Remember to update the init code hash in SC for different chains before deploying
  const { chainName, chainConfig } = await getChainConfig();

  const v2DeployedContracts = await import(`@icecreamswap/dex/deployments/${chainName}.json`);
  const v2Factory_address = v2DeployedContracts.factory;

  const smartRouterHelper = await deployAndVerify("SmartRouterHelper", []);

  const smartRouter = await deployAndVerify(
    "IceCreamSwapSmartRouter",
    [
      v2Factory_address,
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000",
      chainConfig.weth,
    ],
    { SmartRouterHelper: smartRouterHelper.target },
  );

  const contracts = {
    SmartRouter: smartRouter.target,
    SmartRouterHelper: smartRouterHelper.target,
  };

  writeFileSync(`./deployments/${chainName}V2Only.json`, JSON.stringify(contracts, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
