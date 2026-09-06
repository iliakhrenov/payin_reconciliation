# Profiling — Google Play

`raw/google_play_earnings_202606.csv` + `raw/google_play_earnings_202607_partial.csv`, unioned.

1,622 rows (1,544 June + 78 July) · 820 transactions · 2026-06-01 00:28:46 → 2026-07-03 11:16:07 America/Los_Angeles · four SKUs · five countries, one currency each (BR/BRL, DE/EUR, GB/GBP, MX/MXN, US/USD) · merchant currency USD throughout · no blanks, no nulls, no unparseable numerics.

Line 1 of each file is a report banner, not data. The two files are complementary halves of one ledger and must be unioned before anything is counted — the June file already contains a transaction that belongs to July.

### 1. Grain: one row per ledger entry, two entries per sale

┌───────────────┬───────┬───────────────┐
│ type          │ rows  │ local total   │
├───────────────┼───────┼───────────────┤
│ Charge        │   802 │  +38,923.30   │
│ Google fee    │   802 │   −5,848.97   │
│ Charge refund │    18 │   −1,501.76   │
└───────────────┴───────┴───────────────┘

`(timestamp, type, sku, country, currency, amount)` is unique across all 1,622 rows — no duplicates anywhere.

**Every `Charge` carries exactly one `Google fee` row at the identical timestamp, SKU and country.** 802 of 802, zero orphan fee rows. Refunds carry none (section 5). So the transaction grain is the `Charge` row and the fee row is its sibling, not a second sale — summing the gross column unfiltered double-counts nothing but nets the fee into revenue.

The file has no `Charge` for a failed purchase. Google Play publishes an *earnings* report: it lists money that moved and nothing else.

### 2. `captured_at_utc` is an exact join key — the tie-back exists

The export carries no order id, no purchase token, no PSP reference, and the engine's `psp_reference` is **null on all 820 Google Play rows** — the only PSP where it is. So there is no identifier to join on. There is a timestamp, and it turns out to be enough.

┌──────────────────────────────────────────────┬────────┐
│ engine `captured_at_utc` = provider LA→UTC   │    820 │
│ engine `captured_at_utc` = provider raw LA   │      0 │
│ engine `created_at_utc`  = provider LA→UTC   │      0 │
└──────────────────────────────────────────────┴────────┘

Converted, the provider timestamp matches the engine's **capture** time to the second on every row. Unconverted it matches nothing. The banner's timezone claim is therefore proven, not assumed, and the offset is a uniform −7h across the window (PDT, no DST boundary in scope).

The engine's `created_at_utc` is an authorisation time running 5 min to 1h50m ahead of capture (mean 56 min) and appears nowhere in the export. Joining on it matches zero rows.

Key is `(captured_at_utc, operation, sku, country)`. The timestamp alone is unique on 801 of 802 sales — `2026-06-05 18:56:43` carries two, a DE/EUR `sub_annual` and a US/USD `sub_monthly`, and both sides carry the same pair. SKU and country separate them.

**Full outer join: 820 pairs, 0 engine-only, 0 provider-only.** Currency, local amount and USD agree on every one.

┌────────────────┬─────────┬────────┬──────────┐
│                │ engine  │ Google │ unmatched│
├────────────────┼─────────┼────────┼──────────┤
│ sales settled  │     802 │    802 │        0 │
│ refunds        │      18 │     18 │        0 │
│ declines       │       0 │      — │        — │
└────────────────┴─────────┴────────┴──────────┘

Both extracts are cut on the same LA-local boundary — the engine's first Google Play capture is 2026-06-01 00:28:46 LA, exactly the file's first line — so there is no May-side blind spot inside the delivered scope. A transaction late on 31 May LA would sit in the undelivered May file *and* outside the engine slice; neither side can see it, so completeness holds within scope but is not proven beyond it.

### 3. FX: Google prices at our own published as-of rate

`Currency Conversion Rate` is USD per 1 unit of buyer currency — the same direction as `fx_rates.usd_rate`, not inverted. It is constant per currency per day and equals the last published rate on or before the transaction date on **all 130 (currency, date) pairs**, including BRL 2026-06-10 where Google uses the republished 0.190542 rather than the original 0.185352. That independently corroborates the republication rule already assumed in `assumptions.md`.

`fx_rate_applied` in the engine equals Google's rate on all 469 non-USD sales and all 18 refunds, and `amount_usd` agrees to the cent on all 820 rows. No Google Play row appears in the engine's FX defect list.

Google's rate basis is the **LA** date; ours is the UTC date. In this data the distinction never bites: **zero** non-USD transactions fall in the 17:00–24:00 LA window where the two dates diverge — foreign buyers transact in their own daytime, which is LA morning. The single row that does cross the date boundary is USD. The two bases would need to be reconciled if the mix changed.

Refunds are priced at the **refund**-date rate, not the original sale's. The engine does the same, so it nets to zero here; it is a real FX exposure on the P&L, not a reconciliation break.

### 4. Fees: 15% contracted, 15% charged, except six rows at 30%

Contract on file: `google_play / LumoPlayMain / 15.0% / no fixed fee`.

```
fee_local = round(gross_local × 15%, 2)
fee_usd   = round(gross_usd   × 15%, 2)
```

Exact on 796 of 802 sales. Note the USD fee is derived from the **USD gross**, not by converting the local fee — the two differ by a cent on 59 rows ($0.33 across the file). Staging must take Google's USD fee as reported rather than recompute it from the local column.

┌────────────┬───────┬───────────┐
│ eff. rate  │ rows  │ gross     │
├────────────┼───────┼───────────┤
│ 15.0%      │   796 │ 38,863.36 │
│ 30.0%      │     6 │     59.94 │
└────────────┴───────┴───────────┘

The six sit inside a five-hour window on 2026-06-17, 02:21–07:30 LA, and are identical in every other respect: US, USD, `sub_monthly`, $9.99, fee $3.00 against a contracted $1.50. Charges on either side of them in the same file are billed correctly, so this is a pricing-tier misapplication on a handful of transactions, not a rate change.

**Overcharge: $9.00** — the whole of the Google Play fee variance for June.

**Refunds return no fee.** All 802 fee rows are negative — there is no positive `Google fee` row anywhere in the union, so no credit and no reversal. All 18 refunds are standalone, with zero sibling rows of any type against 802-of-802 charges that have one. The buyer gets the gross back; the 15% stays with Google.

June's 10 refunds returned $185.71 of gross, leaving **$27.86 of commission retained** — tight to about a dime, since every one has candidate original sales in the window whose actual fee sits within a cent or two of 15% of the refunded gross.

**This file cannot say whether that is a term or an omission.** A fee-credit row would be indistinguishable in shape from the 802 that exist; there simply are none, and the contract is silent on reversals. Either Google keeps commission on refunds — a real cost and a term to renegotiate — or its policy returns it and the export is missing 18 credit rows, in which case the $27.86 is owed to us. Reported as a caveat rather than classified, consistent with dLocal, where all 23 refunds likewise carry zero fee and $13.25 stays with the provider. One question to put to both.

### 5. Period: Google's month is not June

The file boundary is LA-local. On the UTC recognition basis one June-file transaction belongs to July:

┌──────────────────────────────┬─────────────┬──────────┐
│                              │ gross USD   │ fee USD  │
├──────────────────────────────┼─────────────┼──────────┤
│ Google's June statement      │  14,940.33  │ 2,250.70 │
│ less Jun 30 20:19 LA sale    │      −9.99  │    −1.50 │
│ = June UTC                   │  14,930.34  │ 2,249.20 │
└──────────────────────────────┴─────────────┴──────────┘

`ORD-507797` / `TXN-107971`, US `sub_monthly` $9.99, 2026-06-30 20:19 LA = 2026-07-01 03:19 UTC. **Both sides agree it is a July transaction** — the engine captures it in July too — so this is a difference between Google's statement and June, not between Google and the backend. It carries $0.00 of discrepancy and is listed so the provider's own total ties.

Nothing moves the other way: the July partial file opens at 09:40 UTC on 1 July.

### 6. Close — June 2026 (UTC)

┌─────┬───────┬────────────┬────────────┬────────────┬────────────┐
│ ccy │ sales │ Google USD │ engine USD │ refund USD │ fee USD    │
├─────┼───────┼────────────┼────────────┼────────────┼────────────┤
│ BRL │   123 │   1,622.49 │   1,622.49 │      −6.44 │    −243.50 │
│ EUR │   151 │   3,745.96 │   3,745.96 │     −86.87 │    −561.88 │
│ GBP │   105 │   2,538.65 │   2,538.65 │     −28.54 │    −380.77 │
│ MXN │    72 │     976.39 │     976.39 │     −43.89 │    −146.55 │
│ USD │   315 │   6,046.85 │   6,046.85 │     −19.97 │    −916.50 │
├─────┼───────┼────────────┼────────────┼────────────┼────────────┤
│ all │   766 │  14,930.34 │  14,930.34 │    −185.71 │  −2,249.20 │
└─────┴───────┴────────────┴────────────┴────────────┴────────────┘

Local-currency totals tie exactly in all five currencies, sales and refunds, both directions. Refunds: 10 on each side, BRL 34.90 / EUR 79.96 / GBP 21.99 / MXN 799.00 / USD 19.97.

**Gross discrepancy: $0.00.** Nothing unexplained.

**Fee discrepancy: −$9.00 signed, $9.00 absolute** — the six 30% rows.

June net receipts: $14,930.34 − $185.71 − $2,249.20 = **$12,495.43**.

Signed is the impact on net USD receipts against the backend's books; USD is the last published rate on or before the transaction date.

### 7. Classification

`mart__recon_summary`, June 2026:

┌─────────────┬────────────────────┬──────┬─────────┬────────────┐
│ scope       │ cause              │ rows │ abs USD │ signed USD │
├─────────────┼────────────────────┼──────┼─────────┼────────────┤
│ engine_bugs │ matched            │  776 │    0.00 │       0.00 │
│ gross       │ matched            │  776 │    0.00 │       0.00 │
│ net         │ psp_fee_overcharge │    6 │    9.00 │      −9.00 │
│ net         │ matched            │  760 │    0.00 │       0.00 │
└─────────────┴────────────────────┴──────┴─────────┴────────────┘

**No new cause was needed.** `psp_fee_overcharge` already exists for Adyen and fires here unchanged — it compares the provider's local fee against the contracted local fee, which is the right basis (section 4: comparing in USD would manufacture a cent of variance on 59 rows). Google Play is the first provider to reach the gross reconciliation with nothing to classify.

Reported alongside, not classified: **$27.86** of fee retained on refunded sales (no contract term), and **$9.99 / $1.50** of Google's June statement that belongs to July.

### 8. Caveat: this is a completeness check, not an independent comparison

Google Play is the only PSP where the engine log carries **no declined attempts and no chargebacks** — every other provider runs a 7–8% decline rate. The backend does not initiate a Google Play purchase; Google bills the user and notifies us, so the engine row is created from Google's own notification. The two sides tie perfectly because they share a source.

That makes the tie a genuine but weaker assurance than the other providers': it proves the feed was ingested completely and priced consistently, and it would catch a dropped or duplicated notification. It cannot catch anything Google never told us about. A tie of $0.00 here should be read as "the pipe is clean", not "the revenue is independently confirmed".
