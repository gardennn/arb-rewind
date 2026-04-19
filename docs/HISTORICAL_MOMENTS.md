# Historical Moments

Three case studies the repo re-runs on every `forge test`. Each forks mainnet at
a chosen block, scans four DEX families, and asks the detector to enumerate
every closed triangle A→B→C→A for a given base token. The output is what the
tool *would have seen* standing in that block — not what anyone actually traded.

---

## 1. USDC depeg — March 11, 2023

On the morning of March 10, Silicon Valley Bank was placed into FDIC
receivership. Circle disclosed that ~$3.3B of USDC reserves were held there.
By Saturday the 11th, USDC was trading as low as $0.87 on CEXes; on-chain stable
pools briefly lost a full percent of peg-symmetry before the reserve was made
whole Monday morning and the price snapped back.

The case runs at **block 16,804,000** — inside the *active panic window*,
a few hours into the SVB dislocation. At this block USDC→USDT trades at
~0.90 across four DEXes (vs. the ~1.00 norm) and the cross-DEX rate fan is
wide enough that triangle products exceed the friction floor. The detector
enumerates all 6 closed triangles USDC→{USDT,DAI,WETH}→…→USDC and finds
**4 profitable** ones, topped by `USDC→WETH→DAI→USDC` at +0.1556%
log-profit (≈ +15 USDC on a 10k USDC probe, pre-gas). The next three are
+0.130% / +0.089% / +0.050%. This is the uncompressed state — MEV bots
had not yet finished pulling the cross-DEX stable triangle below the fee
stack.

For contrast, re-running the same pipeline at block **16,818,000** (~12
hours later, mid-recovery) flips the picture entirely: zero profitable
triangles, near-misses clustered at −0.025% to −0.03% log-profit. Same
event, same tokens, same pipeline; the only variable is time. That
≈12-hour window is the fingerprint of MEV searchers compressing the arb
below the combined fee stack (Curve ~4bps + UniV3 5bps + 3pool bonding
curve). The reader's takeaway: opportunity structurally exists during
dislocations and costs nothing to observe in hindsight, but the window
is measured in blocks — you need to be pre-positioned or faster than
searchers to capture it live.

## 2. Yen-carry-trade unwind — August 5, 2024

The Bank of Japan's surprise rate hike on July 31, 2024 triggered a violent
unwind of yen-funded risk trades. On August 5 ETH fell ~22% in under 36 hours
as liquidations cascaded through both TradFi and on-chain lending. Stable
liquidity briefly went one-sided as funds rotated into USDC/USDT for
collateralization.

The case runs at **block 20,480,000** — midnight UTC at the opening of the
cascade. The 100K-probe quotes are notably asymmetric: UniV2 USDC→USDT reports
0.957 (a 4.3% hit for the probe size, evidence of thin same-block depth on
V2 pairs), while Curve remains tight at 0.9997. The detector still finds 0
profitable triangles, but the log-profit distribution is wider than at 16.8M:
best cycle is ~-0.03% loss, worst is ~-1% — dramatically larger than the
depeg snapshot. This is the tool showing that *liquidity fragmentation* was
the dominant regime here, not price dislocation: the raw cross-DEX rates
mostly still agree, but venue-specific slippage at scale is severe.

## 3. PEPE meme spike — May 27, 2024

On May 26–27, 2024, PEPE printed a fresh all-time-high above $1.7×10⁻⁵ on
retail speculative flow. Meme tokens carry asymmetric liquidity — UniV3's
concentrated ticks handle size well, while UniV2 pools have ~0 depth outside
the current price.

The case runs at **block 19,980,000**, inside the impulse. Only UniV2 and
UniV3 carry PEPE; Curve and Balancer return nothing and are quietly dropped.
The pair rates expose the V2/V3 dichotomy vividly: V2 `PEPE→USDC` returns
5.8×10⁻¹¹ (a nonsense number indicating the V2 pool has been drained out of
the live tick range), while V3 reports 1.49×10⁻⁵ — a difference of five
orders of magnitude on the same notional probe. The detector enumerates 6
cycles and again finds 0 profitable after friction, but the near-miss
geometry is revealing: the best cycle is WETH→USDC→USDT→WETH at ~-0.1%,
while any PEPE-involved cycle is ~1% worse. This is the tool saying: during
meme spikes, the arb lives *inside* a single DEX's price curve, not across
DEX families — and that is outside this triangle detector's scope.

---

## What these cases collectively demonstrate

- The pipeline (scan → normalize → log-space detect) runs cleanly at any
  historical block, and the detector produces a numerically coherent ranking
  whether or not it finds profit.
- Profitable cross-DEX triangles *do* exist during active dislocations — the
  USDC depeg case at block 16,804,000 shows four, topped by +0.156%. What
  MEV closes is the *time window*, not the opportunity itself. 12 hours
  later at the same tokens the cycles are already arbed below friction.
- The useful output of this tool is the *shape of the log-profit
  distribution* as much as the top line. A tightening cluster at −friction
  (like 16,818,000 or 20,480,000) is evidence the block has already been
  arbed. A fan of positive cycles (like 16,804,000) is evidence that you
  caught the market mid-dislocation, before searchers finished their work.
  A wide, non-uniform distribution (like 20,480,000) is evidence of
  structural liquidity fragmentation that a larger capital base could still
  exploit.
