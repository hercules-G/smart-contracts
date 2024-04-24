// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./dividendToken.sol";
import "./interfaces/ITokenRegistry.sol";

contract DividendTokenDeployer is Ownable, Pausable {
    ITokenRegistry public tokenRegistry;
    uint256 public iceFee;

    event TokenDeployed(
        address indexed token,
        address indexed creator,
        string name,
        string symbol,
        uint256 buyTax,
        uint256 sellTax
    );

    constructor(
        uint256 _iceFee, // fee in wei to deploy the contract
        ITokenRegistry _tokenRegistry
    ) {
        iceFee = _iceFee;
        tokenRegistry = _tokenRegistry;
    }

    function deploy(
        string memory symbol,
        string memory name,
        uint256 supply, // supply in wei
        uint256 buyTax, // 100 = 1%
        uint256 sellTax, // 100 = 1%
        uint256 marketingTax, // marketingTax + reflectionTax + liquidityTax needs to be 10_000
        uint256 reflectionTax, // marketing tax goes to admin as ETH, reflection to all users as this token
        uint256 liquidityTax // and liquidity tax gets provided as DEX liquidity 50% ETH 50% this token
    ) external whenNotPaused returns (address tokenAddress) {
        tokenRegistry.ice().transferFrom(_msgSender(), tokenRegistry.feeReceiver(), iceFee);

        tokenAddress = address(
            new DividendToken(
                symbol,
                name,
                supply,
                buyTax,
                sellTax,
                marketingTax,
                reflectionTax,
                liquidityTax,
                tokenRegistry.ice(),
                tokenRegistry.dexRouter(),
                _msgSender()
            )
        );

        tokenRegistry.registerToken(tokenAddress, _msgSender());

        emit TokenDeployed(tokenAddress, _msgSender(), name, symbol, buyTax, sellTax);
    }

    function changeIceFee(uint256 _iceFee) external onlyOwner {
        iceFee = _iceFee;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
