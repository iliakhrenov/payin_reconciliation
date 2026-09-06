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
