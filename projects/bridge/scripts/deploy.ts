import { bridgeConfig, deployAndVerify, getChainConfig, transactSafe, nodePrompt } from "@icecreamswap/common";
import { writeFileSync } from "fs";

async function main() {
  const { chainConfig, chainName, defaultWallet } = await getChainConfig();

  const bridge = await deployAndVerify("IceCreamSwapBridge", [
    chainConfig.bridgeDomainId,
    bridgeConfig.relayers,
    1,
    1_000_000_000,
    chainConfig.oneDollarInNative,
  ]);
  // const bridge = (await ethers.getContractFactory("IceCreamSwapBridge")).attach("0xd65CceCFf339e5680b1A1E7821421932cc2b114f")

  const erc20Handler = await deployAndVerify("IceCreamSwapERC20NativeHandler", [
    bridge.target,
    bridgeConfig.tokenFeePercent * 100,
  ]);

  const rateLimiter = await deployAndVerify("RateLimiter", [erc20Handler.target]);
  await transactSafe(erc20Handler.updateRateLimiter, [rateLimiter.target]);

  const tokens: { [symbol: string]: string } = {};
  for (const tokenConfig of bridgeConfig.bridgedTokens) {
    const userTokenInput = await nodePrompt(`Deploy Token ${tokenConfig.name}? [y,n,{existing address}]: `);
    if (userTokenInput.toLowerCase() === "n") continue;
    let tokenAddress: string;
    let mintable: boolean;
    if (userTokenInput.toLowerCase() !== "y") {
      tokenAddress = userTokenInput;
      mintable = (await nodePrompt("Should the token be configured as mintable? [y,n]: ")).toLowerCase() === "y";
    } else {
      const bridgedToken = await deployAndVerify("IceCreamSwapBridgedToken", [
        tokenConfig.name,
        tokenConfig.symbol,
        bridgeConfig.bridgeAdmin,
      ]);
      await transactSafe(bridgedToken.grantRole, [bridgedToken.MINTER_ROLE(), erc20Handler.target]);
      await transactSafe(bridgedToken.revokeRole, [bridgedToken.DEFAULT_ADMIN_ROLE(), defaultWallet.address]);
      tokenAddress = bridgedToken.target.toString();
      mintable = true;
    }
    await transactSafe(bridge.adminSetResource, [erc20Handler.target, tokenConfig.resourceId, tokenAddress]);
    if (mintable) {
      await transactSafe(erc20Handler.setBurnable, [tokenAddress, true]);
    }
    await transactSafe(rateLimiter.addLimit, [tokenConfig.resourceId, tokenConfig.rateLimit4h, 4 * 60 * 60]);
    await transactSafe(rateLimiter.addLimit, [tokenConfig.resourceId, tokenConfig.rateLimit1d, 24 * 60 * 60]);

    tokens[tokenConfig.symbol] = tokenAddress;
  }

  await transactSafe(rateLimiter.transferOwnership, [bridgeConfig.bridgeAdmin]);
  console.log(`transferred RateLimiter admin to ${bridgeConfig.bridgeAdmin}`);

  await transactSafe(bridge.transferAdmin, [bridgeConfig.bridgeAdmin]);
  console.log(`transferred Bridge admin to ${bridgeConfig.bridgeAdmin}`);

  const contracts = {
    bridge: bridge.target.toString(),
    erc20Handler: erc20Handler.target.toString(),
    rateLimiter: rateLimiter.target.toString(),
    tokens: tokens,
  };
  writeFileSync(`./deployments/${chainName}.json`, JSON.stringify(contracts, null, 2));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
