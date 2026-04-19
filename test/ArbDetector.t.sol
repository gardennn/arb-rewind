// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PriceGraph, Edge} from "../src/PriceGraph.sol";
import {ArbDetector, ArbCandidate} from "../src/ArbDetector.sol";

contract ArbDetectorTest is Test {
    address constant A = address(0xA);
    address constant B = address(0xB);
    address constant C = address(0xC);
    address constant D = address(0xD); // decoy, no profitable cycle

    PriceGraph graph;
    ArbDetector detector;

    function setUp() public {
        graph = new PriceGraph();
        detector = new ArbDetector(graph);
    }

    function _addEdge(address tokenIn, address tokenOut, uint256 rate1e18) internal {
        graph.addEdge(
            Edge({
                dexAdapter: address(this),
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                rate1e18: rate1e18,
                feeTier: 0,
                poolId: keccak256(abi.encodePacked(tokenIn, tokenOut))
            })
        );
    }

    function test_finds_one_profitable_triangle() public {
        // Profitable cycle A -> B -> C -> A with product 1.01 (~1% gross).
        _addEdge(A, B, 1e18);
        _addEdge(B, C, 1e18);
        _addEdge(C, A, 1.01e18);

        // D has edges but no triangle closes back to A with profit.
        _addEdge(A, D, 1e18);
        _addEdge(D, A, 0.9e18); // loss cycle

        address[] memory intermediates = new address[](3);
        intermediates[0] = B;
        intermediates[1] = C;
        intermediates[2] = D;

        ArbCandidate[] memory results = detector.findTriangles(A, intermediates);

        assertEq(results.length, 1, "expected exactly one profitable triangle");
        assertEq(results[0].path[0], A);
        assertEq(results[0].path[1], B);
        assertEq(results[0].path[2], C);
        // ln(1.01) ≈ 9.95e15; allow 1e13 tolerance.
        int256 expected = 9950330853168083; // ln(1.01) * 1e18
        int256 diff = results[0].logProfit - expected;
        if (diff < 0) diff = -diff;
        assertTrue(diff < 1e13, "logProfit mismatch");
    }

    function test_no_triangle_when_cycle_unprofitable() public {
        _addEdge(A, B, 1e18);
        _addEdge(B, C, 1e18);
        _addEdge(C, A, 0.99e18);

        address[] memory intermediates = new address[](2);
        intermediates[0] = B;
        intermediates[1] = C;

        ArbCandidate[] memory results = detector.findTriangles(A, intermediates);
        assertEq(results.length, 0);
    }

    function test_ranks_by_logProfit_desc() public {
        // Two profitable cycles: A->B->C->A (1.01) and A->C->B->A (1.02)
        _addEdge(A, B, 1e18);
        _addEdge(B, C, 1e18);
        _addEdge(C, A, 1.01e18);
        _addEdge(A, C, 1e18);
        _addEdge(C, B, 1e18);
        _addEdge(B, A, 1.02e18);

        address[] memory intermediates = new address[](2);
        intermediates[0] = B;
        intermediates[1] = C;

        ArbCandidate[] memory results = detector.findTriangles(A, intermediates);
        assertEq(results.length, 2);
        assertTrue(results[0].logProfit > results[1].logProfit, "not sorted desc");
    }
}
