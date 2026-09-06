# Pre-processing

`raw/` is immutable. One step runs before dbt, writing normalized copies to `staged/`:

```bash
uv run python scripts/prepare_inputs.py
```

dbt reads `staged/` only. Every file is decoded to UTF-8, accents normalized (NFC), line endings unified.

## Why

Two defects in the provider exports would otherwise corrupt the reconciliation silently:

- **PayPal EU ships Windows-1252, not UTF-8.** Read as UTF-8 it fails; read carelessly it mojibakes — `Jürgen` becomes `JÃ¼rgen`. Names then split joins into phantom duplicates.
- **Google Play's report preamble ends in a bare newline while every data row ends CRLF.** Mixed endings make DuckDB refuse the file outright. Found when the file would not load at all.

Three rules guard against the versions of this we have not seen yet:

- **UTF-8 is tried before the declared encoding.** If a provider switches to UTF-8, forcing the old encoding corrupts accents with no error.
- **A byte that will not decode stops the run.** Better a failed pipeline than merchant names full of `�` and a reconciliation that half-works.
- **Accents are normalized.** The same character has two valid encodings; left mixed, they split joins.

## Result

All 9 files load. Row counts after header removal:

| Source | Rows | Note |
| --- | --- | --- |
| payment_engine_log | 7,988 | |
| paypal_us_activity | 2,167 | |
| paypal_eu_activity | 1,893 | decoded cp1252 |
| adyen_payment_accounting | 3,413 | |
| dlocal_transactions | 1,319 | |
| google_play_earnings_202606 | 1,544 | preamble skipped |
| google_play_earnings_202607_partial | 78 | preamble skipped |
| fx_rates | 204 | |
| fee_schedule | 3 | adyen ×2, google_play ×1 |

`staged/_manifest.json` records the encoding used and a SHA-256 per file — the audit trail for which bytes were read.

## Left to dbt

Pre-processing makes the bytes readable, nothing more. These are interpretation, and are handled in staging with the calls recorded in [`assumptions.md`](assumptions.md):

PayPal EU decimal commas and mixed date formats · dLocal minor units, inverted FX direction and one duplicated export line · timezone alignment (Adyen Europe/Amsterdam, Google Play America/Los_Angeles → UTC) · provider status vocabularies.

Profiling a provider export before staging it follows the `profile-psp-export` skill (`.claude/skills/`); results land in `docs/profiling__<psp>.md`.
