# Chapter-to-rule traceability (working draft)

The work logs record a first-pass review of all 32 chapters. They explicitly say the notes still need a complete source audit. The rules below are proposed deterministic translations, not quotations or numeric rules asserted by Al Brooks. A detector can provide context or evidence without being a trade signal.

| Ch. | Source pages | Topic | Candidate rule represented in V2 | Limit / validation needed |
|---:|---|---|---|---|
| 1 | 53–60 | Example breakout trade | Identify range escape, signal bar, stop distance, and measured-move candidate | Entry quality and stop placement depend on context |
| 2 | 61–79 | Breakout strength | Body share, close location, and follow-through evidence | Correlated clues must not be counted as independent reasons |
| 3 | 81–89 | Initial breakout | Confirm a close beyond the reference range and assess follow-through | A single bar is not proof of continuation |
| 4 | 91–97 | Breakouts in trends | Compare breakout direction with higher-timeframe trend | Late breakouts can be poor entries |
| 5 | 99–117 | Failed breakouts and tests | Detect a close back inside after an attempted break; mark retests | Require a separate confirmation before reversal entry |
| 6 | 119–151 | Gaps | Detect a true price gap between adjacent bars | Session gaps differ from ordinary FX noise |
| 7 | 153–163 | Spike measured move | Project a second leg using the first leg's size | Projection is a target candidate, not a forecast |
| 8 | 165–173 | Gap/range measured moves | Derive candidate targets from a gap or range height | Choose only after validating the anchor points |
| 9 | 175–177 | Prior failed reversals | Track recent swing levels as coarse magnets and flag failed breakouts separately | Failed reversal levels are not yet persisted as a dedicated level set |
| 10 | 179–181 | Other magnets | Track prior-day levels, range edges, and moving average | Broker session boundaries affect daily levels |
| 11 | 205–212 | First pullback sequence | Track countertrend bars, overlap, and weakening follow-through | The sequence is contextual, not mandatory |
| 12 | 213–231 | Double-top/bottom flags | Detect approximate paired swing tests and restrict against the higher-timeframe trend | The code does not yet reliably distinguish continuation flags from reversals |
| 13 | 233–237 | Twenty-gap bars | Count closes extended from the moving average | The chapter's count is contextual, not a fixed trigger |
| 14 | 239–243 | First MA-gap bars | Detect a bar fully separated from the moving average | Must distinguish trend from a range |
| 15 | 245–251 | Key times of day | Optional server-time session filter | Session times must be configured for broker/server time |
| 16 | 253–257 | Leg counting | Count approximate swing legs and pullbacks | Bar counting is subjective; test against labeled examples |
| 17 | 259–299 | High/Low 1-4 and ABC | Estimate attempts from alternating candle directions; log a separate rough pivot count | This is not Brooks bar counting or ABC identification; validate or replace with labeled examples |
| 18 | 301–311 | Wedges / three pushes | Detect three progressively weaker pushes | Pivot definition and trend context need manual review |
| 19 | 313–317 | Dueling lines | Use moving-average proximity plus swing/day/range magnets as a coarse confluence proxy | The code does not fit or compare two actual trend lines |
| 20 | 319–325 | Reversal patterns | Detect approximate double-top/bottom and head-and-shoulders shapes | Shape detection is approximate; pattern alone must not trigger an order |
| 21 | 367–375 | Trading ranges | Prefer evidence near range edges; penalize the middle | Range boundaries are heuristic |
| 22 | 377–410 | Tight ranges | Measure overlap, narrowness, and wick/body balance | Can be a pause or a continuation flag |
| 23 | 411–415 | Triangles | Detect contracting swing highs/lows and breakout mode | Direction is unknown before a breakout and follow-through |
| 24 | 419–515* | Trading style | Lock scalp/swing/day-trade holding profile before entry | V2 must not silently change the profile after entry |
| 25 | 419–515* | Trading math | Calculate size from stop distance and estimate net expectancy | Probability is a configurable assumption until calibrated |
| 26 | 419–515* | Two reasons | Require two evidence groups, not two correlated indicators | Independent evidence groups need review |
| 27 | 419–515* | Stop entries | Place a pending stop beyond the signal bar when enabled | Fill, spread, and slippage need tester validation |
| 28 | 419–515* | Limit entries | Optional range-edge limit orders, disabled by default | Countertrend limits need a separate test set |
| 29 | 517–569* | Protective/trailing stops | Initial signal-bar stop and swing-based trailing candidate | Stop changes must never increase planned risk |
| 30 | 517–569* | Profit targets | Fixed-R / measured-move candidate, attached SL/TP, partial exit, cancel remaining pendings on fill | OCO and partial-fill behavior need broker testing |
| 31 | 517–569* | Scaling | Support scaling out; do not average into losing positions | Scaling in remains disabled pending dedicated testing |
| 32 | 517–569* | Trapped traders | Use failed setups as context for an opposite-side candidate | Never infer manipulation from price alone |

\* The work logs provide combined page ranges for Chapters 24–28 and 29–32 rather than a separate page span for each chapter.

## Current coverage status

The V1 repository code covers only a small subset: a basic higher-timeframe high/low comparison and heuristic M15 range / failed-breakout / High 2 / Low 2 screening. It does not implement the complete chapter map, trade sizing, entries, exits, or risk management. V2 is a new working draft; no detector is validated until it has been checked against chart examples and tested in MetaTrader.

