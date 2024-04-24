// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import "../IceCreamSwapSmartRouter.sol";
import "./interfaces/IBlast.sol";

contract SmartRouterBlast is IceCreamSwapSmartRouter {
    IBlast private constant BLAST = IBlast(0x4300000000000000000000000000000000000002);

    constructor(
        address _factoryV2,
        address _deployer,
        address _factoryV3,
        address _positionManager,
        address _stableFactory,
        address _stableInfo,
        address _WETH9
    )
        IceCreamSwapSmartRouter(
            _factoryV2,
            _deployer,
            _factoryV3,
            _positionManager,
            _stableFactory,
            _stableInfo,
            _WETH9
        )
    {
        BLAST.configureClaimableYield();
        BLAST.configureClaimableGas();
    }

    function claimYields(address recipient) external onlyOwner {
        BLAST.claimAllYield(address(this), recipient);

        BLAST.claimMaxGas(address(this), recipient);
    }
}
