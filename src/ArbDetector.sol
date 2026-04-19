// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PriceGraph, Edge} from "./PriceGraph.sol";
import {LogMath} from "./libraries/LogMath.sol";

struct ArbCandidate {
    address[3] path;
    bytes32[3] pools;
    int256 logProfit;
}

contract ArbDetector {
    PriceGraph public immutable graph;

    // Scratch flag avoids adding another arg to the stack-sensitive helper chain.
    bool private _onlyProfitable;

    constructor(PriceGraph graph_) {
        graph = graph_;
    }

    /// @notice Enumerate triangular cycles base -> B -> C -> base and return
    /// those with positive log-profit, sorted descending.
    function findTriangles(address baseToken, address[] calldata intermediates)
        external
        returns (ArbCandidate[] memory results)
    {
        return _enumerate(baseToken, intermediates, true);
    }

    /// @notice Like `findTriangles` but keeps cycles regardless of sign.
    /// Useful for case studies that want to show the best-available path even
    /// when no triangle clears friction. Sorted descending by logProfit.
    function findAllTriangles(address baseToken, address[] calldata intermediates)
        external
        returns (ArbCandidate[] memory results)
    {
        return _enumerate(baseToken, intermediates, false);
    }

    function _enumerate(address baseToken, address[] calldata intermediates, bool onlyProfitable)
        internal
        returns (ArbCandidate[] memory results)
    {
        _onlyProfitable = onlyProfitable;
        uint256 n = intermediates.length;
        ArbCandidate[] memory scratch = new ArbCandidate[](n * n);
        uint256 count;

        for (uint256 i = 0; i < n; i++) {
            address B = intermediates[i];
            if (B == baseToken) continue;

            (uint256 rateAB, bytes32 poolAB) = _bestEdge(baseToken, B);
            if (rateAB == 0) continue;

            count = _expandFromB(baseToken, B, rateAB, poolAB, intermediates, i, scratch, count);
        }

        results = new ArbCandidate[](count);
        for (uint256 k = 0; k < count; k++) {
            results[k] = scratch[k];
        }
        _sortDesc(results);
        delete _onlyProfitable;
    }

    function _expandFromB(
        address baseToken,
        address B,
        uint256 rateAB,
        bytes32 poolAB,
        address[] calldata intermediates,
        uint256 skipIdx,
        ArbCandidate[] memory scratch,
        uint256 count
    ) internal view returns (uint256) {
        uint256 n = intermediates.length;
        for (uint256 j = 0; j < n; j++) {
            if (j == skipIdx) continue;
            address C = intermediates[j];
            if (C == baseToken) continue;

            ArbCandidate memory cand = _tryCycle(baseToken, B, C, rateAB, poolAB);
            // path[0]==0 is the "no cycle" sentinel set by _tryCycle.
            if (cand.path[0] == address(0)) continue;
            if (_onlyProfitable && cand.logProfit <= 0) continue;
            scratch[count] = cand;
            count++;
        }
        return count;
    }

    function _tryCycle(address baseToken, address B, address C, uint256 rateAB, bytes32 poolAB)
        internal
        view
        returns (ArbCandidate memory cand)
    {
        (uint256 rateBC, bytes32 poolBC) = _bestEdge(B, C);
        if (rateBC == 0) return cand;
        (uint256 rateCA, bytes32 poolCA) = _bestEdge(C, baseToken);
        if (rateCA == 0) return cand;

        int256 logProfit = LogMath.ln(rateAB) + LogMath.ln(rateBC) + LogMath.ln(rateCA);

        cand = ArbCandidate({path: [baseToken, B, C], pools: [poolAB, poolBC, poolCA], logProfit: logProfit});
    }

    function _bestEdge(address tokenIn, address tokenOut) internal view returns (uint256 bestRate, bytes32 bestPool) {
        Edge[] memory edges = graph.getEdges(tokenIn, tokenOut);
        for (uint256 k = 0; k < edges.length; k++) {
            if (edges[k].rate1e18 > bestRate) {
                bestRate = edges[k].rate1e18;
                bestPool = edges[k].poolId;
            }
        }
    }

    function _sortDesc(ArbCandidate[] memory arr) internal pure {
        uint256 len = arr.length;
        for (uint256 i = 1; i < len; i++) {
            ArbCandidate memory cur = arr[i];
            uint256 j = i;
            while (j > 0 && arr[j - 1].logProfit < cur.logProfit) {
                arr[j] = arr[j - 1];
                j--;
            }
            arr[j] = cur;
        }
    }
}
