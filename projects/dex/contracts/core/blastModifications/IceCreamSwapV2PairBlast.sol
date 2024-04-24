pragma solidity =0.5.16;

import "./NativeYield.sol";
import "../IceCreamSwapV2Pair.sol";

contract IceCreamSwapV2PairBlast is IceCreamSwapV2Pair, NativeYield {
    function claimYields(address recipient) external {
        require(msg.sender == factory, "Not Factory");
        _claimYields(recipient);
    }

    function claimCustomTokenYield(address token, address recipient) external {
        require(msg.sender == factory, "Not Factory");
        _claimTokenYield(token, recipient);
    }
}
