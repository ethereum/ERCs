#!/usr/bin/env python3
"""
daily-finance-brief — FinChip Skill
===================================
Generates a daily global-finance briefing in English:

  Section 1  One-page dashboard of key asset moves
             (equity indices, blue chips, FX, commodities, crypto, rates & vol)
  Section 2  Top-10 global political / economic news of the day
  Section 3  Analysis paragraph (<= 500 words), Claude-generated if
             ANTHROPIC_API_KEY is set, otherwise rule-based fallback.

Outputs:  report.md  (always)  +  report.pdf  (unless --format md)

Invocation (the "call skill" API — input is a JSON file, string, or stdin):
    python daily_finance_brief.py                                # defaults
    python daily_finance_brief.py examples/input_empty.json
    python daily_finance_brief.py '{"format":"md","demo":true}'
    echo '{"format":"pdf"}' | python daily_finance_brief.py -
    python daily_finance_brief.py --serve --port 8787            # HTTP mode
        GET  /run?format=both&demo=0 -> JSON {md_path, pdf_path, generated_at}
        GET  /report.md  |  /report.pdf  |  /health

Dependencies: requests, feedparser, reportlab   (yfinance optional, preferred)
No API keys required. ANTHROPIC_API_KEY is optional (better analysis).
"""

from __future__ import annotations

import argparse
import datetime as dt
import html
import io
import json
import os
import re
import sys
import time
import traceback
from dataclasses import dataclass, field
from typing import Optional

import requests

# ----------------------------------------------------------------------------
# Configuration: instruments & sources
# ----------------------------------------------------------------------------

UA = {"User-Agent": "finchip-daily-brief/1.0 (+https://finchip.ai)"}

# (yahoo_symbol, display_name, stooq_symbol_or_None)
INSTRUMENTS: dict[str, list[tuple[str, str, Optional[str]]]] = {
    "Equity Indices": [
        ("^GSPC",     "S&P 500",        "^spx"),
        ("^IXIC",     "Nasdaq Comp.",   "^ndq"),
        ("^DJI",      "Dow Jones",      "^dji"),
        ("^FTSE",     "FTSE 100",       "^ftm"),
        ("^GDAXI",    "DAX 40",         "^dax"),
        ("^N225",     "Nikkei 225",     "^nkx"),
        ("^HSI",      "Hang Seng",      None),
        ("000001.SS", "Shanghai Comp.", None),
        ("^STOXX50E", "Euro Stoxx 50",  None),
        ("^NSEI",     "Nifty 50",       None),
    ],
    "Blue Chips": [
        ("AAPL",  "Apple",       "aapl.us"),
        ("MSFT",  "Microsoft",   "msft.us"),
        ("NVDA",  "NVIDIA",      "nvda.us"),
        ("AMZN",  "Amazon",      "amzn.us"),
        ("GOOGL", "Alphabet",    "googl.us"),
        ("META",  "Meta",        "meta.us"),
        ("TSM",   "TSMC",        "tsm.us"),
        ("JPM",   "JPMorgan",    "jpm.us"),
        ("BRK-B", "Berkshire B", "brk-b.us"),
        ("TSLA",  "Tesla",       "tsla.us"),
    ],
    "FX": [
        ("DX-Y.NYB", "US Dollar Index", None),
        ("EURUSD=X", "EUR/USD",         "eurusd"),
        ("USDJPY=X", "USD/JPY",         "usdjpy"),
        ("GBPUSD=X", "GBP/USD",         "gbpusd"),
        ("USDCNY=X", "USD/CNY",         "usdcny"),
        ("AUDUSD=X", "AUD/USD",         "audusd"),
        ("CHF=X",    "USD/CHF",         "usdchf"),
        ("CAD=X",    "USD/CAD",         "usdcad"),
        ("SGD=X",    "USD/SGD",         "usdsgd"),
        ("INR=X",    "USD/INR",         "usdinr"),
    ],
    "Commodities": [
        ("GC=F", "Gold",        "xauusd"),
        ("SI=F", "Silver",      "xagusd"),
        ("CL=F", "WTI Crude",   "cl.f"),
        ("BZ=F", "Brent Crude", None),
        ("HG=F", "Copper",      "hg.f"),
        ("NG=F", "Natural Gas", "ng.f"),
        ("PL=F", "Platinum",    "xptusd"),
        ("PA=F", "Palladium",   "xpdusd"),
        ("ZW=F", "Wheat",       None),
        ("ZC=F", "Corn",        None),
    ],
    "Rates & Volatility": [
        ("^TNX", "US 10Y Yield (%)",  "10usy.b"),
        ("^VIX", "VIX",               None),
        ("^FVX", "US 5Y Yield (%)",   None),
        ("^TYX", "US 30Y Yield (%)",  None),
        ("^IRX", "US 3M Yield (%)",   None),
        ("^VVIX", "VVIX",             None),
        ("^MOVE", "MOVE (Bond Vol)",  None),
        ("^SKEW", "SKEW (Tail Risk)", None),
        ("HYG",  "HYG (HY Credit)",   "hyg.us"),
        ("TLT",  "TLT (20Y+ Bonds)",  "tlt.us"),
    ],
}

# FRED official fallback series for US Treasury yields (no key required)
FRED_MAP = {"^TNX": "DGS10", "^FVX": "DGS5", "^TYX": "DGS30", "^IRX": "DTB3"}

# CoinGecko ids -> display names (top-10 by market cap, ex-stablecoins)
CRYPTO = [
    ("bitcoin",      "Bitcoin (BTC)"),
    ("ethereum",     "Ethereum (ETH)"),
    ("ripple",       "XRP"),
    ("binancecoin",  "BNB"),
    ("solana",       "Solana (SOL)"),
    ("dogecoin",     "Dogecoin (DOGE)"),
    ("cardano",      "Cardano (ADA)"),
    ("tron",         "TRON (TRX)"),
    ("avalanche-2",  "Avalanche (AVAX)"),
    ("chainlink",    "Chainlink (LINK)"),
]


NEWS_FEEDS = [
    # (url, source_name, source_weight)
    ("https://feeds.content.dowjones.io/public/rss/mw_topstories",      "MarketWatch", 1.0),
    ("https://www.cnbc.com/id/100003114/device/rss/rss.html",           "CNBC Top News", 1.0),
    ("https://www.cnbc.com/id/20910258/device/rss/rss.html",            "CNBC Economy", 1.1),
    ("https://feeds.bbci.co.uk/news/business/rss.xml",                  "BBC Business", 1.0),
    ("https://www.theguardian.com/business/economics/rss",              "Guardian Economics", 0.9),
    ("https://news.google.com/rss/search?q=(federal+reserve+OR+ECB+OR+inflation+OR+tariff+OR+treasury+yields)&hl=en-US&gl=US&ceid=US:en",
                                                                        "Google News (Macro)", 0.9),
    ("https://news.google.com/rss/headlines/section/topic/BUSINESS?hl=en-US&gl=US&ceid=US:en",
                                                                        "Google News (Business)", 0.8),
]

# keyword -> importance weight for news ranking
NEWS_KEYWORDS = {
    "federal reserve": 3.0, "fed ": 2.5, "fomc": 3.0, "rate cut": 3.0, "rate hike": 3.0,
    "interest rate": 2.5, "inflation": 2.5, "cpi": 2.5, "ppi": 2.0, "gdp": 2.5,
    "ecb": 2.5, "boj": 2.5, "bank of japan": 2.5, "pboc": 2.5, "bank of england": 2.0,
    "treasury": 2.0, "yield": 2.0, "bond": 1.5, "recession": 2.5, "stimulus": 2.0,
    "tariff": 2.8, "trade war": 2.8, "sanction": 2.3, "opec": 2.3, "oil": 1.5,
    "china": 1.8, "election": 1.8, "white house": 1.8, "congress": 1.5, "imf": 1.8,
    "earnings": 1.5, "default": 2.2, "bailout": 2.2, "layoff": 1.5, "jobs report": 2.5,
    "unemployment": 2.2, "nonfarm": 2.5, "crypto": 1.5, "bitcoin": 1.5, "etf": 1.5,
    "sec ": 1.8, "regulation": 1.5, "war": 2.0, "ceasefire": 2.0, "geopolit": 2.2,
    "dollar": 1.8, "currency": 1.5, "stock market": 1.5, "sell-off": 2.2, "rally": 1.8,
    "ai ": 1.5, "chip": 1.5, "semiconductor": 1.8,
}

ANTHROPIC_MODEL = os.environ.get("DFB_ANTHROPIC_MODEL", "claude-sonnet-4-6")

# ----------------------------------------------------------------------------
# Data structures
# ----------------------------------------------------------------------------

@dataclass
class Quote:
    name: str
    price: Optional[float] = None
    change_pct: Optional[float] = None   # 1-day % change
    ok: bool = False

@dataclass
class NewsItem:
    title: str
    source: str
    link: str
    published: str
    score: float = 0.0

@dataclass
class Brief:
    generated_at: str
    market: dict[str, list[Quote]] = field(default_factory=dict)
    news: list[NewsItem] = field(default_factory=list)
    analysis: str = ""
    analysis_engine: str = "rule-based"
    warnings: list[str] = field(default_factory=list)

# ----------------------------------------------------------------------------
# Market data fetchers
# ----------------------------------------------------------------------------

def _fetch_yfinance(symbols: list[str]) -> dict[str, tuple[float, float]]:
    """Return {symbol: (last_price, pct_change)} using yfinance if available."""
    out: dict[str, tuple[float, float]] = {}
    try:
        import yfinance as yf  # optional dependency
    except ImportError:
        return out
    try:
        data = yf.download(symbols, period="5d", interval="1d",
                           progress=False, group_by="ticker", threads=True)
        for sym in symbols:
            try:
                closes = (data[sym]["Close"] if len(symbols) > 1 else data["Close"]).dropna()
                if len(closes) >= 2:
                    last, prev = float(closes.iloc[-1]), float(closes.iloc[-2])
                    out[sym] = (last, (last / prev - 1.0) * 100.0)
            except Exception:
                continue
    except Exception:
        pass
    # per-symbol retry for anything the batch missed (e.g. sqlite cache
    # "database is locked" under threaded download)
    for sym in symbols:
        if sym in out:
            continue
        try:
            time.sleep(0.3)
            closes = yf.Ticker(sym).history(period="5d", interval="1d")["Close"].dropna()
            if len(closes) >= 2:
                last, prev = float(closes.iloc[-1]), float(closes.iloc[-2])
                out[sym] = (last, (last / prev - 1.0) * 100.0)
        except Exception:
            continue
    return out


def _fetch_stooq(stooq_sym: str) -> Optional[tuple[float, float]]:
    """Free CSV endpoint, no key. Returns (last, pct_change) or None."""
    url = f"https://stooq.com/q/d/l/?s={stooq_sym}&i=d"
    try:
        r = requests.get(url, headers=UA, timeout=10)
        text = r.text.strip()
        if not text.lower().startswith("date,"):
            return None            # rate-limit page / HTML error, not CSV
        rows = [ln.split(",") for ln in text.splitlines()[1:] if ln]
        closes = [float(row[4]) for row in rows[-3:] if len(row) >= 5]
        if len(closes) >= 2:
            last, prev = closes[-1], closes[-2]
            return last, (last / prev - 1.0) * 100.0
    except Exception:
        return None
    return None


def _fetch_coingecko() -> dict[str, tuple[float, float]]:
    ids = ",".join(cid for cid, _ in CRYPTO)
    url = ("https://api.coingecko.com/api/v3/simple/price"
           f"?ids={ids}&vs_currencies=usd&include_24hr_change=true")
    out: dict[str, tuple[float, float]] = {}
    try:
        r = requests.get(url, headers=UA, timeout=15)
        j = r.json()
        for cid, _name in CRYPTO:
            if cid in j and "usd" in j[cid]:
                out[cid] = (float(j[cid]["usd"]),
                            float(j[cid].get("usd_24h_change") or 0.0))
    except Exception:
        pass
    return out


def _fetch_fred(series: str) -> Optional[tuple[float, float]]:
    """US Treasury data from FRED (official, no key). Returns (last, pct_change)."""
    url = f"https://fred.stlouisfed.org/graph/fredgraph.csv?id={series}"
    try:
        r = requests.get(url, headers=UA, timeout=10)
        vals = []
        for ln in r.text.strip().splitlines()[1:]:
            parts = ln.split(",")
            if len(parts) == 2 and parts[1] not in (".", ""):
                vals.append(float(parts[1]))
        if len(vals) >= 2:
            last, prev = vals[-1], vals[-2]
            return last, (last / prev - 1.0) * 100.0
    except Exception:
        return None
    return None


def fetch_market(brief: Brief) -> None:
    all_yahoo = [sym for grp in INSTRUMENTS.values() for sym, _, _ in grp]
    yq = _fetch_yfinance(all_yahoo)
    if not yq:
        brief.warnings.append("yfinance unavailable or blocked; using Stooq fallback where possible")

    for group, items in INSTRUMENTS.items():
        quotes: list[Quote] = []
        for sym, name, stooq_sym in items:
            q = Quote(name=name)
            if sym in yq:
                q.price, q.change_pct, q.ok = yq[sym][0], yq[sym][1], True
            elif stooq_sym:
                res = _fetch_stooq(stooq_sym)
                if res:
                    q.price, q.change_pct, q.ok = res[0], res[1], True
            if not q.ok and sym in FRED_MAP:         # official FRED fallback for UST series
                res = _fetch_fred(FRED_MAP[sym])
                if res:
                    q.price, q.change_pct, q.ok = res[0], res[1], True
            if not q.ok:
                brief.warnings.append(f"no data: {name} ({sym})")
            quotes.append(q)
        brief.market[group] = quotes

    cg = _fetch_coingecko()
    crypto_quotes: list[Quote] = []
    for cid, name in CRYPTO:
        q = Quote(name=name)
        if cid in cg:
            q.price, q.change_pct, q.ok = cg[cid][0], cg[cid][1], True
        else:
            brief.warnings.append(f"no data: {name}")
        crypto_quotes.append(q)
    brief.market["Crypto"] = crypto_quotes

# ----------------------------------------------------------------------------
# News
# ----------------------------------------------------------------------------

def fetch_news(brief: Brief, top_n: int = 10) -> None:
    try:
        import feedparser
    except ImportError:
        brief.warnings.append("feedparser not installed; news section empty")
        return

    now = time.time()
    seen_titles: set[str] = set()
    items: list[NewsItem] = []

    for url, source, src_weight in NEWS_FEEDS:
        try:
            feed = feedparser.parse(url, request_headers=UA)
        except Exception:
            brief.warnings.append(f"feed failed: {source}")
            continue
        for e in feed.entries[:25]:
            title = html.unescape(getattr(e, "title", "")).strip()
            if not title:
                continue
            key = re.sub(r"\W+", "", title.lower())[:80]
            if key in seen_titles:
                continue
            seen_titles.add(key)

            published = getattr(e, "published", "") or getattr(e, "updated", "")
            ts = None
            for attr in ("published_parsed", "updated_parsed"):
                if getattr(e, attr, None):
                    ts = time.mktime(getattr(e, attr))
                    break
            age_h = (now - ts) / 3600.0 if ts else 24.0
            if age_h > 36:            # stale -> skip
                continue
            recency = max(0.0, 1.5 - age_h / 24.0)      # 0..1.5

            low = " " + title.lower() + " "
            kw = sum(w for k, w in NEWS_KEYWORDS.items() if k in low)

            items.append(NewsItem(
                title=title, source=source,
                link=getattr(e, "link", ""), published=published,
                score=(kw + 0.5) * src_weight + recency,
            ))

    items.sort(key=lambda x: x.score, reverse=True)
    # keep at most 2 per source for diversity
    per_src: dict[str, int] = {}
    picked: list[NewsItem] = []
    for it in items:
        if per_src.get(it.source, 0) >= 3:
            continue
        per_src[it.source] = per_src.get(it.source, 0) + 1
        picked.append(it)
        if len(picked) == top_n:
            break
    brief.news = picked
    if not picked:
        brief.warnings.append("no fresh news items collected")

# ----------------------------------------------------------------------------
# Analysis (Claude if key present, otherwise rule-based)
# ----------------------------------------------------------------------------

def _market_digest(brief: Brief) -> str:
    lines = []
    for group, quotes in brief.market.items():
        parts = [f"{q.name} {q.change_pct:+.2f}%" for q in quotes if q.ok and q.change_pct is not None]
        if parts:
            lines.append(f"{group}: " + ", ".join(parts))
    if brief.news:
        lines.append("Top headlines: " + " | ".join(n.title for n in brief.news[:6]))
    return "\n".join(lines)


def _claude_analysis(brief: Brief) -> Optional[str]:
    key = os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        return None
    prompt = (
        "You are a sell-side macro strategist. Based ONLY on the snapshot below, "
        "write ONE cohesive analysis section of AT MOST 500 words in English for a daily "
        "briefing: what drove today's moves, cross-asset signals (risk-on/off, rates vs. "
        "equities vs. dollar vs. gold vs. crypto), and 2-3 things to watch tomorrow. "
        "No bullet points, no headers, no preamble — just the paragraphs.\n\n"
        + _market_digest(brief)
    )
    try:
        r = requests.post(
            "https://api.anthropic.com/v1/messages",
            headers={"x-api-key": key, "anthropic-version": "2023-06-01",
                     "content-type": "application/json"},
            json={"model": ANTHROPIC_MODEL, "max_tokens": 900,
                  "messages": [{"role": "user", "content": prompt}]},
            timeout=60,
        )
        j = r.json()
        text = " ".join(b.get("text", "") for b in j.get("content", []) if b.get("type") == "text").strip()
        return text or None
    except Exception:
        brief.warnings.append("Claude analysis call failed; using rule-based fallback")
        return None


def _rule_based_analysis(brief: Brief) -> str:
    def chg(group: str, name: str) -> Optional[float]:
        for q in brief.market.get(group, []):
            if q.name == name and q.ok:
                return q.change_pct
        return None

    all_q = [q for qs in brief.market.values() for q in qs if q.ok and q.change_pct is not None]
    if not all_q:
        return ("Market data could not be retrieved for this session, so no cross-asset "
                "read is available. Refer to the headlines above for the day's key drivers.")

    movers = sorted(all_q, key=lambda q: abs(q.change_pct), reverse=True)[:3]
    eq = [q.change_pct for q in brief.market.get("Equity Indices", []) if q.ok]
    eq_avg = sum(eq) / len(eq) if eq else 0.0
    vix = chg("Rates & Volatility", "VIX")
    tnx = chg("Rates & Volatility", "US 10Y Yield (%)")
    dxy = chg("FX", "US Dollar Index")
    gold = chg("Commodities", "Gold")
    btc = chg("Crypto", "Bitcoin (BTC)")

    risk = 0.0
    risk += 1 if eq_avg > 0.15 else (-1 if eq_avg < -0.15 else 0)
    if vix is not None:  risk += -1 if vix > 3 else (1 if vix < -3 else 0)
    if btc is not None:  risk += 0.5 if btc > 1 else (-0.5 if btc < -1 else 0)
    if gold is not None: risk += -0.5 if gold > 0.8 else 0
    tone = "risk-on" if risk >= 1 else ("risk-off" if risk <= -1 else "mixed")

    p1 = (f"Global markets closed the session with a {tone} tone. Major equity indices "
          f"averaged {eq_avg:+.2f}% on the day, with the largest single moves coming from "
          + ", ".join(f"{m.name} ({m.change_pct:+.2f}%)" for m in movers) + ". ")
    p2 = ""
    if tnx is not None or dxy is not None:
        p2 = ("In rates and currencies, the US 10-year yield moved "
              f"{tnx:+.2f}% " if tnx is not None else "") + \
             (f"while the dollar index changed {dxy:+.2f}%. " if dxy is not None else "")
    p3 = ""
    if gold is not None or btc is not None:
        p3 = ("Across alternative stores of value, gold "
              f"{'gained' if (gold or 0) >= 0 else 'fell'} {abs(gold or 0):.2f}% " if gold is not None else "") + \
             (f"and bitcoin moved {btc:+.2f}% over 24 hours, " if btc is not None else "") + \
             "keeping the hedging complex consistent with the broader tone. "
    p4 = ("Headlines centered on " + "; ".join(n.title for n in brief.news[:3]) + ". "
          if brief.news else "")
    p5 = ("Watch tomorrow: follow-through in the day's biggest movers, any central-bank "
          "commentary that could reprice rate expectations, and whether volatility confirms "
          "or fades today's direction.")
    return (p1 + p2 + p3 + p4 + p5).strip()


def build_analysis(brief: Brief) -> None:
    text = _claude_analysis(brief)
    if text:
        brief.analysis, brief.analysis_engine = text, f"claude ({ANTHROPIC_MODEL})"
    else:
        brief.analysis, brief.analysis_engine = _rule_based_analysis(brief), "rule-based"

# ----------------------------------------------------------------------------
# Renderers
# ----------------------------------------------------------------------------

def _fmt_price(q: Quote) -> str:
    if not q.ok or q.price is None:
        return "—"
    p = q.price
    return f"{p:,.4f}" if p < 10 else (f"{p:,.2f}" if p < 100000 else f"{p:,.0f}")


def _fmt_chg(q: Quote) -> str:
    return f"{q.change_pct:+.2f}%" if (q.ok and q.change_pct is not None) else "—"


def render_markdown(brief: Brief) -> str:
    d = brief.generated_at
    out = [f"# Daily Global Finance Brief", f"*Generated {d} (UTC) — FinChip Skill `daily-finance-brief`*", ""]
    out += ["## 1 · Global Asset Dashboard", ""]
    for group, quotes in brief.market.items():
        out += [f"### {group}", "", "| Asset | Last | 1D Change |", "|---|---:|---:|"]
        for q in quotes:
            arrow = "" if not q.ok else ("🟢 " if (q.change_pct or 0) > 0 else ("🔴 " if (q.change_pct or 0) < 0 else "⚪ "))
            out.append(f"| {q.name} | {_fmt_price(q)} | {arrow}{_fmt_chg(q)} |")
        out.append("")
    out += ["## 2 · Top 10 Global Political & Economic News", ""]
    if brief.news:
        for i, n in enumerate(brief.news, 1):
            out.append(f"{i}. **{n.title}** — *{n.source}*" + (f" ([link]({n.link}))" if n.link else ""))
    else:
        out.append("_No fresh headlines were collected in this run._")
    out += ["", "## 3 · Analysis", "", brief.analysis, "",
            f"---", f"*Analysis engine: {brief.analysis_engine}. Sources: Yahoo Finance / Stooq, "
            f"CoinGecko, MarketWatch, CNBC, BBC, The Guardian, Google News. "
            f"Informational only — not investment advice.*"]
    if brief.warnings:
        out += ["", "<details><summary>Run warnings</summary>", ""]
        out += [f"- {w}" for w in brief.warnings] + ["", "</details>"]
    return "\n".join(out) + "\n"


def _draw_logo(canvas, x: float, y: float, h: float) -> float:
    """Draw the FinChip logo at (x, y baseline) with icon height h.
    Uses assets/finchip-logo.png if present; otherwise a vector recreation.
    Returns total width drawn."""
    from reportlab.lib import colors
    AZURE, COBALT = colors.HexColor("#00C0F8"), colors.HexColor("#0080F8")
    here = os.path.dirname(os.path.abspath(__file__))
    for p in (os.path.join(here, "assets", "finchip-logo.png"), "assets/finchip-logo.png"):
        if os.path.isfile(p):
            try:
                from reportlab.lib.utils import ImageReader
                img = ImageReader(p)
                iw, ih = img.getSize()
                w = h * iw / ih
                canvas.drawImage(img, x, y, width=w, height=h, mask="auto")
                return w
            except Exception:
                break
    # --- vector fallback: rounded icon with stylized F + wordmark ---
    canvas.saveState()
    canvas.setFillColor(colors.white)
    canvas.setStrokeColor(colors.HexColor("#CFE4FB")); canvas.setLineWidth(0.9)
    canvas.roundRect(x, y, h, h, h * 0.24, stroke=1, fill=1)
    ix, iy, s = x + h * 0.22, y + h * 0.16, h * 0.62   # F glyph box
    sk = s * 0.14                                       # italic skew
    p = canvas.beginPath()                              # top bar (azure)
    p.moveTo(ix + sk, iy + s); p.lineTo(ix + sk + s * 0.78, iy + s)
    p.lineTo(ix + sk + s * 0.70, iy + s * 0.74); p.lineTo(ix + sk * 0.72, iy + s * 0.74); p.close()
    canvas.setFillColor(AZURE); canvas.drawPath(p, stroke=0, fill=1)
    p = canvas.beginPath()                              # middle bar (cobalt)
    p.moveTo(ix + sk * 0.55, iy + s * 0.58); p.lineTo(ix + sk * 0.55 + s * 0.56, iy + s * 0.58)
    p.lineTo(ix + sk * 0.40 + s * 0.50, iy + s * 0.34); p.lineTo(ix + sk * 0.30, iy + s * 0.34); p.close()
    canvas.setFillColor(COBALT); canvas.drawPath(p, stroke=0, fill=1)
    p = canvas.beginPath()                              # stem (azure)
    p.moveTo(ix + sk, iy + s); p.lineTo(ix + sk * 0.72 + s * 0.26, iy + s)
    p.lineTo(ix + s * 0.20, iy); p.lineTo(ix, iy); p.close()
    canvas.setFillColor(AZURE); canvas.drawPath(p, stroke=0, fill=1)
    fs = h * 0.60                                       # wordmark
    tx = x + h * 1.22
    canvas.setFont("Helvetica-Bold", fs)
    canvas.setFillColor(AZURE); canvas.drawString(tx, y + h * 0.24, "FinChip")
    w1 = canvas.stringWidth("FinChip", "Helvetica-Bold", fs)
    canvas.setFillColor(COBALT); canvas.drawString(tx + w1, y + h * 0.24, ".AI")
    w2 = canvas.stringWidth(".AI", "Helvetica-Bold", fs)
    canvas.restoreState()
    return h * 1.22 + w1 + w2


def render_pdf(brief: Brief, path: str) -> None:
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
    from reportlab.lib.units import mm
    from reportlab.platypus import (BaseDocTemplate, Frame, PageTemplate,
                                    Paragraph, Spacer, Table, TableStyle,
                                    NextPageTemplate, PageBreak)

    # Palette extracted from the official FinChip logo (assets/finchip-logo.png):
    #   wordmark blue #0098F8 | icon gradient #00C0F8 -> #0080F8 | light accent #88C8F8 | plate #E8F0F8
    BRAND  = colors.HexColor("#0098F8")   # primary FinChip blue (wordmark)
    DEEP   = colors.HexColor("#0080F8")   # gradient dark end
    CYAN   = colors.HexColor("#00C0F8")   # gradient light end / hairlines
    SOFT   = colors.HexColor("#88C8F8")   # light accent
    SKY    = colors.HexColor("#E8F0F8")   # plate / zebra rows (logo plate color)
    PAGE   = colors.HexColor("#F5FAFD")   # page wash (plate tinted toward white)
    INK    = colors.HexColor("#16324F")   # body text, blue-slate
    MUTE   = colors.HexColor("#6E96B8")   # secondary text, blue-grey
    UP, DOWN, BORDER = colors.HexColor("#0B8A3E"), colors.HexColor("#C0392B"), colors.HexColor("#C7E6FC")

    styles = getSampleStyleSheet()
    s_title = ParagraphStyle("t", parent=styles["Title"], fontSize=18, textColor=BRAND,
                             alignment=0, spaceAfter=1)
    s_sub   = ParagraphStyle("s", parent=styles["Normal"], fontSize=8.5, textColor=MUTE)
    s_h2    = ParagraphStyle("h2", parent=styles["Heading2"], fontSize=13, textColor=BRAND, spaceBefore=4)
    s_cell  = ParagraphStyle("c", parent=styles["Normal"], fontSize=8.3, leading=10.5, textColor=INK)
    s_body  = ParagraphStyle("b", parent=styles["Normal"], fontSize=9.5, leading=13.5, textColor=INK)
    s_news  = ParagraphStyle("n", parent=styles["Normal"], fontSize=9.5, leading=13, textColor=INK, spaceAfter=4)
    s_foot  = ParagraphStyle("f", parent=styles["Normal"], fontSize=7, textColor=colors.HexColor("#7A8CA3"))

    SOURCES_LINE = ("Data: Yahoo Finance \u00b7 Stooq \u00b7 FRED (St. Louis Fed) \u00b7 CoinGecko   |   "
                    "News: MarketWatch \u00b7 CNBC \u00b7 BBC \u00b7 The Guardian \u00b7 Google News   |   "
                    "finchip.ai \u00b7 Informational only, not investment advice")

    def _chrome(canvas, doc, with_sources_footer: bool):
        canvas.saveState()
        canvas.setFillColor(PAGE)                                   # sky page wash
        canvas.rect(0, 0, A4[0], A4[1], stroke=0, fill=1)
        canvas.setFillColor(colors.white)                           # header band
        canvas.rect(0, A4[1] - 18 * mm, A4[0], 18 * mm, stroke=0, fill=1)
        canvas.setFillColor(CYAN)                                   # brand hairline
        canvas.rect(0, A4[1] - 18.7 * mm, A4[0], 0.7 * mm, stroke=0, fill=1)
        _draw_logo(canvas, 14 * mm, A4[1] - 14.6 * mm, 8.2 * mm)
        canvas.setFillColor(MUTE); canvas.setFont("Helvetica-Bold", 8.5)
        canvas.drawRightString(A4[0] - 14 * mm, A4[1] - 9.2 * mm, "DAILY GLOBAL FINANCE BRIEF")
        canvas.setFillColor(INK); canvas.setFont("Helvetica", 8)
        canvas.drawRightString(A4[0] - 14 * mm, A4[1] - 13.6 * mm, f"{brief.generated_at} UTC")
        if with_sources_footer:
            canvas.setFillColor(colors.HexColor("#7A8CA3")); canvas.setFont("Helvetica", 6.6)
            canvas.drawCentredString(A4[0] / 2, 7.5 * mm, SOURCES_LINE)
        canvas.restoreState()

    def chrome_dash(canvas, doc): _chrome(canvas, doc, True)
    def chrome_text(canvas, doc): _chrome(canvas, doc, False)

    doc = BaseDocTemplate(path, pagesize=A4,
                          leftMargin=13 * mm, rightMargin=13 * mm,
                          topMargin=22 * mm, bottomMargin=13 * mm)
    gap = 5 * mm
    colw = (A4[0] - 26 * mm - gap) / 2
    f1 = Frame(13 * mm, 13 * mm, colw, A4[1] - 35 * mm, id="c1")
    f2 = Frame(13 * mm + colw + gap, 13 * mm, colw, A4[1] - 35 * mm, id="c2")
    full = Frame(13 * mm, 13 * mm, A4[0] - 26 * mm, A4[1] - 35 * mm, id="full")
    doc.addPageTemplates([PageTemplate(id="dash", frames=[f1, f2], onPage=chrome_dash),
                          PageTemplate(id="text", frames=[full], onPage=chrome_text)])

    def qtable(group: str, quotes: list[Quote]):
        data = [[Paragraph(f'<font color="white"><b>{html.escape(group)}</b></font>', s_cell), "", ""]]
        for q in quotes:
            data.append([Paragraph(html.escape(q.name), s_cell), _fmt_price(q), _fmt_chg(q)])
        t = Table(data, colWidths=[colw * 0.50, colw * 0.28, colw * 0.22])
        style = [
            ("SPAN", (0, 0), (-1, 0)),
            ("BACKGROUND", (0, 0), (-1, 0), BRAND),
            ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, SKY]),
            ("FONTSIZE", (1, 1), (-1, -1), 8.3),
            ("FONTNAME", (1, 1), (1, -1), "Helvetica"),
            ("ALIGN", (1, 1), (-1, -1), "RIGHT"),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("TEXTCOLOR", (1, 1), (1, -1), INK),
            ("TOPPADDING", (0, 1), (-1, -1), 2.2), ("BOTTOMPADDING", (0, 1), (-1, -1), 2.2),
            ("TOPPADDING", (0, 0), (-1, 0), 3.2), ("BOTTOMPADDING", (0, 0), (-1, 0), 3.2),
            ("LEFTPADDING", (0, 0), (0, -1), 6),
            ("LINEBELOW", (0, 0), (-1, 0), 1.0, CYAN),
            ("BOX", (0, 0), (-1, -1), 0.7, BORDER),
            ("LINEBELOW", (0, -1), (-1, -1), 0.7, BORDER),
        ]
        for i, q in enumerate(quotes, start=1):
            c = UP if (q.ok and (q.change_pct or 0) > 0) else (DOWN if (q.ok and (q.change_pct or 0) < 0) else INK)
            style.append(("TEXTCOLOR", (2, i), (2, i), c))
            style.append(("FONTNAME", (2, i), (2, i), "Helvetica-Bold"))
        t.setStyle(TableStyle(style))
        return t

    # symmetric 2x3 grid: left column = Equity / FX / Rates, right = Blue Chips / Commodities / Crypto
    LEFT  = ["Equity Indices", "FX", "Rates & Volatility"]
    RIGHT = ["Blue Chips", "Commodities", "Crypto"]

    story = [Paragraph("Global Asset Dashboard", s_title),
             Paragraph("Section 1 \u00b7 One-day moves across major asset classes \u00b7 10 instruments per class", s_sub),
             Spacer(1, 5)]
    for g in LEFT:
        story += [qtable(g, brief.market.get(g, [])), Spacer(1, 6)]
    # jump to right frame at matching height: pad to top with same title-block height
    from reportlab.platypus import FrameBreak
    story += [FrameBreak(),
              Spacer(1, s_title.fontSize + s_sub.fontSize + 25.5)]
    for g in RIGHT:
        story += [qtable(g, brief.market.get(g, [])), Spacer(1, 6)]

    story += [NextPageTemplate("text"), PageBreak(),
              Paragraph("Top 10 Global Political &amp; Economic News", s_h2), Spacer(1, 2)]
    if brief.news:
        for i, n in enumerate(brief.news, 1):
            story.append(Paragraph(
                f"<b>{i}.</b> {html.escape(n.title)} "
                f'<font size="8" color="#5B7898">\u2014 {html.escape(n.source)}</font>', s_news))
    else:
        story.append(Paragraph("No fresh headlines were collected in this run.", s_body))

    story += [Spacer(1, 8), Paragraph("Analysis", s_h2), Spacer(1, 2)]
    for para in brief.analysis.split("\n\n"):
        story += [Paragraph(html.escape(para), s_body), Spacer(1, 4)]

    story += [Spacer(1, 10), Paragraph(
        f"Analysis engine: {brief.analysis_engine}. " + SOURCES_LINE, s_foot)]
    doc.build(story)

# ----------------------------------------------------------------------------
# Demo fixtures (offline test mode)
# ----------------------------------------------------------------------------

def load_demo(brief: Brief) -> None:
    fx = {
        "Equity Indices": [("S&P 500", 6489.22, 0.84), ("Nasdaq Comp.", 21440.15, 1.22),
                           ("Dow Jones", 45102.60, 0.41), ("FTSE 100", 8890.34, -0.18),
                           ("DAX 40", 24310.55, 0.35), ("Nikkei 225", 42780.90, 1.05),
                           ("Hang Seng", 24890.44, -0.62), ("Shanghai Comp.", 3455.87, -0.21),
                           ("Euro Stoxx 50", 5388.10, 0.22), ("Nifty 50", 25640.35, 0.68)],
        "Blue Chips": [("Apple", 244.31, 0.62), ("Microsoft", 512.44, 1.10),
                       ("NVIDIA", 176.02, 2.85), ("Amazon", 231.77, 0.95),
                       ("Alphabet", 201.15, 0.44), ("Meta", 742.60, -0.35),
                       ("TSMC", 228.90, 1.75), ("JPMorgan", 291.33, 0.28),
                       ("Berkshire B", 489.05, 0.15), ("Tesla", 318.42, -1.62)],
        "FX": [("US Dollar Index", 97.42, -0.33), ("EUR/USD", 1.1842, 0.31),
               ("USD/JPY", 143.85, -0.42), ("GBP/USD", 1.3722, 0.18), ("USD/CNY", 7.1420, -0.05),
               ("AUD/USD", 0.6588, 0.24), ("USD/CHF", 0.7925, -0.15),
               ("USD/CAD", 1.3610, 0.08), ("USD/SGD", 1.2735, -0.11), ("USD/INR", 85.52, 0.06)],
        "Commodities": [("Gold", 3348.50, 0.72), ("Silver", 37.05, 1.34),
                        ("WTI Crude", 66.42, -1.85), ("Brent Crude", 68.51, -1.62), ("Copper", 5.12, 0.88),
                        ("Natural Gas", 3.42, 2.10), ("Platinum", 1388.60, 0.95),
                        ("Palladium", 1142.30, -0.44), ("Wheat", 548.25, 0.36), ("Corn", 412.50, -0.72)],
        "Rates & Volatility": [("US 10Y Yield (%)", 4.34, -1.10), ("VIX", 16.42, -4.20),
                               ("US 5Y Yield (%)", 3.92, -0.85), ("US 30Y Yield (%)", 4.86, -0.62),
                               ("US 3M Yield (%)", 4.28, 0.05), ("VVIX", 92.40, -2.15),
                               ("MOVE (Bond Vol)", 88.60, -1.40), ("SKEW (Tail Risk)", 148.22, 0.85),
                               ("HYG (HY Credit)", 80.15, 0.22), ("TLT (20Y+ Bonds)", 89.44, 0.65)],
        "Crypto": [("Bitcoin (BTC)", 108420.0, 2.15), ("Ethereum (ETH)", 2588.4, 3.42),
                   ("XRP", 2.28, 1.85), ("BNB", 662.3, 1.22),
                   ("Solana (SOL)", 152.7, 4.10), ("Dogecoin (DOGE)", 0.1685, 2.92),
                   ("Cardano (ADA)", 0.5840, 1.05), ("TRON (TRX)", 0.2870, 0.44),
                   ("Avalanche (AVAX)", 18.25, 3.15), ("Chainlink (LINK)", 13.42, 2.36)],
    }
    for group, rows in fx.items():
        brief.market[group] = [Quote(name=n, price=p, change_pct=c, ok=True) for n, p, c in rows]
    demo_news = [
        ("US June payrolls beat expectations, tempering hopes for a September rate cut", "CNBC Economy"),
        ("Treasury yields slip as markets weigh mixed signals from Fed officials", "MarketWatch"),
        ("EU and US negotiators race to close framework trade deal before tariff deadline", "BBC Business"),
        ("Congress passes sweeping tax-and-spending bill; deficit projections in focus", "Google News (Macro)"),
        ("Oil falls ahead of OPEC+ meeting expected to approve another supply increase", "MarketWatch"),
        ("Dollar heads for worst first half in decades as reserve managers diversify", "Guardian Economics"),
        ("Nvidia nears record valuation as AI capex cycle shows no sign of slowing", "CNBC Top News"),
        ("China services PMI cools, adding pressure for further stimulus in H2", "Google News (Business)"),
        ("Bitcoin tops $108,000 as spot-ETF inflows accelerate for a third week", "CNBC Top News"),
        ("ECB minutes show growing debate over the pace of further easing", "Guardian Economics"),
    ]
    brief.news = [NewsItem(title=t, source=s, link="", published="") for t, s in demo_news]
    brief.warnings.append("DEMO MODE: fixture data, not live quotes")

# ----------------------------------------------------------------------------
# Skill entrypoints
# ----------------------------------------------------------------------------

def run_skill(fmt: str = "both", out_dir: str = "./out", demo: bool = False,
              news_count: int = 10) -> dict:
    os.makedirs(out_dir, exist_ok=True)
    brief = Brief(generated_at=dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M"))
    if demo:
        load_demo(brief)
    else:
        fetch_market(brief)
        fetch_news(brief, top_n=news_count)
    build_analysis(brief)

    stamp = dt.datetime.now(dt.timezone.utc).strftime("%y%m%d")
    result = {"generated_at": brief.generated_at, "warnings": brief.warnings}
    if fmt in ("md", "both"):
        md_path = os.path.join(out_dir, f"report{stamp}.md")
        with open(md_path, "w", encoding="utf-8") as f:
            f.write(render_markdown(brief))
        result["md_path"] = md_path
    if fmt in ("pdf", "both"):
        pdf_path = os.path.join(out_dir, f"report{stamp}.pdf")
        render_pdf(brief, pdf_path)
        result["pdf_path"] = pdf_path
    return result


def serve(port: int, out_dir: str) -> None:
    from http.server import BaseHTTPRequestHandler, HTTPServer
    from urllib.parse import urlparse, parse_qs

    class H(BaseHTTPRequestHandler):
        def do_GET(self):
            u = urlparse(self.path)
            try:
                if u.path == "/run":
                    fmt = parse_qs(u.query).get("format", ["both"])[0]
                    demo = parse_qs(u.query).get("demo", ["0"])[0] == "1"
                    res = run_skill(fmt=fmt, out_dir=out_dir, demo=demo)
                    body = json.dumps(res).encode()
                    self.send_response(200); self.send_header("Content-Type", "application/json")
                elif re.fullmatch(r"/report(\d{6})?\.(md|pdf)", u.path):
                    ext = u.path.rsplit(".", 1)[1]
                    name = u.path.lstrip("/")
                    p = os.path.join(out_dir, name)
                    if not re.fullmatch(r"report\d{6}\." + ext, name):
                        # bare /report.md or /report.pdf -> latest dated file
                        import glob
                        cand = sorted(glob.glob(os.path.join(out_dir, f"report[0-9][0-9][0-9][0-9][0-9][0-9].{ext}")))
                        if not cand:
                            raise FileNotFoundError(f"no report*.{ext} generated yet")
                        p = cand[-1]
                    with open(p, "rb") as f:
                        body = f.read()
                    ctype = "text/markdown" if ext == "md" else "application/pdf"
                    self.send_response(200); self.send_header("Content-Type", ctype)
                elif u.path == "/health":
                    body = b'{"ok":true,"skill":"daily-finance-brief"}'
                    self.send_response(200); self.send_header("Content-Type", "application/json")
                else:
                    body = b'{"error":"not found"}'
                    self.send_response(404); self.send_header("Content-Type", "application/json")
            except Exception as e:
                body = json.dumps({"error": str(e)}).encode()
                self.send_response(500); self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers(); self.wfile.write(body)

        def log_message(self, *a):  # quiet
            pass

    print(f"daily-finance-brief serving on :{port}  (GET /run, /report.md, /report.pdf, /health)")
    HTTPServer(("0.0.0.0", port), H).serve_forever()


DEFAULT_INPUT = {"format": "both", "out": "./out", "demo": False, "news_count": 10}


def _load_input(arg: Optional[str]) -> dict:
    """Accept: nothing (defaults) | path to .json file | inline JSON string | '-' (stdin)."""
    cfg = dict(DEFAULT_INPUT)
    if not arg:
        return cfg
    if arg == "-":
        cfg.update(json.load(sys.stdin) or {})
    elif os.path.isfile(arg):
        with open(arg, "r", encoding="utf-8") as f:
            cfg.update(json.load(f) or {})
    else:
        cfg.update(json.loads(arg))
    return cfg


def main() -> int:
    ap = argparse.ArgumentParser(
        description="FinChip skill: daily global finance brief",
        epilog=("Examples:  python daily_finance_brief.py examples/input_empty.json | "
                "python daily_finance_brief.py '{\"format\":\"md\",\"demo\":true}' | "
                "python daily_finance_brief.py --serve --port 8787"))
    ap.add_argument("input", nargs="?", default=None,
                    help="path to input .json, inline JSON string, or '-' for stdin (omit for defaults)")
    ap.add_argument("--serve", action="store_true", help="run as HTTP endpoint instead of one-shot")
    ap.add_argument("--port", type=int, default=8787)
    args = ap.parse_args()

    if args.serve:
        out_dir = _load_input(args.input).get("out", "./out")
        serve(args.port, out_dir)
        return 0
    try:
        cfg = _load_input(args.input)
        res = run_skill(fmt=cfg.get("format", "both"),
                        out_dir=cfg.get("out", "./out"),
                        demo=bool(cfg.get("demo", False)),
                        news_count=int(cfg.get("news_count", 10)))
        print(json.dumps(res, indent=2))
        return 0
    except Exception:
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
