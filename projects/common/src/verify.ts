import { run } from "hardhat";
import { Addressable } from "ethers/lib.esm/address";

export async function tryVerify(
  contractAddress: string | Addressable,
  constructorArguments: any[] = [],
  libraries: any = {},
) {
  if (process.env.HARDHAT_NETWORK !== "hardhat") {
    try {
      console.info("Verifying", contractAddress, constructorArguments);
      await run("verify:verify", {
        address: contractAddress,
        constructorArguments,
        libraries,
      });
      console.log("verification completed");
    } catch (error) {
      console.error(error);
    }
  }
}
