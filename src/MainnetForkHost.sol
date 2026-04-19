// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

abstract contract MainnetForkHost is Test {
    uint256 internal mainnetFork;

    constructor(uint256 blockNumber) {
        mainnetFork = vm.createSelectFork("mainnet", blockNumber);
    }

    modifier atBlock(uint256 blockNumber) {
        vm.selectFork(mainnetFork);
        vm.rollFork(blockNumber);
        _;
    }
}
