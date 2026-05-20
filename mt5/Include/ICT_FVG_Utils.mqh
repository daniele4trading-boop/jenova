//+------------------------------------------------------------------+
//| ICT_FVG_Utils.mqh                                                |
//+------------------------------------------------------------------+
#ifndef ICT_FVG_UTILS_MQH
#define ICT_FVG_UTILS_MQH

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

double NormalizePrice(const string symbol,const double price)
  {
   const int digits = (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   return NormalizeDouble(price,digits);
  }

double NormalizeVolume(const string symbol,double volume)
  {
   const double vmin  = SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   const double vmax  = SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   const double vstep = SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(vstep <= 0.0)
      return 0.0;
   volume = MathFloor(volume / vstep) * vstep;
   if(volume < vmin) volume = 0.0;
   if(volume > vmax) volume = vmax;
   return volume;
  }

ENUM_MARKET_KIND DetectMarketKind(const string symbol)
  {
   string s = symbol;
   StringToUpper(s);
   if(StringFind(s,"XAU") >= 0 || StringFind(s,"GOLD") >= 0 || StringFind(s,"XAG") >= 0)
      return MARKET_GOLD;
   if(StringFind(s,"BTC") >= 0 || StringFind(s,"ETH") >= 0 || StringFind(s,"LTC") >= 0 ||
      StringFind(s,"XRP") >= 0 || StringFind(s,"SOL") >= 0)
      return MARKET_CRYPTO;
   if(StringFind(s,"USD") >= 0 || StringFind(s,"EUR") >= 0 || StringFind(s,"GBP") >= 0 || StringFind(s,"JPY") >= 0)
      return MARKET_FOREX;
   return MARKET_OTHER;
  }

#endif
