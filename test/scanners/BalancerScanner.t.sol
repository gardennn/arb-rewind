// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BalancerScanner} from "../../src/scanners/BalancerScanner.sol";
import {Tokens} from "../../src/tokens/Tokens.sol";

// staBAL3 pool (0x06df3b2b...9f91b42 / poolId ...0063) at block 19_000_000.
// 1 USDC (1e6) -> DAI (1e18) should be close to peg (0.990e18 - 1.010e18).
contract BalancerScannerTest is Test {
    BalancerScanner scanner;

    function setUp() public {
        vm.createSelectFork("mainnet", 19_000_000);
        scanner = new BalancerScanner();
    }

    function test_quote_USDC_to_DAI() public {
        (uint256 out, bytes32 poolId) = scanner.quote(Tokens.USDC, Tokens.DAI, 1e6);
        emit log_named_uint("1 USDC -> DAI (staBAL3, 1e18)", out);
        emit log_named_bytes32("poolId", poolId);
        assertTrue(out > 0, "quote returned zero");
        assertTrue(out >= 0.99e18 && out <= 1.01e18, "stable pool peg out of range");
    }
}
