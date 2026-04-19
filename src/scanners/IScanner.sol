// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IScanner {
    // Not marked `view` on purpose: Uniswap V3 and Balancer V2 quoting
    // relies on revert-trick helpers that are not statically callable.
    // Implementations that happen to be pure/view can still conform.
    function quote(address tokenIn, address tokenOut, uint256 amountIn)
        external
        returns (uint256 amountOut, bytes32 poolId);
}
