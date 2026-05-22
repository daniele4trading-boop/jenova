//+------------------------------------------------------------------+
//|                                         Adaptive ICT - FVG.mq5   |
//| ICT Sweep + FVG + Kill Zone - Forex / Gold / Crypto (ATR)        |
//| Single file - no external includes required                      |
//+------------------------------------------------------------------+
#property copyright "Adaptive ICT FVG"
#property version   "1.02"
#property description "Sweep + FVG OTE 50-62 pct. Kill Zone. Draw levels + optional trading."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

//--- enums (inline, no external .mqh)
enum ENUM_ASSET_PRESET
  {
   PRESET_AUTO   = 0,
   PRESET_FOREX  = 1,
   PRESET_GOLD   = 2,
   PRESET_CRYPTO = 3,
   PRESET_CUSTOM = 4
  };

enum ENUM_MARKET_KIND
  {
   MARKET_FOREX  = 0,
   MARKET_GOLD   = 1,
   MARKET_CRYPTO = 2,
   MARKET_OTHER  = 3
  };

//--- helpers
double NPrice(const string sym,const double price)
  {
   return NormalizeDouble(price,(int)SymbolInfoInteger(sym,SYMBOL_DIGITS));
  }

double NVol(const string sym,double vol)
  {
   const double vmin=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   const double vmax=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   const double vstep=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   if(vstep<=0.0) return 0.0;
   vol=MathFloor(vol/vstep)*vstep;
   if(vol<vmin) return 0.0;
   if(vol>vmax) vol=vmax;
   return vol;
  }

ENUM_MARKET_KIND DetectMarketKind(const string symbol)
  {
   string s=symbol;
   StringToUpper(s);
   if(StringFind(s,"XAU")>=0||StringFind(s,"GOLD")>=0||StringFind(s,"XAG")>=0)
      return MARKET_GOLD;
   if(StringFind(s,"BTC")>=0||StringFind(s,"ETH")>=0||StringFind(s,"LTC")>=0||
      StringFind(s,"XRP")>=0||StringFind(s,"SOL")>=0)
      return MARKET_CRYPTO;
   if(StringFind(s,"USD")>=0||StringFind(s,"EUR")>=0||StringFind(s,"GBP")>=0||StringFind(s,"JPY")>=0)
      return MARKET_FOREX;
   return MARKET_OTHER;
  }

//--- inputs
input group "=== General ==="
input ENUM_ASSET_PRESET InpPreset           = PRESET_AUTO;
input bool              InpAllowTrading     = true;
input bool              InpDrawLevels       = true;
input ulong             InpMagic            = 20260521;
input string            InpTradeComment     = "ICT_FVG";

input group "=== Timeframe ==="
input ENUM_TIMEFRAMES   InpBiasTF           = PERIOD_H1;
input ENUM_TIMEFRAMES   InpEntryTF          = PERIOD_M15;

input group "=== Volatility ATR ==="
input int               InpATRPeriod        = 14;
input double            InpSweepBreakATR    = 0.05;
input double            InpSLBufferATR      = 0.30;
input double            InpMinFVGSizeATR    = 0.15;
input double            InpMaxSpreadATR     = 0.35;
input int               InpSweepLookback    = 24;
input int               InpSweepReclaimBars = 3;

input group "=== FVG OTE ==="
input double            InpEntryFibMin      = 0.50;
input double            InpEntryFibMax      = 0.62;
input int               InpFVGMaxAgeHours   = 24;

input group "=== Risk ==="
input bool              InpUseRiskPercent   = true;
input double            InpRiskPercent      = 1.0;
input double            InpFixedLots          = 0.01;
input double            InpTP1RR             = 1.0;
input double            InpTP2RR             = 2.0;
input bool              InpClosePartialAtTP1= true;
input double            InpPartialClosePct  = 50.0;
input int               InpMaxOpenTrades    = 1;
input int               InpMinBarsBetweenTrades = 4;

input group "=== Kill Zone CET ==="
input bool              InpUseKillZone      = true;
input int               InpCETOffsetHours   = 0;
input int               InpLondonStartHour  = 7;
input int               InpLondonEndHour    = 10;
input double            InpNYStartHour      = 14.5;
input double            InpNYEndHour        = 16.5;
input bool              InpCrypto24h         = false;

input group "=== Filters ==="
input bool              InpRequireClosedBar = true;

double g_sweepBreakATR,g_slBufferATR,g_minFVGSizeATR,g_maxSpreadATR;
bool   g_useKillZone,g_crypto24h;

CTrade        g_trade;
CPositionInfo g_pos;
int           g_atrEntry=INVALID_HANDLE;
datetime      g_lastBarTime=0;
datetime      g_lastTradeBar=0;
string        g_prefix;
ulong         g_partialDone[];

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

void ApplyPreset()
  {
   g_sweepBreakATR=InpSweepBreakATR;
   g_slBufferATR=InpSLBufferATR;
   g_minFVGSizeATR=InpMinFVGSizeATR;
   g_maxSpreadATR=InpMaxSpreadATR;
   g_useKillZone=InpUseKillZone;
   g_crypto24h=InpCrypto24h;
   if(InpPreset==PRESET_CUSTOM) return;
   ENUM_MARKET_KIND mk=MARKET_FOREX;
   if(InpPreset==PRESET_AUTO){mk=DetectMarketKind(_Symbol);if(mk==MARKET_OTHER)mk=MARKET_FOREX;}
   else if(InpPreset==PRESET_FOREX) mk=MARKET_FOREX;
   else if(InpPreset==PRESET_GOLD) mk=MARKET_GOLD;
   else if(InpPreset==PRESET_CRYPTO) mk=MARKET_CRYPTO;
   switch(mk)
     {
      case MARKET_FOREX:
         g_sweepBreakATR=0.05;g_slBufferATR=0.25;g_minFVGSizeATR=0.12;g_maxSpreadATR=0.30;break;
      case MARKET_GOLD:
         g_sweepBreakATR=0.08;g_slBufferATR=0.35;g_minFVGSizeATR=0.20;g_maxSpreadATR=0.45;break;
      case MARKET_CRYPTO:
         g_sweepBreakATR=0.10;g_slBufferATR=0.40;g_minFVGSizeATR=0.18;g_maxSpreadATR=0.55;
         if(InpPreset==PRESET_CRYPTO) g_crypto24h=InpCrypto24h;
         break;
     }
  }

int OnInit()
  {
   g_prefix="ICTFVG_"+_Symbol+"_";
   ApplyPreset();
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(30);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_atrEntry=iATR(_Symbol,InpEntryTF,InpATRPeriod);
   if(g_atrEntry==INVALID_HANDLE) return INIT_FAILED;
   ArrayResize(g_partialDone,0);
   Print("Adaptive ICT FVG started on ",_Symbol);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(g_atrEntry!=INVALID_HANDLE) IndicatorRelease(g_atrEntry);
  }

void OnTick()
  {
   if(!IsNewBar(InpEntryTF)) return;
   ManagePartialTP1();
   int bias=GetStructureBias();
   if(bias==0) return;
   if(g_useKillZone && !IsKillZone(TimeCurrent())) return;
   if(!SpreadAllowed()) return;
   SetupSignal sig;
   if(!BuildSetup(bias,sig)) return;
   if(InpDrawLevels) DrawSetup(sig);
   if(!InpAllowTrading) return;
   if(CountPositions()>=InpMaxOpenTrades) return;
   if(g_lastTradeBar==sig.signalTime) return;
   if(g_lastTradeBar>0 && iBarShift(_Symbol,InpEntryTF,g_lastTradeBar,true)<InpMinBarsBetweenTrades) return;
   if(PlaceOrder(sig)) g_lastTradeBar=sig.signalTime;
  }

bool IsNewBar(const ENUM_TIMEFRAMES tf)
  {
   datetime t[1];
   if(CopyTime(_Symbol,tf,0,1,t)<1) return false;
   if(t[0]==g_lastBarTime) return false;
   g_lastBarTime=t[0];
   return true;
  }

double GetATR(const int shift)
  {
   double b[];
   if(CopyBuffer(g_atrEntry,0,shift,1,b)<1) return 0.0;
   return b[0];
  }

bool SpreadAllowed()
  {
   double sp=SymbolInfoDouble(_Symbol,SYMBOL_ASK)-SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double a=GetATR(1);
   return(a>0 && sp<=g_maxSpreadATR*a);
  }

datetime ToCET(datetime t){return t+InpCETOffsetHours*3600;}

bool IsKillZone(datetime t)
  {
   if(g_crypto24h) return true;
   if(!g_useKillZone) return true;
   MqlDateTime dt;
   TimeToStruct(ToCET(t),dt);
   double hm=dt.hour+dt.min/60.0;
   return(hm>=InpLondonStartHour && hm<InpLondonEndHour)||(hm>=InpNYStartHour && hm<InpNYEndHour);
  }

int GetStructureBias()
  {
   double hi[],lo[];
   ArraySetAsSeries(hi,true);
   ArraySetAsSeries(lo,true);
   const int n=100;
   if(CopyHigh(_Symbol,InpBiasTF,1,n,hi)<n) return 0;
   if(CopyLow(_Symbol,InpBiasTF,1,n,lo)<n) return 0;
   double sh1=0,sh2=0,sl1=0,sl2=0;
   int hc=0,lc=0;
   const int w=2;
   for(int i=w;i<n-w;i++)
     {
      bool ih=true,il=true;
      for(int j=1;j<=w;j++)
        {
         if(hi[i]<=hi[i-j]||hi[i]<=hi[i+j]) ih=false;
         if(lo[i]>=lo[i-j]||lo[i]>=lo[i+j]) il=false;
        }
      if(ih){sh2=sh1;sh1=hi[i];hc++;}
      if(il){sl2=sl1;sl1=lo[i];lc++;}
     }
   if(hc<2||lc<2) return 0;
   if(sh1>sh2 && sl1>sl2) return 1;
   if(sh1<sh2 && sl1<sl2) return -1;
   return 0;
  }

bool DetectFVG(const int dir,const int shift,double &top,double &bot)
  {
   double h[],l[];
   if(CopyHigh(_Symbol,InpEntryTF,shift,3,h)<3) return false;
   if(CopyLow(_Symbol,InpEntryTF,shift,3,l)<3) return false;
   // h[0]/l[0]=bar shift (newest), h[2]/l[2]=bar shift+2 (oldest of 3)
   if(dir>0 && h[2]<l[0]){bot=h[2];top=l[0];return true;}
   if(dir<0 && l[2]>h[0]){bot=h[0];top=l[2];return true;}
   return false;
  }

bool BuildSetup(const int bias,SetupSignal &sig)
  {
   const int sh=InpRequireClosedBar?1:0;
   const double atr=GetATR(sh);
   if(atr<=0) return false;
   double hi[],lo[],cl[];
   ArraySetAsSeries(hi,true);
   ArraySetAsSeries(lo,true);
   ArraySetAsSeries(cl,true);
   const int lb=InpSweepLookback+2;
   if(CopyHigh(_Symbol,InpEntryTF,sh,lb,hi)<lb) return false;
   if(CopyLow(_Symbol,InpEntryTF,sh,lb,lo)<lb) return false;
   if(CopyClose(_Symbol,InpEntryTF,sh,3,cl)<3) return false;
   double swingH=hi[1],swingL=lo[1];
   for(int i=2;i<InpSweepLookback;i++)
     {
      if(hi[i]>swingH) swingH=hi[i];
      if(lo[i]<swingL) swingL=lo[i];
     }
   datetime tm[1];
   if(CopyTime(_Symbol,InpEntryTF,sh,1,tm)<1) return false;
   if(InpFVGMaxAgeHours>0 && (TimeCurrent()-tm[0])>InpFVGMaxAgeHours*3600) return false;
   const double brk=g_sweepBreakATR*atr;
   if(bias>0)
     {
      if(lo[1]>=swingL-brk || cl[1]<=swingL) return false;
      double ft=0.0,fb=0.0; bool ok=false;
      for(int j=0;j<=InpSweepReclaimBars;j++)
         if(DetectFVG(1,sh+j,ft,fb)){ok=true;break;}
      if(!ok) return false;
      if(ft-fb<g_minFVGSizeATR*atr) return false;
      sig.direction=1;
      sig.sweepLevel=swingL;
      sig.fvgTop=ft; sig.fvgBottom=fb;
      sig.entry=NPrice(_Symbol,fb+InpEntryFibMin*(ft-fb));
      sig.sl=NPrice(_Symbol,MathMin(lo[1],swingL)-g_slBufferATR*atr);
      double risk=sig.entry-sig.sl;
      if(risk<=0) return false;
      sig.tp1=NPrice(_Symbol,sig.entry+InpTP1RR*risk);
      sig.tp2=NPrice(_Symbol,sig.entry+InpTP2RR*risk);
      sig.signalTime=tm[0];
      sig.id=TimeToString(tm[0],TIME_DATE|TIME_MINUTES)+"_L";
      return true;
     }
   if(bias<0)
     {
      if(hi[1]<=swingH+brk || cl[1]>=swingH) return false;
      double ft=0.0,fb=0.0; bool ok=false;
      for(int j=0;j<=InpSweepReclaimBars;j++)
         if(DetectFVG(-1,sh+j,ft,fb)){ok=true;break;}
      if(!ok) return false;
      if(ft-fb<g_minFVGSizeATR*atr) return false;
      sig.direction=-1;
      sig.sweepLevel=swingH;
      sig.fvgTop=ft; sig.fvgBottom=fb;
      sig.entry=NPrice(_Symbol,fb+InpEntryFibMax*(ft-fb));
      sig.sl=NPrice(_Symbol,MathMax(hi[1],swingH)+g_slBufferATR*atr);
      double risk=sig.sl-sig.entry;
      if(risk<=0) return false;
      sig.tp1=NPrice(_Symbol,sig.entry-InpTP1RR*risk);
      sig.tp2=NPrice(_Symbol,sig.entry-InpTP2RR*risk);
      sig.signalTime=tm[0];
      sig.id=TimeToString(tm[0],TIME_DATE|TIME_MINUTES)+"_S";
      return true;
     }
   return false;
  }

int CountPositions()
  {
   int c=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(g_pos.SelectByIndex(i) && g_pos.Symbol()==_Symbol && g_pos.Magic()==InpMagic) c++;
   return c;
  }

double CalcLots(const double entry,const double sl)
  {
   if(!InpUseRiskPercent) return NVol(_Symbol,InpFixedLots);
   double riskMoney=AccountInfoDouble(ACCOUNT_EQUITY)*InpRiskPercent/100.0;
   double dist=MathAbs(entry-sl);
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   if(dist<=0||ts<=0||tv<=0) return NVol(_Symbol,InpFixedLots);
   return NVol(_Symbol,riskMoney/((dist/ts)*tv));
  }

bool PlaceOrder(const SetupSignal &s)
  {
   double lots=CalcLots(s.entry,s.sl);
   if(lots<=0) return false;
   datetime exp=s.signalTime+InpFVGMaxAgeHours*3600;
   bool ok=false;
   if(s.direction>0)
     {
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      if(ask<=s.entry) ok=g_trade.Buy(lots,_Symbol,0,s.sl,s.tp2,InpTradeComment);
      else ok=g_trade.BuyLimit(lots,s.entry,_Symbol,s.sl,s.tp2,ORDER_TIME_SPECIFIED,exp,InpTradeComment);
     }
   else
     {
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      if(bid>=s.entry) ok=g_trade.Sell(lots,_Symbol,0,s.sl,s.tp2,InpTradeComment);
      else ok=g_trade.SellLimit(lots,s.entry,_Symbol,s.sl,s.tp2,ORDER_TIME_SPECIFIED,exp,InpTradeComment);
     }
   if(!ok) Print("Order failed: ",g_trade.ResultRetcodeDescription());
   return ok;
  }

void ManagePartialTP1()
  {
   if(!InpClosePartialAtTP1) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol()!=_Symbol || g_pos.Magic()!=InpMagic) continue;
      ulong ticket=g_pos.Ticket();
      if(IsTicketPartialDone(ticket)) continue;
      double open=g_pos.PriceOpen();
      double sl=g_pos.StopLoss();
      if(sl<=0) continue;
      double risk=MathAbs(open-sl);
      double tp1=(g_pos.PositionType()==POSITION_TYPE_BUY)?open+InpTP1RR*risk:open-InpTP1RR*risk;
      double px=(g_pos.PositionType()==POSITION_TYPE_BUY)?SymbolInfoDouble(_Symbol,SYMBOL_BID):SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      bool hit=(g_pos.PositionType()==POSITION_TYPE_BUY && px>=tp1)||(g_pos.PositionType()==POSITION_TYPE_SELL && px<=tp1);
      if(!hit) continue;
      double v=NVol(_Symbol,g_pos.Volume()*InpPartialClosePct/100.0);
      if(v>0 && v<g_pos.Volume())
        {
         if(g_trade.PositionClosePartial(ticket,v)) MarkTicketPartialDone(ticket);
        }
     }
  }

bool IsTicketPartialDone(const ulong ticket)
  {
   for(int i=0;i<ArraySize(g_partialDone);i++)
      if(g_partialDone[i]==ticket) return true;
   return false;
  }

void MarkTicketPartialDone(const ulong ticket)
  {
   int n=ArraySize(g_partialDone);
   ArrayResize(g_partialDone,n+1);
   g_partialDone[n]=ticket;
  }

void DrawSetup(const SetupSignal &s)
  {
   string b=g_prefix+s.id;
   datetime t2=s.signalTime+PeriodSeconds(InpEntryTF)*48;
   DrawRect(b+"_FVG",s.signalTime,t2,s.fvgTop,s.fvgBottom,clrGoldenrod);
   DrawHLine(b+"_SWP",s.sweepLevel,clrDodgerBlue,"Sweep");
   DrawHLine(b+"_ENT",s.entry,clrLime,"Entry");
   DrawHLine(b+"_SL",s.sl,clrRed,"SL");
   DrawHLine(b+"_TP1",s.tp1,clrGreen,"TP1");
   DrawHLine(b+"_TP2",s.tp2,clrLimeGreen,"TP2");
   double oteT=s.fvgBottom+InpEntryFibMax*(s.fvgTop-s.fvgBottom);
   double oteB=s.fvgBottom+InpEntryFibMin*(s.fvgTop-s.fvgBottom);
   DrawRect(b+"_OTE",s.signalTime,t2,oteT,oteB,clrDarkGreen);
  }

void DrawHLine(const string name,const double price,const color clr,const string txt)
  {
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_HLINE,0,0,price);
   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetString(0,name,OBJPROP_TEXT,txt);
  }

void DrawRect(const string name,const datetime t1,const datetime t2,const double pTop,const double pBot,const color clr)
  {
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,pTop,t2,pBot);
   ObjectSetInteger(0,name,OBJPROP_TIME,0,t1);
   ObjectSetDouble(0,name,OBJPROP_PRICE,0,pTop);
   ObjectSetInteger(0,name,OBJPROP_TIME,1,t2);
   ObjectSetDouble(0,name,OBJPROP_PRICE,1,pBot);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FILL,true);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
  }
//+------------------------------------------------------------------+
