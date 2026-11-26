# Boot AI V2 - Al Brooks Trading Ranges

This is a new working implementation alongside the files currently in the GitHub repository. The repository files and everything under `sources/` remain untouched.

## Scope

The source book is discretionary. This implementation translates its ideas into explicit, configurable screening heuristics; it cannot reproduce every judgment in the book mechanically. Numeric thresholds are engineering choices and must be calibrated. Chapter references are traceability labels, not claims of faithful or profitable reproduction.

The V2 expert advisor is designed to:

- Read closed bars on an entry timeframe and a higher trend timeframe.
- Build market context and evaluate candidate price-action setups.
- Keep a chapter-to-rule map and explain which evidence contributed to each signal.
- Calculate a proposed stop, target, size, and expected value before an order is considered.
- Optionally scale out in two risk-based stages while leaving a runner; scale-in remains blocked.
- Default to analysis-only mode. Order execution is behind explicit inputs and demo-account checks.
- Cancel an unfilled managed pending entry if its attached invalidation level is reached, and cancel managed pending entries when execution is turned off.

## Files

- `TradingBot_V2.mq5`: the expert advisor implementation.
- `RULE_TRACEABILITY.md`: a chapter-by-chapter map from the book concepts to candidate code rules and their limits.
- `TEST_PLAN.md`: source audit, MetaTrader checks, and gates before demo.
- `Research_Ch31_20261126.set`: Strategy Tester input preset for the staged Chapter 31 research build. This preset enables execution only in the tester; do not load it onto a live chart.

## Development gates

1. Audit the chapter-to-rule mapping against the supplied source PDF.
2. Compile in MetaEditor and resolve all errors and warnings.
3. Check every detector with known chart examples and Strategy Tester visual runs.
4. Backtest with realistic spread, commission, slippage, and fill assumptions; keep out-of-sample data separate.
5. Enable execution only for demo forward testing after the earlier gates pass.

No profitability claim is made. V2 is a research draft and does not fully implement or validate all 32 chapters. The current source compiled with 0 errors and 0 warnings and was copied as `BootAI_V2_Research_Ch31_20261126.ex5`, but this build has not yet had a historical test. Earlier one-year tests lost roughly 49% and 54% under idealized tester settings. See `CHAPTER_COVERAGE_AUDIT.md` and `TEST_PLAN.md` before making any execution decision.
