// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ArbExecutor, ExecutionPlan, ExecutionResult, DexKind} from "../src/ArbExecutor.sol";
import {Tokens} from "../src/tokens/Tokens.sol";

// End-to-end executor test. Validates that a full Balancer flashloan ->
// triangle-swap -> repay cycle executes cleanly and that profit accounting
// (balanceEnd - balanceStart, flashloan amount cancels) is consistent.
//
// Historical block 16_810_500 is during the USDC depeg (Mar 11 2023). Actual
// profit on arbitrary paths is NOT guaranteed at any specific block — by
// this point MEV searchers had already compressed most 3pool skew. Finding a
// triangle that clears costs is a Phase 5 case-study concern. What this test
// proves: the executor wires up flashloan + multi-DEX dispatch + repayment
// without reverting, and returns a numerically coherent result.
contract ArbExecutorTest is Test {
    ArbExecutor executor;

    function setUp() public {
        vm.createSelectFork("mainnet", 16_810_500);
        executor = new ArbExecutor();
    }

    function test_triangle_runs_end_to_end() public {
        uint256 preFund = 100_000e6;
        uint256 flashAmount = 1_000e6;
        deal(Tokens.USDT, address(executor), preFund);

        DexKind[3] memory kinds = [DexKind.CURVE, DexKind.UNI_V3, DexKind.UNI_V3];
        address[3] memory path = [Tokens.USDT, Tokens.USDC, Tokens.WETH];
        // UniV3 fee tier encoded in poolId for _swapUniV3; Curve hop ignores its pool arg.
        bytes32[3] memory pools = [bytes32(0), bytes32(uint256(500)), bytes32(uint256(500))];

        ExecutionPlan memory plan = ExecutionPlan({kinds: kinds, path: path, pools: pools, amountIn: flashAmount});

        ExecutionResult memory r = executor.simulate(plan);

        emit log_named_int("profit (USDT base units)", r.profit);
        emit log_named_uint("gas used", r.gasUsed);

        assertEq(r.amountStart, preFund, "amountStart must equal pre-funded balance");
        assertEq(int256(r.amountEnd) - int256(r.amountStart), r.profit, "profit accounting inconsistent");
        assertGt(r.gasUsed, 0);
        // Slippage/fee friction should stay within 1% of the flashloan amount.
        int256 maxLoss = -int256(flashAmount) / 100;
        assertGt(r.profit, maxLoss, "unexpectedly large loss; probable dispatch bug");
    }
}
