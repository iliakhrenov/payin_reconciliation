## Context
Lumo Wellness sells app subscriptions through five payment providers: PayPal (separate US and EU accounts), dLocal (Latin America), Adyen, and Google Play.

`payment_engine_log.csv` is an extract from the payment backend — the engine that initiates and tracks every transaction attempt, applies FX conversion, and is treated internally as the source of truth. The other files are data exports from each payment provider’s admin panel — it’s what the PSPs
themselves say happened.

Every month, Finance Analyst must prove that the payment backend and the provider exports tell the
same story, and explain every difference in dollars if it’s not the case. That is your task, for the reporting period June 2026.

The engine-log extract and the provider exports intentionally cover a few days around the month boundary as well.

## Input data

| File                                           | What it is                                                    | Format notes                                                   |
| ---------------------------------------------- | ------------------------------------------------------------- | -------------------------------------------------------------- |
| payment_engine_log.csv                         | Payment backend (engine) log extract, all providers           | comma, UTF-8                                                   |
| paypal_us_activity_20260601_20260703.csv       | PayPal US account activity export                             | comma, UTF-8                                                   |
| paypal_eu_activity_20260601_20260703.csv       | PayPal EU account activity export                             | semicolon, cp1252 (Windows-1252)                               |
| adyen_payment_accounting_20260601_20260703.csv | Adyen payment accounting report                               | comma, UTF-8                                                   |
| dlocal_transactions_20260601_20260703.csv      | dLocal transactions export                                    | comma, UTF-8                                                   |
| google_play_earnings_202606.csv                | Google Play earnings report, June                             | comma, UTF-8; line 1 is a report header, data starts on line 2 |
| google_play_earnings_202607_partial.csv        | Google Play earnings report, July 1–3                         | same as above                                                  |
| fx_rates.csv                                   | Daily FX rates to USD (usd_rate = USD per 1 unit of currency) | comma, UTF-8                                                   |
| fee_schedule.csv                               | Contracted provider fees, where we have a contract on file    | comma, UTF-8                                                   |

location: `raw/`

## Tooling

- DuckDB: for in-memory SQL data processing
- dbt: for data transformation, will sit directly on CSVs via DuckDB

## Goal

1. Reconcile each provider export against the payment engine log for June 2026. Quantify all discrepancies — in row counts and in USD.
2. Classify every discrepancy by root cause, using your own taxonomy.
3. Deliver a summary at provider × cause grain: row count, absolute USD impact, signed USD impact, and each cause’s share of the total discrepancy in %.
4. Where fee_schedule.csv is applicable to  a provider, reconcile the reported fees against the contracted rates.
5. Report the total discrepancy and show what remains unexplained after your classification (the residual). A correct analysis explains all the discrepancies.

## Notes

1. When the data is ambiguous, make a call and document it. Location: `docs/assumptions.md`
2. Every dollar of difference between the payment backend and the providers is either matched, explained with a cause, or explicitly listed as unexplained — and the three add up. (dbt test)
3. The reconciliation summary format: numbers first, caveats and issues stated. Tone: concise, executive-facing, something that can be skimmed for essence quikly. Location: `docs/cfo_summary_<month>.md`.
4. Data pre-processing (before it lands in dbt) must be documented. Location: `docs/pre_processing.md`

## Style
- Keep SQL lowercase, 2 space indent
- Code comments are a cheat-meal, not a regular diet. Place them only where it is absolutely essential for future-self.
- Documentation: extremely concise, capture only essence, something that can be explained to business stakeholders.