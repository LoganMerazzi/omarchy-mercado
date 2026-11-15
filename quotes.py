"""Stock and currency quotes for the logan.mercado bar widget.

Usage: quotes.py <symbols> [ttl_seconds]
<symbols> is a comma-separated list of Yahoo Finance symbols (bare B3 tickers
like PETR4 get ".SA" appended). Prints one JSON object. Results are cached so
opening the panel repeatedly doesn't hammer Yahoo.
"""

import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "omarchy-mercado"
CHART_URL = "https://query1.finance.yahoo.com/v8/finance/chart/{}?range=1d&interval=5m"
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64)"
NAMES = {"USDBRL=X": "Dólar", "EURBRL=X": "Euro", "BTC-USD": "Bitcoin", "^BVSP": "Ibovespa"}
B3_TICKER = re.compile(r"^[A-Z]{4}\d{1,2}$")


def normalize(symbol):
  s = symbol.strip().upper()
  return s + ".SA" if B3_TICKER.match(s) else s


def label(symbol):
  if symbol in NAMES:
    return NAMES[symbol]
  return symbol[:-3] if symbol.endswith(".SA") else symbol


def fetch(symbol):
  url = CHART_URL.format(urllib.parse.quote(symbol, safe=""))
  request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
  try:
    with urllib.request.urlopen(request, timeout=10) as response:
      data = json.load(response)
    result = data["chart"]["result"][0]
  except (OSError, ValueError, KeyError, IndexError, TypeError):
    return {"symbol": symbol, "label": label(symbol), "ok": False}

  meta = result.get("meta", {})
  price = meta.get("regularMarketPrice")
  previous = meta.get("chartPreviousClose") or meta.get("previousClose")
  percent = meta.get("regularMarketChangePercent")
  if percent is None and price is not None and previous:
    percent = (price - previous) / previous * 100
  change = price - previous if price is not None and previous else None
  closes = (result.get("indicators", {}).get("quote") or [{}])[0].get("close") or []
  points = [round(c, 4) for c in closes if c is not None]

  return {
    "symbol": symbol,
    "label": label(symbol),
    "name": (meta.get("longName") or meta.get("shortName") or "").strip(),
    "currency": meta.get("currency") or "",
    "type": meta.get("instrumentType") or "",
    "price": price,
    "previousClose": previous,
    "change": change,
    "changePercent": percent,
    "time": meta.get("regularMarketTime") or 0,
    "points": points,
    "ok": price is not None,
  }


def main():
  raw = sys.argv[1] if len(sys.argv) > 1 else "USDBRL=X"
  ttl = int(sys.argv[2]) if len(sys.argv) > 2 else 60
  symbols = list(dict.fromkeys(normalize(s) for s in raw.split(",") if s.strip()))

  cache = CACHE_DIR / "quotes.json"
  try:
    cached = json.loads(cache.read_text(encoding="utf-8"))
    if time.time() - cached.get("fetchedAt", 0) < ttl and cached.get("symbols") == symbols:
      print(json.dumps(cached))
      return
  except (OSError, ValueError, AttributeError):
    cached = None

  with ThreadPoolExecutor(max_workers=8) as pool:
    quotes = list(pool.map(fetch, symbols))

  # Keep the last good value for a symbol when one fetch fails (offline, rate limit).
  if cached and cached.get("symbols") == symbols:
    previous = {q["symbol"]: q for q in cached.get("quotes", [])}
    quotes = [q if q["ok"] or not previous.get(q["symbol"], {}).get("ok") else dict(previous[q["symbol"]], stale=True)
              for q in quotes]

  result = {"symbols": symbols, "quotes": quotes, "fetchedAt": time.time(), "ok": any(q["ok"] for q in quotes)}
  if result["ok"]:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache.write_text(json.dumps(result), encoding="utf-8")
  print(json.dumps(result))


if __name__ == "__main__":
  main()
