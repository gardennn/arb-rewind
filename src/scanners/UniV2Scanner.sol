// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IScanner} from "./IScanner.sol";

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
}

contract UniV2Scanner is IScanner {
    IUniswapV2Factory public constant FACTORY = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);

    function quote(address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        returns (uint256 amountOut, bytes32 poolId)
    {
        address pair = FACTORY.getPair(tokenIn, tokenOut);
        if (pair == address(0) || amountIn == 0) return (0, bytes32(0));

        (uint112 r0, uint112 r1,) = IUniswapV2Pair(pair).getReserves();
        if (r0 == 0 || r1 == 0) return (0, bytes32(0));

        address token0 = IUniswapV2Pair(pair).token0();
        (uint256 reserveIn, uint256 reserveOut) =
            tokenIn == token0 ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
        poolId = bytes32(uint256(uint160(pair)));
    }
}
