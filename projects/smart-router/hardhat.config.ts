import { getHardhatConfig } from "@icecreamswap/common/src/getHardhatConfig";

const config = getHardhatConfig(["0.7.6", "0.8.10", "0.6.6", "0.5.16", "0.4.18"], 500);
config.solidity["overrides"] = {
  "@icecreamswap/dex-v3-core/contracts/libraries/FullMath.sol": {
    version: "0.7.6",
    settings: {},
  },
  "@icecreamswap/dex-v3-core/contracts/libraries/TickBitmap.sol": {
    version: "0.7.6",
    settings: {},
  },
  "@icecreamswap/dex-v3-core/contracts/libraries/TickMath.sol": {
    version: "0.7.6",
    settings: {},
  },
  "@icecreamswap/dex-v3-periphery/contracts/libraries/PoolAddress.sol": {
    version: "0.7.6",
    settings: {},
  },
  "contracts/libraries/PoolTicksCounter.sol": {
    version: "0.7.6",
    settings: {},
  },
};
export default config;
