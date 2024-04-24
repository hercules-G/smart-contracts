// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import "@icecreamswap/dex-v3-core/contracts/libraries/SafeCast.sol";
import "@icecreamswap/dex-v3-core/contracts/libraries/TickMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/IV3SwapRouter.sol";
import "./base/PeripheryPaymentsWithFeeExtended.sol";
import "./base/OracleSlippage.sol";
import "./libraries/Constants.sol";
import "./libraries/SmartRouterHelper.sol";
import "./libraries/PathForeign.sol";

/// @title PancakeSwap V3 Swap Router
/// @notice Router for stateless execution of swaps against PancakeSwap V3
abstract contract V3SwapRouter is IV3SwapRouter, PeripheryPaymentsWithFeeExtended, OracleSlippage, ReentrancyGuard {
    using PathForeign for bytes;
    using SafeCast for uint256;

    /// @dev Used as the placeholder value for amountInCached, because the computed amount in for an exact output swap
    /// can never actually be this value
    uint256 private constant DEFAULT_AMOUNT_IN_CACHED = type(uint256).max;

    /// @dev Transient storage variable used for returning the computed amount in for an exact output swap.
    uint256 private amountInCached = DEFAULT_AMOUNT_IN_CACHED;

    struct SwapCallbackData {
        bytes path;
    }

    /// catches all V3 callbacks like uniswapV3SwapCallback and forwards their decoded parameter to pancakeV3SwapCallback
    fallback(bytes calldata _input) external returns (bytes memory) {
        (int256 amount0Delta, int256 amount1Delta, bytes memory _data) = abi.decode(
            _input[4:],
            (int256, int256, bytes)
        );
        pancakeV3SwapCallback(amount0Delta, amount1Delta, _data);
        return "";
    }

    /// @notice Called to `msg.sender` after executing a swap via IPancakeV3Pool#swap.
    /// @dev In the implementation you must pay the pool tokens owed for the swap.
    /// The caller of this method must be checked to be a PancakeV3Pool deployed by the canonical PancakeV3Factory.
    /// amount0Delta and amount1Delta can both be 0 if no tokens were swapped.
    /// @param amount0Delta The amount of token0 that was sent (negative) or must be received (positive) by the pool by
    /// the end of the swap. If positive, the callback must send that amount of token0 to the pool.
    /// @param amount1Delta The amount of token1 that was sent (negative) or must be received (positive) by the pool by
    /// the end of the swap. If positive, the callback must send that amount of token1 to the pool.
    /// @param _data Any data passed through by the caller via the IPancakeV3PoolActions#swap call
    function pancakeV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes memory _data) private {
        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported
        SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));
        (address pool, address tokenIn, address tokenOut) = data.path.decodeFirstPool();
        require(msg.sender == pool, "!pool");

        (bool isExactInput, uint256 amountToPay) = amount0Delta > 0
            ? (tokenIn < tokenOut, uint256(amount0Delta))
            : (tokenOut < tokenIn, uint256(amount1Delta));

        if (isExactInput) {
            pay(tokenIn, address(this), msg.sender, amountToPay);
        } else {
            // either initiate the next swap or pay
            if (data.path.hasMultiplePools()) {
                data.path = data.path.skipToken();
                exactOutputInternal(amountToPay, msg.sender, 0, data);
            } else {
                amountInCached = amountToPay;
                // note that because exact output swaps are executed in reverse order, tokenOut is actually tokenIn
                pay(tokenOut, address(this), msg.sender, amountToPay);
            }
        }
    }

    /// @dev Performs a single exact input swap
    /// @notice `refundETH` should be called at very end of all swaps
    function exactInputInternal(
        uint256 amountIn,
        address recipient,
        uint160 sqrtPriceLimitX96,
        SwapCallbackData memory data
    ) private returns (uint256 amountOut) {
        // find and replace recipient addresses
        if (recipient == Constants.MSG_SENDER) recipient = msg.sender;
        else if (recipient == Constants.ADDRESS_THIS) recipient = address(this);

        (address pool, address tokenIn, address tokenOut) = data.path.decodeFirstPool();

        bool zeroForOne = tokenIn < tokenOut;

        (int256 amount0, int256 amount1) = IPancakeV3Pool(pool).swap(
            recipient,
            zeroForOne,
            amountIn.toInt256(),
            sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : sqrtPriceLimitX96,
            abi.encode(data)
        );

        return uint256(-(zeroForOne ? amount1 : amount0));
    }

    /// @inheritdoc IV3SwapRouter
    function exactInputSingle(
        ExactInputSingleParams memory params
    ) external payable override nonReentrant returns (uint256 amountOut) {
        // use amountIn == Constants.CONTRACT_BALANCE as a flag to swap the entire balance of the contract
        if (params.amountIn == Constants.CONTRACT_BALANCE) {
            params.amountIn = IERC20(params.tokenIn).balanceOf(address(this));
        } else {
            pay(params.tokenIn, msg.sender, address(this), params.amountIn);
        }

        amountOut = exactInputInternal(
            params.amountIn,
            params.recipient,
            params.sqrtPriceLimitX96,
            SwapCallbackData({path: abi.encodePacked(params.tokenIn, params.pool, params.tokenOut)})
        );
        require(amountOut >= params.amountOutMinimum);
    }

    /// @inheritdoc IV3SwapRouter
    function exactInput(
        ExactInputParams memory params
    ) external payable override nonReentrant returns (uint256 amountOut) {
        (, address tokenIn, ) = params.path.decodeFirstPool();
        // use amountIn == Constants.CONTRACT_BALANCE as a flag to swap the entire balance of the contract
        if (params.amountIn == Constants.CONTRACT_BALANCE) {
            params.amountIn = IERC20(tokenIn).balanceOf(address(this));
        } else {
            pay(tokenIn, msg.sender, address(this), params.amountIn);
        }

        while (true) {
            bool hasMultiplePools = params.path.hasMultiplePools();

            // the outputs of prior swaps become the inputs to subsequent ones
            params.amountIn = exactInputInternal(
                params.amountIn,
                hasMultiplePools ? address(this) : params.recipient, // for intermediate swaps, this contract custodies
                0,
                SwapCallbackData({
                    path: params.path.getFirstPool() // only the first pool in the path is necessary
                })
            );

            // decide whether to continue or terminate
            if (hasMultiplePools) {
                params.path = params.path.skipToken();
            } else {
                amountOut = params.amountIn;
                break;
            }
        }

        require(amountOut >= params.amountOutMinimum);
    }

    /// @dev Performs a single exact output swap
    /// @notice `refundETH` should be called at very end of all swaps
    function exactOutputInternal(
        uint256 amountOut,
        address recipient,
        uint160 sqrtPriceLimitX96,
        SwapCallbackData memory data
    ) private returns (uint256 amountIn) {
        // find and replace recipient addresses
        if (recipient == Constants.MSG_SENDER) recipient = msg.sender;
        else if (recipient == Constants.ADDRESS_THIS) recipient = address(this);

        (address pool, address tokenOut, address tokenIn) = data.path.decodeFirstPool();

        bool zeroForOne = tokenIn < tokenOut;

        (int256 amount0Delta, int256 amount1Delta) = IPancakeV3Pool(pool).swap(
            recipient,
            zeroForOne,
            -amountOut.toInt256(),
            sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : sqrtPriceLimitX96,
            abi.encode(data)
        );

        uint256 amountOutReceived;
        (amountIn, amountOutReceived) = zeroForOne
            ? (uint256(amount0Delta), uint256(-amount1Delta))
            : (uint256(amount1Delta), uint256(-amount0Delta));
        // it's technically possible to not receive the full output amount,
        // so if no price limit has been specified, require this possibility away
        if (sqrtPriceLimitX96 == 0) require(amountOutReceived == amountOut);
    }

    /// @inheritdoc IV3SwapRouter
    function exactOutputSingle(
        ExactOutputSingleParams calldata params
    ) external payable override nonReentrant returns (uint256 amountIn) {
        // transfer amountInMaximum from sender to this contract
        pay(params.tokenIn, msg.sender, address(this), params.amountInMaximum);

        // avoid an SLOAD by using the swap return data
        amountIn = exactOutputInternal(
            params.amountOut,
            params.recipient,
            params.sqrtPriceLimitX96,
            SwapCallbackData({path: abi.encodePacked(params.tokenOut, params.pool, params.tokenIn)})
        );

        // refund unused input amount to sender
        pay(params.tokenIn, address(this), msg.sender, params.amountInMaximum - amountIn);

        // has to be reset even though we don't use it in the single hop case
        amountInCached = DEFAULT_AMOUNT_IN_CACHED;
    }

    /// @inheritdoc IV3SwapRouter
    function exactOutput(
        ExactOutputParams calldata params
    ) external payable override nonReentrant returns (uint256 amountIn) {
        address tokenIn = params.path.getLastToken();

        // transfer amountInMaximum from sender to this contract
        pay(tokenIn, msg.sender, address(this), params.amountInMaximum);

        exactOutputInternal(params.amountOut, params.recipient, 0, SwapCallbackData({path: params.path}));

        amountIn = amountInCached;

        // refund unused input amount to sender
        pay(tokenIn, address(this), msg.sender, params.amountInMaximum - amountIn);

        amountInCached = DEFAULT_AMOUNT_IN_CACHED;
    }
}
