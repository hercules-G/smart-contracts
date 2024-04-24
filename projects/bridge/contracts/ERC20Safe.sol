// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IERC20MintableBurnable.sol";

/**
    @title Manages deposited ERC20s.
    @author ChainSafe Systems.
    @notice This contract is intended to be used with ERC20Handler contract.
 */
contract ERC20Safe {
    /**
        @notice Used to gain custody of deposited token.
        @param tokenAddress Address of ERC20 to transfer.
        @param owner Address of current token owner.
        @param amount Amount of tokens to transfer.
     */
    function lockERC20(address tokenAddress, address owner, uint256 amount) internal returns (uint256 amountReceived) {
        IERC20 erc20 = IERC20(tokenAddress);
        uint256 balanceBefore = erc20.balanceOf(address(this));
        safeTransferFrom(erc20, owner, address(this), amount);
        amountReceived = erc20.balanceOf(address(this)) - balanceBefore;
    }

    /**
        @notice Transfers custody of token to recipient.
        @param tokenAddress Address of ERC20 to transfer.
        @param recipient Address to transfer tokens to.
        @param amount Amount of tokens to transfer.
     */
    function releaseERC20(address tokenAddress, address recipient, uint256 amount) internal {
        IERC20 erc20 = IERC20(tokenAddress);
        safeTransfer(erc20, recipient, amount);
    }

    /**
        @notice Used to create new ERC20s.
        @param tokenAddress Address of ERC20 to transfer.
        @param recipient Address to mint token to.
        @param amount Amount of token to mint.
     */
    function mintERC20(address tokenAddress, address recipient, uint256 amount) internal {
        IERC20MintableBurnable erc20 = IERC20MintableBurnable(tokenAddress);
        erc20.mint(recipient, amount);
    }

    /**
        @notice Used to burn ERC20s.
        @notice Does so by first using transferFrom and then burn as not all contracts implement burnFrom.
        @param tokenAddress Address of ERC20 to burn.
        @param owner Current owner of tokens.
        @param amount Amount of tokens to burn.
     */
    function burnERC20(address tokenAddress, address owner, uint256 amount) internal {
        IERC20MintableBurnable erc20 = IERC20MintableBurnable(tokenAddress);
        uint256 balanceBefore = erc20.balanceOf(address(this));
        safeTransferFrom(erc20, owner, address(this), amount);
        erc20.burn(erc20.balanceOf(address(this)) - balanceBefore);
    }

    /**
        @notice used to transfer ERC20s safely
        @param token Token instance to transfer
        @param to Address to transfer token to
        @param value Amount of token to transfer
     */
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _safeCall(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    /**
        @notice used to transfer ERC20s safely
        @param token Token instance to transfer
        @param from Address to transfer token from
        @param to Address to transfer token to
        @param value Amount of token to transfer
     */
    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _safeCall(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
        @notice used to make calls to ERC20s safely
        @param token Token instance call targets
        @param data encoded call data
     */
    function _safeCall(IERC20 token, bytes memory data) private {
        uint256 tokenSize;
        assembly {
            tokenSize := extcodesize(token)
        }
        require(tokenSize > 0, "ERC20: not a contract");

        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "ERC20: call failed");

        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "ERC20: operation did not succeed");
        }
    }
}
