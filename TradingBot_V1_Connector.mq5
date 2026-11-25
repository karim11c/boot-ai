
#property strict
#property version   "1.000"
#property description "Trading Bot V1 - Historical Data and Trend Analysis"

input ENUM_TIMEFRAMES EntryTF = PERIOD_M15;
input ENUM_TIMEFRAMES TrendTF = PERIOD_H1;

input int CandlesToRead = 20;
input int RetrySeconds = 10;

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

   Print("Trading Bot V1.001 Started");
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
}

// Shutdown
void OnDeinit(const int reason)
{
   EventKillTimer();

   Print("Trading Bot V1.001 Stopped.");
}
