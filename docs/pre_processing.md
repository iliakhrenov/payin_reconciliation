# Pre-processing

Everything done to the provider exports **before** dbt reads them.

Rule: `raw/` is immutable — nothing is ever written back into it. Pre-processing reads
from `raw/` and writes to `staged/`. dbt sources point at `staged/` where a staged copy
exists, and at `raw/` otherwise.

Scope is deliberately narrow: pre-processing makes the *bytes* trustworthy. Anything that
requires interpreting a value is a modelling decision and lives in dbt staging, recorded in
[`assumptions.md`](assumptions.md).

## Steps

### 1. PayPal EU — encoding normalization to UTF-8

PayPal EU exports in Windows-1252 (cp1252). Every other file is already UTF-8 and passes through untouched.

```bash
uv run python scripts/normalize_encoding.py \
  raw/paypal_eu_activity_20260601_20260703.csv \
  staged/paypal_eu_activity_20260601_20260703.csv
```

`scripts/normalize_encoding.py` detects the encoding (BOM, then a UTF-8 probe, then the declared cp1252), decodes it, and normalizes accents and line endings.

Three choices, each guarding a way the file goes wrong without anyone noticing:

- **UTF-8 is tried before cp1252.** If PayPal ever switches their export to UTF-8, forcing cp1252 on it turns `é` into `Ã©` — corrupt, but no error.
- **A byte that will not decode fails the run.** It means the declared encoding is wrong. Better a stopped pipeline than merchant names full of `�` and a reconciliation that half-works.
- **Accents are normalized (NFC).** The same character has two valid encodings; left mixed, they split joins into phantom duplicates.

Result: 1,894 rows, names intact (`Jürgen Müller`, `Søren Kjær`). Re-running on the output changes nothing, and an undecodable byte is confirmed to stop the run.
