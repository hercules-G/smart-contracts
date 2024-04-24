// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IIceCreamSwapRouter.sol";

interface ITokenRegistry {
    event TokenRegistered(address indexed token, address indexed creator, uint256 tokenType);
    event DeployerRegistered(uint256 indexed tokenType, address indexed deployer);

    function ice() external returns (IERC20 ice);

    function feeReceiver() external returns (address feeReceiver);

    function dexRouter() external returns (IIceCreamSwapRouter dexRouter);

    function getTokenType(address) external returns (uint256 tokenType);

    function getDeployerTokenType(address) external returns (uint256 tokenType);

    function getTokenCreator(address) external returns (address creator);

    function getTokensByCreator(address, uint256) external returns (address token);

    function allTokens(uint256) external returns (address token);

    function registerToken(address token, address creator) external;

    function isTokenRegistered(address token) external view returns (bool isRegistered);

    function isDeployerRegistered(address deployer) external view returns (bool isRegistered);

    function numTokensByCreator(address creator) external view returns (uint256 numTokens);

    function numTokensCreated() external view returns (uint256 numTokens);
}
