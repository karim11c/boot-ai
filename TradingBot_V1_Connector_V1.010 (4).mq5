
#property strict
#property version   "1.010"
#property description "Trading Bot V1 - Historical Data and Trend Analysis"

input ENUM_TIMEFRAMES EntryTF = PERIOD_M15;
input ENUM_TIMEFRAMES TrendTF = PERIOD_H1;

input int CandlesToRead = 20;
input int RetrySeconds = 10;

// Price-action research settings. These are transparent implementation
// heuristics, not numeric rules stated by Al Brooks.
input int PA_LookbackBars = 10;
input int PA_MinDirectionChanges = 4;
input int PA_MinOverlappingBars = 5;
input double PA_RangeEdgePercent = 25.0;

datetime lastBar = 0;
bool historyReady = false;

// Print historical candles
void PrintCandles(MqlRates &rates[], ENUM_TIMEFRAMES tf)
{
   Print("========== ", EnumToString(tf),
         " - LAST ", CandlesToRead, " CLOSED CANDLES ==========");

   for(int i = CandlesToRead - 1; i >= 0; i--)
   {
      Print(EnumToString(tf),
            " | ", TimeToString(rates[i].time),
            " | O: ", DoubleToString(rates[i].open, _Digits),
            " | H: ", DoubleToString(rates[i].high, _Digits),
            " | L: ", DoubleToString(rates[i].low, _Digits),
            " | C: ", DoubleToString(rates[i].close, _Digits),
            " | Tick Volume: ", rates[i].tick_volume);
   }
}

// Analyze market trend using price structure
void AnalyzeH1Trend(MqlRates &rates[])
{
   double recentHigh = rates[0].high;
   double recentLow  = rates[0].low;

   double previousHigh = rates[5].high;
   double previousLow  = rates[5].low;

   // Last 5 closed candles
   for(int i = 1; i < 5; i++)
   {
      if(rates[i].high > recentHigh)
         recentHigh = rates[i].high;

      if(rates[i].low < recentLow)
         recentLow = rates[i].low;
   }

   // Previous 5 closed candles
   for(int i = 6; i < 10; i++)
   {
      if(rates[i].high > previousHigh)
         previousHigh = rates[i].high;

      if(rates[i].low < previousLow)
         previousLow = rates[i].low;
   }

   string trend = "UNCLEAR";
   string reason = "Mixed price structure";

   if(recentHigh > previousHigh &&
      recentLow > previousLow)
   {
      trend = "BULLISH";
      reason = "Higher High and Higher Low";
   }
   else if(recentHigh < previousHigh &&
           recentLow < previousLow)
   {
      trend = "BEARISH";
      reason = "Lower High and Lower Low";
   }
   else if(recentHigh <= previousHigh &&
           recentLow >= previousLow)
   {
      trend = "RANGE";
      reason = "Recent price movement is inside previous range";
   }

   Print("========== H1 TREND ANALYSIS ==========");
   Print("Symbol: ", _Symbol);
   Print("Trend: ", trend);
   Print("Reason: ", reason);

   Print("Recent High: ", DoubleToString(recentHigh, _Digits));
   Print("Recent Low: ", DoubleToString(recentLow, _Digits));

   Print("Previous High: ", DoubleToString(previousHigh, _Digits));
   Print("Previous Low: ", DoubleToString(previousLow, _Digits));

   Print("=======================================");
   Print("STATUS: ANALYSIS ONLY - NO TRADE EXECUTION");
}

// Return the sign of a candle body: 1 bull, -1 bear, 0 doji.
int CandleDirection(const MqlRates &bar)
{
   if(bar.close > bar.open) return 1;
   if(bar.close < bar.open) return -1;
   return 0;
}

// Approximate two-sided/range context from overlap and alternating candle bodies.
// The book describes these as contextual clues; the numeric thresholds below
// are engineering heuristics and must be validated on historical data.
void AnalyzeEntryPriceAction(MqlRates &rates[])
{
   int n = PA_LookbackBars;
   if(n < 6) n = 6;
   if(n > ArraySize(rates) - 2) n = ArraySize(rates) - 2;

   double rangeHigh = rates[1].high;
   double rangeLow  = rates[1].low;
   int directionChanges = 0;
   int overlaps = 0;
   int previousDirection = 0;

   for(int i = 1; i <= n; i++)
   {
      if(rates[i].high > rangeHigh) rangeHigh = rates[i].high;
      if(rates[i].low < rangeLow) rangeLow = rates[i].low;

      int direction = CandleDirection(rates[i]);
      if(direction != 0)
      {
         if(previousDirection != 0 && direction != previousDirection)
            directionChanges++;
         previousDirection = direction;
      }

      if(i < n)
      {
         double overlapHigh = MathMin(rates[i].high, rates[i+1].high);
         double overlapLow  = MathMax(rates[i].low, rates[i+1].low);
         if(overlapHigh > overlapLow)
            overlaps++;
      }
   }

   bool isRange = (directionChanges >= PA_MinDirectionChanges &&
                   overlaps >= PA_MinOverlappingBars);

   double width = rangeHigh - rangeLow;
   double edge = width * PA_RangeEdgePercent / 100.0;
   string location = "MIDDLE";
   if(width > 0.0)
   {
      if(rates[1].close <= rangeLow + edge) location = "NEAR RANGE LOW";
      else if(rates[1].close >= rangeHigh - edge) location = "NEAR RANGE HIGH";
   }

   // Failed breakout: a completed bar trades beyond the prior range boundary,
   // then closes back inside. The boundary excludes the two newest closed bars.
   double priorHigh = rates[3].high;
   double priorLow  = rates[3].low;
   for(int j = 4; j <= n; j++)
   {
      if(rates[j].high > priorHigh) priorHigh = rates[j].high;
      if(rates[j].low < priorLow) priorLow = rates[j].low;
   }
   bool failedBullBreakout = (rates[2].high > priorHigh && rates[1].close < priorHigh);
   bool failedBearBreakout = (rates[2].low < priorLow && rates[1].close > priorLow);

   // Approximate second-entry candidates: two local swing attempts near an
   // extreme, followed by a reversal signal bar. This is a screening label,
   // not a fully validated Brooks bar-counting implementation.
   int olderLowPivot = -1;
   int newerLowPivot = -1;
   int olderHighPivot = -1;
   int newerHighPivot = -1;
   for(int k = 2; k <= MathMin(7, n-1); k++)
   {
      if(rates[k].low <= rates[k-1].low && rates[k].low < rates[k+1].low)
      {
         if(newerLowPivot == -1) newerLowPivot = k;
         else if(olderLowPivot == -1) olderLowPivot = k;
      }
      if(rates[k].high >= rates[k-1].high && rates[k].high > rates[k+1].high)
      {
         if(newerHighPivot == -1) newerHighPivot = k;
         else if(olderHighPivot == -1) olderHighPivot = k;
      }
   }

   bool possibleHigh2 = false;
   bool possibleLow2 = false;
   if(isRange && width > 0.0 && olderLowPivot > newerLowPivot && newerLowPivot >= 2 &&
      rates[1].close > rates[1].open &&
      rates[1].close > rates[2].high &&
      rates[newerLowPivot].low <= rangeLow + edge)
      possibleHigh2 = true;

   if(isRange && width > 0.0 && olderHighPivot > newerHighPivot && newerHighPivot >= 2 &&
      rates[1].close < rates[1].open &&
      rates[1].close < rates[2].low &&
      rates[newerHighPivot].high >= rangeHigh - edge)
      possibleLow2 = true;

   Print("========== M15 PRICE ACTION ANALYSIS ==========");
   Print("Context: ", (isRange ? "POSSIBLE TRADING RANGE" : "NOT CONFIRMED AS RANGE"));
   Print("Heuristic evidence | Direction changes: ", directionChanges,
         " | Overlapping adjacent bars: ", overlaps,
         " | Lookback: ", n);
   Print("Range High: ", DoubleToString(rangeHigh, _Digits),
         " | Range Low: ", DoubleToString(rangeLow, _Digits),
         " | Close location: ", location);

   if(failedBullBreakout)
      Print("SETUP WATCH: Possible FAILED BULL BREAKOUT - prior bar traded above the reference high and the latest close returned below it.");
   if(failedBearBreakout)
      Print("SETUP WATCH: Possible FAILED BEAR BREAKOUT - prior bar traded below the reference low and the latest close returned above it.");
   if(possibleHigh2)
      Print("SETUP WATCH: Possible HIGH 2 bull reversal near range low. Confirmation/entry is not automatic.");
   if(possibleLow2)
      Print("SETUP WATCH: Possible LOW 2 bear reversal near range high. Confirmation/entry is not automatic.");
   if(!failedBullBreakout && !failedBearBreakout && !possibleHigh2 && !possibleLow2)
      Print("No qualified price-action setup from current screening rules.");

   Print("NOTE: Screening only; heuristic labels require historical validation. No orders are sent.");
   Print("================================================");
}

// Read historical market data
bool ReadMarketHistory()
{
   MqlRates entryRates[];
   MqlRates trendRates[];

   ArraySetAsSeries(entryRates, true);
   ArraySetAsSeries(trendRates, true);

   int entryCount = CopyRates(
      _Symbol, EntryTF, 1, CandlesToRead, entryRates
   );

   int trendCount = CopyRates(
      _Symbol, TrendTF, 1, CandlesToRead, trendRates
   );

   if(entryCount < CandlesToRead ||
      trendCount < CandlesToRead)
   {
      Print("WAIT: Historical data is not ready.");
      return false;
   }

   if(!historyReady)
   {
      Print("HISTORICAL MARKET DATA RECEIVED");

      PrintCandles(entryRates, EntryTF);
      PrintCandles(trendRates, TrendTF);

      Print("STATUS: HISTORICAL DATA READ SUCCESSFULLY");

      historyReady = true;
   }

   AnalyzeH1Trend(trendRates);
   AnalyzeEntryPriceAction(entryRates);

   return true;
}

// Initialization
int OnInit()
{
   long mode = AccountInfoInteger(ACCOUNT_TRADE_MODE);

   if(mode != ACCOUNT_TRADE_MODE_DEMO)
   {
      Print("SAFETY BLOCK: Demo account required.");
      return INIT_FAILED;
   }

   if(CandlesToRead < 10)
   {
      Print("ERROR: CandlesToRead must be at least 10.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(!SymbolSelect(_Symbol, true))
   {
      Print("ERROR: Cannot select symbol ", _Symbol);
      return INIT_FAILED;
   }

   Print("Trading Bot V1.010 Started");
   Print("Account: ", AccountInfoString(ACCOUNT_SERVER));
   Print("Symbol: ", _Symbol);
   Print("Entry timeframe: ", EnumToString(EntryTF));
   Print("Trend timeframe: ", EnumToString(TrendTF));

   EventSetTimer(RetrySeconds);

   ReadMarketHistory();

   lastBar = iTime(_Symbol, EntryTF, 0);

   return INIT_SUCCEEDED;
}

// Retry history reading while data is unavailable
void OnTimer()
{
   if(!historyReady)
      ReadMarketHistory();
}

// Update analysis when a new entry-timeframe candle starts
void OnTick()
{
   if(!historyReady)
      return;

   datetime currentBar = iTime(_Symbol, EntryTF, 0);

   if(currentBar == 0 || currentBar == lastBar)
      return;

   lastBar = currentBar;

   MqlRates trendRates[];
   ArraySetAsSeries(trendRates, true);

   int count = CopyRates(
      _Symbol, TrendTF, 1, CandlesToRead, trendRates
   );

   if(count < CandlesToRead)
   {
      Print("WAIT: Cannot update trend analysis.");
      return;
   }

   AnalyzeH1Trend(trendRates);

   MqlRates entryRates[];
   ArraySetAsSeries(entryRates, true);
   int entryCount = CopyRates(_Symbol, EntryTF, 1, CandlesToRead, entryRates);
   if(entryCount < CandlesToRead)
   {
      Print("WAIT: Cannot update entry-timeframe price action analysis.");
      return;
   }
   AnalyzeEntryPriceAction(entryRates);
}

// Shutdown
void OnDeinit(const int reason)
{
   EventKillTimer();

   Print("Trading Bot V1.010 Stopped.");
}
