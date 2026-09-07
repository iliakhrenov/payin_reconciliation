# Profiling — FX rates

`raw/fx_rates.csv`

204 rows · 7 currencies · 29 rate dates · 2026-05-25 → 2026-07-03. Reference data, not a transaction file: it prices both sides of the reconciliation, so a fault here moves every dollar at once.

`usd_rate` is **USD per 1 unit of currency** — multiply, never divide. dLocal's export states its rate the other way round; conflating them inverts every Latin American transaction.

### 1. Business days only, with one hole

29 dates across a 40-day span. Weekends are absent by design — Mon–Thu 6 each, Fri 5.

**2026-06-19 is a Friday with no rates at all.** It is the only missing weekday in the range. Nothing distinguishes it in the file from a weekend, which is exactly why the reconciliation cannot price on the transaction date.

**The rule that follows: price at the last rate published on or before the transaction date.** The backend does this on 5,145 of 5,147 foreign-currency rows, so the rule is the backend's own behaviour, not an invention. Both sides of the reconciliation are held to it.

### 2. One rate was republished — the correction is authoritative

| currency | rate_date | usd_rate | published_at |
| --- | --- | ---: | --- |
| BRL | 2026-06-10 | 0.185352 | 2026-06-10 17:00 |
| BRL | 2026-06-10 | **0.190542** | 2026-06-12 10:00 |

The only duplicate `(currency, rate_date)` in the file, and the only row where `published_at` is not the rate date (203 of 204 match).

**Treated as a correction that supersedes, not a second as-of rate.** dLocal priced every BRL transaction that day at 0.190542, and so did the backend on 23 of 24 — so the corrected rate is what the world actually used. `stg__fx_rates` ranks versions by `published_at` and every consumer pins `is_current_rate`.

The file carries no version or effective-from column, so the only way to tell a correction from an accidental duplicate is to check which one everyone used. That is a reference-data gap, not a reconciliation one — `action_items.md` R1.

### 3. Rates are plausible and stable

| currency | dates | low | high | range |
| --- | ---: | ---: | ---: | ---: |
| ARS | 29 | 0.000824 | 0.000844 | 2.4% |
| BRL | 29 | 0.182476 | 0.190542 | 4.4% |
| CLP | 29 | 0.001056 | 0.001068 | 1.1% |
| COP | 29 | 0.000243 | 0.000252 | 3.7% |
| EUR | 29 | 1.080042 | 1.095953 | 1.5% |
| GBP | 29 | 1.272727 | 1.302510 | 2.3% |
| MXN | 29 | 0.054896 | 0.055489 | 1.1% |

No nulls, no zeros, no negatives, no order-of-magnitude jumps. BRL's 4.4% range is the widest and is mostly the 10 June republication itself. Every currency has all 29 dates; BRL has 30 rows for 29 dates because of that republication.

**USD is absent from the file, correctly** — the backend carries rate exactly 1 on all 2,841 USD rows and never looks one up.

### 4. Coverage against the transaction book

The seven currencies here are exactly the seven non-USD currencies in the engine log. No transaction currency is unpriced, and no rate is published for a currency we do not transact in.

The window starts 2026-05-25, seven days before the reporting period — necessary, because the as-of rule reaches backwards. ORD-507781 is created 2026-05-31 23:59 and prices off the 29 May rate.
