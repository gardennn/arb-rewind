// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Tokens {
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    // PEPE (meme coin) — used only in Phase 5 case studies.
    address internal constant PEPE = 0x6982508145454Ce325dDbE47a25d4ec3d2311933;

    uint8 internal constant WETH_DECIMALS = 18;
    uint8 internal constant USDC_DECIMALS = 6;
    uint8 internal constant USDT_DECIMALS = 6;
    uint8 internal constant DAI_DECIMALS = 18;
    uint8 internal constant WBTC_DECIMALS = 8;
    uint8 internal constant PEPE_DECIMALS = 18;

    function decimalsOf(address token) internal pure returns (uint8) {
        if (token == WETH) return WETH_DECIMALS;
        if (token == USDC) return USDC_DECIMALS;
        if (token == USDT) return USDT_DECIMALS;
        if (token == DAI) return DAI_DECIMALS;
        if (token == WBTC) return WBTC_DECIMALS;
        if (token == PEPE) return PEPE_DECIMALS;
        revert UnknownToken(token);
    }

    error UnknownToken(address token);
}
