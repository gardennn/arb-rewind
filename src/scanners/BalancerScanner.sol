// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IScanner} from "./IScanner.sol";
import {Tokens} from "../tokens/Tokens.sol";

interface IBalancerVault {
    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }

    struct BatchSwapStep {
        bytes32 poolId;
        uint256 assetInIndex;
        uint256 assetOutIndex;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address recipient;
        bool toInternalBalance;
    }

    function queryBatchSwap(
        SwapKind kind,
        BatchSwapStep[] memory swaps,
        address[] memory assets,
        FundManagement memory funds
    ) external returns (int256[] memory assetDeltas);
}

contract BalancerScanner is IScanner {
    IBalancerVault public constant VAULT = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    // staBAL3: DAI/USDC/USDT stable pool (Balancer V2 original "3pool").
    bytes32 public constant STABAL3_ID = 0x06df3b2bbb68adc8b0e302443692037ed9f91b42000000000000000000000063;

    function quote(address tokenIn, address tokenOut, uint256 amountIn)
        external
        returns (uint256 amountOut, bytes32 poolId)
    {
        if (amountIn == 0 || tokenIn == tokenOut) return (0, bytes32(0));

        bytes32 target = _poolFor(tokenIn, tokenOut);
        if (target == bytes32(0)) return (0, bytes32(0));

        address[] memory assets = new address[](2);
        assets[0] = tokenIn;
        assets[1] = tokenOut;

        IBalancerVault.BatchSwapStep[] memory swaps = new IBalancerVault.BatchSwapStep[](1);
        swaps[0] = IBalancerVault.BatchSwapStep({
            poolId: target, assetInIndex: 0, assetOutIndex: 1, amount: amountIn, userData: ""
        });

        IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
            sender: address(this), fromInternalBalance: false, recipient: address(this), toInternalBalance: false
        });

        try VAULT.queryBatchSwap(IBalancerVault.SwapKind.GIVEN_IN, swaps, assets, funds) returns (
            int256[] memory deltas
        ) {
            // Delta for tokenOut (index 1) is negative: vault pays out.
            int256 outDelta = deltas[1];
            if (outDelta >= 0) return (0, bytes32(0));
            amountOut = uint256(-outDelta);
            poolId = target;
        } catch {
            return (0, bytes32(0));
        }
    }

    function _poolFor(address a, address b) internal pure returns (bytes32) {
        if (_isStaBal3Token(a) && _isStaBal3Token(b)) return STABAL3_ID;
        return bytes32(0);
    }

    function _isStaBal3Token(address t) internal pure returns (bool) {
        return t == Tokens.DAI || t == Tokens.USDC || t == Tokens.USDT;
    }
}
