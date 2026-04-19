// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IScanner} from "./IScanner.sol";

interface IQuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate);
}

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

contract UniV3Scanner is IScanner {
    IQuoterV2 public constant QUOTER = IQuoterV2(0x61fFE014bA17989E743c5F6cB21bF9697530B21e);
    IUniswapV3Factory public constant FACTORY = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    uint24 internal constant FEE_LOW = 500;
    uint24 internal constant FEE_MID = 3000;
    uint24 internal constant FEE_HIGH = 10000;

    function quote(address tokenIn, address tokenOut, uint256 amountIn)
        external
        returns (uint256 amountOut, bytes32 poolId)
    {
        if (amountIn == 0) return (0, bytes32(0));
        uint24 bestFee;
        (amountOut, bestFee) = _bestQuote(tokenIn, tokenOut, amountIn);
        if (amountOut == 0) return (0, bytes32(0));
        address pool = FACTORY.getPool(tokenIn, tokenOut, bestFee);
        // Composite poolId: [pool address (160b) << 24] | fee (24b).
        // ArbExecutor._swapUniV3 reads the low 24 bits as the fee tier; the
        // upper 160 bits preserve the pool address for consumers that need
        // it. Works because pool addresses fit in 160 bits with 72 free bits
        // above in a bytes32 word.
        poolId = bytes32((uint256(uint160(pool)) << 24) | uint256(bestFee));
    }

    function _bestQuote(address tokenIn, address tokenOut, uint256 amountIn)
        internal
        returns (uint256 bestOut, uint24 bestFee)
    {
        uint24[3] memory fees = [FEE_LOW, FEE_MID, FEE_HIGH];
        for (uint256 i = 0; i < 3; i++) {
            try QUOTER.quoteExactInputSingle(
                IQuoterV2.QuoteExactInputSingleParams({
                    tokenIn: tokenIn, tokenOut: tokenOut, amountIn: amountIn, fee: fees[i], sqrtPriceLimitX96: 0
                })
            ) returns (
                uint256 out, uint160, uint32, uint256
            ) {
                if (out > bestOut) {
                    bestOut = out;
                    bestFee = fees[i];
                }
            } catch {}
        }
    }
}
