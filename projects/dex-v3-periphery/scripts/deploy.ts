import "@openzeppelin/hardhat-upgrades";
import { ethers, upgrades } from "hardhat";
import { writeFileSync } from "fs";
import { deployAndVerify, getChainConfig } from "@icecreamswap/common/dist";

const BASE_TOKEN_URI = "https://nft.icecreamswap.com/v3/";

async function main() {
  const { chainConfig, chainName } = await getChainConfig();

  const coreDeployments = await import(`@icecreamswap/dex-v3-core/deployments/${chainName}.json`);
  const v3PoolDeployer_address = coreDeployments.v3PoolDeployer;
  const v3Factory_address = coreDeployments.v3Factory;

  const swapRouter = await deployAndVerify("SwapRouter", [v3PoolDeployer_address, v3Factory_address, chainConfig.weth]);

  // todo: standardize proxy contract deployments the same way as normal deployments
  const NonfungibleTokenPositionDescriptor = await ethers.getContractFactory(
    "NonfungibleTokenPositionDescriptorOffChain",
  );
  const nonfungibleTokenPositionDescriptor = await upgrades.deployProxy(NonfungibleTokenPositionDescriptor, [
    `${BASE_TOKEN_URI}${(await ethers.provider.getNetwork()).chainId}/`,
  ]);
  await nonfungibleTokenPositionDescriptor.waitForDeployment();
  console.log("nonfungibleTokenPositionDescriptor", nonfungibleTokenPositionDescriptor.target);

  const nonfungiblePositionManager = await deployAndVerify("NonfungiblePositionManager", [
    v3PoolDeployer_address,
    v3Factory_address,
    chainConfig.weth,
    nonfungibleTokenPositionDescriptor.target,
  ]);

  const pancakeInterfaceMulticallV2 = await deployAndVerify("PancakeInterfaceMulticallV2", []);

  const v3Migrator = await deployAndVerify("V3Migrator", [
    v3PoolDeployer_address,
    v3Factory_address,
    chainConfig.weth,
    nonfungiblePositionManager.target,
  ]);

  const tickLens = await deployAndVerify("TickLens", []);

  const quoterV2 = await deployAndVerify("QuoterV2", [v3PoolDeployer_address, v3Factory_address, chainConfig.weth]);

  const contracts = {
    SwapRouter: swapRouter.target,
    V3Migrator: v3Migrator.target,
    QuoterV2: quoterV2.target,
    TickLens: tickLens.target,
    NonfungibleTokenPositionDescriptor: nonfungibleTokenPositionDescriptor.target,
    NonfungiblePositionManager: nonfungiblePositionManager.target,
    InterfaceMulticallV2: pancakeInterfaceMulticallV2.target,
  };

  writeFileSync(`./deployments/${chainName}.json`, JSON.stringify(contracts, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
