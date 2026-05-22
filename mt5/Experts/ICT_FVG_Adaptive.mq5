//+------------------------------------------------------------------+
//| ICT_FVG_Adaptive.mq5                                             |
//| ICT Sweep + FVG + Kill Zone — adattivo Forex / Gold / Crypto     |
//| Opera sul simbolo del grafico (_Symbol)                          |
//+------------------------------------------------------------------+
#property copyright "ICT FVG Adaptive"
#property version   "1.00"
#property description "Sweep + FVG retest OTE. Parametri ATR adattivi. Disegno livelli + trading opzionale."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <ICT_FVG_Utils.mqh>

//--- Generale
input group "=== Generale ==="
input ENUM_ASSET_PRESET InpPreset           = PRESET_AUTO;
input bool              InpAllowTrading     = true;
input bool              InpDrawLevels       = true;
input ulong             InpMagic            = 20260521;
input string            InpTradeComment     = "ICT_FVG";

//--- Timeframe
input group "=== Timeframe ==="
input ENUM_TIMEFRAMES   InpBiasTF           = PERIOD_H1;
input ENUM_TIMEFRAMES   InpEntryTF          = PERIOD_M15;

//--- Volatilità (ATR) — usati con PRESET_CUSTOM
input group "=== Volatilità ATR ==="
input int               InpATRPeriod        = 14;
input double            InpSweepBreakATR    = 0.05;
input double            InpSLBufferATR      = 0.30;
input double            InpMinFVGSizeATR    = 0.15;
input double            InpMaxSpreadATR     = 0.35;
input int               InpSweepLookback    = 24;
input int               InpSweepReclaimBars = 3;

//--- FVG / OTE
input group "=== FVG e OTE ==="
input double            InpEntryFibMin      = 0.50;
input double            InpEntryFibMax      = 0.62;
input int               InpFVGMaxAgeHours   = 24;

//--- Rischio
input group "=== Rischio e target ==="
input bool              InpUseRiskPercent   = true;
input double            InpRiskPercent      = 1.0;
input double            InpFixedLots          = 0.01;
input double            InpTP1RR             = 1.0;
input double            InpTP2RR             = 2.0;
input bool              InpClosePartialAtTP1= true;
input double            InpPartialClosePct  = 50.0;
input int               InpMaxOpenTrades    = 1;
input int               InpMinBarsBetweenTrades = 4;

//--- Kill Zone (ore CET)
input group "=== Kill Zone CET ==="
input bool              InpUseKillZone      = true;
input int               InpCETOffsetHours   = 0;
input int               InpLondonStartHour  = 7;
input int               InpLondonEndHour    = 10;
input double            InpNYStartHour      = 14.5;
input double            InpNYEndHour        = 16.5;
input bool              InpCrypto24h         = false;

//--- Filtri
input group "=== Filtri ==="
input bool              InpRequireClosedBar = true;

//--- effective preset values
double g_sweepBreakATR, g_slBufferATR, g_minFVGSizeATR, g_maxSpreadATR;
bool   g_useKillZone, g_crypto24h;

CTrade        g_trade;
CPositionInfo g_pos;
int           g_atrEntry = INVALID_HANDLE;
datetime      g_lastBarTime = 0;
datetime      g_lastTradeBar = 0;
string        g_prefix;
ulong         g_partialDone[];

//+------------------------------------------------------------------+
struct SetupSignal
  {
   int      direction;
   double   sweepLevel;
   double   fvgTop;
   double   fvgBottom;
   double   entry;
   double   sl;
   double   tp1;
   double   tp2;
   datetime signalTime;
   string   id;
  };

//+------------------------------------------------------------------+
void ApplyPreset()
  {
   g_sweepBreakATR = InpSweepBreakATR;
   g_slBufferATR   = InpSLBufferATR;
   g_minFVGSizeATR = InpMinFVGSizeATR;
   g_maxSpreadATR  = InpMaxSpreadATR;
   g_useKillZone   = InpUseKillZone;
   g_crypto24h     = InpCrypto24h;

   if(InpPreset == PRESET_CUSTOM)
      return;

   ENUM_MARKET_KIND mk = MARKET_FOREX;
   if(InpPreset == PRESET_AUTO)
     {
      mk = DetectMarketKind(_Symbol);
      if(mk == MARKET_OTHER) mk = MARKET_FOREX;
     }
   else if(InpPreset == PRESET_FOREX)  mk = MARKET_FOREX;
   else if(InpPreset == PRESET_GOLD)   mk = MARKET_GOLD;
   else if(InpPreset == PRESET_CRYPTO) mk = MARKET_CRYPTO;

   switch(mk)
     {
      case MARKET_FOREX:
         g_sweepBreakATR = 0.05; g_slBufferATR = 0.25; g_minFVGSizeATR = 0.12; g_maxSpreadATR = 0.30;
         break;
      case MARKET_GOLD:
         g_sweepBreakATR = 0.08; g_slBufferATR = 0.35; g_minFVGSizeATR = 0.20; g_maxSpreadATR = 0.45;
         break;
      case MARKET_CRYPTO:
         g_sweepBreakATR = 0.10; g_slBufferATR = 0.40; g_minFVGSizeATR = 0.18; g_maxSpreadATR = 0.55;
         if(InpPreset == PRESET_CRYPTO)
            g_crypto24h = InpCrypto24h;
         break;
      default:
         break;
     }
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   g_prefix = "ICTFVG_" + _Symbol + "_";
   ApplyPreset();
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(30);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_atrEntry = iATR(_Symbol, InpEntryTF, InpATRPeriod);
   if(g_atrEntry == INVALID_HANDLE)
      return INIT_FAILED;
   ArrayResize(g_partialDone, 0);
   PrintFormat("ICT FVG Adaptive avviato su %s | preset=%d", _Symbol, InpPreset);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_atrEntry != INVALID_HANDLE)
      IndicatorRelease(g_atrEntry);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(!IsNewBar(InpEntryTF))
      return;

   ManagePartialTP1();

   const int bias = GetStructureBias();
   if(bias == 0)
      return;
   if(g_useKillZone && !IsKillZone(TimeCurrent()))
      return;
   if(!SpreadAllowed())
      return;

   SetupSignal sig;
   if(!BuildSetup(bias, sig))
      return;

   if(InpDrawLevels)
      DrawSetup(sig);

   if(!InpAllowTrading)
      return;
   if(CountPositions() >= InpMaxOpenTrades)
      return;
   if(g_lastTradeBar == sig.signalTime)
      return;
   if(g_lastTradeBar > 0 && iBarShift(_Symbol, InpEntryTF, g_lastTradeBar, true) < InpMinBarsBetweenTrades)
      return;

   if(PlaceOrder(sig))
      g_lastTradeBar = sig.signalTime;
  }

//+------------------------------------------------------------------+
bool IsNewBar(const ENUM_TIMEFRAMES tf)
  {
   datetime t[1];
   if(CopyTime(_Symbol, tf, 0, 1, t) < 1)
      return false;
   if(t[0] == g_lastBarTime)
      return false;
   g_lastBarTime = t[0];
   return true;
  }

//+------------------------------------------------------------------+
double ATR(const int shift)
  {
   double b[1];
   ArraySetAsSeries(b, true);
   if(CopyBuffer(g_atrEntry, 0, shift, 1, b) < 1)
      return 0.0;
   return b[0];
  }

//+------------------------------------------------------------------+
bool SpreadAllowed()
  {
   const double sp = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double a = ATR(1);
   return (a > 0 && sp <= g_maxSpreadATR * a);
  }

//+------------------------------------------------------------------+
datetime ToCET(datetime t) { return t + InpCETOffsetHours * 3600; }

//+------------------------------------------------------------------+
bool IsKillZone(datetime t)
  {
   if(g_crypto24h) return true;
   if(!g_useKillZone) return true;
   MqlDateTime dt;
   TimeToStruct(ToCET(t), dt);
   const double hm = dt.hour + dt.min / 60.0;
   return (hm >= InpLondonStartHour && hm < InpLondonEndHour) ||
          (hm >= InpNYStartHour && hm < InpNYEndHour);
  }

//+------------------------------------------------------------------+
int GetStructureBias()
  {
   double hi[], lo[];
   ArraySetAsSeries(hi, true);
   ArraySetAsSeries(lo, true);
   const int n = 100;
   if(CopyHigh(_Symbol, InpBiasTF, 1, n, hi) < n) return 0;
   if(CopyLow(_Symbol,  InpBiasTF, 1, n, lo)  < n) return 0;

   double sh1=0, sh2=0, sl1=0, sl2=0;
   int hc=0, lc=0;
   const int w = 2;
   for(int i=w; i<n-w; i++)
     {
      bool ih=true, il=true;
      for(int j=1;j<=w;j++)
        {
         if(hi[i]<=hi[i-j]||hi[i]<=hi[i+j]) ih=false;
         if(lo[i]>=lo[i-j]||lo[i]>=lo[i+j]) il=false;
        }
      if(ih){ sh2=sh1; sh1=hi[i]; hc++; }
      if(il){ sl2=sl1; sl1=lo[i]; lc++; }
     }
   if(hc<2||lc<2) return 0;
   if(sh1>sh2 && sl1>sl2) return 1;
   if(sh1<sh2 && sl1<sl2) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
bool DetectFVG(int dir,int shift,double &top,double &bot)
  {
   double h[4], l[4];
   ArraySetAsSeries(h,true);
   ArraySetAsSeries(l,true);
   if(CopyHigh(_Symbol,InpEntryTF,shift,4,h)<4) return false;
   if(CopyLow(_Symbol,InpEntryTF,shift,4,l)<4) return false;
   if(dir>0 && h[3]<l[1]) { bot=h[3]; top=l[1]; return true; }
   if(dir<0 && l[3]>h[1]) { bot=h[1]; top=l[3]; return true; }
   return false;
  }

//+------------------------------------------------------------------+
bool BuildSetup(int bias, SetupSignal &sig)
  {
   const int sh = InpRequireClosedBar ? 1 : 0;
   const double atr = ATR(sh);
   if(atr<=0) return false;

   double hi[], lo[], cl[];
   ArraySetAsSeries(hi,true);
   ArraySetAsSeries(lo,true);
   ArraySetAsSeries(cl,true);
   const int lb = InpSweepLookback + 2;
   if(CopyHigh(_Symbol,InpEntryTF,sh,lb,hi)<lb) return false;
   if(CopyLow(_Symbol,InpEntryTF,sh,lb,lo)<lb) return false;
   if(CopyClose(_Symbol,InpEntryTF,sh,3,cl)<3) return false;

   double swingH=hi[1], swingL=lo[1];
   for(int i=2;i<InpSweepLookback;i++)
     {
      if(hi[i]>swingH) swingH=hi[i];
      if(lo[i]<swingL) swingL=lo[i];
     }

   datetime tm[1];
   if(CopyTime(_Symbol,InpEntryTF,sh,1,tm)<1) return false;
   if(InpFVGMaxAgeHours>0 && (TimeCurrent()-tm[0])>InpFVGMaxAgeHours*3600)
      return false;

   const double brk = g_sweepBreakATR * atr;

   if(bias>0)
     {
      if(lo[1] >= swingL - brk || cl[1] <= swingL) return false;
      double ft, fb;
      bool ok=false;
      for(int j=0;j<=InpSweepReclaimBars;j++)
         if(DetectFVG(1, sh+j, ft, fb)) { ok=true; break; }
      if(!ok) return false;
      if(ft-fb < g_minFVGSizeATR*atr) return false;
      sig.direction=1;
      sig.sweepLevel=swingL;
      sig.fvgTop=ft; sig.fvgBottom=fb;
      sig.entry=NormalizePrice(_Symbol, fb + InpEntryFibMin*(ft-fb));
      sig.sl=NormalizePrice(_Symbol, MathMin(lo[1],swingL) - g_slBufferATR*atr);
      double risk=sig.entry-sig.sl;
      if(risk<=0) return false;
      sig.tp1=NormalizePrice(_Symbol, sig.entry+InpTP1RR*risk);
      sig.tp2=NormalizePrice(_Symbol, sig.entry+InpTP2RR*risk);
      sig.signalTime=tm[0];
      sig.id=TimeToString(tm[0],TIME_DATE|TIME_MINUTES)+"_L";
      return true;
     }

   if(bias<0)
     {
      if(hi[1] <= swingH + brk || cl[1] >= swingH) return false;
      double ft, fb;
      bool ok=false;
      for(int j=0;j<=InpSweepReclaimBars;j++)
         if(DetectFVG(-1, sh+j, ft, fb)) { ok=true; break; }
      if(!ok) return false;
      if(ft-fb < g_minFVGSizeATR*atr) return false;
      sig.direction=-1;
      sig.sweepLevel=swingH;
      sig.fvgTop=ft; sig.fvgBottom=fb;
      sig.entry=NormalizePrice(_Symbol, fb + InpEntryFibMax*(ft-fb));
      sig.sl=NormalizePrice(_Symbol, MathMax(hi[1],swingH) + g_slBufferATR*atr);
      double risk=sig.sl-sig.entry;
      if(risk<=0) return false;
      sig.tp1=NormalizePrice(_Symbol, sig.entry-InpTP1RR*risk);
      sig.tp2=NormalizePrice(_Symbol, sig.entry-InpTP2RR*risk);
      sig.signalTime=tm[0];
      sig.id=TimeToString(tm[0],TIME_DATE|TIME_MINUTES)+"_S";
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
int CountPositions()
  {
   int c=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(g_pos.SelectByIndex(i) && g_pos.Symbol()==_Symbol && g_pos.Magic()==InpMagic)
         c++;
   return c;
  }

//+------------------------------------------------------------------+
double CalcLots(double entry,double sl)
  {
   if(!InpUseRiskPercent)
      return NormalizeVolume(_Symbol, InpFixedLots);
   const double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   const double riskMoney = eq * InpRiskPercent / 100.0;
   const double dist = MathAbs(entry-sl);
   double ts = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tv = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   if(dist<=0||ts<=0||tv<=0)
      return NormalizeVolume(_Symbol,InpFixedLots);
   return NormalizeVolume(_Symbol, riskMoney / ((dist/ts)*tv));
  }

//+------------------------------------------------------------------+
bool PlaceOrder(const SetupSignal &s)
  {
   double lots=CalcLots(s.entry,s.sl);
   if(lots<=0) return false;

   datetime exp = s.signalTime + InpFVGMaxAgeHours*3600;
   bool ok=false;
   if(s.direction>0)
     {
      const double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      if(ask<=s.entry)
         ok=g_trade.Buy(lots,_Symbol,0,s.sl,s.tp2,InpTradeComment);
      else
         ok=g_trade.BuyLimit(lots,s.entry,_Symbol,s.sl,s.tp2,ORDER_TIME_SPECIFIED,exp,InpTradeComment);
     }
   else
     {
      const double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      if(bid>=s.entry)
         ok=g_trade.Sell(lots,_Symbol,0,s.sl,s.tp2,InpTradeComment);
      else
         ok=g_trade.SellLimit(lots,s.entry,_Symbol,s.sl,s.tp2,ORDER_TIME_SPECIFIED,exp,InpTradeComment);
     }
   if(!ok)
      Print("Ordine fallito: ", g_trade.ResultRetcodeDescription());
   return ok;
  }

//+------------------------------------------------------------------+
void ManagePartialTP1()
  {
   if(!InpClosePartialAtTP1) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol()!=_Symbol || g_pos.Magic()!=InpMagic) continue;

      ulong ticket=g_pos.Ticket();
      if(IsTicketClosedPartial(ticket)) continue;

      const double open=g_pos.PriceOpen();
      const double sl=g_pos.StopLoss();
      if(sl<=0) continue;
      const double risk=MathAbs(open-sl);
      const double tp1=(g_pos.PositionType()==POSITION_TYPE_BUY)? open+InpTP1RR*risk : open-InpTP1RR*risk;
      const double px=(g_pos.PositionType()==POSITION_TYPE_BUY)?
                      SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      bool hit=(g_pos.PositionType()==POSITION_TYPE_BUY && px>=tp1) ||
               (g_pos.PositionType()==POSITION_TYPE_SELL && px<=tp1);
      if(!hit) continue;

      double v=NormalizeVolume(_Symbol, g_pos.Volume()*InpPartialClosePct/100.0);
      if(v>0 && v<g_pos.Volume())
        {
         if(g_trade.PositionClosePartial(ticket,v))
            MarkTicketPartial(ticket);
        }
     }
  }

//+------------------------------------------------------------------+
bool IsTicketClosedPartial(const ulong ticket)
  {
   for(int i=0;i<ArraySize(g_partialDone);i++)
      if(g_partialDone[i]==ticket) return true;
   return false;
  }

//+------------------------------------------------------------------+
void MarkTicketPartial(const ulong ticket)
  {
   const int n=ArraySize(g_partialDone);
   ArrayResize(g_partialDone,n+1);
   g_partialDone[n]=ticket;
  }

//+------------------------------------------------------------------+
void DrawSetup(const SetupSignal &s)
  {
   const string b=g_prefix+s.id;
   datetime t2=s.signalTime+PeriodSeconds(InpEntryTF)*48;
   DrawRect(b+"_FVG",s.signalTime,t2,s.fvgTop,s.fvgBottom,clrGoldenrod);
   DrawLine(b+"_SWP",s.sweepLevel,clrDodgerBlue,"Sweep");
   DrawLine(b+"_ENT",s.entry,clrLime,"Entry");
   DrawLine(b+"_SL",s.sl,clrRed,"SL");
   DrawLine(b+"_TP1",s.tp1,clrGreen,"TP1");
   DrawLine(b+"_TP2",s.tp2,clrLimeGreen,"TP2");
   double oteT=s.fvgBottom+InpEntryFibMax*(s.fvgTop-s.fvgBottom);
   double oteB=s.fvgBottom+InpEntryFibMin*(s.fvgTop-s.fvgBottom);
   DrawRect(b+"_OTE",s.signalTime,t2,oteT,oteB,clrDarkGreen);
  }

//+------------------------------------------------------------------+
void DrawLine(const string n,double p,color c,string t)
  {
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_HLINE,0,0,p);
   ObjectSetDouble(0,n,OBJPROP_PRICE,p);
   ObjectSetInteger(0,n,OBJPROP_COLOR,c);
   ObjectSetString(0,n,OBJPROP_TEXT,t);
  }

//+------------------------------------------------------------------+
void DrawRect(const string n,datetime t1,datetime t2,double p1,double p2,color c)
  {
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_RECTANGLE,0,t1,p1,t2,p2);
   ObjectSetInteger(0,n,OBJPROP_TIME,0,t1);
   ObjectSetDouble(0,n,OBJPROP_PRICE,0,p1);
   ObjectSetInteger(0,n,OBJPROP_TIME,1,t2);
   ObjectSetDouble(0,n,OBJPROP_PRICE,1,p2);
   ObjectSetInteger(0,n,OBJPROP_COLOR,c);
   ObjectSetInteger(0,n,OBJPROP_FILL,true);
   ObjectSetInteger(0,n,OBJPROP_BACK,true);
  }
