// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CaseBase} from "./CaseBase.sol";
import {Tokens} from "../../src/tokens/Tokens.sol";
import {ArbCandidate} from "../../src/ArbDetector.sol";

// Historical context: May 27, 2024 - PEPE printed a fresh ATH above $1.7e-5
// on the back of retail speculation re-entering meme tokens. Block
// 19_980_000 falls inside the impulse move; PEPE-paired pools on UniV2 and
// UniV3 typically diverge most sharply on this kind of fast-repricing
// event because the two AMM models clear impulse flow at different speeds.
//
// Only UniV2 and UniV3 carry PEPE — Curve and Balancer return 0 for these
// legs, which the scanner-probe loop simply drops. The test exercises the
// same pipeline against a non-stable token and demonstrates that the
// log-space detector is indifferent to decimals / magnitudes.
contract CaseMemeSpikeTest is CaseBase {
    function setUp() public {
        vm.createSelectFork("mainnet", 19_980_000);
        _deployInfra();
    }

    function test_scan_and_detect_triangles() public {
        address[] memory tokens = new address[](4);
        tokens[0] = Tokens.WETH;
        tokens[1] = Tokens.USDC;
        tokens[2] = Tokens.USDT;
        tokens[3] = Tokens.PEPE;

        uint256[] memory probes = new uint256[](4);
        probes[0] = 1e18; // 1 WETH
        probes[1] = 1_000e6; // 1,000 USDC
        probes[2] = 1_000e6; // 1,000 USDT
        probes[3] = 1_000_000e18; // 1M PEPE (~$17 at ATH)

        _populateGraph(tokens, probes);

        address[] memory intermediates = new address[](3);
        intermediates[0] = Tokens.USDC;
        intermediates[1] = Tokens.USDT;
        intermediates[2] = Tokens.PEPE;

        ArbCandidate[] memory all = detector.findAllTriangles(Tokens.WETH, intermediates);
        ArbCandidate[] memory profitable = detector.findTriangles(Tokens.WETH, intermediates);

        emit log_named_uint("profitable triangles", profitable.length);
        _printTop(all, 5);

        assertGt(all.length, 0, "pipeline failed to enumerate any cycle");
    }
}
