# MT5 validation plan

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
- Strong and weak breakouts; failed breakouts in both directions; breakout pullbacks/tests in both directions, including deep but valid tests, decisive closes through the level, stale breakouts, and failed retests; and gaps.
- Chapter 9 failed-reversal magnets: verify trigger then later stop breach, direction-specific signal-bar level, every qualifying level retained, same-bar ambiguity ignored, and only closed bars considered.
- Chapter 19 dueling lines: verify pivot selection, rising-low and falling-high slopes, projection to the current closed bar, and confluence only when both lines and price are within the fixed half-ATR distance.
- Chapter 15 session filter: verify exact start/end boundaries, overnight windows, disabled mode, and that backtests use each closed bar timestamp rather than current workstation time.
- High 1–4 / Low 1–4 and ABC H2/L2 proxies (including no intermediate countertrend leg, trading-range context, and reset cases), double tops/bottoms, head-and-shoulders proxies, wedges, and pullback weakening.
- Tight-range gate: no candidate by default except a failed strong breakout that exceeded the range by at least three ticks or a small directional reversal bar at a range edge; verify the explicit research override separately.
- Chapter 26 steep-trend gate: verify trend-strength classification, line breaks use only closed bars and pre-existing pivots, countertrend candidates are skipped without a qualifying line break or wedge/failure reversal proxy, and qualifying cases still meet the two-reason gate.
- Moving-average gap and twenty-gap counters, session filter boundaries, and daily-level magnets.
- Verify each printed setup against the manually labeled chart examples. No false positive should be silently treated as a confirmed trade.

## 4. Order and risk checks on demo only

- Confirm risk sizing with `OrderCalcProfit`, volume step/minimum, symbol tick size, and stop distance. If the minimum lot would exceed the risk budget, the EA must skip the order.
- Chapter 25 EV gate: verify the configured probability and spread/slippage/commission assumptions, verify candidates at or below `MinimumExpectedValuePoints` are rejected and logged, and confirm positive EV is not treated as evidence of profitability without out-of-sample calibration.
- Confirm pending stop/limit price, expiration, attached stop and target, retcode handling, and cancellation after a fill or partial fill.
- Confirm enabled range-edge limit entries use `LimitEntryRiskMultiplier` for position sizing and that the default 0.50 value halves the stop-based risk amount without changing the stop distance; confirm the limit-entry switch remains off by default.
- Confirm an unfilled managed stop/limit entry is deleted after bid reaches a buy order's attached stop or ask reaches a sell order's attached stop; verify delete rejection is logged and retried on later ticks. Confirm switching `EnableTradeExecution` off deletes all managed pending entries without touching unrelated orders.
- Test both hedging and netting account modes; confirm partial close reduces the intended position and never reverses it.
- For Chapters 30–31 staged exits, verify they activate only for an aligned strong-trend setup; defaults follow the source example: 50% of initial volume near 2R, 25% near 3R, then trail the final quarter. Verify staged mode keeps the protective SL but sends no fixed TP, while range/unclear-trend contexts retain the fixed candidate target. Check intrabar threshold crossings, price gaps beyond both thresholds, cooldown retries, and minimum-volume cases; compare against `EnablePartialExit=false`.
- For Chapter 30 opposite-signal exits, verify only a fully qualified opposite-direction setup closes the managed position, the close is attempted on the closed-bar decision, a rejection is retried after cooldown, and the EA does not reverse into a new trade on that same bar.
- Confirm trailing/breakeven changes only tighten risk; rejected modify/close/delete operations remain visible in the log and are retried where appropriate.
- For swing trailing, confirm only a pivot with both older and newer closed-bar confirmation is used, the configured lookback is respected, no forming bar is read, and the stop never loosens or crosses the current market.
- For Chapter 29 entry-bar stop management, verify the first closed bar after fill is the one evaluated; a strong directional bar can tighten to the configured 1–2 tick offset, while a Doji, weak/opposite bar, non-improving candidate, or broker-invalid distance keeps the original stop. Confirm modification rejection retries only after the cooldown and never loosens the stop.
- Confirm each trade style uses its configured max-bar exit and that changing `TradeStyle` or its max-bar inputs after a pending entry is placed (and after it fills) does not alter the locked horizon.
- Confirm one position/pending order per symbol and magic number; confirm unrelated netting exposure blocks a new order.
- Confirm `EnableTradeExecution=false` creates no order under any signal and non-demo accounts are rejected when execution is enabled.

## 5. Historical and forward evaluation

- Use realistic spread, commission, slippage, and pending-order fill assumptions.
- Keep a chronological out-of-sample segment untouched during rule/parameter development.
- Report trade count, expectancy after costs, profit factor, maximum drawdown, average R, missed fills, and parameter sensitivity; do not use win rate alone.
- Run demo forward testing only after the source audit, successful build, visual signal checks, and historical evaluation are complete.
- Agree on acceptable drawdown and minimum evidence thresholds before treating the demo phase as a pass.

## Current recorded run

- MetaEditor compiled V2 with 0 errors and 0 warnings.
- A user-provided Strategy Tester Journal screenshot shows a one-year EURUSDm M15 run ending with a final balance of $5,125.09 from a $10,000 deposit (about -48.75%).
- The local MetaTester journal confirms the test passed in 25.413 seconds with 11,313,866 ticks and 22,375 bars, then shut down normally. The “Not Responding” label in the screenshot was transient/stale UI state, not evidence that the test was still running.
- The tester's Backtest tab shows 2,170 trades, 873 winners (40.23%), profit factor 0.71, expected payoff -$2.25 per trade, and maximal balance drawdown $5,023.92 (50.08%). Gross profit was $12,228.45 against gross loss $17,103.36. The settings used zero latency/ideal execution and $0 commission, so this is optimistic about costs despite the loss.
- This run predates the latest Chapter 9, 15, 17, and 19 changes. Treat it as a failed baseline for the earlier heuristic draft; do not use it to claim anything about a complete or validated Al Brooks strategy.
- A second one-year run of the separate research build (with the Chapter 3/5 retest detector and Chapter 9/15/17/19 updates) ended at $4,623.96, net -$5,376.04, with 2,139 trades, 38.94% winners, profit factor 0.67, expected payoff -$2.51, and maximal balance drawdown $5,498.50 (54.98%). It completed in 38 seconds over the same 11,313,866 ticks and 22,375 bars. This result is worse than the original baseline. Both runs used zero latency and no commission. The second run is now the baseline for the next tight-range gate comparison.
- A third build adds `AllowTightRangeSignals=false` by default and a strong-breakout/follow-through exception. MetaEditor compiled it with 0 errors and 0 warnings, and its separate EX5 copy is staged in the MT5 Experts folder. It has not been tested yet.
- The latest build includes Chapters 25/26/28–32 research changes: Chapter 29 tightens the stop beyond a strong directional entry bar only after it closes (weak/Doji bars retain the original); Chapter 30 optionally scales out 50% near 2R and 25% near 3R only in an aligned strong trend, trails the final quarter, and closes on a qualified opposite-direction setup; other contexts retain a fixed target. Opposite-signal close requests and partial exits retry after cooldowns. Scale-in remains rejected. MetaEditor compiled this version with 0 errors and 0 warnings (89,650-byte EX5); it is staged as `BootAI_V2_Research_Ch31_20261126.ex5`, matching hash `949C4B7EEB73900D0E00F20C6C73FEC2220B1B79C1C7DDFC1191C9E10937A507`. Matching tester `.ini` and `.set` presets contain all 43 EA inputs and enable execution only inside Strategy Tester. No historical result exists for this newest build; the latest MetaTester log remains the earlier run ending at $4,623.96. The source EA default remains `EnableTradeExecution=false`, and the base `TradingBot_V2.ex5` was not overwritten. A command-line run attempt did not start because the existing terminal instance ignored the new startup configuration; the agent log timestamp did not change. Do not claim the new build was tested.
- The user changed `EnableTradeExecution` to true in Strategy Tester inputs for that simulation. The EA source default remains false; live-chart execution must remain off.
