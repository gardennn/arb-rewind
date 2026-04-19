// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

enum DexKind {
    UNI_V2,
    UNI_V3,
    CURVE,
    BALANCER
}

struct ExecutionPlan {
    DexKind[3] kinds;
    address[3] path; // [A, B, C]; cycle closes back to A
    bytes32[3] pools; // interpretation depends on DexKind
    uint256 amountIn; // amount of path[0] to flashloan
}

struct ExecutionResult {
    uint256 amountStart;
    uint256 amountEnd;
    int256 profit;
    uint256 gasUsed;
}

interface IBalancerVault {
    function flashLoan(address recipient, address[] memory tokens, uint256[] memory amounts, bytes memory userData)
        external;

    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }

    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        address assetIn;
        address assetOut;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address recipient;
        bool toInternalBalance;
    }

    function swap(SingleSwap memory singleSwap, FundManagement memory funds, uint256 limit, uint256 deadline)
        external
        returns (uint256 amountCalculated);
}

interface IUniV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IUniV3Router {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface ICurve3Pool {
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
}

/// @notice Simulates a triangular arbitrage using a Balancer V2 flashloan.
/// Always runs inside a forked environment; never for live trading.
contract ArbExecutor {
    using SafeTransferLib for ERC20;

    IBalancerVault public constant VAULT = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IUniV2Router public constant UNIV2_ROUTER = IUniV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IUniV3Router public constant UNIV3_ROUTER = IUniV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address public constant CURVE_3POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;

    error NotVault();
    error UnexpectedFeeCharged();

    // Transient state for the flashloan callback.
    ExecutionPlan private _plan;
    uint256 private _balanceBeforeLoan;

    /// @notice Entry point. Runs the triangle via flashloan and returns the
    /// amount of path[0] held by this contract before and after.
    function simulate(ExecutionPlan calldata plan) external returns (ExecutionResult memory result) {
        uint256 gasStart = gasleft();

        _plan = plan;
        _balanceBeforeLoan = ERC20(plan.path[0]).balanceOf(address(this));

        address[] memory tokens = new address[](1);
        tokens[0] = plan.path[0];
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = plan.amountIn;

        VAULT.flashLoan(address(this), tokens, amounts, "");

        uint256 balanceAfter = ERC20(plan.path[0]).balanceOf(address(this));

        result.amountStart = _balanceBeforeLoan;
        result.amountEnd = balanceAfter;
        result.profit = int256(balanceAfter) - int256(_balanceBeforeLoan);
        result.gasUsed = gasStart - gasleft();

        delete _plan;
        delete _balanceBeforeLoan;
    }

    /// @notice Balancer V2 flashloan callback. Executes A->B->C->A.
    function receiveFlashLoan(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes calldata
    ) external {
        if (msg.sender != address(VAULT)) revert NotVault();
        if (feeAmounts[0] != 0) revert UnexpectedFeeCharged();

        _runTriangle(amounts[0]);

        // Repay the flashloan (Balancer V2 fee is zero).
        ERC20(tokens[0]).safeTransfer(address(VAULT), amounts[0]);
    }

    function _runTriangle(uint256 amountIn) internal {
        ExecutionPlan memory plan = _plan;
        uint256 amt = _swap(plan.kinds[0], plan.path[0], plan.path[1], amountIn, plan.pools[0]);
        amt = _swap(plan.kinds[1], plan.path[1], plan.path[2], amt, plan.pools[1]);
        _swap(plan.kinds[2], plan.path[2], plan.path[0], amt, plan.pools[2]);
    }

    function _swap(DexKind kind, address tokenIn, address tokenOut, uint256 amountIn, bytes32 poolId)
        internal
        returns (uint256 out)
    {
        if (kind == DexKind.UNI_V2) {
            return _swapUniV2(tokenIn, tokenOut, amountIn);
        }
        if (kind == DexKind.UNI_V3) {
            return _swapUniV3(tokenIn, tokenOut, amountIn, uint24(uint256(poolId)));
        }
        if (kind == DexKind.CURVE) {
            return _swapCurve(tokenIn, tokenOut, amountIn);
        }
        if (kind == DexKind.BALANCER) {
            return _swapBalancer(tokenIn, tokenOut, amountIn, poolId);
        }
        revert("unknown DexKind");
    }

    function _swapUniV2(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256) {
        ERC20(tokenIn).safeApprove(address(UNIV2_ROUTER), amountIn);
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        uint256[] memory amounts =
            UNIV2_ROUTER.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp);
        return amounts[amounts.length - 1];
    }

    function _swapUniV3(address tokenIn, address tokenOut, uint256 amountIn, uint24 fee) internal returns (uint256) {
        ERC20(tokenIn).safeApprove(address(UNIV3_ROUTER), amountIn);
        return UNIV3_ROUTER.exactInputSingle(
            IUniV3Router.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    function _swapCurve(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256) {
        int128 i = _curveIndex(tokenIn);
        int128 j = _curveIndex(tokenOut);
        ERC20(tokenIn).safeApprove(CURVE_3POOL, amountIn);
        uint256 before = ERC20(tokenOut).balanceOf(address(this));
        ICurve3Pool(CURVE_3POOL).exchange(i, j, amountIn, 0);
        return ERC20(tokenOut).balanceOf(address(this)) - before;
    }

    function _swapBalancer(address tokenIn, address tokenOut, uint256 amountIn, bytes32 poolId)
        internal
        returns (uint256)
    {
        ERC20(tokenIn).safeApprove(address(VAULT), amountIn);
        return VAULT.swap(
            IBalancerVault.SingleSwap({
                poolId: poolId,
                kind: IBalancerVault.SwapKind.GIVEN_IN,
                assetIn: tokenIn,
                assetOut: tokenOut,
                amount: amountIn,
                userData: ""
            }),
            IBalancerVault.FundManagement({
                sender: address(this), fromInternalBalance: false, recipient: address(this), toInternalBalance: false
            }),
            0,
            block.timestamp
        );
    }

    function _curveIndex(address token) internal pure returns (int128) {
        // 3pool ordering: DAI (0x6B17...) = 0, USDC (0xA0b8...) = 1, USDT (0xdAC1...) = 2.
        if (token == 0x6B175474E89094C44Da98b954EedeAC495271d0F) return 0;
        if (token == 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) return 1;
        if (token == 0xdAC17F958D2ee523a2206206994597C13D831ec7) return 2;
        revert("non-3pool token");
    }
}
