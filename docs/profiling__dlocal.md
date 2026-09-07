# Profiling — dLocal

`raw/dlocal_transactions_20260601_20260703.csv`

1,319 rows · 1,318 transaction ids · 1,295 invoices · 2026-06-01 → 2026-07-03 · five countries, one currency each (AR/ARS, BR/BRL, CL/CLP, CO/COP, MX/MXN) · no blanks, no nulls, no unparseable numerics.

### 1. Grain: one row per lifecycle event, `invoice_id` × `transaction_type`

1,318 distinct combinations over 1,319 rows. The extra row is an exact duplicate — lines 787 and 788 are byte-identical (`DL-90001316` / `ORD-507810`). Every other `transaction_id` appears once.

Lifecycle sets per invoice:

┌────────────────────────────────┬───────┐
│ states                         │ inv.  │
├────────────────────────────────┼───────┤
│ PAYMENT/PAID                   │ 1,159 │
│ PAYMENT/REJECTED               │   111 │
│ PAYMENT/PAID + REFUND/REFUNDED │    23 │
│ PAYMENT/PAID ×2 (duplicate)    │     1 │
│ PAYMENT/IN_MEDIATION           │     1 │
└────────────────────────────────┴───────┘

**Filter rule.** Money moved on `PAYMENT/PAID` and `REFUND/REFUNDED`. `REJECTED` never settled. `IN_MEDIATION` is a payment under dispute — dLocal has not confirmed settlement, so it is not counted as one (see assumptions). Deduplicate on the full row before summing anything.

Unlike Adyen there is no authorisation row: dLocal reports one row per outcome, and no gross column is ever double-counted except by the duplicate line above.

**Every column is populated on every row** — including `fee_usd` on the 111 `REJECTED` rows, which is the one population fact that matters (section 5).

### 2. `local_amount` is in minor units, and the exponent is per-currency

`currency_exponent` is 2 for ARS/BRL/COP/MXN and **0 for CLP** (153 rows). A blanket ÷100 understates CLP by 100×; ignoring the exponent overstates the other four by 100×. Scaled row by row:

```
amount_local = local_amount / 10 ^ currency_exponent
```

1,318 of 1,319 rows then equal the engine's `amount_local` to the cent, and the currency agrees on all 1,319. The single break is `ORD-507807` (section 4).

### 3. `fx_rate` is inverted, and `usd_amount` derives from it

`fx_rate` is **local units per USD** — the reciprocal of `fx_rates.usd_rate`. dLocal's own USD column is `round(amount_local / fx_rate, 2)`, exact on 1,317 of 1,319. Two ARS rows report a cent more than their own rate produces:

┌────────────┬──────────────┬───────────┬────────┬──────┐
│ order      │ amount_local │ fx_rate   │ dLocal │ calc │
├────────────┼──────────────┼───────────┼────────┼──────┤
│ ORD-507813 │ ARS 15,999   │ 1190.4762 │ 13.45  │ 13.44│
│ ORD-507814 │ ARS 15,999   │ 1197.6048 │ 13.37  │ 13.36│
└────────────┴──────────────┴───────────┴────────┴──────┘

Immaterial to the reconciliation — both sides are re-priced at the published rate, so `usd_amount` is a cross-check, not an input.

`1 / fx_rate` equals the published as-of `usd_rate` on 1,318 of 1,319 rows. The exception is `ORD-507781`, created 2026-05-31 23:59:50 and settled 2026-06-01 00:05: both dLocal and the engine price it at the 29 May rate (0.055082), the as-of rate for the **creation** date. Pricing it off the export timestamp gives the 1 June rate (0.055014) and a $0.01 break. dLocal publishes no creation timestamp, so this cent is a known, named item rather than a residual.

### 4. `invoice_id` coverage: 1,295 of 1,295 match the engine

Every provider invoice lands on an engine `order_id`, all on `psp = 'dlocal'` — no cross-provider bleed. Engine side, one of 1,296 dLocal orders has no provider row.

**`transaction_id` is a valid alternate key, contrary to expectation.** The engine stores dLocal's id in `psp_reference` and they agree on every joinable row — 1,296 sales and all 23 refunds. dLocal mints a *fresh* id for each refund and the engine records that same fresh id, so unlike Adyen the reference survives reversals. `invoice_id` remains the join key for uniformity with the other providers, but the PSP reference is not the trap here — it is corroboration.

Four rows break, all one-offs:

┌────────────┬────────────────────────────────────────────────────┬────────────────┬────────┐
│ order      │ what                                               │ local          │ USD    │
├────────────┼────────────────────────────────────────────────────┼────────────────┼────────┤
│ ORD-507812 │ engine SALE settled, absent from the export         │ CLP −6,990.00  │ −7.42  │
│ ORD-507807 │ dLocal refunded BRL 99.95, engine booked 59.97      │ BRL +39.98     │ −7.36  │
│ ORD-507787 │ engine SALE settled, dLocal status IN_MEDIATION     │ BRL −34.90     │ −6.45  │
│ ORD-507810 │ export line duplicated verbatim (lines 787–788)     │ MXN +129.00    │ +7.13  │
└────────────┴────────────────────────────────────────────────────┴────────────────┴────────┘

`ORD-507812` is a provider export omission, not an engine invention: dLocal transaction ids run dense from `DL-90000001` to `DL-90001319` across the union of both sides, and `DL-90001317` — the reference the engine holds for this order — is the **only** id missing from the file.

`ORD-507807` refunds exactly 50% of a BRL 199.90 sale while the engine books 30%. dLocal moved the money, so the engine understates the refund. No other refund exceeds its sale.

Status vocabulary otherwise maps 1:1 — `PAID`→`settled`, `REJECTED`→`declined`, `REFUNDED`→ refund `settled`. Amounts, currencies and rates agree on all 1,315 remaining rows.

### 5. Fees: 4.5% flat, exact, and not under contract

```
fee_usd = round(usd_amount × 4.5%, 2)
```

Exact on all 1,184 `PAID` rows, all 111 `REJECTED`, and the `IN_MEDIATION` row — every currency, no exceptions. The 4.41–4.65% spread in the effective rate is entirely cent-rounding on $6–$50 tickets. Fees are charged in USD; the file carries no local fee column.

**dLocal is absent from `fee_schedule`** — so the contract file is what has the gap, not the charge. The export is taken as authoritative and June's **1,150 settled sales carry $682.56 as `psp_claims_fee_out_of_contract`** (4.500% of $15,168.94 gross, after the duplicate line is collapsed). Finance should retrieve the dLocal contract and confirm the rate.

Two things that contract would also settle:

- **$68.69 of June fee sits on rows where no money moved** — $68.40 across 109 rejected attempts and $0.29 on the disputed row. The file gives no way to tell whether dLocal bills them, so this is reported as a caveat rather than booked.
- **Refunds return no fee** — all 23 carry `fee_usd = 0.00`. The $13.25 originally charged on those sales stays with us.

### 6. Timezone and period boundary

`created_at_utc` is genuinely UTC — no conversion. It is dLocal's **settlement** time and matches the engine exactly: `captured_at_utc` on all 1,208 settled rows, `created_at_utc` on all 111 declined (which the engine leaves uncaptured). Not one row is off by a minute. The file carries no authorisation timestamp.

Because both sides recognise at the same instant, dLocal has no Adyen-style month-end split. June holds 1,151 `PAID` export lines (1,150 transactions, one shipped twice), 109 `REJECTED`, 18 `REFUNDED` and the 1 `IN_MEDIATION`; July holds 33 `PAID` ($456.68), 5 `REFUNDED` ($26.58) and 2 `REJECTED`, all excluded.

### 7. Engine FX faults land here

All four engine FX defects are dLocal rows ([`action_items.md`](action_items.md) A1 and R2). June booked USD is $216,067.79 against $15,388.81 at the published as-of rate — **$200,678.97 of overstatement across four rows**, 99.6% of it one:

┌────────────┬─────┬──────────────┬─────────────┬─────────────┬──────────────┐
│ txn        │ ccy │ local        │ rate applied│ correct     │ overstated   │
├────────────┼─────┼──────────────┼─────────────┼─────────────┼──────────────┤
│ TXN-107965 │ COP │ 199,900.00   │ 1.000000    │ 0.000244    │ +199,851.22  │
│ TXN-107964 │ MXN │ 799.00       │ 1.000000    │ 0.055169    │ +754.92      │
│ TXN-107963 │ BRL │ 89.90        │ 1.000000    │ 0.184648    │ +73.30       │
│ TXN-107952 │ BRL │ 89.90        │ 0.185352    │ 0.190542    │ −0.47        │
└────────────┴─────┴──────────────┴─────────────┴─────────────┴──────────────┘

These do not touch section 4: the gross comparison is done in local currency, where all four rows agree exactly. dLocal independently reports the corrected figure on every one of them.

### 8. Close

June settled sales, local currency:

┌─────┬───────────────┬───────────────┬───────────┐
│ ccy │ dLocal        │ engine        │ diff      │
├─────┼───────────────┼───────────────┼───────────┤
│ ARS │   1,170,500   │   1,170,500   │      0    │
│ BRL │      35,360.00│      35,394.90│    −34.90 │
│ CLP │   1,875,660   │   1,882,650   │ −6,990    │
│ COP │   7,291,800   │   7,291,800   │      0    │
│ MXN │      70,395.00│      70,266.00│   +129.00 │
└─────┴───────────────┴───────────────┴───────────┘

June refunds: BRL 989.95 vs 949.97 → +39.98. ARS, CLP, MXN nil.

BRL −34.90 = `ORD-507787`. CLP −6,990 = `ORD-507812`. MXN +129.00 = `ORD-507810`. Refund BRL +39.98 = `ORD-507807`. Residual zero in every currency.

**Total dLocal gross discrepancy: −$14.11 signed, $28.37 absolute** — the four rows above plus $0.01 on the `ORD-507781` FX date basis. Nothing unexplained.

Signed is the impact on net USD receipts against the backend's books; USD is the last published rate on or before the transaction date.

### 9. How each finding is classified

`mart__recon_summary`, June 2026:

┌─────────────┬────────────────────────────────┬───────┬────────────┬─────────────┐
│ scope       │ cause                          │ rows  │ abs USD    │ signed USD  │
├─────────────┼────────────────────────────────┼───────┼────────────┼─────────────┤
│ engine_bugs │ engine_fx_not_applied          │     3 │ 200,679.44 │ −200,679.44 │
│ engine_bugs │ engine_fx_rate_mismatch        │     1 │       0.47 │       +0.47 │
│ gross       │ engine_claims_sale             │     1 │       7.42 │       −7.42 │
│ gross       │ psp_claims_different_amount    │     1 │       7.36 │       −7.36 │
│ gross       │ psp_claims_duplicate_row       │     1 │       7.13 │       +7.13 │
│ gross       │ psp_claims_disputed            │     1 │       6.45 │       −6.45 │
│ gross       │ psp_fx_date_basis              │     1 │       0.01 │       −0.01 │
│ net         │ psp_claims_fee_out_of_contract │ 1,150 │     682.56 │     −682.56 │
└─────────────┴────────────────────────────────┴───────┴────────────┴─────────────┘

Four causes are new — the existing taxonomy had no home for them and forcing them into one would have misnamed the counterparty:

- `engine_claims_sale` — the mirror of `psp_claims_sale`. Only the provider-has-it direction existed.
- `psp_claims_disputed` — a decline is final and costs nothing; a dispute may still resolve either way and the fee is already charged. Different thing to chase.
- `psp_claims_duplicate_row` — an export-integrity defect. Naming it keeps the report tied to the file as delivered rather than silently correcting it.
- `psp_fx_date_basis` — both sides agree on the local amount and price it on different days. Generalises to any provider that publishes only a settlement timestamp.

`psp_claims_different_amount` is also new and deliberately last in the chain: it fires only when both sides settled, currencies agree, and no structural cause applies. `ORD-507807` lands there rather than in an `engine_*` cause because the convention names the claimant, not our verdict — the provider moved the money; [`action_items.md`](action_items.md) A4 carries the judgment that the engine is the deviant.
