// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {wadLn} from "solmate/utils/SignedWadMath.sol";

library LogMath {
    error NonPositiveInput();

    function ln(uint256 x1e18) internal pure returns (int256) {
        if (x1e18 == 0) revert NonPositiveInput();
        return wadLn(int256(x1e18));
    }
}
