# Payin reconciliation — June 2026

Reconciles five payment providers (PayPal US/EU, dLocal, Adyen, Google Play) against the payment backend log for June 2026. Every dollar of difference is matched, explained with a root cause, or listed as unexplained — and the three add up.

**Result: $127,062.78 net receipts. $205,576.14 of total absolute discrepancy, fully classified. $0.00 unexplained.**

### Start here

| You are | Read |
| --- | --- |
| **CFO / finance** | **[docs/cfo_summary_2026-06.md](docs/cfo_summary_2026-06.md)** — numbers first, one page, skimmable |
| **Analyst / engineer** | **[exports/recon_summary_2026-06.csv](exports/recon_summary_2026-06.csv)** — provider × scope × cause, then [the SQL](models/) |
| **Whoever has to fix things** | **[docs/action_items.md](docs/action_items.md)** — 18 items, owned, ranked by dollars |

## Quickstart

```bash
uv sync
uv run python scripts/prepare_inputs.py   # raw/ -> staged/, decode + normalize. required first.
uv run dbt build                          # 13 models, 153 tests, writes both CSVs
```

Two commands from a clean clone. `dbt build` regenerates `exports/recon_summary_2026-06.csv` byte-identically — the CSV in this repo is not hand-made and cannot drift from the model.

**`staged/` is gitignored and `dbt build` will fail without step one.** `raw/` is immutable and the only committed input.

No database to install — DuckDB runs in-process against `payin.duckdb`. `profiles.yml` is in the repo root; dbt picks it up from the working directory.

## How it works

```
raw/  ──prepare_inputs.py──>  staged/  ──dbt──>  staging  ->  intermediate  ->  marts  ->  exports/*.csv
```

Both CSVs in `exports/` are written by post-hooks, so neither can drift from the model. The waterfall table in the CFO summary is regenerated from the second one:

```bash
uv run python scripts/render_waterfall.py     # prints the markdown table, byte-identical to the doc
```

| Layer | What it does |
| --- | --- |
| `models/staging/` | One model per provider. Normalizes each export's own dialect into a common shape and derives a `match_key` from its **own** columns only — neither side ever reads the other's, so the two remain independent. |
| `models/intermediate/` | `int__engine_log_fx_corrected` restates the backend's FX faults · `int__psp_transactions` unions the providers and applies contracted fees · `int__recon_matched` full-outer-joins the two sides · `int__recon_classified` assigns a root cause to every row. |
| `models/marts/` | `mart__recon_summary` — the deliverable, at provider × scope × cause · `mart__recon_waterfall` — the CFO summary's opening table, derived from the summary's own scope bases. |

**Three scopes, three different counterparties**, and they never net against each other:

- `backend_fx` — the backend against itself (its own FX booking errors)
- `gross` — the backend against the provider
- `fees` — the provider against the contracted rate

## Reading guide

Skimming the SQL cold, the four files that carry the actual thinking:

1. **[`int__recon_classified.sql`](models/intermediate/int__recon_classified.sql)** — the cause taxonomy. An ordered branch chain; order is load-bearing, and the comments say why each branch sits where it does.
2. **[`stg__payment_log_paypal.sql`](models/staging/stg__payment_log_paypal.sql)** — two accounts, two file dialects, one model. Also the mixed-date-format fix.
3. **[`stg__fx_rates.sql`](models/staging/stg__fx_rates.sql)** — the as-of pricing rule that both sides are held to.
4. **[`mart__recon_summary.sql`](models/marts/mart__recon_summary.sql)** — the output grain and the materiality bases.

Cause names state **who is claiming what**: `psp_claims_*` is the provider asserting something the backend does not, `engine_claims_*` the reverse, `engine_fx_*` the backend's own booking at fault. The prefix alone tells you which side to go and ask.

**153 tests.** Most assert a property rather than count rows. Three carry the report:

- **`assert_recon_buckets_reconcile`** — per provider and scope, matched + explained + unexplained must equal a control total recomputed from the transaction rows. If a dollar goes missing between the buckets, the build fails.
- **`assert_recon_waterfall_closes`** — what the backend booked, plus its own FX faults, plus the provider variance, must equal what the provider says it took.
- **`assert_recon_grain`** — one row per provider, match key and operation. A fan-out in the join would inflate every figure downstream and nothing else would notice.

## Docs

| | |
| --- | --- |
| [cfo_summary_2026-06.md](docs/cfo_summary_2026-06.md) | The deliverable |
| [action_items.md](docs/action_items.md) | What needs fixing, by whom, ranked |
| [assumptions.md](docs/assumptions.md) | Every call made where the data was ambiguous, and why |
| [pre_processing.md](docs/pre_processing.md) | What happens before dbt, and why |
| `profiling__*.md` | One per input file: grain, join key, fee formula, dollar-level accounting |

Start with `assumptions.md` if you disagree with a number. Every judgment call is there with the evidence that settled it.

## About the data

Synthetic data for a reconciliation exercise.
