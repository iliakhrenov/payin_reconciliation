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

**The unit of reconciliation is provider × order reference × operation.** Not the transaction id — for Adyen the engine issues its own reference for every refund and chargeback while the provider reuses the original sale's, so a PSP-reference join loses them. (dLocal is the opposite: it mints a fresh id per refund and the engine records it, so the reference happens to hold there.) Order reference plus operation is the only key every provider agrees on. A full outer join on it is 1:1 for Adyen, and a test fails the build if any provider breaks that.

**A transaction belongs to the period it was recognised in, and settlement is recognition.** Where a provider settles, its settlement time decides the period; otherwise the attempt does. So a sale the backend captures on 28 June and Adyen settles on 2 July counts in June on one side and July on the other. That is a real month-end difference, not a matching failure, and it is reported as one rather than netted away.

**A declined attempt is worth zero dollars.** Both sides carry the attempted amount, but only money that moved is reconciled. This is what turns "the engine booked a sale the provider refused" into its full value instead of nothing.

**Both sides are valued at the same published rate.** Providers report local amounts; USD comes from the last rate published on or before the transaction date — the same as-of rule the engine is held to. A matched row therefore shows no FX noise, and where the engine priced against the wrong day the difference surfaces in dollars instead of disappearing.

**The cause name says who is making the claim.** `psp_claims_*` is the provider asserting something the backend does not; `engine_claims_*` is the backend asserting something the provider does not; `engine_fx_*` is the backend's own booking at fault. Reading a summary, the prefix alone says which side to go and ask — which is why a cause names the claimant, not our verdict. `psp_claims_different_amount` covers a refund we believe the backend under-booked, because the provider is still the party that moved the money.

**Fees are a third reconciliation, not part of the second.** The backend records no fees, so a fee variance is the provider against the contract, not the provider against the backend. They share a grain, so they share a row and a summary — but they never net against each other, because the counterparties are different and adding them would imply the backend had a fee opinion to disagree with.

**Only settled sales are fee-reconciled.** Providers return no fee when a sale is refunded or charged back, and no contract on file says they should. The fee on a reversed sale is a real cost that stays with us; it is a commercial term to renegotiate, not a reconciliation break.

**A fee the provider reports is a fee we paid, contract or no contract.** `fee_schedule` is our record of what was agreed, not evidence of what was charged — and a provider processing 1,150 transactions for nothing is not a credible reading. So where a settled sale carries a provider fee we hold no contract for, the whole charge is booked against us as `psp_claims_fee_out_of_contract`. The gap is in our contract file, not in the charge. A settled sale with no contract *and* no fee stays `fee_not_contracted` at zero dollars, still visible as a row count.

**Negative always means the same thing.** In both scopes the signed figure is the impact on net USD receipts: negative means the backend's books overstate what we actually keep. Gross and fees can therefore be added for a total, even though they are measured against different counterparties.

**The reconciliation is a waterfall, not three separate exercises.** What the backend booked, plus its own bugs, plus the provider variance, equals what the provider says it took — then fees carry that down to net. Each section hands a clean number to the next, which is why FX faults are settled in the first one: a gross comparison is only meaningful once both sides believe the same rate. A test fails the build if the identity stops holding.

## dLocal

**`local_amount` is minor units, scaled by the row's own `currency_exponent`.** CLP carries exponent 0 and the other four currencies carry 2, so a blanket ÷100 is wrong in both directions. Scaled per row, 1,318 of 1,319 rows tie to the engine's local amount exactly — the engine adjudicates the rule.

**`IN_MEDIATION` is not settlement.** dLocal has one such row (`ORD-507787`, BRL 34.90) where the engine says settled. Mediation means the money is disputed and not confirmed ours, and only money that moved is reconciled — so it is treated as unsettled and reported as a $6.45 discrepancy rather than matched. dLocal charges its 4.5% on it regardless.

**The duplicated export line is a defect, not a second payment.** `DL-90001316` / `ORD-507810` appears twice, byte-identical, on adjacent lines. Staging deduplicates on the full row. Kept in the discrepancy report at +$7.13 so the provider's own total is explained rather than silently corrected.

**dLocal's `usd_amount` is a cross-check, not an input.** Its `fx_rate` is inverted (local per USD) and its USD column is internally consistent with it on 1,317 of 1,319 rows. Both sides are re-priced at the published as-of rate regardless, so the two cent-level exceptions carry no weight.

**`ORD-507781` is priced on its creation date, and we accept the cent.** The sale is created 2026-05-31 23:59:50 and settles 2026-06-01 00:05. Both dLocal and the engine use the 29 May rate; dLocal's export publishes only the settlement timestamp, so pricing the provider side off its own file gives the 1 June rate and a $0.01 break. Importing the engine's timestamp into a provider staging model would destroy the independence of the two sides for one cent, so the cent is named and classified instead of engineered away.

**dLocal's reported fee is authoritative; `fee_schedule` is incomplete.** The effective rate is exactly 4.5% on every row and `fee_schedule` has no dLocal entry at all. We treat the export as the record of what was charged and the contract file as the thing with the gap, so June's 1,150 settled sales carry $682.56 as `psp_claims_fee_out_of_contract` rather than $0.00 as unverifiable. This is the one place the reconciliation books a number the backend has no opinion on — Finance should retrieve the dLocal contract and confirm the 4.5%.

**Only settled sales carry that charge, and the rest is flagged instead.** dLocal also reports a 4.5% fee on 109 rejected attempts ($68.40) and on the disputed row ($0.29). No money moved on those, and the export gives no way to tell whether dLocal actually bills them. $68.69 is reported as a caveat rather than classified — booking it would assert a billing behaviour we cannot evidence, and it is the same contract retrieval that settles it.
