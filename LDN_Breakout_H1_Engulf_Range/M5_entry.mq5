// 1.直接使用server time, tm.hour: 正常H1 range 是 NY: [3, 5], LDN: [8, 10], Server: [10, 12]
// 2.目前适用于 GU, AJ, 可以尝试加入EU

//+------------------------------------------------------------------+
//| Engulfing Breakout EA - Long & Short - Adjusted for GMT+3       |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
CTrade trade;

// === Inputs ===
input double RiskPerTradeUSD = 1000.0;
input double RRRatio         = 3.0;

// === Globals ===
datetime lastTradeDay = 0;
double rangeHigh = -1, rangeLow = -1;
bool foundEngulf = false;
bool tradePlaced = false;

double lastBearishWickLow = -1;
double lastBullishWickHigh = -1;

//+------------------------------------------------------------------+
int OnInit() {
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick() {
   MqlDateTime tm, lastTm;
   TimeToStruct(TimeCurrent(), tm);
   TimeToStruct(lastTradeDay, lastTm);

   int serverHour = tm.hour;

   // === Reset at start of a new day ===
   if (tm.day != lastTm.day || tm.mon != lastTm.mon || tm.year != lastTm.year) {
      lastTradeDay = TimeCurrent();
      foundEngulf = false;
      tradePlaced = false;
      rangeHigh = -1;
      rangeLow = -1;
      lastBearishWickLow = -1;
      lastBullishWickHigh = -1;
   }

   // === Step 1: Detect engulfing using H1[i=1] vs H1[i=2]
   if (!foundEngulf && serverHour >= 10 && serverHour <= 12) {
      double h1OpenPrev  = iOpen(_Symbol, PERIOD_H1, 2);
      double h1ClosePrev = iClose(_Symbol, PERIOD_H1, 2);
      double h1HighPrev  = iHigh(_Symbol, PERIOD_H1, 2);
      double h1LowPrev   = iLow(_Symbol, PERIOD_H1, 2);

      double h1Open  = iOpen(_Symbol, PERIOD_H1, 1);
      double h1Close = iClose(_Symbol, PERIOD_H1, 1);
      double h1High  = iHigh(_Symbol, PERIOD_H1, 1);
      double h1Low   = iLow(_Symbol, PERIOD_H1, 1);

      bool isBullish = h1Low < h1LowPrev && h1Close > MathMax(h1OpenPrev, h1ClosePrev);
      bool isBearish = h1High > h1HighPrev && h1Close < MathMin(h1OpenPrev, h1ClosePrev);

      if (isBullish || isBearish) {
         rangeHigh = h1High;
         rangeLow = h1Low;
         foundEngulf = true;

         Print("H1 Engulfing Detected - ", isBullish ? "Bullish" : "Bearish",
               " | RangeHigh=", rangeHigh, " RangeLow=", rangeLow);

         // === Draw box over engulfing bar
         long chartId = ChartID();
         datetime barStart = iTime(_Symbol, PERIOD_H1, 1);
         datetime barEnd = barStart + 3600;
         string boxName = "EngulfBox_" + IntegerToString(barStart);

         ObjectDelete(chartId, boxName);
         ObjectCreate(chartId, boxName, OBJ_RECTANGLE, 0, barStart, rangeHigh, barEnd, rangeLow);
         ObjectSetInteger(chartId, boxName, OBJPROP_COLOR, isBullish ? clrLime : clrRed);
         ObjectSetInteger(chartId, boxName, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(chartId, boxName, OBJPROP_WIDTH, 1);
         ObjectSetInteger(chartId, boxName, OBJPROP_BACK, true);
      }
   }

   // === Step 2: Get wick of last M5 candle ===
   double openM5 = iOpen(_Symbol, PERIOD_M5, 1);
   double closeM5 = iClose(_Symbol, PERIOD_M5, 1);
   double highM5 = iHigh(_Symbol, PERIOD_M5, 1);
   double lowM5 = iLow(_Symbol, PERIOD_M5, 1);

   if (closeM5 < openM5)
      lastBearishWickLow = lowM5;

   if (closeM5 > openM5)
      lastBullishWickHigh = highM5;

   // === Step 3: Entry logic on M5 between 8AM–10PM server ===
   if (foundEngulf && !tradePlaced && serverHour >= 8 && serverHour <= 22) {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double openCurr = iOpen(_Symbol, PERIOD_M5, 1);
      double closeCurr = iClose(_Symbol, PERIOD_M5, 1);

      bool breakoutLong  = closeCurr > rangeHigh && openCurr <= rangeHigh + _Point;
      bool breakoutShort = closeCurr < rangeLow  && openCurr >= rangeLow - _Point;

      Print("CheckEntry | HOUR=", serverHour,
            " | breakoutLong=", breakoutLong, " | breakoutShort=", breakoutShort,
            " | open=", openCurr, " close=", closeCurr,
            " | rangeHigh=", rangeHigh, " rangeLow=", rangeLow,
            " | wickLow=", lastBearishWickLow, " wickHigh=", lastBullishWickHigh);

      // === Long Entry ===
      if (breakoutLong && lastBearishWickLow > 0) {
         double entry = ask;
         double sl = lastBearishWickLow;
         double risk = entry - sl;
         if (risk <= 0) return;

         double tp = entry + risk * RRRatio;
         double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         double dollarPerPoint = risk / tickSize * tickValue;
         double lots = RiskPerTradeUSD / dollarPerPoint;

         NormalizeLots(lots);
         if (trade.Buy(lots, _Symbol, entry, sl, tp, "Engulfing Long")) {
            tradePlaced = true;
            Print("LONG Trade Placed: lots=", lots, " sl=", sl, " tp=", tp);
         }
      }

      // === Short Entry ===
      if (breakoutShort && lastBullishWickHigh > 0) {
         double entry = bid;
         double sl = lastBullishWickHigh;
         double risk = sl - entry;
         if (risk <= 0) return;

         double tp = entry - risk * RRRatio;
         double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
         double dollarPerPoint = risk / tickSize * tickValue;
         double lots = RiskPerTradeUSD / dollarPerPoint;

         NormalizeLots(lots);
         if (trade.Sell(lots, _Symbol, entry, sl, tp, "Engulfing Short")) {
            tradePlaced = true;
            Print("SHORT Trade Placed: lots=", lots, " sl=", sl, " tp=", tp);
         }
      }
   }
}

//+------------------------------------------------------------------+
void NormalizeLots(double &lots) {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lots = MathMax(MathMin(NormalizeDouble(lots, 2), maxLot), minLot);
}
