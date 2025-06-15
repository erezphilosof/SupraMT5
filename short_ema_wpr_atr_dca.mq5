//+------------------------------------------------------------------+
//|                                                  ShortBiasEA.mq5 |
//|                                  Example Implementation in MQL5 |
//+------------------------------------------------------------------+
#property copyright "OpenAI"
#property version   "1.00"
#property strict
#include <Trade/Trade.mqh>

CTrade trade;

//--- input parameters
input int      EMA_Period          = 50;           // EMA period for bias
input int      ATR_Period          = 14;           // ATR period
input int      WPR_Period          = 14;           // Williams %R period
input double   WPR_Threshold       = -20.0;        // WPR threshold for shorts (above this value)
input double   Base_Lot            = 0.1;          // Base lot size
input double   DCAMultipliers[]    = {1.0,2.0,3.0,4.0,5.0}; // ATR multipliers for DCA levels
input double   DCAQty[]            = {0.1,0.1,0.1,0.1,0.1}; // Lot size for each DCA level
input double   Risk_LossPercent    = 5.0;          // Max percent loss of start-of-day equity
input double   Daily_StopLoss      = 100.0;        // Daily stop loss in account currency
input double   Catastrophic_Stop   = 300.0;        // Catastrophic stop in account currency
input double   Target_ATR_Mult     = 2.0;          // Take profit ATR multiplier

//--- global variables
double    gDayStartEquity = 0.0;
double    gEntryPrice     = 0.0;
int       gDcaLevel       = 0;
datetime  gDayStartTime   = 0;
int       gAtrHandle      = INVALID_HANDLE;
int       gWprHandle      = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   gDayStartTime = iTime(_Symbol,PERIOD_D1,0);
   gDayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   gAtrHandle = iATR(_Symbol,PERIOD_CURRENT,ATR_Period);
   gWprHandle = iWPR(_Symbol,PERIOD_CURRENT,WPR_Period);
   if(gAtrHandle==INVALID_HANDLE || gWprHandle==INVALID_HANDLE)
      return(INIT_FAILED);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(gAtrHandle!=INVALID_HANDLE)
      IndicatorRelease(gAtrHandle);
   if(gWprHandle!=INVALID_HANDLE)
      IndicatorRelease(gWprHandle);
}

//+------------------------------------------------------------------+
//| Obtain intraday VWAP                                             |
//+------------------------------------------------------------------+
double GetVWAP()
{
   datetime day_start = iTime(_Symbol,PERIOD_D1,0);
   int bars = iBarShift(_Symbol,0,day_start,true);
   if(bars==INVALID_HANDLE) bars = 0;
   double sumPV=0.0,sumV=0.0;
   for(int i=bars;i>=0;--i)
   {
      double price=(iHigh(_Symbol,0,i)+iLow(_Symbol,0,i)+iClose(_Symbol,0,i))/3.0;
      double vol=(double)iVolume(_Symbol,0,i);
      sumPV+=price*vol;
      sumV+=vol;
   }
   if(sumV==0) return(iClose(_Symbol,0,0));
   return(sumPV/sumV);
}

//+------------------------------------------------------------------+
//| Check daily reset                                                |
//+------------------------------------------------------------------+
void CheckNewDay()
{
   datetime day_start = iTime(_Symbol,PERIOD_D1,0);
   if(day_start!=gDayStartTime)
   {
      gDayStartTime=day_start;
      gDayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      gDcaLevel=0;
      gEntryPrice=0.0;
   }
}

//+------------------------------------------------------------------+
//| Manage exits                                                     |
//+------------------------------------------------------------------+
void CheckRiskExit(double ema,double atr)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double profitToday = equity - gDayStartEquity;
   // state change exit
   if(PositionSelect(_Symbol))
   {
      ulong ticket = PositionGetTicket(0);
      double price = SymbolInfoDouble(_Symbol,SYMBOL_BID);

      if(price>ema)
         trade.PositionClose(ticket); // EMA cross
      else if(profitToday <= -Risk_LossPercent/100.0 * gDayStartEquity)
         trade.PositionClose(ticket); // loss percent
      else if(profitToday <= -Daily_StopLoss)
         trade.PositionClose(ticket); // daily stop
      else if(profitToday <= -Catastrophic_Stop)
         trade.PositionClose(ticket); // catastrophic exit
      else if((gEntryPrice - price) >= Target_ATR_Mult*atr)
         trade.PositionClose(ticket); // target
   }
}

//+------------------------------------------------------------------+
//| Manage DCA                                                       |
//+------------------------------------------------------------------+
void CheckDCA(double atr)
{
   if(!PositionSelect(_Symbol)) return;
   double price = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(gDcaLevel>=ArraySize(DCAMultipliers)) return;

   double level_price = gEntryPrice + DCAMultipliers[gDcaLevel]*atr;
   if(price>=level_price)
   {
      double lot = DCAQty[gDcaLevel];
      trade.Sell(lot,_Symbol,0,0,0); // market sell at Bid
      gDcaLevel++;
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   CheckNewDay();
   double ema = iMA(_Symbol,0,EMA_Period,0,MODE_EMA,PRICE_CLOSE,0);
   double atr = 0.0,wpr = 0.0;
   double atrBuf[1],wprBuf[1];
   if(CopyBuffer(gAtrHandle,0,0,1,atrBuf)==1)
      atr = atrBuf[0];
   if(CopyBuffer(gWprHandle,0,0,1,wprBuf)==1)
      wpr = wprBuf[0];
   double vwap = GetVWAP();
   double price = SymbolInfoDouble(_Symbol,SYMBOL_BID);

   // entry condition
   if(!PositionSelect(_Symbol))
   {
      gDcaLevel=0;
      if(price<ema && price<vwap && wpr>WPR_Threshold)
      {
         trade.Sell(Base_Lot,_Symbol,0,0,0);
         gEntryPrice=price;
      }
   }
   else
   {
      CheckDCA(atr);
   }

   CheckRiskExit(ema,atr);
}
//+------------------------------------------------------------------+
