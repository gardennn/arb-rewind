# arb-rewind

> Rewind mainnet to any block. Scan DEXes. Find the arbitrage you missed.

A Foundry-based historical arbitrage backtesting engine for EVM DEXes.
Forks mainnet at any block, quotes 4 DEX families (Uniswap V2/V3, Curve,
Balancer V2), and runs a log-space triangular arbitrage detector across
every A→B→C→A cycle. An executor path simulates a Balancer V2 flashloan
end-to-end to prove the winning cycle would settle.

No private keys. No live transactions. Everything runs inside `forge test`.

## Quick start

```bash
cp .env.example .env   # set MAINNET_RPC_URL
forge install          # or: git submodule update --init --recursive
source .env && forge test
```

First run is cold-fork slow (30–120s per case); subsequent runs cache in
`~/.foundry/cache/`.

## Example — USDC depeg, Mar 11 2023 @ block 16,804,000

A few hours after SVB froze Circle's USDC reserve, before MEV searchers
had fully closed the window:

```
  UniV2 USDC->USDT rate: 0.902158493700000000
  UniV3 USDC->USDT rate: 0.903699397700000000
  Curve USDC->USDT rate: 0.905973036800000000
  UniV2 USDC->DAI rate:  0.974088341049807260
  UniV3 USDC->DAI rate:  0.977605082165469346
  ...
  profitable triangles: 4
  ------- top candidates -------
    logProfit (1e18): 1556908663373049   (USDC->WETH->DAI->USDC,  +0.1556%)
    logProfit (1e18): 1297802508273535   (USDC->DAI->USDT->USDC,  +0.1297%)
    logProfit (1e18):  888461768292190   (USDC->WETH->USDT->USDC, +0.0888%)
    logProfit (1e18):  503736545450560   (USDC->USDT->WETH->USDC, +0.0503%)
```

Four closed triangles with positive log-profit, peaking at **+0.1556%** —
a real, MEV-available arb sitting on-chain at that block. The test pins
it in place with `assertGt(profitable.length, 0)`.

Point any case file's `vm.createSelectFork` at a different block to scan
your own moment in history. See [`test/cases/`](test/cases/) for three
worked examples (USDC depeg, yen-carry unwind, PEPE spike) and
[`docs/HISTORICAL_MOMENTS.md`][hm] for per-case narrative.

## Architecture

```
           +------------------+
           | Case test (fork) |
           +--------+---------+
                    |
                    v
           +------------------+       +------------------+
           |  Scanners x 4    | ----> |   PriceGraph     |
           |  V2/V3/Curve/Bal |       |  (edge index)    |
           +------------------+       +--------+---------+
                                               |
                                               v
                                      +------------------+
                                      |   ArbDetector    |
                                      |  (log-space,     |
                                      |   greedy/hop)    |
                                      +--------+---------+
                                               |
                     (optional execution path) |
                                               v
                                      +------------------+
                                      |   ArbExecutor    |
                                      |  (Balancer V2    |
                                      |   flashloan +    |
                                      |   multi-DEX)     |
                                      +------------------+
```

- **Scanners** read DEX state at the forked block (no writes).
- **PriceGraph** indexes directed rate edges per token pair.
- **ArbDetector** enumerates A→B→C→A triangles; ranks by
  `ln(r_AB) + ln(r_BC) + ln(r_CA)`. Positive sum = profitable cycle.
- **ArbExecutor** runs the ranked cycle inside the fork via a zero-fee
  Balancer V2 flashloan. `test/ArbExecutor.t.sol` proves dispatch
  correctness (not profit — see limitations).

Math details in [`docs/ALGORITHM.md`](docs/ALGORITHM.md).

## Limitations

- **Triangles only.** No 4+ cycles. Real 2024+ arb paths are often multi-hop.
- **Greedy per-hop edge choice.** Picks best-quoted venue per hop; does not
  jointly optimize edge selection with trade size.
- **Fixed probe size per token.** One quote size per case; no slippage
  curve sweep.
- **Research surface, not a production searcher.** No mempool awareness,
  no tick-level V3 math, no bundle competition. Surfaces market structure;
  does not capture it.

## Repo layout

```
src/
  scanners/    4 DEX quote adapters
  ArbDetector  triangle enumeration (log-space)
  ArbExecutor  flashloan + multi-DEX dispatch
  PriceGraph   directed edge index
test/
  scanners/    per-DEX fork tests
  cases/       historical case studies
  ArbExecutor  end-to-end flashloan test
```

## License

MIT. See [LICENSE](LICENSE).

[hm]: docs/HISTORICAL_MOMENTS.md