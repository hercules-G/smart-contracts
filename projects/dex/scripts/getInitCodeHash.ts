import { network } from "hardhat";
import { deployAndVerify } from "@icecreamswap/common";

async function main() {
  const networkName = network.name;
  if (networkName != "hardhat") {
    throw "not Hardhat";
  }

  const factory = await deployAndVerify("IceCreamSwapV2Factory", ["0x0000000000000000000000000000000000000000", 0]);

  console.log("Init code hash:", await factory.INIT_CODE_HASH());
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
