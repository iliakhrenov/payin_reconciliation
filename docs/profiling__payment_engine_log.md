# Profiling — payment engine log

`raw/payment_engine_log.csv`

7,988 rows · 7,813 orders · 5 providers · 8 currencies · 2026-06-01 → 2026-07-03. The internal source of truth, and the spine every provider export is reconciled against.

### 1. Grain: one row per transaction attempt

`txn_id` is unique across all 7,988 rows. `order_id` is not — 7,813 distinct, because a refund or chargeback reuses the order and mints a new `txn_id`. The reconciliation therefore keys on **order plus operation**, not on either column alone.

| psp | rows | orders | currencies | has psp_reference |
| --- | ---: | ---: | ---: | ---: |
| adyen | 1,792 | 1,755 | 3 | 1,792 |
| dlocal | 1,319 | 1,296 | 5 | 1,319 |
| google_play | 820 | 802 | 5 | **0** |
| paypal_eu | 1,891 | 1,851 | 2 | 1,891 |
| paypal_us | 2,166 | 2,109 | 1 | 2,166 |

`psp_reference` is null on every Google Play row — the only provider with no identifier at all. Raised as [`action_items.md`](action_items.md) A5.

### 2. Status and operation vocabularies are small and clean

| status | operation | rows |
| --- | --- | ---: |
| settled | SALE | 7,250 |
| declined | SALE | 562 |
| settled | REFUND | 173 |
| settled | CHARGEBACK | 2 |
| pending | SALE | **1** |

Five combinations, no others. A refund or chargeback is never anything but `settled`; a decline is never anything but a `SALE`. The single `pending` row is ORD-507786, the lost capture raised as [`action_items.md`](action_items.md) A2.

Nulls: none anywhere except `psp_reference` (820, all Google Play) and `captured_at_utc` (563 — the 562 declines plus that one pending row). Every declined attempt correctly carries no capture time.

### 3. Decline and reversal rates — Google Play is the outlier

| psp | declines | rate | refunds | chargebacks |
| --- | ---: | ---: | ---: | ---: |
| adyen | 136 | 7.59% | 35 | **2** |
| dlocal | 111 | 8.42% | 23 | 0 |
| paypal_eu | 147 | 7.77% | 40 | 0 |
| paypal_us | 168 | 7.76% | 57 | 0 |
| google_play | **0** | **0.00%** | 18 | 0 |

Four providers cluster at 7.6–8.4% declines. Google Play has none, because the backend does not initiate those purchases — it writes its row from Google's notification. The engine log is a copy of the provider feed there rather than an independent record, which is what makes Google Play's clean tie weaker evidence than it looks.

Chargebacks exist only for Adyen. PayPal has zero across both accounts and the whole window — yet the PayPal EU export contains one. That gap is [`action_items.md`](action_items.md) A3.

### 4. FX arithmetic is internally consistent; the inputs are not always right

`amount_usd = round(amount_local × fx_rate_applied, 2)` holds on **all 7,988 rows**. The multiplication is never the problem — the rate fed into it is.

- USD rows carry rate exactly 1 on all 2,841. No exceptions.
- **Three non-USD rows also carry rate exactly 1** — TXN-107963/107964/107965, all dLocal. $200,679.44 mis-booked. This is the report's headline defect.
- `fx_date_applied` is the transaction date on 3,642 of 5,147 foreign-currency rows and an earlier date on 1,505 — never later. That is the as-of rule (`fx_rates` publishes business days only), not staleness. Two of those 1,505 are genuinely stale: [`action_items.md`](action_items.md) R2.

`captured_at_utc < created_at_utc` on zero rows.

### 5. Sequence gaps — four, all resolved

`txn_id` runs 100001–107991 with three missing: **107981, 107985, 107988**.
`order_id` runs 500001–507814 with one missing: **507811**.

A missing `txn_id` with no matching `order_id` gap is the signature of an unbooked operation on an existing order. That holds: 107981 and 107985 are the two PayPal EU reversals absent from the backend, and 107988 / 507811 pair up as the two orders the providers have and the backend does not (Adyen ORD-507811, dLocal ORD-507812). All four are classified in the reconciliation.

### 6. Dimensions

Currencies: EUR 2,914 · USD 2,841 · BRL 725 · GBP 708 · MXN 403 · CLP 154 · COP 131 · ARS 112. Three currencies (EUR, USD, GBP) appear under more than one provider, so currency never identifies the provider.

SKUs: `sub_monthly` 4,476 · `sub_quarterly` 1,567 · `sub_annual` 1,166 · `coach_addon` 779. Four values, no nulls, no free text — safe as a join component for Google Play's timestamp key.
