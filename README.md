# arb-rewind

> Rewind mainnet to any block. Scan DEXes. Find the arbitrage you missed.

A Foundry-based historical arbitrage backtesting engine for EVM DEXes.
Given any historical block number, it forks mainnet at that block, scans
four DEX families (Uniswap V2, Uniswap V3, Curve 3pool, Balancer V2), and
runs a log-space triangular arbitrage detector across every A→B→C→A cycle
it can enumerate. An optional executor path simulates a Balancer V2
flashloan + multi-DEX dispatch to prove that the winning cycle would
actually settle.

**This is not a trading bot.** It has no private keys, sends no
transactions, and cannot leave the forked environment.

---

## What it does

- Forks mainnet at a block you choose (`vm.createSelectFork`).
- Quotes every pair you hand it across four DEX families in parallel.
- Normalizes rates to 1e18 fixed-point (decimals-independent).
- Finds every closed triangle A→B→C→A for a chosen base token and sorts
  them by log-profit.
- Optionally runs the cycle through a flashloan executor inside the fork
  to produce a net-of-fees profit figure.

## Why it exists

MEV searchers compress arb windows on the order of blocks. Retail tools
that watch the mempool cannot keep up. But the question "what did the
market look like at block X, and what arb was structurally available?"
is *static* — every answer lives in historical state. This tool answers
that question for a Foundry user in one `forge test`.

## Quick start

```bash
# 1. Put a mainnet archive RPC URL in .env (Alchemy, Infura, QuickNode, etc.)
cp .env.example .env
echo "MAINNET_RPC_URL=https://your-archive-rpc" >> .env

# 2. Install submodules
forge install

# 3. Run everything (unit + fork + case tests)
source .env && forge test
```

First run is slow (each case forks mainnet at a historical block and
cold-loads state — expect 30–120s per case). Subsequent runs reuse the
local fork cache in `~/.foundry/cache/`.

## How to "test" the tool (what commands to run)

Everything is driven by `forge test`. Targeted invocations:

```bash
# Show every per-DEX rate + top 5 candidates for each historical case.
# This is the main "is it working?" command — the interesting output.
source .env && forge test --match-path "test/cases/*" -vv

# Just one case, maximum verbosity (all edge quotes + ranked cycles).
source .env && forge test --match-contract CaseUSDCDepeg202303Test -vvv

# Unit + scanner + executor tests, no case studies (fast sanity check).
source .env && forge test --no-match-path "test/cases/*"

# Single scanner fork test (fastest way to validate an RPC/fork setup).
source .env && forge test --match-contract UniV2ScannerTest -vv

# Profile gas per test.
source .env && forge test --gas-report
```

### Pick your own block

Every case file has a block number near the top. Edit and re-run:

```solidity
// test/cases/Case_USDCDepeg_202303.t.sol
vm.createSelectFork("mainnet", 16_818_000);   // ← change this
```

Then `forge test --match-contract CaseUSDCDepeg202303Test -vv` to see what
the tool would have found at your chosen block.

### What to look for in the output

Each case test prints, in order:

1. **Every scanner edge** it found (`UniV2 USDC->USDT rate: 0.9967...`).
   Useful for spotting which DEX was offering the best rate on which leg.
2. **Count of profitable triangles** (`profitable triangles: 0`).
   Zero is normal and expected at most blocks — it means MEV already
   arbed the opportunity.
3. **Top 5 candidates by log-profit**, including negative ones. This is the
   real signal: how far below friction the best near-miss was. A cluster
   near `-3e14` = ~-0.03% = arbed-to-the-floor; a cycle near `+1e16` =
   ~+1% = you found a real one.

## Example output

From `test/cases/Case_USDCDepeg_202303.t.sol` at block 16,818,000:

```
  UniV2 USDC->USDT rate: 0.979744880700000000
  UniV3 USDC->USDT rate: 0.987451619600000000
  Curve USDC->USDT rate: 0.987605095700000000
  Balancer USDC->USDT rate: 0.986846785200000000
  UniV2 USDC->DAI rate: 0.995769149946949539
  UniV3 USDC->DAI rate: 0.999085577953564074
  Curve USDC->DAI rate: 0.999873092417166677
  Balancer USDC->DAI rate: 0.999928093460413902
  ...
  profitable triangles: 0
  ------- top candidates -------
    logProfit (1e18): -259056188314006   (USDC->DAI->USDT->USDC, -0.0259%)
    logProfit (1e18): -300517991962202   (USDC->USDT->DAI->USDC, -0.0300%)
    logProfit (1e18): -695980278301171   (USDC->USDT->WETH->USDC, -0.0695%)
    logProfit (1e18): -909042321636580   (USDC->WETH->DAI->USDC, -0.0909%)
    logProfit (1e18): -1602745858020427   (USDC->WETH->USDT->USDC, -0.1602%)
  total candidates: 6
```

> **Reading this output:** `profitable triangles: 0` is **the finding, not
> a failure.** At this block, MEV searchers had already compressed every
> cross-DEX stable triangle to *just below* swap friction. The -0.0259%
> top-candidate logProfit tells you exactly *how* arbed-flat the market
> was — a cluster around -0.03% is roughly the combined fee stack on the
> best routes, which means the opportunity was already gone before this
> block landed. **That is the insight.** A tool that reported
> "opportunity found" here would be lying; a tool that reports
> "arbed to the floor, near-miss was −0.0259%" is telling you the truth
> about how fast MEV moves.

More technical context: near-miss log-profits cluster at ~−0.03% because
that's the combined V2/V3/Curve/Balancer swap-fee stack. A positive
logProfit (say `+1e16` ≈ +1%) would be a real opportunity the MEV bots
missed — rare on high-liquidity pairs, more common around event-driven
dislocations (depegs, liquidations, bridge outages). See
[`docs/HISTORICAL_MOMENTS.md`][hm] for per-case narrative; edit the block
number in any case file to scan your own moment in history.

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

## Case studies

- [USDC depeg — Mar 11 2023](test/cases/Case_USDCDepeg_202303.t.sol)
- [Yen-carry unwind — Aug 5 2024](test/cases/Case_StableImbalance_202408.t.sol)
- [PEPE meme spike — May 27 2024](test/cases/Case_MemeSpike.t.sol)

Each test forks at a historical block, scans, detects, prints top 5
candidates, and asserts the pipeline enumerated at least one closed
cycle. Full narrative context in [`docs/HISTORICAL_MOMENTS.md`][hm].

## Algorithm

The detector works in log space: a triangle A→B→C→A is profitable iff
`ln(r_AB) + ln(r_BC) + ln(r_CA) > 0`. Rates live in 1e18 fixed-point;
`wadLn` from `solmate/SignedWadMath` gives signed 1e18 logs. See
[`docs/ALGORITHM.md`](docs/ALGORITHM.md) for a worked example and the
cases where greedy-per-hop diverges from the joint optimum.

## Limitations

- **Triangles only.** No 4-cycles or longer. Most real arb paths in 2024+
  are multi-hop by necessity; a triangle detector catches the simple
  bilateral/trilateral mispricings but misses the rest.
- **Greedy per-hop edge choice.** The detector picks the best-quoted
  venue for each hop independently. The globally-optimal choice would
  solve edge-selection jointly with trade size; this tool doesn't.
- **Fixed probe sizes.** Each case test picks a probe size per token.
  Larger probes expose slippage curves but shrink the searchable space.
- **No mempool.** This is a strictly on-chain-state tool. Pending-tx
  awareness is out of scope.
- **No private keys, ever.** Execution is simulated inside the fork via
  Balancer V2 flashloan; nothing leaves the test runner.

## Repo layout

```
src/
  ArbDetector.sol       triangle enumeration + log-space ranking
  ArbExecutor.sol       Balancer flashloan + multi-DEX dispatch (sim only)
  PriceGraph.sol        directed edges, mapping(pairKey => Edge[])
  MainnetForkHost.sol   fork harness base
  libraries/
    LogMath.sol         wadLn wrapper
    GasEstimator.sol    block.basefee → USD cost
  scanners/
    UniV2Scanner.sol    Factory.getPair + x*y=k
    UniV3Scanner.sol    QuoterV2, best fee tier across 500/3000/10000
    CurveScanner.sol    3pool get_dy
    BalancerScanner.sol Vault.queryBatchSwap (staBAL3)
  tokens/Tokens.sol     mainnet token registry + decimals helper
test/
  ArbDetector.t.sol     unit tests (no fork)
  ArbExecutor.t.sol     fork: flashloan + triangle end-to-end
  scanners/*.t.sol      fork: per-scanner quote sanity
  cases/*.t.sol         Phase 5 historical case studies
docs/
  HISTORICAL_MOMENTS.md narrative for each case
  ALGORITHM.md          log-space detector math
```

## License

MIT. See [LICENSE](LICENSE).

[hm]: docs/HISTORICAL_MOMENTS.md
