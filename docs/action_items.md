# Action items — June 2026 reconciliation

Everything the reconciliation surfaced that needs someone outside this pipeline to act. Ordered by dollars at risk. Evidence for each sits in the profiling docs, one per input file.

## Payment backend (engineering)

**A1 — FX conversion silently skipped. $200,679.50 in one month.** `HIGH`
Three dLocal transactions were written with `fx_rate_applied = 1.000000` on non-USD currency: COP 199,900 booked as $199,900. TXN-107963 / 107964 / 107965, all June. dLocal reports the correct figure on all three, so nothing is missing — but the backend is the internal source of truth and it was wrong by 150% of its own June total. The rate lookup can fail open and nothing catches it.
*Ask: reject the transaction rather than default the rate to 1.0, and alert on any non-USD row where the applied rate is exactly 1.*

**A2 — A settled capture never reached the backend. $24.99.** `HIGH`
ORD-507786 / TXN-107960 is `pending` with an empty `captured_at_utc`. PayPal reports the payment `Completed` at 2026-06-12 14:25 UTC and charged its $1.36 fee. Money moved; the backend never learned. One row this month, but the failure mode is silent revenue loss and there is nothing to bound how often it happens.
*Ask: reconcile pending captures against the provider on a rolling basis, not monthly.*

**A3 — Reversals not being ingested. $157.14, and probably a missing path.** `HIGH`
Three reversals exist at the provider with no backend row at all: ORD-507788 chargeback (€59.99), ORD-507806 refund (€24.99), ORD-507808 Adyen chargeback ($64.79). The sales are all present and correct. Two gaps in the `txn_id` sequence sit exactly where the PayPal reversals would be, which is the signature of an operation that failed to write.
Related and unquantifiable: **the backend has never recorded a single PayPal chargeback**, either account, any month in this extract. Adyen has 2, PayPal has 0 — yet ORD-507788 proves at least one occurred. Whether that is a real absence or a missing ingestion path cannot be told from the data.
*Ask: confirm the PayPal chargeback webhook is subscribed and wired.*

**A4 — Refund amount under-booked. $7.36.** `MEDIUM`
ORD-507807: dLocal refunded BRL 99.95, exactly 50% of the sale. The backend booked BRL 59.97, exactly 30%. Both figures are too clean to be a rounding fault — this reads as the wrong tier applied, not a corruption.

**A5 — Google Play transactions carry no provider reference at all.** `MEDIUM`
`psp_reference` is null on all 820 Google Play rows — the only provider with no identifier. This month's reconciliation works because the capture timestamp happens to be an exact key on 820 of 820 rows, but that is a property of the data, not a designed identifier. Two purchases in the same second with the same SKU and country would be unresolvable.
*Ask: persist Google's purchase token or order id.*

## Finance / commercial

**F1 — Retrieve the dLocal and PayPal contracts. Unlocks $4,591.52/month.** `HIGH`
`fee_schedule.csv` holds Adyen and Google Play only. dLocal (4.5% flat) and PayPal (3.49% + $0.49 US, 2.90% + €0.35 / £0.30 EU) charge consistently and plausibly on every settled sale, and are booked as charged — but nothing independent confirms the rates. This is 59% of June's fee spend that cannot be checked. Single highest-value item in the report.
PayPal needs **one schedule row per currency** — the fixed fee is denominated in whatever the customer paid, and the current file shape cannot express that.

**F2 — Recover $9.00 from Google Play.** `MEDIUM`
Six transactions billed at 30% against a contracted 15%, all on 2026-06-17 between 02:21 and 07:30 LA, all US / USD / `sub_monthly` / $9.99. Charges either side of that window are billed correctly. Small money, but a four-hour rate excursion is worth an explanation — if it recurs unnoticed it scales.

**F3 — Ask dLocal about $68.69 of fees on transactions where no money moved.** `MEDIUM`
4.5% charged on 109 declined attempts and one disputed transaction. The export gives no way to tell whether dLocal actually bills these or merely reports them. Settled by the same contract retrieval as F1.

**F4 — No fee is returned on any reversal. $2,121.17 reversed in June.** `LOW`
All five providers keep the original processing fee when a sale is refunded or charged back. This is a real cost that stays with us and no contract we hold states it. A renegotiation item, not a reconciliation break.

**F5 — Two Adyen fees over contract by $1.72.** `LOW`
Immaterial. Listed for completeness — where we hold a contract, the provider is essentially right.

## Provider data quality

**P1 — dLocal omitted a settled sale from its export. $7.42.** `MEDIUM`
The backend has ORD-507812, CLP 6,990, `psp_reference` DL-90001317. dLocal transaction ids run dense from 90000001 to 90001319 across both sides and DL-90001317 is the *only* id missing from the export — so the id was minted and the transaction is real. This reads as an export omission, not a backend invention, but dLocal has to confirm it.

**P2 — dLocal holds a transaction in mediation the backend calls settled. $6.45.** `LOW`
ORD-507787, BRL 34.90. Treated as unsettled here because disputed money is not confirmed ours. dLocal charged its 4.5% on it regardless. Needs an outcome.

**P3 — Two providers exported duplicate lines. $17.12.** `LOW`
dLocal DL-90001316 / ORD-507810 and PayPal ORD-507809 each appear twice, byte-identical, on adjacent lines. The backend has one row and is right in both cases. Deduplicated in staging, kept in the discrepancy report so each provider's own total ties.

**P4 — PayPal EU ships three rows in the wrong date format.** `LOW`
ORD-507782 / 507783 / 507784 are `MM/DD/YYYY` inside a `DD/MM/YYYY` file. Handled by re-parsing any row that falls outside the export's declared window, and a test pins it to exactly those three. If PayPal ever fixes this the build fails rather than quietly moving money between months — that is intentional, but someone has to know to update it.

**P5 — A refund precedes its own sale.** `LOW`
ORD-506947: refund at 12:56, sale at 16:13 the same day. Both dLocal and the backend record it identically, so it is a provider sequencing oddity rather than a log defect. Outside June.

## Reference data

**R1 — `fx_rates.csv` published BRL 2026-06-10 twice.** `LOW`
0.185352, then 0.190542 two days later. The correction is treated as authoritative — dLocal priced every BRL transaction that day at the corrected rate and so did the backend, on 23 of 24. But the file has no version column, so the only way to tell a correction from a duplicate is to look at which one everyone used.
*Ask: publish a version or effective-from timestamp on republished rates.*

**R2 — Two transactions priced against the wrong day's rate. $0.59.** `LOW`
TXN-107950 (PayPal EU, 14 days stale) and TXN-107951 (Adyen, 1 day). Immaterial in dollars, and the backend follows the as-of rule on 5,145 of 5,147 foreign-currency rows — but it is the same lookup that fails wide open in A1.
