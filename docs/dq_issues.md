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

3. fx_rates.csv has a duplicate key. BRL / 2026-06-10 appears twice: 0.185352 (published 06-10) and 0.190542 (published 06-12). The second is a correction, not an as-of rate — dLocal priced every BRL transaction that day at 0.190542, and so did the engine for 23 of the 24. TXN-107952 is the one left on the superseded rate, understated by $0.47. Resolved in `stg__fx_rates`: versions are ranked and consumers pin `is_current_rate`, which also stops the join fanning out.

4. One refund precedes its sale. TXN-107929 (dlocal, ORD-506947) refunds at 12:56 for a sale created 16:13 the same day, 2026-07-03. Outside June, so it's a warn, not a blocker — but it answers your DQ question: yes, it happens.

5. minor: sign convention is not in the data. Refunds and chargebacks are stored positive (min(amount_usd) = 1.55 for refunds). Staging must derive the signed amount or every downstream sum will be wrong.

6. minor: 3 gaps in the txn_id sequence (107981, 107985, 107988) and one in order_id (507811). Possible "provider has it, engine doesn't" leads — not an engine-log defect.