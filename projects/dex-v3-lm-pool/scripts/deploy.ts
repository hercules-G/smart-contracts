import { deployAndVerify, getChainConfig } from "@icecreamswap/common";
import { writeFileSync } from "fs";
import { abi as V3FactoryABI } from "@icecreamswap/dex-v3-core/artifacts/contracts/IceCreamSwapV3Factory.sol/IceCreamSwapV3Factory.json";
import { abi as V3MasterchefABI } from "@icecreamswap/liquidity-farms-v3/artifacts/contracts/IceCreamSwapLiquidityFarmV3.sol/IceCreamSwapLiquidityFarmV3.json";
import { ethers } from "hardhat";

async function main() {
  const { chainName } = await getChainConfig();
  const signer = (await ethers.getSigners())[0];

  const v3DeployedContracts = await import(`@icecreamswap/dex-v3-core/deployments/${chainName}.json`);
  const mcV3DeployedContracts = await import(`@icecreamswap/liquidity-farms-v3/deployments/${chainName}.json`);

  const v3Factory_address = v3DeployedContracts.v3Factory;
  const v3Masterchef_address = mcV3DeployedContracts.farmV3;

  const v3LmDeployer = await deployAndVerify("IceCreamSwapV3LmPoolDeployer", [v3Masterchef_address]);

  if (chainName !== "hardhat") {
    // hardhat ethers estimates the contract to be a wrong contract due to reused addresses and throws an error
    const v3Factory = new ethers.Contract(v3Factory_address, V3FactoryABI, signer);
    await v3Factory.setLmPoolDeployer(v3LmDeployer.target);

    const v3Masterchef = new ethers.Contract(v3Masterchef_address, V3MasterchefABI, signer);
    await v3Masterchef.setLmPoolDeployer(v3LmDeployer.target);
  }

  const contracts = {
    v3LmDeployer: v3LmDeployer.target,
  };
  writeFileSync(`./deployments/${chainName}.json`, JSON.stringify(contracts, null, 2));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
