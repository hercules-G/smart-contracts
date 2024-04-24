import "@icecreamswap/common";
import { ethers } from "hardhat";

async function main() {
  const v3Pool = await ethers.getContractFactory("PancakeV3Pool");
  const hash = ethers.keccak256(v3Pool.bytecode);
  console.log("V3 init code hash: " + hash);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
