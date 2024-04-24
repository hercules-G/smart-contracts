import { getHardhatConfig } from "@icecreamswap/common/src/getHardhatConfig";

// lower optimization runs result in smaller contracts that are more gas intensive to interact with
// if contract size is too big, lower the optimization rounds
export default getHardhatConfig(["0.7.6"], 500);
