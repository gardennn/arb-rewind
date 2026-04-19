// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IScanner} from "./IScanner.sol";
import {Tokens} from "../tokens/Tokens.sol";

interface ICurve3Pool {
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
}

contract CurveScanner is IScanner {
    address public constant THREE_POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;

    function quote(address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        returns (uint256 amountOut, bytes32 poolId)
    {
        if (amountIn == 0 || tokenIn == tokenOut) return (0, bytes32(0));

        int128 i = _indexOf(tokenIn);
        int128 j = _indexOf(tokenOut);
        if (i < 0 || j < 0) return (0, bytes32(0));

        try ICurve3Pool(THREE_POOL).get_dy(i, j, amountIn) returns (uint256 out) {
            amountOut = out;
            poolId = bytes32(uint256(uint160(THREE_POOL)));
        } catch {
            return (0, bytes32(0));
        }
    }

    function _indexOf(address token) internal pure returns (int128) {
        if (token == Tokens.DAI) return 0;
        if (token == Tokens.USDC) return 1;
        if (token == Tokens.USDT) return 2;
        return -1;
    }
}
