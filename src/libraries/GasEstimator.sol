// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library GasEstimator {
    /// @notice Convert a gas-used figure into a USD cost using the forked
    /// block's basefee and a provided WETH price (1e18 scaled).
    /// @dev Returned value is 1e18-scaled USD (wei-of-USD).
    function costInUSD(uint256 gasUsed, uint256 wethPriceUSD1e18) internal view returns (uint256) {
        uint256 gasPriceWei = block.basefee;
        uint256 weiCost = gasUsed * gasPriceWei;
        // weiCost (in 1e18 wei) * USD-per-WETH (1e18) / 1e18 wei-per-WETH = USD (1e18).
        return (weiCost * wethPriceUSD1e18) / 1e18;
    }
}
