import { ethers, network } from "hardhat";
import hre from "hardhat";
import { chainConfigs } from "./index";
import prompt from "./nodePrompt";

export const getChainConfig = async () => {
  const defaultWallet = (await ethers.getSigners())[0];

  const chainName = network.name;
  const config = chainConfigs[chainName as keyof typeof chainConfigs];
  if (!config) {
    throw new Error(`No config found for network ${chainName}: `);
  }

  if (chainName !== "hardhat") {
    if ((await prompt(`Network is ${chainName} are you sure you want to continue? [y,n]: `)).toLowerCase() !== "y") {
      throw new Error(`Aborted`);
    }
  }

  const explorerApiUri = hre.config.etherscan.customChains.find((chain) => chain.network === chainName)?.urls.apiURL;
  let explorerApiWorking = false;
  if (explorerApiUri && config.explorerApiKey) {
    // @ts-ignore
    const response = await fetch(
      explorerApiUri + "?module=block&action=eth_block_number&apikey=" + config.explorerApiKey,
    );
    if (response.ok) {
      explorerApiWorking = true;
    }
  }

  if (!explorerApiWorking && chainName !== "hardhat") {
    if (
      (await prompt(`Block explorer API seems to not be configured or working. Continue? [y,n]: `)).toLowerCase() !==
      "y"
    ) {
      throw new Error(`Aborted`);
    }
  }

  return {
    chainConfig: config,
    chainName,
    defaultWallet,
  };
};
