pragma solidity =0.5.16;

import "./NativeYield.sol";
import "../IceCreamSwapV2Factory.sol";

contract IceCreamSwapV2FactoryBlast is IceCreamSwapV2Factory, NativeYield {
    modifier onlyFeeToSetter() {
        require(msg.sender == feeToSetter, "Not feeToSetter");
        _;
    }

    constructor(address _feeToSetter, uint8 _feeProtocol) public IceCreamSwapV2Factory(_feeToSetter, _feeProtocol) {}

    function claimYields(address recipient) external onlyFeeToSetter {
        _claimYields(recipient);
    }

    function claimCustomTokenYield(address token, address recipient) external onlyFeeToSetter {
        _claimTokenYield(token, recipient);
    }

    function claimPoolYields(address pool, address recipient) external onlyFeeToSetter {
        // claim fees from liquidity pool pair or Router contract
        NativeYield(pool).claimYields(recipient);
    }

    function claimPoolCustomTokenYield(address pool, address token, address recipient) external onlyFeeToSetter {
        // claim fees from liquidity pool pair or Router contract
        NativeYield(pool).claimCustomTokenYield(token, recipient);
    }
}
