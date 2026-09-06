# Profiling — Adyen

`raw/adyen_payment_accounting_20260601_20260703.csv`

3,413 rows · 1,756 merchant references · 2026-06-01 → 2026-07-03 · all `LumoGroup`, all `Europe/Amsterdam`.

### 1. Grain: `Merchant Reference` × `Record Type` is the key — confirmed

3,413 distinct combinations over 3,413 rows. `Psp Reference` ↔ `Merchant Reference` is strictly 1:1
(1,756 ↔ 1,756), so either can key the entity; the record type is what makes the row unique.

Lifecycle sets are clean — no reference carries two attempts:

┌───────────────────────────────┬────────┐
│         record types          │  refs  │
├───────────────────────────────┼────────┤
│ Authorised + Settled          │ 1,581  │
│ Refused                       │   137  │
│ Authorised + Refunded+Settled │    35  │
│ Authorised + Chargeback+Sett. │     3  │
└───────────────────────────────┴────────┘

Every Authorised has a Settled. Refunds and chargebacks never appear without one.

**Filter rule.** Sales join on `Record Type = 'Settled'` only — it carries the money that moved,
the fees, and a settle timestamp that matches the engine's `captured_at_utc`. `Authorised` is a
duplicate of gross for 1,617 of 1,619 rows and must never be summed. `Refused` never settled and
is not a discrepancy. Refunds and chargebacks are separate rows joined on the same reference.

Column population follows the record type exactly — worth knowing before casting:

- `Gross Credit` on sales, `Gross Debit` on the 38 refunds/chargebacks. Never both.
- `Commission`, `Markup`, `Net Credit` populated on `Settled` only (1,619 rows). Blank elsewhere.
- `Net Currency` = `Gross Currency` on every row. No FX inside the file.
- No negatives, no unparseable numerics, no blank keys.

### 2. `Merchant Reference` coverage: 1,755 of 1,756 match the engine

All 1,755 matches land on `psp = 'adyen'` — no cross-provider bleed. Engine-side coverage is
total: every one of the engine's 1,755 Adyen order_ids appears in the export.

Note `Psp Reference` is **not** a universal join key: the engine issues a *new* reference for each
refund and chargeback (37 rows) while Adyen reuses the original sale's. Join on
`order_id = Merchant Reference` plus operation, not on the PSP reference.

Six references break, all one-offs:

┌────────────┬──────────────────────────────────────────────┬────────────┬─────────┐
│ order      │ what                                         │ local      │ USD     │
├────────────┼──────────────────────────────────────────────┼────────────┼─────────┤
│ ORD-507808 │ chargeback in Adyen, absent from engine       │ EUR −59.99 │ −64.79  │
│ ORD-507792 │ partial capture: auth 59.99, settled 35.99    │ EUR −24.00 │ −26.15  │
│ ORD-507793 │ partial capture: auth 21.99, settled 11.00    │ GBP −10.99 │ −14.21  │
│ ORD-507785 │ engine SALE settled, Adyen says Refused       │ EUR −9.99  │ −10.90  │
│ ORD-507794 │ engine captured 06-28, Adyen settled 07-02    │ EUR −9.99  │ −10.79  │
│ ORD-507811 │ sale in Adyen, absent from engine             │ EUR +9.99  │ +10.86  │
└────────────┴──────────────────────────────────────────────┴────────────┴─────────┘

`ORD-507811` is the order_id gap flagged in dq_issues item 5 — confirmed as provider-has-it, engine-doesn't.
`ORD-507794` is a period-boundary case, not a loss: batch 26 authorises it in June, batch 27
settles it in July.

These six account for the June settled-sales gap in full, currency by currency:

┌─────┬───────────┬────────────┬─────────┐
│ ccy │ Adyen     │ engine     │ diff    │
├─────┼───────────┼────────────┼─────────┤
│ EUR │ 19,355.93 │ 19,389.92  │ −33.99  │
│ GBP │  4,596.38 │  4,607.37  │ −10.99  │
│ USD │  6,276.94 │  6,276.94  │   0.00  │
└─────┴───────────┴────────────┴─────────┘

EUR −33.99 = −24.00 (507792) + 9.99 (507811) − 9.99 (507785) − 9.99 (507794). GBP −10.99 = 507793.
Residual zero. Amounts and currencies agree on all other 1,616 settled sales, and on all 35 refunds.

### 3. Fees: contracted 2.5% is applied correctly, split across two columns

`fee_schedule` gives both accounts 2.5% + 0.00 fixed, effective 2026-01-01, no mid-period change.
Adyen does not report that as one number — it splits it:

```
Commission = round(Gross Credit × 1.9%, 2)
Markup     = round(Gross Credit × 2.5%, 2) − Commission
Net Credit = Gross Credit − Commission − Markup
```

Exact on 1,617 of 1,619 settled rows, both accounts, all three currencies. `Net Credit` ties
to the arithmetic on all 1,619 with zero residual. Fees are charged in the gross currency —
no FX enters the fee calculation.

**Checking `Commission` alone against the 2.5% contract fails on every row** (it reads as 1.9%).
The comparison must be `Commission + Markup`.

Two rows are genuinely overcharged, at 4.40%:

┌────────────┬─────────────┬───────┬──────┬──────┬───────┬────────────┬────────┐
│ order      │ account     │ gross │ comm │ mkup │ total │ contracted │ over   │
├────────────┼─────────────┼───────┼──────┼──────┼───────┼────────────┼────────┤
│ ORD-507798 │ LumoECOM_EU │ 59.99 │ 2.28 │ 0.36 │ 2.64  │ 1.50       │ +1.14  │
│ ORD-507799 │ LumoAPP_US  │ 24.99 │ 0.95 │ 0.15 │ 1.10  │ 0.62       │ +0.48  │
└────────────┴─────────────┴───────┴──────┴──────┴───────┴────────────┴────────┘

June fee totals — variance is exactly those two rows, nothing else:

┌─────────────┬─────┬───────┬───────────┬───────────┬─────────┬──────────┐
│ account     │ ccy │  n    │ gross     │ total fee │ eff %   │ variance │
├─────────────┼─────┼───────┼───────────┼───────────┼─────────┼──────────┤
│ LumoAPP_US  │ USD │   306 │  6,276.94 │   157.00  │ 2.501   │ +0.48    │
│ LumoECOM_EU │ EUR │ 1,007 │ 19,355.93 │   483.98  │ 2.500   │ +1.14    │
│ LumoECOM_EU │ GBP │   263 │  4,596.38 │   114.01  │ 2.480   │  0.00    │
└─────────────┴─────┴───────┴───────────┴───────────┴─────────┴──────────┘

GBP reads 2.480% because ORD-507793's fee is charged on the captured 11.00, not the authorised
21.99 — correct behaviour, and the same partial capture already counted above.

Refunds and chargebacks return no fee: all 38 have blank `Commission`/`Markup` and
`Net Debit = Gross Debit`. The 2.5% on a refunded sale is a real cost that stays with us.

### 4. Timezone and period boundary

`Creation Date` is Europe/Amsterdam (UTC+2 in June). Converted to UTC it matches the engine
exactly — `Authorised` = `created_at_utc` on all 1,618 joinable sales, `Settled` = `captured_at_utc`
on 1,617 (ORD-507794 is the July settlement above).

The export runs past the month end. Scoped on UTC settle date, June holds 1,576 Settled rows;
43 Settled, 42 Authorised, 11 Refunded and 3 Refused fall in July and must be excluded.
`Batch Number` is a weekly Mon–Sun cycle (23–27); batch 27 straddles the boundary, so batch
is not a substitute for a date filter.

**Total Adyen discrepancy identified: −$117.70 signed, $139.41 absolute.** Nothing unexplained.
