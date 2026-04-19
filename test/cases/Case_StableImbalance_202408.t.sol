// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CaseBase} from "./CaseBase.sol";
import {Tokens} from "../../src/tokens/Tokens.sol";
import {ArbCandidate} from "../../src/ArbDetector.sol";

// Historical context: Aug 5, 2024 - The Yen-carry-trade unwind crash. A sharp
// BoJ rate hike triggered a violent deleveraging cascade: ETH fell ~22% over
// ~36h, on-chain liquidations burned through stablecoin routes, and stable
// pools briefly lost peg symmetry under one-sided flow.
//
// Block 20_480_000 is ~midnight UTC Aug 5 2024 — during the opening hours
// of the cascade. Same structure as T5.1: scan, detect, print. We are not
// asserting profit — the point is to look at stable rates during stress and
// verify the pipeline extracts a coherent snapshot.
contract CaseStableImbalance202408Test is CaseBase {
    function setUp() public {
        vm.createSelectFork("mainnet", 20_480_000);
        _deployInfra();
    }

    function test_scan_and_detect_triangles() public {
        address[] memory tokens = new address[](4);
        tokens[0] = Tokens.USDC;
        tokens[1] = Tokens.USDT;
        tokens[2] = Tokens.DAI;
        tokens[3] = Tokens.WETH;

        uint256[] memory probes = new uint256[](4);
        probes[0] = 100_000e6;
        probes[1] = 100_000e6;
        probes[2] = 100_000e18;
        probes[3] = 50e18;

        _populateGraph(tokens, probes);

        address[] memory intermediates = new address[](3);
        intermediates[0] = Tokens.USDT;
        intermediates[1] = Tokens.DAI;
        intermediates[2] = Tokens.WETH;

        ArbCandidate[] memory all = detector.findAllTriangles(Tokens.USDC, intermediates);
        ArbCandidate[] memory profitable = detector.findTriangles(Tokens.USDC, intermediates);

        emit log_named_uint("profitable triangles", profitable.length);
        _printTop(all, 5);

        assertGt(all.length, 0, "pipeline failed to enumerate any cycle");
    }
}
