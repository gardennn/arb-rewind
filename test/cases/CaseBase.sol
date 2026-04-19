// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {UniV2Scanner} from "../../src/scanners/UniV2Scanner.sol";
import {UniV3Scanner} from "../../src/scanners/UniV3Scanner.sol";
import {CurveScanner} from "../../src/scanners/CurveScanner.sol";
import {BalancerScanner} from "../../src/scanners/BalancerScanner.sol";
import {IScanner} from "../../src/scanners/IScanner.sol";
import {PriceGraph, Edge} from "../../src/PriceGraph.sol";
import {ArbDetector, ArbCandidate} from "../../src/ArbDetector.sol";
import {LogMath} from "../../src/libraries/LogMath.sol";
import {Tokens} from "../../src/tokens/Tokens.sol";

/// @notice Harness for Phase 5 case studies. Each test forks a historical block,
/// probes all four scanners for a chosen token set, loads the PriceGraph, and
/// invokes the detector. Subclasses just call `_runCase` with a token matrix.
abstract contract CaseBase is Test {
    UniV2Scanner internal v2;
    UniV3Scanner internal v3;
    CurveScanner internal curv;
    BalancerScanner internal bal;
    PriceGraph internal graph;
    ArbDetector internal detector;

    // Names for human-readable log output (maps scanner address -> label).
    mapping(address => string) internal _dexName;

    function _deployInfra() internal {
        v2 = new UniV2Scanner();
        v3 = new UniV3Scanner();
        curv = new CurveScanner();
        bal = new BalancerScanner();
        graph = new PriceGraph();
        detector = new ArbDetector(graph);

        _dexName[address(v2)] = "UniV2";
        _dexName[address(v3)] = "UniV3";
        _dexName[address(curv)] = "Curve";
        _dexName[address(bal)] = "Balancer";
    }

    /// @notice Probe every ordered pair (tokens[i], tokens[j]) with `probe[i]`
    /// on all four DEXes, inserting every non-zero quote as an Edge.
    function _populateGraph(address[] memory tokens, uint256[] memory probes) internal {
        require(tokens.length == probes.length, "len mismatch");
        uint256 n = tokens.length;
        for (uint256 i = 0; i < n; i++) {
            for (uint256 j = 0; j < n; j++) {
                if (i == j) continue;
                _probeAll(tokens[i], tokens[j], probes[i]);
            }
        }
    }

    function _probeAll(address tokenIn, address tokenOut, uint256 probe) internal {
        _probeOne(IScanner(address(v2)), tokenIn, tokenOut, probe);
        _probeOne(IScanner(address(v3)), tokenIn, tokenOut, probe);
        _probeOne(IScanner(address(curv)), tokenIn, tokenOut, probe);
        _probeOne(IScanner(address(bal)), tokenIn, tokenOut, probe);
    }

    function _probeOne(IScanner scanner, address tokenIn, address tokenOut, uint256 probe) internal {
        try scanner.quote(tokenIn, tokenOut, probe) returns (uint256 out, bytes32 poolId) {
            if (out == 0) return;
            uint256 rate = _toRate1e18(probe, out, Tokens.decimalsOf(tokenIn), Tokens.decimalsOf(tokenOut));
            if (rate == 0) return;
            graph.addEdge(
                Edge({
                    dexAdapter: address(scanner),
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    rate1e18: rate,
                    feeTier: 0,
                    poolId: poolId
                })
            );
            _logEdge(scanner, tokenIn, tokenOut, rate);
        } catch {}
    }

    /// @notice Emit a single edge for human-readable scan output.
    function _logEdge(IScanner scanner, address tokenIn, address tokenOut, uint256 rate1e18) internal {
        emit log_named_decimal_uint(
            string.concat(_dexName[address(scanner)], " ", _symbol(tokenIn), "->", _symbol(tokenOut), " rate"),
            rate1e18,
            18
        );
    }

    function _toRate1e18(uint256 inAmt, uint256 outAmt, uint8 decIn, uint8 decOut) internal pure returns (uint256) {
        uint256 inNorm = _scale18(inAmt, decIn);
        uint256 outNorm = _scale18(outAmt, decOut);
        if (inNorm == 0) return 0;
        return (outNorm * 1e18) / inNorm;
    }

    function _scale18(uint256 x, uint8 dec) internal pure returns (uint256) {
        if (dec == 18) return x;
        if (dec < 18) return x * (10 ** (18 - dec));
        return x / (10 ** (dec - 18));
    }

    /// @notice Print the top `k` candidates one line each, in the form
    ///   `  logProfit (1e18): <n>   (SYMA->SYMB->SYMC->SYMA, <pct>%)`
    function _printTop(ArbCandidate[] memory cands, uint256 k) internal {
        emit log("------- top candidates -------");
        uint256 shown = cands.length < k ? cands.length : k;
        for (uint256 i = 0; i < shown; i++) {
            ArbCandidate memory c = cands[i];
            string memory path = string.concat(
                _symbol(c.path[0]), "->", _symbol(c.path[1]), "->", _symbol(c.path[2]), "->", _symbol(c.path[0])
            );
            emit log(string.concat(
                    "  logProfit (1e18): ", vm.toString(c.logProfit), "   (", path, ", ", _fmtPct(c.logProfit), ")"
                ));
        }
        emit log_named_uint("total candidates", cands.length);
    }

    /// @notice Format a log-profit value (1e18-scaled) as a percent string with
    /// 4 decimal places (truncated toward zero). For small x, ln(1+x) ≈ x, so
    /// this is a close approximation of actual round-trip percent return.
    function _fmtPct(int256 log1e18) internal pure returns (string memory) {
        // percent * 1e4  =  ln(product) * 100 * 1e4  =  log1e18 / 1e12
        int256 pctE4 = log1e18 / int256(1e12);
        bool neg = pctE4 < 0;
        uint256 abs = uint256(neg ? -pctE4 : pctE4);
        uint256 whole = abs / 10000;
        uint256 frac = abs % 10000;
        string memory body = string.concat(vm.toString(whole), ".", _pad4(frac), "%");
        return neg ? string.concat("-", body) : body;
    }

    function _pad4(uint256 x) internal pure returns (string memory) {
        if (x >= 1000) return vm.toString(x);
        if (x >= 100) return string.concat("0", vm.toString(x));
        if (x >= 10) return string.concat("00", vm.toString(x));
        return string.concat("000", vm.toString(x));
    }

    function _symbol(address t) internal pure returns (string memory) {
        if (t == Tokens.WETH) return "WETH";
        if (t == Tokens.USDC) return "USDC";
        if (t == Tokens.USDT) return "USDT";
        if (t == Tokens.DAI) return "DAI";
        if (t == Tokens.WBTC) return "WBTC";
        if (t == Tokens.PEPE) return "PEPE";
        return "???";
    }
}
