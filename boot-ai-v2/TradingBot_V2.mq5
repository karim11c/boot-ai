#property strict
#property version   "2.000"
#property description "Boot AI V2 - research implementation of Al Brooks Trading Ranges concepts"

#include <Trade/Trade.mqh>

// All numeric thres  double stop;
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

bool IsSteepTrend(const MqlRates &rates[], const int direction)
{
   int bars = MinInt(TrendBarsPerLeg, ArraySize(rates) - 1);
   if(direction == 0 || bars < 3) return false;
   double averageRange = AverageRange(rates, 0, bars);
   if(averageRange <= 0.0) return false;
   double directionalMove = (double)direction * (rates[0].close - rates[bars-1].close);
   int overlapCount = CountOverlaps(rates, 0, bars);
   return (directionalMove >= averageRange * SteepTrendDisplacementATR &&
           overlapCount <= (bars - 1) / 2);
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

// Chapters 3 and 5 proxy: find a prior range breakout followed by a pullback
// that tests the boundary without a decisive close back through it, then a
// current-bar rejection in the breakout direction. Tolerances are engineering
// estimates; test windows are limited to available closed-bar history.
void FindRecentBreakoutPullbackTests(const MqlRates &rates[], const int rangeBars,
                                    const int maxAge, const double tolerance,
                                    bool &bullTest, double &bullLevel,
                                    bool &bearTest, double &bearLevel)
{
   bullTest = false;
   bearTest = false;
   bullLevel = 0.0;
   bearLevel = 0.0;
   int size = ArraySize(rates);
   int ageScan = MinInt(maxAge, size - rangeBars - 2);
   if(ageScan < 3) return;

   for(int i = 3; i <= ageScan; i++)
   {
      int sample = MinInt(rangeBars, size - i - 1);
      if(sample < 6) continue;
      double priorHigh, priorLow;
      GetRangeBounds(rates, i + 1, sample, priorHigh, priorLow);

      bool brokeUp = (rates[i].close > priorHigh && rates[i+1].close <= priorHigh);
      if(brokeUp)
      {
         bool touched = false, held = true;
         for(int j = i - 1; j >= 0; j--)
         {
            if(rates[j].close < priorHigh - tolerance) { held = false; break; }
            if(rates[j].low <= priorHigh + tolerance) touched = true;
         }
         if(held && touched && rates[0].close > priorHigh &&
            BarDirection(rates[0]) > 0 && rates[0].high > rates[1].high)
         {
            bullTest = true;
            bullLevel = priorHigh;
            return;
         }
      }

      bool brokeDown = (rates[i].close < priorLow && rates[i+1].close >= priorLow);
      if(brokeDown)
      {
         bool touched = false, held = true;
         for(int j = i - 1; j >= 0; j--)
         {
            if(rates[j].close > priorLow + tolerance) { held = false; break; }
            if(rates[j].high >= priorLow - tolerance) touched = true;
         }
         if(held && touched && rates[0].close < priorLow &&
            BarDirection(rates[0]) < 0 && rates[0].low < rates[1].low)
         {
            bearTest = true;
            bearLevel = priorLow;
            return;
         }
      }
   }
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

// Brooks bar counting: during a pullback, a High 1/2/3/4 is an occurrence
// where a bar's high exceeds the prior bar's high; Low 1/2/3/4 is the mirror.
// This finite-window detector is still an approximation: it cannot resolve
// every nested/fractal correction described in the source.
int CurrentPullbackSignalCount(const MqlRates &rates[], const bool countHighs,
                               const int lookback, bool &abcCorrection)
{
   abcCorrection = false;
   int n = MinInt(lookback, ArraySize(rates) - 1);
   if(n < 3) return 0;

   bool pullback = false;
   bool secondLegAfterFirstSignal = false;
   int count = 0;
   int latestSignalCount = 0;
   double trendExtreme = (countHighs ? rates[n].high : rates[n].low);
   double tick = TickSize();

   // CopyRates with a series array is indexed newest-first, so scan from old
   // bars toward index zero (the latest closed bar).
   for(int i = n - 1; i >= 0; i--)
   {
      bool counterBar = (countHighs ?
                        (rates[i].low < rates[i+1].low || rates[i].close < rates[i+1].close) :
                        (rates[i].high > rates[i+1].high || rates[i].close > rates[i+1].close));
      bool secondLegWasAlreadySeen = secondLegAfterFirstSignal;
      if(counterBar)
      {
         if(count == 1) secondLegAfterFirstSignal = true;
         pullback = true;
      }

      bool signal = (countHighs ? rates[i].high > rates[i+1].high + tick :
                                  rates[i].low < rates[i+1].low - tick);
      if(pullback && signal)
      {
         count = MinInt(4, count + 1);
         if(i == 0) latestSignalCount = count;
         if(i == 0 && count == 2 && secondLegWasAlreadySeen)
            abcCorrection = true;
      }

      bool trendResumed = (countHighs ? rates[i].high > trendExtreme + tick :
                                        rates[i].low < trendExtreme - tick);
      if(trendResumed)
      {
         trendExtreme = (countHighs ? rates[i].high : rates[i].low);
         if(i > 0)
         {
            pullback = false;
            count = 0;
            secondLegAfterFirstSignal = false;
         }
      }
   }
   return latestSignalCount;
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

bool InConfiguredSession(const datetime signalBarTime)
{
   if(!UseSessionFilter) return true;
   MqlDateTime now;
   // Use the closed signal bar's timestamp so historical runs never depend on
   // the workstation clock or the wall-clock time when the EA is evaluated.
   if(!TimeToStruct(signalBarTime, now)) return false;
   int current = now.hour * 60 + now.min;
   int start = SessionStartHour * 60;
   int finish = SessionEndHour * 60;
   if(start == finish) return true;
   if(start < finish) return (current >= start && current < finish);
   return (current >= start || current < finish);
}

// Chapter 9 proxy: a countertrend signal bar is treated as a failed entry only
// when its stop-entry extreme is crossed and a later closed bar breaches the
// signal-bar protective extreme. Keep every detected signal-bar extreme as a
// separate candidate magnet. This is an engineering approximation, not a full
// Brooks setup classifier.
void FindPriorFailedReversalSignalMagnets(const MqlRates &rates[],
                                          const double current,
                                          double &failedBullTargets[], int &bullCount,
                                          double &failedBearTargets[], int &bearCount)
{
   bullCount = 0;
   bearCount = 0;
   ArrayInitialize(failedBullTargets, 0.0);
   ArrayInitialize(failedBearTargets, 0.0);
   int scan = MinInt(100, ArraySize(rates) - 4);
   double tick = TickSize();
   for(int i = 4; i < scan; i++)
   {
      bool bearSignalInBullMove = (BarDirection(rates[i]) < 0 && BodyShare(rates[i]) >= 0.45 &&
                                   rates[i+1].close >= rates[i+2].close);
      bool bullSignalInBearMove = (BarDirection(rates[i]) > 0 && BodyShare(rates[i]) >= 0.45 &&
                                   rates[i+1].close <= rates[i+2].close);
      bool bearEntryTriggered = false;
      bool bullEntryTriggered = false;
      bool failedBearEntry = false;
      bool failedBullEntry = false;
      // Visit the three bars after the signal in chronological order. A stop
      // and its protective stop touched in the same bar is deliberately ignored
      // because OHLC data cannot reveal which was hit first.
      for(int step = 3; step >= 1; step--)
      {
         int bar = i - step;
         if(bar < 0) continue;
         if(bearEntryTriggered && rates[bar].high > rates[i].high + tick)
            failedBearEntry = true;
         if(bullEntryTriggered && rates[bar].low < rates[i].low - tick)
            failedBullEntry = true;
         if(bearSignalInBullMove && rates[bar].low < rates[i].low - tick)
            bearEntryTriggered = true;
         if(bullSignalInBearMove && rates[bar].high > rates[i].high + tick)
            bullEntryTriggered = true;
      }
      if(bearSignalInBullMove && failedBearEntry && rates[i].low < current && bearCount <= 198)
      {
         failedBearTargets[bearCount++] = rates[i].low;
         failedBearTargets[bearCount++] = rates[i].low - tick; // approximate stop-entry price
      }
      if(bullSignalInBearMove && failedBullEntry && rates[i].high > current && bullCount <= 198)
      {
         failedBullTargets[bullCount++] = rates[i].high;
         failedBullTargets[bullCount++] = rates[i].high + tick; // approximate stop-entry price
      }
   }
}

void FindMagnets(const MqlRates &rates[], SContext &ctx)
{
   double candidates[407];
   candidates[0] = ctx.ma;
   candidates[1] = iHigh(_Symbol, PERIOD_D1, 1);
   candidates[2] = iLow(_Symbol, PERIOD_D1, 1);
   candidates[3] = ctx.rangeHigh;
   candidates[4] = ctx.rangeLow;
   candidates[5] = 0.0;
   candidates[6] = 0.0;
   double failedBullTargets[200], failedBearTargets[200];
   int failedBullCount = 0, failedBearCount = 0;
   FindPriorFailedReversalSignalMagnets(rates, rates[0].close,
                                        failedBullTargets, failedBullCount,
                                        failedBearTargets, failedBearCount);
   for(int n = 0; n < 200; n++)
   {
      candidates[7+n] = failedBullTargets[n];
      candidates[207+n] = failedBearTargets[n];
   }
   ctx.failedBullReversalTarget = 0.0;
   ctx.failedBearReversalTarget = 0.0;
   for(int n = 0; n < failedBullCount; n++)
      if(failedBullTargets[n] > rates[0].close &&
         (ctx.failedBullReversalTarget == 0.0 || failedBullTargets[n] < ctx.failedBullReversalTarget))
         ctx.failedBullReversalTarget = failedBullTargets[n];
   for(int n = 0; n < failedBearCount; n++)
      if(failedBearTargets[n] < rates[0].close &&
         (ctx.failedBearReversalTarget == 0.0 || failedBearTargets[n] > ctx.failedBearReversalTarget))
         ctx.failedBearReversalTarget = failedBearTargets[n];
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
   for(int i = 0; i < 407; i++)
   {
      if(candidates[i] <= 0.0) continue;
      if(candidates[i] > current && candidates[i] < ctx.nearestMagnetAbove)
         ctx.nearestMagnetAbove = candidates[i];
      if(candidates[i] < current && candidates[i] > ctx.nearestMagnetBelow)
         ctx.nearestMagnetBelow = candidates[i];
   }
   ctx.magnetAbove = (ctx.nearestMagnetAbove < DBL_MAX);
   ctx.magnetBelow = (ctx.nearestMagnetBelow > -DBL_MAX);
   ctx.priorFailureMagnet = (ctx.failedBullReversalTarget > 0.0 ||
                             ctx.failedBearReversalTarget > 0.0);
}

// Chapter 19 approximation: fit a line through the two newest confirmed swing
// lows (support) or highs (resistance), then project it to the current bar.
// Series index decreases toward the present, so slope is expressed per bar.
bool FitRecentPivotTrendLine(const MqlRates &rates[], const bool useLows,
                             const int lookback, double &projected,
                             double &slope)
{
   projected = 0.0;
   slope = 0.0;
   int scan = MinInt(lookback, ArraySize(rates) - 2);
   int newer = -1, older = -1;
   for(int i = 2; i < scan; i++)
   {
      bool pivot = (useLows ?
                    (rates[i].low <= rates[i-1].low && rates[i].low < rates[i+1].low) :
                    (rates[i].high >= rates[i-1].high && rates[i].high > rates[i+1].high));
      if(!pivot) continue;
      if(newer < 0) newer = i;
      else { older = i; break; }
   }
   if(newer < 0 || older < 0 || older <= newer) return false;
   double newerPrice = (useLows ? rates[newer].low : rates[newer].high);
   double olderPrice = (useLows ? rates[older].low : rates[older].high);
   slope = (newerPrice - olderPrice) / (double)(older - newer);
   if(useLows && slope <= 0.0) return false;
   if(!useLows && slope >= 0.0) return false;
   projected = newerPrice + slope * (double)newer;
   return (projected > 0.0);
}

void AnalyzeContext(const MqlRates &entry[], const MqlRates &trend[], SContext &ctx)
{
   ctx.trend = DetectTrend(trend);
   ctx.steepTrend = IsSteepTrend(trend, ctx.trend);
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
   double tick = TickSize();
   bool strongBreakAboveRange = (ArraySize(entry) > 2 &&
                                 entry[1].close > priorHigh &&
                                 entry[1].high - priorHigh >= 3.0 * tick &&
                                 BarDirection(entry[1]) > 0 &&
                                 BodyShare(entry[1]) >= StrongBodyShare);
   bool strongBreakBelowRange = (ArraySize(entry) > 2 &&
                                 entry[1].close < priorLow &&
                                 priorLow - entry[1].low >= 3.0 * tick &&
                                 BarDirection(entry[1]) < 0 &&
                                 BodyShare(entry[1]) >= StrongBodyShare);
   ctx.failedBreakoutUp = (ArraySize(entry) > 2 && entry[1].high > priorHigh &&
                           entry[0].close < priorHigh);
   ctx.failedBreakoutDown = (ArraySize(entry) > 2 && entry[1].low < priorLow &&
                             entry[0].close > priorLow);
   ctx.tightRangeFailedBreakoutUp = (strongBreakAboveRange && entry[0].close < priorHigh);
   ctx.tightRangeFailedBreakoutDown = (strongBreakBelowRange && entry[0].close > priorLow);
   double breakoutTestTolerance = MaxDouble(TickSize() * 3.0, ctx.atrLike * 0.10);
   FindRecentBreakoutPullbackTests(entry, RangeLookback, 80, breakoutTestTolerance,
                                   ctx.breakoutPullbackUp, ctx.breakoutTestLevelUp,
                                   ctx.breakoutPullbackDown, ctx.breakoutTestLevelDown);
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
   ctx.channelOvershootReversalUp = (ctx.trend < 0 && ctx.wedgeDown &&
                                     ctx.failedBreakoutDown && BarDirection(entry[0]) > 0);
   ctx.channelOvershootReversalDown = (ctx.trend > 0 && ctx.wedgeUp &&
                                       ctx.failedBreakoutUp && BarDirection(entry[0]) < 0);
   ctx.legCount = CountApproximateLegs(entry, 20);
   ctx.highBarCount = CurrentPullbackSignalCount(entry, true, 20, ctx.abcBullCorrection);
   ctx.lowBarCount = CurrentPullbackSignalCount(entry, false, 20, ctx.abcBearCorrection);
   ctx.highLowCount = MaxInt(ctx.highBarCount, ctx.lowBarCount);
   ctx.attemptCount = ctx.highLowCount;
   double edgeSize = (ctx.rangeHigh - ctx.rangeLow) * RangeEdgePercent / 100.0;
   bool rangeContext = (ctx.range || ctx.tightRange);
   ctx.nearRangeLow = (rangeContext && edgeSize > 0.0 && entry[0].close <= ctx.rangeLow + edgeSize);
   ctx.nearRangeHigh = (rangeContext && edgeSize > 0.0 && entry[0].close >= ctx.rangeHigh - edgeSize);
   bool smallSignalBar = (ctx.atrLike > 0.0 &&
                          BarRange(entry[0]) <= ctx.atrLike * SmallBarRangeATR);
   ctx.tightRangeBullFade = (ctx.tightRange && ctx.nearRangeLow && smallSignalBar &&
                             BarDirection(entry[0]) > 0);
   ctx.tightRangeBearFade = (ctx.tightRange && ctx.nearRangeHigh && smallSignalBar &&
                             BarDirection(entry[0]) < 0);
   ctx.high1 = (ctx.highBarCount == 1);
   ctx.high2 = (ctx.highBarCount == 2 &&
                ((ctx.trend > 0 && entry[0].close >= ctx.ma) || ctx.nearRangeLow));
   ctx.high3 = (ctx.highBarCount == 3);
   ctx.high4 = (ctx.highBarCount == 4);
   ctx.low1 = (ctx.lowBarCount == 1);
   ctx.low2 = (ctx.lowBarCount == 2 &&
               ((ctx.trend < 0 && entry[0].close <= ctx.ma) || ctx.nearRangeHigh));
   ctx.low3 = (ctx.lowBarCount == 3);
   ctx.low4 = (ctx.lowBarCount == 4);
   ctx.abcBullCorrection = (ctx.abcBullCorrection && ctx.trend > 0 && ctx.high2);
   ctx.abcBearCorrection = (ctx.abcBearCorrection && ctx.trend < 0 && ctx.low2);
   ctx.sessionOK = InConfiguredSession(entry[0].time);
   double oldHigh, oldLow;
   GetRangeBounds(entry, 5, MinInt(10, ArraySize(entry)-5), oldHigh, oldLow);
   double leg = MaxDouble(oldHigh-oldLow, ctx.atrLike);
   ctx.measuredMoveUp = entry[0].close + leg;
   ctx.measuredMoveDown = entry[0].close - leg;
   if(ctx.gapUp) ctx.measuredMoveUp = entry[0].close + (entry[0].low-entry[1].high);
   if(ctx.gapDown) ctx.measuredMoveDown = entry[0].close - (entry[1].low-entry[0].high);
   FindMagnets(entry, ctx);
   double bullLineSlope = 0.0, bearLineSlope = 0.0;
   bool hasBullSupportLine = FitRecentPivotTrendLine(entry, true, 100,
                                                      ctx.bullTrendLineNow, bullLineSlope);
   bool hasBearResistanceLine = FitRecentPivotTrendLine(entry, false, 100,
                                                         ctx.bearTrendLineNow, bearLineSlope);
   double priorBullLine = ctx.bullTrendLineNow - bullLineSlope;
   double priorBearLine = ctx.bearTrendLineNow - bearLineSlope;
   ctx.reversalLineBreakDown = (ctx.trend > 0 && hasBullSupportLine &&
                                BarDirection(entry[0]) < 0 &&
                                BodyShare(entry[0]) >= StrongBodyShare &&
                                entry[1].close >= priorBullLine &&
                                entry[0].close < ctx.bullTrendLineNow);
   ctx.reversalLineBreakUp = (ctx.trend < 0 && hasBearResistanceLine &&
                              BarDirection(entry[0]) > 0 &&
                              BodyShare(entry[0]) >= StrongBodyShare &&
                              entry[1].close <= priorBearLine &&
                              entry[0].close > ctx.bearTrendLineNow);
   ctx.channelOvershootReversalUp = (ctx.channelOvershootReversalUp ||
                                     (ctx.trend < 0 && ctx.wedgeDown &&
                                      ctx.failedBreakoutDown && BarDirection(entry[0]) > 0));
   ctx.channelOvershootReversalDown = (ctx.channelOvershootReversalDown ||
                                       (ctx.trend > 0 && ctx.wedgeUp &&
                                        ctx.failedBreakoutUp && BarDirection(entry[0]) < 0));
   ctx.duelingLines = (ctx.atrLike > 0.0 && hasBullSupportLine && hasBearResistanceLine &&
                       MathAbs(ctx.bullTrendLineNow - ctx.bearTrendLineNow) <= ctx.atrLike * 0.50 &&
                       MathAbs(entry[0].close - ctx.bullTrendLineNow) <= ctx.atrLike * 0.50 &&
                       MathAbs(entry[0].close - ctx.bearTrendLineNow) <= ctx.atrLike * 0.50);
}

int CountReasonGroups(const SContext &ctx, const int direction)
{
   int groups = 0;
   bool trendAligned = (direction > 0 ? ctx.trend > 0 : ctx.trend < 0);
   bool rangeLocation = (direction > 0 ? ctx.nearRangeLow : ctx.nearRangeHigh);
   bool patternGroup = (direction > 0 ? (ctx.strongBreakoutUp || ctx.followThroughUp ||
                                        ctx.failedBreakoutDown || ctx.breakoutPullbackUp ||
                                        ctx.high1 || ctx.high2 || ctx.high3 || ctx.high4 ||
                                        ctx.wedgeDown || ctx.doubleBottom ||
                                        ctx.headShouldersBottom || ctx.firstMAGapUp ||
                                        ctx.tightRangeBullFade)
                                      : (ctx.strongBreakoutDown || ctx.followThroughDown ||
                                        ctx.failedBreakoutUp || ctx.breakoutPullbackDown ||
                                        ctx.low1 || ctx.low2 || ctx.low3 || ctx.low4 ||
                                        ctx.wedgeUp || ctx.doubleTop ||
                                        ctx.headShouldersTop || ctx.firstMAGapDown ||
                                        ctx.tightRangeBearFade));
   // A magnet is primarily a target; do not count it as a second reason by itself.
   bool contextGroup = (trendAligned || rangeLocation);
   bool independentTimeGroup = ctx.sessionOK && UseSessionFilter;
   bool volatilityGroup = (direction > 0 ? ctx.twentyGapUp : ctx.twentyGapDown) ||
                          ctx.triangle || ctx.duelingLines ||
                          (direction > 0 ? (ctx.reversalLineBreakUp || ctx.channelOvershootReversalUp) :
                                           (ctx.reversalLineBreakDown || ctx.channelOvershootReversalDown));
   if(patternGroup) groups++;
   if(contextGroup) groups++;
   if(independentTimeGroup) groups++;
   if(volatilityGroup) groups++;
   return groups;
}

bool IsBullishCandidate(const SContext &ctx)
{
   bool candidate = (ctx.strongBreakoutUp || ctx.followThroughUp || ctx.failedBreakoutDown ||
                     ctx.breakoutPullbackUp ||
                     ctx.high1 || ctx.high2 || ctx.high3 || ctx.high4 || ctx.wedgeDown ||
                     ctx.doubleBottom || ctx.headShouldersBottom || ctx.firstMAGapUp ||
                     ctx.tightRangeBullFade);
   if(ctx.trend < 0 && !ctx.failedBreakoutDown && !ctx.wedgeDown && !ctx.doubleBottom && !ctx.headShouldersBottom)
      return false;
   return candidate;
}

bool IsBearishCandidate(const SContext &ctx)
{
   bool candidate = (ctx.strongBreakoutDown || ctx.followThroughDown || ctx.failedBreakoutUp ||
                     ctx.breakoutPullbackDown ||
                     ctx.low1 || ctx.low2 || ctx.low3 || ctx.low4 || ctx.wedgeUp ||
                     ctx.doubleTop || ctx.headShouldersTop || ctx.firstMAGapDown ||
                     ctx.tightRangeBearFade);
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
   setup.usePartialExit = false;
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
   bool tightRangeAllowed = (direction > 0 ?
                             (ctx.tightRangeFailedBreakoutDown || ctx.tightRangeBullFade) :
                             (ctx.tightRangeFailedBreakoutUp || ctx.tightRangeBearFade));
   if(ctx.tightRange && !AllowTightRangeSignals && !tightRangeAllowed)
   {
      setup.label = "SKIP tight range; wait for failed breakout or small edge fade";
      return false;
   }
   bool countertrendReversalConfirmed = (direction > 0 ?
      (ctx.reversalLineBreakUp || ctx.channelOvershootReversalUp) :
      (ctx.reversalLineBreakDown || ctx.channelOvershootReversalDown));
   if(ctx.steepTrend && direction != ctx.trend && !countertrendReversalConfirmed)
   {
      setup.label = "SKIP countertrend; steep trend needs line break or overshoot reversal";
      return false;
   }
   setup.reasonGroups = CountReasonGroups(ctx, direction);
   setup.isRangeSetup = ((ctx.range || ctx.tightRange) &&
                         (ctx.high2 || ctx.low2 || ctx.failedBreakoutUp ||
                          ctx.failedBreakoutDown || ctx.tightRangeBullFade ||
                          ctx.tightRangeBearFade));
   bool strongDirectionalTrend = (ctx.trend == direction && !ctx.range &&
      !ctx.tightRange && (ctx.steepTrend ||
      (direction > 0 ? (ctx.strongBreakoutUp && ctx.followThroughUp)
                     : (ctx.strongBreakoutDown && ctx.followThroughDown))));
   setup.usePartialExit = (EnablePartialExit && strongDirectionalTrend);
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
   if(setup.expectedValue <= MinimumExpectedValuePoints)
   {
      setup.label = "SKIP expected value " + DoubleToString(setup.expectedValue, 1) +
                    " points <= minimum " + DoubleToString(MinimumExpectedValuePoints, 1);
      return false;
   }
   setup.label = (direction > 0 ? "BUY" : "SELL");
   if(ctx.breakoutPullbackUp || ctx.breakoutPullbackDown) setup.label += " breakout-test";
   else if(ctx.failedBreakoutUp || ctx.failedBreakoutDown) setup.label += " failed-breakout";
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

double CalculateRiskVolume(const int direction, const double entry, const double stop,
                           const double riskMultiplier)
{
   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * RiskPercent / 100.0 *
                      riskMultiplier;
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

bool TryPendingOppositeSignalExit(const ulong ticket)
{
   string requestKey = "BAI2_OPPOSITE_EXIT_" + (string)ticket;
   string retryKey = "BAI2_OPPOSITE_EXIT_RETRY_" + (string)ticket;
   if(!GlobalVariableCheck(requestKey)) return false;
   if(!PositionSelectByTicket(ticket) ||
      PositionGetString(POSITION_SYMBOL) != _Symbol ||
      (ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
   {
      GlobalVariableDel(requestKey);
      if(GlobalVariableCheck(retryKey)) GlobalVariableDel(retryKey);
      return true;
   }
   if(GlobalVariableCheck(retryKey) && TimeCurrent() < (datetime)GlobalVariableGet(retryKey))
      return false;

   bool sent = trade.PositionClose(ticket);
   if(sent && TradeResultSucceeded())
   {
      GlobalVariableDel(requestKey);
      if(GlobalVariableCheck(retryKey)) GlobalVariableDel(retryKey);
      Print("POSITION EXIT: qualified opposite-direction setup.");
      return true;
   }
   GlobalVariableSet(retryKey, (double)(TimeCurrent() + 5));
   Print("OPPOSITE-SIGNAL EXIT REJECTED; retry in 5 seconds: ",
         trade.ResultRetcode(), " | ", trade.ResultRetcodeDescription());
   return false;
}

bool CloseManagedPositionPartial(const ulong ticket, const long type,
                                 const double closeVolume)
{
   if(closeVolume <= 0.0 || !PositionSelectByTicket(ticket)) return false;
   double currentVolume = PositionGetDouble(POSITION_VOLUME);
   if(closeVolume >= currentVolume) return false;

   ENUM_ACCOUNT_MARGIN_MODE marginMode =
      (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   bool sent = false;
   if(marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      sent = trade.PositionClosePartial(ticket, closeVolume);
   else if(type == POSITION_TYPE_BUY)
      sent = trade.Sell(closeVolume, _Symbol, 0.0, 0.0, 0.0,
                        "BootAI V2 scale out");
   else
      sent = trade.Buy(closeVolume, _Symbol, 0.0, 0.0, 0.0,
                       "BootAI V2 scale out");

   if(!sent || !TradeResultSucceeded())
   {
      Print("PARTIAL EXIT REJECTED: ticket=", ticket, " | ",
            trade.ResultRetcode(), " | ", trade.ResultRetcodeDescription());
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

bool CancelInvalidatedPendingOrders()
{
   bool allCleared = true;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol ||
         (ulong)OrderGetInteger(ORDER_MAGIC) != MagicNumber) continue;

      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      double invalidation = OrderGetDouble(ORDER_SL);
      if(invalidation <= 0.0) continue;
      bool invalidated = ((type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_LIMIT ||
                           type == ORDER_TYPE_BUY_STOP_LIMIT) && bid <= invalidation) ||
                         ((type == ORDER_TYPE_SELL_STOP || type == ORDER_TYPE_SELL_LIMIT ||
                           type == ORDER_TYPE_SELL_STOP_LIMIT) && ask >= invalidation);
      if(!invalidated) continue;

      bool sent = trade.OrderDelete(ticket);
      if(!sent || !TradeResultSucceeded())
      {
         allCleared = false;
         Print("INVALIDATED PENDING ORDER CANCEL REJECTED: ticket=", ticket,
               " | ", trade.ResultRetcode(), " | ", trade.ResultRetcodeDescription());
      }
      else
         Print("PENDING ORDER CANCELLED: invalidation level was reached | ticket=", ticket);
   }
   return allCleared;
}

int ConfiguredMaxHoldingBars();

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

   double riskMultiplier = (setup.useLimit ? LimitEntryRiskMultiplier : 1.0);
   double volume = CalculateRiskVolume(setup.direction, setup.entry, setup.stop,
                                       riskMultiplier);
   if(volume <= 0.0)
   {
      Print("ORDER SKIPPED: Calculated size is below the broker minimum or risk calculation failed.");
      return false;
   }
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints((ulong)SlippagePointsEstimate);
   trade.SetTypeFillingBySymbol(_Symbol);
   datetime expiry = TimeTradeServer() + PeriodSeconds(EntryTF) * 2;
   double orderTarget = (setup.usePartialExit ? 0.0 : setup.target);
   bool sent = false;
   if(setup.direction > 0 && setup.useLimit)
      sent = trade.BuyLimit(volume, setup.entry, _Symbol, setup.stop, orderTarget,
                            ORDER_TIME_SPECIFIED, expiry, "BootAI V2 range limit");
   else if(setup.direction < 0 && setup.useLimit)
      sent = trade.SellLimit(volume, setup.entry, _Symbol, setup.stop, orderTarget,
                             ORDER_TIME_SPECIFIED, expiry, "BootAI V2 range limit");
   else if(setup.direction > 0)
      sent = trade.BuyStop(volume, setup.entry, _Symbol, setup.stop, orderTarget,
                           ORDER_TIME_SPECIFIED, expiry, "BootAI V2 stop entry");
   else
      sent = trade.SellStop(volume, setup.entry, _Symbol, setup.stop, orderTarget,
                            ORDER_TIME_SPECIFIED, expiry, "BootAI V2 stop entry");

   if(!sent || !TradeResultSucceeded())
   {
      Print("ORDER REJECTED: ", trade.ResultRetcode(), " | ", trade.ResultRetcodeDescription());
      return false;
   }
   ulong orderTicket = trade.ResultOrder();
   int lockedHorizon = ConfiguredMaxHoldingBars();
   if(orderTicket > 0 && lockedHorizon > 0)
      GlobalVariableSet("BAI2_ORDER_HORIZON_" + (string)orderTicket,
                        (double)lockedHorizon);
   if(orderTicket > 0)
      GlobalVariableSet("BAI2_ORDER_PARTIAL_" + (string)orderTicket,
                        (setup.usePartialExit ? 1.0 : 0.0));
   Print("PENDING ORDER: ", setup.label, " | volume=", DoubleToString(volume, 2),
         " | entry=", DoubleToString(setup.entry, _Digits),
         " | stop=", DoubleToString(setup.stop, _Digits),
         " | target=", DoubleToString(setup.target, _Digits),
         " | exit plan=", (setup.usePartialExit ? "staged trend exits" : "fixed candidate target"),
         " | evidence groups=", setup.reasonGroups,
         " | estimated EV points=", DoubleToString(setup.expectedValue, 1));
   return true;
}

int ConfiguredMaxHoldingBars()
{
   if(TradeStyle == STYLE_SCALP) return MaxBarsForScalp;
   if(TradeStyle == STYLE_INTRADAY_SWING) return MaxBarsForIntraday;
   if(TradeStyle == STYLE_SWING) return MaxBarsForSwing;
   return 0;
}

int LockedMaxHoldingBars(const ulong ticket)
{
   string styleKey = "BAI2_HORIZON_" + (string)ticket;
   if(GlobalVariableCheck(styleKey))
      return (int)GlobalVariableGet(styleKey);

   int maxBars = ConfiguredMaxHoldingBars();
   if(maxBars > 0) GlobalVariableSet(styleKey, (double)maxBars);
   return maxBars;
}

bool FindRecentConfirmedSwing(const MqlRates &rates[], const bool findHigh,
                              const int lookbackBars, double &swingPrice)
{
   swingPrice = 0.0;
   int lastShift = MinInt(lookbackBars, ArraySize(rates) - 2);
   if(lastShift < 2) return false;

   // Rates are series: index 0 is newest. Shift 2 is the newest pivot that
   // has at least one newer and one older closed bar confirming it.
   for(int i = 2; i <= lastShift; i++)
   {
      if(findHigh)
      {
         if(rates[i].high >= rates[i-1].high && rates[i].high > rates[i+1].high)
         {
            swingPrice = rates[i].high;
            return true;
         }
      }
      else if(rates[i].low <= rates[i-1].low && rates[i].low < rates[i+1].low)
      {
         swingPrice = rates[i].low;
         return true;
      }
   }
   return false;
}

void ManageOpenPosition(const MqlRates &rates[])
{
   ulong ticket = FindManagedPositionTicket();
   if(ticket == 0 || !PositionSelectByTicket(ticket)) return;
   if(ticket != g_partialExitRetryTicket)
   {
      g_partialExitRetryTicket = ticket;
      g_partialExitRetryAfter = 0;
   }
   if(ticket != g_entryStopRetryTicket)
   {
      g_entryStopRetryTicket = ticket;
      g_entryStopRetryAfter = 0;
   }
   long type = PositionGetInteger(POSITION_TYPE);
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double stop = PositionGetDouble(POSITION_SL);
   double target = PositionGetDouble(POSITION_TP);
   double volume = PositionGetDouble(POSITION_VOLUME);
   datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
   string partialKey1 = "BAI2_PART1_" + (string)ticket;
   string partialKey2 = "BAI2_PART2_" + (string)ticket;
   string riskKey = "BAI2_RISK_" + (string)ticket;
   string initialVolumeKey = "BAI2_INITIAL_VOLUME_" + (string)ticket;
   string partialModeKey = "BAI2_PARTIAL_MODE_" + (string)ticket;
   bool partialMode = (GlobalVariableCheck(partialModeKey) &&
                       GlobalVariableGet(partialModeKey) > 0.5);

   int maxBars = LockedMaxHoldingBars(ticket);
   int heldBars = iBarShift(_Symbol, EntryTF, opened, false);
   if(heldBars >= maxBars && maxBars > 0)
   {
      bool closed = trade.PositionClose(ticket);
      if(closed && TradeResultSucceeded()) Print("TIME EXIT: configured holding window reached.");
      else Print("TIME EXIT REJECTED: ", trade.ResultRetcode(), " | ", trade.ResultRetcodeDescription());
      return;
   }

   if(GlobalVariableCheck("BAI2_OPPOSITE_EXIT_" + (string)ticket))
   {
      TryPendingOppositeSignalExit(ticket);
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
   double initialVolume = volume;
   if(GlobalVariableCheck(initialVolumeKey))
      initialVolume = GlobalVariableGet(initialVolumeKey);
   else
      GlobalVariableSet(initialVolumeKey, initialVolume);

   double mark = (type == POSITION_TYPE_BUY ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                             : SymbolInfoDouble(_Symbol, SYMBOL_ASK));
   double favorable = (type == POSITION_TYPE_BUY ? mark-open : open-mark);
   string entryStopKey = "BAI2_ENTRY_BAR_STOP_" + (string)ticket;
   if(TightenStopAfterStrongEntryBar && heldBars == 1 && ArraySize(rates) > 0 &&
      rates[0].time == iTime(_Symbol, EntryTF, 1) &&
      !GlobalVariableCheck(entryStopKey) && TimeCurrent() >= g_entryStopRetryAfter)
   {
      int positionDirection = (type == POSITION_TYPE_BUY ? 1 : -1);
      bool strongEntryBar = (BarDirection(rates[0]) == positionDirection &&
                             BodyShare(rates[0]) >= StrongBodyShare &&
                             (positionDirection > 0 ?
                              rates[0].close >= rates[0].high - 0.20 * BarRange(rates[0]) :
                              rates[0].close <= rates[0].low + 0.20 * BarRange(rates[0])));
      if(!strongEntryBar)
      {
         GlobalVariableSet(entryStopKey, 1.0);
         Print("ENTRY BAR STOP: original protective stop retained; entry bar was not a strong directional bar.");
      }
      else
      {
         double offset = TickSize() * StrongEntryBarStopOffsetTicks;
         double candidate = NormalizePrice(positionDirection > 0 ?
                             rates[0].low - offset : rates[0].high + offset);
         bool tighter = (positionDirection > 0 ?
                         (stop == 0.0 || candidate > stop) :
                         (stop == 0.0 || candidate < stop));
         double minStopDistance = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
         bool validDistance = (positionDirection > 0 ?
                               candidate < mark - minStopDistance :
                               candidate > mark + minStopDistance);
         if(!tighter)
         {
            GlobalVariableSet(entryStopKey, 1.0);
            Print("ENTRY BAR STOP: original stop retained; candidate would not tighten risk.");
         }
         else if(!validDistance)
         {
            GlobalVariableSet(entryStopKey, 1.0);
            Print("ENTRY BAR STOP: original stop retained; broker stop-distance would be violated.");
         }
         else if(ModifyManagedPosition(ticket, candidate, target))
         {
            stop = candidate;
            GlobalVariableSet(entryStopKey, 1.0);
            Print("ENTRY BAR STOP TIGHTENED: strong entry bar; offset ticks=",
                  StrongEntryBarStopOffsetTicks, ".");
         }
         else
            g_entryStopRetryAfter = TimeCurrent() + 5;
      }
   }
   if(partialMode && TimeCurrent() >= g_partialExitRetryAfter &&
      favorable >= initialRisk * PartialExitAtR1 &&
      !GlobalVariableCheck(partialKey1))
   {
      double closeVolume = NormalizeVolumeDown(initialVolume * PartialExitPercent1 / 100.0);
      if(closeVolume <= 0.0)
      {
         GlobalVariableSet(partialKey1, 1.0);
         Print("PARTIAL EXIT 1 SKIPPED: calculated volume is below broker minimum.");
      }
      else if(!PositionSelectByTicket(ticket) ||
              closeVolume >= PositionGetDouble(POSITION_VOLUME))
      {
         GlobalVariableSet(partialKey1, 1.0);
         Print("PARTIAL EXIT 1 SKIPPED: tranche would close the full remaining position.");
      }
      else if(CloseManagedPositionPartial(ticket, type, closeVolume))
      {
         g_partialExitRetryAfter = 0;
         GlobalVariableSet(partialKey1, 1.0);
         Print("PARTIAL EXIT 1: closed ", DoubleToString(closeVolume, 2),
               " lots at approximately ", DoubleToString(PartialExitAtR1, 2), "R.");
      }
      else
         g_partialExitRetryAfter = TimeCurrent() + 5;
   }

   if(partialMode && TimeCurrent() >= g_partialExitRetryAfter &&
      favorable >= initialRisk * PartialExitAtR2 &&
      !GlobalVariableCheck(partialKey2))
   {
      double closeVolume = NormalizeVolumeDown(initialVolume * PartialExitPercent2 / 100.0);
      if(closeVolume <= 0.0)
      {
         GlobalVariableSet(partialKey2, 1.0);
         Print("PARTIAL EXIT 2 SKIPPED: calculated volume is below broker minimum.");
      }
      else if(!PositionSelectByTicket(ticket) ||
              closeVolume >= PositionGetDouble(POSITION_VOLUME))
      {
         GlobalVariableSet(partialKey2, 1.0);
         Print("PARTIAL EXIT 2 SKIPPED: tranche would close the full remaining position.");
      }
      else if(CloseManagedPositionPartial(ticket, type, closeVolume))
      {
         g_partialExitRetryAfter = 0;
         GlobalVariableSet(partialKey2, 1.0);
         Print("PARTIAL EXIT 2: closed ", DoubleToString(closeVolume, 2),
               " lots at approximately ", DoubleToString(PartialExitAtR2, 2), "R.");
      }
      else
         g_partialExitRetryAfter = TimeCurrent() + 5;
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

   bool runnerStageReached = GlobalVariableCheck(partialKey2);
   bool trailRunner = (EnableSwingTrailingStop ||
                       (TrailRunnerAfterSecondPartial && partialMode && runnerStageReached));
   if(!trailRunner || ArraySize(rates) < 4) return;
   double candidate = stop;
   if(type == POSITION_TYPE_BUY)
   {
      double swingLow = 0.0;
      if(FindRecentConfirmedSwing(rates, false, SwingTrailLookbackBars, swingLow))
      {
         candidate = NormalizePrice(swingLow - TickSize());
         if(candidate > stop && candidate < mark)
            ModifyManagedPosition(ticket, candidate, target);
      }
   }
   else
   {
      double swingHigh = 0.0;
      if(FindRecentConfirmedSwing(rates, true, SwingTrailLookbackBars, swingHigh))
      {
         candidate = NormalizePrice(swingHigh + TickSize());
         if((stop == 0.0 || candidate < stop) && candidate > mark)
            ModifyManagedPosition(ticket, candidate, target);
      }
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
         " | breakout-test+", ctx.breakoutPullbackUp, "/-", ctx.breakoutPullbackDown,
         " (levels=", DoubleToString(ctx.breakoutTestLevelUp, _Digits), "/",
         DoubleToString(ctx.breakoutTestLevelDown, _Digits), ")",
         " | H-count=", ctx.highBarCount, " | L-count=", ctx.lowBarCount,
         " | ABC bull/bear=", ctx.abcBullCorrection, "/", ctx.abcBearCorrection,
         " | wedge=", ctx.wedgeDown, "/", ctx.wedgeUp,
         " | DT/DB=", ctx.doubleTop, "/", ctx.doubleBottom,
         " | MA20-gap=", ctx.twentyGapUp, "/", ctx.twentyGapDown,
         " | prior-failed-reversal-magnet=", ctx.priorFailureMagnet,
         " (above=", DoubleToString(ctx.failedBullReversalTarget, _Digits),
         ", below=", DoubleToString(ctx.failedBearReversalTarget, _Digits), ")",
         " | dueling-lines=", ctx.duelingLines,
         " (bull=", DoubleToString(ctx.bullTrendLineNow, _Digits),
         ", bear=", DoubleToString(ctx.bearTrendLineNow, _Digits), ")",
         " | steep-trend=", ctx.steepTrend,
         " | trendline-break-up/down=", ctx.reversalLineBreakUp, "/", ctx.reversalLineBreakDown,
         " | channel-overshoot-reversal-up/down=", ctx.channelOvershootReversalUp, "/",
         ctx.channelOvershootReversalDown,
         " | tight-range-fade-up/down=", ctx.tightRangeBullFade, "/", ctx.tightRangeBearFade,
         " | session=", ctx.sessionOK);
   if(hasSetup)
      Print("CANDIDATE | ", setup.label, " | evidence groups=", setup.reasonGroups,
            " | entry=", DoubleToString(setup.entry, _Digits),
            " | stop=", DoubleToString(setup.stop, _Digits),
            " | target=", DoubleToString(setup.target, _Digits),
            " | EV points=", DoubleToString(setup.expectedValue, 1),
            " | order=", (setup.useLimit ? "LIMIT" : "STOP"));
   else
   {
      if(StringFind(setup.label, "SKIP ") == 0)
         Print("NO TRADE | ", setup.label);
      else
         Print("NO QUALIFIED SETUP | screening only; no order requested.");
   }
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
      MinimumExpectedValuePoints < 0.0 ||
      MinReasonGroups > 4 || CommissionPerLotRoundTurn < 0.0 || SlippagePointsEstimate < 0 ||
      RangeOverlapThreshold < 0.0 || RangeOverlapThreshold > 1.0 ||
      SteepTrendDisplacementATR < 0.5 || SteepTrendDisplacementATR > 5.0 ||
      SmallBarRangeATR <= 0.0 || SmallBarRangeATR > 2.0 ||
      MaxBarsForScalp < 1 || MaxBarsForIntraday < 1 || MaxBarsForSwing < 1 ||
      LimitEntryRiskMultiplier <= 0.0 || LimitEntryRiskMultiplier > 1.0 ||
      PartialExitAtR1 <= 0.0 || PartialExitAtR2 <= PartialExitAtR1 ||
      PartialExitPercent1 <= 0.0 || PartialExitPercent1 >= 100.0 ||
      PartialExitPercent2 <= 0.0 ||
      PartialExitPercent1 + PartialExitPercent2 >= 100.0 ||
      SwingTrailLookbackBars < 2 || SwingTrailLookbackBars > BarsToRead - 2 ||
      RangeEdgePercent <= 0.0 || RangeEdgePercent >= 50.0 ||
      StrongBodyShare < 0.0 || StrongBodyShare > 1.0 ||
      StrongEntryBarStopOffsetTicks < 1 || StrongEntryBarStopOffsetTicks > 2 ||
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
   Print("Boot AI V2 started. Execution=", (EnableTradeExecution ? "ON" : "OFF"),
         " | demo-only execution | scale-in=disabled.");
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(!EnableTradeExecution)
      CancelManagedPendingOrders();
   else
      CancelInvalidatedPendingOrders();

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
   if(HasManagedPosition()) ManageOpenPosition(entry);
   if(currentBar == g_lastEntryBar) return;
   g_lastEntryBar = currentBar;

   SContext ctx;
   AnalyzeContext(entry, trend, ctx);
   SSetup setup;
   bool hasSetup = BuildSetup(ctx, entry, setup);
   PrintContext(ctx, setup, hasSetup);
   if(ExitOnQualifiedOppositeSignal && hasSetup && HasManagedPosition())
   {
      ulong ticket = FindManagedPositionTicket();
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         long positionType = PositionGetInteger(POSITION_TYPE);
         bool isOpposite = ((positionType == POSITION_TYPE_BUY && setup.direction < 0) ||
                            (positionType == POSITION_TYPE_SELL && setup.direction > 0));
         if(isOpposite)
         {
            GlobalVariableSet("BAI2_OPPOSITE_EXIT_" + (string)ticket, 1.0);
            TryPendingOppositeSignalExit(ticket);
            return;
         }
      }
   }
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
   if(HistoryDealSelect(trans.deal) && trans.symbol == _Symbol &&
      (ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) == MagicNumber &&
      (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
   {
      ulong orderTicket = (ulong)HistoryDealGetInteger(trans.deal, DEAL_ORDER);
      string orderHorizonKey = "BAI2_ORDER_HORIZON_" + (string)orderTicket;
      string orderPartialKey = "BAI2_ORDER_PARTIAL_" + (string)orderTicket;
      double partialMode = (GlobalVariableCheck(orderPartialKey) ?
                            GlobalVariableGet(orderPartialKey) : 0.0);
      if(GlobalVariableCheck(orderHorizonKey))
      {
         double lockedHorizon = GlobalVariableGet(orderHorizonKey);
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong positionTicket = PositionGetTicket(i);
            if(positionTicket == 0) continue;
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               (ulong)PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
               GlobalVariableSet("BAI2_HORIZON_" + (string)positionTicket,
                                 lockedHorizon);
               GlobalVariableSet("BAI2_PARTIAL_MODE_" + (string)positionTicket,
                                 partialMode);
            }
         }
      }
      else
      {
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong positionTicket = PositionGetTicket(i);
            if(positionTicket > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol &&
               (ulong)PositionGetInteger(POSITION_MAGIC) == MagicNumber)
               GlobalVariableSet("BAI2_PARTIAL_MODE_" + (string)positionTicket,
                                 partialMode);
         }
      }
      if(GlobalVariableCheck(orderPartialKey)) GlobalVariableDel(orderPartialKey);
   }
   if(HasManagedPosition()) CancelManagedPendingOrders();
}

void OnDeinit(const int reason)
{
   Print("Boot AI V2 stopped. Reason=", reason);
}
