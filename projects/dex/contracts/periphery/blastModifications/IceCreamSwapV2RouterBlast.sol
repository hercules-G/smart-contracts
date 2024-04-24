pragma solidity =0.6.6;

import "./NativeYield.sol";
import "../IceCreamSwapV2Router.sol";

contract IceCreamSwapV2RouterBlast is IceCreamSwapV2Router, NativeYield {
    constructor(address _factory, address _WETH) public IceCreamSwapV2Router(_factory, _WETH) {}

    function claimYields(address recipient) external override {
        require(msg.sender == factory, "Not Factory");
        _claimYields(recipient);
    }

    function claimCustomTokenYield(address token, address recipient) external override {
        require(msg.sender == factory, "Not Factory");
        _claimTokenYield(token, recipient);
    }
}
