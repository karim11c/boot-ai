# MT5 validation plan (not yet executed)

The EA must stay in analysis-only mode while this plan is pending. `EnableTradeExecution` defaults to `false`; if it is enabled later, the current draft blocks non-demo accounts.

## 1. Source and rule audit

- Compare the chapter map and each proposed heuristic with the supplied Trading Ranges source, including chart examples and exceptions.
- Label each statement as author-supported concept, engineering approximation, or parameter chosen for testing.
- For each rule, save at least one positive and one negative chart example with symbol, timeframe, date, and expected result.
- Do not enable a setup for order placement while its context, invalidation, entry, stop, and exit are ambiguous.

## 2. Build and data checks

- Compile `TradingBot_V2.mq5` in MetaEditor with zero errors; review every warning.
- Confirm `CopyRates(..., 1, ...)` excludes the forming bar and that `rates[0]` is the most recent closed bar after `ArraySetAsSeries(true)`.
- Confirm short-history and unavailable-history cases do not create signals or orders.
- Confirm signal evaluation occurs once per new entry-timeframe bar and higher-timeframe updates use only closed bars.

## 3. Signal checks in visual Strategy Tester

- Range edges, range middle, tight range, triangle breakout, and breakout follow-through.
- Strong and weak breakouts; failed breakouts in both directions; retests and gaps.
- High 1–4 / Low 1–4 proxies, double tops/bottoms, head-and-shoulders proxies, wedges, and pullback weakening.
- Moving-average gap and twenty-gap counters, session filter boundaries, and daily-level magnets.
- Verify each printed setup against the manually labeled chart examples. No false positive should be silently treated as a confirmed trade.

## 4. Order and risk checks on demo only

- Confirm risk sizing with `OrderCalcProfit`, volume step/minimum, symbol tick size, and stop distance. If the minimum lot would exceed the risk budget, the EA must skip the order.
- Confirm pending stop/limit price, expiration, attached stop and target, retcode handling, and cancellation after a fill or partial fill.
- Test both hedging and netting account modes; confirm partial close reduces the intended position and never reverses it.
- Confirm trailing/breakeven changes only tighten risk; rejected modify/close/delete operations remain visible in the log and are retried where appropriate.
- Confirm one position/pending order per symbol and magic number; confirm unrelated netting exposure blocks a new order.
- Confirm `EnableTradeExecution=false` creates no order under any signal and non-demo accounts are rejected when execution is enabled.

## 5. Historical and forward evaluation

- Use realistic spread, commission, slippage, and pending-order fill assumptions.
- Keep a chronological out-of-sample segment untouched during rule/parameter development.
- Report trade count, expectancy after costs, profit factor, maximum drawdown, average R, missed fills, and parameter sensitivity; do not use win rate alone.
- Run demo forward testing only after the source audit, successful build, visual signal checks, and historical evaluation are complete.
- Agree on acceptable drawdown and minimum evidence thresholds before treating the demo phase as a pass.

No compile, Strategy Tester, or demo run has been performed for this draft.

