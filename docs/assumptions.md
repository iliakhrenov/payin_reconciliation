# Assumptions

Calls made where the data is ambiguous. Each one is enforced in code and tested.

## FX

**The engine prices at the last published business day, not the transaction date.**
`fx_rates` publishes business days only (and skips 2026-06-19). The engine applies the most
recent rate on or before the transaction date — true for 5,145 of 5,147 foreign-currency rows.
That rule, not the transaction date, is the baseline the two exceptions are measured against.

**A republished rate supersedes the original; it is not a second as-of rate.**
BRL 2026-06-10 was published twice — 0.185352, then 0.190542 two days later. dLocal priced
every BRL transaction that day at the corrected rate, and so did the engine for 23 of 24. So
the correction is authoritative and the original is simply wrong. `stg__fx_rates` ranks
versions and consumers pin `is_current_rate`.

**Every row is priced at the as-of rate, including the ones with the wrong date.**
The reconciliation needs one pricing basis or the two sides are not comparable, so
`amount_usd_recon` is the local amount at the rate published for the as-of date — no carve-outs.
For the four rows where the rate itself was wrong the correction is evidenced, not inferred:
dLocal independently reports the restated figure. For the two priced against the wrong day the
engine adjudicates itself — it follows the as-of rule on 5,145 of 5,147 foreign-currency rows,
so its own dominant behaviour convicts the deviants. We do not need the provider to arbitrate.

**Corrections never overwrite.** `amount_usd_engine` is the backend's claim and is preserved
untouched; `amount_usd_recon` is the restated figure. The difference is the FX share of the
discrepancy — the number the reconciliation exists to report — so it has to stay visible.

## Reconciliation

**The unit of reconciliation is provider × order reference × operation.** Not the transaction id — the engine issues its own id for every refund and chargeback while providers reuse the original sale's reference, so a PSP-reference join loses them. Order reference plus operation is the only key both sides agree on. A full outer join on it is 1:1 for Adyen, and a test fails the build if any provider breaks that.

**A transaction belongs to the period it was recognised in, and settlement is recognition.** Where a provider settles, its settlement time decides the period; otherwise the attempt does. So a sale the backend captures on 28 June and Adyen settles on 2 July counts in June on one side and July on the other. That is a real month-end difference, not a matching failure, and it is reported as one rather than netted away.

**A declined attempt is worth zero dollars.** Both sides carry the attempted amount, but only money that moved is reconciled. This is what turns "the engine booked a sale the provider refused" into its full value instead of nothing.

**Both sides are valued at the same published rate.** Providers report local amounts; USD comes from the last rate published on or before the transaction date — the same as-of rule the engine is held to. A matched row therefore shows no FX noise, and where the engine priced against the wrong day the difference surfaces in dollars instead of disappearing.

**The cause name says who is making the claim.** `psp_claims_*` is the provider asserting something the backend does not. `engine_*` is the backend's own booking at fault. Reading a summary, the prefix alone says which side to go and ask.

**Fees are a third reconciliation, not part of the second.** The backend records no fees, so a fee variance is the provider against the contract, not the provider against the backend. They share a grain, so they share a row and a summary — but they never net against each other, because the counterparties are different and adding them would imply the backend had a fee opinion to disagree with.

**Only settled sales are fee-reconciled.** Providers return no fee when a sale is refunded or charged back, and no contract on file says they should. The fee on a reversed sale is a real cost that stays with us; it is a commercial term to renegotiate, not a reconciliation break.

**No contract on file means unverifiable, not compliant.** A settled sale whose provider and account are absent from `fee_schedule` is carried as `fee_not_contracted` at zero dollars. It shows as a row count so the gap in coverage is visible, rather than silently joining the matched pile.

**Negative always means the same thing.** In both scopes the signed figure is the impact on net USD receipts: negative means the backend's books overstate what we actually keep. Gross and fees can therefore be added for a total, even though they are measured against different counterparties.

**The reconciliation is a waterfall, not three separate exercises.** What the backend booked, plus its own bugs, plus the provider variance, equals what the provider says it took — then fees carry that down to net. Each section hands a clean number to the next, which is why FX faults are settled in the first one: a gross comparison is only meaningful once both sides believe the same rate. A test fails the build if the identity stops holding.
