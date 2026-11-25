#property strict
#property version   "2.000"
#property description "Boot AI V2 - research implementation of Al Brooks Trading Ranges concepts"

#include <Trade/Trade.mqh>

// All numeric thresholds are engineering heuristics, not rules stated by the author.
// Execution is disabled by default. Keep it disabled until the rule map and tests pass.
input ENUM_TIMEFRAMES EntryTF = PERIOD_M15;
input ENUM_TIMEFRAMES TrendTF = PERIOD_H1;
input int BarsToRead = 100;
input int RangeLookback = 20;
input int TrendBarsPerLeg = 5;
input int MovingAveragePeriod = 20;
input double RangeOverlapThreshold = 0.55;
input double StrongBodyShare = 0.55;
input double RangeEdgePercent = 25.0;
input int MinReasonGroups = 2;

enum ENUM_BOOTAI_STYLE
{
   STYLE_SCALP = 0,
   STYLE_INTRADAY_SWING = 1,
   STYLE_SWING = 2
};

input ENUM_BOOTAI_STYLE TradeStyle = STYLE_INTRADAY_SWING;
input double EstimatedWinProbability = 0.50;
input double RiskPercent = 0.25;
input double TargetRR = 2.0;
input double CommissionPerLotRoundTurn = 0.0;
input int SlippagePointsEstimate = 2;
input bool UseSessionFilter = false;
input int SessionStartHour = 7;
input int SessionEndHour = 18;

input bool EnableTradeExecution = false;
input bool EnableLimitEntries = false;
input bool EnablePartialExit = true;
input bool MoveStopToBreakevenAtOneR = false;
input bool EnableSwingTrailingStop = false;
input bool EnableScaleIn = false; // Intentionally rejected in V2 until separately tested.
input ulong MagicNumber = 320032;

CTrade trade;
datetime g_lastEntryBar = 0;
datetime g_lastManageBar = 0;
string g_lastSignalKey = "";

struct SContext
{
   int trend;
   bool range;
   bool tightRange;
   bool triangle;
   bool bullMA;
   bool bearMA;
   bool firstMAGapUp;
   bool firstMAGapDown;
   bool twentyGapUp;
   bool twentyGapDown;
   bool pullbackWeakening;
   bool doubleTop;
   bool doubleBottom;
   bool headShouldersTop;
   bool headShouldersBottom;
   bool wedgeUp;
   bool wedgeDown;
   bool breakoutUp;
   bool breakoutDown;
   bool strongBreakoutUp;
   bool strongBreakoutDown;
   bool followThroughUp;
   bool followThroughDown;
   bool failedBreakoutUp;
   bool failedBreakoutDown;
   bool gapUp;
   bool gapDown;
   bool high2;
   bool low2;
   bool magnetAbove;
   bool magnetBelow;
   bool priorFailureMagnet;
   bool duelingLines;
   bool sessionOK;
   bool nearRangeLow;
   bool nearRangeHigh;
   int legCount;
   int attemptCount;
   int highLowCount;
   double ma;
   double atrLike;
   double rangeHigh;
   double rangeLow;
   double measuredMoveUp;
   double measuredMoveDown;
   double nearestMagnetAbove;
   double nearestMagnetBelow;
};

struct SSetup
{
   int direction;
   int reasonGroups;
   bool isRangeSetup;
   bool useLimit;
   double entry;
   double stop;
   double target;
   double expectedValue;
   string label;
};

// -----------------------------------------------------------------------------
// Chapter map in code:
// 1-5 breakout / strength / follow-through / failures; 6 gaps; 7-10 measured
// moves and magnets; 11-20 pullbacks, flags, MA gaps, legs, H/L counts, wedges,
// confluence and reversals; 21-23 ranges, tight ranges and triangles; 24-28
// style, expectancy, evidence groups, stop/limit entry; 29-32 stops, exits,
// scaling out and trapped-trader context. See RULE_TRACEABILITY.md for limits.
// -----------------------------------------------------------------------------

int MinInt(const int a, const int b) { return (a < b ? a : b); }
int MaxInt(const int a, const int b) { return (a > b ? a : b); }
double MaxDouble(const double a, const double b) { return (a > b ? a : b); }
double MinDouble(const double a, const double b) { return (a < b ? a : b); }

double TickSize()
{
   double value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(value <= 0.0) value = _Point;
   return value;
}

double NormalizePrice(const double price)
{
   double tick = TickSize();
   if(tick <= 0.0) return NormalizeDouble(price, _Digits);
   return NormalizeDouble(MathRound(price / tick) * tick, _Digits);
}

double BarRange(const MqlRates &bar)
{
   return MaxDouble(bar.high - bar.low, TickSize());
}

double BodyShare(const MqlRates &bar)
{
   return MathAbs(bar.close - bar.open) / BarRange(bar);
}

int BarDirection(const MqlRates &bar)
{
   if(bar.close > bar.open) return 1;
   if(bar.close < bar.open) return -1;
   return 0;
}

bool ReadClosedRates(const ENUM_TIMEFRAMES timeframe, const int minimumBars, MqlRates &rates[])
{
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, timeframe, 1, BarsToRead, rates);
   return (copied >= minimumBars);
}

double AverageRange(const MqlRates &rates[], const int start, const int count)
{
   int size = ArraySize(rates);
   if(size <= start || count <= 0) return 0.0;
   int end = MinInt(size, start + count);
   double sum = 0.0;
   for(int i = start; i < end; i++) sum += rates[i].high - rates[i].low;
   return (end > start ? sum / (end - start) : 0.0);
}

double AverageClose(const MqlRates &rates[], const int start, const int count)
{
   int size = ArraySize(rates);
   if(size <= start || count <= 0) return 0.0;
   int end = MinInt(size, start + count);
   double sum = 0.0;
   for(int i = start; i < end; i++) sum += rates[i].close;
   return (end > start ? sum / (end - start) : 0.0);
}

int DetectTrend(const MqlRates &rates[])
{
   if(ArraySize(rates) < 2 * TrendBarsPerLeg) return 0;
   double recentHigh = rates[0].high, recentLow = rates[0].low;
   double oldHigh = rates[TrendBarsPerLeg].high;
   double oldLow = rates[TrendBarsPerLeg].low;
   for(int i = 1; i < TrendBarsPerLeg; i++)
   {
      recentHigh = MaxDouble(recentHigh, rates[i].high);
      recentLow = MinDouble(recentLow, rates[i].low);
   }
   for(int j = TrendBarsPerLeg + 1; j < 2 * TrendBarsPerLeg; j++)
   {
      oldHigh = MaxDouble(oldHigh, rates[j].high);
      oldLow = MinDouble(oldLow, rates[j].low);
   }
   if(recentHigh > oldHigh && recentLow > oldLow) return 1;
   if(recentHigh < oldHigh && recentLow < oldLow) return -1;
   return 0;
}

void GetRangeBounds(const MqlRates &rates[], const int start, const int count,
                    double &high, double &low)
{
   int end = MinInt(ArraySize(rates), start + count);
   high = -DBL_MAX;
   low = DBL_MAX;
   for(int i = start; i < end; i++)
   {
      high = MaxDouble(high, rates[i].high);
      low = MinDouble(low, rates[i].low);
   }
   if(high == -DBL_MAX) high = 0.0;
   if(low == DBL_MAX) low = 0.0;
}

int CountDirectionChanges(const MqlRates &rates[], const int start, const int count)
{
   int changes = 0, previous = 0;
   int end = MinInt(ArraySize(rates), start + count);
   for(int i = start; i < end; i++)
   {
      int direction = BarDirection(rates[i]);
      if(direction != 0)
      {
         if(previous != 0 && direction != previous) changes++;
         previous = direction;
      }
   }
   return changes;
}

int CountOverlaps(const MqlRates &rates[], const int start, const int count)
{
   int overlaps = 0;
   int end = MinInt(ArraySize(rates) - 1, start + count - 1);
   for(int i = start; i < end; i++)
   {
      double overlap = MinDouble(rates[i].high, rates[i+1].high) -
                       MaxDouble(rates[i].low, rates[i+1].low);
      if(overlap > 0.0) overlaps++;
   }
   return overlaps;
}

bool IsTightRange(const MqlRates &rates[])
{
   if(ArraySize(rates) < 14) return false;
   double recent = AverageRange(rates, 0, 6);
   double prior = AverageRange(rates, 6, 6);
   int overlap = CountOverlaps(rates, 0, 8);
   return (prior > 0.0 && recent <= prior * 0.75 && overlap >= 5);
}

bool IsTriangle(const MqlRates &rates[], double &olderHigh, double &olderLow)
{
   if(ArraySize(rates) < 18) return false;
   double recentHigh, recentLow;
   GetRangeBounds(rates, 0, 8, recentHigh, recentLow);
   GetRangeBounds(rates, 8, 8, olderHigh, olderLow);
   return (recentHigh < olderHigh && recentLow > olderLow && recentHigh > recentLow);
}

int CountApproximateLegs(const MqlRates &rates[], const int bars)
{
   int n = MinInt(bars, ArraySize(rates) - 2);
   int pivots = 0;
   for(int i = 1; i < n; i++)
   {
      bool pivotHigh = rates[i].high >= rates[i-1].high && rates[i].high > rates[i+1].high;
      bool pivotLow = rates[i].low <= rates[i-1].low && rates[i].low < rates[i+1].low;
      if(pivotHigh || pivotLow) pivots++;
   }
   return MinInt(4, pivots);
}

void DetectDoubleTopBottom(const MqlRates &rates[], const double tolerance,
                           bool &doubleTop, bool &doubleBottom)
{
   doubleTop = false;
   doubleBottom = false;
   int firstHigh = -1, secondHigh = -1, firstLow = -1, secondLow = -1;
   int scan = MinInt(16, ArraySize(rates) - 2);
   for(int i = 2; i < scan; i++)
   {
      bool ph = rates[i].high >= rates[i-1].high && rates[i].high > rates[i+1].high;
      bool pl = rates[i].low <= rates[i-1].low && rates[i].low < rates[i+1].low;
      if(ph) { if(firstHigh < 0) firstHigh = i; else if(secondHigh < 0) secondHigh = i; }
      if(pl) { if(firstLow < 0) firstLow = i; else if(secondLow < 0) secondLow = i; }
   }
   if(firstHigh >= 0 && secondHigh >= 0)
      doubleTop = (MathAbs(rates[firstHigh].high - rates[secondHigh].high) <= tolerance);
   if(firstLow >= 0 && secondLow >= 0)
      doubleBottom = (MathAbs(rates[firstLow].low - rates[secondLow].low) <= tolerance);
}

void DetectHeadShoulders(const MqlRates &rates[], const double tolerance,
                         bool &top, bool &bottom)
{
   top = false;
   bottom = false;
   int highs[3] = {-1, -1, -1};
   int lows[3] = {-1, -1, -1};
   int highCount = 0, lowCount = 0;
   int scan = MinInt(22, ArraySize(rates) - 2);
   for(int i = 2; i < scan; i++)
   {
      bool ph = rates[i].high >= rates[i-1].high && rates[i].high > rates[i+1].high;
      bool pl = rates[i].low <= rates[i-1].low && rates[i].low < rates[i+1].low;
      if(ph && highCount < 3) highs[highCount++] = i;
      if(pl && lowCount < 3) lows[lowCount++] = i;
   }
   // With series arrays, the first pivot found is newest: p2 is the left shoulder,
   // p1 the head, and p0 the right shoulder.
   if(highCount == 3)
      top = (rates[highs[1]].high > rates[highs[2]].high &&
             rates[highs[1]].high > rates[highs[0]].high &&
             MathAbs(rates[highs[2]].high - rates[highs[0]].high) <= tolerance);
   if(lowCount == 3)
      bottom = (rates[lows[1]].low < rates[lows[2]].low &&
                rates[lows[1]].low < rates[lows[0]].low &&
                MathAbs(rates[lows[2]].low - rates[lows[0]].low) <= tolerance);
}

bool DetectWedgeUp(const MqlRates &rates[])
{
   if(ArraySize(rates) < 12) return false;
   double p0 = rates[0].high, p1 = rates[3].high, p2 = rates[6].high, p3 = rates[9].high;
   return (p0 > p1 && p1 > p2 && p2 > p3 && (p0-p1) < (p1-p2) && (p1-p2) < (p2-p3));
}

bool DetectWedgeDown(const MqlRates &rates[])
{
   if(ArraySize(rates) < 12) return false;
   double p0 = rates[0].low, p1 = rates[3].low, p2 = rates[6].low, p3 = rates[9].low;
   return (p0 < p1 && p1 < p2 && p2 < p3 && (p1-p0) < (p2-p1) && (p2-p1) < (p3-p2));
}

bool InConfiguredSession()
{
   if(!UseSessionFilter) return true;
   MqlDateTime now;
   TimeToStruct(TimeTradeServer(), now);
   int current = now.hour * 60 + now.min;
   int start = SessionStartHour * 60;
   int finish = SessionEndHour * 60;
   if(start == finish) return true;
   if(start < finish) return (current >= start && current < finish);
   return (current >= start || current < finish);
}

void FindMagnets(const MqlRates &rates[], SContext &ctx)
{
   double candidates[7];
   candidates[0] = ctx.ma;
   candidates[1] = iHigh(_Symbol, PERIOD_D1, 1);
   candidates[2] = iLow(_Symbol, PERIOD_D1, 1);
   candidates[3] = ctx.rangeHigh;
   candidates[4] = ctx.rangeLow;
   candidates[5] = 0.0;
   candidates[6] = 0.0;
   int scan = MinInt(20, ArraySize(rates) - 2);
   for(int i = 2; i < scan; i++)
   {
      if(rates[i].high >= rates[i-1].high && rates[i].high > rates[i+1].high)
      { candidates[5] = rates[i].high; break; }
   }
   for(int j = 2; j < scan; j++)
   {
      if(rates[j].low <= rates[j-1].low && rates[j].low < rates[j+1].low)
      { candidates[6] = rates[j].low; break; }
   }
   double current = rates[0].close;
   ctx.nearestMagnetAbove = DBL_MAX;
   ctx.nearestMagnetBelow = -DBL_MAX;
   for(int i = 0; i < 7; i++)
   {
      if(candidates[i] <= 0.0) continue;
      if(candidates[i] > current && candidates[i] < ctx.nearestMagnetAbove)
         ctx.nearestMagnetAbove = candidates[i];
      if(candidates[i] < current && candidates[i] > ctx.nearestMagnetBelow)
         ctx.nearestMagnetBelow = candidates[i];
   }
   ctx.magnetAbove = (ctx.nearestMagnetAbove < DBL_MAX);
   ctx.magnetBelow = (ctx.nearestMagnetBelow > -DBL_MAX);
}

void AnalyzeContext(const MqlRates &entry[], const MqlRates &trend[], SContext &ctx)
{
   ctx.trend = DetectTrend(trend);
   int lookback = MinInt(RangeLookback, ArraySize(entry) - 2);
   GetRangeBounds(entry, 1, lookback, ctx.rangeHigh, ctx.rangeLow);
   int flips = CountDirectionChanges(entry, 0, lookback);
   int overlaps = CountOverlaps(entry, 0, lookback);
   double overlapRatio = (lookback > 1 ? (double)overlaps / (lookback - 1) : 0.0);
   ctx.range = (flips >= 4 && overlapRatio >= RangeOverlapThreshold);
   ctx.tightRange = IsTightRange(entry);
   double triangleHigh, triangleLow;
   ctx.triangle = IsTriangle(entry, triangleHigh, triangleLow);
   ctx.ma = AverageClose(entry, 0, MovingAveragePeriod);
   ctx.atrLike = AverageRange(entry, 0, 14);
   ctx.bullMA = (ctx.ma > 0.0 && entry[0].low > ctx.ma);
   ctx.bearMA = (ctx.ma > 0.0 && entry[0].high < ctx.ma);
   double priorMA = AverageClose(entry, 1, MovingAveragePeriod);
   ctx.firstMAGapUp = (ctx.bullMA && priorMA > 0.0 && entry[1].low <= priorMA);
   ctx.firstMAGapDown = (ctx.bearMA && priorMA > 0.0 && entry[1].high >= priorMA);
   ctx.gapUp = (ArraySize(entry) > 1 && entry[0].low > entry[1].high);
   ctx.gapDown = (ArraySize(entry) > 1 && entry[0].high < entry[1].low);
   ctx.breakoutUp = (entry[0].close > ctx.rangeHigh);
   ctx.breakoutDown = (entry[0].close < ctx.rangeLow);
   ctx.strongBreakoutUp = (ctx.breakoutUp && BarDirection(entry[0]) > 0 &&
                           BodyShare(entry[0]) >= StrongBodyShare &&
                           (entry[0].high - entry[0].close) <= BarRange(entry[0]) * 0.20);
   ctx.strongBreakoutDown = (ctx.breakoutDown && BarDirection(entry[0]) < 0 &&
                             BodyShare(entry[0]) >= StrongBodyShare &&
                             (entry[0].close - entry[0].low) <= BarRange(entry[0]) * 0.20);
   double priorHigh, priorLow;
   GetRangeBounds(entry, 2, MinInt(lookback, ArraySize(entry) - 2), priorHigh, priorLow);
   ctx.followThroughUp = (ArraySize(entry) > 1 && entry[1].close > priorHigh &&
                          entry[0].close > entry[1].close);
   ctx.followThroughDown = (ArraySize(entry) > 1 && entry[1].close < priorLow &&
                            entry[0].close < entry[1].close);
   ctx.failedBreakoutUp = (ArraySize(entry) > 2 && entry[1].high > priorHigh &&
                           entry[0].close < priorHigh);
   ctx.failedBreakoutDown = (ArraySize(entry) > 2 && entry[1].low < priorLow &&
                             entry[0].close > priorLow);
   ctx.twentyGapUp = false;
   ctx.twentyGapDown = false;
   int above = 0, below = 0;
   int gapScan = MinInt(30, ArraySize(entry));
   for(int i = 0; i < gapScan; i++)
   {
      double ma = AverageClose(entry, i, MovingAveragePeriod);
      if(ma <= 0.0) break;
      if(entry[i].low > ma) above++; else break;
   }
   for(int j = 0; j < gapScan; j++)
   {
      double ma = AverageClose(entry, j, MovingAveragePeriod);
      if(ma <= 0.0) break;
      if(entry[j].high < ma) below++; else break;
   }
   ctx.twentyGapUp = (above >= 20);
   ctx.twentyGapDown = (below >= 20);
   ctx.pullbackWeakening = (CountDirectionChanges(entry, 0, 8) >= 3 &&
                            CountOverlaps(entry, 0, 8) >= 4);
   DetectDoubleTopBottom(entry, MaxDouble(TickSize() * 4.0, ctx.atrLike * 0.30),
                         ctx.doubleTop, ctx.doubleBottom);
   DetectHeadShoulders(entry, MaxDouble(TickSize() * 4.0, ctx.atrLike * 0.30),
                       ctx.headShouldersTop, ctx.headShouldersBottom);
   ctx.wedgeUp = DetectWedgeUp(entry);
   ctx.wedgeDown = DetectWedgeDown(entry);
   ctx.legCount = CountApproximateLegs(entry, 20);
   ctx.attemptCount = MinInt(4, CountDirectionChanges(entry, 0, 10) / 2 + 1);
   ctx.highLowCount = ctx.attemptCount;
   ctx.high2 = (ctx.range && ctx.attemptCount >= 2 && entry[0].close > entry[0].open &&
                entry[0].close > entry[1].high &&
                entry[0].close <= ctx.rangeLow + (ctx.rangeHigh-ctx.rangeLow) * RangeEdgePercent/100.0);
   ctx.low2 = (ctx.range && ctx.attemptCount >= 2 && entry[0].close < entry[0].open &&
               entry[0].close < entry[1].low &&
               entry[0].close >= ctx.rangeHigh - (ctx.rangeHigh-ctx.rangeLow) * RangeEdgePercent/100.0);
   double edgeSize = (ctx.rangeHigh - ctx.rangeLow) * RangeEdgePercent / 100.0;
   ctx.nearRangeLow = (ctx.range && edgeSize > 0.0 && entry[0].close <= ctx.rangeLow + edgeSize);
   ctx.nearRangeHigh = (ctx.range && edgeSize > 0.0 && entry[0].close >= ctx.rangeHigh - edgeSize);
   ctx.sessionOK = InConfiguredSession();
   double oldHigh, oldLow;
   GetRangeBounds(entry, 5, MinInt(10, ArraySize(entry)-5), oldHigh, oldLow);
   double leg = MaxDouble(oldHigh-oldLow, ctx.atrLike);
   ctx.measuredMoveUp = entry[0].close + leg;
   ctx.measuredMoveDown = entry[0].close - leg;
   if(ctx.gapUp) ctx.measuredMoveUp = entry[0].close + (entry[0].low-entry[1].high);
   if(ctx.gapDown) ctx.measuredMoveDown = entry[0].close - (entry[1].low-entry[0].high);
   FindMagnets(entry, ctx);
   ctx.priorFailureMagnet = (ctx.failedBreakoutUp || ctx.failedBreakoutDown);
   ctx.duelingLines = (ctx.atrLike > 0.0 &&
                       MathAbs(entry[0].close - ctx.ma) <= ctx.atrLike * 0.35 &&
                       ((ctx.magnetAbove && ctx.magnetBelow) || ctx.doubleTop || ctx.doubleBottom));
}

int CountReasonGroups(const SContext &ctx, const int direction)
{
   int groups = 0;
   bool trendAligned = (direction > 0 ? ctx.trend > 0 : ctx.trend < 0);
   bool rangeLocation = (direction > 0 ? ctx.nearRangeLow : ctx.nearRangeHigh);
   bool patternGroup = (direction > 0 ? (ctx.strongBreakoutUp || ctx.followThroughUp ||
                                        ctx.failedBreakoutDown || ctx.high2 || ctx.wedgeDown || ctx.doubleBottom ||
                                        ctx.headShouldersBottom || ctx.firstMAGapUp)
                                      : (ctx.strongBreakoutDown || ctx.followThroughDown ||
                                        ctx.failedBreakoutUp || ctx.low2 || ctx.wedgeUp || ctx.doubleTop ||
                                        ctx.headShouldersTop || ctx.firstMAGapDown));
   // A magnet is primarily a target; do not count it as a second reason by itself.
   bool contextGroup = (trendAligned || rangeLocation);
   bool independentTimeGroup = ctx.sessionOK && UseSessionFilter;
   bool volatilityGroup = (direction > 0 ? ctx.twentyGapUp : ctx.twentyGapDown) ||
                          ctx.tightRange || ctx.triangle || ctx.duelingLines;
   if(patternGroup) groups++;
   if(contextGroup) groups++;
   if(independentTimeGroup) groups++;
   if(volatilityGroup) groups++;
   return groups;
}

bool IsBullishCandidate(const SContext &ctx)
{
   bool candidate = (ctx.strongBreakoutUp || ctx.followThroughUp || ctx.failedBreakoutDown ||
                     ctx.high2 || ctx.wedgeDown || ctx.doubleBottom || ctx.headShouldersBottom || ctx.firstMAGapUp);
   if(ctx.trend < 0 && !ctx.failedBreakoutDown && !ctx.wedgeDown && !ctx.doubleBottom && !ctx.headShouldersBottom)
      return false;
   return candidate;
}

bool IsBearishCandidate(const SContext &ctx)
{
   bool candidate = (ctx.strongBreakoutDown || ctx.followThroughDown || ctx.failedBreakoutUp ||
                     ctx.low2 || ctx.wedgeUp || ctx.doubleTop || ctx.headShouldersTop || ctx.firstMAGapDown);
   if(ctx.trend > 0 && !ctx.failedBreakoutUp && !ctx.wedgeUp && !ctx.doubleTop && !ctx.headShouldersTop)
      return false;
   return candidate;
}

double ChooseMagnetTarget(const SContext &ctx, const int direction,
                          const double entry, const double risk)
{
   double minRR = MaxDouble(1.0, TargetRR * 0.75);
   if(direction > 0 && ctx.magnetAbove && ctx.nearestMagnetAbove-entry >= risk*minRR)
      return ctx.nearestMagnetAbove;
   if(direction < 0 && ctx.magnetBelow && entry-ctx.nearestMagnetBelow >= risk*minRR)
      return ctx.nearestMagnetBelow;
   if(direction > 0 && ctx.measuredMoveUp-entry >= risk*minRR) return ctx.measuredMoveUp;
   if(direction < 0 && entry-ctx.measuredMoveDown >= risk*minRR) return ctx.measuredMoveDown;
   return (direction > 0 ? entry + risk*TargetRR : entry - risk*TargetRR);
}

double EstimateExpectedValue(const int direction, const double entry,
                             const double stop, const double target)
{
   double risk = MathAbs(entry-stop) / _Point;
   double reward = MathAbs(target-entry) / _Point;
   double costs = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) +
                  SlippagePointsEstimate;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickValue > 0.0 && _Point > 0.0)
      costs += CommissionPerLotRoundTurn / tickValue * TickSize() / _Point;
   double p = MathMax(0.0, MathMin(1.0, EstimatedWinProbability));
   return p * (reward-costs) - (1.0-p) * (risk+costs);
}

bool BuildSetup(const SContext &ctx, const MqlRates &rates[], SSetup &setup)
{
   setup.direction = 0;
   setup.reasonGroups = 0;
   setup.isRangeSetup = false;
   setup.useLimit = false;
   setup.entry = 0.0;
   setup.stop = 0.0;
   setup.target = 0.0;
   setup.expectedValue = 0.0;
   setup.label = "NONE";

   bool bull = IsBullishCandidate(ctx);
   bool bear = IsBearishCandidate(ctx);
   if(bull == bear) return false;
   int direction = (bull ? 1 : -1);
   setup.direction = direction;
   setup.reasonGroups = CountReasonGroups(ctx, direction);
   setup.isRangeSetup = (ctx.range && (ctx.high2 || ctx.low2 || ctx.failedBreakoutUp || ctx.failedBreakoutDown));
   if(setup.reasonGroups < MinReasonGroups || !ctx.sessionOK) return false;

   double tick = TickSize();
   double width = ctx.rangeHigh - ctx.rangeLow;
   double stopBuffer = MaxDouble(tick, _Point * (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL));
   if(direction > 0)
   {
      setup.entry = rates[0].high + tick;
      setup.stop = rates[0].low - stopBuffer;
      if(setup.isRangeSetup && EnableLimitEntries && width > 0.0)
      {
         double limitPrice = ctx.rangeLow + width * 0.15;
         if(limitPrice < SymbolInfoDouble(_Symbol, SYMBOL_ASK))
         {
            setup.entry = limitPrice;
            setup.useLimit = true;
            setup.stop = ctx.rangeLow - stopBuffer;
         }
      }
      setup.target = ChooseMagnetTarget(ctx, direction, setup.entry, setup.entry-setup.stop);
   }
   else
   {
      setup.entry = rates[0].low - tick;
      setup.stop = rates[0].high + stopBuffer;
      if(setup.isRangeSetup && EnableLimitEntries && width > 0.0)
      {
         double limitPrice = ctx.rangeHigh - width * 0.15;
         if(limitPrice > SymbolInfoDouble(_Symbol, SYMBOL_BID))
         {
            setup.entry = limitPrice;
            setup.useLimit = true;
            setup.stop = ctx.rangeHigh + stopBuffer;
         }
      }
      setup.target = ChooseMagnetTarget(ctx, direction, setup.entry, setup.stop-setup.entry);
   }

   if((direction > 0 && (setup.stop >= setup.entry || setup.target <= setup.entry)) ||
      (direction < 0 && (setup.stop <= setup.entry || setup.target >= setup.entry))) return false;
   setup.entry = NormalizePrice(setup.entry);
   setup.stop = NormalizePrice(setup.stop);
   setup.target = NormalizePrice(setup.target);
   setup.expectedValue = EstimateExpectedValue(direction, setup.entry, setup.stop, setup.target);
   if(setup.expectedValue <= 0.0) return false;
   setup.label = (direction > 0 ? "BUY" : "SELL");
   if(ctx.failedBreakoutUp || ctx.failedBreakoutDown) setup.label += " failed-breakout";
   else if(ctx.high2 || ctx.low2) setup.label += " H2/L2";
   else if(ctx.wedgeUp || ctx.wedgeDown) setup.label += " three-push";
   else setup.label += " breakout/trend";
   return true;
}

double NormalizeVolumeDown(const double volume)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0 || minVol <= 0.0) return 0.0;
   double rounded = MathFloor(volume / step) * step;
   if(rounded < minVol) return 0.0;
   return NormalizeDouble(MathMin(rounded, maxVol), 8);
}

double CalculateRiskVolume(const int direction, const double entry, const double stop)
{
   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * RiskPercent / 100.0;
   if(riskMoney <= 0.0) return 0.0;
   double oneLotProfit = 0.0;
   ENUM_ORDER_TYPE type = (direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double spreadBuffer = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * _Point;
   double slipBuffer = (double)SlippagePointsEstimate * _Point;
   double riskEntry = entry + direction * slipBuffer;
   double riskStop = stop - direction * (spreadBuffer + slipBuffer);
   if(!OrderCalcProfit(type, _Symbol, 1.0, riskEntry, riskStop, oneLotProfit)) return 0.0;
   double lossPerLot = MathAbs(oneLotProfit) + CommissionPerLotRoundTurn;
   if(lossPerLot <= 0.0) return 0.0;
   return NormalizeVolumeDown(riskMoney / lossPerLot);
}

bool HasManagedPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == MagicNumber) return true;
   }
   return false;
}

ulong FindManagedPositionTicket()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == MagicNumber) return ticket;
   }
   return 0;
}

bool TradeResultSucceeded()
{
   uint code = trade.ResultRetcode();
   return (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_PLACED ||
           code == TRADE_RETCODE_DONE_PARTIAL || code == TRADE_RETCODE_NO_CHANGES);
}

bool ModifyManagedPosition(const ulong ticket, const double stop, const double target)
{
   bool sent = trade.PositionModify(ticket, stop, target);
   if(!sent || !TradeResultSucceeded())
   {
      Print("POSITION MODIFY REJECTED: ", trade.ResultRetcode(),
            " | ", trade.ResultRetcodeDescription());
      return false;
   }
   return true;
}

bool HasManagedPendingOrder()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         (ulong)OrderGetInteger(ORDER_MAGIC) == MagicNumber) return true;
   }
   return false;
}

bool HasUnmanagedNettingExposure()
{
   ENUM_ACCOUNT_MARGIN_MODE mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) return false;
   if(PositionSelect(_Symbol) && (ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
      return true;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         (ulong)OrderGetInteger(ORDER_MAGIC) != MagicNumber) return true;
   }
   return false;
}

bool CancelManagedPendingOrders()
{
   bool allCleared = true;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         (ulong)OrderGetInteger(ORDER_MAGIC) == MagicNumber)
      {
         bool sent = trade.OrderDelete(ticket);
         if(!sent || !TradeResultSucceeded())
         {
            allCleared = false;
            Print("PENDING ORDER CLEANUP REJECTED: ", trade.ResultRetcode(),
                  " | ", trade.ResultRetcodeDescription());
         }
      }
   }
   return allCleared;
}

bool PlaceSetupOrder(const SSetup &setup)
{
   if(!EnableTradeExecution || HasManagedPosition() || HasManagedPendingOrder()) return false;
   if(HasUnmanagedNettingExposure())
   {
      Print("ORDER BLOCKED: This symbol has another netting position or pending order.");
      return false;
   }
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) != ACCOUNT_TRADE_MODE_DEMO)
   {
      Print("SAFETY BLOCK: Demo account required before order placement.");
      return false;
   }
   if(EnableScaleIn)
   {
      Print("SAFETY BLOCK: Scale-in is not supported in this research version.");
      return false;
   }

   double volume = CalculateRiskVolume(setup.direction, setup.entry, setup.stop);
   if(volume <= 0.0)
   {
      Print("ORDER SKIPPED: Calculated size is below the broker minimum or risk calculation failed.");
      return false;
   }
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints((ulong)SlippagePointsEstimate);
   trade.SetTypeFillingBySymbol(_Symbol);
   datetime expiry = TimeTradeServer() + PeriodSeconds(EntryTF) * 2;
   bool sent = false;
   if(setup.direction > 0 && setup.useLimit)
      sent = trade.BuyLimit(volume, setup.entry, _Symbol, setup.stop, setup.target,
                            ORDER_TIME_SPECIFIED, expiry, "BootAI V2 range limit");
   else if(setup.direction < 0 && setup.useLimit)
      sent = trade.SellLimit(volume, setup.entry, _Symbol, setup.stop, setup.target,
                             ORDER_TIME_SPECIFIED, expiry, "BootAI V2 range limit");
   else if(setup.direction > 0)
      sent = trade.BuyStop(volume, setup.entry, _Symbol, setup.stop, setup.target,
                           ORDER_TIME_SPECIFIED, expiry, "BootAI V2 stop entry");
   else
      sent = trade.SellStop(volume, setup.entry, _Symbol, setup.stop, setup.target,
                            ORDER_TIME_SPECIFIED, expiry, "BootAI V2 stop entry");

   if(!sent || !TradeResultSucceeded())
   {
      Print("ORDER REJECTED: ", trade.ResultRetcode(), " | ", trade.ResultRetcodeDescription());
      return false;
   }
   Print("PENDING ORDER: ", setup.label, " | volume=", DoubleToString(volume, 2),
         " | entry=", DoubleToString(setup.entry, _Digits),
         " | stop=", DoubleToString(setup.stop, _Digits),
         " | target=", DoubleToString(setup.target, _Digits),
         " | evidence groups=", setup.reasonGroups,
         " | estimated EV points=", DoubleToString(setup.expectedValue, 1));
   return true;
}

void ManageOpenPosition(const MqlRates &rates[])
{
   ulong ticket = FindManagedPositionTicket();
   if(ticket == 0 || !PositionSelectByTicket(ticket)) return;
   long type = PositionGetInteger(POSITION_TYPE);
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double stop = PositionGetDouble(POSITION_SL);
   double target = PositionGetDouble(POSITION_TP);
   double volume = PositionGetDouble(POSITION_VOLUME);
   datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
   string partialKey = "BAI2_PART_" + (string)ticket;
   string riskKey = "BAI2_RISK_" + (string)ticket;

   int maxBars = (TradeStyle == STYLE_SCALP ? 1 :
                  TradeStyle == STYLE_INTRADAY_SWING ? 40 : 160);
   int heldBars = iBarShift(_Symbol, EntryTF, opened, false);
   if(heldBars >= maxBars && maxBars > 0)
   {
      bool closed = trade.PositionClose(ticket);
      if(closed && TradeResultSucceeded()) Print("TIME EXIT: configured holding window reached.");
      else Print("TIME EXIT REJECTED: ", trade.ResultRetcode(), " | ", trade.ResultRetcodeDescription());
      return;
   }

   double initialRisk = 0.0;
   if(GlobalVariableCheck(riskKey))
      initialRisk = GlobalVariableGet(riskKey);
   else
   {
      initialRisk = MathAbs(open-stop);
      if(initialRisk > 0.0) GlobalVariableSet(riskKey, initialRisk);
   }
   if(initialRisk <= 0.0) return;
   double mark = (type == POSITION_TYPE_BUY ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                             : SymbolInfoDouble(_Symbol, SYMBOL_ASK));
   double favorable = (type == POSITION_TYPE_BUY ? mark-open : open-mark);
   if(EnablePartialExit && favorable >= initialRisk && !GlobalVariableCheck(partialKey))
   {
      double closeVolume = NormalizeVolumeDown(volume * 0.50);
      bool partialSent = false;
      if(closeVolume > 0.0 && closeVolume < volume)
      {
         ENUM_ACCOUNT_MARGIN_MODE marginMode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
         if(marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
            partialSent = trade.PositionClosePartial(ticket, closeVolume);
         else if(type == POSITION_TYPE_BUY)
            partialSent = trade.Sell(closeVolume, _Symbol, 0.0, 0.0, 0.0, "BootAI V2 partial close");
         else
            partialSent = trade.Buy(closeVolume, _Symbol, 0.0, 0.0, 0.0, "BootAI V2 partial close");
      }
      if(partialSent && TradeResultSucceeded())
      {
         GlobalVariableSet(partialKey, 1.0);
         Print("PARTIAL EXIT: closed half after approximately 1R.");
      }
      else if(partialSent)
      {
         Print("PARTIAL EXIT REJECTED: ", trade.ResultRetcode(), " | ", trade.ResultRetcodeDescription());
      }
   }

   if(MoveStopToBreakevenAtOneR && favorable >= initialRisk)
   {
      double be = NormalizePrice(open);
      if((type == POSITION_TYPE_BUY && (stop < be || stop == 0.0)) ||
         (type == POSITION_TYPE_SELL && (stop > be || stop == 0.0)))
      {
         if(ModifyManagedPosition(ticket, be, target)) stop = be;
      }
   }

   if(!EnableSwingTrailingStop || ArraySize(rates) < 4) return;
   double candidate = stop;
   if(type == POSITION_TYPE_BUY)
   {
      double swingLow = rates[0].low;
      for(int i = 1; i < MinInt(4, ArraySize(rates)); i++) swingLow = MinDouble(swingLow, rates[i].low);
      candidate = NormalizePrice(swingLow - TickSize());
      if(candidate > stop && candidate < mark)
         ModifyManagedPosition(ticket, candidate, target);
   }
   else
   {
      double swingHigh = rates[0].high;
      for(int j = 1; j < MinInt(4, ArraySize(rates)); j++) swingHigh = MaxDouble(swingHigh, rates[j].high);
      candidate = NormalizePrice(swingHigh + TickSize());
      if((stop == 0.0 || candidate < stop) && candidate > mark)
         ModifyManagedPosition(ticket, candidate, target);
   }
}

void PrintContext(const SContext &ctx, const SSetup &setup, const bool hasSetup)
{
   string trendName = (ctx.trend > 0 ? "UP" : ctx.trend < 0 ? "DOWN" : "UNCLEAR/RANGE");
   Print("BOOTAI V2 | ", _Symbol, " | ", EnumToString(EntryTF),
         " | HTF trend=", trendName,
         " | range=", (ctx.range ? "yes" : "no"),
         " | tight=", (ctx.tightRange ? "yes" : "no"),
         " | triangle=", (ctx.triangle ? "yes" : "no"),
         " | legs~", ctx.legCount, " | attempts~", ctx.attemptCount);
   Print("Evidence | breakout+", ctx.breakoutUp, "/-", ctx.breakoutDown,
         " | strong+", ctx.strongBreakoutUp, "/-", ctx.strongBreakoutDown,
         " | failed+", ctx.failedBreakoutUp, "/-", ctx.failedBreakoutDown,
         " | H2/L2=", ctx.high2, "/", ctx.low2,
         " | wedge=", ctx.wedgeDown, "/", ctx.wedgeUp,
         " | DT/DB=", ctx.doubleTop, "/", ctx.doubleBottom,
         " | MA20-gap=", ctx.twentyGapUp, "/", ctx.twentyGapDown,
         " | session=", ctx.sessionOK);
   if(hasSetup)
      Print("CANDIDATE | ", setup.label, " | evidence groups=", setup.reasonGroups,
            " | entry=", DoubleToString(setup.entry, _Digits),
            " | stop=", DoubleToString(setup.stop, _Digits),
            " | target=", DoubleToString(setup.target, _Digits),
            " | EV points=", DoubleToString(setup.expectedValue, 1),
            " | order=", (setup.useLimit ? "LIMIT" : "STOP"));
   else
      Print("NO QUALIFIED SETUP | screening only; no order requested.");
}

int OnInit()
{
   int requiredEntryBars = MaxInt(MaxInt(40, RangeLookback + 2), MovingAveragePeriod + 20);
   int requiredTrendBars = MaxInt(10, 2 * TrendBarsPerLeg);
   if(BarsToRead < requiredEntryBars || BarsToRead < requiredTrendBars ||
      RangeLookback < 6 || MovingAveragePeriod < 2 || TrendBarsPerLeg < 5)
   {
      Print("INPUT ERROR: BarsToRead must cover the range, 20-gap MA sample, and two trend legs; "
            "RangeLookback >= 6, MA period >= 2, TrendBarsPerLeg >= 5.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(PeriodSeconds(TrendTF) <= PeriodSeconds(EntryTF))
   {
      Print("INPUT ERROR: TrendTF must be higher than EntryTF.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(RiskPercent <= 0.0 || RiskPercent > 1.0 || EstimatedWinProbability < 0.0 ||
      EstimatedWinProbability > 1.0 || TargetRR <= 0.0 || MinReasonGroups < 1 ||
      MinReasonGroups > 4 || CommissionPerLotRoundTurn < 0.0 || SlippagePointsEstimate < 0 ||
      RangeOverlapThreshold < 0.0 || RangeOverlapThreshold > 1.0 ||
      RangeEdgePercent <= 0.0 || RangeEdgePercent >= 50.0 ||
      StrongBodyShare < 0.0 || StrongBodyShare > 1.0 ||
      SessionStartHour < 0 || SessionStartHour > 23 || SessionEndHour < 0 || SessionEndHour > 23)
   {
      Print("INPUT ERROR: Risk, probability, target, or evidence threshold is invalid.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(EnableScaleIn)
   {
      Print("SAFETY BLOCK: Scale-in is not implemented in this version.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(EnableTradeExecution && AccountInfoInteger(ACCOUNT_TRADE_MODE) != ACCOUNT_TRADE_MODE_DEMO)
   {
      Print("SAFETY BLOCK: Trade execution requires a demo account.");
      return INIT_FAILED;
   }
   if(!SymbolSelect(_Symbol, true))
   {
      Print("INIT ERROR: Could not select symbol.");
      return INIT_FAILED;
   }
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);
   g_lastEntryBar = iTime(_Symbol, EntryTF, 0);
   g_lastManageBar = g_lastEntryBar;
   Print("Boot AI V2 started. Execution=", (EnableTradeExecution ? "ON" : "OFF"),
         " | demo-only execution | scale-in=disabled.");
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(HasManagedPosition() && HasManagedPendingOrder())
      CancelManagedPendingOrders();

   MqlRates entry[];
   MqlRates trend[];
   int requiredEntryBars = MaxInt(MaxInt(40, RangeLookback + 2), MovingAveragePeriod + 20);
   int requiredTrendBars = MaxInt(10, 2 * TrendBarsPerLeg);
   if(!ReadClosedRates(EntryTF, requiredEntryBars, entry) ||
      !ReadClosedRates(TrendTF, requiredTrendBars, trend)) return;

   datetime currentBar = iTime(_Symbol, EntryTF, 0);
   if(currentBar == 0) return;
   if(currentBar != g_lastManageBar)
   {
      ManageOpenPosition(entry);
      g_lastManageBar = currentBar;
   }
   if(currentBar == g_lastEntryBar) return;
   g_lastEntryBar = currentBar;

   SContext ctx;
   AnalyzeContext(entry, trend, ctx);
   SSetup setup;
   bool hasSetup = BuildSetup(ctx, entry, setup);
   PrintContext(ctx, setup, hasSetup);
   if(!hasSetup) return;

   string key = (string)entry[0].time + "_" + setup.label;
   if(key == g_lastSignalKey) return;
   g_lastSignalKey = key;
   if(EnableTradeExecution) PlaceSetupOrder(setup);
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(HasManagedPosition()) CancelManagedPendingOrders();
}

void OnDeinit(const int reason)
{
   Print("Boot AI V2 stopped. Reason=", reason);
}

