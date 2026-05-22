## Installazione (consigliata)

1. Copia **solo** `Experts/Adaptive ICT - FVG.mq5` in `MQL5/Experts/`
2. MetaEditor: compila `Adaptive ICT - FVG.mq5` (F7) — **un solo file**, nessun .mqh esterno
3. Trascina l'EA sul grafico (XAUUSD, EURUSD, BTCUSD, ...)
4. Abilita **Algo Trading**

**Non incollare questo README dentro il file .mq5** — il codice deve finire con `//+------------------------------------------------------------------+`

### Errore compilazione

| Errore | Soluzione |
|--------|-----------|
| `ICT_FVG_Utils.mqh not found` | Usa `Adaptive ICT - FVG.mq5` oppure copia anche `Include/ICT_FVG_Utils.mqh` |
| `# invalid preprocessor` / backtick | Hai incollato il README nel .mq5: cancella tutto dalla riga ~460 in poi |
| `invalid suffix` / caratteri strani | Scarica di nuovo il file pulito dal repo |

### Versione a 2 file (opzionale)

- `ICT_FVG_Adaptive.mq5` + `Include/ICT_FVG_Utils.mqh` (entrambi richiesti)

# ICT FVG Adaptive — Expert Advisor MT5

EA basato su **ICT**: sweep di liquidità → **FVG** → retest **OTE** (50–62%) in **Kill Zone**.

- Opera sempre sul **simbolo del grafico** (`_Symbol`)
- **Preset** adattivi: Forex / Gold / Crypto / Auto / Custom
- Parametri in multipli di **ATR** (si adattano alla volatilità del simbolo)
- **Disegna** sweep, FVG, OTE, SL, TP1, TP2
- **Trading** opzionale (limit a OTE o market se prezzo già nel gap)

## Installazione

1. Copia i file nella cartella dati MT5:
   - `Experts/ICT_FVG_Adaptive.mq5` → `MQL5/Experts/`
   - `Include/ICT_FVG_Utils.mqh` → `MQL5/Include/`
2. In MetaEditor: **Compila** `ICT_FVG_Adaptive.mq5`
3. Trascina l’EA sul grafico del simbolo desiderato (es. `XAUUSD`, `EURUSD`, `BTCUSD`)
4. Abilita **Algo Trading** e consenti DLL/import se richiesto

## Preset volatilità

| Preset | Sweep break | SL buffer | FVG min | Spread max |
|--------|-------------|-----------|---------|------------|
| **Forex** | 0.05×ATR | 0.25×ATR | 0.12×ATR | 0.30×ATR |
| **Gold** | 0.08×ATR | 0.35×ATR | 0.20×ATR | 0.45×ATR |
| **Crypto** | 0.10×ATR | 0.40×ATR | 0.18×ATR | 0.55×ATR |
| **Auto** | Rileva da nome simbolo (XAU, BTC, …) | | | |
| **Custom** | Usa i valori nel gruppo “Volatilità ATR” | | | |

### Gold (XAUUSD)

- Preset: **Gold** o **Auto**
- TF consigliati: Bias **H1**, Entry **M15**
- `InpCETOffsetHours`: imposta offset del **server broker** rispetto al CET (es. se server = UTC+2 e CET = UTC+1 → prova `-1` o `+1` e verifica le KZ)
- Rischio: 0.5–1% — SL spesso **$10–25/oz** a seconda del broker

### Forex

- Preset: **Forex**
- Entry **M15** o **M5**, Kill Zone attiva

### Crypto

- Preset: **Crypto**
- Opzione `InpCrypto24h = true` per tradare fuori Kill Zone (mercato 24/7)
- Spread spesso alto: alza `InpMaxSpreadATR` in Custom se necessario

## Parametri principali

| Parametro | Descrizione |
|-----------|-------------|
| `InpAllowTrading` | `false` = solo disegno livelli |
| `InpDrawLevels` | Rettangoli FVG/OTE + linee SL/TP |
| `InpUseRiskPercent` | Lotto da % equity vs lotto fisso |
| `InpTP1RR` / `InpTP2RR` | Target in multipli di R (default 1 e 2) |
| `InpClosePartialAtTP1` | Chiude 50% (default) al raggiungimento TP1 |
| `InpFVGMaxAgeHours` | Scadenza ordine limit / validità setup |
| `InpUseKillZone` | Filtra segnali fuori London/NY (CET) |

## Oggetti grafici

- **FVG** — rettangolo oro
- **OTE** — rettangolo verde scuro (zona 50–62%)
- **Sweep** — linea blu / arancione
- **Entry, SL, TP1, TP2** — linee etichettate

## Backtest

1. Strategy Tester → simbolo del grafico (es. `XAUUSD`)
2. Modello: **Every tick based on real ticks** (se disponibile)
3. Allinea `InpCETOffsetHours` al server storico
4. Confronta preset **Gold** vs **Custom** dopo almeno 100 trade

## Avvertenze

- Nessuna garanzia di performance; validare su demo.
- News ad alto impatto: disattivare manualmente o filtrare fuori sessione.
- Il calcolo lotti usa `SYMBOL_TRADE_TICK_VALUE` del broker — verificare su conto reale.

## File

```
mt5/
├── Experts/ICT_FVG_Adaptive.mq5
├── Include/ICT_FVG_Utils.mqh
└── README.md
```
