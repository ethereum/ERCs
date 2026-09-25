# finchip-daily-finance-brief

A FinChip Skill that generates an English **daily global finance briefing**:

1. **Global Asset Dashboard** — one page, symmetric 2×3 grid, **60 instruments** (10 each): Equity Indices, Blue Chips, FX, Commodities, Rates & Volatility, Crypto (top-10 by cap). 1-day changes color-coded, data-source line in the footer.
2. **Top 10 Global Political & Economic News** — ranked from multi-source RSS by keyword importance × source weight × recency (36-hour window, per-source diversity cap).
3. **Analysis** — one cohesive section, max 500 words. Uses the Anthropic API when `ANTHROPIC_API_KEY` is set; otherwise a deterministic rule-based engine (risk-on/off score, top movers, rates / dollar / gold / crypto cross-read).

Outputs `reportYYMMDD.md` (always) and `reportYYMMDD.pdf` (reportlab, FinChip design language).

## Repository layout

```
finchip-daily-finance-brief/
├── daily_finance_brief.py        # the skill (single file)
├── skill.json                    # FinChip invocation-contract manifest
├── requirements.txt
├── README.md
├── LICENSE                       # MIT
├── examples/
│   ├── input_empty.json          # {} -> all defaults (live data, md+pdf)
│   ├── input_md_only.json        # markdown only
│   └── input_demo_offline.json   # offline fixture mode (no network needed)
└── .github/workflows/test.yml    # CI: offline test + live smoke + daily schedule
```

## Quick start (EC2 / local)

```bash
git clone https://github.com/Sleipnirs/finchip-daily-finance-brief.git
cd finchip-daily-finance-brief
pip install -r requirements.txt
python daily_finance_brief.py examples/input_empty.json
```

Result JSON is printed to stdout; artifacts land in `./out/`:

```json
{
  "generated_at": "2026-07-04 22:05",
  "md_path": "./out/report260704.md",
  "pdf_path": "./out/report260704.pdf",
  "warnings": []
}
```

## Calling it directly (no clone)

The skill is a single file, so you can pull and run it in one line:

```bash
pip install requests feedparser reportlab yfinance
curl -sL https://raw.githubusercontent.com/Sleipnirs/finchip-daily-finance-brief/main/daily_finance_brief.py \
  | python - '{"format":"md"}'
```

## Input contract

The single positional argument is the input — a `.json` file path, an inline JSON string, or `-` for stdin. Omit it for defaults.

| Field | Type | Default | Meaning |
|---|---|---|---|
| `format` | `"md" \| "pdf" \| "both"` | `"both"` | which artifacts to produce |
| `out` | string | `"./out"` | output directory |
| `demo` | bool | `false` | offline fixture mode (testing) |
| `news_count` | int | `10` | number of headlines |

## HTTP mode (agent-callable endpoint)

```bash
python daily_finance_brief.py --serve --port 8787
```

| Endpoint | Purpose |
|---|---|
| `GET /run?format=both` | trigger a generation, returns result JSON |
| `GET /report.md`, `GET /report.pdf` | fetch **latest** artifacts |
| `GET /reportYYMMDD.md`, `GET /reportYYMMDD.pdf` | fetch a specific day |
| `GET /health` | liveness |

## Scheduling

**EC2 cron** (22:05 UTC after US close, weekdays):

```cron
5 22 * * 1-5 cd /opt/skills/finchip-daily-finance-brief && /usr/bin/python3 daily_finance_brief.py examples/input_empty.json
```

**GitHub Actions**: already wired — `.github/workflows/test.yml` runs the brief on the same schedule and uploads `out/` as a build artifact. Add repo secret `ANTHROPIC_API_KEY` (optional) to enable Claude-generated analysis in CI.

## Branding

The PDF header carries the FinChip logo. By default a vector recreation is drawn; to use the official logo, drop the PNG from finchip.ai into `assets/finchip-logo.png` — it will be picked up automatically.

## Data sources (all public, no auth required)

| Source | Role |
|---|---|
| Yahoo Finance (yfinance) | primary quotes: indices / stocks / FX / commodities / rates |
| Stooq CSV | per-instrument fallback |
| FRED (St. Louis Fed) | official fallback for US Treasury yields (10Y/5Y/30Y/3M) |
| CoinGecko public API | crypto 24h prices |
| MarketWatch, CNBC, BBC Business, Guardian Economics, Google News RSS | headlines |

Graceful degradation: each instrument and feed fails independently; the report is always produced and gaps are listed under "Run warnings".

## Environment variables (optional)

| Variable | Effect |
|---|---|
| `ANTHROPIC_API_KEY` | enables Claude-generated analysis section |
| `DFB_ANTHROPIC_MODEL` | override analysis model (default `claude-sonnet-4-6`) |

## License

MIT — see [LICENSE](LICENSE).

*Informational only — not investment advice.*
