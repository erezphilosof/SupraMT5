#include <Trade\Trade.mqh>
#include <Indicators\Indicators.mqh>

CTrade      trade;
int         wprHandle;
int         atrHandle;
double      atrExitLevel = 0;
datetime    shortEntryTime = 0;
datetime    lastClosedBarTime = 0;

//--- input parameters
input int    WPRPeriod           = 14;      // Period for Williams %R
input bool   NormalizeWPR        = false;   // false = raw (-100..0), true = normalized (0..100)
input double WPREntryThreshold   = -20.0;   // Entry threshold: if WPRVal > this, enter short
input double WPRExitThreshold    = -50.0;   // Exit threshold: if WPRVal < this, exit short
input int    ATRPeriod           = 14;      // Period for ATR
input double ATRMultiplier       = 2.0;     // Multiplier for ATR-based exit (price - ATR*multiplier)
input ENUM_TIMEFRAMES ATRTimeframe = PERIOD_CURRENT; // Timeframe for ATR exit calculation
input double Lots                = 0.1;     // Trade size
input int    Slippage            = 5;       // Slippage in points       // Slippage in points

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("WPR & ATR Short EA initialized on ", _Symbol);

   // Create Williams %R indicator
   wprHandle = iWPR(_Symbol, PERIOD_CURRENT, WPRPeriod);
   if(wprHandle == INVALID_HANDLE)
      return(INIT_FAILED);
   ChartIndicatorAdd(0, 1, wprHandle);

   // Create ATR indicator
   atrHandle = iATR(_Symbol, ATRTimeframe, ATRPeriod);
   if(atrHandle == INVALID_HANDLE)
      return(INIT_FAILED);

   // Plot entry threshold line
   const string entryLine = "WPR_Entry_Threshold";
   if(ObjectFind(0, entryLine) != -1) ObjectDelete(0, entryLine);
   double entryValue = NormalizeWPR ? -WPREntryThreshold : WPREntryThreshold;
   ObjectCreate(0, entryLine, OBJ_HLINE, 0, 0, entryValue);
   ObjectSetInteger(0, entryLine, OBJPROP_COLOR, clrGreen);
   ObjectSetInteger(0, entryLine, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, entryLine, OBJPROP_WIDTH, 1);

   // Plot exit threshold line
   const string exitLine = "WPR_Exit_Threshold";
   if(ObjectFind(0, exitLine) != -1) ObjectDelete(0, exitLine);
   double exitValue = NormalizeWPR ? -WPRExitThreshold : WPRExitThreshold;
   ObjectCreate(0, exitLine, OBJ_HLINE, 0, 0, exitValue);
   ObjectSetInteger(0, exitLine, OBJPROP_COLOR, clrRed);
   ObjectSetInteger(0, exitLine, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, exitLine, OBJPROP_WIDTH, 1);

   // Initialize last bar close time
   lastClosedBarTime = iTime(_Symbol, PERIOD_CURRENT, 1);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectDelete(0, "WPR_Entry_Threshold");
   ObjectDelete(0, "WPR_Exit_Threshold");
   ObjectDelete(0, "ATR_ExitLine");
}

//+------------------------------------------------------------------+
//| Expert tick function                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return;

   // Detect new bar close
   datetime closedTime = iTime(_Symbol, PERIOD_CURRENT, 1);
   if(closedTime == lastClosedBarTime) return;
   lastClosedBarTime = closedTime;

   // Read WPR at closed bar
   double bufWPR[1];
   if(CopyBuffer(wprHandle, 0, 1, 1, bufWPR) != 1) return;
   double wprRaw = bufWPR[0];
   double wprVal = NormalizeWPR ? -wprRaw : wprRaw;

   // Debug print
   PrintFormat("BarClose %s: WPR=%.2f (Entry=%.2f, Exit=%.2f)",
               TimeToString(closedTime, TIME_DATE|TIME_MINUTES),
               wprVal, WPREntryThreshold, WPRExitThreshold);

   // Entry logic: short when WPR > entry threshold
   if(wprVal > WPREntryThreshold && !HasPosition(POSITION_TYPE_SELL))
   {
      if(HasPosition(POSITION_TYPE_BUY)) trade.PositionClose(_Symbol);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      // Calculate ATR exit level: price - ATR*multiplier
      double bufATR[1];
      if(CopyBuffer(atrHandle, 0, 1, 1, bufATR) == 1)
      {
         double atrVal = bufATR[0];
         atrExitLevel = bid - atrVal * ATRMultiplier;
         // Draw ATR exit line
         const string atrLine = "ATR_ExitLine";
         if(ObjectFind(0, atrLine) != -1) ObjectDelete(0, atrLine);
         ObjectCreate(0, atrLine, OBJ_HLINE, 0, 0, atrExitLevel);
         ObjectSetInteger(0, atrLine, OBJPROP_COLOR, clrOrange);
         ObjectSetInteger(0, atrLine, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, atrLine, OBJPROP_WIDTH, 1);
      }
      if(trade.Sell(Lots, NULL, bid, Slippage))
      {
         shortEntryTime = TimeCurrent();
         Print("Reason: Entry_Short_WPR_BarClose");
         PrintFormat("Short opened at %.5f, ATR_exit=%.5f, ticket=%I64u", bid, atrExitLevel, trade.ResultOrder());
      }
   }

   // Exit logic: WPR-based
   if(HasPosition(POSITION_TYPE_SELL) && shortEntryTime > 0 && wprVal < WPRExitThreshold)
   {
      if(trade.PositionClose(_Symbol))
      {
         Print("Reason: Exit_Short_WPR_BarClose");
         PrintFormat("WPR=%.2f dropped below %.2f, closed short", wprVal, WPRExitThreshold);
      }
      atrExitLevel = 0;
      ObjectDelete(0, "ATR_ExitLine");
      shortEntryTime = 0;
   }

   // Exit logic: ATR-based
   if(HasPosition(POSITION_TYPE_SELL) && atrExitLevel != 0)
   {
      double bidNow = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bidNow <= atrExitLevel)
      {
         if(trade.PositionClose(_Symbol))
         {
            Print("Reason: Exit_Short_ATR_Level");
            PrintFormat("Price=%.5f reached ATR_exit=%.5f, closed short", bidNow, atrExitLevel);
         }
         atrExitLevel = 0;
         ObjectDelete(0, "ATR_ExitLine");
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: Check for existing position                              |
//+------------------------------------------------------------------+
bool HasPosition(int type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket) &&
         PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_TYPE) == type)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
