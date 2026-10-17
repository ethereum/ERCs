# Daily Global Finance Brief — Production Task

Produce one edition of the FinChip daily global finance brief for the date given in
`spec/brief-request.yaml`.

## Demanded work

- A branded PDF/Markdown report covering a 60-instrument asset dashboard (equity
  indices, blue chips, FX, commodities, rates & volatility, top-10 crypto), the
  top-10 political/economic headlines of that date, and an analysis section of at
  most 500 words.
- All figures MUST be sourced as of that date's close and be reproducible from the
  sources listed in the spec.
- The deliverable MUST be packaged as a content-addressed object graph; `resultHash`
  submitted on-chain MUST be the SHA-256 of its canonical root. A deliverable
  published as an ERC-8338 skill package is preferred: cite its packageHash.

## Judgment

Completions are judged by the committed harness in `acceptance/harness.py`
(profile `x-pytest-v1`): structural checks on the dashboard, headline count,
and analysis word limit. See `fulfillment.json` for the tender shape.
