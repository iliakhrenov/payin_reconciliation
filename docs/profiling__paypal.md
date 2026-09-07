# Profiling — PayPal (US + EU)

`raw/paypal_us_activity_20260601_20260703.csv` — 2,167 rows · 2,166 transaction ids · 2,109 invoices · USD only · comma-delimited, UTF-8, `MM/DD/YYYY`, dot decimals.
`raw/paypal_eu_activity_20260601_20260703.csv` — 1,893 rows · 1,893 transaction ids · 1,851 invoices · EUR + GBP · semicolon-delimited, cp1252, `DD/MM/YYYY`, comma decimals.

Both span 2026-06-01 → 2026-07-03. Both declare `Time Zone = GMT` on every row. The two files are one PSP with two accounts and share every column; only the dialect differs.

### 1. Grain: one row per transaction — with one duplicate

`Transaction ID` is the row key. US carries 2,167 rows over 2,166 ids — a single **byte-identical duplicated line** (`DAB2MG8NSYNB3UXDY`, `ORD-507809`, $9.99). EU is clean at 1,893/1,893.

`Invoice ID` is *not* the key: it fans out to 2 on 100 invoices (57 US refunds, 41 EU refunds, 1 EU reversal, 1 duplicate line). Summing gross by invoice double-counts.

Lifecycle vocabulary, both accounts:

┌───────────┬──────────────────┬───────────┬───────┬────────────────────────────────┐
│  account  │       Type       │  Status   │ rows  │ money                          │
├───────────┼──────────────────┼───────────┼───────┼────────────────────────────────┤
│ paypal_us │ Website Payment  │ Completed │ 1,942 │ gross +, fee, net = gross+fee  │
│ paypal_us │ Website Payment  │ Denied    │   168 │ gross +, fee 0, net 0          │
│ paypal_us │ Refund           │ Refunded  │    57 │ gross −, fee 0, net = gross    │
│ paypal_eu │ Website Payment  │ Completed │ 1,704 │ gross +, fee, net = gross+fee  │
│ paypal_eu │ Website Payment  │ Denied    │   147 │ gross +, fee 0, net 0          │
│ paypal_eu │ Refund           │ Refunded  │    41 │ gross −, fee 0, net = gross    │
│ paypal_eu │ Payment Reversal │ Reversed  │     1 │ gross −, fee 0, net = gross    │
└───────────┴──────────────────┴───────────┴───────┴────────────────────────────────┘

**Filter rule.** `Completed`, `Refunded` and `Reversed` carry money. `Denied` carries a gross figure but zero net — it never settled and must not enter any sum; it is the counterpart of the engine's `declined`, not a discrepancy. Signs are already correct in the file: reversals are negative, unlike the engine log, which stores refunds positive.

`net = gross + fee` holds on all 4,060 rows. No blanks, no nulls, no unparseable numerics in any column.

### 2. Join key: `psp_reference` ↔ `Transaction ID`, 1:1 in both directions

Unlike Adyen, the engine mints a **fresh** `psp_reference` for every PayPal refund and it equals the refund's own provider `Transaction ID` — 97 of 97 refunds match. So the transaction id is a complete key across all operation types, and `Invoice ID` ↔ `order_id` is the entity-level key that fans out on reversals.

- Engine side: **0 orphans**. All 4,057 PayPal engine rows appear in the exports.
- Provider side: **2 orphans**, both EU (§5).
- No cross-provider bleed: 2,166 ids land on `paypal_us`, 1,891 on `paypal_eu`, none anywhere else.

Status agreement is a perfect diagonal — every matched `Completed` faces a settled sale, every `Denied` faces a declined sale, every `Refunded` faces a refund. **One exception**, in §5.

`Reference Txn ID` (populated on all 99 reversals, blank on all 3,961 sales) resolves to a `Completed` sale in the same file with the same `Invoice ID` on 99 of 99 rows, always later than that sale. 32 are partial refunds, each exactly 50% of the sale. It is sound, and useful for asserting the reversal→sale link, but it is not needed as a join key.

### 3. Amounts: zero variance on every matched row

Compared in local currency: `abs(Gross) = amount_local` on **all 4,058 matched rows**, and `Currency` agrees with the engine on every one. No partial capture — PayPal publishes a single settled amount, no authorised column. Every PayPal discrepancy is a row-existence or status question, never an amount question.

### 4. Fees: no contract on file, but the schedule is exact

`fee_schedule.csv` has no PayPal entry, so there is nothing to reconcile against. The charge is nevertheless fully determined — **percentage + a fixed fee denominated in the transaction currency**:

┌──────────┬─────────┬───────────┬──────────────────────────┐
│ currency │ percent │ fixed fee │ rows matching exactly    │
├──────────┼─────────┼───────────┼──────────────────────────┤
│ USD      │ 3.49 %  │ 0.49 USD  │ 1,942 / 1,942            │
│ EUR      │ 2.90 %  │ 0.35 EUR  │ 1,435 / 1,435            │
│ GBP      │ 2.90 %  │ 0.30 GBP  │   269 /   269            │
└──────────┴─────────┴───────────┴──────────────────────────┘

`round(gross × pct, 2) + fixed` reproduces the reported fee on **3,646 of 3,646** settled sales. Zero variance, zero rounding noise.

The raw effective rate is misleading and should not be compared to a contracted percentage: it runs 3.4%–13.2% because the fixed fee dominates small tickets. June's blended rate is 6.01% US, 4.60% EU / EUR, 4.72% EU / GBP — none of which is a rate anyone contracted. June's charge is **$2,208.46 US and $1,700.50 EU, $3,908.96 in total**, counting the duplicated line once.

**PayPal keeps the fee on a refund.** All 99 reversals report `Fee = 0.00`; the original processing fee is never returned. Real cost, not stated in any contract we hold.

Note for staging: the fixed fee here is per-currency, unlike Adyen's and Google's schedule entries. The existing `fixed_fee_currency` logic zeroes a fixed fee when the currency differs — correct for a single-currency contract, wrong for PayPal. If a PayPal row is ever added to `fee_schedule`, it needs three rows, one per currency.

### 5. The four discrepancies — June 2026

┌──────────────┬───────────┬──────────────────────────────────────────┬──────┬──────────┬──────────┐
│    order     │  account  │ cause                                    │ rows │  local   │   USD    │
├──────────────┼───────────┼──────────────────────────────────────────┼──────┼──────────┼──────────┤
│ ORD-507786   │ paypal_us │ engine capture never recorded            │  +1  │ + 24.99  │ + 24.99  │
│ ORD-507809   │ paypal_us │ duplicated line in the export            │  +1  │ +  9.99  │ +  9.99  │
│ ORD-507788   │ paypal_eu │ chargeback the engine never booked       │  +1  │ − 59.99  │ − 65.36  │
│ ORD-507806   │ paypal_eu │ refund the engine never booked           │  +1  │ − 24.99  │ − 26.99  │
└──────────────┴───────────┴──────────────────────────────────────────┴──────┴──────────┴──────────┘

**ORD-507786 — engine capture never recorded.** `TXN-107960` sits at `pending` with `captured_at_utc` empty. PayPal reports the payment `Completed` at 2026-06-12 14:25 UTC and charged its $1.36 fee. The money moved; the engine never learned. Engine-log defect, understates June by $24.99.

**ORD-507809 — duplicated export line.** The same $9.99 sale is exported twice, all thirteen fields identical. The engine has one row. Provider-side artefact, overstates PayPal by $9.99.

**ORD-507788 and ORD-507806 — reversals the engine never booked.** Both sales are in the engine, settled and correct. PayPal then reports a chargeback (€59.99, 20 June) and a refund (€24.99, 25 June) with no counterpart in the engine at all. Corroborated by the `txn_id` sequence: `TXN-107981` is the gap immediately after `TXN-107980` (= `ORD-507806`'s sale), and `TXN-107985` is the only other unaccounted gap — two missing reversal ids for two missing reversals, with no matching `order_id` gap, which is what an unbooked operation on an existing order looks like. The engine overstates June net revenue by €84.98. Raised as [`action_items.md`](action_items.md) A3.

### 6. Timezone: `GMT` is honest, verified against the engine

`Date + Time` parses to exactly `captured_at_utc` on **1,998 of 1,998** settled US sales and refunds and on 1,701 of 1,704 settled EU sales — the 3 exceptions are a date-format problem, not a timezone one (§7). No conversion is needed; `at time zone` on this file would be wrong.

On `Denied` rows the provider timestamp is `created_at_utc + 30 min` on all 315, consistently — PayPal stamps the decline decision, the engine stamps the attempt. Neither is wrong and no money is involved.

### 7. Date format: EU is `DD/MM/YYYY` — except for three rows

Provable per file: 1,267 US rows have a first component > 12 and none have a second component > 12; EU is the exact mirror (1,153 rows). But three EU rows — `ORD-507782`, `ORD-507783`, `ORD-507784`, all €9.99 at 12:20:00 — are written `MM/DD/YYYY`. Read as `DD/MM` they land in March, September and December 2026, outside the export window; the engine puts all three in June, matching the `MM/DD` reading to the second.

**Detection rule, no engine input needed:** if the `DD/MM` parse falls outside 2026-06-01 → 2026-07-03, use `MM/DD`. It selects exactly those three rows and no others. Getting this wrong pushes 2 of them out of June and manufactures a €29.97 discrepancy that does not exist.

### 8. Period boundary

Recognition is the settlement instant on both sides. 135 provider rows fall in July (91 completed, 33 reversals, 11 denied across both accounts) and the engine agrees on every one — the straddle is excluded identically, not a discrepancy.

Two US sales, `ORD-507779` and `ORD-507780`, are created 2026-06-30 23:59 and captured 2026-07-01 00:04. Both sides recognise them in **July**. USD, so no FX consequence — but it confirms the rule: recognise on capture, or these two flip month on the engine side only.

No provider row predates 2026-06-01.

### 9. Engine-side FX defect (not a PayPal difference)

One PayPal row books the wrong USD: `TXN-107950` / `ORD-507776`, €59.99 priced at the 2 June rate on a 16 June transaction — $65.75 booked, $65.19 correct, **+$0.56 overstated**. Local amounts agree with PayPal exactly; this is an engine conversion defect, raised as [`action_items.md`](action_items.md) R2, and it belongs in the FX lane rather than the gross-difference lane. It is the only one on PayPal.

### 10. Close — residual zero

June 2026, settled money only, both sides priced at the published as-of rate:

┌──────┬────────────┬──────────────┬────────────┬──────────────┬──────────┬───────────┐
│ ccy  │ psp rows   │ engine rows  │ psp local  │ engine local │ Δ local  │ Δ USD     │
├──────┼────────────┼──────────────┼────────────┼──────────────┼──────────┼───────────┤
│ EUR  │ 1,421      │ 1,419        │ 28,361.17  │ 28,446.15    │ − 84.98  │ − 92.35   │
│ GBP  │   266      │   266        │  4,157.96  │  4,157.96    │    0.00  │    0.00   │
│ USD  │ 1,934      │ 1,932        │ 36,081.29  │ 36,046.31    │ + 34.98  │ + 34.98   │
└──────┴────────────┴──────────────┴────────────┴──────────────┴──────────┴───────────┘

Decomposition:

- `EUR −92.35 = −65.36 (unbooked chargeback) − 26.99 (unbooked refund)`
- `USD +34.98 = +24.99 (uncaptured sale) + 9.99 (duplicate line)`
- `GBP 0.00` — nothing to explain.

**Total: signed −$57.37, absolute $127.33, across 4 rows. Residual $0.00.**
