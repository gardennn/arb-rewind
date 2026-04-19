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

# 2. Install submodules (foundry wrapper)
forge install
# Fallback if forge install stalls on a submodule SHA or network hiccup:
#   git submodule update --init --recursive

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
vm.createSelectFork("mainnet", 16_804_000);   // ← change this
```

Then `forge test --match-contract CaseUSDCDepeg202303Test -vv` to see what
the tool would have found at your chosen block.

### What to look for in the output

Each case test prints, in order:

1. **Every scanner edge** it found (`UniV2 USDC->USDT rate: 0.9967...`).
   Useful for spotting which DEX was offering the best rate on which leg.
2. **Count of profitable triangles** (`profitable triangles: N`). Both
   outcomes are informative:
   - `profitable triangles: 0` means MEV searchers had already compressed
     every cycle below the fee floor by the time this block closed —
     normal at most blocks. The shape of the near-miss distribution is
     the signal, not a failure.
   - `profitable triangles: N > 0` means you caught the block mid-
     dislocation, before searchers closed the window. The repo's
     `Case_USDCDepeg_202303` test pins a block where `N=4` and locks
     that in with `assertGt(profitable.length, 0)`.
3. **Top 5 candidates by log-profit**, including negative ones. A cluster
   near `-3e14` ≈ −0.03% = arbed-to-the-floor (fee-stack residual); a
   cycle near `+1e15` ≈ +0.1% = a real, MEV-available arb.

## Example output

The repo ships with two contrasting cases that tell the same story from
opposite sides: what a real arb opportunity looks like, and what an
already-arbed market looks like.

### Case 1 — opportunity found (USDC depeg, active panic)

From `test/cases/Case_USDCDepeg_202303.t.sol` at block **16,804,000**
(Mar 11 2023, a few hours after SVB froze Circle's USDC reserve — the
active dislocation window, *before* MEV searchers had fully compressed
the cross-DEX stable triangle spread):

```
  UniV2 USDC->USDT rate: 0.902158493700000000
  UniV3 USDC->USDT rate: 0.903699397700000000
  Curve USDC->USDT rate: 0.905973036800000000
  Balancer USDC->USDT rate: 0.890668293400000000
  UniV2 USDC->DAI rate: 0.974088341049807260
  UniV3 USDC->DAI rate: 0.977605082165469346
  ...
  profitable triangles: 4
  ------- top candidates -------
    logProfit (1e18):  1556908663373049   (USDC->WETH->DAI->USDC,  0.1556%)
    logProfit (1e18):  1297802508273535   (USDC->DAI->USDT->USDC,  0.1297%)
    logProfit (1e18):   888461768292190   (USDC->WETH->USDT->USDC, 0.0888%)
    logProfit (1e18):   503736545450560   (USDC->USDT->WETH->USDC, 0.0503%)
    logProfit (1e18):   -44037597245172   (USDC->USDT->DAI->USDC, -0.0044%)
  total candidates: 6
```

> **Reading this output:** `profitable triangles: 4` with a top cycle at
> **+0.1556%** is a **real, MEV-available opportunity** sitting on-chain
> at that block. The detector says: if you'd sent 10,000 USDC through
> `USDC → WETH → DAI → USDC`, picking the best-quoted venue per hop,
> you'd have finished ~+15 USDC up before gas. The next three cycles are
> also positive. This is what the tool is looking for — and it's exactly
> the kind of moment that lives *inside* historical state and can no
> longer be exploited in the present.

### Case 2 — arbed to the floor (yen-carry unwind cascade)

From `test/cases/Case_StableImbalance_202408.t.sol` at block **20,480,000**
(Aug 5 2024, mid-cascade during the yen-carry unwind):

```
  UniV2 USDC->USDT rate: 0.957205888800000000
  UniV3 USDC->USDT rate: 0.999091316980000000
  Curve USDC->USDT rate: 0.999696128800000000
  Balancer USDC->USDT rate: 0.273612404730000000
  UniV2 USDC->DAI rate: 0.879530348657468619
  UniV3 USDC->DAI rate: 0.999167415154245756
  ...
  profitable triangles: 0
  ------- top candidates -------
    logProfit (1e18):  -302980763817415   (USDC->DAI->USDT->USDC, -0.0302%)
    logProfit (1e18):  -302980778450745   (USDC->USDT->DAI->USDC, -0.0302%)
    logProfit (1e18): -3073904190314660   (USDC->WETH->USDT->USDC, -0.3073%)
    logProfit (1e18): -7817588414174412   (USDC->USDT->WETH->USDC, -0.7817%)
    logProfit (1e18): -9779889011595358   (USDC->DAI->WETH->USDC, -0.9779%)
  total candidates: 6
```

> **Reading this output:** `profitable triangles: 0` is **the finding, not
> a failure.** At this block, MEV searchers had already compressed every
> cross-DEX stable triangle to *just below* swap friction. The -0.0302%
> top-candidate logProfit tells you exactly *how* arbed-flat the market
> was — a cluster around -0.03% is roughly the combined fee stack on the
> best routes, which means the opportunity was already gone before this
> block landed. A tool that reported "opportunity found" here would be
> lying; a tool that reports "arbed to the floor, near-miss was −0.0302%"
> is telling you the truth about how fast MEV moves.
>
> **About the outlier rates (0.273 Balancer, 0.880 UniV2).** The
> `Balancer USDC->USDT: 0.273` and `UniV2 USDC->DAI: 0.880` lines are
> *not* the real market — they are thin-liquidity artifacts from a
> staBAL3 pool and a shallow V2 pair at a 100k-USDC probe size, where
> the quote collapses into the depth curve. The detector's greedy
> best-edge selection (`_bestEdge` picks the highest-quoted venue per
> hop) correctly ignores them and routes each leg through Curve / UniV3,
> whose rates sit at the expected ~0.999 level. This is worth calling
> out: the scanner layer deliberately reports noisy pools as-is, and the
> detector layer is robust to that noise. The tool degrades gracefully
> when a venue is broken at your chosen probe size; it does not silently
> corrupt the ranking.

Same pipeline, same tokens, two market regimes. Edit the block number in
any case file and re-run to scan your own moment in history; see
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

## End-to-end execution (optional)

Beyond scanning and detection, the repo includes an on-fork execution
path: [`test/ArbExecutor.t.sol`](test/ArbExecutor.t.sol). The executor
forks at block 16,810,500 (USDC depeg window), takes a 1,000 USDT
Balancer V2 flashloan, dispatches a 3-hop triangle
`USDT → USDC → WETH → USDT` across Curve → UniV3 → UniV3, and repays in
the same transaction — all inside the forked environment, no keys, no
network egress.

**What it validates (structural, not profit):**
- Flashloan + multi-DEX dispatch + repay round-trips without reverting.
- Profit accounting is internally consistent
  (`amountEnd - amountStart == profit`).
- Slippage stays within 1% of the flashloan (else the dispatch is buggy).

It deliberately does **not** assert that an arbitrary path is profitable
at that block — by 16,810,500 most cross-DEX skew had already been
compressed (the USDC-depeg *case study* at 16,804,000 is what checks
whether profitable cycles exist in the first place; this test checks
whether a cycle the detector hands you can actually settle).

```bash
source .env && forge test --match-contract ArbExecutorTest -vv
```

Together the two layers cover the full question: *did an opportunity
exist at block X* (case studies), and *would it have settled cleanly
through a flashloan* (this test).

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
- **Research surface, not a production searcher.** The greedy
  per-venue quoting described above — one probe size, best-rate-per-hop,
  no joint optimization — is adequate for *answering* the historical
  question "did an opportunity exist here?" A live searcher would solve
  edge selection jointly with trade size (slippage-aware routing),
  include tick-level UniV3 math, model pool inventory across the
  mempool, and compete on MEV-bundle ordering. None of that is wired
  here. This repo surfaces market structure; it does not capture it.

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
  ArbDetector.t.sol     unit tests with mock PriceGraph (no fork)
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
