// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {UniV2Scanner} from "../../src/scanners/UniV2Scanner.sol";
import {Tokens} from "../../src/tokens/Tokens.sol";

// Fork test. ETH price around Jan 30 2024 (block 19_000_000) ~ $2300.
// Etherscan WETH/USDC pair: 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc
// Expected 1 WETH → USDC in range [2000e6, 2600e6].
contract UniV2ScannerTest is Test {
    UniV2Scanner scanner;

    function setUp() public {
        vm.createSelectFork("mainnet", 19_000_000);
        scanner = new UniV2Scanner();
    }

    function test_quote_WETH_to_USDC() public {
        (uint256 out, bytes32 poolId) = scanner.quote(Tokens.WETH, Tokens.USDC, 1e18);
        assertTrue(out >= 2000e6 && out <= 2600e6, "quote outside expected range");
        assertTrue(poolId != bytes32(0), "poolId must be set");
        emit log_named_uint("1 WETH -> USDC", out);
    }
}
