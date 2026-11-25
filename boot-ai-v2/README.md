# Boot AI V2 - Al Brooks Trading Ranges

This is a new working implementation alongside the files currently in the GitHub repository. The repository files and everything under `sources/` remain untouched.

## Scope

The source book is discretionary. This implementation translates its ideas into explicit, configurable screening heuristics; it cannot reproduce every judgment in the book mechanically. Numeric thresholds are engineering choices and must be calibrated. Chapter references are traceability labels, not claims of faithful or profitable reproduction.

The V2 expert advisor is designed to:

- Read closed bars on an entry timeframe and a higher trend timeframe.
- Build market context and evaluate candidate price-action setups.
- Keep a chapter-to-rule map and explain which evidence contributed to each signal.
- Calculate a proposed stop, target, size, and expected value before an order is considered.
- Default to analysis-only mode. Order execution is behind explicit inputs and demo-account checks.

## Files

- `TradingBot_V2.mq5`: the expert advisor implementation.
- `RULE_TRACEABILITY.md`: a chapter-by-chapter map from the book concepts to candidate code rules and their limits.
- `TEST_PLAN.md`: source audit, MetaTrader checks, and gates before demo.

## Development gates

1. Audit the chapter-to-rule mapping against the supplied source PDF.
2. Compile in MetaEditor and resolve all errors and warnings.
3. Check every detector with known chart examples and Strategy Tester visual runs.
4. Backtest with realistic spread, commission, slippage, and fill assumptions; keep out-of-sample data separate.
5. Enable execution only for demo forward testing after the earlier gates pass.

No profitability claim is made. This working copy has not been compiled or tested in MetaTrader. See `TEST_PLAN.md` for acceptance gates.

