// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LogMath} from "../../src/libraries/LogMath.sol";

contract LogMathTest is Test {
    int256 constant TOL = 1e12;

    function test_ln_one_is_zero() public pure {
        int256 result = LogMath.ln(1e18);
        assertApprox(result, 0);
    }

    function test_ln_two() public pure {
        // ln(2) ≈ 0.6931471805599453
        int256 result = LogMath.ln(2e18);
        assertApprox(result, 693147180559945309);
    }

    function test_ln_e_is_one() public pure {
        // e ≈ 2.718281828459045235
        int256 result = LogMath.ln(2718281828459045235);
        assertApprox(result, 1e18);
    }

    function assertApprox(int256 actual, int256 expected) internal pure {
        int256 diff = actual - expected;
        if (diff < 0) diff = -diff;
        require(diff <= TOL, "LogMath tolerance exceeded");
    }
}
