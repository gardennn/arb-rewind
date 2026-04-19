// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CurveScanner} from "../../src/scanners/CurveScanner.sol";
import {Tokens} from "../../src/tokens/Tokens.sol";

// 1 USDC (1e6) → DAI (18 decimals) through Curve 3pool at block 19_000_000.
// Pool is a StableSwap invariant; quote should be very close to 1.0 DAI (0.995-1.005).
contract CurveScannerTest is Test {
    CurveScanner scanner;

    function setUp() public {
        vm.createSelectFork("mainnet", 19_000_000);
        scanner = new CurveScanner();
    }

    function test_quote_USDC_to_DAI() public {
        (uint256 out, bytes32 poolId) = scanner.quote(Tokens.USDC, Tokens.DAI, 1e6);
        assertTrue(out >= 0.995e18 && out <= 1.005e18, "stablecoin peg out of range");
        assertTrue(poolId != bytes32(0), "poolId must be set");
        emit log_named_uint("1 USDC -> DAI (3pool, 1e18)", out);
    }
}
