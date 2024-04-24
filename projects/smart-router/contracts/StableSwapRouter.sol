// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IStableSwapRouter.sol";

import "./base/PeripheryPaymentsWithFeeExtended.sol";

// Contract is mocked as after concentrated liquidity stable swaps are not really needed anymore. Save contract size

/// @title Stable Swap Router
abstract contract StableSwapRouter is IStableSwapRouter, PeripheryPaymentsWithFeeExtended, Ownable {
    address public stableSwapFactory = address(0);
    address public stableSwapInfo = address(0);

    event SetStableSwap(address indexed factory, address indexed info);

    constructor(address, address) {}

    function setStableSwap(address, address) external onlyOwner {
        revert();
    }

    function _swap(address[] memory, uint256[] memory) private {
        revert();
    }

    function exactInputStableSwap(
        address[] calldata,
        uint256[] calldata,
        uint256,
        uint256,
        address
    ) external payable override returns (uint256) {
        revert();
    }

    function exactOutputStableSwap(
        address[] calldata,
        uint256[] calldata,
        uint256,
        uint256,
        address
    ) external payable override returns (uint256) {
        revert();
    }
}
