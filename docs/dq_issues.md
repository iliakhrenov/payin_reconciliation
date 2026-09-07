# Data quality — working log

Findings in the order they were discovered, with the evidence that settled each one. Items opened here are closed here (item 5 is closed inside item 9), so this reads as a trail, not a register.

**For the register — what needs acting on, by whom, ranked by dollars — see [`action_items.md`](action_items.md).** This file is why we believe each item; that one is what to do about it.

---

1. stale fx rates
The 2 exceptions are real anomalies worth carrying into the reconciliation:

┌────────────┬───────────┬────────────┬────────────┬──────────┬────────────┐
│    txn     │    psp    │  applied   │ should be  │ stale by │ USD impact │
├────────────┼───────────┼────────────┼────────────┼──────────┼────────────┤
│ TXN-107950 │ paypal_eu │ 2026-06-02 │ 2026-06-16 │ 14 days  │ +0.56      │
├────────────┼───────────┼────────────┼────────────┼──────────┼────────────┤
│ TXN-107951 │ adyen     │ 2026-06-10 │ 2026-06-11 │ 1 day    │ −0.03      │
└────────────┴───────────┴────────────┴────────────┴──────────┴────────────┘

2. Three dLocal rows have fx_rate_applied = 1.000000 on non-USD currency — FX simply not applied. Local amount booked straight as USD:

┌────────────┬─────┬────────────┬────────────┬─────────────┬─────────────┐
│    txn     │ ccy │   local    │ booked USD │ correct USD │ overstated  │
├────────────┼─────┼────────────┼────────────┼─────────────┼─────────────┤
│ TXN-107965 │ COP │ 199,900.00 │ 199,900.00 │ 48.78       │ +199,851.22 │
├────────────┼─────┼────────────┼────────────┼─────────────┼─────────────┤
│ TXN-107964 │ MXN │ 799.00     │ 799.00     │ 44.08       │ +754.92     │
├────────────┼─────┼────────────┼────────────┼─────────────┼─────────────┤
│ TXN-107963 │ BRL │ 89.90      │ 89.90      │ 16.60       │ +73.30      │
└────────────┴─────┴────────────┴────────────┴─────────────┴─────────────┘

3. One refund precedes its sale. TXN-107929 (dlocal, ORD-506947) refunds at 12:56 for a sale created 16:13 the same day, 2026-07-03. Outside June, so it's a warn, not a blocker — but it answers your DQ question: yes, it happens.

4. minor: sign convention is not in the data. Refunds and chargebacks are stored positive (min(amount_usd) = 1.55 for refunds). Staging must derive the signed amount or every downstream sum will be wrong.

5. minor: 3 gaps in the txn_id sequence (107981, 107985, 107988) and one in order_id (507811). Possible "provider has it, engine doesn't" leads — not an engine-log defect.
6. Adyen emits two rows per transaction (Authorised + Settled). That's the next fan-out trap, and it'll need a record-type filter before the join.

7. dLocal profiling closed out items 1–3 and added one engine defect:

- **item 3 is not an engine bug.** dLocal's export carries the same refund-before-sale sequence for ORD-506947 — refund 2026-07-03 12:56, sale 17:55 — identically to the engine. Both systems agree, so it is a provider sequencing oddity, not a log defect. Still outside June.
- **items 1–2 are all dLocal rows.** TXN-107952/107963/107964/107965 overstate June dLocal by $200,678.97 combined, 99.6% of it TXN-107965. dLocal independently reports the corrected figure on every one, so the correction is evidenced.
- **new: ORD-507807 refund is under-booked.** The engine books BRL 59.97 against dLocal's BRL 99.95 — exactly 30% of the sale where dLocal refunded 50%. dLocal moved the money; the engine understates the refund by BRL 39.98 ($7.36).
- **unresolved, likely provider-side: ORD-507812.** Engine has a settled CLP 6,990 sale ($7.42) with psp_reference DL-90001317. dLocal transaction ids run dense 90000001–90001319 across both sides and DL-90001317 is the only id missing from the export, so the id was minted — this reads as an export omission, not an engine invention. Needs dLocal to confirm.


8. Google Play profiling — no engine defects found, two structural gaps worth naming:

- **`psp_reference` is null on all 820 Google Play rows.** The only PSP with no provider reference at all. The reconciliation works because `captured_at_utc` happens to be an exact key (820/820), but that is a coincidence of the data, not a designed identifier — two purchases at the same second with the same SKU and country would be unresolvable. The engine should persist Google's purchase token or order id.
- **The engine records no declined Google Play attempts and no chargebacks.** Every other PSP runs 7–8% declines. The backend is not initiating these purchases; it is ingesting Google's notifications, so the engine log is a copy of the provider feed rather than an independent record. The June tie of $0.00 should be read accordingly.

Provider-side finding, needs Google: **six transactions billed at 30% against a contracted 15%**, all on 2026-06-17 between 02:21 and 07:30 LA, all US / USD / `sub_monthly` / $9.99, fee $3.00 where $1.50 was due. $9.00 overcharge. Charges either side of the window are billed correctly.

9. PayPal profiling — one engine defect, two unbooked reversals, one provider artefact:

- **new: `ORD-507786` capture never recorded.** `TXN-107960` (paypal_us) is `pending` with `captured_at_utc` empty. PayPal reports the $24.99 payment `Completed` at 2026-06-12 14:25 UTC and charged its $1.36 fee. Money moved, engine never learned. June understated by $24.99.
- **new: two PayPal EU reversals absent from the engine.** `ORD-507788` chargeback (€59.99, 20 June) and `ORD-507806` refund (€24.99, 25 June). Both sales are in the engine and correct; the reversals have no engine row at all. Engine overstates June net revenue by €84.98 ($92.35). This is also the answer to item 5's remaining gaps: `TXN-107981` sits directly after `ORD-507806`'s sale and `TXN-107985` is the only other unaccounted gap — two missing ids, no matching `order_id` gap, which is the signature of an unbooked operation on an existing order. Item 5 is now closed: 107988 / `ORD-507811` is dLocal's `ORD-507812` case, 107981 and 107985 are these.
- **item 1 confirmed and bounded on PayPal.** `TXN-107950` is the only PayPal FX defect: €59.99 priced at the 2 June rate on a 16 June transaction, $65.75 booked vs $65.19, +$0.56.
- **provider-side, no action on the engine: `ORD-507809` is exported twice** by PayPal US — a byte-identical duplicate line. The engine has one row and is right.

Also worth naming, not a defect: **the engine records no PayPal chargebacks at all**, and never has an `operation_type = 'CHARGEBACK'` row for either PayPal account. Adyen has 2. Whether that is a real absence or a missing ingestion path is unknown from the data — `ORD-507788` shows at least one occurred.
