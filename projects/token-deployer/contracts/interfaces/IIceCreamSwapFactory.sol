// SPDX-License-Identifier: MIT

pragma solidity 0.8;

interface IIceCreamSwapFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}
