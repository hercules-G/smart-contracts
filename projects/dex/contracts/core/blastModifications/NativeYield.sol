pragma solidity =0.5.16;

import "./interfaces/IBlast.sol";
import "./interfaces/IERC20Rebasing.sol";

contract NativeYield {
    IBlast private constant BLAST = IBlast(0x4300000000000000000000000000000000000002);
    IERC20Rebasing private constant USDB = IERC20Rebasing(0x4300000000000000000000000000000000000003);
    IERC20Rebasing private constant WETH = IERC20Rebasing(0x4300000000000000000000000000000000000004);

    constructor() public {
        BLAST.configureClaimableYield();
        BLAST.configureClaimableGas();
        USDB.configure(IERC20Rebasing.YieldMode.CLAIMABLE);
        WETH.configure(IERC20Rebasing.YieldMode.CLAIMABLE);
    }

    function claimYields(address recipient) external;

    function claimCustomTokenYield(address token, address recipient) external;

    function _claimYields(address recipient) internal {
        BLAST.claimAllYield(address(this), recipient);

        BLAST.claimMaxGas(address(this), recipient);

        _claimTokenYield(address(USDB), recipient);
        _claimTokenYield(address(WETH), recipient);
    }

    function _claimTokenYield(address token, address recipient) internal {
        uint256 claimable = IERC20Rebasing(token).getClaimableAmount(address(this));
        if (claimable != 0) {
            IERC20Rebasing(token).claim(recipient, claimable);
        }
    }

    function setTokenClaimableYield(address token) external {
        // this function is intentionally permission less
        IERC20Rebasing(token).configure(IERC20Rebasing.YieldMode.CLAIMABLE);
    }
}
