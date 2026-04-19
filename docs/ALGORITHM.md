# Algorithm

How `arb-rewind` decides a triangle is profitable.

## The core trick: work in log space

Suppose you swap token A for B at rate `r_AB`, then B for C at rate `r_BC`,
then C back to A at rate `r_CA`. Starting with 1 A, you end with:

```
r_AB * r_BC * r_CA  units of A
```

A cycle is profitable iff that product is greater than 1. Checking the product
works fine in isolation, but a triangle detector that's scanning thousands of
(A, B, C) triples needs to *rank* them, not just classify. And ranking by a
product means you're sorting by a value that can underflow to near-zero for
bad cycles and overflow for good ones — numerically awkward.

The fix is to take `ln` of both sides:

```
ln(r_AB) + ln(r_BC) + ln(r_CA)  >  0
```

Now "profitable" is "sum positive", and "more profitable" is "sum larger". A
cycle that loses 2% shows up as `-0.0202`, a cycle that gains 2% as `+0.0198`,
and you can sort them on a single signed integer line. No overflow, no
underflow, just addition.

## Worked example

Real numbers from the USDC depeg event at block 16,818,000 (~12 hours
after the active panic the test case now samples — used here because it
is the cleanest pedagogical illustration of a *near-miss* triangle;
at block 16,804,000 the equivalent cycles clear friction, see
HISTORICAL_MOMENTS.md §1):

```
r_USDC→DAI   = 0.999873 (via Curve 3pool)
r_DAI→USDT   = 1.012306 (via Curve 3pool)
r_USDT→USDC  = 1.011693 (via UniV3 0.01% tier)
```

Quick sanity: the product is 1.012306 * 1.011693 * 0.999873 ≈ 1.024. That
*looks* profitable — 2.4% net. But two of those rates are round-trip quotes
of each other: if DAI→USDT is 1.012, then USDT→DAI must be roughly 0.988,
and you can't exit the stable at the same favorable rate you entered at
when the pools are nearly balanced. The detector does **not** pick the
"best of both directions" for free — it takes the actual A→B edge, the
actual B→C edge, and the actual C→A edge, each independently queried.

At this same block the *actual* closing edge r_USDC→USDT (not the inverse of
USDT→USDC shown above) is 0.988, and the cycle that closes properly is:

```
r_USDC→USDT = 0.988    →  ln = -0.01207
r_USDT→DAI  = 1.012    →  ln = +0.01193
r_DAI→USDC  = 0.99994  →  ln = -0.00006
                          ------
                          -0.00020  ← net loss of 2 bps
```

The detector outputs `logProfit = -0.00020 × 1e18 = -2×10¹⁴`. Because the
value is negative, `findTriangles` (which filters to strictly profitable)
returns 0 results. `findAllTriangles` (used by the case studies) returns all
6 cycles including this one, sorted with the least-negative at the top.

## Fixed-point mechanics

All rates live in 1e18 fixed-point (`uint256`, normalized from native
token decimals). The `ln` function is `solmate/SignedWadMath.wadLn`, which
operates on 1e18-scaled signed integers and returns 1e18-scaled results
in the range roughly [-43×1e18, +43×1e18] — plenty for any rate you'd
see on chain.

A few numeric conveniences fall out of this:

- `ln(1e18) == 0` exactly, so a parity-1 edge contributes nothing.
- `ln(1.01 × 1e18) ≈ 9.95×10¹⁵` — i.e. 1% excess shows up as ~1×10¹⁶.
- Adding three `wadLn` values cannot overflow a signed 256-bit integer
  under any realistic rate, because each term is bounded.

## Edge selection per hop

For each directed pair (tokenIn, tokenOut), the price graph may contain
multiple edges (one per DEX that quoted a non-zero amount). The detector
picks the edge with the highest `rate1e18` for that hop before composing
the product. This is the "greedy per-hop" heuristic — it is *not* globally
optimal in the presence of slippage curves, because a 1% better rate on
hop 1 might leave you with an awkward amount that quotes worse on hop 2.
A tighter model would solve the joint optimization of (edge choice × input
size). That belongs in v2.

## Why this is enough for a research tool

The detector's job is to produce a ranked list of candidates, not to
execute. The ranking built from greedy-per-hop log-products reproduces the
same *ordering* the joint model would most of the time, because across
close-to-parity pools the difference between optimal and greedy is small
compared to the logprofit spread between cycles. For the research purpose
of this repo — staring at historical snapshots and asking "what structure
would a searcher have seen here?" — greedy log-space is both sufficient
and transparent.
