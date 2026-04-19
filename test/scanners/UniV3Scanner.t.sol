// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {UniV3Scanner} from "../../src/scanners/UniV3Scanner.sol";
import {Tokens} from "../../src/tokens/Tokens.sol";

// Fork test. Block 19_000_000 (~Jan 30 2024, ETH ~ $2300-2600).
// The 0.05% WETH/USDC pool (0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640) is
// the deepest for this pair and should win the iteration.
contract UniV3ScannerTest is Test {
    UniV3Scanner scanner;

    function setUp() public {
        vm.createSelectFork("mainnet", 19_000_000);
        scanner = new UniV3Scanner();
    }

    function test_quote_WETH_to_USDC() public {
        (uint256 out, bytes32 poolId) = scanner.quote(Tokens.WETH, Tokens.USDC, 1e18);
        assertTrue(out >= 2000e6 && out <= 2800e6, "quote outside expected range");
        assertTrue(poolId != bytes32(0), "poolId must be set");
        emit log_named_uint("1 WETH -> USDC (best V3 tier)", out);
    }

    // Contract lock-in: the low 24 bits of poolId MUST be the winning fee tier
    // so ArbExecutor._swapUniV3 (which does `uint24(uint256(poolId))`) decodes
    // correctly. The upper 160 bits carry the pool address.
    function test_poolId_encodes_fee_in_low_24_bits() public {
        (, bytes32 poolId) = scanner.quote(Tokens.WETH, Tokens.USDC, 1e18);
        uint24 fee = uint24(uint256(poolId));
        assertTrue(fee == 500 || fee == 3000 || fee == 10000, "fee tier not in low 24 bits");
        address pool = address(uint160(uint256(poolId) >> 24));
        assertTrue(pool != address(0), "pool address lost from upper bits");
    }
}
