// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IIceCreamSwapRouter.sol";

contract SwapHelper {
    IIceCreamSwapRouter dexRouter;

    constructor(
        IIceCreamSwapRouter _dexRouter // dex router address to list liquidity at
    ) {
        dexRouter = _dexRouter;
    }

    function swapToken(uint256 tokens, bool viaNative, address tokenOut) external {
        IERC20(msg.sender).transferFrom(msg.sender, address(this), tokens);
        IERC20(msg.sender).approve(address(dexRouter), tokens);

        address[] memory path;
        if (viaNative) {
            path = new address[](3);
            path[0] = address(this);
            path[1] = dexRouter.WETH();
            path[2] = address(tokenOut);
        } else {
            path = new address[](2);
            path[0] = address(this);
            path[1] = address(tokenOut);
        }

        // intentional first transfer here and then to token contract as tokens in the pair can not be the to address.
        dexRouter.swapExactTokensForTokens(tokens, 0, path, address(this), block.timestamp);
        IERC20(tokenOut).transfer(msg.sender, IERC20(tokenOut).balanceOf(address(this)));
    }
}
